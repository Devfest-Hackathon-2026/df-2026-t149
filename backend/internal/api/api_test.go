package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/assistant"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/auth"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
)

var discard = slog.New(slog.NewTextHandler(io.Discard, nil))

// stubClient は本物の Places API の代わり。
type stubClient struct {
	nearby []places.Place
	text   []places.Place
	err    error
	// gotNearby があれば、Nearby Search に渡された条件を入れる
	gotNearby *places.NearbyRequest
	// nearbyCalls があれば、同時に呼ばれる Nearby Search の条件を全て記録する
	nearbyCalls *nearbyLog
	// details は Place Details が返す場所
	details map[string]places.Place
	// gotDetails があれば、Place Details の呼び出しを入れる
	gotDetails *detailsCalls
}

func (c stubClient) SearchNearby(_ context.Context, req places.NearbyRequest) ([]places.Place, error) {
	if c.gotNearby != nil {
		*c.gotNearby = req
	}
	if c.nearbyCalls != nil {
		c.nearbyCalls.add(req)
	}
	return c.nearby, c.err
}

type nearbyLog struct {
	mu   sync.Mutex
	reqs []places.NearbyRequest
}

func (l *nearbyLog) add(r places.NearbyRequest) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.reqs = append(l.reqs, r)
}

func (l *nearbyLog) all() []places.NearbyRequest {
	l.mu.Lock()
	defer l.mu.Unlock()
	return slices.Clone(l.reqs)
}

// failFirstNearby は最初の Nearby Search だけ失敗する
type failFirstNearby struct {
	stubClient
	calls atomic.Int32
}

func (c *failFirstNearby) SearchNearby(ctx context.Context, req places.NearbyRequest) ([]places.Place, error) {
	if c.calls.Add(1) == 1 {
		return nil, errors.New("boom")
	}
	return c.stubClient.SearchNearby(ctx, req)
}

// failNearby は Nearby Search だけ必ず失敗する
type failNearby struct{ stubClient }

func (c *failNearby) SearchNearby(context.Context, places.NearbyRequest) ([]places.Place, error) {
	return nil, errors.New("boom")
}

func (c stubClient) SearchText(context.Context, string, int) ([]places.Place, error) {
	return c.text, c.err
}

func (c stubClient) LocatePlace(_ context.Context, query string) (places.Place, error) {
	if c.err != nil {
		return places.Place{}, c.err
	}
	if len(c.text) == 0 {
		return places.Place{}, places.ErrPlaceNotFound
	}
	return c.text[0], nil
}

func (c stubClient) GetPlace(_ context.Context, id, fieldMask string) (places.Place, error) {
	if c.gotDetails != nil {
		c.gotDetails.add(id, fieldMask)
	}
	if c.err != nil {
		return places.Place{}, c.err
	}
	p, ok := c.details[id]
	if !ok {
		return places.Place{}, places.ErrPlaceNotFound
	}
	return p, nil
}

// detailsCalls は Place Details の呼び出しを記録する。思い出ログの名前は並列に読まれる。
type detailsCalls struct {
	mu    sync.Mutex
	ids   []string
	masks []string
}

func (c *detailsCalls) add(id, mask string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.ids = append(c.ids, id)
	c.masks = append(c.masks, mask)
}

func newTestServer(t *testing.T, primary places.Client) *httptest.Server {
	t.Helper()
	return newTestServerWithModel(t, primary, nil)
}

// newTestServerWithModel は Geminiちゃんの本物の代わりに model を使う。nil なら簡易版だけで答える。
func newTestServerWithModel(t *testing.T, primary places.Client, model assistant.Model) *httptest.Server {
	t.Helper()
	mock, err := places.NewMockClient()
	if err != nil {
		t.Fatal(err)
	}
	st := store.NewMemoryStore()
	now := func() time.Time { return time.Date(2026, 11, 8, 3, 12, 45, 0, time.UTC) }
	s := &Server{
		Places: &places.Gateway{Primary: primary, Fallback: mock, Log: discard, Usage: st, DailyLimit: 100, UserDailyLimit: 100, DetailsDailyLimit: 100, Now: now},
		Assistant: &assistant.Service{Primary: model, Fallback: assistant.Fake{}, Log: discard, Usage: st,
			DailyLimit: 100, UserDailyLimit: 4, Now: now},
		Scorer:   places.DefaultScorer,
		Store:    st,
		Verifier: auth.FakeVerifier{},
		Log:      discard,
		Now:      now,

		ExposeUsage: true,
	}
	ts := httptest.NewServer(s.Handler())
	t.Cleanup(ts.Close)
	return ts
}

func call(t *testing.T, ts *httptest.Server, method, path, token, body string) (int, map[string]any) {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req, _ := http.NewRequest(method, ts.URL+path, r)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("%s %s: Content-Type = %q", method, path, ct)
	}
	var out map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatalf("%s %s: decode: %v", method, path, err)
	}
	return resp.StatusCode, out
}

func errCode(m map[string]any) string {
	e, _ := m["error"].(map[string]any)
	c, _ := e["code"].(string)
	return c
}

// --- アプリとの約束（パスとデータの形） ---

// アプリに同梱したダミーデータ（app/assets/mock/）は、Dart のサーバーを mock=1 で呼んで作ったもの
// （app/tool/update_mock_assets.dart）。Go が同じリクエストに同じ JSON を返せば、アプリはそのまま受け取れる。
func TestMatchesAppBundledMock(t *testing.T) {
	appMock := filepath.Join("..", "..", "..", "app", "assets", "mock")
	if _, err := os.Stat(appMock); err != nil {
		t.Skipf("アプリのダミーデータがないので飛ばす: %v", err)
	}
	ts := newTestServer(t, nil)
	cases := []struct {
		file, path string
	}{
		{"explore.json", "/api/explore?lat=34.693&lng=135.19&radius=5000&mock=1"},
		{"alternatives.json", "/api/alternatives?q=" + "%E3%83%80%E3%83%9F%E3%83%BC" + "&radius=10000&mock=1"}, // q=ダミー
	}
	for _, c := range cases {
		t.Run(c.file, func(t *testing.T) {
			b, err := os.ReadFile(filepath.Join(appMock, c.file))
			if err != nil {
				t.Fatal(err)
			}
			var want map[string]any
			if err := json.Unmarshal(b, &want); err != nil {
				t.Fatal(err)
			}
			delete(want, "center") // 作る道具が後から足した項目
			code, got := call(t, ts, "GET", c.path, "alice", "")
			if code != 200 {
				t.Fatalf("status %d %v", code, got)
			}
			if !reflect.DeepEqual(got, want) {
				g, _ := json.MarshalIndent(got, "", "  ")
				w, _ := json.MarshalIndent(want, "", "  ")
				t.Errorf("アプリのダミーデータと違う\n--- got\n%s\n--- want\n%s", g, w)
			}
		})
	}
}

func TestHealth(t *testing.T) {
	code, body := call(t, newTestServer(t, nil), "GET", "/api/health", "", "")
	if code != 200 || body["ok"] != true || body["places"] != "mock" {
		t.Fatalf("got %d %v", code, body)
	}
}

func TestExplore(t *testing.T) {
	ts := newTestServer(t, nil)
	// アプリが送る半径はどれも受け付ける
	for _, radius := range []string{"1500", "3000", "5000", ""} {
		code, body := call(t, ts, "GET", "/api/explore?lat=34.693&lng=135.19&radius="+radius, "alice", "")
		if code != 200 || body["source"] != "mock" || len(body["places"].([]any)) == 0 {
			t.Fatalf("radius=%q: %d %v", radius, code, body)
		}
	}
	for _, q := range []string{"lng=135", "lat=abc&lng=135", "lat=91&lng=135"} {
		code, body := call(t, ts, "GET", "/api/explore?"+q, "alice", "")
		if code != 400 || errCode(body) != "bad_request" {
			t.Errorf("%s: got %d %v", q, code, body)
		}
	}
}

func TestExploreDoesNotFallBackToMock(t *testing.T) {
	// 本物の Places API が失敗しても、架空の場所を返さずに、探せなかったことを返す
	ts := newTestServer(t, stubClient{err: errors.New("boom")})
	code, body := call(t, ts, "GET", "/api/explore?lat=34.693&lng=135.19", "alice", "")
	if code != 503 || errCode(body) != "places_unavailable" {
		t.Fatalf("got %d %v", code, body)
	}
}

func TestExploreReportsTheDailyLimit(t *testing.T) {
	ts := newTestServer(t, stubClient{nearby: []places.Place{}})
	var code int
	var body map[string]any
	// 1回の検索で呼ぶのは1回（半径 1500 m）。上限は 100 回
	for range 101 {
		code, body = call(t, ts, "GET", "/api/explore?lat=34.693&lng=135.19", "alice", "")
	}
	if code != 429 || errCode(body) != "daily_limit" {
		t.Errorf("上限に達したことを返す: %d %v", code, body)
	}
}

func TestExploreGoogleSource(t *testing.T) {
	rating := 4.2
	ts := newTestServer(t, stubClient{nearby: []places.Place{
		{ID: "a", Name: "有名", Types: []string{"park"}, UserRatingCount: 9000, Rating: &rating},
		{ID: "b", Name: "無名", Types: []string{"park"}, UserRatingCount: 0},
	}})
	code, body := call(t, ts, "GET", "/api/explore?lat=35&lng=135", "alice", "")
	if code != 200 || body["source"] != "google" {
		t.Fatalf("got %d %v", code, body)
	}
	ps := body["places"].([]any)
	first := ps[0].(map[string]any)
	if first["id"] != "b" || first["obscurity"] != 100.0 || first["title"] != "untrodden" {
		t.Errorf("未知度の高い順になっていない: %v", ps)
	}
	if _, ok := first["rating"]; ok {
		t.Errorf("評価がない場所は rating を省く: %v", first)
	}
	if ps[1].(map[string]any)["title"] != "famous" {
		t.Errorf("9000件は famous: %v", ps[1])
	}
}

func TestAlternativesOriginNotFound(t *testing.T) {
	ts := newTestServer(t, stubClient{text: []places.Place{}})
	code, body := call(t, ts, "GET", "/api/alternatives?q=nowhere", "alice", "")
	if code != 404 || errCode(body) != "origin_not_found" {
		t.Fatalf("got %d %v", code, body)
	}
	if code, body := call(t, ts, "GET", "/api/alternatives?q=", "alice", ""); code != 400 || errCode(body) != "bad_request" {
		t.Errorf("q なし: got %d %v", code, body)
	}
}

