package store

import (
	"context"
	"errors"
	"slices"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	firestorepb "cloud.google.com/go/firestore/apiv1/firestorepb"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/usage"
)

// FirestoreStore は STORE_MODE=firestore のときに使う。
// Admin の権限（サービスアカウント）で読み書きするので、セキュリティルールの影響を受けない。
// ルールでは、クライアントからの読み書きをすべて禁止する。
type FirestoreStore struct {
	client *firestore.Client
}

func NewFirestoreStore(client *firestore.Client) *FirestoreStore {
	return &FirestoreStore{client: client}
}

func (s *FirestoreStore) Close() error { return s.client.Close() }

type fsCheckin struct {
	Order int       `firestore:"order"`
	At    time.Time `firestore:"at"`
	Geo   string    `firestore:"geo,omitempty"`
}

type fsLog struct {
	PlaceID   string    `firestore:"placeId"`
	Verdict   string    `firestore:"verdict"`
	Rating    int       `firestore:"rating,omitempty"`
	Comment   string    `firestore:"comment"`
	Order     int       `firestore:"order"`
	PhotoPath string    `firestore:"photoPath,omitempty"`
	CreatedAt time.Time `firestore:"createdAt"`
	Public    bool      `firestore:"public"`
	Geo       string    `firestore:"geo,omitempty"`
	Genre     string    `firestore:"genre,omitempty"`
	PhotoID   string    `firestore:"photoId,omitempty"`
}

type fsTimeline struct {
	Author    string    `firestore:"author"`
	PlaceID   string    `firestore:"placeId"`
	Verdict   string    `firestore:"verdict"`
	Rating    int       `firestore:"rating,omitempty"`
	Comment   string    `firestore:"comment"`
	Order     int       `firestore:"order"`
	CreatedAt time.Time `firestore:"createdAt"`
	Geo       string    `firestore:"geo"`
	Reports   int       `firestore:"reports"`
	Public    bool      `firestore:"public"`
	Genre     string    `firestore:"genre,omitempty"`
	PhotoID   string    `firestore:"photoId,omitempty"`
	// WantCount と HelpfulCount は反応の数。反応を付けるトランザクションだけが書く
	WantCount    int `firestore:"wantCount"`
	HelpfulCount int `firestore:"helpfulCount"`
}

func timelineFromDoc(id string, f fsTimeline) TimelineEntry {
	return TimelineEntry{
		ID: id, Author: f.Author, PlaceID: f.PlaceID, Verdict: f.Verdict, Rating: f.Rating, Comment: f.Comment,
		Order: f.Order, CreatedAt: f.CreatedAt, Geo: f.Geo, Reports: f.Reports, Public: f.Public,
		Genre: f.Genre, PhotoID: f.PhotoID, WantCount: f.WantCount, HelpfulCount: f.HelpfulCount,
	}
}

type fsProfile struct {
	Nickname string `firestore:"nickname"`
	Icon     string `firestore:"icon"`
}

// publishFields は公開するときに書く項目。報告の数は含めない。
// 上書きすると、非公開にして公開し直すだけで報告を取り消せてしまう。
func publishFields(e TimelineEntry) map[string]any {
	return map[string]any{
		"author": e.Author, "placeId": e.PlaceID, "verdict": e.Verdict, "rating": e.Rating, "comment": e.Comment,
		"order": e.Order, "createdAt": e.CreatedAt, "geo": e.Geo, "public": true,
		"genre": e.Genre, "photoId": e.PhotoID,
	}
}

// voteChange は票を入れ替えるときに places/{placeId} の数へ足す値。oldVerdict が空ならはじめての票。
func voteChange(oldVerdict string, oldRating int, verdict string, rating int) map[string]any {
	var c VerdictCount
	if oldVerdict != "" {
		c = c.without(oldVerdict, oldRating)
	}
	c = c.with(verdict, rating)
	change := map[string]any{}
	for field, n := range map[string]int{
		"hits": c.Hits, "misses": c.Misses, "ratingSum": c.RatingSum, "ratingCount": c.RatingCount,
	} {
		if n != 0 {
			change[field] = firestore.Increment(n)
		}
	}
	return change
}

