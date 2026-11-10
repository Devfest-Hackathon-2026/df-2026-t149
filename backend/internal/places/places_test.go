package places

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/auth"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/usage"
)

func TestScore(t *testing.T) {
	s := DefaultScorer
	// 削除した Dart のサーバー（server/lib/src/scoring/obscurity.dart）と同じ値になること
	cases := map[int]int{0: 100, 3: 84, 7: 76, 10: 72, 100: 46, 5000: 0, 15400: 0}
	for n, want := range cases {
		if got := s.Score(n); got != want {
			t.Errorf("Score(%d) = %d, want %d", n, got, want)
		}
	}
	titles := map[int]string{0: TitleUntrodden, 10: TitleUntrodden, 11: TitleHidden, 100: TitleHidden,
		101: TitleKnown, 1000: TitleKnown, 1001: TitleFamous}
	for n, want := range titles {
		if got := s.Title(n); got != want {
			t.Errorf("Title(%d) = %q, want %q", n, got, want)
		}
	}
}

func TestPlaceJSONOmitsEmpty(t *testing.T) {
	b, _ := json.Marshal(apiPlace{ID: "x"}.toPlace())
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	if m["name"] != "(名前なし)" {
		t.Errorf("name = %v", m["name"])
	}
	if types, ok := m["types"].([]any); !ok || len(types) != 0 {
		t.Errorf("types は空の配列にする: %v", m["types"])
	}
	for _, k := range []string{"address", "primaryType", "rating", "obscurity", "title", "distanceMeters"} {
		if _, ok := m[k]; ok {
			t.Errorf("値がない %s は省く: %s", k, b)
		}
	}
}

func TestMockShiftsToCaller(t *testing.T) {
	c, err := NewMockClient()
	if err != nil {
		t.Fatal(err)
	}
	ps, _ := c.SearchNearby(context.Background(), NearbyRequest{Lat: 35.0, Lng: 135.78, RadiusMeters: 1500})
	if len(ps) == 0 {
		t.Fatal("ダミーが空")
	}
	if d := DistanceMeters(35.0, 135.78, ps[0].Lat, ps[0].Lng); d > 5000 {
		t.Errorf("呼び出し地点へずれていない: %.0fm", d)
	}
	ps, _ = c.SearchNearby(context.Background(), NearbyRequest{Lat: 34.693, Lng: 135.19, RadiusMeters: 1500, IncludedTypes: []string{"park"}})
	for _, p := range ps {
		if p.PrimaryType != "park" && p.Types[0] != "park" {
			t.Errorf("種類で絞れていない: %v", p)
		}
	}
	hits, _ := c.SearchText(context.Background(), "見つからない名前", 1)
	if len(hits) != 1 {
		t.Errorf("見つからなくても先頭を返す: %v", hits)
	}
}

func TestGoogleClient(t *testing.T) {
	var gotMask, gotKey string
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMask, gotKey = r.Header.Get("X-Goog-FieldMask"), r.Header.Get("X-Goog-Api-Key")
		gotBody = nil
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_, _ = io.WriteString(w, `{"places":[
			{"id":"p1","displayName":{"text":"寺"},"location":{"latitude":35,"longitude":135},"userRatingCount":3,"types":["buddhist_temple"],"businessStatus":"OPERATIONAL"},
			{"id":"closed","displayName":{"text":"閉業"},"businessStatus":"CLOSED_PERMANENTLY"},
			{"id":"resting","displayName":{"text":"休業"},"businessStatus":"CLOSED_TEMPORARILY"}]}`)
	}))
	defer srv.Close()

	c := NewGoogleClient("KEY")
	c.baseURL = srv.URL
	ps, err := c.SearchNearby(context.Background(), NearbyRequest{Lat: 35, Lng: 135, RadiusMeters: 3000, IncludedTypes: []string{"park"}})
	if err != nil || len(ps) != 1 || ps[0].Name != "寺" || ps[0].Lat != 35 {
		t.Fatalf("閉業と休業の場所を除いた1件になっていない: %v %v", ps, err)
	}
	if gotKey != "KEY" || gotMask != fieldMask || gotBody["includedTypes"] == nil || gotBody["languageCode"] != "ja" {
		t.Errorf("request: key=%q mask=%q body=%v", gotKey, gotMask, gotBody)
	}
	if _, ok := gotBody["rankPreference"]; ok {
		t.Errorf("既定の探し方では rankPreference を送らない: %v", gotBody)
	}

	if _, err := c.SearchNearby(context.Background(), NearbyRequest{Lat: 35, Lng: 135, RadiusMeters: 300, RankByDistance: true}); err != nil {
		t.Fatal(err)
	}
	if gotBody["rankPreference"] != "DISTANCE" {
		t.Errorf("近い順の指定が送られていない: %v", gotBody)
	}

	// 名前で探す有名スポットは、休業中でも見つける
	hits, err := c.SearchText(context.Background(), "x", 3)
	if err != nil || len(hits) != 3 {
		t.Errorf("SearchText: %v %v", hits, err)
	}
}