func TestUnknownRouteAndPlanB(t *testing.T) {
	ts := newTestServer(t, nil)
	if code, body := call(t, ts, "GET", "/api/nothing", "", ""); code != 404 || errCode(body) != "not_found" {
		t.Errorf("未定義のパス: %d %v", code, body)
	}
	if code, body := call(t, ts, "GET", "/api/gacha?lat=1&lng=1", "", ""); code != 501 || errCode(body) != "not_implemented" {
		t.Errorf("ガチャ: %d %v", code, body)
	}
}

func TestCORS(t *testing.T) {
	ts := newTestServer(t, nil)
	req, _ := http.NewRequest("OPTIONS", ts.URL+"/api/checkins", nil)
	req.Header.Set("Origin", "http://localhost:54321")
	req.Header.Set("Access-Control-Request-Method", "POST")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 204 || resp.Header.Get("Access-Control-Allow-Origin") != "http://localhost:54321" ||
		!strings.Contains(resp.Header.Get("Access-Control-Allow-Headers"), "Authorization") {
		t.Errorf("localhost: %d %v", resp.StatusCode, resp.Header)
	}

	req, _ = http.NewRequest("GET", ts.URL+"/api/health", nil)
	req.Header.Set("Origin", "https://evil.example")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.Header.Get("Access-Control-Allow-Origin") != "" {
		t.Errorf("ほかのオリジンを許している")
	}
}

// --- チェックインと思い出ログ ---

func TestCheckinRequiresAuth(t *testing.T) {
	ts := newTestServer(t, nil)
	for _, c := range []struct{ method, path, body string }{
		{"POST", "/api/checkins", `{"placeId":"mock_01"}`},
		{"POST", "/api/logs", `{}`},
		{"GET", "/api/logs", ""},
	} {
		code, body := call(t, ts, c.method, c.path, "", c.body)
		if code != 401 || errCode(body) != "unauthenticated" {
			t.Errorf("%s %s: got %d %v", c.method, c.path, code, body)
		}
	}
}

func TestCheckinAndLogFlow(t *testing.T) {
	ts := newTestServer(t, nil)

	// alice が1人目
	code, body := call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	if code != 200 || body["order"] != 1.0 || body["isNew"] != true {
		t.Fatalf("alice: %d %v", code, body)
	}
	// 2回目は1回目の順番のまま、isNew=false
	code, body = call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	if code != 200 || body["order"] != 1.0 || body["isNew"] != false {
		t.Fatalf("alice 2回目: %d %v", code, body)
	}
	// bob が2人目
	if _, body := call(t, ts, "POST", "/api/checkins", "bob", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`); body["order"] != 2.0 {
		t.Fatalf("bob: %v", body)
	}
	// 訪問者数
	if code, body := call(t, ts, "GET", "/api/places/mock_01/visitors", "carol", ""); code != 200 || body["visitorCount"] != 2.0 {
		t.Errorf("visitors: %d %v", code, body)
	}
	if _, body := call(t, ts, "GET", "/api/places/never/visitors", "carol", ""); body["visitorCount"] != 0.0 {
		t.Errorf("誰も来ていない場所は0: %v", body)
	}

	// 思い出ログ。order と createdAt は偽っても無視される
	logBody := `{"placeId":"mock_01","verdict":"miss","comment":" 閉まってた ",` +
		`"order":99,"createdAt":"1999-01-01T00:00:00.000"}`
	code, body = call(t, ts, "POST", "/api/logs", "bob", logBody)
	if code != 201 || body["order"] != 2.0 || body["createdAt"] != "2026-11-08T03:12:45Z" || body["comment"] != "閉まってた" {
		t.Fatalf("addLog: %d %v", code, body)
	}
	if _, ok := body["photoPath"]; ok {
		t.Errorf("写真がなければ photoPath を省く: %v", body)
	}
	if id, _ := body["id"].(string); !strings.HasPrefix(id, "lg_") {
		t.Errorf("id = %v", body["id"])
	}

	// 一覧は本人の分だけ、新しい順
	call(t, ts, "POST", "/api/checkins", "bob", `{"placeId":"mock_02","lat":34.69,"lng":135.19}`)
	call(t, ts, "POST", "/api/logs", "bob", `{"placeId":"mock_02","verdict":"hit"}`)
	code, body = call(t, ts, "GET", "/api/logs", "bob", "")
	logs := body["logs"].([]any)
	if code != 200 || len(logs) != 2 || logs[0].(map[string]any)["placeId"] != "mock_02" {
		t.Fatalf("listLogs: %d %v", code, body)
	}
	if logs[0].(map[string]any)["placeName"] != "路地裏の古書喫茶" {
		t.Errorf("place ID から読んだ名前を返していない: %v", logs[0])
	}
	if _, body := call(t, ts, "GET", "/api/logs", "alice", ""); len(body["logs"].([]any)) != 0 {
		t.Errorf("alice の一覧に bob の記録が出ている: %v", body)
	}
}

func TestLogValidation(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	long := strings.Repeat("あ", 141)
	cases := []struct {
		name, body, code string
		status           int
	}{
		{"チェックインしていない", `{"placeId":"mock_02","verdict":"hit"}`, "not_checked_in", 400},
		{"verdict が不正", `{"placeId":"mock_01","verdict":"meh"}`, "bad_request", 400},
		{"一言が長すぎる", `{"placeId":"mock_01","verdict":"hit","comment":"` + long + `"}`, "bad_request", 400},
		{"他人の写真のパス", `{"placeId":"mock_01","verdict":"hit","photoPath":"users/bob/a.jpg"}`, "permission_denied", 403},
		{"JSON でない", `not json`, "bad_request", 400},
	}
	for _, c := range cases {
		code, body := call(t, ts, "POST", "/api/logs", "alice", c.body)
		if code != c.status || errCode(body) != c.code {
			t.Errorf("%s: got %d %v", c.name, code, body)
		}
	}
	// 140文字ちょうどと、自分の写真のパスは通る
	ok := `{"placeId":"mock_01","verdict":"hit","comment":"` + strings.Repeat("あ", 140) +
		`","photoPath":"users/alice/logs/a.jpg"}`
	if code, body := call(t, ts, "POST", "/api/logs", "alice", ok); code != 201 || body["photoPath"] != "users/alice/logs/a.jpg" {
		t.Errorf("140文字: got %d %v", code, body)
	}

	for _, id := range []string{"", "a/b", "__x__"} {
		b, _ := json.Marshal(map[string]string{"placeId": id})
		if code, body := call(t, ts, "POST", "/api/checkins", "alice", string(b)); code != 400 || errCode(body) != "bad_request" {
			t.Errorf("placeId=%q: got %d %v", id, code, body)
		}
	}
}

// --- 圏外で保存した記録の送信 ---

func TestCheckinAndLogKeepVisitedAt(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19,"visitedAt":"2026-11-05T01:02:03.000Z"}`)

	// 日時は訪問したときの値になり、一覧も訪問した日時の新しい順に並ぶ
	call(t, ts, "POST", "/api/logs", "alice",
		`{"placeId":"mock_01","verdict":"hit","visitedAt":"2026-11-07T01:00:00.000Z"}`)
	code, body := call(t, ts, "POST", "/api/logs", "alice",
		`{"placeId":"mock_01","verdict":"hit","visitedAt":"2026-11-05T01:02:03.000Z"}`)
	if code != 201 || body["createdAt"] != "2026-11-05T01:02:03Z" {
		t.Fatalf("got %d %v", code, body)
	}
	_, body = call(t, ts, "GET", "/api/logs", "alice", "")
	logs := body["logs"].([]any)
	if logs[0].(map[string]any)["createdAt"] != "2026-11-07T01:00:00Z" {
		t.Errorf("訪問した日時の新しい順になっていない: %v", logs)
	}
}

func TestVisitedAtOutOfRangeFallsBackToServerTime(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	const serverTime = "2026-11-08T03:12:45Z"
	cases := map[string]struct{ visitedAt, want string }{
		"未来":        {"2026-11-08T03:18:46Z", serverTime},
		"時計のずれの範囲内": {"2026-11-08T03:17:45Z", "2026-11-08T03:17:45Z"},
		"古すぎる":      {"2026-10-09T03:12:44Z", serverTime},
		"保持期間の範囲内":  {"2026-10-09T03:12:46Z", "2026-10-09T03:12:46Z"},
		"読めない":      {"昨日", serverTime},
		"指定なし":      {"", serverTime},
	}
	for name, c := range cases {
		code, body := call(t, ts, "POST", "/api/logs", "alice",
			`{"placeId":"mock_01","verdict":"hit","visitedAt":"`+c.visitedAt+`"}`)
		if code != 201 || body["createdAt"] != c.want {
			t.Errorf("%s: got %d %v, want %s", name, code, body["createdAt"], c.want)
		}
	}
}

func TestResentLogIsNotDuplicated(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	call(t, ts, "POST", "/api/checkins", "bob", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	const body = `{"placeId":"mock_01","verdict":"hit","comment":"一回目","clientId":"abc_1"}`

	code, first := call(t, ts, "POST", "/api/logs", "alice", body)
	if code != 201 {
		t.Fatalf("got %d %v", code, first)
	}
	code, again := call(t, ts, "POST", "/api/logs", "alice", body)
	if code != 201 || again["id"] != first["id"] {
		t.Errorf("送り直しの応答が保存済みの記録と違う: %d %v / %v", code, again, first)
	}
	if _, list := call(t, ts, "GET", "/api/logs", "alice", ""); len(list["logs"].([]any)) != 1 {
		t.Errorf("二重に保存された: %v", list)
	}

	// 別の利用者が同じ clientId を使っても、別の記録になる
	if _, list := call(t, ts, "GET", "/api/logs", "bob", ""); len(list["logs"].([]any)) != 0 {
		t.Errorf("bob の一覧: %v", list)
	}
	if code, b := call(t, ts, "POST", "/api/logs", "bob", body); code != 201 || b["order"] != 2.0 {
		t.Errorf("bob: %d %v", code, b)
	}

	bad := `{"placeId":"mock_01","verdict":"hit","clientId":"a/b"}`
	if code, b := call(t, ts, "POST", "/api/logs", "alice", bad); code != 400 || errCode(b) != "bad_request" {
		t.Errorf("Firestore の ID に使えない clientId: %d %v", code, b)
	}
}

// --- チェックインの確認 ---

// placeAt35 は、テストの場所と同じ地点を指す現在地。緯度 35 度では経度 0.005 度が約 456 m、0.006 度が約 547 m になる
const placeAt35 = `"lat":35,"lng":135`

func TestCheckinVerifiesLocation(t *testing.T) {
	stub := stubClient{details: map[string]places.Place{"real": {ID: "real", Lat: 35, Lng: 135}}, gotDetails: &detailsCalls{}}
	ts := newTestServer(t, stub)

	cases := []struct {
		name, body string
		wantCode   int
		wantErr    string
	}{
		{"位置がない", `{"placeId":"real"}`, 400, "bad_request"},
		{"緯度が範囲の外", `{"placeId":"real","lat":91,"lng":135}`, 400, "bad_request"},
		{"500 m より遠い", `{"placeId":"real","lat":35,"lng":135.006}`, 400, "too_far"},
		{"存在しない場所", `{"placeId":"nowhere",` + placeAt35 + `}`, 404, "place_not_found"},
		{"ダミーの場所", `{"placeId":"mock_01",` + placeAt35 + `}`, 404, "place_not_found"},
	}
	for _, c := range cases {
		code, body := call(t, ts, "POST", "/api/checkins", "alice", c.body)
		if code != c.wantCode || errCode(body) != c.wantErr {
			t.Errorf("%s: got %d %v, want %d %s", c.name, code, body, c.wantCode, c.wantErr)
		}
	}
	if _, body := call(t, ts, "GET", "/api/places/real/visitors", "alice", ""); body["visitorCount"] != 0.0 {
		t.Errorf("断ったチェックインが人数に入っている: %v", body)
	}

	// 500 m 以内なら記録する
	code, body := call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"real","lat":35,"lng":135.005}`)
	if code != 200 || body["order"] != 1.0 {
		t.Fatalf("500 m 以内: %d %v", code, body)
	}
	if got := stub.gotDetails.masks[len(stub.gotDetails.masks)-1]; got != places.DetailsLocationMask {
		t.Errorf("確認には位置だけを読む: %s", got)
	}
	for _, id := range stub.gotDetails.ids {
		if id == "mock_01" {
			t.Error("ダミーの ID で Places API を呼んだ")
		}
	}

	// チェックイン済みなら、遠くからでも Places API を呼ばずに1回目の順番を返す
	before := len(stub.gotDetails.ids)
	code, body = call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"real","lat":0,"lng":0}`)
	if code != 200 || body["order"] != 1.0 || body["isNew"] != false || len(stub.gotDetails.ids) != before {
		t.Errorf("チェックイン済み: %d %v", code, body)
	}
}

func TestCheckinIsUnavailableWhenPlacesFails(t *testing.T) {
	ts := newTestServer(t, stubClient{err: errors.New("Places API エラー 500")})
	code, body := call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"real",`+placeAt35+`}`)
	if code != 503 || errCode(body) != "places_unavailable" {
		t.Errorf("記録を残して送り直せるよう 503 を返す: %d %v", code, body)
	}
}

