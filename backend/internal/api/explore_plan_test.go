package api

import (
	"net/url"
	"slices"
	"testing"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
)

func TestParsePopularity(t *testing.T) {
	for raw, want := range map[string]popularity{
		"":      {},
		"x":     {},
		"0,1":   {Min: 0, Max: 1, Set: true},
		"3,0":   {Min: 0, Max: 3, Set: true},
		"-5,9":  {Min: 0, Max: 3, Set: true},
		"2, 3":  {Min: 2, Max: 3, Set: true},
		"1,a":   {},
		"1,2,3": {},
	} {
		if got := parsePopularity(url.Values{"popularity": {raw}}); got != want {
			t.Errorf("%q: got %+v want %+v", raw, got, want)
		}
	}
}

func TestPlanExplore(t *testing.T) {
	obscure := popularity{Min: 0, Max: 1, Set: true}
	famous := popularity{Min: 2, Max: 3, Set: true}
	all := popularity{Min: 0, Max: 3, Set: true}

	// 狭い範囲は1地点。指定しなければ前と同じく近い順で1回
	if qs := planExplore(35, 135, 1500, popularity{}); len(qs) != 1 || !qs[0].ByDistance || qs[0].Radius != 1500 {
		t.Errorf("既定: %+v", qs)
	}
	if qs := planExplore(35, 135, 1500, famous); len(qs) != 1 || qs[0].ByDistance {
		t.Errorf("有名な場所だけ: %+v", qs)
	}
	if qs := planExplore(35, 135, 1500, all); len(qs) != 2 || qs[0].ByDistance == qs[1].ByDistance {
		t.Errorf("全部: %+v", qs)
	}
	// 3km からは複数の地点で探し、円の全体から拾う
	if qs := planExplore(35, 135, 3000, popularity{}); len(qs) != exploreMaxCalls {
		t.Errorf("3km: %+v", qs)
	}

	// 広い範囲は4地点。外側の地点は円の中に収まる
	for _, pop := range []popularity{obscure, famous, all} {
		qs := planExplore(35, 135, 30000, pop)
		if len(qs) != exploreMaxCalls {
			t.Fatalf("%+v: %d 地点", pop, len(qs))
		}
		for _, q := range qs {
			d := places.DistanceMeters(35, 135, q.Lat, q.Lng)
			if d+q.Radius > 30000*1.06 {
				t.Errorf("円からはみ出す: %+v（中心から %.0f m）", q, d)
			}
		}
		if qs[0].ByDistance == pop.wantsFamous() {
			t.Errorf("%+v: 中心の地点の並べ方 %+v", pop, qs[0])
		}
	}
}

func TestSortByPopularity(t *testing.T) {
	mk := func(id string, reviews int) places.Place {
		return places.DefaultScorer.Apply(places.Place{ID: id, UserRatingCount: reviews})
	}
	ps := func() []places.Place {
		return []places.Place{mk("famous", 9000), mk("known", 500), mk("hidden", 50), mk("untrodden", 2)}
	}
	ids := func(ps []places.Place) []string {
		out := []string{}
		for _, p := range ps {
			out = append(out, p.ID)
		}
		return out
	}
	got := ps()
	sortByPopularity(got, popularity{})
	if !slices.Equal(ids(got), []string{"untrodden", "hidden", "known", "famous"}) {
		t.Errorf("既定: %v", ids(got))
	}
	got = ps()
	sortByPopularity(got, popularity{Min: 2, Max: 3, Set: true})
	if !slices.Equal(ids(got), []string{"famous", "known", "hidden", "untrodden"}) {
		t.Errorf("有名な側: %v", ids(got))
	}
	got = ps()
	sortByPopularity(got, popularity{Min: 1, Max: 2, Set: true})
	if !slices.Equal(ids(got), []string{"hidden", "known", "untrodden", "famous"}) {
		t.Errorf("真ん中: %v", ids(got))
	}
}

func TestExploreWideRadiusSearchesSeveralPoints(t *testing.T) {
	log := &nearbyLog{}
	ts := newTestServer(t, stubClient{nearbyCalls: log, nearby: []places.Place{
		{ID: "a", Name: "a", Types: []string{"park"}, UserRatingCount: 3},
		{ID: "b", Name: "b", Types: []string{"park"}, UserRatingCount: 9000},
	}})
	code, body := call(t, ts, "GET", "/api/explore?lat=36.65&lng=138.18&radius=30000&popularity=0,3", "alice", "")
	if code != 200 {
		t.Fatalf("%d %v", code, body)
	}
	if n := len(log.all()); n != exploreMaxCalls {
		t.Errorf("Nearby Search を %d 回呼んだ", n)
	}
	// 同じ場所は1件にまとめる
	if ids := placeIDs(body); len(ids) != 2 {
		t.Errorf("重ねずに返す: %v", ids)
	}
	// 有名な場所を含む幅でも、知られていない場所から先に並べる（幅の真ん中が穴場と定番の間）
	if ids := placeIDs(body); ids[0] != "a" {
		t.Errorf("並び: %v", ids)
	}

	// チェックインは広い半径を受け付けず、5000 m に丸める
	log2 := &places.NearbyRequest{}
	ts2 := newTestServer(t, stubClient{gotNearby: log2})
	call(t, ts2, "GET", "/api/explore?lat=35&lng=135&radius=30000&purpose=checkin", "alice", "")
	if log2.RadiusMeters != checkinMaxRadius {
		t.Errorf("チェックインの半径: %v", log2.RadiusMeters)
	}
}

func TestExploreWithoutGenreSearchesVisitableTypes(t *testing.T) {
	var got places.NearbyRequest
	ts := newTestServer(t, stubClient{gotNearby: &got})
	call(t, ts, "GET", "/api/explore?lat=35&lng=135", "alice", "")
	if !slices.Equal(got.IncludedTypes, places.ExploreTypes) {
		t.Errorf("ジャンルなしは訪れられる種類で探す: %v", got.IncludedTypes)
	}
	// ジャンルを選んだときは、そのジャンルの種類で探す
	call(t, ts, "GET", "/api/explore?lat=35&lng=135&genre=food", "alice", "")
	if slices.Contains(got.IncludedTypes, "park") || !slices.Contains(got.IncludedTypes, "cafe") {
		t.Errorf("ジャンルを選んだとき: %v", got.IncludedTypes)
	}
	// チェックインの候補は種類で絞らない（今いる場所を取りこぼさない）
	call(t, ts, "GET", "/api/explore?lat=35&lng=135&purpose=checkin", "alice", "")
	if len(got.IncludedTypes) != 0 {
		t.Errorf("チェックイン: %v", got.IncludedTypes)
	}
}