func TestGoogleClientGetPlace(t *testing.T) {
	var gotPath, gotMask string
	status, body := 200, `{"id":"ChIJ a","displayName":{"text":"寺"},"location":{"latitude":35,"longitude":135}}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotMask = r.URL.EscapedPath(), r.Header.Get("X-Goog-FieldMask")
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}))
	defer srv.Close()
	c := NewGoogleClient("KEY")
	c.baseURL = srv.URL

	p, err := c.GetPlace(context.Background(), "ChIJ a", DetailsLocationMask)
	if err != nil || p.Name != "寺" || p.Lat != 35 {
		t.Fatalf("got %+v %v", p, err)
	}
	if gotPath != "/places/ChIJ%20a" || gotMask != DetailsLocationMask {
		t.Errorf("request: path=%q mask=%q", gotPath, gotMask)
	}

	cases := []struct {
		name         string
		status       int
		body         string
		wantNotFound bool
	}{
		{"存在しない", 404, `{"error":{"status":"NOT_FOUND"}}`, true},
		{"形の正しくない ID", 400, `{"error":{"status":"INVALID_ARGUMENT","message":"Not a valid Place ID"}}`, true},
		{"API キーの誤り", 400, `{"error":{"status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}`, false},
		{"サーバーの失敗", 500, `{}`, false},
	}
	for _, tc := range cases {
		status, body = tc.status, tc.body
		_, err := c.GetPlace(context.Background(), "x", DetailsLocationMask)
		if err == nil || errors.Is(err, ErrPlaceNotFound) != tc.wantNotFound {
			t.Errorf("%s: err = %v", tc.name, err)
		}
	}
}

func newGateway(t *testing.T, primary Client, limit int, now time.Time) (*Gateway, *store.MemoryStore) {
	t.Helper()
	mock, err := NewMockClient()
	if err != nil {
		t.Fatal(err)
	}
	st := store.NewMemoryStore()
	return &Gateway{
		Primary: primary, Fallback: mock, Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Usage: st, DailyLimit: limit, Now: func() time.Time { return now },
	}, st
}

var nearbyReq = NearbyRequest{Lat: 34.693, Lng: 135.19, RadiusMeters: 1500}

func TestGatewayGivesNoDummyWhenLive(t *testing.T) {
	g, _ := newGateway(t, failing{}, 100, time.Now())
	if ps, src, err := g.Nearby(context.Background(), nearbyReq, FeatureExplore, false); err == nil {
		t.Fatalf("本物の API が失敗したのにダミーを返した: %d %q", len(ps), src)
	}
	// キーがない開発環境ではダミーを返す
	g.Primary = nil
	if ps, src, err := g.Nearby(context.Background(), nearbyReq, FeatureExplore, false); err != nil || src != SourceMock || len(ps) == 0 {
		t.Fatalf("got %d %q %v", len(ps), src, err)
	}
}

func TestGatewayGivesNoDummyDetailsWhenLive(t *testing.T) {
	g, _ := newGateway(t, failing{}, 100, time.Now())
	g.DetailsDailyLimit = 10
	if _, _, err := g.PlaceLocation(context.Background(), "real"); err == nil || errors.Is(err, ErrPlaceNotFound) {
		t.Errorf("失敗を場所がないことと区別して返す: %v", err)
	}
	if _, _, err := g.PlaceLocation(context.Background(), "mock_01"); !errors.Is(err, ErrPlaceNotFound) {
		t.Errorf("本物の API を使うときのダミーの ID: %v", err)
	}
	g.Primary = nil
	if p, src, err := g.PlaceLocation(context.Background(), "mock_01"); err != nil || src != SourceMock || p.ID != "mock_01" {
		t.Errorf("キーがないときのダミー: %+v %q %v", p, src, err)
	}
}

func TestGatewayDetailsHaveTheirOwnLimits(t *testing.T) {
	ctx := context.Background()
	g, _ := newGateway(t, stubDetails{}, 1, time.Now())
	g.DetailsDailyLimit = 1
	g.UserDailyLimit = 100

	if _, err := g.PlaceName(ctx, "a", FeatureLogs); err != nil {
		t.Fatal(err)
	}
	if _, err := g.PlaceName(ctx, "a", FeatureLogs); !errors.Is(err, ErrDailyLimit) {
		t.Errorf("名前の取得の上限: %v", err)
	}
	if _, _, err := g.PlaceLocation(ctx, "a"); err != nil {
		t.Errorf("名前の取得が上限に達しても、チェックインの確認は止めない: %v", err)
	}
	if _, src, err := g.Nearby(ctx, nearbyReq, FeatureExplore, false); err != nil || src != SourceGoogle {
		t.Errorf("名前の取得が上限に達しても、検索はダミーに変えない: %q %v", src, err)
	}
}

func TestGatewayDetailsKeepOneUserFromUsingUpTheLimit(t *testing.T) {
	g, _ := newGateway(t, stubDetails{}, 100, time.Now())
	g.DetailsDailyLimit = 30
	alice := auth.WithUser(context.Background(), auth.User{UID: "alice"})
	bob := auth.WithUser(context.Background(), auth.User{UID: "bob"})

	for i := range 3 {
		if _, _, err := g.PlaceLocation(alice, "a"); err != nil {
			t.Fatalf("%d回目: %v", i+1, err)
		}
	}
	if _, _, err := g.PlaceLocation(alice, "a"); !errors.Is(err, ErrDailyLimit) {
		t.Errorf("位置の確認は全体の10分の1で止める: %v", err)
	}
	if _, _, err := g.PlaceLocation(bob, "a"); err != nil {
		t.Errorf("ほかの利用者は止めない: %v", err)
	}

	for i := range 10 {
		if _, err := g.PlaceName(alice, "a", FeatureLogs); err != nil {
			t.Fatalf("%d回目: %v", i+1, err)
		}
	}
	if _, err := g.PlaceName(alice, "a", FeatureLogs); !errors.Is(err, ErrDailyLimit) {
		t.Errorf("名前の取得は全体の3分の1で止める: %v", err)
	}
}

func TestGatewayGivesNoDummySpotsForCheckin(t *testing.T) {
	g, _ := newGateway(t, failing{}, 100, time.Now())
	if _, _, err := g.Nearby(context.Background(), nearbyReq, FeatureCheckin, false); err == nil {
		t.Fatal("本物の API が失敗したのにチェックインの候補をダミーで返した")
	}
	// キーがない開発環境では、チェックインの候補もダミーで返す
	g.Primary = nil
	if ps, src, err := g.Nearby(context.Background(), nearbyReq, FeatureCheckin, false); err != nil || src != SourceMock || len(ps) == 0 {
		t.Fatalf("got %d %q %v", len(ps), src, err)
	}
}

func TestGatewayStopsAtDailyLimitAcrossInstancesAndResetsNextDay(t *testing.T) {
	now := time.Date(2026, 11, 7, 3, 0, 0, 0, time.UTC)
	primary := &counting{}
	g, st := newGateway(t, primary, 2, now)
	for range 2 {
		if _, src, err := g.Nearby(context.Background(), nearbyReq, FeatureExplore, false); err != nil || src != SourceGoogle {
			t.Fatalf("source = %q (%v)", src, err)
		}
	}
	if _, _, err := g.Nearby(context.Background(), nearbyReq, FeatureExplore, false); !errors.Is(err, ErrDailyLimit) {
		t.Fatalf("上限に達したらダミーではなくエラーを返す: %v", err)
	}
	if primary.calls != 2 {
		t.Errorf("本物を呼んだ回数 = %d", primary.calls)
	}

	// インスタンスが入れ替わっても、保存先が同じなら数え直さない
	next := &Gateway{Primary: primary, Fallback: g.Fallback, Log: g.Log, Usage: st, DailyLimit: 2, Now: g.Now}
	if _, _, err := next.Text(context.Background(), "x", 1, FeatureAlternatives, false); !errors.Is(err, ErrDailyLimit) {
		t.Errorf("別のインスタンスが上限を超えて呼んだ: %v", err)
	}

	// JST の日付が変わると数え直す
	next.Now = func() time.Time { return now.Add(24 * time.Hour) }
	if _, src, _ := next.Nearby(context.Background(), nearbyReq, FeatureExplore, false); src != SourceGoogle {
		t.Errorf("日付が変わっても止まったまま: %q", src)
	}
}

func TestGatewayCountsByFeatureAndMode(t *testing.T) {
	now := time.Date(2026, 11, 7, 3, 0, 0, 0, time.UTC)
	ctx := context.Background()

	g, st := newGateway(t, &counting{}, 100, now)
	_, _, _ = g.Nearby(ctx, nearbyReq, FeatureCheckin, false)
	_, _, _ = g.Text(ctx, "x", 1, FeatureAlternatives, false)
	_, _, _ = g.Nearby(ctx, nearbyReq, FeatureExplore, true) // mock=1 は本物を呼ばないので数えない
	days, _ := st.Days(ctx, []string{"2026-11-07"})
	if days[0].Real["nearby.checkin"] != 1 || days[0].Real["text.alternatives"] != 1 || len(days[0].Real) != 2 || len(days[0].Simulated) != 0 {
		t.Errorf("本物の回数: %+v", days[0])
	}

	// キーがないときは、本物なら呼んでいた回数として数える
	g, st = newGateway(t, nil, 100, now)
	_, _, _ = g.Nearby(ctx, nearbyReq, FeatureExplore, false)
	_, _, _ = g.Nearby(ctx, nearbyReq, FeatureExplore, true)
	days, _ = st.Days(ctx, []string{"2026-11-07"})
	if days[0].Simulated["nearby.explore"] != 1 || len(days[0].Real) != 0 {
		t.Errorf("試算の回数: %+v", days[0])
	}
}

func TestGatewayLimitsEachUser(t *testing.T) {
	g, _ := newGateway(t, &counting{}, 100, time.Now())
	g.UserDailyLimit = 1
	alice := auth.WithUser(context.Background(), auth.User{UID: "alice"})
	bob := auth.WithUser(context.Background(), auth.User{UID: "bob"})

	for _, c := range []struct {
		ctx     context.Context
		limited bool
	}{{alice, false}, {alice, true}, {bob, false}} {
		if _, _, err := g.Nearby(c.ctx, nearbyReq, FeatureExplore, false); errors.Is(err, ErrDailyLimit) != c.limited {
			t.Errorf("limited = %v のはずが %v", c.limited, err)
		}
	}
}

type counting struct{ calls int }

func (c *counting) SearchNearby(context.Context, NearbyRequest) ([]Place, error) {
	c.calls++
	return []Place{}, nil
}

func (c *counting) SearchText(context.Context, string, int) ([]Place, error) {
	c.calls++
	return []Place{}, nil
}

type failing struct{}

func (failing) SearchNearby(context.Context, NearbyRequest) ([]Place, error) {
	return nil, ErrDailyLimit
}

// stubDetails は全ての呼び出しが成功する本物の API の代わり。
type stubDetails struct{}

func (stubDetails) SearchNearby(context.Context, NearbyRequest) ([]Place, error) {
	return []Place{}, nil
}
func (stubDetails) SearchText(context.Context, string, int) ([]Place, error) { return []Place{}, nil }
func (stubDetails) LocatePlace(context.Context, string) (Place, error) {
	return Place{ID: "x", Name: "寺"}, nil
}
func (stubDetails) GetPlace(_ context.Context, id, _ string) (Place, error) {
	return Place{ID: id, Name: "寺"}, nil
}

func (failing) SearchText(context.Context, string, int) ([]Place, error) { return nil, ErrDailyLimit }

func (failing) LocatePlace(context.Context, string) (Place, error) {
	return Place{}, errors.New("Places API エラー 500")
}

func (failing) GetPlace(context.Context, string, string) (Place, error) {
	return Place{}, errors.New("Places API エラー 500")
}

func (*counting) GetPlace(context.Context, string, string) (Place, error) {
	return Place{}, ErrPlaceNotFound
}

func (*counting) LocatePlace(context.Context, string) (Place, error) {
	return Place{}, ErrPlaceNotFound
}

func TestGenreFilter(t *testing.T) {
	inc, exc, err := GenreFilter([]string{"nature", "worship"})
	if err != nil || !slices.Contains(inc, "park") || !slices.Contains(inc, "shinto_shrine") || len(exc) != 0 {
		t.Errorf("%v %v %v", inc, exc, err)
	}
	inc, exc, err = GenreFilter(nil)
	if err != nil || len(inc) != 0 || len(exc) != 0 {
		t.Errorf("指定なしは絞らない: %v %v %v", inc, exc, err)
	}
	inc, exc, err = GenreFilter([]string{GenreOther, "nature"})
	if err != nil || len(inc) != 0 || slices.Contains(exc, "park") || !slices.Contains(exc, "restaurant") {
		t.Errorf("その他: %v %v %v", inc, exc, err)
	}
	if _, _, err := GenreFilter([]string{"nope"}); err == nil {
		t.Error("不明なジャンルを受け付けた")
	}
}

func TestIsVisitable(t *testing.T) {
	cases := []struct {
		name  string
		place Place
		want  bool
	}{
		{"喫茶店", Place{Types: []string{"cafe", "food", "point_of_interest"}}, true},
		{"町の商店", Place{Types: []string{"point_of_interest", "store", "establishment"}}, true},
		{"種類の細かくない祠", Place{Types: []string{"place_of_worship", "point_of_interest"}}, true},
		{"種類のない会社", Place{Types: []string{"point_of_interest", "establishment"}, UserRatingCount: 1}, false},
		{"会社の事務所", Place{PrimaryType: "corporate_office", Types: []string{"corporate_office", "point_of_interest"}, UserRatingCount: 99}, false},
		{"見に行く人の多い会社", Place{PrimaryType: "corporate_office", Types: []string{"corporate_office", "point_of_interest"}, UserRatingCount: 100}, true},
		{"マンション", Place{PrimaryType: "apartment_building", Types: []string{"apartment_building", "service"}}, false},
		{"バス停", Place{PrimaryType: "bus_stop", Types: []string{"bus_stop", "transit_station"}}, false},
		{"口コミの多い駐車場", Place{PrimaryType: "parking_lot", Types: []string{"parking_lot", "parking"}, UserRatingCount: 300}, false},
		{"口コミの多い病院", Place{PrimaryType: "hospital", Types: []string{"hospital"}, UserRatingCount: 1200}, false},
	}
	for _, c := range cases {
		if got := IsVisitable(c.place); got != c.want {
			t.Errorf("%s: got %v", c.name, got)
		}
	}
}

func TestNonVisitablePrimaryTypesFitInOneRequest(t *testing.T) {
	// Nearby Search は1つの条件に50種類まで受け付ける
	if n := len(NonVisitablePrimaryTypes); n == 0 || n > 50 {
		t.Fatalf("種類の数: %d", n)
	}
	for _, typ := range NonVisitablePrimaryTypes {
		if IsVisitable(Place{PrimaryType: typ, Types: []string{typ}}) {
			t.Errorf("%s は除く種類なのに訪れられる場所と判定される", typ)
		}
	}
	for _, typs := range genreTypes {
		for _, typ := range typs {
			if slices.Contains(NonVisitablePrimaryTypes, typ) {
				t.Errorf("ジャンルの種類 %s を除いている", typ)
			}
		}
	}
}

func TestGoogleClientSendsExcludedPrimaryTypes(t *testing.T) {
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		_, _ = io.WriteString(w, `{"places":[]}`)
	}))
	defer srv.Close()

	c := NewGoogleClient("KEY")
	c.baseURL = srv.URL
	if _, err := c.SearchNearby(context.Background(), NearbyRequest{Lat: 35, Lng: 135, RadiusMeters: 300, ExcludedPrimaryTypes: []string{"parking"}}); err != nil {
		t.Fatal(err)
	}
	if got, _ := gotBody["excludedPrimaryTypes"].([]any); len(got) != 1 || got[0] != "parking" {
		t.Errorf("excludedPrimaryTypes: %v", gotBody)
	}
}