func TestCheckinWithoutKeyAcceptsOnlyDummyPlaces(t *testing.T) {
	ts := newTestServer(t, nil)
	if code, body := call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":0,"lng":0}`); code != 200 {
		t.Errorf("ダミーは検索した地点の周りへ動くので距離を比べない: %d %v", code, body)
	}
	if code, body := call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"real","lat":0,"lng":0}`); code != 404 {
		t.Errorf("ダミーにない場所: %d %v", code, body)
	}
}

// --- 思い出ログの名前 ---

func TestLogNamesAreReadFromPlacesAPI(t *testing.T) {
	calls := &detailsCalls{}
	ts := newTestServer(t, stubClient{
		details: map[string]places.Place{
			"a": {ID: "a", Name: "小さな祠", Lat: 35, Lng: 135},
			"b": {ID: "b", Name: "", Lat: 35, Lng: 135},
		},
		gotDetails: calls,
	})
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"a",`+placeAt35+`}`)
	// 送られた名前を保存しない
	code, body := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","placeName":"偽の名前","verdict":"hit","comment":"1"}`)
	if code != 201 {
		t.Fatalf("got %d %v", code, body)
	}
	if _, ok := body["placeName"]; ok {
		t.Errorf("登録の応答には名前を入れない: %v", body)
	}
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","verdict":"hit","comment":"2"}`)

	calls.mu.Lock()
	calls.ids, calls.masks = nil, nil
	calls.mu.Unlock()
	_, list := call(t, ts, "GET", "/api/logs", "alice", "")
	logs := list["logs"].([]any)
	if len(logs) != 2 || logs[0].(map[string]any)["placeName"] != "小さな祠" || logs[1].(map[string]any)["placeName"] != "小さな祠" {
		t.Errorf("一覧: %v", logs)
	}
	if !reflect.DeepEqual(calls.ids, []string{"a"}) || calls.masks[0] != places.DetailsNameMask {
		t.Errorf("同じ場所の名前は1回だけ読む: %v %v", calls.ids, calls.masks)
	}
}

func TestLogListSurvivesNameFailure(t *testing.T) {
	mock, err := places.NewMockClient()
	if err != nil {
		t.Fatal(err)
	}
	st := store.NewMemoryStore()
	now := func() time.Time { return time.Date(2026, 11, 8, 3, 12, 45, 0, time.UTC) }
	s := &Server{
		// 上限が 0 なので、名前の読み込みは全て失敗する
		Places: &places.Gateway{Primary: stubClient{}, Fallback: mock, Log: discard, Usage: st, Now: now},
		Scorer: places.DefaultScorer, Store: st, Verifier: auth.FakeVerifier{}, Log: discard, Now: now,
	}
	ts := httptest.NewServer(s.Handler())
	t.Cleanup(ts.Close)
	if _, _, err := st.CheckIn(context.Background(), "alice", "a", now(), ""); err != nil {
		t.Fatal(err)
	}
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","verdict":"hit"}`)

	code, list := call(t, ts, "GET", "/api/logs", "alice", "")
	logs := list["logs"].([]any)
	if code != 200 || len(logs) != 1 {
		t.Fatalf("名前を読めなくても記録は返す: %d %v", code, list)
	}
	if _, ok := logs[0].(map[string]any)["placeName"]; ok {
		t.Errorf("読めなかった名前は省く: %v", logs[0])
	}
}

// --- ジャンルと地点の検索 ---

func TestExploreGenreBecomesNearbyTypes(t *testing.T) {
	var got places.NearbyRequest
	ts := newTestServer(t, stubClient{nearby: []places.Place{}, gotNearby: &got})

	call(t, ts, "GET", "/api/explore?lat=35&lng=135&genre=food", "alice", "")
	if !got.RankByDistance || !slices.Contains(got.IncludedTypes, "cafe") || !slices.Contains(got.IncludedTypes, "restaurant") || len(got.ExcludedTypes) != 0 {
		t.Errorf("飲食: %+v", got)
	}

	call(t, ts, "GET", "/api/explore?lat=35&lng=135&genre=other,food", "alice", "")
	if len(got.IncludedTypes) != 0 || slices.Contains(got.ExcludedTypes, "cafe") || !slices.Contains(got.ExcludedTypes, "park") {
		t.Errorf("その他は選んでいないジャンルを除く: %+v", got)
	}

	if code, body := call(t, ts, "GET", "/api/explore?lat=35&lng=135&genre=nope", "alice", ""); code != 400 {
		t.Errorf("不明なジャンル: %d %v", code, body)
	}
}

func TestExploreOmitsPlacesThatCannotBeVisited(t *testing.T) {
	var got places.NearbyRequest
	ts := newTestServer(t, stubClient{gotNearby: &got, nearby: []places.Place{
		{ID: "company", Name: "株式会社 大興", Types: []string{"point_of_interest", "establishment"}, UserRatingCount: 1},
		{ID: "cafe", Name: "喫茶店", PrimaryType: "cafe", Types: []string{"cafe", "food"}, UserRatingCount: 3},
		{ID: "hq", Name: "本社", PrimaryType: "corporate_office", Types: []string{"corporate_office"}, UserRatingCount: 2000},
		{ID: "stop", Name: "中常三島", PrimaryType: "bus_stop", Types: []string{"bus_stop", "transit_station"}},
	}})

	_, body := call(t, ts, "GET", "/api/explore?lat=35&lng=135", "alice", "")
	ids := placeIDs(body)
	if !slices.Contains(got.ExcludedPrimaryTypes, "apartment_building") {
		t.Errorf("住宅を探す条件から除いていない: %+v", got)
	}
	if slices.Contains(ids, "company") || slices.Contains(ids, "stop") || !slices.Contains(ids, "cafe") || !slices.Contains(ids, "hq") {
		t.Errorf("訪れられる場所と、見に行く人の多い場所だけを返す: %v", ids)
	}

	// Geminiちゃんのおすすめも、訪れられない場所を候補にしない
	call(t, ts, "POST", "/api/assistant", "alice", `{"message":"近くの穴場を教えて","lat":35,"lng":135}`)
	if !slices.Contains(got.ExcludedPrimaryTypes, "apartment_building") {
		t.Errorf("Geminiちゃんの検索: %+v", got)
	}

	// チェックインの候補は、種類で絞らずに探し（最寄りを取りこぼさないため）、地図と同じく訪れられる場所を返す
	_, body = call(t, ts, "GET", "/api/explore?lat=35&lng=135&purpose=checkin", "alice", "")
	if ids := placeIDs(body); len(got.ExcludedPrimaryTypes) != 0 || slices.Contains(ids, "company") || !slices.Contains(ids, "cafe") {
		t.Errorf("チェックインの候補: %+v %v", got, ids)
	}
}

// 近くに訪れられる場所が1つもなければ、今いる場所が会社でもチェックインできるよう絞らずに返す
func TestCheckinFallsBackWhenNothingVisitable(t *testing.T) {
	ts := newTestServer(t, stubClient{nearby: []places.Place{
		{ID: "company", Name: "株式会社 大興", Types: []string{"point_of_interest", "establishment"}},
	}})
	_, body := call(t, ts, "GET", "/api/explore?lat=35&lng=135&purpose=checkin", "alice", "")
	if ids := placeIDs(body); !slices.Contains(ids, "company") {
		t.Errorf("チェックインの候補: %v", ids)
	}
}

