package api

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
)

// maxPhotoBytes は受け付ける写真の大きさの上限。Firestore の1件の上限（1MiB）に収まるようにする。
// アプリは長い辺を 1280px に縮め、JPEG にしてから送る
const maxPhotoBytes = 900 << 10

// POST /api/photos — 記録に付ける写真を上げる（ボディは画像のバイト列。Content-Type は image/jpeg か image/png か image/webp）
func (s *Server) postPhoto(w http.ResponseWriter, r *http.Request) error {
	data, err := io.ReadAll(io.LimitReader(r.Body, maxPhotoBytes+1))
	if err != nil {
		return apierr.New(apierr.BadRequest, "写真を読めませんでした")
	}
	if len(data) == 0 {
		return apierr.New(apierr.BadRequest, "写真がありません")
	}
	if len(data) > maxPhotoBytes {
		return apierr.New(apierr.BadRequest, "写真が大きすぎます（%dKB まで）", maxPhotoBytes>>10)
	}
	contentType := imageType(data)
	if contentType == "" {
		return apierr.New(apierr.BadRequest, "JPEG、PNG、WebP の写真を選んでください")
	}
	id, err := s.Store.SavePhoto(r.Context(), currentUser(r).UID, store.Photo{ContentType: contentType, Data: data}, s.now())
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "写真を保存できませんでした")
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id})
	return nil
}

// imageType は中身の先頭のバイトから画像の種類を決める。Content-Type の申告は信じない
func imageType(b []byte) string {
	switch {
	case bytes.HasPrefix(b, []byte{0xFF, 0xD8, 0xFF}):
		return "image/jpeg"
	case bytes.HasPrefix(b, []byte("\x89PNG\r\n\x1a\n")):
		return "image/png"
	case len(b) >= 12 && string(b[0:4]) == "RIFF" && string(b[8:12]) == "WEBP":
		return "image/webp"
	}
	return ""
}

// GET /api/photos/{photoId} — 写真を返す。ID は推測できないランダムな値で、ログインした人なら読める
func (s *Server) getPhoto(w http.ResponseWriter, r *http.Request) error {
	p, err := s.Store.Photo(r.Context(), r.PathValue("photoId"))
	if errors.Is(err, store.ErrPhotoNotFound) {
		return apierr.New(apierr.NotFound, "写真が見つかりませんでした")
	}
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "写真を読めませんでした")
	}
	w.Header().Set("Content-Type", p.ContentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(p.Data)))
	// 写真は変わらないので、端末に長く残してよい
	w.Header().Set("Cache-Control", "private, max-age=604800, immutable")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	_, _ = w.Write(p.Data)
	return nil
}

// PUT/DELETE /api/timeline/{entryId}/reactions/{kind} — 公開された記録に「行ってみたい」（want）や「参考になった」（helpful）を付け外しする
func (s *Server) reactionHandler(on bool) handlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		kind := store.ReactionKind(r.PathValue("kind"))
		if kind != store.ReactionWant && kind != store.ReactionHelpful {
			return apierr.New(apierr.BadRequest, "反応は want か helpful にしてください")
		}
		uid := currentUser(r).UID
		entryID := r.PathValue("entryId")
		e, err := s.Store.React(r.Context(), uid, entryID, kind, on)
		switch {
		case errors.Is(err, store.ErrEntryNotFound):
			return apierr.New(apierr.NotFound, "この記録は見つかりませんでした")
		case errors.Is(err, store.ErrOwnEntry):
			return apierr.New(apierr.BadRequest, "自分の記録には反応できません")
		case err != nil:
			return apierr.Wrap(apierr.Internal, err, "反応を送れませんでした")
		}
		mine, err := s.Store.MyReactions(r.Context(), uid, []string{entryID})
		if err != nil {
			return apierr.Wrap(apierr.Internal, err, "反応を読めませんでした")
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"wantCount": e.WantCount, "helpfulCount": e.HelpfulCount,
			"myWant": mine[entryID].Want, "myHelpful": mine[entryID].Helpful,
		})
		return nil
	}
}