func TestIsPublicStop(t *testing.T) {
	if !IsPublicStop(Place{PrimaryType: "bus_stop", Types: []string{"bus_stop"}}) || !IsPublicStop(Place{Types: []string{"train_station", "transit_station"}}) {
		t.Error("バス停と駅は停留所")
	}
	if IsPublicStop(Place{PrimaryType: "parking_lot", Types: []string{"parking_lot"}}) || IsPublicStop(Place{Types: []string{"point_of_interest"}}) {
		t.Error("駐車場と種類のない場所は停留所でない")
	}
	if slices.Contains(NonVisitablePrimaryTypes, "bus_stop") {
		t.Error("バス停を検索の条件で除くと、名前を Gemini に尋ねられない")
	}
}

func TestExploreTypes(t *testing.T) {
	// Nearby Search は1つの条件に50種類まで
	if n := len(ExploreTypes); n == 0 || n > 50 {
		t.Fatalf("%d 種類", n)
	}
	seen := map[string]bool{}
	for _, ty := range ExploreTypes {
		if seen[ty] {
			t.Errorf("重なり: %s", ty)
		}
		seen[ty] = true
		if !slices.Contains(visitableTypes, ty) && !slices.Contains(publicStopTypes, ty) {
			t.Errorf("訪れられる種類でも停留所でもない: %s", ty)
		}
	}
	// 検索の条件に使えない種類は入れない（入れると Places API がエラーを返す）
	for _, ng := range []string{"food", "landmark", "natural_feature", "place_of_worship", "town_square"} {
		if seen[ng] {
			t.Errorf("検索の条件に使えない種類: %s", ng)
		}
	}
}