// 停留所は訪れる場所ではないので返さない。名前の変わった停留所を Gemini に選ばせるのは、
// Places API の結果を Gemini に渡すことになるためやめた（D-036）
func TestExploreLeavesOutStops(t *testing.T) {
	stop := func(id, name string) places.Place {
		return places.Place{ID: id, Name: name, PrimaryType: "bus_stop", Types: []string{"bus_stop", "transit_station"}}
	}
	m := &stubModel{}
	ts := newTestServerWithModel(t, stubClient{nearby: []places.Place{
		stop("obake", "おばけ坂"),
		{ID: "company", Name: "株式会社 大興", Types: []string{"point_of_interest", "establishment"}},
	}}, m)

	_, body := call(t, ts, "GET", "/api/explore?lat=35&lng=135", "alice", "")
	if ids := placeIDs(body); len(ids) != 0 {
		t.Errorf("停留所と会社を返した: %v", ids)
	}
	if m.calls != 0 {
		t.Errorf("地図の検索で Gemini を %d 回呼んだ", m.calls)
	}
}

func placeIDs(body map[string]any) []string {
	ids := []string{}
	for _, p := range body["places"].([]any) {
		ids = append(ids, p.(map[string]any)["id"].(string))
	}
	return ids
}

func TestLocate(t *testing.T) {
	ts := newTestServer(t, stubClient{text: []places.Place{{ID: "x", Name: "嵐山", Lat: 35.01, Lng: 135.67, Types: []string{}}}})
	code, body := call(t, ts, "GET", "/api/locate?q=x", "alice", "")
	if code != 200 || body["name"] != "嵐山" || body["lat"] != 35.01 || body["source"] != "google" {
		t.Errorf("got %d %v", code, body)
	}
	if code, _ := call(t, ts, "GET", "/api/locate?q=", "alice", ""); code != 400 {
		t.Errorf("q なし: %d", code)
	}
	if code, _ := call(t, ts, "GET", "/api/locate?q=x", "", ""); code != 401 {
		t.Errorf("ログインなし: %d", code)
	}
	empty := newTestServer(t, stubClient{})
	if code, body := call(t, empty, "GET", "/api/locate?q=x", "alice", ""); code != 404 || errCode(body) != "place_not_found" {
		t.Errorf("見つからない: %d %v", code, body)
	}
	failing := newTestServer(t, stubClient{err: errors.New("Places API エラー 500")})
	if code, _ := call(t, failing, "GET", "/api/locate?q=x", "alice", ""); code != 503 {
		t.Errorf("失敗: %d", code)
	}
}

// --- 当たりとハズレの集計 ---

