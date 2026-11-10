// Package config は環境変数から設定を読み込む。
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Port string

	// PlacesAPIKey が空なら、Places API を呼ばずにダミーデータだけで動く。
	PlacesAPIKey string
	// PlacesDailyLimit はサーバー全体で Places API を呼ぶ1日の上限（JST の日付で区切る）。
	PlacesDailyLimit int
	// PlacesUserDailyLimit は1人が Places API を呼べる1日の回数。
	PlacesUserDailyLimit int
	// PlacesDetailsDailyLimit はサーバー全体で Place Details を種類ごとに呼ぶ1日の上限。
	PlacesDetailsDailyLimit int
	// PlacesTestUntil は、テストのために上限をゆるめる最後の日（JST、例: 2026-11-16）。空ならゆるめない。
	// この日までは1人あたりの上限をなくし、全体の上限を PlacesTestDailyLimit にする。過ぎると自動で元に戻る。
	PlacesTestUntil string
	// PlacesTestDailyLimit はテストの期間の、検索と Place Details の種類ごとの全体の1日の上限（費用の歯止め）。
	PlacesTestDailyLimit int

	// AllowedOrigins は CORS で許すオリジン。localhost は常に許す。"*" ならすべて許す。
	AllowedOrigins []string

	// AuthMode: "firebase"（IDトークンを検証する）または "fake"（トークンの文字列を uid にする。ローカル専用）
	AuthMode string

	// StoreMode: "firestore" または "memory"（プロセス内に保存する。ローカル専用）
	StoreMode string

	// GoogleCloudProject は Firebase / Firestore のプロジェクトID。
	GoogleCloudProject string

	// GeminiMode: "vertex"（Vertex AI の Gemini を呼ぶ）または "fake"（キーワードで答える簡易版だけ）
	GeminiMode string
	// GeminiModel は Vertex AI のモデル ID。GeminiLocation はそのリージョン。
	GeminiModel, GeminiLocation string
	// PlacesPhotosEnabled は場所の写真（Place Photos）を読むか。1回の表示で Places API を最大5回呼ぶため、既定は止める。
	PlacesPhotosEnabled bool
	// GeminiDailyLimit はサーバー全体で Gemini を呼ぶ1日の上限、GeminiUserDailyLimit は1人あたりの上限。
	GeminiDailyLimit, GeminiUserDailyLimit int

	// OnCloudRun は Cloud Run 上で動いているか（K_SERVICE が設定されているか）。
	OnCloudRun bool
}

func Load() (Config, error) {
	c := Config{
		Port:               getenv("PORT", "8080"),
		PlacesAPIKey:       strings.TrimSpace(os.Getenv("PLACES_API_KEY")),
		AllowedOrigins:     splitCSV(os.Getenv("ALLOWED_ORIGINS")),
		AuthMode:           getenv("AUTH_MODE", "firebase"),
		StoreMode:          getenv("STORE_MODE", "firestore"),
		GoogleCloudProject: os.Getenv("GOOGLE_CLOUD_PROJECT"),
		OnCloudRun:         os.Getenv("K_SERVICE") != "",
		GeminiMode:         getenv("GEMINI_MODE", "fake"),
		GeminiModel:        getenv("GEMINI_MODEL", "gemini-3.1-flash-lite"),
		GeminiLocation:     getenv("GEMINI_LOCATION", "global"),
	}

	var err error
	if c.PlacesDailyLimit, err = getenvInt("PLACES_DAILY_LIMIT", 100); err != nil {
		return c, err
	}

	if c.PlacesUserDailyLimit, err = getenvInt("PLACES_USER_DAILY_LIMIT", 30); err != nil {
		return c, err
	}
	if c.PlacesDetailsDailyLimit, err = getenvInt("PLACES_DETAILS_DAILY_LIMIT", 150); err != nil {
		return c, err
	}

	c.PlacesTestUntil = getenv("PLACES_TEST_UNTIL", "")
	if c.PlacesTestUntil != "" {
		if _, err := time.Parse("2006-01-02", c.PlacesTestUntil); err != nil {
			return c, fmt.Errorf("PLACES_TEST_UNTIL は 2026-11-16 の形で指定してください: %q", c.PlacesTestUntil)
		}
	}
	if c.PlacesTestDailyLimit, err = getenvInt("PLACES_TEST_DAILY_LIMIT", 1000); err != nil {
		return c, err
	}
	c.PlacesPhotosEnabled = getenv("PLACES_PHOTOS", "off") == "on"
	if c.GeminiDailyLimit, err = getenvInt("GEMINI_DAILY_LIMIT", 300); err != nil {
		return c, err
	}
	if c.GeminiUserDailyLimit, err = getenvInt("GEMINI_USER_DAILY_LIMIT", 30); err != nil {
		return c, err
	}
	switch c.GeminiMode {
	case "vertex", "fake":
	default:
		return c, fmt.Errorf("GEMINI_MODE が不正です: %q（vertex / fake）", c.GeminiMode)
	}

	switch c.AuthMode {
	case "firebase":
	case "fake":
		if c.OnCloudRun {
			return c, fmt.Errorf("Cloud Run 上では AUTH_MODE=fake を使えません")
		}
	default:
		return c, fmt.Errorf("AUTH_MODE が不正です: %q（firebase / fake）", c.AuthMode)
	}

	switch c.StoreMode {
	case "firestore", "memory":
	default:
		return c, fmt.Errorf("STORE_MODE が不正です: %q（firestore / memory）", c.StoreMode)
	}

	if (c.AuthMode == "firebase" || c.StoreMode == "firestore" || c.GeminiMode == "vertex") && c.GoogleCloudProject == "" {
		return c, fmt.Errorf("AUTH_MODE=firebase、STORE_MODE=firestore、GEMINI_MODE=vertex のときは GOOGLE_CLOUD_PROJECT が必要です")
	}
	return c, nil
}

func getenv(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func getenvInt(key string, def int) (int, error) {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return def, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return 0, fmt.Errorf("%s は0以上の整数にしてください: %q", key, v)
	}
	return n, nil
}

func splitCSV(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
