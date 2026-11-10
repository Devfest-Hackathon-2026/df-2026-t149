package store

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// stores はメモリの版と、FIRESTORE_EMULATOR_HOST があるときの Firestore の版で同じ動きを確かめる。
func stores(t *testing.T) map[string]Store {
	t.Helper()
	out := map[string]Store{"memory": NewMemoryStore()}
	if os.Getenv("FIRESTORE_EMULATOR_HOST") != "" {
		client, err := firestore.NewClient(context.Background(), "uramichi-test")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = client.Close() })
		out["firestore"] = NewFirestoreStore(client)
	}
	return out
}

// 同じエミュレーターに残ったデータと混ざらないよう、実行ごとに値を変える。
func unique(t *testing.T, prefix string) string {
	t.Helper()
	return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
}

func TestResentLogReturnsSavedRecord(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			uid, place := unique(t, "u"), unique(t, "p")
			at := time.Date(2026, 11, 5, 1, 2, 3, 0, time.UTC)
			if _, _, err := st.CheckIn(ctx, uid, place, at, ""); err != nil {
				t.Fatal(err)
			}
			first, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "hit", Comment: "一回目", CreatedAt: at, ClientID: "c1"})
			if err != nil {
				t.Fatal(err)
			}
			again, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "hit", Comment: "二回目", CreatedAt: at.Add(time.Hour), ClientID: "c1"})
			if err != nil {
				t.Fatal(err)
			}
			if again.ID != first.ID || again.Comment != "一回目" || !again.CreatedAt.Equal(at) {
				t.Errorf("保存済みの記録を返していない: %+v", again)
			}
			logs, err := st.ListLogs(ctx, uid)
			if err != nil || len(logs) != 1 {
				t.Errorf("logs = %+v, err = %v", logs, err)
			}
		})
	}
}

func TestTakeCallStopsAtLimitEvenWhenConcurrent(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			date := unique(t, "d")
			var taken atomic.Int32
			var wg sync.WaitGroup
			for range 8 {
				wg.Add(1)
				go func() {
					defer wg.Done()
					ok, err := st.TakeCall(ctx, date, "nearby.explore", "", 5, 0)
					if err != nil {
						t.Error(err)
					}
					if ok {
						taken.Add(1)
					}
				}()
			}
			wg.Wait()
			if taken.Load() != 5 {
				t.Errorf("上限 5 のところ %d 回通した", taken.Load())
			}
			// 種類が違っても、合計で上限を判定する
			if ok, err := st.TakeCall(ctx, date, "text.alternatives", "", 5, 0); ok || err != nil {
				t.Errorf("上限を超えた: %v %v", ok, err)
			}
			if ok, err := st.TakeCall(ctx, date, "text.alternatives", "", 6, 0); !ok || err != nil {
				t.Errorf("上限の内なのに断った: %v %v", ok, err)
			}
		})
	}
}