// photoStub は写真を返す本物の API の代わり。
type photoStub struct {
	stubDetails
	photos int
	fail   map[string]bool
	asked  *[]string
}

func (s photoStub) GetPlace(_ context.Context, id, mask string) (Place, error) {
	p := Place{ID: id}
	if mask == DetailsPhotosMask {
		for i := range s.photos {
			p.Photos = append(p.Photos, Photo{
				Name: fmt.Sprintf("places/%s/photos/%d", id, i), Width: 800, Height: 600,
				Attributions: []PhotoAttribution{{Name: "撮影者", URI: "https://maps.google.com/maps/contrib/1"}},
			})
		}
	}
	return p, nil
}

func (s photoStub) PhotoURI(_ context.Context, name string, maxWidth int) (string, error) {
	*s.asked = append(*s.asked, name)
	if s.fail[name] {
		return "", errors.New("boom")
	}
	return fmt.Sprintf("https://lh3.googleusercontent.com/%s=w%d", name, maxWidth), nil
}

func TestPlacePhotos(t *testing.T) {
	var asked []string
	g, st := newGateway(t, photoStub{photos: 6, fail: map[string]bool{"places/p/photos/1": true}, asked: &asked}, 100, time.Now())
	g.DetailsDailyLimit = 100
	g.PhotosEnabled = true
	photos, src, err := g.PlacePhotos(context.Background(), "p", MaxPhotos)
	if err != nil || src != SourceGoogle {
		t.Fatalf("%v %v", src, err)
	}
	// 1枚読めなくても、ほかの写真で上限まで埋める
	if len(photos) != MaxPhotos || photos[0].URL == "" || photos[0].Attributions[0].Name != "撮影者" {
		t.Errorf("写真: %+v", photos)
	}
	for _, p := range photos {
		if p.Name == "places/p/photos/1" {
			t.Errorf("読めなかった写真を返している")
		}
	}
	if len(asked) != MaxPhotos+1 {
		t.Errorf("上限を超えて画像を読んでいる: %v", asked)
	}
	// 写真の一覧と画像の URL を、別の区分で数える
	days, err := st.Days(context.Background(), []string{usage.DateOf(time.Now())})
	if err != nil || len(days) != 1 {
		t.Fatalf("%v %v", days, err)
	}
	day := days[0]
	if day.Real[usage.Key(usage.KindDetailsPhotos, FeaturePhotos)] != 1 || day.Real[usage.Key(usage.KindPhoto, FeaturePhotos)] != MaxPhotos+1 {
		t.Errorf("回数: %+v %v", day.Real, err)
	}
}

