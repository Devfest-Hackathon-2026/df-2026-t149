package places

import (
	"fmt"
	"slices"
)

// GenreOther は、ほかのジャンルに入らない場所を表す。
const GenreOther = "other"

// genreTypes はジャンルと Places API の種類の対応。アプリの PlaceGenre と同じ ID を使う。
var genreTypes = map[string][]string{
	"food":     {"restaurant", "cafe", "coffee_shop", "tea_house"},
	"nature":   {"park", "garden", "hiking_area"},
	"worship":  {"buddhist_temple", "shinto_shrine"},
	"culture":  {"museum", "art_gallery", "cultural_center"},
	"view":     {"observation_deck", "tourist_attraction"},
	"shopping": {"market", "store", "shopping_mall"},
}

// GenreFilter は選んだジャンルを Nearby Search の条件に変える。
//
// 「その他」は種類の一覧で指定できないため、選んでいないジャンルの種類を除いて探す。
// 含む条件と除く条件を同時に送ると両方を満たす場所だけになり、「その他」が含む条件に絞られる。
func GenreFilter(ids []string) (included, excluded []string, err error) {
	for _, id := range ids {
		if _, ok := genreTypes[id]; !ok && id != GenreOther {
			return nil, nil, fmt.Errorf("不明なジャンル: %s", id)
		}
	}
	names := make([]string, 0, len(genreTypes))
	for name := range genreTypes {
		names = append(names, name)
	}
	slices.Sort(names)
	withOther := slices.Contains(ids, GenreOther)
	for _, name := range names {
		switch {
		case withOther && !slices.Contains(ids, name):
			excluded = append(excluded, genreTypes[name]...)
		case !withOther && slices.Contains(ids, name):
			included = append(included, genreTypes[name]...)
		}
	}
	return included, excluded, nil
}