func TestTimelineAndVerdictCounts(t *testing.T) {
	ctx := context.Background()
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			place, uid, geo := unique(t, "place"), unique(t, "uid"), unique(t, "g")
			if _, _, err := st.CheckIn(ctx, uid, place, time.Now(), geo); err != nil {
				t.Fatal(err)
			}
			l, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "miss", CreatedAt: time.Now(), Public: true, ClientID: "t1"})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "miss", CreatedAt: time.Now(), Public: true, ClientID: "t1"}); err != nil {
				t.Fatal(err)
			}
			counts, err := st.VerdictCounts(ctx, []string{place, unique(t, "none")})
			if err != nil || len(counts) != 1 || counts[place].Misses != 1 || counts[place].Hits != 0 {
				t.Errorf("集計: %v %v", counts, err)
			}
			entries, err := st.Timeline(ctx, []string{geo}, 10)
			if err != nil || len(entries) != 1 || entries[0].PlaceID != place {
				t.Fatalf("公開: %v %v", entries, err)
			}
			reporterBase := unique(t, "r")
			for i := range HiddenAtReports - 1 {
				if err := st.ReportEntry(ctx, reporterBase+string(rune('a'+i)), entries[0].ID, Report{Reason: ReportSpam}); err != nil {
					t.Fatal(err)
				}
			}
			if got, _ := st.Timeline(ctx, []string{geo}, 10); len(got) != 1 {
				t.Errorf("報告が足りないうちは消さない: %v", got)
			}
			// 報告した人だけが分かる
			reporter := reporterBase + "a"
			if mine, err := st.MyReports(ctx, reporter, []string{entries[0].ID, "nope"}); err != nil || !mine[entries[0].ID] || len(mine) != 1 {
				t.Errorf("自分の報告: %v %v", mine, err)
			}
			if mine, _ := st.MyReports(ctx, uid, []string{entries[0].ID}); len(mine) != 0 {
				t.Errorf("報告していない人: %v", mine)
			}
			if _, err := st.UpdateLog(ctx, uid, l.ID, LogUpdate{Public: ptr(false)}); err != nil {
				t.Fatal(err)
			}
			if got, _ := st.Timeline(ctx, []string{geo}, 10); len(got) != 0 {
				t.Errorf("非公開: %v", got)
			}
			saved, err := st.UpdateLog(ctx, uid, l.ID, LogUpdate{Public: ptr(true)})
			if err != nil || !saved.Public || saved.Geo != geo {
				t.Errorf("再公開: %+v %v", saved, err)
			}
			got, _ := st.Timeline(ctx, []string{geo}, 10)
			if len(got) != 1 || got[0].Reports != HiddenAtReports-1 {
				t.Fatalf("公開し直しても報告の数を残す: %+v", got)
			}
			// 公開し直した後の1回で、隠す数に達する
			if err := st.ReportEntry(ctx, unique(t, "r-last"), got[0].ID, Report{Reason: ReportOther}); err != nil {
				t.Fatal(err)
			}
			if got, _ := st.Timeline(ctx, []string{geo}, 10); len(got) != 0 {
				t.Errorf("報告が溜まった記録が出ている: %+v", got)
			}
			if _, err := st.UpdateLog(ctx, unique(t, "other"), l.ID, LogUpdate{Public: ptr(true)}); !errors.Is(err, ErrLogNotFound) {
				t.Errorf("他人の記録: %v", err)
			}
			if err := st.ReportEntry(ctx, uid, "nope", Report{}); !errors.Is(err, ErrEntryNotFound) {
				t.Errorf("ない記録: %v", err)
			}
		})
	}
}

func TestVerdictCountsOneVotePerUser(t *testing.T) {
	ctx := context.Background()
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			place, uid := unique(t, "place"), unique(t, "uid")
			if _, _, err := st.CheckIn(ctx, uid, place, time.Now(), ""); err != nil {
				t.Fatal(err)
			}
			add := func(verdict, clientID string) {
				t.Helper()
				if _, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: verdict, CreatedAt: time.Now(), ClientID: clientID}); err != nil {
					t.Fatal(err)
				}
			}
			add("hit", "v1")
			add("hit", "v2")
			counts, err := st.VerdictCounts(ctx, []string{place})
			if err != nil || counts[place] != (VerdictCount{Hits: 1}) {
				t.Errorf("同じ評価を重ねても1票: %v %v", counts, err)
			}
			add("miss", "v3")
			counts, err = st.VerdictCounts(ctx, []string{place})
			if err != nil || counts[place] != (VerdictCount{Misses: 1}) {
				t.Errorf("別の評価で票を入れ替える: %v %v", counts, err)
			}
		})
	}
}

func TestCheckinOrder(t *testing.T) {
	ctx := context.Background()
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			place, uid := unique(t, "place"), unique(t, "uid")
			if _, ok, err := st.CheckinOrder(ctx, uid, place); ok || err != nil {
				t.Fatalf("チェックイン前: %v %v", ok, err)
			}
			if _, _, err := st.CheckIn(ctx, uid, place, time.Now(), ""); err != nil {
				t.Fatal(err)
			}
			if order, ok, err := st.CheckinOrder(ctx, uid, place); order != 1 || !ok || err != nil {
				t.Errorf("チェックイン後: %d %v %v", order, ok, err)
			}
		})
	}
}

