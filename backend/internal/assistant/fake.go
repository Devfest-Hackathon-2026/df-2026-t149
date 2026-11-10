package assistant

import (
	"context"
	"fmt"
	"regexp"
	"slices"
	"strings"
)

// Fake は Gemini を呼ばずに、キーワードで意図を読み取り、決まった文で理由を書く簡易版。
// ローカルの開発（GEMINI_MODE=fake）と、Gemini が失敗したときの保険に使う。
type Fake struct{}

var _ Model = Fake{}

// genreWords はジャンルを決めるキーワード。
var genreWords = []struct {
	genre string
	words []string
}{
	{"food", []string{"カフェ", "喫茶", "コーヒー", "ご飯", "ごはん", "ランチ", "ディナー", "食べ", "グルメ", "お茶", "甘味", "レストラン", "食事"}},
	{"nature", []string{"公園", "自然", "緑", "庭", "山", "川", "海", "森", "散歩", "ハイキング", "花"}},
	{"worship", []string{"寺", "神社", "お参り", "参拝", "御朱印", "お堂", "祠"}},
	{"culture", []string{"美術", "博物", "歴史", "文化", "ギャラリー", "アート", "資料館"}},
	{"view", []string{"景色", "眺め", "夜景", "展望", "絶景", "見晴らし"}},
	{"shopping", []string{"買い物", "お土産", "おみやげ", "雑貨", "市場", "ショッピング", "お店"}},
}

var (
	alternativesRe = regexp.MustCompile(`[「『"]?([^「」『』"、。？?！!\s]+?)[」』"]?\s*(?:の代わり|が混|は混|が人|は人)`)
	areaRe         = regexp.MustCompile(`[「『"]?([^「」『』"、。？?！!\s]+?)[」』"]?\s*の?(?:近く|周辺|周り|まわり|あたり|辺り|付近)`)
	locateRe       = regexp.MustCompile(`[「『"]?([^「」『』"、。？?！!\s]+?)[」』"]?\s*(?:に|へ|まで)?\s*(?:移動|地図|飛んで|連れて)`)
	// targetWords は、穴場ではなくその場所そのものを探す言葉（簡易版はこの一覧だけを見分ける）
	targetWords = []string{"駅", "コンビニ", "トイレ", "駐車場", "バス停", "ラーメン", "銭湯", "郵便局", "ATM"}
	searchWords = []string{"穴場", "おすすめ", "オススメ", "近く", "探", "教えて", "行きたい", "どこ", "スポット", "静か", "空いて"}
	// areaStopWords は地名として扱わない語（「この近く」「近くの」など）。
	areaStopWords = []string{"こ", "そ", "あ", "ど", "この", "ここ", "その", "そこ", "今", "いま", "現在地", "私", "わたし", "家", "地図"}
)

func (Fake) Interpret(_ context.Context, message string, history []Turn) (Interpretation, error) {
	msg := strings.TrimSpace(message)
	in := Interpretation{}
	// 地名の中の字（嵐山の「山」、清水寺の「寺」）でジャンルを決めないよう、地名を除いてから探す
	genresWithout := func(area string) []string {
		if area == "" {
			return genresIn(msg)
		}
		return genresIn(strings.ReplaceAll(msg, area, ""))
	}

	switch {
	case strings.Contains(msg, "代わり"):
		in.Intent = IntentAlternatives
		in.Area = firstGroup(alternativesRe, msg)
		in.Genres = genresWithout(in.Area)
		if in.Area == "" {
			in.Area = lastArea(history)
		}
		if in.Area == "" {
			in.Reply = "どの有名スポットの代わりを探しますか？「（有名な場所の名前）の代わり」のように教えてください。"
			in.Intent = IntentChat
		}
	case firstGroup(locateRe, msg) != "":
		in.Intent = IntentLocate
		in.Area = firstGroup(locateRe, msg)
		in.Genres = []string{}
	default:
		area := firstGroup(areaRe, msg)
		in.Genres = genresWithout(area)
		for _, w := range targetWords {
			if strings.Contains(strings.ReplaceAll(msg, area, ""), w) {
				in.Target = w
				break
			}
		}
		if len(in.Genres) > 0 || area != "" || in.Target != "" || containsAny(msg, searchWords) {
			in.Intent, in.Area = IntentRecommend, area
			break
		}
		in.Intent = IntentChat
		in.Reply = "Geminiちゃんです。「近くの静かな穴場を教えて」「（有名な場所の名前）の代わりは？」「（地名）へ移動して」のように話しかけてください。"
	}
	return in, nil
}

// explainByTemplate は候補を上から MaxPicks 件選び、口コミの数・称号・距離から理由の文を作る。
func explainByTemplate(req ExplainRequest) Explanation {
	out := Explanation{Picks: []Pick{}}
	for i, c := range req.Candidates {
		if i == MaxPicks {
			break
		}
		out.Picks = append(out.Picks, Pick{Index: c.Index, Reason: fakeReason(c, req.Center)})
	}
	switch {
	case len(out.Picks) == 0:
		out.Reply = "条件に合う穴場が見つかりませんでした。場所やジャンルを変えて話しかけてください。"
	case req.Intent == IntentAlternatives:
		out.Reply = fmt.Sprintf("%sの代わりに、まだあまり知られていない場所を%d件選びました。", req.Center, len(out.Picks))
	default:
		out.Reply = fmt.Sprintf("%sの近くで、口コミの少ない穴場を%d件選びました。", req.Center, len(out.Picks))
	}
	return out
}

func fakeReason(c Candidate, center string) string {
	var head string
	switch c.Title {
	case "untrodden":
		head = fmt.Sprintf("口コミが%d件しかない、ほぼ未踏の場所です。", c.ReviewCount)
	case "hidden":
		head = fmt.Sprintf("口コミが%d件と少なく、まだ知る人ぞ知る穴場です。", c.ReviewCount)
	default:
		head = fmt.Sprintf("口コミは%d件で、人混みを避けて立ち寄れます。", c.ReviewCount)
	}
	if c.DistanceMeters > 0 {
		return head + fmt.Sprintf("%sから約%s。", center, walk(c.DistanceMeters))
	}
	return head
}

// walk は距離を歩く時間（分速80m）で表す。
func walk(m int) string {
	min := (m + 79) / 80
	if min <= 1 {
		return "徒歩1分"
	}
	if min > 30 {
		return fmt.Sprintf("%.1fkm", float64(m)/1000)
	}
	return fmt.Sprintf("徒歩%d分", min)
}

func genresIn(msg string) []string {
	out := []string{}
	for _, g := range genreWords {
		if containsAny(msg, g.words) {
			out = append(out, g.genre)
		}
	}
	return out
}

func containsAny(s string, words []string) bool {
	return slices.ContainsFunc(words, func(w string) bool { return strings.Contains(s, w) })
}

func firstGroup(re *regexp.Regexp, s string) string {
	m := re.FindStringSubmatch(s)
	if len(m) < 2 {
		return ""
	}
	area := strings.TrimSuffix(strings.TrimSpace(m[1]), "の")
	if slices.Contains(areaStopWords, area) {
		return ""
	}
	return area
}

// lastArea は直前の利用者の発言から地名を探す（「じゃあ代わりは？」のような続きの依頼のため）。
func lastArea(history []Turn) string {
	for i := len(history) - 1; i >= 0; i-- {
		if history[i].Role != "user" {
			continue
		}
		for _, re := range []*regexp.Regexp{alternativesRe, areaRe, locateRe} {
			if a := firstGroup(re, history[i].Text); a != "" {
				return a
			}
		}
	}
	return ""
}