func TestExploreIncludesVerdictCounts(t *testing.T) {
	ts := newTestServer(t, nil)
	for _, u := range []string{"alice", "bob"} {
		call(t, ts, "POST", "/api/checkins", u, `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	}
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","verdict":"hit","clientId":"a1"}`)
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","verdict":"hit","clientId":"a1"}`) // 送り直しは数えない
	call(t, ts, "POST", "/api/logs", "bob", `{"placeId":"mock_01","verdict":"miss"}`)

	_, body := call(t, ts, "GET", "/api/explore?lat=34.693&lng=135.19&radius=5000", "alice", "")
	if m := placeByID(body, "mock_01"); m == nil || m["hits"] != 1.0 || m["misses"] != 1.0 {
		t.Errorf("mock_01: %v", m)
	}

	// mock=1 のダミーの場所はアプリが端末だけで記録するため、集計を読まない
	_, body = call(t, ts, "GET", "/api/explore?lat=34.693&lng=135.19&radius=5000&mock=1", "alice", "")
	if m := placeByID(body, "mock_01"); m == nil || m["hits"] != nil || m["misses"] != nil {
		t.Errorf("mock=1 で集計を付けている: %v", m)
	}
}

func TestLogRating(t *testing.T) {
	ts := newTestServer(t, nil)
	for _, u := range []string{"alice", "bob"} {
		call(t, ts, "POST", "/api/checkins", u, `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	}
	code, body := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","rating":5}`)
	if code != 201 || body["rating"] != 5.0 || body["verdict"] != "hit" {
		t.Fatalf("★5: %d %v", code, body)
	}
	// verdict を送っても、★評価から決める
	code, body = call(t, ts, "POST", "/api/logs", "bob", `{"placeId":"mock_01","rating":2,"verdict":"hit"}`)
	if code != 201 || body["verdict"] != "miss" {
		t.Fatalf("★2: %d %v", code, body)
	}
	for _, bad := range []string{`{"placeId":"mock_01","rating":0}`, `{"placeId":"mock_01","rating":6}`, `{"placeId":"mock_01"}`} {
		if code, body := call(t, ts, "POST", "/api/logs", "alice", bad); code != 400 || errCode(body) != "bad_request" {
			t.Errorf("%s: %d %v", bad, code, body)
		}
	}

	_, body = call(t, ts, "GET", "/api/explore?lat=34.693&lng=135.19&radius=5000", "alice", "")
	if m := placeByID(body, "mock_01"); m == nil || m["stars"] != 3.5 || m["starCount"] != 2.0 {
		t.Errorf("★の平均: %v", m)
	}
	_, body = call(t, ts, "GET", "/api/logs", "alice", "")
	if l := body["logs"].([]any)[0].(map[string]any); l["rating"] != 5.0 {
		t.Errorf("一覧の★評価: %v", l)
	}
}

func placeByID(body map[string]any, id string) map[string]any {
	for _, p := range body["places"].([]any) {
		if m := p.(map[string]any); m["id"] == id {
			return m
		}
	}
	return nil
}

// --- タイムライン ---

func TestTimelineShowsOnlyPublicLogsNearby(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_02","lat":34.69,"lng":135.19}`)
	_, public := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","verdict":"hit","comment":"良い","public":true}`)
	_, private := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_02","verdict":"miss"}`)
	if public["public"] != true || private["public"] != false {
		t.Fatalf("公開状態: %v %v", public, private)
	}

	const near = "/api/timeline?lat=34.70&lng=135.20"
	_, body := call(t, ts, "GET", near, "bob", "")
	entries := body["entries"].([]any)
	if len(entries) != 1 {
		t.Fatalf("公開した記録だけを返す: %v", entries)
	}
	e := entries[0].(map[string]any)
	if e["placeId"] != "mock_01" || e["comment"] != "良い" || e["mine"] != false || e["placeName"] == "" {
		t.Errorf("記録: %v", e)
	}
	if strings.Contains(e["id"].(string), "alice") || strings.Contains(e["author"].(string), "alice") {
		t.Errorf("uid を公開している: %v", e)
	}
	if _, mine := call(t, ts, "GET", near, "alice", ""); mine["entries"].([]any)[0].(map[string]any)["mine"] != true {
		t.Errorf("自分の記録: %v", mine)
	}

	if _, far := call(t, ts, "GET", "/api/timeline?lat=43.06&lng=141.35", "bob", ""); len(far["entries"].([]any)) != 0 {
		t.Errorf("遠い地点には出さない: %v", far)
	}
	if code, _ := call(t, ts, "GET", near, "", ""); code != 401 {
		t.Errorf("ログインなし: %d", code)
	}
	if code, _ := call(t, ts, "GET", "/api/timeline?lat=x&lng=1", "bob", ""); code != 400 {
		t.Errorf("読めない位置: %d", code)
	}
}

func TestTimelineLocationComesFromCheckin(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	// 思い出ログで送った位置は読まない。任意の地域のタイムラインへ投稿できないようにする
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","verdict":"hit","public":true,"lat":43.06,"lng":141.35}`)

	if _, far := call(t, ts, "GET", "/api/timeline?lat=43.06&lng=141.35", "bob", ""); len(far["entries"].([]any)) != 0 {
		t.Errorf("送られた位置を使った: %v", far)
	}
	if _, near := call(t, ts, "GET", "/api/timeline?lat=34.69&lng=135.19", "bob", ""); len(near["entries"].([]any)) != 1 {
		t.Errorf("チェックインの地点に出ない: %v", near)
	}
}

func TestPublicStateCanBeChangedAfterwards(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	_, log := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","verdict":"hit"}`)
	path := "/api/logs/" + log["id"].(string)
	const near = "/api/timeline?lat=34.69&lng=135.19"
	count := func() int {
		_, b := call(t, ts, "GET", near, "bob", "")
		return len(b["entries"].([]any))
	}

	if code, b := call(t, ts, "PATCH", path, "alice", `{"public":true}`); code != 200 || b["public"] != true {
		t.Fatalf("公開: %d %v", code, b)
	}
	if count() != 1 {
		t.Error("公開した記録が出ない")
	}
	if _, list := call(t, ts, "GET", "/api/logs", "alice", ""); list["logs"].([]any)[0].(map[string]any)["public"] != true {
		t.Errorf("自分の一覧に反映されない: %v", list)
	}
	if code, b := call(t, ts, "PATCH", path, "alice", `{"public":false}`); code != 200 || b["public"] != false {
		t.Fatalf("非公開: %d %v", code, b)
	}
	if count() != 0 {
		t.Error("非公開にした記録が残っている")
	}
	if code, _ := call(t, ts, "PATCH", path, "bob", `{"public":true}`); code != 404 {
		t.Errorf("他人の記録は変えられない: %d", code)
	}
	if code, _ := call(t, ts, "PATCH", path, "alice", `{}`); code != 400 {
		t.Errorf("public なし: %d", code)
	}
}

func TestReportedEntriesAreHidden(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","verdict":"hit","public":true}`)
	const near = "/api/timeline?lat=34.69&lng=135.19"
	_, b := call(t, ts, "GET", near, "bob", "")
	id := b["entries"].([]any)[0].(map[string]any)["id"].(string)
	report := "/api/timeline/" + id + "/report"

	// 理由とひとことを確かめる
	if code, body := call(t, ts, "POST", report, "bob", `{"reason":"rude"}`); code != 400 || errCode(body) != "bad_request" {
		t.Errorf("知らない理由: %d %v", code, body)
	}
	if code, _ := call(t, ts, "POST", report, "bob", `{"reason":"spam","note":"`+strings.Repeat("あ", 201)+`"}`); code != 400 {
		t.Errorf("長すぎるひとこと: %d", code)
	}
	// 同じ人が何度報告しても1回と数える。理由を送らない古いアプリの報告も受け付ける
	for _, body := range []string{`{"reason":"spam","note":"宣伝です"}`, ``, `{}`} {
		if code, _ := call(t, ts, "POST", report, "bob", body); code != 200 {
			t.Fatalf("報告 %q: %d", body, code)
		}
	}
	if _, b := call(t, ts, "GET", near, "erin", ""); len(b["entries"].([]any)) != 1 {
		t.Errorf("1人の報告では、ほかの人のタイムラインから消さない: %v", b)
	}
	if _, b := call(t, ts, "GET", near, "bob", ""); len(b["entries"].([]any)) != 0 {
		t.Errorf("報告した人のタイムラインからは、すぐに消す: %v", b)
	}
	call(t, ts, "POST", report, "carol", `{"reason":"inappropriate"}`)
	call(t, ts, "POST", report, "dave", `{"reason":"personal"}`)
	if _, b := call(t, ts, "GET", near, "erin", ""); len(b["entries"].([]any)) != 0 {
		t.Errorf("3人が報告したら消す: %v", b)
	}
	if code, _ := call(t, ts, "POST", "/api/timeline/nope/report", "bob", ""); code != 404 {
		t.Errorf("ない記録: %d", code)
	}
}

// --- チェックインの候補 ---

func TestExploreForCheckinAsksNearestFirst(t *testing.T) {
	var got places.NearbyRequest
	ts := newTestServer(t, stubClient{nearby: []places.Place{}, gotNearby: &got})

	call(t, ts, "GET", "/api/explore?lat=35&lng=135&radius=300&purpose=checkin", "alice", "")
	if !got.RankByDistance || got.RadiusMeters != 300 {
		t.Errorf("チェックインの候補: %+v", got)
	}
	call(t, ts, "GET", "/api/explore?lat=35&lng=135", "alice", "")
	if !got.RankByDistance {
		t.Errorf("未踏サーチも人気順では知られた場所で埋まる: %+v", got)
	}
}

func TestExploreForCheckinFailsWithoutDummySpots(t *testing.T) {
	ts := newTestServer(t, stubClient{err: errors.New("boom")})
	code, body := call(t, ts, "GET", "/api/explore?lat=35&lng=135&radius=300&purpose=checkin", "alice", "")
	if code != 503 || errCode(body) != "places_unavailable" {
		t.Fatalf("got %d %v", code, body)
	}
}

// 有名スポットの位置。距離の条件を確かめるため、候補はここからの距離で置く
const originLat, originLng = 35.0, 135.0

func spotAt(id string, meters float64, reviews int) places.Place {
	lat, lng := places.OffsetPoint(originLat, originLng, meters, 90)
	return places.Place{ID: id, Name: id, Lat: lat, Lng: lng, Types: []string{}, UserRatingCount: reviews}
}

func famousOrigin(reviews int) places.Place {
	return places.Place{ID: "o", Name: "有名", Lat: originLat, Lng: originLng, Types: []string{}, UserRatingCount: reviews}
}

func alternativeIDs(t *testing.T, body map[string]any) []string {
	t.Helper()
	ids := []string{}
	for _, a := range body["alternatives"].([]any) {
		ids = append(ids, a.(map[string]any)["id"].(string))
	}
	return ids
}

func TestAlternativesSearchesThreePointsAroundOriginByPopularity(t *testing.T) {
	log := &nearbyLog{}
	ts := newTestServer(t, stubClient{text: []places.Place{famousOrigin(9000)}, nearby: []places.Place{}, nearbyCalls: log})
	if code, body := call(t, ts, "GET", "/api/alternatives?q=x&radius=3000", "alice", ""); code != 200 {
		t.Fatalf("got %d %v", code, body)
	}
	reqs := log.all()
	if len(reqs) != 3 {
		t.Fatalf("Nearby Search の回数 = %d", len(reqs))
	}
	for _, r := range reqs {
		if r.RankByDistance {
			t.Errorf("近い順では敷地内の場所だけで埋まる: %+v", r)
		}
		if len(r.IncludedPrimaryTypes) == 0 || len(r.IncludedTypes) != 0 {
			t.Errorf("主な種類で絞る: %+v", r)
		}
		if r.RadiusMeters != 1200 {
			t.Errorf("各地点の半径 = %v", r.RadiusMeters)
		}
		if d := places.DistanceMeters(originLat, originLng, r.Lat, r.Lng); math.Abs(d-1200) > 1 {
			t.Errorf("有名スポットから地点までの距離 = %v", d)
		}
	}
	// 3 地点が同じ方向に偏らない
	if d := places.DistanceMeters(reqs[0].Lat, reqs[0].Lng, reqs[1].Lat, reqs[1].Lng); d < 2000 {
		t.Errorf("地点どうしの距離 = %v", d)
	}
}

func TestAlternativesOffersOnlyStandalonePlacesAwayFromOrigin(t *testing.T) {
	contained := spotAt("contained", 800, 300)
	contained.Contained = true
	ts := newTestServer(t, stubClient{
		text: []places.Place{famousOrigin(9000)},
		nearby: []places.Place{
			spotAt("origin-grounds", 299, 300),
			spotAt("at-min-distance", 300, 300),
			contained,
			spotAt("no-reviews", 800, 0),
			spotAt("below-min-reviews", 800, 19),
			spotAt("at-min-reviews", 900, 20),
			spotAt("at-max-reviews", 1000, 1000),
			spotAt("famous", 800, 1001),
		},
	})
	code, body := call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")
	if code != 200 {
		t.Fatalf("got %d %v", code, body)
	}
	want := []string{"at-min-distance", "at-min-reviews", "at-max-reviews"}
	if got := alternativeIDs(t, body); !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestAlternativesOnlyOffersLesserKnownPlaces(t *testing.T) {
	ts := newTestServer(t, stubClient{
		text: []places.Place{famousOrigin(800)},
		nearby: []places.Place{
			spotAt("quiet", 800, 30),
			spotAt("same", 800, 800),
			spotAt("busier", 800, 900),
		},
	})
	code, body := call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")
	if code != 200 {
		t.Fatalf("got %d %v", code, body)
	}
	if got := alternativeIDs(t, body); !reflect.DeepEqual(got, []string{"quiet"}) {
		t.Errorf("条件を満たす候補だけを、少なくてもそのまま返す: %v", got)
	}
}

func TestAlternativesAreNearestFirstWithoutDuplicates(t *testing.T) {
	// 同じ場所が複数の地点の検索に現れても、stubClient は全ての地点に同じ一覧を返す
	ts := newTestServer(t, stubClient{
		text: []places.Place{famousOrigin(9000)},
		nearby: []places.Place{
			spotAt("far", 1800, 30),
			spotAt("near", 500, 900),
			spotAt("middle", 1000, 100),
		},
	})
	_, body := call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")
	want := []string{"near", "middle", "far"}
	if got := alternativeIDs(t, body); !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestAlternativesKeepRealResultsWhenOnePointFails(t *testing.T) {
	ts := newTestServer(t, &failFirstNearby{stubClient: stubClient{
		text:   []places.Place{famousOrigin(9000)},
		nearby: []places.Place{spotAt("real", 800, 100)},
	}})
	code, body := call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")
	if code != 200 || body["source"] != places.SourceGoogle {
		t.Fatalf("got %d %v", code, body)
	}
	// 失敗した地点のダミーを本物の結果に混ぜない
	if got := alternativeIDs(t, body); !reflect.DeepEqual(got, []string{"real"}) {
		t.Errorf("got %v", got)
	}
}

func TestAlternativesDoNotFallBackToMockWhenEveryPointFails(t *testing.T) {
	ts := newTestServer(t, &failNearby{stubClient: stubClient{text: []places.Place{famousOrigin(9000)}}})
	code, body := call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")
	if code != 503 || errCode(body) != "places_unavailable" {
		t.Fatalf("got %d %v", code, body)
	}
}

func TestAlternativesEmptyWhenNothingIsLesserKnown(t *testing.T) {
	ts := newTestServer(t, stubClient{
		text:   []places.Place{famousOrigin(0)},
		nearby: []places.Place{spotAt("busier", 800, 50)},
	})
	code, body := call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")
	if code != 200 || len(body["alternatives"].([]any)) != 0 {
		t.Errorf("候補がなければ 0 件を返す: %d %v", code, body)
	}
}

// --- 呼び出し回数 ---

func TestUsageCountsCallsByFeature(t *testing.T) {
	ts := newTestServer(t, stubClient{
		text:   []places.Place{{ID: "o", Name: "有名", Types: []string{}}},
		nearby: []places.Place{},
	})
	call(t, ts, "GET", "/api/explore?lat=35&lng=135", "alice", "")
	call(t, ts, "GET", "/api/explore?lat=35&lng=135&purpose=checkin", "alice", "")
	call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")

	code, body := call(t, ts, "GET", "/api/usage", "", "")
	if code != 200 || body["date"] != "2026-11-08" || body["dailyLimit"] != 100.0 {
		t.Fatalf("got %d %v", code, body)
	}
	real := body["today"].(map[string]any)["real"].(map[string]any)
	calls := real["calls"].(map[string]any)
	if calls["nearby.explore"] != 1.0 || calls["nearby.checkin"] != 1.0 || calls["nearby.alternatives"] != 3.0 || calls["text.alternatives"] != 1.0 {
		t.Errorf("calls = %v", calls)
	}
	if real["estimatedUsd"] != 0.0 || real["listPriceUsd"].(float64) != 0.21 {
		t.Errorf("料金の目安: %v", real)
	}
}

func TestUsageWithoutKeyReportsSimulatedCalls(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "GET", "/api/alternatives?q=x", "alice", "")
	call(t, ts, "GET", "/api/alternatives?q=x&mock=1", "alice", "")
	_, body := call(t, ts, "GET", "/api/usage", "", "")
	today := body["today"].(map[string]any)
	sim := today["simulated"].(map[string]any)["byKind"].(map[string]any)
	if sim["text"] != 1.0 || sim["nearby"] != 3.0 {
		t.Errorf("simulated = %v", sim)
	}
	if n := len(today["real"].(map[string]any)["byKind"].(map[string]any)); n != 0 {
		t.Errorf("本物の回数に数えている: %v", today["real"])
	}
}

func TestUsageIsHiddenUnlessExposed(t *testing.T) {
	mock, err := places.NewMockClient()
	if err != nil {
		t.Fatal(err)
	}
	st := store.NewMemoryStore()
	s := &Server{
		Places: &places.Gateway{Fallback: mock, Log: discard, Usage: st},
		Scorer: places.DefaultScorer, Store: st, Verifier: auth.FakeVerifier{}, Log: discard,
	}
	ts := httptest.NewServer(s.Handler())
	t.Cleanup(ts.Close)
	if code, body := call(t, ts, "GET", "/api/usage", "", ""); code != 404 || errCode(body) != "not_found" {
		t.Errorf("本番の設定で公開している: %d %v", code, body)
	}
}

// --- 検索のログイン ---

func TestSearchRequiresAuth(t *testing.T) {
	ts := newTestServer(t, stubClient{text: []places.Place{}, nearby: []places.Place{}})
	for _, path := range []string{"/api/explore?lat=35&lng=135", "/api/alternatives?q=x", "/api/explore?lat=35&lng=135&purpose=checkin"} {
		if code, body := call(t, ts, "GET", path, "", ""); code != 401 || errCode(body) != "unauthenticated" {
			t.Errorf("%s: got %d %v", path, code, body)
		}
	}
	// ログインしていない呼び出しは回数に含めない
	_, body := call(t, ts, "GET", "/api/usage", "", "")
	if n := len(body["today"].(map[string]any)["real"].(map[string]any)["calls"].(map[string]any)); n != 0 {
		t.Errorf("回数に含めている: %v", body["today"])
	}
}

// /api/health 以外は、Places API を呼ばない mock=1 の検索と訪問者数も、ログインしていなければ断る
func TestPublicEndpointsRequireAuth(t *testing.T) {
	ts := newTestServer(t, nil)
	for _, path := range []string{
		"/api/explore?lat=35&lng=135&mock=1",
		"/api/alternatives?q=x&mock=1",
		"/api/locate?q=x&mock=1",
		"/api/places/mock_01/visitors",
	} {
		if code, body := call(t, ts, "GET", path, "", ""); code != 401 || errCode(body) != "unauthenticated" {
			t.Errorf("%s: got %d %v", path, code, body)
		}
	}
	if code, body := call(t, ts, "GET", "/api/explore?lat=35&lng=135&mock=1", "alice", ""); code != 200 || body["source"] != "mock" {
		t.Errorf("ログインした mock=1: got %d %v", code, body)
	}
}

// --- Geminiちゃん ---

func suggestionNames(body map[string]any) []string {
	var out []string
	for _, s := range body["suggestions"].([]any) {
		p := s.(map[string]any)["place"].(map[string]any)
		out = append(out, p["name"].(string))
	}
	return out
}

func TestAssistantFake(t *testing.T) {
	ts := newTestServer(t, nil)

	// 穴場のおすすめ：地図の中心の周りを探し、理由を付けて最大3件返す
	code, body := call(t, ts, "POST", "/api/assistant", "alice", `{"message":"近くの穴場を教えて","lat":34.693,"lng":135.19}`)
	if code != 200 || body["source"] != "fake" || body["intent"] != "recommend" || body["placesSource"] != "mock" || body["reply"] == "" {
		t.Fatalf("%d %v", code, body)
	}
	sg := body["suggestions"].([]any)
	if len(sg) != 3 {
		t.Fatalf("suggestions = %v", sg)
	}
	first := sg[0].(map[string]any)
	if first["reason"] == "" || first["place"].(map[string]any)["title"] == "famous" {
		t.Fatalf("first = %v", first)
	}
	if c := body["center"].(map[string]any); c["name"] != "地図の中心" {
		t.Fatalf("center = %v", c)
	}

	// ジャンルで絞る（カフェ → food）
	code, body = call(t, ts, "POST", "/api/assistant", "alice", `{"message":"静かなカフェ","lat":34.693,"lng":135.19}`)
	if code != 200 {
		t.Fatalf("%d %v", code, body)
	}
	if g := body["search"].(map[string]any)["genres"].([]any); len(g) != 1 || g[0] != "food" {
		t.Fatalf("genres = %v", g)
	}
	for _, n := range suggestionNames(body) {
		if !strings.Contains(n, "喫茶") && !strings.Contains(n, "食堂") {
			t.Errorf("カフェでない候補: %s", n)
		}
	}

	// 代わりに行くならここ：有名スポットを中心にする
	code, body = call(t, ts, "POST", "/api/assistant", "alice", `{"message":"海辺の大展望台の代わりは？"}`)
	if code != 200 || body["intent"] != "alternatives" || len(body["suggestions"].([]any)) == 0 {
		t.Fatalf("%d %v", code, body)
	}
	if c := body["center"].(map[string]any); c["name"] != "海辺の大展望台" {
		t.Fatalf("center = %v", c)
	}
	if body["search"].(map[string]any)["query"] != "海辺の大展望台" {
		t.Fatalf("search = %v", body["search"])
	}

	// 地図の移動：候補は返さない
	code, body = call(t, ts, "POST", "/api/assistant", "alice", `{"message":"異国の洋館公園へ移動して"}`)
	if code != 200 || body["intent"] != "locate" || body["center"] == nil || len(body["suggestions"].([]any)) != 0 {
		t.Fatalf("%d %v", code, body)
	}

	// 地図の中心も地名もなければ聞き返す
	code, body = call(t, ts, "POST", "/api/assistant", "alice", `{"message":"穴場を教えて"}`)
	if code != 200 || body["center"] != nil || body["reply"] != replyNoCenter {
		t.Fatalf("%d %v", code, body)
	}

	// 会話
	code, body = call(t, ts, "POST", "/api/assistant", "alice", `{"message":"こんにちは"}`)
	if code != 200 || body["intent"] != "chat" || body["reply"] == "" || body["placesSource"] != nil {
		t.Fatalf("%d %v", code, body)
	}
}

func TestAssistantValidation(t *testing.T) {
	ts := newTestServer(t, nil)
	if code, body := call(t, ts, "POST", "/api/assistant", "", `{"message":"こんにちは"}`); code != 401 {
		t.Fatalf("トークンなし: %d %v", code, body)
	}
	for _, b := range []string{`{"message":"  "}`, `{}`, `{"message":"` + strings.Repeat("あ", 201) + `"}`, `{"message":"hi","lat":91,"lng":0}`, `not json`} {
		if code, body := call(t, ts, "POST", "/api/assistant", "alice", b); code != 400 || errCode(body) != "bad_request" {
			t.Errorf("%s: %d %v", b, code, body)
		}
	}
}

// stubModel は本物の Gemini の代わり。
type stubModel struct {
	in    assistant.Interpretation
	err   error
	calls int
}

func (m *stubModel) Interpret(context.Context, string, []assistant.Turn) (assistant.Interpretation, error) {
	m.calls++
	return m.in, m.err
}

func TestAssistantGemini(t *testing.T) {
	m := &stubModel{in: assistant.Interpretation{Intent: assistant.IntentRecommend, Genres: []string{"worship"}}}
	ts := newTestServerWithModel(t, nil, m)
	code, body := call(t, ts, "POST", "/api/assistant", "alice", `{"message":"お参りしたい","lat":34.693,"lng":135.19,"history":[{"role":"user","text":"こんにちは"}]}`)
	if code != 200 || body["source"] != "gemini" || body["reply"] == "" {
		t.Fatalf("%d %v", code, body)
	}
	// Gemini は一言の読み取りだけに使い、理由の文は口コミの数と称号から作る
	if m.calls != 1 {
		t.Errorf("Gemini を %d 回呼んだ", m.calls)
	}
	for _, s := range body["suggestions"].([]any) {
		if !strings.Contains(s.(map[string]any)["reason"].(string), "口コミ") {
			t.Errorf("理由の文: %v", s)
		}
		if s.(map[string]any)["place"].(map[string]any)["title"] == "famous" {
			t.Errorf("超有名の場所を候補に入れた: %v", s)
		}
	}

	// Gemini が失敗しても簡易版で答える
	m.err = errors.New("vertex down")
	code, body = call(t, ts, "POST", "/api/assistant", "alice", `{"message":"近くの穴場","lat":34.693,"lng":135.19}`)
	if code != 200 || body["source"] != "fake" || len(body["suggestions"].([]any)) == 0 {
		t.Fatalf("%d %v", code, body)
	}
}

func TestAssistantPlacesDown(t *testing.T) {
	// 地名を探す Places API が失敗したら、エラーにせずに伝える
	ts := newTestServer(t, stubClient{err: errors.New("places down")})
	code, body := call(t, ts, "POST", "/api/assistant", "alice", `{"message":"嵐山へ移動して"}`)
	if code != 200 || body["reply"] != replyPlacesDown || body["center"] != nil {
		t.Fatalf("%d %v", code, body)
	}
	// 見つからない地名
	ts = newTestServer(t, stubClient{})
	code, body = call(t, ts, "POST", "/api/assistant", "alice", `{"message":"どこでもない町の近くの穴場"}`)
	if code != 200 || !strings.Contains(body["reply"].(string), "見つかりませんでした") {
		t.Fatalf("%d %v", code, body)
	}
}

// --- ログインとプロフィール ---

func TestAnonymousUserIsRejected(t *testing.T) {
	ts := newTestServer(t, stubClient{text: []places.Place{}, nearby: []places.Place{}})
	for _, c := range []struct{ method, path, body string }{
		{"GET", "/api/explore?lat=35&lng=135", ""},
		{"GET", "/api/alternatives?q=x", ""},
		{"POST", "/api/checkins", `{"placeId":"mock_01"}`},
		{"GET", "/api/logs", ""},
		{"GET", "/api/timeline?lat=34.70&lng=135.20", ""},
		{"POST", "/api/assistant", `{"message":"カフェ"}`},
		{"GET", "/api/me", ""},
		{"PUT", "/api/me", `{"nickname":"たろう","icon":"hiker"}`},
	} {
		code, body := call(t, ts, c.method, c.path, "anon:alice", c.body)
		if code != 403 || errCode(body) != "login_required" {
			t.Errorf("%s %s: got %d %v", c.method, c.path, code, body)
		}
	}
}

func TestProfileIsEmptyUntilSaved(t *testing.T) {
	ts := newTestServer(t, nil)
	code, body := call(t, ts, "GET", "/api/me", "alice", "")
	if code != 200 || body["profile"] != nil {
		t.Errorf("保存前: got %d %v", code, body)
	}
	if code, _ := call(t, ts, "GET", "/api/me", "", ""); code != 401 {
		t.Errorf("ログインなし: %d", code)
	}
}

func TestProfileCanBeSavedAndChanged(t *testing.T) {
	ts := newTestServer(t, nil)
	code, body := call(t, ts, "PUT", "/api/me", "alice", `{"nickname":"  路地裏の旅人  ","icon":"hiker"}`)
	want := map[string]any{"nickname": "路地裏の旅人", "icon": "hiker"}
	if code != 200 || !reflect.DeepEqual(body["profile"], want) {
		t.Fatalf("保存: got %d %v", code, body)
	}
	if _, got := call(t, ts, "GET", "/api/me", "alice", ""); !reflect.DeepEqual(got["profile"], want) {
		t.Errorf("読み込み: %v", got)
	}
	call(t, ts, "PUT", "/api/me", "alice", `{"nickname":"たろう","icon":"cat"}`)
	if _, got := call(t, ts, "GET", "/api/me", "alice", ""); !reflect.DeepEqual(got["profile"], map[string]any{"nickname": "たろう", "icon": "cat"}) {
		t.Errorf("変更: %v", got)
	}
	if _, got := call(t, ts, "GET", "/api/me", "bob", ""); got["profile"] != nil {
		t.Errorf("他の人のプロフィールを返している: %v", got)
	}
}

func TestProfileValidation(t *testing.T) {
	ts := newTestServer(t, nil)
	twenty := strings.Repeat("あ", 20)
	if code, body := call(t, ts, "PUT", "/api/me", "alice", `{"nickname":"`+twenty+`","icon":"hiker"}`); code != 200 {
		t.Errorf("20文字: got %d %v", code, body)
	}
	for _, b := range []string{
		`{"nickname":"","icon":"hiker"}`,
		`{"nickname":"   ","icon":"hiker"}`,
		`{"nickname":"` + twenty + `い","icon":"hiker"}`,
		`{"nickname":"二行\nの名前","icon":"hiker"}`,
		`{"nickname":"たろう","icon":""}`,
		`{"nickname":"たろう","icon":"Hiker!"}`,
		`{"nickname":"たろう"}`,
	} {
		if code, body := call(t, ts, "PUT", "/api/me", "alice", b); code != 400 || errCode(body) != "bad_request" {
			t.Errorf("%s: got %d %v", b, code, body)
		}
	}
	if _, got := call(t, ts, "GET", "/api/me", "alice", ""); got["profile"].(map[string]any)["nickname"] != twenty {
		t.Errorf("不正な値で上書きしている: %v", got)
	}
}

func TestTimelineShowsAuthorProfile(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "PUT", "/api/me", "alice", `{"nickname":"たろう","icon":"hiker"}`)
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"mock_01","lat":34.69,"lng":135.19}`)
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"mock_01","verdict":"hit","public":true}`)
	call(t, ts, "POST", "/api/checkins", "carol", `{"placeId":"mock_02","lat":34.69,"lng":135.19}`)
	call(t, ts, "POST", "/api/logs", "carol", `{"placeId":"mock_02","verdict":"miss","public":true}`)

	const near = "/api/timeline?lat=34.70&lng=135.20"
	byPlace := func() map[string]map[string]any {
		_, body := call(t, ts, "GET", near, "bob", "")
		out := map[string]map[string]any{}
		for _, e := range body["entries"].([]any) {
			m := e.(map[string]any)
			out[m["placeId"].(string)] = m
		}
		return out
	}
	got := byPlace()
	if a := got["mock_01"]; a["authorName"] != "たろう" || a["authorIcon"] != "hiker" {
		t.Errorf("投稿者のプロフィール: %v", a)
	}
	if c := got["mock_02"]; c["authorName"] != "" || c["authorIcon"] != "" {
		t.Errorf("プロフィールのない投稿者: %v", c)
	}

	call(t, ts, "PUT", "/api/me", "alice", `{"nickname":"じろう","icon":"cat"}`)
	if a := byPlace()["mock_01"]; a["authorName"] != "じろう" || a["authorIcon"] != "cat" {
		t.Errorf("変更したプロフィールが過去の投稿に反映されていない: %v", a)
	}
}