func TestPlacePhotosAreOffByDefault(t *testing.T) {
	// 費用が高いため、PLACES_PHOTOS=on にするまで Places API を呼ばない
	var asked []string
	g, st := newGateway(t, photoStub{photos: 3, asked: &asked}, 100, time.Now())
	g.DetailsDailyLimit = 100
	photos, _, err := g.PlacePhotos(context.Background(), "p", MaxPhotos)
	if err != nil || len(photos) != 0 || len(asked) != 0 {
		t.Errorf("%v %v %v", photos, asked, err)
	}
	days, _ := st.Days(context.Background(), []string{usage.DateOf(time.Now())})
	if len(days) == 1 && len(days[0].Real) != 0 {
		t.Errorf("回数を数えている: %v", days[0].Real)
	}
}

func TestPlacePhotosWithoutKeyOrForMockPlaces(t *testing.T) {
	g, _ := newGateway(t, nil, 100, time.Now())
	if photos, src, err := g.PlacePhotos(context.Background(), "p", MaxPhotos); err != nil || src != SourceMock || len(photos) != 0 {
		t.Errorf("キーなし: %v %v %v", photos, src, err)
	}
	var asked []string
	g, _ = newGateway(t, photoStub{photos: 2, asked: &asked}, 100, time.Now())
	g.PhotosEnabled = true
	if photos, _, err := g.PlacePhotos(context.Background(), "mock_01", MaxPhotos); err != nil || len(photos) != 0 || len(asked) != 0 {
		t.Errorf("ダミーの場所: %v %v %v", photos, asked, err)
	}
}