func (s *FirestoreStore) placeRef(placeID string) *firestore.DocumentRef {
	return s.client.Collection("places").Doc(placeID)
}

func (s *FirestoreStore) checkinRef(placeID, uid string) *firestore.DocumentRef {
	return s.placeRef(placeID).Collection("checkins").Doc(uid)
}

func (s *FirestoreStore) logs(uid string) *firestore.CollectionRef {
	return s.client.Collection("users").Doc(uid).Collection("logs")
}

func isNotFound(err error) bool { return status.Code(err) == codes.NotFound }

// CheckIn は places/{placeId} と places/{placeId}/checkins/{uid} を同じトランザクションで更新する。
// 同時にチェックインしても順番は重ならない（衝突すると Firestore が自動でやり直す）。
func (s *FirestoreStore) CheckIn(ctx context.Context, uid, placeID string, now time.Time, geo string) (int, bool, error) {
	var order int
	var isNew bool
	err := s.client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		mineRef := s.checkinRef(placeID, uid)
		mine, err := tx.Get(mineRef)
		if err == nil {
			var c fsCheckin
			if err := mine.DataTo(&c); err != nil {
				return err
			}
			order, isNew = c.Order, false
			return nil
		}
		if !isNotFound(err) {
			return err
		}

		count := 0
		placeSnap, err := tx.Get(s.placeRef(placeID))
		switch {
		case err == nil:
			if v, err := placeSnap.DataAt("visitorCount"); err == nil {
				if n, ok := v.(int64); ok {
					count = int(n)
				}
			}
		case !isNotFound(err):
			return err
		}

		order, isNew = count+1, true
		if err := tx.Set(s.placeRef(placeID), map[string]any{"visitorCount": order}, firestore.MergeAll); err != nil {
			return err
		}
		return tx.Create(mineRef, fsCheckin{Order: order, At: now.UTC(), Geo: geo})
	})
	if err != nil {
		return 0, false, err
	}
	return order, isNew, nil
}

func (s *FirestoreStore) CheckinOrder(ctx context.Context, uid, placeID string) (int, bool, error) {
	snap, err := s.checkinRef(placeID, uid).Get(ctx)
	if isNotFound(err) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	var c fsCheckin
	if err := snap.DataTo(&c); err != nil {
		return 0, false, err
	}
	return c.Order, true, nil
}

func (s *FirestoreStore) VisitorCount(ctx context.Context, placeID string) (int, error) {
	snap, err := s.placeRef(placeID).Get(ctx)
	if isNotFound(err) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	v, err := snap.DataAt("visitorCount")
	if err != nil {
		return 0, nil // 項目がなければ0
	}
	n, _ := v.(int64)
	return int(n), nil
}