func TestFavoritesAPI(t *testing.T) {
	ts := newTestServer(t, nil)
	for _, id := range []string{"mock_01", "mock_02"} {
		if code, body := call(t, ts, "PUT", "/api/favorites/"+id, "alice", ""); code != 200 || body["favorite"] != true {
			t.Fatalf("PUT %s: %d %v", id, code, body)
		}
	}
	_, body := call(t, ts, "GET", "/api/favorites/ids", "alice", "")
	if ids := body["placeIds"].([]any); len(ids) != 2 {
		t.Errorf("ids: %v", body)
	}
	_, body = call(t, ts, "GET", "/api/favorites", "alice", "")
	favs := body["favorites"].([]any)
	if len(favs) != 2 {
		t.Fatalf("favorites: %v", body)
	}
	for _, f := range favs {
		p := f.(map[string]any)["place"].(map[string]any)
		if p["name"] == "" || p["lat"] == nil {
			t.Errorf("名前と位置を付けて返す: %v", p)
		}
		// 口コミ数は取得していないので、0 件や「未踏」と誤って見せないよう、口コミ数と称号を含めない
		for _, k := range []string{"userRatingCount", "obscurity", "title"} {
			if _, ok := p[k]; ok {
				t.Errorf("取得していない %s を返している: %v", k, p)
			}
		}
	}
	if code, _ := call(t, ts, "DELETE", "/api/favorites/mock_01", "alice", ""); code != 200 {
		t.Errorf("DELETE: %d", code)
	}
	_, body = call(t, ts, "GET", "/api/favorites/ids", "alice", "")
	if ids := body["placeIds"].([]any); len(ids) != 1 || ids[0] != "mock_02" {
		t.Errorf("外したあと: %v", body)
	}
	// ほかの人には見えない
	_, body = call(t, ts, "GET", "/api/favorites/ids", "bob", "")
	if ids := body["placeIds"].([]any); len(ids) != 0 {
		t.Errorf("bob: %v", body)
	}
	// 名前を読めない場所も、一覧から消さずに返す
	call(t, ts, "PUT", "/api/favorites/unknown_place", "carol", "")
	_, body = call(t, ts, "GET", "/api/favorites", "carol", "")
	if f := body["favorites"].([]any)[0].(map[string]any); f["placeId"] != "unknown_place" || f["place"] != nil {
		t.Errorf("読めない場所: %v", f)
	}
	if code, body := call(t, ts, "PUT", "/api/favorites/a%2Fb", "alice", ""); code != 400 {
		t.Errorf("形の正しくない place ID: %d %v", code, body)
	}
}

