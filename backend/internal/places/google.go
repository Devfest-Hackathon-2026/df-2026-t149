package places

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"slices"
	"time"
)

const googleBaseURL = "https://places.googleapis.com/v1"

// 取得する項目。項目によって料金の区分が変わる（rating と userRatingCount を含むので Enterprise 区分）。
// 足すときは docs/decisions.md に理由を書く。
const fieldMask = "places.id,places.displayName,places.location,places.types,places.primaryType," +
	"places.userRatingCount,places.rating,places.formattedAddress,places.businessStatus,places.containingPlaces"

// locateFieldMask は地図を移動する先の検索で取得する項目。
const locateFieldMask = "places.id,places.displayName,places.location"

// GoogleClient は Places API (New) を呼ぶ本物のクライアント。
// 1日の上限は Gateway が確かめる。
type GoogleClient struct {
	apiKey  string
	http    *http.Client
	baseURL string
}

func NewGoogleClient(apiKey string) *GoogleClient {
	return &GoogleClient{
		apiKey:  apiKey,
		http:    &http.Client{Timeout: 8 * time.Second}, // アプリは10秒で諦めるので、それより短くする
		baseURL: googleBaseURL,
	}
}

func (c *GoogleClient) SearchNearby(ctx context.Context, req NearbyRequest) ([]Place, error) {
	body := map[string]any{
		"maxResultCount": clampInt(maxOr20(req.MaxResults), 1, 20),
		"languageCode":   "ja",
		"locationRestriction": map[string]any{
			"circle": map[string]any{
				"center": map[string]float64{"latitude": req.Lat, "longitude": req.Lng},
				"radius": clampFloat(req.RadiusMeters, 1, 50000),
			},
		},
	}
	if len(req.IncludedTypes) > 0 {
		body["includedTypes"] = req.IncludedTypes
	}
	if len(req.IncludedPrimaryTypes) > 0 {
		body["includedPrimaryTypes"] = req.IncludedPrimaryTypes
	}
	if len(req.ExcludedTypes) > 0 {
		body["excludedTypes"] = req.ExcludedTypes
	}
	if len(req.ExcludedPrimaryTypes) > 0 {
		body["excludedPrimaryTypes"] = req.ExcludedPrimaryTypes
	}
	if req.RankByDistance {
		body["rankPreference"] = "DISTANCE"
	}
	found, err := c.post(ctx, "/places:searchNearby", body, fieldMask)
	if err != nil {
		return nil, err
	}
	return convert(slices.DeleteFunc(found, apiPlace.isClosed)), nil
}

// PhotoURI は Place Photos の media を skipHttpRedirect=true で呼び、画像の URL を返す。
// 画像そのものを中継せず、API キーを含まない URL をアプリに渡すため。
func (c *GoogleClient) PhotoURI(ctx context.Context, photoName string, maxWidthPx int) (string, error) {
	q := url.Values{"maxWidthPx": {fmt.Sprint(maxWidthPx)}, "skipHttpRedirect": {"true"}}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/"+photoName+"/media?"+q.Encode(), nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("X-Goog-Api-Key", c.apiKey)
	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("Places API に接続できません: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return "", fmt.Errorf("Places API エラー %d: %s", resp.StatusCode, msg)
	}
	var body struct {
		PhotoURI string `json:"photoUri"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil || body.PhotoURI == "" {
		return "", fmt.Errorf("写真の URL を読めません: %v", err)
	}
	return body.PhotoURI, nil
}

func (c *GoogleClient) SearchText(ctx context.Context, query string, maxResults int) ([]Place, error) {
	found, err := c.post(ctx, "/places:searchText", map[string]any{
		"textQuery":    query,
		"languageCode": "ja",
		"pageSize":     clampInt(maxResults, 1, 20),
	}, fieldMask)
	if err != nil {
		return nil, err
	}
	return convert(found), nil
}

// SearchTextNear は地点の近くを優先して文字列で探す。円の外の場所も返ることがあるので、呼び出し元が距離で絞る。
func (c *GoogleClient) SearchTextNear(ctx context.Context, query string, lat, lng, radiusMeters float64, maxResults int) ([]Place, error) {
	found, err := c.post(ctx, "/places:searchText", map[string]any{
		"textQuery":    query,
		"languageCode": "ja",
		"pageSize":     clampInt(maxResults, 1, 20),
		"locationBias": map[string]any{
			"circle": map[string]any{
				"center": map[string]float64{"latitude": lat, "longitude": lng},
				"radius": math.Min(math.Max(radiusMeters, 1), 50000),
			},
		},
	}, fieldMask)
	if err != nil {
		return nil, err
	}
	return convert(found), nil
}

func (c *GoogleClient) GetPlace(ctx context.Context, id, fieldMask string) (Place, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		c.baseURL+"/places/"+url.PathEscape(id)+"?languageCode=ja", nil)
	if err != nil {
		return Place{}, err
	}
	req.Header.Set("X-Goog-Api-Key", c.apiKey)
	req.Header.Set("X-Goog-FieldMask", fieldMask)

	resp, err := c.http.Do(req)
	if err != nil {
		return Place{}, fmt.Errorf("Places API に接続できません: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		// 形の正しくない place ID は 400 になる。ただし API キーの誤りも 400 で返るので、
		// それを場所の問題として扱うと、アプリが正しい記録を送るのをやめてしまう
		invalidID := resp.StatusCode == http.StatusBadRequest && !bytes.Contains(msg, []byte("API_KEY"))
		if resp.StatusCode == http.StatusNotFound || invalidID {
			return Place{}, ErrPlaceNotFound
		}
		return Place{}, fmt.Errorf("Places API エラー %d: %s", resp.StatusCode, msg)
	}
	var p apiPlace
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		return Place{}, fmt.Errorf("Places API の応答を読めません: %w", err)
	}
	return p.toPlace(), nil
}

// LocatePlace は検索と違い位置と名前だけを読み、Text Search の Pro 区分で呼ぶ。
func (c *GoogleClient) LocatePlace(ctx context.Context, query string) (Place, error) {
	found, err := c.post(ctx, "/places:searchText", map[string]any{
		"textQuery":    query,
		"languageCode": "ja",
		"pageSize":     1,
	}, locateFieldMask)
	if err != nil {
		return Place{}, err
	}
	if len(found) == 0 {
		return Place{}, ErrPlaceNotFound
	}
	return found[0].toPlace(), nil
}

func (c *GoogleClient) post(ctx context.Context, path string, body any, mask string) ([]apiPlace, error) {
	b, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Goog-Api-Key", c.apiKey)
	req.Header.Set("X-Goog-FieldMask", mask)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Places API に接続できません: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("Places API エラー %d: %s", resp.StatusCode, msg)
	}
	var res struct {
		Places []apiPlace `json:"places"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return nil, fmt.Errorf("Places API の応答を読めません: %w", err)
	}
	return res.Places, nil
}

func maxOr20(n int) int {
	if n <= 0 {
		return 20
	}
	return n
}

func clampInt(v, lo, hi int) int { return min(max(v, lo), hi) }

func clampFloat(v, lo, hi float64) float64 { return min(max(v, lo), hi) }