// AddLog は記録と当たりの数と公開の記録を同じトランザクションで保存する。送り直しても数が増えない。
func (s *FirestoreStore) AddLog(ctx context.Context, uid string, l Log) (Log, error) {
	l.ID = newLogID(l.ClientID)
	l.CreatedAt = l.CreatedAt.UTC()
	ref := s.logs(uid).Doc(l.ID)
	var saved Log
	err := s.client.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(s.checkinRef(l.PlaceID, uid))
		if isNotFound(err) {
			return ErrNotCheckedIn
		}
		if err != nil {
			return err
		}
		var c fsCheckin
		if err := snap.DataTo(&c); err != nil {
			return err
		}
		existing, err := tx.Get(ref)
		if err == nil {
			saved, err = logFromDoc(existing)
			return err
		}
		if !isNotFound(err) {
			return err
		}

		// 1人1票にする。同じ場所の記録を重ねても、数が増えないようにする。
		// 票はその場所でいちばん後に訪問した記録の★評価にするので、前の訪問が後から届いたときは変えない
		latest, err := s.latestLog(tx, uid, l.PlaceID)
		if err != nil {
			return err
		}
		newest := latest.ID == "" || newerVisit(l, latest)
		voteRef := s.placeRef(l.PlaceID).Collection("verdicts").Doc(uid)
		oldVerdict, oldRating := "", 0
		voteSnap, err := tx.Get(voteRef)
		switch {
		case err == nil:
			if v, err := voteSnap.DataAt("verdict"); err == nil {
				oldVerdict, _ = v.(string)
			}
			if v, err := voteSnap.DataAt("rating"); err == nil {
				if n, ok := v.(int64); ok {
					oldRating = int(n)
				}
			}
		case !isNotFound(err):
			return err
		}

		saved = l
		saved.Order = c.Order
		saved.Geo = c.Geo
		if err := tx.Create(ref, fsLog{
			PlaceID: l.PlaceID, Verdict: l.Verdict, Rating: l.Rating, Comment: l.Comment, Order: c.Order,
			PhotoPath: l.PhotoPath, CreatedAt: l.CreatedAt, Public: l.Public, Geo: c.Geo,
			Genre: l.Genre, PhotoID: l.PhotoID,
		}); err != nil {
			return err
		}
		if newest && (oldVerdict != l.Verdict || oldRating != l.Rating) {
			if err := tx.Set(s.placeRef(l.PlaceID), voteChange(oldVerdict, oldRating, l.Verdict, l.Rating), firestore.MergeAll); err != nil {
				return err
			}
			if err := tx.Set(voteRef, map[string]any{"verdict": l.Verdict, "rating": l.Rating}); err != nil {
				return err
			}
		}
		if l.Public {
			return tx.Set(s.timelineRef(uid, l.ID), publishFields(newTimelineEntry(uid, saved)), firestore.MergeAll)
		}
		return nil
	})
	if err != nil {
		return Log{}, err
	}
	return saved, nil
}

func (s *FirestoreStore) timelineRef(uid, logID string) *firestore.DocumentRef {
	return s.client.Collection("timeline").Doc(timelineID(uid, logID))
}

func (s *FirestoreStore) UpdateLog(ctx context.Context, uid, logID string, u LogUpdate) (Log, error) {
	ref := s.logs(uid).Doc(logID)
	var saved Log
	err := s.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if isNotFound(err) {
			return ErrLogNotFound
		}
		if err != nil {
			return err
		}
		before, err := logFromDoc(snap)
		if err != nil {
			return err
		}
		saved = u.apply(before)
		entryRef := s.timelineRef(uid, logID)
		_, entryErr := tx.Get(entryRef)
		if entryErr != nil && !isNotFound(entryErr) {
			return entryErr
		}
		// 票を入れ替えるため、書く前に今の票を読む（トランザクションでは読みを先に済ませる）。
		// 票はその場所のいちばん新しい記録の★評価にするので、古い記録を直したときは変えない
		rated := saved.Verdict != before.Verdict || saved.Rating != before.Rating
		if rated {
			latest, err := s.latestLog(tx, uid, saved.PlaceID)
			if err != nil {
				return err
			}
			rated = latest.ID == logID
		}
		voteRef := s.placeRef(saved.PlaceID).Collection("verdicts").Doc(uid)
		oldVerdict, oldRating := "", 0
		if rated {
			voteSnap, err := tx.Get(voteRef)
			switch {
			case err == nil:
				if v, err := voteSnap.DataAt("verdict"); err == nil {
					oldVerdict, _ = v.(string)
				}
				if v, err := voteSnap.DataAt("rating"); err == nil {
					if n, ok := v.(int64); ok {
						oldRating = int(n)
					}
				}
			case !isNotFound(err):
				return err
			}
		}
		if err := tx.Update(ref, []firestore.Update{
			{Path: "verdict", Value: saved.Verdict}, {Path: "rating", Value: saved.Rating},
			{Path: "comment", Value: saved.Comment}, {Path: "public", Value: saved.Public},
		}); err != nil {
			return err
		}
		if rated && (oldVerdict != saved.Verdict || oldRating != saved.Rating) {
			if err := tx.Set(s.placeRef(saved.PlaceID), voteChange(oldVerdict, oldRating, saved.Verdict, saved.Rating), firestore.MergeAll); err != nil {
				return err
			}
			if err := tx.Set(voteRef, map[string]any{"verdict": saved.Verdict, "rating": saved.Rating}); err != nil {
				return err
			}
		}
		if saved.Public {
			return tx.Set(entryRef, publishFields(newTimelineEntry(uid, saved)), firestore.MergeAll)
		}
		if isNotFound(entryErr) {
			return nil
		}
		// 報告の数を残すために文書は消さず、公開していた内容だけを消す
		return tx.Update(entryRef, []firestore.Update{
			{Path: "public", Value: false}, {Path: "comment", Value: ""}, {Path: "placeId", Value: ""},
		})
	})
	if err != nil {
		return Log{}, err
	}
	return saved, nil
}

