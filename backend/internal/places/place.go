// Package places は Places API (New) の呼び出しと、未知度スコア・称号の計算をまとめる。
//
// Google Maps の規約のため、ここで取得した内容は place ID を除いて Firestore に保存しない
// （docs/decisions.md の D-006）。
package places

// Place は場所1件。アプリ（app/lib/core/models/place.dart）がそのまま読める JSON の形。
//
// フィールドを足すのはよい（アプリは知らないフィールドを読み飛ばす）。
// 削除・改名・型の変更はアプリが壊れるのでしない。
type Place struct {
	ID              string   `json:"id"`
	Name            string   `json:"name"`
	Lat             float64  `json:"lat"`
	Lng             float64  `json:"lng"`
	Address         string   `json:"address,omitempty"`
	PrimaryType     string   `json:"primaryType,omitempty"`
	Types           []string `json:"types"`
	UserRatingCount int      `json:"userRatingCount"`
	Rating          *float64 `json:"rating,omitempty"`
	// Obscurity は未知度スコア（0〜100。大きいほど知られていない）。
	Obscurity *int `json:"obscurity,omitempty"`
	// Title は称号。TitleUntrodden などの4つの値のどれか。
	Title string `json:"title,omitempty"`
	// DistanceMeters は基準地点からの距離。代替提案の候補で、有名スポットからの距離を入れる。
	DistanceMeters *int `json:"distanceMeters,omitempty"`
	// Hits と Misses はウラミチの利用者が付けた当たりとハズレの数。
	Hits   int `json:"hits,omitempty"`
	Misses int `json:"misses,omitempty"`
	// Stars はウラミチの利用者が付けた★評価の平均（1〜5）、StarCount はその数。★評価がなければ省く
	Stars     *float64 `json:"stars,omitempty"`
	StarCount int      `json:"starCount,omitempty"`
	// Contained は別の場所の敷地や施設の中にある場所か。代替提案で、寺の中の門や像を除くために使う。
	Contained bool `json:"-"`
	// Photos は Place Details で photos を取得したときだけ入る。写真の名前（photos/...）はアプリに渡さない
	Photos []Photo `json:"-"`
}

// Photo は場所の写真1枚。Google Maps の規約で、撮影者（Attributions）を写真と一緒に表示する。
type Photo struct {
	// Name は Place Photos の media を呼ぶための名前（places/.../photos/...）。
	Name         string             `json:"-"`
	URL          string             `json:"url"`
	Width        int                `json:"width"`
	Height       int                `json:"height"`
	Attributions []PhotoAttribution `json:"attributions"`
}

// PhotoAttribution は写真の撮影者。URI は撮影者の Google マップのページ。
type PhotoAttribution struct {
	Name string `json:"name"`
	URI  string `json:"uri,omitempty"`
}

// apiPlace は Places API (New) の places[] の1件（ダミーの JSON も同じ形）。
type apiPlace struct {
	ID          string `json:"id"`
	DisplayName struct {
		Text string `json:"text"`
	} `json:"displayName"`
	Location struct {
		Latitude  float64 `json:"latitude"`
		Longitude float64 `json:"longitude"`
	} `json:"location"`
	FormattedAddress string   `json:"formattedAddress"`
	PrimaryType      string   `json:"primaryType"`
	Types            []string `json:"types"`
	UserRatingCount  int      `json:"userRatingCount"`
	Rating           *float64 `json:"rating"`
	BusinessStatus   string   `json:"businessStatus"`
	ContainingPlaces []struct {
		ID string `json:"id"`
	} `json:"containingPlaces"`
	Photos []struct {
		Name               string `json:"name"`
		WidthPx            int    `json:"widthPx"`
		HeightPx           int    `json:"heightPx"`
		AuthorAttributions []struct {
			DisplayName string `json:"displayName"`
			URI         string `json:"uri"`
		} `json:"authorAttributions"`
	} `json:"photos"`
}

// isClosed は閉業または休業中の場所か。行っても入れない場所を提案しないために使う。
func (p apiPlace) isClosed() bool {
	return p.BusinessStatus == "CLOSED_PERMANENTLY" || p.BusinessStatus == "CLOSED_TEMPORARILY"
}

func (p apiPlace) toPlace() Place {
	name := p.DisplayName.Text
	if name == "" {
		name = "(名前なし)"
	}
	types := p.Types
	if types == nil {
		types = []string{} // JSON で null ではなく [] にする
	}
	var photos []Photo
	for _, ph := range p.Photos {
		attrs := []PhotoAttribution{}
		for _, a := range ph.AuthorAttributions {
			attrs = append(attrs, PhotoAttribution{Name: a.DisplayName, URI: a.URI})
		}
		photos = append(photos, Photo{Name: ph.Name, Width: ph.WidthPx, Height: ph.HeightPx, Attributions: attrs})
	}
	return Place{
		Photos:          photos,
		ID:              p.ID,
		Name:            name,
		Lat:             p.Location.Latitude,
		Lng:             p.Location.Longitude,
		Address:         p.FormattedAddress,
		PrimaryType:     p.PrimaryType,
		Types:           types,
		UserRatingCount: p.UserRatingCount,
		Rating:          p.Rating,
		Contained:       len(p.ContainingPlaces) > 0,
	}
}

func convert(ps []apiPlace) []Place {
	out := make([]Place, len(ps))
	for i, p := range ps {
		out[i] = p.toPlace()
	}
	return out
}
