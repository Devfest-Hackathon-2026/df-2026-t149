// Package api は HTTP のルーティングとハンドラーをまとめる。
//
// パスとデータの形は、アプリ（chore/scaffold の app/）が受け取れる形に合わせている。
// 仕様は docs_dev-fest の「ウラミチ API仕様.org」を参照。
package api

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/assistant"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/auth"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/usage"
)

type Server struct {
	Places *places.Gateway
	// Assistant は Geminiちゃんの言葉を扱う部分（POST /api/assistant）。
	Assistant *assistant.Service
	Scorer    places.Scorer
	Store     store.Store
	Verifier  auth.Verifier
	Log       *slog.Logger

	// AllowedOrigins は CORS で許すオリジン。localhost は常に許す。"*" ならすべて許す。
	AllowedOrigins []string

	// ExposeUsage が true のときだけ GET /api/usage を公開する。ローカルの開発環境でだけ使う。
	ExposeUsage bool

	// Now はテストで時刻を固定するため。nil なら time.Now。
	Now func() time.Time
}

// now は現在時刻を UTC・秒単位で返す。
func (s *Server) now() time.Time {
	t := time.Now()
	if s.Now != nil {
		t = s.Now()
	}
	return t.UTC().Truncate(time.Second)
}

// Handler はすべてのルートを登録した http.Handler を返す。
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	// Cloud Run は末尾が z の一部のパス（/healthz など）を予約しており、本番では届かないため /api/health にする
	mux.HandleFunc("GET /api/health", s.getHealth)
	// 本番では匿名の利用者に回数を見せず、Firestore の読み取りも消費させない
	if s.ExposeUsage {
		mux.Handle("GET /api/usage", s.handle(s.getUsage))
	}

	// /api/health と開発用の /api/usage 以外は IDトークンを必須にする。認証なしで呼べると、外部から Firestore の読み取りやサーバーの処理を繰り返し消費できるため。
	// mock=1 の検索も、アプリは同梱のダミーデータを使い、サーバーへは送らないため、ログインを求めても困らない

	// Plan A: Places API を呼ぶ検索
	mux.Handle("GET /api/explore", s.requireAuth(s.getExplore))
	mux.Handle("GET /api/alternatives", s.requireAuth(s.getAlternatives))
	mux.Handle("GET /api/locate", s.requireAuth(s.getLocate))

	// Plan A: 読み込み
	mux.Handle("GET /api/places/{placeId}/visitors", s.requireAuth(s.getVisitors))
	mux.Handle("GET /api/places/{placeId}/photos", s.requireAuth(s.getPlacePhotos))

	// Plan A: チェックインと思い出ログ（IDトークンが必須）
	mux.Handle("POST /api/checkins", s.requireAuth(s.postCheckin))
	mux.Handle("POST /api/logs", s.requireAuth(s.postLog))
	mux.Handle("GET /api/logs", s.requireAuth(s.getLogs))
	mux.Handle("PATCH /api/logs/{logId}", s.requireAuth(s.patchLog))

	// 周辺のタイムライン（IDトークンが必須）
	mux.Handle("GET /api/timeline", s.requireAuth(s.getTimeline))
	mux.Handle("POST /api/timeline/{entryId}/report", s.requireAuth(s.postReport))
	mux.Handle("PUT /api/timeline/{entryId}/reactions/{kind}", s.requireAuth(s.reactionHandler(true)))
	mux.Handle("DELETE /api/timeline/{entryId}/reactions/{kind}", s.requireAuth(s.reactionHandler(false)))
	mux.Handle("POST /api/photos", s.requireAuth(s.postPhoto))
	mux.Handle("GET /api/photos/{photoId}", s.requireAuth(s.getPhoto))

	// プロフィール（タイムラインに表示するニックネームとアイコン）
	// お気に入り
	mux.Handle("GET /api/favorites/ids", s.requireAuth(s.getFavoriteIDs))
	mux.Handle("GET /api/favorites", s.requireAuth(s.getFavorites))
	mux.Handle("PUT /api/favorites/{placeId}", s.requireAuth(s.putFavorite))
	mux.Handle("DELETE /api/favorites/{placeId}", s.requireAuth(s.deleteFavorite))

	mux.Handle("GET /api/me", s.requireAuth(s.getMe))
	mux.Handle("PUT /api/me", s.requireAuth(s.putMe))
	mux.Handle("PUT /api/me/achievements", s.requireAuth(s.putAchievements))
	mux.Handle("GET /api/achievements/stats", s.requireAuth(s.getAchievementStats))

	// Geminiちゃん（Gemini と Places API を呼ぶので IDトークンが必須）
	mux.Handle("POST /api/assistant", s.requireAuth(s.postAssistant))

	// Plan B（未実装）。501 を返すと、アプリは読み込みのAPIでダミーに切り替えられる
	mux.Handle("GET /api/gacha", s.handle(notImplemented("逆張りガチャ")))

	mux.Handle("/", s.handle(func(w http.ResponseWriter, r *http.Request) error {
		return apierr.New(apierr.NotFound, "%s %s はありません", r.Method, r.URL.Path)
	}))

	return s.recover(s.logRequests(s.cors(mux)))
}

func notImplemented(feature string) handlerFunc {
	return func(http.ResponseWriter, *http.Request) error {
		return apierr.New(apierr.NotImplemented, "%sはまだ実装していません", feature)
	}
}

// GET /api/health — 死活確認。アプリは開発中、200 が返るかで手元のサーバーがあるかを確かめる
func (s *Server) getHealth(w http.ResponseWriter, _ *http.Request) {
	source := places.SourceMock
	if s.Places.IsLive() {
		source = places.SourceGoogle
	}
	gemini := assistant.SourceFake
	if s.Assistant != nil && s.Assistant.IsLive() {
		gemini = assistant.SourceGemini
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "places": source, "assistant": gemini})
}

// GET /api/usage — Places API の呼び出し回数と料金の目安（docs/api-usage.md）
func (s *Server) getUsage(w http.ResponseWriter, r *http.Request) error {
	now := s.now()
	days, err := s.Store.Days(r.Context(), usage.MonthDates(now))
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "呼び出し回数を読めませんでした")
	}
	writeJSON(w, http.StatusOK, usage.Summarize(days, usage.DateOf(now), s.Places.DailyLimit))
	return nil
}
