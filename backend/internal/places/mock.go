package places

import (
	"cmp"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
)

// ダミーの JSON は Places API (New) の応答と同じ形。中身は架空のデータ（神戸周辺）。
// 本物の応答をそのまま置かないこと（Google Maps Platform の規約でコンテンツの保存が制限されている）。
// 削除した Dart のサーバーの server/mock/ と同じ内容。アプリの同梱のダミー（app/assets/mock/）もここから作る
// （app/tool/update_mock_assets.dart）。
var (
	//go:embed mockdata/nearby.json
	mockNearbyJSON []byte
	//go:embed mockdata/text_search.json
	mockTextJSON []byte
)

// MockClient はダミーの JSON を返す。API キーがないとき・デモの保険に使う。
// 動きは削除した Dart のサーバー（server/lib/src/places/mock_places_client.dart）と同じ。
type MockClient struct {
	nearby []Place
	text   []Place
}

func NewMockClient() (*MockClient, error) {
	nearby, err := parseMock(mockNearbyJSON)
	if err != nil {
		return nil, fmt.Errorf("mockdata/nearby.json: %w", err)
	}
	text, err := parseMock(mockTextJSON)
	if err != nil {
		return nil, fmt.Errorf("mockdata/text_search.json: %w", err)
	}
	return &MockClient{nearby: nearby, text: text}, nil
}

func parseMock(b []byte) ([]Place, error) {
	var res struct {
		Places []apiPlace `json:"places"`
	}
	if err := json.Unmarshal(b, &res); err != nil {
		return nil, err
	}
	return convert(res.Places), nil
}

// SearchNearby は、呼び出し地点がダミーの場所の重心から遠ければ（半径の3倍より遠ければ）、
// ダミーの並びをその地点へ平行移動して返す。どこで「このエリアを探す」を押しても画面が空にならない。
func (c *MockClient) SearchNearby(_ context.Context, req NearbyRequest) ([]Place, error) {
	ps := slices.Clone(c.nearby)
	if len(ps) == 0 {
		return []Place{}, nil
	}
	var cLat, cLng float64
	for _, p := range ps {
		cLat += p.Lat
		cLng += p.Lng
	}
	cLat /= float64(len(ps))
	cLng /= float64(len(ps))
	if DistanceMeters(req.Lat, req.Lng, cLat, cLng) > req.RadiusMeters*3 {
		for i := range ps {
			ps[i].Lat = ps[i].Lat - cLat + req.Lat
			ps[i].Lng = ps[i].Lng - cLng + req.Lng
		}
	}

	out := []Place{}
	for _, p := range ps {
		if slices.ContainsFunc(p.Types, func(t string) bool { return slices.Contains(req.ExcludedTypes, t) }) {
			continue
		}
		if len(req.IncludedTypes) > 0 && !slices.ContainsFunc(p.Types, func(t string) bool {
			return slices.Contains(req.IncludedTypes, t)
		}) {
			continue
		}
		if len(req.IncludedPrimaryTypes) > 0 && !slices.Contains(req.IncludedPrimaryTypes, p.PrimaryType) {
			continue
		}
		out = append(out, p)
		if len(out) == maxOr20(req.MaxResults) {
			break
		}
	}
	return out, nil
}

// SearchText は名前に query を含む場所を返す。見つからなくても先頭を返す（デモで「0件」にしないため）。
func (c *MockClient) SearchText(_ context.Context, query string, maxResults int) ([]Place, error) {
	q := strings.TrimSpace(query)
	var hits []Place
	for _, p := range c.text {
		if q != "" && strings.Contains(p.Name, q) {
			hits = append(hits, p)
		}
	}
	if len(hits) == 0 {
		hits = slices.Clone(c.text)
	}
	if maxResults > 0 && len(hits) > maxResults {
		hits = hits[:maxResults]
	}
	return hits, nil
}

// SearchTextNear は名前に query を含むダミーの場所を、近い順に返す。見つからなければ空。
func (c *MockClient) SearchTextNear(_ context.Context, query string, lat, lng, _ float64, maxResults int) ([]Place, error) {
	q := strings.TrimSpace(query)
	var hits []Place
	for _, list := range [][]Place{c.nearby, c.text} {
		for _, p := range list {
			if q != "" && strings.Contains(p.Name, q) && !slices.ContainsFunc(hits, func(h Place) bool { return h.ID == p.ID }) {
				hits = append(hits, p)
			}
		}
	}
	slices.SortFunc(hits, func(a, b Place) int {
		return cmp.Compare(DistanceMeters(lat, lng, a.Lat, a.Lng), DistanceMeters(lat, lng, b.Lat, b.Lng))
	})
	if maxResults > 0 && len(hits) > maxResults {
		hits = hits[:maxResults]
	}
	return hits, nil
}

// GetPlace はダミーの JSON から place ID の場所を返す。
func (c *MockClient) GetPlace(_ context.Context, id, _ string) (Place, error) {
	for _, list := range [][]Place{c.nearby, c.text} {
		if i := slices.IndexFunc(list, func(p Place) bool { return p.ID == id }); i >= 0 {
			return list[i], nil
		}
	}
	return Place{}, ErrPlaceNotFound
}

// LocatePlace は名前に query を含む場所を返す。見つからなくても先頭を返す（デモで移動先をなくさないため）。
func (c *MockClient) LocatePlace(ctx context.Context, query string) (Place, error) {
	hits, err := c.SearchText(ctx, query, 1)
	if err != nil || len(hits) == 0 {
		return Place{}, ErrPlaceNotFound
	}
	return hits[0], nil
}
