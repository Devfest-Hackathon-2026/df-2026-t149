// Command server はウラミチの API サーバー。設定はすべて環境変数で渡す（backend/README.md）。
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/api"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/assistant"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/auth"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/config"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(log); err != nil {
		log.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	var verifier auth.Verifier = auth.FakeVerifier{}
	if cfg.AuthMode == "firebase" {
		app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: cfg.GoogleCloudProject})
		if err != nil {
			return err
		}
		if verifier, err = auth.NewFirebaseVerifier(ctx, app); err != nil {
			return err
		}
	}

	var st store.Store = store.NewMemoryStore()
	if cfg.StoreMode == "firestore" {
		// FIRESTORE_EMULATOR_HOST が設定されていればエミュレーターにつながる
		fs, err := firestore.NewClient(ctx, cfg.GoogleCloudProject)
		if err != nil {
			return err
		}
		st = store.NewFirestoreStore(fs)
	} else if cfg.OnCloudRun {
		log.Warn("STORE_MODE=memory で動いています。再起動するとチェックインと思い出ログが消えます")
	}
	defer st.Close()

	mock, err := places.NewMockClient()
	if err != nil {
		return err
	}
	gateway := &places.Gateway{Fallback: mock, Log: log, Usage: st, DailyLimit: cfg.PlacesDailyLimit, UserDailyLimit: cfg.PlacesUserDailyLimit, DetailsDailyLimit: cfg.PlacesDetailsDailyLimit, PhotosEnabled: cfg.PlacesPhotosEnabled,
		TestUntil: cfg.PlacesTestUntil, TestDailyLimit: cfg.PlacesTestDailyLimit}
	if cfg.PlacesAPIKey != "" {
		gateway.Primary = places.NewGoogleClient(cfg.PlacesAPIKey)
	}

	assist := &assistant.Service{Fallback: assistant.Fake{}, Log: log, Usage: st,
		DailyLimit: cfg.GeminiDailyLimit, UserDailyLimit: cfg.GeminiUserDailyLimit}
	if cfg.GeminiMode == "vertex" {
		gemini, err := assistant.NewGemini(ctx, cfg.GoogleCloudProject, cfg.GeminiLocation, cfg.GeminiModel)
		if err != nil {
			return err
		}
		assist.Primary = gemini
	}

	srv := &api.Server{
		Places:         gateway,
		Assistant:      assist,
		Scorer:         places.DefaultScorer,
		Store:          st,
		Verifier:       verifier,
		Log:            log,
		AllowedOrigins: cfg.AllowedOrigins,
		ExposeUsage:    cfg.AuthMode == "fake",
	}

	httpSrv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		placesMode := "ダミー"
		if cfg.PlacesAPIKey != "" {
			placesMode = "本物"
		}
		log.Info("listening", "port", cfg.Port, "places", placesMode, "placesDailyLimit", cfg.PlacesDailyLimit,
			"authMode", cfg.AuthMode, "storeMode", cfg.StoreMode, "geminiMode", cfg.GeminiMode, "geminiModel", cfg.GeminiModel)
		errCh <- httpSrv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		log.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return httpSrv.Shutdown(shutdownCtx)
	}
}
