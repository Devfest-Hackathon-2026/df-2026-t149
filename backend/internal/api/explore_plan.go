package api

import (
	"cmp"
	"context"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"sync"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
)

// 未踏サーチの検索範囲と人気度の扱い。
//
// Nearby Search は1回で20件しか返さない。近い順で探すと中心のまわりの20件で埋まり、
// 人気順で探すと知られた場所で埋まる。そこで、
//   - 3km 以上（multiPointRadius）の範囲は、円の中の複数の地点で探して、範囲の全体から拾う
//   - 人気度の幅に有名な場所を含むときは人気順でも探し、知られていない場所を含むときは近い順でも探す
//
// 呼び出しの回数は最大でも exploreMaxCalls 回にする（1人あたりの1日の上限で使い切らないため）。
const (
	// exploreMaxRadius は未踏サーチの半径の上限（m）。Places API の Nearby Search の上限と同じ
	exploreMaxRadius = 50000
	// checkinMaxRadius はチェックインの候補を探す半径の上限（m）
	checkinMaxRadius = 5000
	// wideRadius より大きい半径を「広い範囲」とし、返す件数を増やす
	wideRadius = 5000
	// multiPointRadius 以上の半径は、複数の地点で探す。1地点の近い順の20件では、円の中心のまわりしか拾えないため
	multiPointRadius = 3000
	// 広い範囲で、外側の地点を中心から離す距離と、各地点の検索半径の、全体の半径に対する割合
	wideOffsetShare = 0.6
	wideReachShare  = 0.45
	// 広い範囲で返す件数の上限
	wideMaxResults = 40
	// exploreMaxCalls は1回の検索で Places API を呼ぶ回数の上限
	exploreMaxCalls = 4
)

// 広い範囲で外側の地点を置く方向（北が 0）
var wideBearings = [...]float64{0, 120, 240}

// popularity は人気度の幅。称号の段階（0 未踏・1 穴場・2 定番・3 超有名）で表す。
type popularity struct {
	Min, Max int
	// Set は popularity を指定したか。指定しなければ前と同じ動き（近い順で1回探し、知られていない順に並べる）にする
	Set bool
}

func (p popularity) wantsObscure() bool { return !p.Set || p.Min <= 1 }
func (p popularity) wantsFamous() bool  { return p.Set && p.Max >= 2 }

// parsePopularity は popularity=0,3 のような値を読む。読めない値は指定しなかったことにする。
func parsePopularity(q url.Values) popularity {
	parts := strings.Split(q.Get("popularity"), ",")
	if len(parts) != 2 {
		return popularity{}
	}
	lo, err1 := strconv.Atoi(strings.TrimSpace(parts[0]))
	hi, err2 := strconv.Atoi(strings.TrimSpace(parts[1]))
	if err1 != nil || err2 != nil {
		return popularity{}
	}
	lo, hi = min(max(lo, 0), 3), min(max(hi, 0), 3)
	if lo > hi {
		lo, hi = hi, lo
	}
	return popularity{Min: lo, Max: hi, Set: true}
}

// titleLevel は称号を人気度の段階にする。
func titleLevel(title string) int {
	switch title {
	case places.TitleUntrodden:
		return 0
	case places.TitleHidden:
		return 1
	case places.TitleKnown:
		return 2
	default:
		return 3
	}
}

// exploreQuery は Nearby Search を1回呼ぶ条件。
type exploreQuery struct {
	Lat, Lng, Radius float64
	ByDistance       bool
}

// planExplore は検索する地点と並べ方を決める。
func planExplore(lat, lng, radius float64, pop popularity) []exploreQuery {
	if radius < multiPointRadius {
		var qs []exploreQuery
		if pop.wantsObscure() {
			qs = append(qs, exploreQuery{lat, lng, radius, true})
		}
		if pop.wantsFamous() {
			qs = append(qs, exploreQuery{lat, lng, radius, false})
		}
		return qs
	}
	// 中心の地点は、有名な場所を含むなら人気順、含まなければ近い順で探す
	qs := []exploreQuery{{lat, lng, radius * wideReachShare, !pop.wantsFamous()}}
	for _, bearing := range wideBearings {
		pLat, pLng := places.OffsetPoint(lat, lng, radius*wideOffsetShare, bearing)
		// 外側の地点は、知られていない場所を含むなら近い順で探す
		qs = append(qs, exploreQuery{pLat, pLng, radius * wideReachShare, pop.wantsObscure()})
	}
	return qs[:min(len(qs), exploreMaxCalls)]
}

// runExplore は planExplore の条件で並行して探し、place ID で重ねずにまとめる。
// 1つでも本物の結果が返れば、ダミーの結果を混ぜない（架空の場所を本物と一緒に見せないため）。
func (s *Server) runExplore(ctx context.Context, base places.NearbyRequest, qs []exploreQuery, feature string, forceMock bool) ([]places.Place, string, error) {
	type result struct {
		found  []places.Place
		source string
		err    error
	}
	results := make([]result, len(qs))
	var wg sync.WaitGroup
	for i, q := range qs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := base
			req.Lat, req.Lng, req.RadiusMeters, req.RankByDistance = q.Lat, q.Lng, q.Radius, q.ByDistance
			found, source, err := s.Places.Nearby(ctx, req, feature, forceMock)
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
	switch {
	case realOK:
		return dedupePlaces(real), places.SourceGoogle, nil
	case mockOK:
		return dedupePlaces(mock), places.SourceMock, nil
	default:
		return nil, "", firstErr
	}
}

func dedupePlaces(ps []places.Place) []places.Place {
	seen := map[string]bool{}
	out := make([]places.Place, 0, len(ps))
	for _, p := range ps {
		if seen[p.ID] {
			continue
		}
		seen[p.ID] = true
		out = append(out, p)
	}
	return out
}

// sortByPopularity は人気度の幅の中の場所を先に、幅に近い場所を後に並べる。
// 幅の中では、知られていない側の幅なら知られていない順、有名な側の幅なら口コミの多い順にする。
func sortByPopularity(ps []places.Place, pop popularity) {
	if !pop.Set {
		slices.SortStableFunc(ps, func(a, b places.Place) int { return cmp.Compare(*b.Obscurity, *a.Obscurity) })
		return
	}
	outside := func(p places.Place) int {
		l := titleLevel(p.Title)
		switch {
		case l < pop.Min:
			return pop.Min - l
		case l > pop.Max:
			return l - pop.Max
		default:
			return 0
		}
	}
	famousSide := pop.Min+pop.Max >= 4 // 幅の真ん中が定番より有名
	slices.SortStableFunc(ps, func(a, b places.Place) int {
		if c := cmp.Compare(outside(a), outside(b)); c != 0 {
			return c
		}
		if famousSide {
			return cmp.Compare(b.UserRatingCount, a.UserRatingCount)
		}
		return cmp.Compare(*b.Obscurity, *a.Obscurity)
	})
}