func (s *FirestoreStore) VerdictCounts(ctx context.Context, placeIDs []string) (map[string]VerdictCount, error) {
	out := map[string]VerdictCount{}
	if len(placeIDs) == 0 {
		return out, nil
	}
	refs := make([]*firestore.DocumentRef, len(placeIDs))
	for i, id := range placeIDs {
		refs[i] = s.placeRef(id)
	}
	snaps, err := s.client.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for i, snap := range snaps {
		if !snap.Exists() {
			continue
		}
		var c struct {
			Hits        int `firestore:"hits"`
			Misses      int `firestore:"misses"`
			RatingSum   int `firestore:"ratingSum"`
			RatingCount int `firestore:"ratingCount"`
		}
		if err := snap.DataTo(&c); err != nil {
			return nil, err
		}
		if c.Hits > 0 || c.Misses > 0 {
			out[placeIDs[i]] = VerdictCount{Hits: c.Hits, Misses: c.Misses, RatingSum: c.RatingSum, RatingCount: c.RatingCount}
		}
	}
	return out, nil
}

// Timeline は firestore.indexes.json の複合インデックスを使う。
// 並べ替えずに件数を絞ると、古い記録で上限が埋まって新しい記録が出なくなるため。
func (s *FirestoreStore) Timeline(ctx context.Context, geos []string, limit int) ([]TimelineEntry, error) {
	if len(geos) == 0 {
		return []TimelineEntry{}, nil
	}
	docs, err := s.client.Collection("timeline").Where("public", "==", true).Where("geo", "in", geos).
		OrderBy("createdAt", firestore.Desc).Limit(300).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]TimelineEntry, 0, len(docs))
	for _, d := range docs {
		var f fsTimeline
		if err := d.DataTo(&f); err != nil {
			return nil, err
		}
		out = append(out, timelineFromDoc(d.Ref.ID, f))
	}
	return latestVisible(out, limit), nil
}

func (s *FirestoreStore) ReportEntry(ctx context.Context, uid, entryID string, rep Report) error {
	ref := s.client.Collection("timeline").Doc(entryID)
	reporter := ref.Collection("reports").Doc(uid)
	return s.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		entry, err := tx.Get(ref)
		if isNotFound(err) {
			return ErrEntryNotFound
		}
		if err != nil {
			return err
		}
		if public, err := entry.DataAt("public"); err != nil || public != true {
			return ErrEntryNotFound
		}
		_, err = tx.Get(reporter)
		if err == nil {
			return nil
		}
		if !isNotFound(err) {
			return err
		}
		if err := tx.Create(reporter, map[string]any{"at": firestore.ServerTimestamp, "reason": string(rep.Reason), "note": rep.Note}); err != nil {
			return err
		}
		return tx.Update(ref, []firestore.Update{{Path: "reports", Value: firestore.Increment(1)}})
	})
}

func logFromDoc(d *firestore.DocumentSnapshot) (Log, error) {
	var f fsLog
	if err := d.DataTo(&f); err != nil {
		return Log{}, errors.Join(errors.New("思い出ログを読めません: "+d.Ref.ID), err)
	}
	return Log{
		ID: d.Ref.ID, PlaceID: f.PlaceID, Verdict: f.Verdict, Rating: f.Rating, Comment: f.Comment,
		Order: f.Order, PhotoPath: f.PhotoPath, CreatedAt: f.CreatedAt, Public: f.Public, Geo: f.Geo,
		Genre: f.Genre, PhotoID: f.PhotoID,
	}, nil
}

// ListLogs は createdAt の新しい順に返す。1つの項目での並べ替えなので、複合インデックスはいらない。
func (s *FirestoreStore) ListLogs(ctx context.Context, uid string) ([]Log, error) {
	docs, err := s.logs(uid).OrderBy("createdAt", firestore.Desc).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]Log, 0, len(docs))
	for _, d := range docs {
		l, err := logFromDoc(d)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, nil
}

