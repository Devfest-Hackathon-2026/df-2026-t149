package api

const (
	geohashAlphabet  = "0123456789bcdefghjkmnpqrstuvwxyz"
	geohashPrecision = 5
	// 5文字の区画の大きさ（度）。緯度方向は約 4.9 km で、周辺の探す範囲の広さに近い
	geohashCellDegrees = 0.0439
)

// geohash は位置を5文字の区画に変える。投稿の正確な位置を保存せず、周辺の記録を探せるようにする。
func geohash(lat, lng float64) string {
	latLo, latHi, lngLo, lngHi := -90.0, 90.0, -180.0, 180.0
	out := make([]byte, 0, geohashPrecision)
	bits, value, useLng := 0, 0, true
	for len(out) < geohashPrecision {
		value <<= 1
		if useLng {
			mid := (lngLo + lngHi) / 2
			if lng >= mid {
				value |= 1
				lngLo = mid
			} else {
				lngHi = mid
			}
		} else {
			mid := (latLo + latHi) / 2
			if lat >= mid {
				value |= 1
				latLo = mid
			} else {
				latHi = mid
			}
		}
		useLng = !useLng
		if bits++; bits == 5 {
			out = append(out, geohashAlphabet[value])
			bits, value = 0, 0
		}
	}
	return string(out)
}

// geohashesAround は指定した地点の区画と周囲の8区画を返す。
func geohashesAround(lat, lng float64) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, dLat := range []float64{-geohashCellDegrees, 0, geohashCellDegrees} {
		for _, dLng := range []float64{-geohashCellDegrees, 0, geohashCellDegrees} {
			h := geohash(min(max(lat+dLat, -90), 90), min(max(lng+dLng, -180), 180))
			if !seen[h] {
				seen[h] = true
				out = append(out, h)
			}
		}
	}
	return out
}
