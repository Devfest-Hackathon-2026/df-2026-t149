// Package usage は Places API の呼び出し回数を数え、料金の目安を計算する。
//
// キーがない状態でも、本物なら呼んでいたはずの回数を simulated として数える。
// 費用をかけずにアプリを操作して、1回の利用で何回呼ぶかを確かめられるようにするため。
package usage

import (
	"context"
	"strings"
	"time"
)

// 呼び出しの種類。回数の記録のキーは「種類.機能」の形にする（例: nearby.checkin）。
const (
	KindNearby = "nearby"
	KindText   = "text"
	// KindDetailsLocation はチェックインの場所の確認（Place Details の id と location）。
	KindDetailsLocation = "detailsLocation"
	// KindDetailsName は思い出ログの名前の取得（Place Details の id と displayName）。
	KindDetailsName = "detailsName"
	// KindLocate は地図を移動する先の検索（Text Search の id、displayName、location）。
	KindLocate = "locate"
	// KindDetailsPhotos は場所の写真の一覧の取得（Place Details の id と photos）。
	KindDetailsPhotos = "detailsPhotos"
	// KindPhoto は写真1枚の画像の URL の取得（Place Photos）。
	KindPhoto = "photo"
)

// Key は回数の記録のキーを返す。
func Key(kind, feature string) string { return kind + "." + feature }

// BudgetCheckin はチェックインの候補を探す検索の区分。地図の検索とは別の上限にする。
// 共有すると、地図で広い範囲を何度か探しただけで、チェックインの候補が出なくなるため。
const BudgetCheckin = "checkinSearch"

// BudgetOf はキーが1日の上限を共有する区分を返す。
// 検索の2種類は上限を共有し（チェックインの候補を除く）、Place Details は種類ごとに別の上限を持つ。
// 共有すると、思い出ログを開くだけで検索がダミーに変わり、名前の取得でチェックインの確認も止まるため。
func BudgetOf(key string) string {
	kind, feature, _ := strings.Cut(key, ".")
	if kind == KindNearby && feature == "checkin" {
		return BudgetCheckin
	}
	if kind == KindNearby || kind == KindText {
		return "search"
	}
	return kind
}

// SameBudget は2つのキーが同じ1日の上限を共有するか。
func SameBudget(a, b string) bool { return BudgetOf(a) == BudgetOf(b) }

// Price は SKU ごとの無料枠と単価。
type Price struct {
	FreePerMonth int     `json:"freePerMonth"`
	USDPer1000   float64 `json:"usdPer1000"`
}

// Prices は取得する項目（places/google.go の fieldMask）に userRatingCount を含むときの料金。
// どちらも Enterprise 区分で、2026-11-07 に公式の料金表で確かめた値。
var Prices = map[string]Price{
	KindNearby: {FreePerMonth: 1000, USDPer1000: 35},
	KindText:   {FreePerMonth: 1000, USDPer1000: 35},
	// Place Details の Essentials 区分と Pro 区分。2026-11-07 に公式の料金表で確かめた値。
	KindDetailsLocation: {FreePerMonth: 10000, USDPer1000: 5},
	KindDetailsName:     {FreePerMonth: 5000, USDPer1000: 17},
	// Text Search の Pro 区分。
	KindLocate: {FreePerMonth: 5000, USDPer1000: 32},
	// Place Details の Pro 区分（photos）と Place Photos。公式の料金表の値で、使い始める前に確かめ直す。
	KindDetailsPhotos: {FreePerMonth: 5000, USDPer1000: 17},
	KindPhoto:         {FreePerMonth: 1000, USDPer1000: 7},
}

// Day は1日分の回数。
type Day struct {
	Date      string
	Real      map[string]int
	Simulated map[string]int
}

// Store は回数を保存する先。Cloud Run のインスタンスが入れ替わっても数え直さないよう、Firestore に保存する。
type Store interface {
	// TakeCall は本物の呼び出しを1回数える。key と同じ上限を共有するキーのその日の合計が limit に達しているか、
	// uid の回数が userLimit に達していれば、数えずに false を返す。uid が空なら1人あたりの回数は見ない。
	TakeCall(ctx context.Context, date, key, uid string, limit, userLimit int) (bool, error)
	// AddSimulated は本物なら呼んでいたはずの呼び出しを1回数える。
	AddSimulated(ctx context.Context, date, key string) error
	// Days は指定した日の回数を返す。記録がない日は含めない。
	Days(ctx context.Context, dates []string) ([]Day, error)
}

var jst = time.FixedZone("Asia/Tokyo", 9*60*60)

// DateOf は t の JST の日付を返す。
func DateOf(t time.Time) string { return t.In(jst).Format("2006-01-02") }

// MonthDates は t の月の1日から t の日までの JST の日付を返す。
func MonthDates(t time.Time) []string {
	t = t.In(jst)
	dates := make([]string, 0, t.Day())
	for d := 1; d <= t.Day(); d++ {
		dates = append(dates, time.Date(t.Year(), t.Month(), d, 0, 0, 0, 0, jst).Format("2006-01-02"))
	}
	return dates
}

// Tally は回数の集計と料金の目安。
type Tally struct {
	Calls map[string]int `json:"calls"`
	// ByKind は SKU ごとの回数。
	ByKind map[string]int `json:"byKind"`
	// EstimatedUSD は無料枠を引いた料金の目安。
	EstimatedUSD float64 `json:"estimatedUsd"`
	// ListPriceUSD は無料枠を引かない料金。回数の違いを費用で比べるために使う。
	ListPriceUSD float64 `json:"listPriceUsd"`
}

// Report は GET /api/usage の応答。
type Report struct {
	Date       string           `json:"date"`
	DailyLimit int              `json:"dailyLimit"`
	Today      Modes            `json:"today"`
	Month      Modes            `json:"month"`
	Pricing    map[string]Price `json:"pricing"`
}

// Modes は本物の呼び出しと、キーがないときに数えた呼び出しを分けて持つ。
type Modes struct {
	Real      Tally `json:"real"`
	Simulated Tally `json:"simulated"`
}

// Summarize は今月の記録から報告を作る。
func Summarize(days []Day, today string, dailyLimit int) Report {
	var r Report
	r.Date, r.DailyLimit, r.Pricing = today, dailyLimit, Prices
	realMonth, simMonth := map[string]int{}, map[string]int{}
	realToday, simToday := map[string]int{}, map[string]int{}
	for _, d := range days {
		addAll(realMonth, d.Real)
		addAll(simMonth, d.Simulated)
		if d.Date == today {
			addAll(realToday, d.Real)
			addAll(simToday, d.Simulated)
		}
	}
	r.Today = Modes{Real: tally(realToday), Simulated: tally(simToday)}
	r.Month = Modes{Real: tally(realMonth), Simulated: tally(simMonth)}
	return r
}

func addAll(dst, src map[string]int) {
	for k, n := range src {
		dst[k] += n
	}
}

func tally(calls map[string]int) Tally {
	t := Tally{Calls: calls, ByKind: map[string]int{}}
	for key, n := range calls {
		kind, _, _ := strings.Cut(key, ".")
		t.ByKind[kind] += n
	}
	for kind, n := range t.ByKind {
		p := Prices[kind]
		t.ListPriceUSD += float64(n) * p.USDPer1000 / 1000
		t.EstimatedUSD += float64(max(0, n-p.FreePerMonth)) * p.USDPer1000 / 1000
	}
	return t
}
