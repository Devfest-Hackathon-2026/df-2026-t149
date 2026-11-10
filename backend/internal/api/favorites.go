package api

import (
	"context"
	"errors"
	"net/http"
	"sync"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
)

// お気に入り。Firestore には place ID と登録した日時だけを保存し、名前と位置は一覧を開いたときに Places API から読む
// （Google Maps の規約で、place ID のほかは保存しないため）。

// GET /api/favorites/ids — お気に入りの place ID だけを返す。Places API を呼ばないので、起動のたびに読んでよい
func (s *Server) getFavoriteIDs(w http.ResponseWriter, r *http.Request) error {
	favs, err := s.Store.Favorites(r.Context(), currentUser(r).UID)
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "お気に入りを読めませんでした")
	}
	ids := make([]string, len(favs))
	for i, f := range favs {
		ids[i] = f.PlaceID
	}
	writeJSON(w, http.StatusOK, map[string]any{"placeIds": ids})
	return nil
}

// favoriteView はお気に入り1件。place は読めなかったとき null にし、アプリは「名前を読み込めません」と表示する
type favoriteView struct {
	PlaceID   string         `json:"placeId"`
	Place     *favoritePlace `json:"place"`
	CreatedAt time.Time      `json:"createdAt"`
}

// favoritePlace はお気に入りの一覧で返す場所。
// 口コミ数は Place Details で取得していないので、口コミ数と、口コミ数から決める未知度・称号を含めない。
// places.Place のまま返すと口コミ数が 0 になり、アプリが「口コミ 0 件・未踏」と表示してしまう。
// 口コミ数を取得しないのは、userRatingCount を足すと Place Details の料金の区分が上がるため
type favoritePlace struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Lat         float64  `json:"lat"`
	Lng         float64  `json:"lng"`
	PrimaryType string   `json:"primaryType,omitempty"`
	Types       []string `json:"types"`
}

// GET /api/favorites — お気に入りの一覧（新しい順）。場所の名前・位置・種類を Places API から読む
func (s *Server) getFavorites(w http.ResponseWriter, r *http.Request) error {
	favs, err := s.Store.Favorites(r.Context(), currentUser(r).UID)
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "お気に入りを読めませんでした")
	}
	ids := make([]string, len(favs))
	for i, f := range favs {
		ids[i] = f.PlaceID
	}
	basics := s.placeBasics(r.Context(), ids)
	out := make([]favoriteView, 0, len(favs))
	for _, f := range favs {
		v := favoriteView{PlaceID: f.PlaceID, CreatedAt: f.CreatedAt.UTC()}
		if p, ok := basics[f.PlaceID]; ok {
			v.Place = &favoritePlace{ID: p.ID, Name: p.Name, Lat: p.Lat, Lng: p.Lng, PrimaryType: p.PrimaryType, Types: p.Types}
			if v.Place.Types == nil {
				v.Place.Types = []string{}
			}
		}
		out = append(out, v)
	}
	writeJSON(w, http.StatusOK, map[string]any{"favorites": out})
	return nil
}

// placeBasics は場所の名前・位置・種類を並列に読む。読めなかった場所は含めない
func (s *Server) placeBasics(ctx context.Context, placeIDs []string) map[string]places.Place {
	ctx, cancel := context.WithTimeout(ctx, logNamesTimeout)
	defer cancel()
	var (
		mu    sync.Mutex
		wg    sync.WaitGroup
		out   = map[string]places.Place{}
		slots = make(chan struct{}, logNameConcurrency)
	)
	for _, id := range placeIDs {
		wg.Add(1)
		slots <- struct{}{}
		go func(placeID string) {
			defer wg.Done()
			defer func() { <-slots }()
			p, err := s.Places.PlaceBasics(ctx, placeID, places.FeatureFavorites)
			if err != nil {
				s.Log.WarnContext(ctx, "お気に入りの場所を読めません", "placeId", placeID, "err", err)
				return
			}
			p.ID = placeID
			mu.Lock()
			defer mu.Unlock()
			out[placeID] = p
		}(id)
	}
	wg.Wait()
	return out
}

// PUT /api/favorites/{placeId} — お気に入りに入れる
func (s *Server) putFavorite(w http.ResponseWriter, r *http.Request) error {
	placeID, err := validPlaceID(r.PathValue("placeId"))
	if err != nil {
		return err
	}
	err = s.Store.AddFavorite(r.Context(), currentUser(r).UID, placeID, s.now())
	if errors.Is(err, store.ErrTooManyFavorites) {
		return apierr.New(apierr.BadRequest, "お気に入りは%d件までです。ほかの場所を外してから入れてください", store.MaxFavorites)
	}
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "お気に入りに入れられませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"placeId": placeID, "favorite": true})
	return nil
}

// DELETE /api/favorites/{placeId} — お気に入りから外す
func (s *Server) deleteFavorite(w http.ResponseWriter, r *http.Request) error {
	placeID, err := validPlaceID(r.PathValue("placeId"))
	if err != nil {
		return err
	}
	if err := s.Store.RemoveFavorite(r.Context(), currentUser(r).UID, placeID); err != nil {
		return apierr.Wrap(apierr.Internal, err, "お気に入りから外せませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"placeId": placeID, "favorite": false})
	return nil
}
