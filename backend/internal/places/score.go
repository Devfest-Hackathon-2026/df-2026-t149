package places

import "math"

// 称号の値。アプリの PlaceTitle と同じ文字列。4つ以外の値を返すと、アプリは称号を表示できない。
const (
	TitleUntrodden = "untrodden" // 未踏
	TitleHidden    = "hidden"    // 穴場
	TitleKnown     = "known"     // 定番
	TitleFamous    = "famous"    // 超有名
)

// TitleThresholds は称号のレビュー数の上限（この数「以下」ならその称号）。
type TitleThresholds struct {
	Untrodden int
	Hidden    int
	Known     int
}

// Scorer は未知度スコアと称号を決める。
//
// TODO: 区切りと式は API 仕様で【未決】。今は Dart のサーバーと同じ値にしている。
// 企画書の5段階にするには、アプリの PlaceTitle と称号の色も増やす必要がある。
type Scorer struct {
	// ReferenceCount はスコアが0（誰でも知っている）になるレビュー数。
	ReferenceCount int
	Thresholds     TitleThresholds
}

var DefaultScorer = Scorer{
	ReferenceCount: 5000,
	Thresholds:     TitleThresholds{Untrodden: 10, Hidden: 100, Known: 1000},
}

// Score は 0〜100。レビュー数が少ないほど大きい。
// (1 − log(1+n) / log(1+ReferenceCount)) × 100 を四捨五入する。
func (s Scorer) Score(userRatingCount int) int {
	n := math.Max(0, float64(userRatingCount))
	v := 1 - math.Log1p(n)/math.Log1p(float64(s.ReferenceCount))
	return int(math.Round(math.Min(1, math.Max(0, v)) * 100))
}

func (s Scorer) Title(userRatingCount int) string {
	switch {
	case userRatingCount <= s.Thresholds.Untrodden:
		return TitleUntrodden
	case userRatingCount <= s.Thresholds.Hidden:
		return TitleHidden
	case userRatingCount <= s.Thresholds.Known:
		return TitleKnown
	default:
		return TitleFamous
	}
}

// Apply は p に未知度スコアと称号を付けた複製を返す。
func (s Scorer) Apply(p Place) Place {
	score := s.Score(p.UserRatingCount)
	p.Obscurity = &score
	p.Title = s.Title(p.UserRatingCount)
	return p
}

// DistanceMeters は2点間の距離（ハバーサインの公式）。
func DistanceMeters(lat1, lng1, lat2, lng2 float64) float64 {
	const earthRadius = 6371000.0
	rad := func(d float64) float64 { return d * math.Pi / 180 }
	dLat := rad(lat2 - lat1)
	dLng := rad(lng2 - lng1)
	h := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(rad(lat1))*math.Cos(rad(lat2))*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * earthRadius * math.Asin(math.Sqrt(h))
}

// OffsetPoint は基準地点から bearingDegrees の方向（北が 0、東が 90）へ meters だけ離れた地点を返す。
// 数 km の範囲を扱うので、地球を平面とみなす近似で足りる。
func OffsetPoint(lat, lng, meters, bearingDegrees float64) (float64, float64) {
	const earthRadius = 6371000.0
	metersPerDegree := earthRadius * math.Pi / 180
	bearing := bearingDegrees * math.Pi / 180
	dLat := meters * math.Cos(bearing) / metersPerDegree
	dLng := meters * math.Sin(bearing) / (metersPerDegree * math.Cos(lat*math.Pi/180))
	return lat + dLat, lng + dLng
}
