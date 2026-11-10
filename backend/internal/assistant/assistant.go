// Package assistant はアプリ内のアシスタント「Geminiちゃん」の、言葉を扱う部分をまとめる。
//
// Gemini に任せるのは、利用者の一言から意図を読み取ることだけである。
// Google Maps Platform の利用規約（3.2.3(c)：Google マップの内容から新しい内容を作らない）に合わせ、
// Places API の結果（場所の名前・種類・口コミの数など）は Gemini に渡さない。勧める理由の文は、
// 口コミの数・称号・距離からテンプレートで作る（Explain）。docs/decisions.md の D-036 を参照。
// 場所の検索、未知度スコア、称号は api パッケージの今の処理を使う。
//
// Gemini が失敗したとき・1日の上限に達したときは、キーワードで読み取る簡易版（Fake）に切り替える。
// 設計は docs/architecture.md の「POST /api/assistant」と docs/decisions.md の D-017 を参照。
package assistant

import (
	"context"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/auth"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/usage"
)

// Intent は利用者の一言の意図。
type Intent string

const (
	// IntentRecommend は穴場のおすすめ（地域とジャンルで探す）。
	IntentRecommend Intent = "recommend"
	// IntentAlternatives は「代わりに行くならここ」（有名スポットの代わりを探す）。
	IntentAlternatives Intent = "alternatives"
	// IntentLocate は地図を移動する先を探すだけ。
	IntentLocate Intent = "locate"
	// IntentChat は場所を探さない会話（あいさつ、使い方の質問など）。
	IntentChat Intent = "chat"
)

var intents = []Intent{IntentRecommend, IntentAlternatives, IntentLocate, IntentChat}

// Genres はアプリの PlaceGenre と places.GenreFilter が受け付けるジャンルの ID。
var Genres = []string{"food", "nature", "worship", "culture", "view", "shopping"}

// 文の長さの上限（文字数）。
const (
	MaxMessageRunes = 200
	maxHistoryRunes = 400
	maxHistory      = 6
	maxReplyRunes   = 160
	maxReasonRunes  = 80
	maxAreaRunes    = 40
	// MaxPicks はおすすめとして返す件数の上限。
	MaxPicks = 3
)

// Source は文を作ったもの。
const (
	SourceGemini = "gemini"
	SourceFake   = "fake"
)

// Turn は直前のやり取りの1件。Role は "user" または "assistant"。
type Turn struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

// Interpretation は一言から読み取った意図。
type Interpretation struct {
	Intent Intent `json:"intent"`
	// Area は探す中心の地名、または代わりを探す有名スポットの名前。一言に地名がなければ空。
	Area string `json:"area"`
	// Genres は Genres のうち、一言の希望に合うもの。
	Genres []string `json:"genres"`
	// Target は、穴場ではなく特定の種類や名前の場所そのものを探しているときの、その言葉（「駅」「コンビニ」「ラーメン」など）。
	// なければ空。recommend で使い、サーバーはその場所と、いちばん近いその場所のそばの穴場の両方を返す。
	Target string `json:"target"`
	// Reply は場所を探さないとき（chat）に返す答え。
	Reply string `json:"reply"`
}

// Candidate は理由を書いてもらう候補の場所。Places API の結果から作る。
type Candidate struct {
	Index          int    `json:"index"`
	Name           string `json:"name"`
	PrimaryType    string `json:"primaryType,omitempty"`
	ReviewCount    int    `json:"reviewCount"`
	Title          string `json:"title"`
	DistanceMeters int    `json:"distanceMeters"`
}

// ExplainRequest は候補から選んで理由を書く依頼。
type ExplainRequest struct {
	Message string
	Intent  Intent
	// Situation は利用者の状況（時間帯、現地にいるかなど）を書いた文。空なら渡さない。
	Situation string
	// Center は候補の距離の基準の名前（「清水寺」「地図の中心」など）。
	Center     string
	Candidates []Candidate
}

// Pick は選んだ候補と理由。
type Pick struct {
	Index  int    `json:"index"`
	Reason string `json:"reason"`
}

// Explanation は候補から選んだ結果。
type Explanation struct {
	Reply string `json:"reply"`
	Picks []Pick `json:"picks"`
}

