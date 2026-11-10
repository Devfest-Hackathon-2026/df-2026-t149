package places

import "slices"

// NonVisitablePrimaryTypes は、観光で訪れる場所にならない主な種類。
// Nearby Search の excludedPrimaryTypes に渡し、近い順の20件が住宅や美容室などで埋まらないようにする。
// Nearby Search は1つの条件に50種類までしか受け付けないため、近所の検索で多く返る種類から選んでいる。
var NonVisitablePrimaryTypes = []string{
	// 住宅
	"apartment_building", "apartment_complex", "condominium_complex", "housing_complex",
	// 店に入る目的の決まったサービス
	"barber_shop", "beauty_salon", "hair_salon", "hair_care", "nail_salon", "laundry",
	"consultant", "service", "lawyer", "real_estate_agency", "insurance_agency", "storage",
	"moving_company", "funeral_home", "electrician", "plumber", "painter", "courier_service",
	// 車と交通
	"car_dealer", "car_repair", "car_wash", "car_rental", "tire_shop", "gas_station",
	"parking", "parking_lot", "parking_garage",
	// 金融
	"accounting", "atm", "bank",
	// 医療
	"dentist", "dental_clinic", "doctor", "hospital", "medical_clinic", "pharmacy", "drugstore",
	"physiotherapist", "chiropractor",
	// 学校
	"preschool", "primary_school", "secondary_school", "school",
	// その他
	"manufacturer", "convenience_store",
}

// visitableTypes は、その種類を一つでも持てば訪れられる場所とみなす種類。
// 飲食店の細かい種類（ramen_restaurant など）には restaurant と food も付くため、上位の種類だけを並べる。
// food、landmark、natural_feature、place_of_worship、town_square は検索の条件に使えない種類だが、応答の types には付く。
var visitableTypes = []string{
	// 飲食と買い物
	"food", "restaurant", "cafe", "coffee_shop", "tea_house", "bakery", "store", "market", "shopping_mall",
	// 文化
	"art_gallery", "art_museum", "art_studio", "castle", "cultural_landmark", "fountain", "historical_place",
	"history_museum", "monument", "museum", "performing_arts_theater", "sculpture", "cultural_center",
	"library",
	// 娯楽
	"amusement_center", "amusement_park", "aquarium", "botanical_garden", "city_park", "garden",
	"hiking_area", "historical_landmark", "national_park", "observation_deck", "park", "picnic_ground",
	"planetarium", "plaza", "tourist_attraction", "visitor_center", "zoo", "wildlife_park", "movie_theater",
	"video_arcade", "karaoke", "bowling_alley", "public_bath",
	// 自然
	"beach", "island", "lake", "mountain_peak", "nature_preserve", "river", "scenic_spot", "woods",
	"natural_feature",
	// 寺社
	"buddhist_temple", "shinto_shrine", "church", "place_of_worship",
	// 種類の細かくない名所
	"landmark", "town_square",
}

// ExploreTypes は、ジャンルを選んでいないときに Nearby Search の includedTypes に渡す種類。
//
// 種類で絞らずに近い順の20件を受け取ると、会社や店や停留所で埋まり、訪れられる場所が数件しか残らない。
// 訪れられる種類に絞ると20件のほとんどが候補になり、近い順でも少し遠くの場所まで届く。
// Nearby Search は1つの条件に50種類までしか受け付けないため、visitableTypes から検索の条件に使える種類を選び、
// 種類の広すぎる store や、目的の決まった娯楽（映画館・カラオケなど）は入れない。
// 名前の変わった停留所を Gemini に選ばせるため、停留所の種類も入れる。
var ExploreTypes = []string{
	// 飲食
	"restaurant", "cafe", "coffee_shop", "tea_house", "bakery", "market",
	// 文化
	"art_gallery", "art_museum", "castle", "cultural_landmark", "historical_place", "history_museum",
	"monument", "museum", "performing_arts_theater", "cultural_center", "sculpture", "fountain",
	// 娯楽
	"amusement_park", "aquarium", "botanical_garden", "city_park", "garden", "hiking_area",
	"historical_landmark", "national_park", "observation_deck", "park", "picnic_ground", "planetarium",
	"plaza", "tourist_attraction", "visitor_center", "zoo", "wildlife_park", "public_bath",
	// 自然
	"beach", "island", "lake", "mountain_peak", "nature_preserve", "river", "scenic_spot", "woods",
	// 寺社
	"buddhist_temple", "shinto_shrine", "church",
	// 停留所
	"bus_stop", "train_station", "transit_station",
}

// notableRatingCount 以上の口コミがある場所は、種類が会社などでも人が見に行く場所として残す。
const notableRatingCount = 100

// IsVisitable は、観光で訪れる場所として提案できるか。
// NonVisitablePrimaryTypes の場所は、口コミが多くても除く。
func IsVisitable(p Place) bool {
	if slices.Contains(NonVisitablePrimaryTypes, p.PrimaryType) {
		return false
	}
	if p.UserRatingCount >= notableRatingCount {
		return true
	}
	return slices.ContainsFunc(p.Types, func(t string) bool { return slices.Contains(visitableTypes, t) })
}

// publicStopTypes は、誰でも立ち寄れるが、名前が変わっているときだけ提案する停留所の種類。
// 検索の条件で除くと名前を確かめられないため、NonVisitablePrimaryTypes には入れない。
var publicStopTypes = []string{"bus_stop", "transit_stop", "transit_station", "train_station", "subway_station", "light_rail_station", "tram_stop"}

// IsPublicStop は、バス停や駅などの停留所か。
func IsPublicStop(p Place) bool {
	return slices.Contains(publicStopTypes, p.PrimaryType) ||
		slices.ContainsFunc(p.Types, func(t string) bool { return slices.Contains(publicStopTypes, t) })
}