func TestPlacePhotosWithoutKey(t *testing.T) {
	// API キーがないとき（ダミー）は写真を返さず、エラーにもしない
	ts := newTestServer(t, nil)
	code, body := call(t, ts, "GET", "/api/places/mock_01/photos", "alice", "")
	if code != 200 || body["source"] != "mock" || len(body["photos"].([]any)) != 0 {
		t.Errorf("%d %v", code, body)
	}
	if code, _ := call(t, ts, "GET", "/api/places/mock_01/photos", "", ""); code != 401 {
		t.Errorf("ログインなし: %d", code)
	}
}

func TestLogsWithoutNamesDoNotCallPlaces(t *testing.T) {
	got := &detailsCalls{}
	ts := newTestServer(t, stubClient{gotDetails: got, details: map[string]places.Place{"a": {ID: "a", Name: "祠", Lat: 35, Lng: 135}}})
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"a","lat":35,"lng":135}`)
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","rating":4}`)
	before := len(got.ids)
	_, body := call(t, ts, "GET", "/api/logs?names=0", "alice", "")
	if len(got.ids) != before || len(body["logs"].([]any)) != 1 {
		t.Errorf("names=0 で名前を読んだ: %v %v", got.ids, body)
	}
	_, body = call(t, ts, "GET", "/api/logs", "alice", "")
	if l := body["logs"].([]any)[0].(map[string]any); l["placeName"] != "祠" {
		t.Errorf("既定では名前を返す: %v", l)
	}
}

func TestLogsAndTimelineSkipNamesTheAppKnows(t *testing.T) {
	got := &detailsCalls{}
	ts := newTestServer(t, stubClient{gotDetails: got, details: map[string]places.Place{
		"a": {ID: "a", Name: "祠", Lat: 35, Lng: 135},
	}})
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"a","lat":35,"lng":135}`)
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","rating":4,"public":true}`)
	before := len(got.ids)
	_, body := call(t, ts, "GET", "/api/logs?known=a,b", "alice", "")
	if len(got.ids) != before {
		t.Errorf("アプリが知っている名前を読んだ: %v", got.ids)
	}
	if l := body["logs"].([]any)[0].(map[string]any); l["placeName"] != nil && l["placeName"] != "" {
		t.Errorf("知っている場所の名前は空で返す: %v", l)
	}
	call(t, ts, "GET", "/api/timeline?lat=35&lng=135&known=a", "bob", "")
	if len(got.ids) != before {
		t.Errorf("タイムラインで、知っている名前を読んだ: %v", got.ids)
	}
}

func TestCheckinCandidatesReportTheDailyLimit(t *testing.T) {
	ts := newTestServer(t, stubClient{nearby: []places.Place{{ID: "a", Name: "祠", Lat: 35, Lng: 135}}})
	var code int
	var body map[string]any
	for range 101 {
		code, body = call(t, ts, "GET", "/api/explore?lat=35&lng=135&radius=300&purpose=checkin", "alice", "")
	}
	if code != 429 || errCode(body) != "daily_limit" {
		t.Errorf("上限に達したことを、通信できないことと分けて返す: %d %v", code, body)
	}
}

