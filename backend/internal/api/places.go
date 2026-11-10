package api

import (
	"cmp"
	"context"
	"errors"
	"math"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"sync"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
)

// GET /api/explore?lat=34.69&lng=135.19&radius=1500[&genre=food,other][&popularity=0,1][&purpose=checkin][&mock=1] — 未踏サーチ
//
// 地図の中心付近の場所を探し、未知度スコアの高い順に返す。
// radius は 50000 まで受け付ける。3000 以上の範囲は、円の中の複数の地点で探す（explore_plan.go）。
// ジャンルを選んでいなければ、訪れられる種類（places.ExploreTypes）に絞って探す。
//
// popularity は人気度の幅で、称号の段階（0 未踏・1 穴場・2 定番・3 超有名）を「最小,最大」で送る。
// 有名な場所を含む幅なら人気順でも探し、幅の中の場所から先に並べる。指定しなければ前と同じ動きにする。
//
// purpose=checkin はチェックインの候補を探す。最寄りのスポットを取りこぼさないよう近い順の上位を受け取り、
// 地図と同じく訪れられる場所に絞る（近くに1つもなければ絞らない）。
// 本物の API が失敗したときは 503 を返す（ダミーのスポットにチェックインさせないため）。
func (s *Server) getExplore(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	lat, okLat := parseFloat(q.Get("lat"))
	lng, okLng := parseFloat(q.Get("lng"))
	if !okLat || !okLng || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return apierr.New(apierr.BadRequest, "lat と lng を数値で指定してください")
	}
	forCheckin := q.Get("purpose") == "checkin"
	maxRadius := float64(exploreMaxRadius)
	if forCheckin {
		maxRadius = checkinMaxRadius
	}
	radius := queryRadius(q, 1500, 100, maxRadius)

	feature := places.FeatureExplore
	if forCheckin {
		feature = places.FeatureCheckin
	}
	included, excluded, err := places.GenreFilter(splitCSV(q.Get("genre")))
	if err != nil {
		return apierr.New(apierr.BadRequest, "genre の値が正しくありません")
	}
	// 既定の人気順では知られた場所だけで埋まるため、近い順の上位を受け取る
	req := places.NearbyRequest{
		Lat: lat, Lng: lng, RadiusMeters: radius, MaxResults: 20, RankByDistance: true,
		IncludedTypes: included, ExcludedTypes: excluded,
	}
	var found []places.Place
	var source string
	pop := popularity{}
	if forCheckin {
		// 種類で絞って探すと最寄りの場所を取りこぼすため、絞らずに探してから訪れられる場所を選ぶ
		found, source, err = s.Places.Nearby(r.Context(), req, feature, isMock(q))
	} else {
		req.ExcludedPrimaryTypes = places.NonVisitablePrimaryTypes
		// ジャンルを選んでいなければ、訪れられる種類に絞って20件を候補で埋める
		if len(included) == 0 && len(excluded) == 0 {
			req.IncludedTypes = places.ExploreTypes
		}
		pop = parsePopularity(q)
		found, source, err = s.runExplore(r.Context(), req, planExplore(lat, lng, radius, pop), feature, isMock(q))
	}
	if err != nil {
		if forCheckin && errors.Is(err, places.ErrDailyLimit) {
			return apierr.Wrap(apierr.DailyLimit, err, "今日はこれ以上、近くのスポットを探せません。地図で選んだ場所からチェックインできます")
		}
		if forCheckin {
			return apierr.Wrap(apierr.PlacesUnavailable, err, "近くのスポットを読み込めませんでした")
		}
		return placesError(err, "場所を探せませんでした。少し待ってからもう一度試してください")
	}

	if !forCheckin {
		found = s.visitable(r.Context(), found)
	} else if v := s.visitable(r.Context(), found); len(v) > 0 {
		// 地図と同じく訪れられる場所だけを候補にし、地図とチェックインで出る場所をそろえる。
		// 近くに1つもなければ、今いる場所が会社や駐車場でもチェックインできるよう、絞らずに返す
		found = v
	}
	scored := make([]places.Place, len(found))
	for i, p := range found {
		scored[i] = s.Scorer.Apply(p)
	}
	sortByPopularity(scored, pop)
	if radius > wideRadius && len(scored) > wideMaxResults {
		scored = scored[:wideMaxResults]
	}
	// mock=1 のダミーの場所は、アプリが端末だけで記録し、集計にない。Firestore を読まずに返す
	if !isMock(q) {
		s.addVerdictCounts(r, scored)
	}

	writeJSON(w, http.StatusOK, exploreResponse{Source: source, Places: scored})
	return nil
}

// visitable は、訪れられる場所だけを返す。
// 以前は名前の変わった停留所を Gemini に選ばせて残していたが、Places API の結果を Gemini に渡さないためやめた（D-036）
func (s *Server) visitable(_ context.Context, found []places.Place) []places.Place {
	out := make([]places.Place, 0, len(found))
	for _, p := range found {
		if places.IsVisitable(p) {
			out = append(out, p)
		}
	}
	return out
}