type fsUsage struct {
	Real      map[string]int `firestore:"real"`
	Simulated map[string]int `firestore:"simulated"`
}

type fsUserUsage struct {
	Calls int `firestore:"calls"`
}

func (s *FirestoreStore) usageRef(date string) *firestore.DocumentRef {
	return s.client.Collection("usage").Doc(date)
}

func (s *FirestoreStore) userUsageRef(date, uid string) *firestore.DocumentRef {
	return s.usageRef(date).Collection("users").Doc(uid)
}

// TakeCall は同じトランザクションで上限を確かめて数える。同時に呼ばれても上限を超えない。
func (s *FirestoreStore) TakeCall(ctx context.Context, date, key, uid string, limit, userLimit int) (bool, error) {
	allowed := false
	err := s.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		allowed = false
		ref := s.usageRef(date)
		var u fsUsage
		snap, err := tx.Get(ref)
		switch {
		case err == nil:
			if err := snap.DataTo(&u); err != nil {
				return err
			}
		case !isNotFound(err):
			return err
		}
		total := 0
		for k, n := range u.Real {
			if usage.SameBudget(k, key) {
				total += n
			}
		}
		if total >= limit {
			return nil
		}

		userCalls := 0
		if uid != "" {
			userSnap, err := tx.Get(s.userUsageRef(date, uid))
			switch {
			case err == nil:
				var mine fsUserUsage
				if err := userSnap.DataTo(&mine); err != nil {
					return err
				}
				userCalls = mine.Calls
			case !isNotFound(err):
				return err
			}
			if userCalls >= userLimit {
				return nil
			}
		}

		allowed = true
		if uid != "" {
			if err := tx.Set(s.userUsageRef(date, uid), fsUserUsage{Calls: userCalls + 1}); err != nil {
				return err
			}
		}
		return tx.Set(ref, map[string]any{"real": map[string]any{key: u.Real[key] + 1}}, firestore.MergeAll)
	})
	return allowed, err
}

func (s *FirestoreStore) AddSimulated(ctx context.Context, date, key string) error {
	_, err := s.usageRef(date).Set(ctx, map[string]any{
		"simulated": map[string]any{key: firestore.Increment(1)},
	}, firestore.MergeAll)
	return err
}

func (s *FirestoreStore) Days(ctx context.Context, dates []string) ([]usage.Day, error) {
	refs := make([]*firestore.DocumentRef, len(dates))
	for i, date := range dates {
		refs[i] = s.usageRef(date)
	}
	snaps, err := s.client.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	out := []usage.Day{}
	for i, snap := range snaps {
		if !snap.Exists() {
			continue
		}
		var u fsUsage
		if err := snap.DataTo(&u); err != nil {
			return nil, err
		}
		out = append(out, usage.Day{Date: dates[i], Real: u.Real, Simulated: u.Simulated})
	}
	return out, nil
}

func (s *FirestoreStore) authorRef(tag string) *firestore.DocumentRef {
	return s.client.Collection("authors").Doc(tag)
}

func (s *FirestoreStore) favorites(uid string) *firestore.CollectionRef {
	return s.client.Collection("users").Doc(uid).Collection("favorites")
}

// AddFavorite は数を確かめてから登録する。同時に登録すると上限を少し超えることがあるが、上限は費用の目安なので許す。
func (s *FirestoreStore) AddFavorite(ctx context.Context, uid, placeID string, at time.Time) error {
	ref := s.favorites(uid).Doc(placeID)
	if _, err := ref.Get(ctx); err == nil {
		return nil
	} else if !isNotFound(err) {
		return err
	}
	n, err := s.favorites(uid).NewAggregationQuery().WithCount("n").Get(ctx)
	if err != nil {
		return err
	}
	if v, ok := n["n"].(*firestorepb.Value); ok && v.GetIntegerValue() >= MaxFavorites {
		return ErrTooManyFavorites
	}
	_, err = ref.Set(ctx, map[string]any{"createdAt": at.UTC()})
	return err
}