func TestTakeCallKeepsDetailsLimitSeparateFromSearch(t *testing.T) {
	ctx := context.Background()
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			date := unique(t, "date")
			if ok, err := st.TakeCall(ctx, date, "nearby.explore", "", 1, 0); !ok || err != nil {
				t.Fatalf("%v %v", ok, err)
			}
			if ok, err := st.TakeCall(ctx, date, "text.alternatives", "", 1, 0); ok || err != nil {
				t.Errorf("検索の2種類は上限を共有する: %v %v", ok, err)
			}
			if ok, err := st.TakeCall(ctx, date, "detailsName.logs", "", 1, 0); !ok || err != nil {
				t.Errorf("名前の取得は別の上限: %v %v", ok, err)
			}
			if ok, err := st.TakeCall(ctx, date, "detailsLocation.checkin", "", 1, 0); !ok || err != nil {
				t.Errorf("位置の確認は別の上限: %v %v", ok, err)
			}
		})
	}
}

func TestDaysReturnsRecordedDaysOnly(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			date, empty := unique(t, "d"), unique(t, "none")
			if _, err := st.TakeCall(ctx, date, "nearby.explore", "", 10, 0); err != nil {
				t.Fatal(err)
			}
			for range 2 {
				if err := st.AddSimulated(ctx, date, "nearby.checkin"); err != nil {
					t.Fatal(err)
				}
			}
			days, err := st.Days(ctx, []string{empty, date})
			if err != nil || len(days) != 1 {
				t.Fatalf("days = %+v, err = %v", days, err)
			}
			d := days[0]
			if d.Date != date || d.Real["nearby.explore"] != 1 || d.Simulated["nearby.checkin"] != 2 {
				t.Errorf("day = %+v", d)
			}
		})
	}
}

func TestTakeCallStopsEachUserAtUserLimit(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			date := unique(t, "d")
			take := func(uid string) bool {
				t.Helper()
				ok, err := st.TakeCall(ctx, date, "nearby.explore", uid, 10, 2)
				if err != nil {
					t.Fatal(err)
				}
				return ok
			}
			if !take("alice") || !take("alice") {
				t.Fatal("上限の内なのに断った")
			}
			if take("alice") {
				t.Error("1人あたりの上限を超えた")
			}
			if !take("bob") {
				t.Error("別の利用者まで止めた")
			}
			// 断った呼び出しは全体の回数に含めない
			days, err := st.Days(ctx, []string{date})
			if err != nil || days[0].Real["nearby.explore"] != 3 {
				t.Errorf("days = %+v, err = %v", days, err)
			}
		})
	}
}

func TestProfilesAreLookedUpByAuthorTag(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			alice, bob := unique(t, "alice"), unique(t, "bob")
			if _, ok, err := st.Profile(ctx, alice); err != nil || ok {
				t.Fatalf("保存前: ok=%v err=%v", ok, err)
			}
			want := Profile{Nickname: "たろう", Icon: "hiker"}
			if err := st.SetProfile(ctx, alice, want); err != nil {
				t.Fatal(err)
			}
			if got, ok, err := st.Profile(ctx, alice); err != nil || !ok || got != want {
				t.Errorf("Profile = %+v %v %v", got, ok, err)
			}
			got, err := st.Profiles(ctx, []string{AuthorTag(alice), AuthorTag(bob), AuthorTag(alice)})
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != 1 || got[AuthorTag(alice)] != want {
				t.Errorf("Profiles = %+v", got)
			}
			if got, err := st.Profiles(ctx, nil); err != nil || len(got) != 0 {
				t.Errorf("空の指定: %+v %v", got, err)
			}
		})
	}
}