// Model は言葉を扱う部分。本物（Gemini）と簡易版（Fake）を差し替えられる。
type Model interface {
	Interpret(ctx context.Context, message string, history []Turn) (Interpretation, error)
}

// Service は本物を優先し、失敗したら簡易版に切り替える。呼び出し回数もここで数える。
// メソッドはエラーを返さない（デモを止めないため）。
type Service struct {
	// Primary は本物。nil なら常に簡易版を使う。
	Primary  Model
	Fallback Model
	Log      *slog.Logger

	Usage usage.Store
	// DailyLimit はサーバー全体で Primary を呼ぶ1日の上限、UserDailyLimit は1人あたりの上限。
	DailyLimit, UserDailyLimit int
	// Timeout は Primary の1回の呼び出しを待つ時間。0 なら8秒。
	Timeout time.Duration
	// Now はテストで時刻を固定するため。nil なら time.Now。
	Now func() time.Time
}

// UsageKind は回数の記録のキーの種類。Places API の検索とは別の上限を持つ。
const UsageKind = "gemini"

const (
	usageFeature = "assistant"
)

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// IsLive は本物の Gemini を呼ぶ設定か。
func (s *Service) IsLive() bool { return s.Primary != nil }

// Interpret は一言の意図を読み取る。結果は検査済みで、Intent は4つのどれか、Genres は Genres の値だけになる。
func (s *Service) Interpret(ctx context.Context, message string, history []Turn) (Interpretation, string) {
	history = TrimHistory(history)
	var out Interpretation
	src := s.call(ctx, "interpret", func(m Model, ctx context.Context) error {
		var err error
		out, err = m.Interpret(ctx, message, history)
		if err == nil && !slices.Contains(intents, out.Intent) {
			err = fmt.Errorf("不明な intent: %q", out.Intent)
		}
		return err
	})
	return sanitizeInterpretation(out), src
}

// Explain は候補から最大 MaxPicks 件を選び、口コミの数・称号・距離から理由の文を作る。
// Places API の結果を Gemini に渡さないため、Gemini は呼ばない（パッケージの説明を参照）。
func (s *Service) Explain(_ context.Context, req ExplainRequest) Explanation {
	return sanitizeExplanation(explainByTemplate(req), len(req.Candidates))
}

// call は Primary を上限の中で呼び、失敗したら Fallback を呼ぶ。使ったものの Source を返す。
func (s *Service) call(ctx context.Context, step string, run func(Model, context.Context) error) string {
	if s.Primary != nil {
		if err := s.takeCall(ctx, UsageKind, usageFeature); err != nil {
			s.Log.WarnContext(ctx, "Gemini を呼ばずに簡易版で答えます", "step", step, "err", err)
		} else {
			timeout := s.Timeout
			if timeout == 0 {
				timeout = 8 * time.Second
			}
			cctx, cancel := context.WithTimeout(ctx, timeout)
			err := run(s.Primary, cctx)
			cancel()
			if err == nil {
				return SourceGemini
			}
			s.Log.WarnContext(ctx, "Gemini が失敗したので簡易版で答えます", "step", step, "err", err)
		}
	}
	if err := run(s.Fallback, ctx); err != nil {
		// 簡易版は外部を呼ばないので、ここで失敗するのは実装の誤り
		s.Log.ErrorContext(ctx, "簡易版のアシスタントが失敗しました", "step", step, "err", err)
	}
	return SourceFake
}

func (s *Service) takeCall(ctx context.Context, kind, feature string) error {
	uid := ""
	if u, ok := auth.FromContext(ctx); ok {
		uid = u.UID + ":" + kind
	}
	key := usage.Key(kind, feature)
	ok, err := s.Usage.TakeCall(ctx, usage.DateOf(s.now()), key, uid, s.DailyLimit, s.UserDailyLimit)
	if err != nil {
		return fmt.Errorf("呼び出し回数を確かめられません: %w", err)
	}
	if !ok {
		return fmt.Errorf("Gemini の1日の上限に達しました")
	}
	s.Log.InfoContext(ctx, "gemini_call", "key", key)
	return nil
}

