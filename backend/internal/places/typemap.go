package places

// alternativeTypes は「有名スポットの種類 → 代わりに探す種類」の対応表。
// 削除した Dart のサーバー（server/lib/src/features/alternatives/type_mapping.dart）と同じ。
//
// Places API (New) の種類の一覧:
// https://developers.google.com/maps/documentation/places/web-service/place-types
var alternativeTypes = map[string][]string{
	"tourist_attraction": sightseeingTypes,
	"buddhist_temple":    {"buddhist_temple", "shinto_shrine"},
	"shinto_shrine":      {"shinto_shrine", "buddhist_temple"},
	"park":               {"park", "city_park", "garden", "hiking_area"},
	"museum":             {"museum", "art_gallery", "cultural_center"},
	"cafe":               {"cafe", "coffee_shop", "tea_house"},
	"restaurant":         {"restaurant"},
	"shopping_mall":      {"market", "store"},
	"observation_deck":   sightseeingTypes,
}

// sightseeingTypes は観光名所の代わりに探す種類。公園を含めると、住宅地の児童公園が候補の大半を占める。
var sightseeingTypes = []string{"tourist_attraction", "historical_landmark", "museum", "art_gallery", "garden", "observation_deck"}

// defaultAlternativeTypes は対応表にない種類のスポットで使う。
var defaultAlternativeTypes = sightseeingTypes

// AlternativeTypesFor はスポットの種類から、代わりに探す種類を決める。
// primaryType を先に、次に types を順に見て、最初に対応表にあったものを使う。
func AlternativeTypesFor(primaryType string, types []string) []string {
	candidates := append([]string{primaryType}, types...)
	for _, t := range candidates {
		if hit, ok := alternativeTypes[t]; ok {
			return hit
		}
	}
	return defaultAlternativeTypes
}