func TestAuthorTagsOfDifferentUsersDoNotCollide(t *testing.T) {
	seen := map[string]string{}
	for i := range 10000 {
		uid := fmt.Sprintf("user-%d", i)
		tag := AuthorTag(uid)
		if prev, ok := seen[tag]; ok {
			t.Fatalf("%s と %s が同じ符号 %s になった", prev, uid, tag)
		}
		seen[tag] = uid
	}
}

func TestRatingVotesReplaceSum(t *testing.T) {
	ctx := context.Background()
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			place := unique(t, "place")
			alice, bob := unique(t, "alice"), unique(t, "bob")
			for _, uid := range []string{alice, bob} {
				if _, _, err := st.CheckIn(ctx, uid, place, time.Now(), ""); err != nil {
					t.Fatal(err)
				}
			}
			add := func(uid string, rating int, clientID string) {
				t.Helper()
				l, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: VerdictOf(rating), Rating: rating, CreatedAt: time.Now(), ClientID: clientID})
				if err != nil || l.Rating != rating {
					t.Fatalf("%+v %v", l, err)
				}
			}
			add(alice, 5, "r1")
			add(bob, 2, "r2")
			counts, err := st.VerdictCounts(ctx, []string{place})
			if want := (VerdictCount{Hits: 1, Misses: 1, RatingSum: 7, RatingCount: 2}); err != nil || counts[place] != want {
				t.Errorf("2人の票: %+v %v", counts[place], err)
			}
			// 同じ人が★を付け直すと、票を入れ替える（当たりのまま★だけ変わることもある）
			add(alice, 3, "r3")
			counts, err = st.VerdictCounts(ctx, []string{place})
			if want := (VerdictCount{Hits: 1, Misses: 1, RatingSum: 5, RatingCount: 2}); err != nil || counts[place] != want {
				t.Errorf("付け直し: %+v %v", counts[place], err)
			}
			// ★評価のない古いアプリの記録は、★の数に入れない
			add(bob, 0, "r4")
			counts, err = st.VerdictCounts(ctx, []string{place})
			if want := (VerdictCount{Hits: 1, Misses: 1, RatingSum: 3, RatingCount: 1}); err != nil || counts[place] != want {
				t.Errorf("★評価なし: %+v %v", counts[place], err)
			}
			logs, err := st.ListLogs(ctx, alice)
			if err != nil || len(logs) != 2 || logs[0].Rating == 0 {
				t.Errorf("★評価を保存する: %+v %v", logs, err)
			}
		})
	}
}

func TestVerdictOf(t *testing.T) {
	for rating, want := range map[int]string{1: "miss", 2: "miss", 3: "hit", 4: "hit", 5: "hit"} {
		if got := VerdictOf(rating); got != want {
			t.Errorf("★%d: %s", rating, got)
		}
	}
}

func TestFavorites(t *testing.T) {
	ctx := context.Background()
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			uid, other := unique(t, "uid"), unique(t, "other")
			base := time.Date(2026, 11, 9, 10, 0, 0, 0, time.UTC)
			for i, id := range []string{"a", "b", "c"} {
				if err := st.AddFavorite(ctx, uid, id, base.Add(time.Duration(i)*time.Minute)); err != nil {
					t.Fatal(err)
				}
			}
			// 同じ場所をもう一度入れても増えず、日時も変えない
			if err := st.AddFavorite(ctx, uid, "a", base.Add(time.Hour)); err != nil {
				t.Fatal(err)
			}
			if err := st.RemoveFavorite(ctx, uid, "b"); err != nil {
				t.Fatal(err)
			}
			// 入っていない場所を外してもエラーにしない
			if err := st.RemoveFavorite(ctx, uid, "none"); err != nil {
				t.Fatal(err)
			}
			favs, err := st.Favorites(ctx, uid)
			if err != nil || len(favs) != 2 || favs[0].PlaceID != "c" || favs[1].PlaceID != "a" || !favs[1].CreatedAt.Equal(base) {
				t.Errorf("新しい順の c, a: %+v %v", favs, err)
			}
			// ほかの人のお気に入りは混ざらない
			if favs, err := st.Favorites(ctx, other); err != nil || len(favs) != 0 {
				t.Errorf("ほかの人: %+v %v", favs, err)
			}
		})
	}
}