// TrimHistory は直前のやり取りを新しいものから maxHistory 件に絞り、長い文を切る。不明な役の発言は捨てる。
func TrimHistory(h []Turn) []Turn {
	out := make([]Turn, 0, maxHistory)
	for _, t := range h {
		if t.Role != "user" && t.Role != "assistant" {
			continue
		}
		text := truncate(strings.TrimSpace(t.Text), maxHistoryRunes)
		if text == "" {
			continue
		}
		out = append(out, Turn{Role: t.Role, Text: text})
	}
	if len(out) > maxHistory {
		out = out[len(out)-maxHistory:]
	}
	return out
}

func sanitizeInterpretation(in Interpretation) Interpretation {
	out := Interpretation{
		Intent: in.Intent,
		Area:   truncate(strings.TrimSpace(in.Area), maxAreaRunes),
		Target: truncate(strings.TrimSpace(in.Target), maxAreaRunes),
		Genres: []string{},
		Reply:  truncate(strings.TrimSpace(in.Reply), maxReplyRunes),
	}
	if !slices.Contains(intents, out.Intent) {
		out.Intent = IntentChat
	}
	for _, g := range in.Genres {
		if slices.Contains(Genres, g) && !slices.Contains(out.Genres, g) {
			out.Genres = append(out.Genres, g)
		}
	}
	return out
}

func sanitizeExplanation(in Explanation, n int) Explanation {
	out := Explanation{Reply: truncate(strings.TrimSpace(in.Reply), maxReplyRunes), Picks: []Pick{}}
	seen := map[int]bool{}
	for _, p := range in.Picks {
		if p.Index < 0 || p.Index >= n || seen[p.Index] {
			continue
		}
		seen[p.Index] = true
		out.Picks = append(out.Picks, Pick{Index: p.Index, Reason: truncate(strings.TrimSpace(p.Reason), maxReasonRunes)})
		if len(out.Picks) == MaxPicks {
			break
		}
	}
	return out
}

func truncate(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n-1]) + "…"
}

// UserContext はアプリが送る利用者の状況。理由を書くときの参考にだけ使い、事実として断定させない。
type UserContext struct {
	// TimeOfDay は「朝」「昼」「夕方」「夜」「深夜」のどれか。
	TimeOfDay string `json:"timeOfDay"`
	Weekend   bool   `json:"weekend"`
	// OnSite は利用者が地図の中心の近くにいるか（false なら遠くから下調べしている）。
	OnSite bool `json:"onSite"`
	// Area は地図で見ている地域の名前（遠くを調べるで選んだ地域など）。
	Area string `json:"area"`
	// Liked は利用者が最近★4以上を付けた場所の種類や名前（最大3件）。
	Liked []string `json:"liked"`
}

// 状況の項目の長さの上限。プロンプトに入れるので、長い文を送られても短くする。
const (
	maxContextRunes = 30
	maxLiked        = 3
)

var timesOfDay = []string{"朝", "昼", "夕方", "夜", "深夜"}

// Describe は状況を1つの文にする。読める値が何もなければ空文字。
// 文字数を切り詰め、知らない時間帯は捨てる（プロンプトに任意の文を入れさせないため）。
func (c UserContext) Describe() string {
	var parts []string
	if slices.Contains(timesOfDay, c.TimeOfDay) {
		day := "平日"
		if c.Weekend {
			day = "休日"
		}
		parts = append(parts, fmt.Sprintf("今は%sの%s", day, c.TimeOfDay))
	}
	if c.OnSite {
		parts = append(parts, "利用者は地図の中心の近くにいて、これから歩いて行ける場所を探している")
	} else {
		parts = append(parts, "利用者は遠くから下調べをしている")
	}
	if a := clip(c.Area); a != "" {
		parts = append(parts, "見ている地域は"+a)
	}
	var liked []string
	for _, l := range c.Liked {
		if l = clip(l); l != "" && len(liked) < maxLiked {
			liked = append(liked, l)
		}
	}
	if len(liked) > 0 {
		parts = append(parts, "最近気に入った場所は"+strings.Join(liked, "、"))
	}
	return strings.Join(parts, "。")
}

func clip(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if r := []rune(s); len(r) > maxContextRunes {
		s = string(r[:maxContextRunes])
	}
	return s
}