func (s *FirestoreStore) RemoveFavorite(ctx context.Context, uid, placeID string) error {
	_, err := s.favorites(uid).Doc(placeID).Delete(ctx)
	if isNotFound(err) {
		return nil
	}
	return err
}

func (s *FirestoreStore) Favorites(ctx context.Context, uid string) ([]Favorite, error) {
	docs, err := s.favorites(uid).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]Favorite, 0, len(docs))
	for _, d := range docs {
		var f struct {
			CreatedAt time.Time `firestore:"createdAt"`
		}
		if err := d.DataTo(&f); err != nil {
			return nil, err
		}
		out = append(out, Favorite{PlaceID: d.Ref.ID, CreatedAt: f.CreatedAt})
	}
	sortFavorites(out)
	return out, nil
}

func (s *FirestoreStore) Profile(ctx context.Context, uid string) (Profile, bool, error) {
	d, err := s.authorRef(AuthorTag(uid)).Get(ctx)
	if isNotFound(err) {
		return Profile{}, false, nil
	}
	if err != nil {
		return Profile{}, false, err
	}
	var f fsProfile
	if err := d.DataTo(&f); err != nil {
		return Profile{}, false, err
	}
	return Profile{Nickname: f.Nickname, Icon: f.Icon}, true, nil
}

func (s *FirestoreStore) SetProfile(ctx context.Context, uid string, p Profile) error {
	_, err := s.authorRef(AuthorTag(uid)).Set(ctx, map[string]any{
		"nickname": p.Nickname, "icon": p.Icon, "updatedAt": firestore.ServerTimestamp,
	})
	return err
}

// Profiles はタイムラインの投稿者をまとめて1回で読む。投稿ごとに読むと、件数の分だけ往復が増えるため。
func (s *FirestoreStore) Profiles(ctx context.Context, authorTags []string) (map[string]Profile, error) {
	out := map[string]Profile{}
	tags := slices.Compact(slices.Sorted(slices.Values(authorTags)))
	if len(tags) == 0 {
		return out, nil
	}
	refs := make([]*firestore.DocumentRef, len(tags))
	for i, tag := range tags {
		refs[i] = s.authorRef(tag)
	}
	docs, err := s.client.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for _, d := range docs {
		if !d.Exists() {
			continue
		}
		var f fsProfile
		if err := d.DataTo(&f); err != nil {
			return nil, err
		}
		out[d.Ref.ID] = Profile{Nickname: f.Nickname, Icon: f.Icon}
	}
	return out, nil
}

func (s *FirestoreStore) achievementRef(uid string) *firestore.DocumentRef {
	return s.client.Collection("achievements").Doc(uid)
}

// achievementStatsRef は全体の集計の文書。利用者ごとの文書を毎回全部読まずに済むよう、差分で数え続ける
func (s *FirestoreStore) achievementStatsRef() *firestore.DocumentRef {
	return s.client.Collection("stats").Doc("achievements")
}

type fsAchievements struct {
	Tiers map[string]int `firestore:"tiers"`
}

// fsAchievementStats の counts のキーは「実績 ID:段階」（例: pioneer:2）。フィールドのパスと区別するため「.」は使わない
type fsAchievementStats struct {
	Users  int            `firestore:"users"`
	Counts map[string]int `firestore:"counts"`
}

func (s *FirestoreStore) SetAchievements(ctx context.Context, uid string, tiers map[string]int) error {
	return s.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		var mine fsAchievements
		existed := true
		snap, err := tx.Get(s.achievementRef(uid))
		switch {
		case err == nil:
			if err := snap.DataTo(&mine); err != nil {
				return err
			}
		case isNotFound(err):
			existed = false
		default:
			return err
		}
		if existed && sameTiers(mine.Tiers, tiers) {
			return nil
		}
		var stats fsAchievementStats
		statsSnap, err := tx.Get(s.achievementStatsRef())
		switch {
		case err == nil:
			if err := statsSnap.DataTo(&stats); err != nil {
				return err
			}
		case !isNotFound(err):
			return err
		}
		if stats.Counts == nil {
			stats.Counts = map[string]int{}
		}
		if !existed {
			stats.Users++
		}
		for id, d := range achievementDiff(mine.Tiers, tiers) {
			for i, n := range d {
				key := id + ":" + strconv.Itoa(i+1)
				stats.Counts[key] = max(0, stats.Counts[key]+n)
			}
		}
		if err := tx.Set(s.achievementStatsRef(), stats); err != nil {
			return err
		}
		return tx.Set(s.achievementRef(uid), map[string]any{"tiers": tiers, "updatedAt": firestore.ServerTimestamp})
	})
}

