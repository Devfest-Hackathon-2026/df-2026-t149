package api

import (
	"errors"
	"net/http"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
)

// GET /api/places/{placeId}/photos — 場所の写真（Google マップの写真）
//
// 写真の画像の URL は短い時間だけ使えるので、アプリは保存せずにその場で表示する。
// Google Maps の規約で、写真と一緒に撮影者（attributions）を表示する。
// API キーがないとき（ダミー）は写真を返さない。
func (s *Server) getPlacePhotos(w http.ResponseWriter, r *http.Request) error {
	placeID, err := validPlaceID(r.PathValue("placeId"))
	if err != nil {
		return err
	}
	photos, source, err := s.Places.PlacePhotos(r.Context(), placeID, places.MaxPhotos)
	if errors.Is(err, places.ErrPlaceNotFound) {
		return apierr.New(apierr.PlaceNotFound, "この場所は見つかりませんでした")
	}
	if errors.Is(err, places.ErrDailyLimit) {
		// 写真がなくても詳細は見られるので、エラーにせず写真なしで返す
		writeJSON(w, http.StatusOK, map[string]any{"source": places.SourceGoogle, "photos": []places.Photo{}, "limited": true})
		return nil
	}
	if err != nil {
		return apierr.Wrap(apierr.PlacesUnavailable, err, "写真を読み込めませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"source": source, "photos": photos})
	return nil
}
