package api

import (
	"net/http"
	"regexp"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
)

// 実績はアプリが思い出ログから決める（app/lib/features/achievements/achievements.dart）。
// サーバーは利用者ごとに解除した実績と段階を受け取り、全体で何%の人が解除したかを数えるだけにする。
const maxAchievements = 64

var achievementIDPattern = regexp.MustCompile(`^[a-z0-9_]{1,40}$`)

// PUT /api/me/achievements {"tiers":{"pioneer":2,"night_owl":1}} — 自分が解除した実績と段階を知らせる
//
// 段階のない実績は 1。まだ解除していない実績は含めない（空でもよい。利用者の数に入る）。
func (s *Server) putAchievements(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Tiers map[string]int `json:"tiers"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	if len(req.Tiers) > maxAchievements {
		return apierr.New(apierr.BadRequest, "実績が多すぎます")
	}
	tiers := map[string]int{}
	for id, tier := range req.Tiers {
		if !achievementIDPattern.MatchString(id) || tier < 0 || tier > store.MaxAchievementTier {
			return apierr.New(apierr.BadRequest, "実績の値が正しくありません")
		}
		if tier > 0 {
			tiers[id] = tier
		}
	}
	if err := s.Store.SetAchievements(r.Context(), currentUser(r).UID, tiers); err != nil {
		return apierr.Wrap(apierr.Internal, err, "実績を保存できませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	return nil
}

// GET /api/achievements/stats — 利用者全体で、それぞれの実績を解除した人数
//
// {"users": 120, "achievements": {"pioneer": [30, 8, 2]}}。配列は段階1〜3それぞれの、その段階以上を解除した人数。
func (s *Server) getAchievementStats(w http.ResponseWriter, r *http.Request) error {
	st, err := s.Store.AchievementStats(r.Context())
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "実績の集計を読めませんでした")
	}
	out := map[string][]int{}
	for id, c := range st.Counts {
		out[id] = c[:]
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": st.Users, "achievements": out})
	return nil
}