func (s *FirestoreStore) AchievementStats(ctx context.Context) (AchievementStats, error) {
	out := AchievementStats{Counts: map[string][MaxAchievementTier]int{}}
	snap, err := s.achievementStatsRef().Get(ctx)
	if isNotFound(err) {
		return out, nil
	}
	if err != nil {
		return out, err
	}
	var f fsAchievementStats
	if err := snap.DataTo(&f); err != nil {
		return out, err
	}
	out.Users = f.Users
	for key, n := range f.Counts {
		id, tierText, ok := strings.Cut(key, ":")
		tier, err := strconv.Atoi(tierText)
		if !ok || err != nil || tier < 1 || tier > MaxAchievementTier {
			continue
		}
		c := out.Counts[id]
		c[tier-1] = n
		out.Counts[id] = c
	}
	return out, nil
}

// latestLog は uid がその場所に残した記録のうち、いちばん後に訪問した記録を返す。記録がなければ ID の空の Log を返す。
// 複合インデックスを作らずに済むよう、場所だけで絞って読み、新しいものを手元で選ぶ（1人が同じ場所に残す記録は少ない）。
func (s *FirestoreStore) latestLog(tx *firestore.Transaction, uid, placeID string) (Log, error) {
	docs, err := tx.Documents(s.logs(uid).Where("placeId", "==", placeID)).GetAll()
	if err != nil {
		return Log{}, err
	}
	var latest Log
	for _, d := range docs {
		l, err := logFromDoc(d)
		if err != nil {
			return Log{}, err
		}
		if latest.ID == "" || newerVisit(l, latest) {
			latest = l
		}
	}
	return latest, nil
}

// LatestTimeline は全国の新着を返す。複合インデックスを増やさないよう、日時の並びだけで読み、公開中のものを手元で選ぶ
// （日時だけの並べ替えは、Firestore が自動で作る1つの項目のインデックスで足りる）。
func (s *FirestoreStore) LatestTimeline(ctx context.Context, limit int) ([]TimelineEntry, error) {
	docs, err := s.client.Collection("timeline").OrderBy("createdAt", firestore.Desc).Limit(300).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]TimelineEntry, 0, len(docs))
	for _, d := range docs {
		var f fsTimeline
		if err := d.DataTo(&f); err != nil {
			return nil, err
		}
		if !f.Public {
			continue
		}
		out = append(out, timelineFromDoc(d.Ref.ID, f))
	}
	return latestVisible(out, limit), nil
}

func (s *FirestoreStore) photoRef(id string) *firestore.DocumentRef {
	return s.client.Collection("photos").Doc(id)
}

type fsPhoto struct {
	Owner       string    `firestore:"owner"`
	ContentType string    `firestore:"contentType"`
	Data        []byte    `firestore:"data"`
	CreatedAt   time.Time `firestore:"createdAt"`
}

// SavePhoto は写真を Firestore に保存する（1件 1MiB まで。アプリが縮小してから送る）。
// Cloud Storage のバケットと権限の設定を増やさずに済むよう、ハッカソンの規模では Firestore に置く（docs/decisions.md の D-031）
func (s *FirestoreStore) SavePhoto(ctx context.Context, uid string, p Photo, at time.Time) (string, error) {
	id := newPhotoID()
	_, err := s.photoRef(id).Create(ctx, fsPhoto{Owner: uid, ContentType: p.ContentType, Data: p.Data, CreatedAt: at.UTC()})
	return id, err
}

