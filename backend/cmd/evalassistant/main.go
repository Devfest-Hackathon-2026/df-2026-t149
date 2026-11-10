// evalassistant は Geminiちゃんの意図の読み取りを、決めた発言の一覧で採点する。
// 理由の文は Places API の結果を Gemini に渡さないためテンプレートで作り、採点しない（D-036）。
// モデルやプロンプトを変えたとき、前より良くなったかを数字で比べるために使う。
//
//	go run ./cmd/evalassistant -mode fake                      # 簡易版（Gemini を呼ばない）
//	go run ./cmd/evalassistant -mode vertex -project <ID>      # gcloud auth application-default login が必要
//	go run ./cmd/evalassistant -mode vertex -project <ID> -model gemini-3.1-flash -v
package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/assistant"
)

//go:embed cases.json
var casesJSON []byte

type interpretCase struct {
	Message string           `json:"message"`
	Intent  assistant.Intent `json:"intent"`
	Area    string           `json:"area"`
	Genres  []string         `json:"genres"`
	History []assistant.Turn `json:"history"`
}

type cases struct {
	Interpret []interpretCase `json:"interpret"`
}

// 渡していない事実を断定しがちな言葉。理由に出たら減点する。
// 利用者に見せる文に出してはいけない内部の称号名。
func main() {
	mode := flag.String("mode", "fake", "fake または vertex")
	project := flag.String("project", os.Getenv("GOOGLE_CLOUD_PROJECT"), "Google Cloud のプロジェクト ID（vertex のとき）")
	location := flag.String("location", "global", "Vertex AI のリージョン")
	model := flag.String("model", "gemini-3.1-flash-lite", "モデル ID")
	casesPath := flag.String("cases", "", "発言の一覧の JSON（省略すると埋め込みの cases.json）")
	verbose := flag.Bool("v", false, "失敗した例と理由の文を全部出す")
	flag.Parse()

	if err := run(*mode, *project, *location, *model, *casesPath, *verbose); err != nil {
		fmt.Fprintln(os.Stderr, "エラー:", err)
		os.Exit(1)
	}
}

func run(mode, project, location, modelID, casesPath string, verbose bool) error {
	raw := casesJSON
	if casesPath != "" {
		b, err := os.ReadFile(casesPath)
		if err != nil {
			return err
		}
		raw = b
	}
	var cs cases
	if err := json.Unmarshal(raw, &cs); err != nil {
		return err
	}
	ctx := context.Background()
	var m assistant.Model = assistant.Fake{}
	if mode == "vertex" {
		if project == "" {
			return fmt.Errorf("-project か GOOGLE_CLOUD_PROJECT が必要です")
		}
		g, err := assistant.NewGemini(ctx, project, location, modelID)
		if err != nil {
			return err
		}
		m = g
	} else if mode != "fake" {
		return fmt.Errorf("-mode は fake か vertex です")
	}
	fmt.Printf("モード: %s  モデル: %s\n\n", mode, map[bool]string{true: modelID, false: "-"}[mode == "vertex"])

	evalInterpret(ctx, m, cs.Interpret, verbose)
	return nil
}

func evalInterpret(ctx context.Context, m assistant.Model, list []interpretCase, verbose bool) {
	var intentOK, areaOK, areaN, genreOK, genreN, errs int
	var total time.Duration
	for _, c := range list {
		start := time.Now()
		got, err := m.Interpret(ctx, c.Message, c.History)
		total += time.Since(start)
		if err != nil {
			errs++
			fmt.Printf("  [エラー] %q: %v\n", c.Message, err)
			continue
		}
		okIntent := got.Intent == c.Intent
		if okIntent {
			intentOK++
		}
		okArea := true
		if c.Area != "" {
			areaN++
			okArea = strings.Contains(got.Area, c.Area)
			if okArea {
				areaOK++
			}
		}
		okGenre := true
		if len(c.Genres) > 0 {
			genreN++
			okGenre = slices.Equal(sorted(got.Genres), sorted(c.Genres))
			if okGenre {
				genreOK++
			}
		}
		if verbose && (!okIntent || !okArea || !okGenre) {
			fmt.Printf("  [不一致] %q\n    期待: intent=%s area=%q genres=%v\n    実際: intent=%s area=%q genres=%v\n", c.Message, c.Intent, c.Area, c.Genres, got.Intent, got.Area, got.Genres)
		}
	}
	n := len(list)
	fmt.Println("■ 意図の読み取り (Interpret)")
	fmt.Printf("  intent 正解   %d/%d\n  地名 正解     %d/%d\n  ジャンル 正解 %d/%d\n  エラー        %d\n  平均の待ち    %v\n\n",
		intentOK, n, areaOK, areaN, genreOK, genreN, errs, (total / time.Duration(max(n, 1))).Round(time.Millisecond))
}

func sorted(s []string) []string {
	c := slices.Clone(s)
	slices.Sort(c)
	return c
}