// addVerdictCounts は場所に当たりとハズレの数を付ける。読めなくても検索の結果は返す。
func (s *Server) addVerdictCounts(r *http.Request, ps []places.Place) {
	ids := make([]string, len(ps))
	for i, p := range ps {
		ids[i] = p.ID
	}
	counts, err := s.Store.VerdictCounts(r.Context(), ids)
	if err != nil {
		s.Log.WarnContext(r.Context(), "当たりとハズレの数を読めません", "err", err)
		return
	}
	for i := range ps {
		c := counts[ps[i].ID]
		ps[i].Hits, ps[i].Misses = c.Hits, c.Misses
		if c.RatingCount > 0 {
			avg := math.Round(float64(c.RatingSum)/float64(c.RatingCount)*10) / 10
			ps[i].Stars, ps[i].StarCount = &avg, c.RatingCount
		}
	}
}

// GET /api/locate?q=嵐山[&mock=1] — 地図を移動する先を探す
func (s *Server) getLocate(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	query := strings.TrimSpace(q.Get("q"))
	if query == "" {
		return apierr.New(apierr.BadRequest, "q（場所の名前）を指定してください")
	}
	p, source, err := s.Places.Locate(r.Context(), query, isMock(q))
	if errors.Is(err, places.ErrPlaceNotFound) {
		return apierr.New(apierr.PlaceNotFound, "「%s」が見つかりませんでした", query)
	}
	if err != nil {
		return placesError(err, "場所を探せませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"source": source, "name": p.Name, "lat": p.Lat, "lng": p.Lng})
	return nil
}

// placesError は Places API を呼べなかった理由を、アプリに返すエラーにする。
// 1日の上限なら 429 daily_limit（今日は直らない）、それ以外は 503 places_unavailable（少し待てば直ることがある）。
func placesError(err error, message string) *apierr.Error {
	if errors.Is(err, places.ErrDailyLimit) {
		return apierr.Wrap(apierr.DailyLimit, err, "今日はこれ以上、場所を探せません。明日また試してください")
	}
	return apierr.Wrap(apierr.PlacesUnavailable, err, message)
}

func splitCSV(raw string) []string {
	out := []string{}
	for _, v := range strings.Split(raw, ",") {
		if v = strings.TrimSpace(v); v != "" {
			out = append(out, v)
		}
	}
	return out
}

// レスポンスは構造体にして、項目の順番を Dart のサーバーと同じにする。
// アプリのダミー（app/assets/mock/）を作り直したときに、余計な差分が出ないようにするため。
type exploreResponse struct {
	Source string         `json:"source"`
	Places []places.Place `json:"places"`
}

type alternativesResponse struct {
	Source       string         `json:"source"`
	Origin       places.Place   `json:"origin"`
	Alternatives []places.Place `json:"alternatives"`
}

// 代替提案の条件。本物の Places API の応答を比べて決めた値
const (
	maxAlternatives = 10
	// 有名スポットの敷地内の場所を除く距離（m）。敷地内でも containingPlaces を返さない場所がある
	alternativeMinDistance = 300
	// 門や像などの個別の設備を除くレビュー数の下限
	alternativeMinReviews = 20
	// 検索する地点を有名スポットから離す距離と、各地点の検索半径の、指定された半径に対する割合
	alternativeSearchShare = 0.4
)

// 検索する地点の方向（北が 0）
var alternativeBearings = [...]float64{0, 120, 240}

// GET /api/alternatives?q=清水寺&radius=3000[&mock=1] — 代わりに行くならここ
//
//  1. Text Search で有名スポットを1件に決める
//  2. その周囲の3地点を、種類の対応表で決めた種類で Nearby Search する
//  3. 独立した場所で、有名スポットより知られていない場所だけ残し、近い順に並べる
//
// アプリは radius に 3000・6000・10000 を送る。
func (s *Server) getAlternatives(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	query := strings.TrimSpace(q.Get("q"))
	if query == "" {
		return apierr.New(apierr.BadRequest, "q（有名スポットの名前）を指定してください")
	}
	origin, picked, source, err := s.findAlternatives(r.Context(), query, queryRadius(q, 3000, 500, 10000), isMock(q), places.FeatureAlternatives)
	if errors.Is(err, errOriginNotFound) {
		return apierr.New(apierr.OriginNotFound, "「%s」が見つかりませんでした", query)
	}
	if err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, alternativesResponse{Source: source, Origin: origin, Alternatives: picked})
	return nil
}

// errOriginNotFound は、代わりを探す有名スポットが見つからないこと。
var errOriginNotFound = errors.New("origin not found")

// findAlternatives は有名スポットを1件に決め、その周辺から代わりの場所を選ぶ。
// 代わりに行くならここ（GET /api/alternatives）と Geminiちゃん（POST /api/assistant）で使う。
// feature は Places API の呼び出し回数の記録で、どの機能が呼んだかを区別するため。
func (s *Server) findAlternatives(ctx context.Context, query string, radius float64, forceMock bool, feature string) (places.Place, []places.Place, string, error) {
	found, textSource, err := s.Places.Text(ctx, query, 1, feature, forceMock)
	if err != nil {
		return places.Place{}, nil, "", placesError(err, "有名スポットを探せませんでした")
	}
	if len(found) == 0 {
		return places.Place{}, nil, "", errOriginNotFound
	}
	origin := s.Scorer.Apply(found[0])

	nearby, nearbySource, err := s.searchAroundOrigin(ctx, origin, radius, feature,
		forceMock || (textSource == places.SourceMock && s.Places.IsLive()))
	if err != nil {
		return places.Place{}, nil, "", placesError(err, "周辺の場所を探せませんでした")
	}

	// 件数が足りなくても条件はゆるめない。有名な場所を代わりとして見せないため、少ないときはアプリが範囲を広げる操作を示す
	picked := []places.Place{}
	seen := map[string]bool{origin.ID: true}
	for _, p := range nearby {
		if seen[p.ID] {
			continue
		}
		seen[p.ID] = true
		p = s.Scorer.Apply(p)
		d := int(math.Round(places.DistanceMeters(origin.Lat, origin.Lng, p.Lat, p.Lng)))
		if p.Contained || d < alternativeMinDistance || p.UserRatingCount < alternativeMinReviews ||
			*p.Obscurity <= *origin.Obscurity || p.Title == places.TitleFamous {
			continue
		}
		p.DistanceMeters = &d
		picked = append(picked, p)
	}
	// 口コミの少なさで並べると石碑のような場所が先頭に来るため、条件を満たす場所を近い順に並べる
	slices.SortStableFunc(picked, func(a, b places.Place) int {
		return cmp.Compare(*a.DistanceMeters, *b.DistanceMeters)
	})
	if len(picked) > maxAlternatives {
		picked = picked[:maxAlternatives]
	}

	source := places.SourceGoogle
	if textSource == places.SourceMock || nearbySource == places.SourceMock {
		source = places.SourceMock
	}
	return origin, picked, source, nil
}

// searchAroundOrigin は有名スポットの周囲の3地点を人気順で検索し、結果をまとめて返す。
//
// 有名スポットを中心に近い順で探すと敷地内の場所で20件が埋まり、人気順で探すと近隣の有名な場所で埋まる。
// 中心を外して検索範囲を小さくすると、人気順の上位に知られていない場所が入る。
// 円は有名スポットを通るので、近い場所も検索範囲に含まれる。
func (s *Server) searchAroundOrigin(ctx context.Context, origin places.Place, radius float64, feature string, forceMock bool) ([]places.Place, string, error) {
	type result struct {
		found  []places.Place
		source string
		err    error
	}
	reach := radius * alternativeSearchShare
	types := places.AlternativeTypesFor(origin.PrimaryType, origin.Types)
	results := make([]result, len(alternativeBearings))
	var wg sync.WaitGroup
	for i, bearing := range alternativeBearings {
		wg.Add(1)
		go func() {
			defer wg.Done()
			lat, lng := places.OffsetPoint(origin.Lat, origin.Lng, reach, bearing)
			found, source, err := s.Places.Nearby(ctx, places.NearbyRequest{
				Lat: lat, Lng: lng, RadiusMeters: reach,
				IncludedPrimaryTypes: types,
				MaxResults:           20,
			}, feature, forceMock)
			results[i] = result{found, source, err}
		}()
	}
	wg.Wait()

	var real, mock []places.Place
	var realOK, mockOK bool
	var firstErr error
	for _, r := range results {
		switch {
		case r.err != nil:
			firstErr = cmp.Or(firstErr, r.err)
		case r.source == places.SourceMock:
			mock, mockOK = append(mock, r.found...), true
		default:
			real, realOK = append(real, r.found...), true
		}
	}
	// 1地点だけ失敗したときは、本物の結果に架空の場所を混ぜないよう、その地点のダミーを捨てる
	switch {
	case realOK:
		return real, places.SourceGoogle, nil
	case mockOK:
		return mock, places.SourceMock, nil
	default:
		return nil, "", firstErr
	}
}

func isMock(q url.Values) bool { return q.Get("mock") == "1" }

func parseFloat(s string) (float64, bool) {
	v, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) {
		return 0, false
	}
	return v, true
}

// queryRadius は radius を読む。ない・読めないときは def、範囲外はエラーにせず範囲内に丸める。
func queryRadius(q url.Values, def, lo, hi float64) float64 {
	v, ok := parseFloat(q.Get("radius"))
	if !ok {
		v = def
	}
	return min(max(v, lo), hi)
}