func (s *FirestoreStore) Photo(ctx context.Context, id string) (Photo, error) {
	d, err := s.photoRef(id).Get(ctx)
	if isNotFound(err) {
		return Photo{}, ErrPhotoNotFound
	}
	if err != nil {
		return Photo{}, err
	}
	var f fsPhoto
	if err := d.DataTo(&f); err != nil {
		return Photo{}, err
	}
	return Photo{Owner: f.Owner, ContentType: f.ContentType, Data: f.Data}, nil
}

type fsReactions struct {
	Want    bool `firestore:"want"`
	Helpful bool `firestore:"helpful"`
}

func (s *FirestoreStore) React(ctx context.Context, uid, entryID string, kind ReactionKind, on bool) (TimelineEntry, error) {
	ref := s.client.Collection("timeline").Doc(entryID)
	mine := ref.Collection("reactions").Doc(uid)
	var out TimelineEntry
	err := s.client.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if isNotFound(err) {
			return ErrEntryNotFound
		}
		if err != nil {
			return err
		}
		var f fsTimeline
		if err := snap.DataTo(&f); err != nil {
			return err
		}
		if !f.Public {
			return ErrEntryNotFound
		}
		if f.Author == AuthorTag(uid) {
			return ErrOwnEntry
		}
		var before fsReactions
		rs, err := tx.Get(mine)
		switch {
		case err == nil:
			if err := rs.DataTo(&before); err != nil {
				return err
			}
		case !isNotFound(err):
			return err
		}
		after := Reactions(before).with(kind, on)
		dw, dh := boolDelta(before.Want, after.Want), boolDelta(before.Helpful, after.Helpful)
		f.WantCount += dw
		f.HelpfulCount += dh
		out = timelineFromDoc(entryID, f)
		if dw == 0 && dh == 0 {
			return nil
		}
		if err := tx.Set(mine, fsReactions(after)); err != nil {
			return err
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "wantCount", Value: firestore.Increment(dw)},
			{Path: "helpfulCount", Value: firestore.Increment(dh)},
		})
	})
	return out, err
}

func (s *FirestoreStore) MyReactions(ctx context.Context, uid string, entryIDs []string) (map[string]Reactions, error) {
	out := map[string]Reactions{}
	ids := slices.Compact(slices.Sorted(slices.Values(entryIDs)))
	if len(ids) == 0 {
		return out, nil
	}
	refs := make([]*firestore.DocumentRef, len(ids))
	for i, id := range ids {
		refs[i] = s.client.Collection("timeline").Doc(id).Collection("reactions").Doc(uid)
	}
	docs, err := s.client.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for i, d := range docs {
		if !d.Exists() {
			continue
		}
		var f fsReactions
		if err := d.DataTo(&f); err != nil {
			return nil, err
		}
		if f.Want || f.Helpful {
			out[ids[i]] = Reactions(f)
		}
	}
	return out, nil
}

func (s *FirestoreStore) MyReports(ctx context.Context, uid string, entryIDs []string) (map[string]bool, error) {
	out := map[string]bool{}
	ids := slices.Compact(slices.Sorted(slices.Values(entryIDs)))
	if len(ids) == 0 {
		return out, nil
	}
	refs := make([]*firestore.DocumentRef, len(ids))
	for i, id := range ids {
		refs[i] = s.client.Collection("timeline").Doc(id).Collection("reports").Doc(uid)
	}
	docs, err := s.client.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for i, d := range docs {
		if d.Exists() {
			out[ids[i]] = true
		}
	}
	return out, nil
}

func (s *FirestoreStore) TimelineEntries(ctx context.Context, entryIDs []string) (map[string]TimelineEntry, error) {
	out := map[string]TimelineEntry{}
	ids := slices.Compact(slices.Sorted(slices.Values(entryIDs)))
	if len(ids) == 0 {
		return out, nil
	}
	refs := make([]*firestore.DocumentRef, len(ids))
	for i, id := range ids {
		refs[i] = s.client.Collection("timeline").Doc(id)
	}
	docs, err := s.client.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for _, d := range docs {
		if !d.Exists() {
			continue
		}
		var f fsTimeline
		if err := d.DataTo(&f); err != nil {
			return nil, err
		}
		if f.Public {
			out[d.Ref.ID] = timelineFromDoc(d.Ref.ID, f)
		}
	}
	return out, nil
}