func TestFavoritesLimit(t *testing.T) {
	ctx := context.Background()
	st := NewMemoryStore()
	for i := range MaxFavorites {
		if err := st.AddFavorite(ctx, "u", fmt.Sprintf("p%d", i), time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	if err := st.AddFavorite(ctx, "u", "over", time.Now()); !errors.Is(err, ErrTooManyFavorites) {
		t.Errorf("上限を超えたとき: %v", err)
	}
	// 入っている場所は、上限でも入れ直せる
	if err := st.AddFavorite(ctx, "u", "p0", time.Now()); err != nil {
		t.Errorf("入っている場所: %v", err)
	}
}

func TestAchievementDiff(t *testing.T) {
	d := achievementDiff(map[string]int{"a": 1, "b": 3}, map[string]int{"a": 3, "c": 1})
	if d["a"] != [MaxAchievementTier]int{0, 1, 1} || d["b"] != [MaxAchievementTier]int{-1, -1, -1} || d["c"] != [MaxAchievementTier]int{1, 0, 0} {
		t.Errorf("got %v", d)
	}
}

func TestSetAchievementsUpdatesStatsByDifference(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			// エミュレーターにほかの実行の集計が残っていても確かめられるよう、増えた分で比べる
			id := strings.ReplaceAll(strings.ToLower(unique(t, "a")), "-", "_")
			before, err := st.AchievementStats(ctx)
			if err != nil {
				t.Fatal(err)
			}
			alice, bob := unique(t, "alice"), unique(t, "bob")
			for _, step := range []struct {
				uid   string
				tiers map[string]int
			}{
				{alice, map[string]int{id: 1}},
				{bob, map[string]int{id: 2}},
				{alice, map[string]int{id: 3}},
				{alice, map[string]int{id: 3}}, // 同じ内容は数えない
			} {
				if err := st.SetAchievements(ctx, step.uid, step.tiers); err != nil {
					t.Fatal(err)
				}
			}
			after, err := st.AchievementStats(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if after.Users-before.Users != 2 {
				t.Errorf("利用者の数: %d → %d", before.Users, after.Users)
			}
			if got := after.Counts[id]; got != [MaxAchievementTier]int{2, 2, 1} {
				t.Errorf("段階ごとの人数: %v", got)
			}
		})
	}
}

func ptr[T any](v T) *T { return &v }

func TestUpdateLogChangesRatingVoteAndTimeline(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			uid, place := unique(t, "u"), unique(t, "p")
			at := time.Date(2026, 11, 5, 1, 2, 3, 0, time.UTC)
			if _, _, err := st.CheckIn(ctx, uid, place, at, "xn76u"); err != nil {
				t.Fatal(err)
			}
			l, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "hit", Rating: 4, Comment: "静か", CreatedAt: at, Public: true})
			if err != nil {
				t.Fatal(err)
			}
			got, err := st.UpdateLog(ctx, uid, l.ID, LogUpdate{Rating: ptr(2), Comment: ptr("混んでいた")})
			if err != nil {
				t.Fatal(err)
			}
			if got.Rating != 2 || got.Verdict != "miss" || got.Comment != "混んでいた" || !got.Public {
				t.Errorf("変えた記録: %+v", got)
			}
			counts, err := st.VerdictCounts(ctx, []string{place})
			if err != nil {
				t.Fatal(err)
			}
			if c := counts[place]; c.Hits != 0 || c.Misses != 1 || c.RatingSum != 2 || c.RatingCount != 1 {
				t.Errorf("1人1票の入れ替え: %+v", c)
			}
			entries, err := st.Timeline(ctx, []string{"xn76u"}, 50)
			if err != nil {
				t.Fatal(err)
			}
			found := false
			for _, e := range entries {
				if e.PlaceID == place {
					found = true
					if e.Comment != "混んでいた" || e.Rating != 2 {
						t.Errorf("タイムラインに反映していない: %+v", e)
					}
				}
			}
			if !found {
				t.Error("公開中の記録がタイムラインにない")
			}
		})
	}
}

