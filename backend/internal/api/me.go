package api

import (
	"net/http"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
)

// nicknameMaxLength はニックネームの最大の文字数。タイムラインの1行に収まる長さにする。
const nicknameMaxLength = 20

// iconPattern はアイコンの ID の形。アイコンの一覧はアプリが持つため、サーバーは形だけを確かめる。
var iconPattern = regexp.MustCompile(`^[a-z0-9_]{1,32}$`)

func profileView(p store.Profile) map[string]any {
	return map[string]any{"nickname": p.Nickname, "icon": p.Icon}
}

// GET /api/me — 自分のプロフィール。まだ保存していなければ profile は null
func (s *Server) getMe(w http.ResponseWriter, r *http.Request) error {
	p, ok, err := s.Store.Profile(r.Context(), currentUser(r).UID)
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "プロフィールを読めませんでした")
	}
	var view any
	if ok {
		view = profileView(p)
	}
	writeJSON(w, http.StatusOK, map[string]any{"profile": view})
	return nil
}

// PUT /api/me {"nickname":"たろう","icon":"hiker"} — 自分のプロフィールを保存する
func (s *Server) putMe(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Nickname string `json:"nickname"`
		Icon     string `json:"icon"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	nickname := strings.TrimSpace(req.Nickname)
	n := utf8.RuneCountInString(nickname)
	if n == 0 || n > nicknameMaxLength {
		return apierr.New(apierr.BadRequest, "ニックネームは1〜%d文字で入力してください", nicknameMaxLength)
	}
	if strings.ContainsFunc(nickname, unicode.IsControl) {
		return apierr.New(apierr.BadRequest, "ニックネームに改行は使えません")
	}
	if !iconPattern.MatchString(req.Icon) {
		return apierr.New(apierr.BadRequest, "アイコンを選んでください")
	}
	p := store.Profile{Nickname: nickname, Icon: req.Icon}
	if err := s.Store.SetProfile(r.Context(), currentUser(r).UID, p); err != nil {
		return apierr.Wrap(apierr.Internal, err, "プロフィールを保存できませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"profile": profileView(p)})
	return nil
}
