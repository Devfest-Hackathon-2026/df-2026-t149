package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/auth"
)

type handlerFunc func(w http.ResponseWriter, r *http.Request) error

// handle はエラーを返すハンドラーを http.Handler にする。エラーは仕様の形で返す。
func (s *Server) handle(h handlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			s.writeError(w, r, err)
		}
	})
}

func (s *Server) writeError(w http.ResponseWriter, r *http.Request, err error) {
	e := apierr.From(err)
	status := e.HTTPStatus()
	if status >= 500 {
		s.Log.ErrorContext(r.Context(), "request failed", "method", r.Method, "path", r.URL.Path, "code", e.Code, "err", err)
	}
	writeJSON(w, status, map[string]any{
		"error": map[string]string{"code": string(e.Code), "message": e.Message},
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// decodeJSON はリクエストのボディを読む。アプリが余分なフィールドを送っても受け付ける。
func decodeJSON(r *http.Request, v any) error {
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(v); err != nil {
		if errors.Is(err, io.EOF) {
			return apierr.New(apierr.BadRequest, "リクエストのボディがありません")
		}
		return apierr.New(apierr.BadRequest, "リクエストのボディが JSON として読めません")
	}
	return nil
}

// requireAuth は Authorization: Bearer <Firebase ID token> を確かめ、ユーザーを context に入れる。
// アプリは Google アカウントでのログインを必須にしているため、匿名ログインのトークンは受け付けない。
func (s *Server) requireAuth(h handlerFunc) http.Handler {
	return s.handle(func(w http.ResponseWriter, r *http.Request) error {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || strings.TrimSpace(token) == "" {
			return apierr.New(apierr.Unauthenticated, "ログインしてからやり直してください")
		}
		u, err := s.Verifier.Verify(r.Context(), strings.TrimSpace(token))
		if err != nil {
			return apierr.Wrap(apierr.Unauthenticated, err, "ログインの情報を確かめられませんでした。もう一度やり直してください")
		}
		if u.IsAnonymous {
			return apierr.New(apierr.LoginRequired, "Google アカウントでログインしてからやり直してください")
		}
		return h(w, r.WithContext(auth.WithUser(r.Context(), u)))
	})
}

func currentUser(r *http.Request) auth.User {
	u, ok := auth.FromContext(r.Context())
	if !ok {
		panic("currentUser は requireAuth の中だけで使う")
	}
	return u
}

// cors は開発中（flutter run -d chrome）に別のポートから呼べるようにする。
// 本番の Web 版は Firebase Hosting を通すので同じオリジンになり、使わない。
func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" && s.originAllowed(origin) {
			h := w.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			h.Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			h.Add("Vary", "Origin")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) originAllowed(origin string) bool {
	if slices.Contains(s.AllowedOrigins, "*") || slices.Contains(s.AllowedOrigins, origin) {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	host := u.Hostname()
	return host == "localhost" || host == "127.0.0.1"
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		s.Log.InfoContext(r.Context(), "request",
			"method", r.Method, "path", r.URL.Path, "status", rec.status,
			"durationMs", time.Since(start).Milliseconds())
	})
}

func (s *Server) recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				if v == http.ErrAbortHandler {
					panic(v)
				}
				s.Log.ErrorContext(r.Context(), "panic", "path", r.URL.Path, "panic", v)
				s.writeError(w, r, apierr.New(apierr.Internal, "サーバーでエラーが起きました"))
			}
		}()
		next.ServeHTTP(w, r)
	})
}