func TestEditingAnOlderLogKeepsTheVoteOfTheNewest(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			uid, place := unique(t, "u"), unique(t, "p")
			at := time.Date(2026, 11, 3, 1, 0, 0, 0, time.UTC)
			if _, _, err := st.CheckIn(ctx, uid, place, at, ""); err != nil {
				t.Fatal(err)
			}
			old, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "hit", Rating: 5, CreatedAt: at, ClientID: "a1"})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "miss", Rating: 1, CreatedAt: at.Add(24 * time.Hour), ClientID: "a2"}); err != nil {
				t.Fatal(err)
			}
			// 古い記録を直しても、票はいちばん新しい記録の★1のまま
			if _, err := st.UpdateLog(ctx, uid, old.ID, LogUpdate{Rating: ptr(4)}); err != nil {
				t.Fatal(err)
			}
			counts, err := st.VerdictCounts(ctx, []string{place})
			if err != nil {
				t.Fatal(err)
			}
			if c := counts[place]; c.Misses != 1 || c.Hits != 0 || c.RatingSum != 1 || c.RatingCount != 1 {
				t.Errorf("古い記録を直して票が変わった: %+v", c)
			}
		})
	}
}

func TestVoteFollowsTheNewestVisitEvenWhenAnOlderVisitArrivesLater(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			uid, place := unique(t, "u"), unique(t, "p")
			at := time.Date(2026, 11, 3, 1, 0, 0, 0, time.UTC)
			if _, _, err := st.CheckIn(ctx, uid, place, at, ""); err != nil {
				t.Fatal(err)
			}
			rating := func() VerdictCount {
				t.Helper()
				counts, err := st.VerdictCounts(ctx, []string{place})
				if err != nil {
					t.Fatal(err)
				}
				return counts[place]
			}
			// 新しい訪問を先に送り、圏外で残した前の日の訪問を後から送る
			newer, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "hit", Rating: 5, CreatedAt: at.Add(24 * time.Hour), ClientID: "n1"})
			if err != nil {
				t.Fatal(err)
			}
			older, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "miss", Rating: 1, CreatedAt: at, ClientID: "o1"})
			if err != nil {
				t.Fatal(err)
			}
			if c := rating(); c.Hits != 1 || c.Misses != 0 || c.RatingSum != 5 || c.RatingCount != 1 {
				t.Errorf("後から届いた前の訪問の★1で集計した: %+v", c)
			}
			// 前の訪問を直しても変わらず、新しい訪問を直すと変わる
			if _, err := st.UpdateLog(ctx, uid, older.ID, LogUpdate{Rating: ptr(2)}); err != nil {
				t.Fatal(err)
			}
			if c := rating(); c.RatingSum != 5 || c.RatingCount != 1 {
				t.Errorf("前の訪問を直して集計が変わった: %+v", c)
			}
			if _, err := st.UpdateLog(ctx, uid, newer.ID, LogUpdate{Rating: ptr(4)}); err != nil {
				t.Fatal(err)
			}
			if c := rating(); c.Hits != 1 || c.RatingSum != 4 || c.RatingCount != 1 {
				t.Errorf("新しい訪問を直しても集計が変わらない: %+v", c)
			}
		})
	}
}