func TestGooglePhotoURI(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/places/p/photos/a/media" || r.URL.Query().Get("skipHttpRedirect") != "true" || r.Header.Get("X-Goog-Api-Key") != "k" {
			http.Error(w, "bad", 400)
			return
		}
		_, _ = w.Write([]byte(`{"name":"places/p/photos/a/media","photoUri":"https://lh3.googleusercontent.com/x"}`))
	}))
	defer srv.Close()
	c := NewGoogleClient("k")
	c.baseURL = srv.URL
	uri, err := c.PhotoURI(context.Background(), "places/p/photos/a", 960)
	if err != nil || uri != "https://lh3.googleusercontent.com/x" {
		t.Errorf("%q %v", uri, err)
	}
}

func TestGatewayCheckinSearchHasItsOwnLimit(t *testing.T) {
	g, _ := newGateway(t, stubDetails{}, 2, time.Now())
	g.UserDailyLimit = 2
	alice := auth.WithUser(context.Background(), auth.User{UID: "alice"})
	for range 2 {
		if _, _, err := g.Nearby(alice, nearbyReq, FeatureExplore, false); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := g.Nearby(alice, nearbyReq, FeatureExplore, false); !errors.Is(err, ErrDailyLimit) {
		t.Fatalf("地図の検索は上限で止まる: %v", err)
	}
	// 地図の検索で上限に達しても、チェックインの候補は探せる
	if _, src, err := g.Nearby(alice, nearbyReq, FeatureCheckin, false); err != nil || src != SourceGoogle {
		t.Errorf("チェックインの候補: %q %v", src, err)
	}
}

func TestGatewayLoosensLimitsUntilTheTestDate(t *testing.T) {
	now := time.Date(2026, 11, 9, 3, 0, 0, 0, time.UTC) // JST 11/9
	g, _ := newGateway(t, &counting{}, 1, now)
	g.UserDailyLimit = 1
	g.TestUntil, g.TestDailyLimit = "2026-11-09", 3
	alice := auth.WithUser(context.Background(), auth.User{UID: "alice"})
	for i := range 3 {
		if _, _, err := g.Nearby(alice, nearbyReq, FeatureExplore, false); err != nil {
			t.Fatalf("テストの期間は1人あたりの上限をなくす（%d回目）: %v", i+1, err)
		}
	}
	if _, _, err := g.Nearby(alice, nearbyReq, FeatureExplore, false); !errors.Is(err, ErrDailyLimit) {
		t.Errorf("テストの期間も、全体の歯止めは残す: %v", err)
	}
	// 期間を過ぎると元の上限に戻る
	g.Now = func() time.Time { return now.Add(24 * time.Hour) }
	if _, _, err := g.Nearby(alice, nearbyReq, FeatureExplore, false); err != nil {
		t.Fatal(err)
	}
	if _, _, err := g.Nearby(alice, nearbyReq, FeatureExplore, false); !errors.Is(err, ErrDailyLimit) {
		t.Errorf("期間を過ぎたら元の上限: %v", err)
	}
}