func TestAchievementStatsCountEachUserOnce(t *testing.T) {
	ts := newTestServer(t, nil)
	call(t, ts, "PUT", "/api/me/achievements", "alice", `{"tiers":{"pioneer":2,"night_owl":1}}`)
	call(t, ts, "PUT", "/api/me/achievements", "bob", `{"tiers":{"pioneer":1}}`)
	call(t, ts, "PUT", "/api/me/achievements", "carol", `{"tiers":{}}`)
	// 送り直しても数え直さない
	call(t, ts, "PUT", "/api/me/achievements", "alice", `{"tiers":{"pioneer":3,"night_owl":1}}`)

	code, body := call(t, ts, "GET", "/api/achievements/stats", "alice", "")
	if code != 200 || body["users"] != float64(3) {
		t.Fatalf("got %d %v", code, body)
	}
	got := body["achievements"].(map[string]any)
	if p := got["pioneer"].([]any); p[0] != float64(2) || p[1] != float64(1) || p[2] != float64(1) {
		t.Errorf("段階ごとの人数: %v", p)
	}
	if code, body := call(t, ts, "PUT", "/api/me/achievements", "alice", `{"tiers":{"Bad ID":1}}`); code != 400 {
		t.Errorf("正しくない ID: %d %v", code, body)
	}
	if code, _ := call(t, ts, "PUT", "/api/me/achievements", "alice", `{"tiers":{"pioneer":4}}`); code != 400 {
		t.Errorf("段階の上限を超えた: %d", code)
	}
}

func TestPatchLogEditsRatingAndComment(t *testing.T) {
	ts := newTestServer(t, stubClient{details: map[string]places.Place{"a": {ID: "a", Name: "祠", Lat: 35, Lng: 135}}})
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"a","lat":35,"lng":135}`)
	_, created := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","rating":5,"comment":"最高"}`)
	id := created["id"].(string)

	code, body := call(t, ts, "PATCH", "/api/logs/"+id, "alice", `{"rating":2,"comment":"  混んでいた  "}`)
	if code != 200 || body["rating"] != float64(2) || body["verdict"] != "miss" || body["comment"] != "混んでいた" {
		t.Fatalf("got %d %v", code, body)
	}
	if code, _ := call(t, ts, "PATCH", "/api/logs/"+id, "alice", `{"rating":6}`); code != 400 {
		t.Errorf("★の範囲の外: %d", code)
	}
	if code, _ := call(t, ts, "PATCH", "/api/logs/"+id, "alice", `{}`); code != 400 {
		t.Errorf("何も指定しない: %d", code)
	}
	if code, _ := call(t, ts, "PATCH", "/api/logs/"+id, "bob", `{"rating":1}`); code != 404 {
		t.Errorf("ほかの人の記録は直せない: %d", code)
	}
}

func TestAssistantFindsTheTargetAndHiddenSpotsNearIt(t *testing.T) {
	ts := newTestServer(t, stubClient{
		text: []places.Place{
			{ID: "far", Name: "遠い駅", Lat: 35.2, Lng: 135, Types: []string{"train_station"}, UserRatingCount: 900},
			{ID: "st", Name: "近くの駅", Lat: 35.003, Lng: 135, Types: []string{"train_station"}, UserRatingCount: 2000},
		},
		nearby: []places.Place{
			{ID: "h1", Name: "駅裏の祠", Lat: 35.004, Lng: 135, Types: []string{"shinto_shrine"}, UserRatingCount: 3},
		},
	})
	code, body := call(t, ts, "POST", "/api/assistant", "alice", `{"message":"近くの駅","lat":35,"lng":135}`)
	if code != 200 {
		t.Fatalf("got %d %v", code, body)
	}
	targets, _ := body["targets"].([]any)
	if len(targets) != 1 || targets[0].(map[string]any)["id"] != "st" {
		t.Fatalf("範囲の中の駅だけを返す: %v", body["targets"])
	}
	if c := body["center"].(map[string]any); c["name"] != "近くの駅" {
		t.Errorf("穴場は、いちばん近い駅のそばで探す: %v", c)
	}
	if sg := body["suggestions"].([]any); len(sg) == 0 {
		t.Errorf("駅のそばの穴場も返す: %v", body)
	}
	if reply := body["reply"].(string); !strings.Contains(reply, "近くの駅") || !strings.Contains(reply, "徒歩") {
		t.Errorf("見つけた駅を答えに書く: %q", reply)
	}
}

func TestTimelineAllShowsPublicEntriesFromAnywhere(t *testing.T) {
	ts := newTestServer(t, stubClient{details: map[string]places.Place{
		"a": {ID: "a", Name: "京都の祠", Lat: 35, Lng: 135.7},
		"b": {ID: "b", Name: "札幌の公園", Lat: 43, Lng: 141.3},
	}})
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"a","lat":35,"lng":135.7}`)
	call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","rating":5,"public":true}`)
	call(t, ts, "POST", "/api/checkins", "bob", `{"placeId":"b","lat":43,"lng":141.3}`)
	call(t, ts, "POST", "/api/logs", "bob", `{"placeId":"b","rating":4,"public":true}`)
	call(t, ts, "POST", "/api/logs", "bob", `{"placeId":"b","rating":3}`) // 自分だけの記録は出さない

	_, body := call(t, ts, "GET", "/api/timeline?scope=all", "carol", "")
	if n := len(body["entries"].([]any)); n != 2 {
		t.Errorf("全国の公開された記録を返す: %d %v", n, body)
	}
	_, near := call(t, ts, "GET", "/api/timeline?lat=35&lng=135.7", "carol", "")
	if n := len(near["entries"].([]any)); n != 1 {
		t.Errorf("周辺は近くの記録だけ: %d", n)
	}
}

func TestPhotosAreUploadedAttachedAndServed(t *testing.T) {
	ts := newTestServer(t, stubClient{details: map[string]places.Place{"a": {ID: "a", Name: "祠", Lat: 35, Lng: 135}}})
	jpeg := append([]byte{0xFF, 0xD8, 0xFF, 0xE0}, bytes.Repeat([]byte{1}, 100)...)
	code, body := call(t, ts, "POST", "/api/photos", "alice", string(jpeg))
	if code != 201 {
		t.Fatalf("got %d %v", code, body)
	}
	id := body["id"].(string)
	if code, _ := call(t, ts, "POST", "/api/photos", "alice", "not an image"); code != 400 {
		t.Errorf("画像でないものは受け付けない: %d", code)
	}

	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"a","lat":35,"lng":135}`)
	// ほかの人の写真は付けられない
	call(t, ts, "POST", "/api/checkins", "bob", `{"placeId":"a","lat":35,"lng":135}`)
	if code, _ := call(t, ts, "POST", "/api/logs", "bob", `{"placeId":"a","rating":4,"photoId":"`+id+`"}`); code != 400 {
		t.Errorf("ほかの人の写真を付けた: %d", code)
	}
	code, created := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","rating":5,"public":true,"genre":"worship","photoId":"`+id+`"}`)
	if code != 201 || created["photoId"] != id || created["genre"] != "worship" {
		t.Fatalf("写真とジャンルを記録に残す: %d %v", code, created)
	}
	_, tl := call(t, ts, "GET", "/api/timeline?lat=35&lng=135", "bob", "")
	if e := tl["entries"].([]any)[0].(map[string]any); e["photoId"] != id || e["genre"] != "worship" {
		t.Errorf("タイムラインにも写真とジャンルを出す: %v", e)
	}

	req, _ := http.NewRequest("GET", ts.URL+"/api/photos/"+id, nil)
	req.Header.Set("Authorization", "Bearer bob")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	got, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "image/jpeg" || !bytes.Equal(got, jpeg) {
		t.Errorf("写真を返す: %d %q %d bytes", resp.StatusCode, resp.Header.Get("Content-Type"), len(got))
	}
	if code, _ := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","rating":5,"genre":"spaceship"}`); code != 400 {
		t.Errorf("知らないジャンル: %d", code)
	}
}

func TestReactionsAreCountedOncePerPerson(t *testing.T) {
	ts := newTestServer(t, stubClient{details: map[string]places.Place{"a": {ID: "a", Name: "祠", Lat: 35, Lng: 135}}})
	call(t, ts, "POST", "/api/checkins", "alice", `{"placeId":"a","lat":35,"lng":135}`)
	_, created := call(t, ts, "POST", "/api/logs", "alice", `{"placeId":"a","rating":5,"public":true}`)
	_, tl := call(t, ts, "GET", "/api/timeline?lat=35&lng=135", "bob", "")
	entryID := tl["entries"].([]any)[0].(map[string]any)["id"].(string)

	call(t, ts, "PUT", "/api/timeline/"+entryID+"/reactions/want", "bob", "")
	code, body := call(t, ts, "PUT", "/api/timeline/"+entryID+"/reactions/want", "bob", "") // 重ねても数えない
	if code != 200 || body["wantCount"] != float64(1) || body["myWant"] != true {
		t.Fatalf("got %d %v", code, body)
	}
	call(t, ts, "PUT", "/api/timeline/"+entryID+"/reactions/helpful", "carol", "")
	if code, _ := call(t, ts, "PUT", "/api/timeline/"+entryID+"/reactions/want", "alice", ""); code != 400 {
		t.Errorf("自分の記録には反応できない: %d", code)
	}
	if code, _ := call(t, ts, "PUT", "/api/timeline/"+entryID+"/reactions/like", "bob", ""); code != 400 {
		t.Errorf("知らない反応: %d", code)
	}

	_, mine := call(t, ts, "GET", "/api/timeline?lat=35&lng=135", "bob", "")
	if e := mine["entries"].([]any)[0].(map[string]any); e["wantCount"] != float64(1) || e["helpfulCount"] != float64(1) || e["myWant"] != true || e["myHelpful"] != false {
		t.Errorf("タイムラインに数と自分の反応を出す: %v", e)
	}
	// 書いた人の記録の一覧にも、付いた反応の数を出す
	_, logs := call(t, ts, "GET", "/api/logs", "alice", "")
	if l := logs["logs"].([]any)[0].(map[string]any); l["id"] != created["id"] || l["wantCount"] != float64(1) || l["helpfulCount"] != float64(1) {
		t.Errorf("記録に反応の数を出す: %v", l)
	}

	_, body = call(t, ts, "DELETE", "/api/timeline/"+entryID+"/reactions/want", "bob", "")
	if body["wantCount"] != float64(0) || body["myWant"] != false {
		t.Errorf("外すと数が減る: %v", body)
	}
}