func TestLatestTimelineReturnsPublicEntriesFromAnyArea(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			uid, place := unique(t, "u"), unique(t, "p")
			// ほかの実行より新しい日時にして、新着の先頭に来るようにする
			at := time.Now().UTC().Add(time.Hour)
			if _, _, err := st.CheckIn(ctx, uid, place, at, "zzzzz"); err != nil {
				t.Fatal(err)
			}
			pub, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "hit", Rating: 5, CreatedAt: at, Public: true, ClientID: "p1"})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := st.AddLog(ctx, uid, Log{PlaceID: place, Verdict: "hit", Rating: 4, CreatedAt: at.Add(time.Minute), ClientID: "p2"}); err != nil {
				t.Fatal(err)
			}
			got, err := st.LatestTimeline(ctx, 20)
			if err != nil {
				t.Fatal(err)
			}
			n := 0
			for _, e := range got {
				if e.PlaceID == place {
					n++
					if e.ID != timelineID(uid, pub.ID) {
						t.Errorf("公開した記録ではない: %+v", e)
					}
				}
			}
			if n != 1 {
				t.Errorf("公開した記録だけを返す: %d 件", n)
			}
		})
	}
}

func TestReactionsAndPhotos(t *testing.T) {
	for name, st := range stores(t) {
		t.Run(name, func(t *testing.T) {
			ctx := context.Background()
			alice, bob, place := unique(t, "alice"), unique(t, "bob"), unique(t, "p")
			at := time.Date(2026, 11, 9, 1, 0, 0, 0, time.UTC)
			photoID, err := st.SavePhoto(ctx, alice, Photo{ContentType: "image/jpeg", Data: []byte{0xFF, 0xD8, 0xFF, 1}}, at)
			if err != nil {
				t.Fatal(err)
			}
			if p, err := st.Photo(ctx, photoID); err != nil || p.Owner != alice || len(p.Data) != 4 {
				t.Fatalf("写真: %+v %v", p, err)
			}
			if _, err := st.Photo(ctx, "ph_none"); !errors.Is(err, ErrPhotoNotFound) {
				t.Errorf("ない写真: %v", err)
			}
			if _, _, err := st.CheckIn(ctx, alice, place, at, "xn76u"); err != nil {
				t.Fatal(err)
			}
			l, err := st.AddLog(ctx, alice, Log{PlaceID: place, Verdict: "hit", Rating: 5, CreatedAt: at, Public: true, Genre: "worship", PhotoID: photoID})
			if err != nil {
				t.Fatal(err)
			}
			entryID := TimelineIDOf(alice, l.ID)
			if _, err := st.React(ctx, alice, entryID, ReactionWant, true); !errors.Is(err, ErrOwnEntry) {
				t.Errorf("自分の記録: %v", err)
			}
			for range 2 {
				if _, err := st.React(ctx, bob, entryID, ReactionWant, true); err != nil {
					t.Fatal(err)
				}
			}
			e, err := st.React(ctx, bob, entryID, ReactionHelpful, true)
			if err != nil || e.WantCount != 1 || e.HelpfulCount != 1 {
				t.Fatalf("1人1回で数える: %+v %v", e, err)
			}
			mine, err := st.MyReactions(ctx, bob, []string{entryID})
			if err != nil || !mine[entryID].Want || !mine[entryID].Helpful {
				t.Errorf("自分の反応: %+v %v", mine, err)
			}
			got, err := st.TimelineEntries(ctx, []string{entryID})
			if err != nil || got[entryID].WantCount != 1 || got[entryID].PhotoID != photoID || got[entryID].Genre != "worship" {
				t.Errorf("記録の数と写真: %+v %v", got[entryID], err)
			}
			// 記録を直して公開し直しても、反応の数は残る
			if _, err := st.UpdateLog(ctx, alice, l.ID, LogUpdate{Comment: ptr("直した")}); err != nil {
				t.Fatal(err)
			}
			got, _ = st.TimelineEntries(ctx, []string{entryID})
			if got[entryID].WantCount != 1 {
				t.Errorf("直した後も反応の数を残す: %+v", got[entryID])
			}
			if e, err := st.React(ctx, bob, entryID, ReactionWant, false); err != nil || e.WantCount != 0 {
				t.Errorf("外す: %+v %v", e, err)
			}
		})
	}
}
