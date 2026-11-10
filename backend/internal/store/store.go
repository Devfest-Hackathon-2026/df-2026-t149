// Package store はチェックインと思い出ログを保存する。
//
// Firestore の形は Go の内部のことで、アプリとの約束ではない（API 仕様の「Firestoreのデータ構造」）:
//
//	places/{placeId}                  visitorCount
//	places/{placeId}/checkins/{uid}   order, at
//	places/{placeId}                  hits, misses（当たりとハズレの数）, ratingSum, ratingCount（★評価の合計と数）
//	places/{placeId}/verdicts/{uid}   verdict, rating（1人1票）
//	users/{uid}/logs/{logId}          placeId, verdict, rating, comment, order, photoPath, createdAt, public, geo
//	timeline/{id}                     公開された記録。author, placeId, verdict, rating, comment, order, createdAt, geo, reports
//	timeline/{id}/reports/{uid}       報告した人（1人1回）
//	users/{uid}/favorites/{placeId}   createdAt（お気に入り。place ID のほかは保存しない）
//	authors/{AuthorTag}               nickname, icon, updatedAt
//	usage/{JST の日付}                 real, simulated（Places API の呼び出し回数）
//	usage/{JST の日付}/users/{uid}     calls（1人あたりの呼び出し回数）
//
// place ID と訪問者数のほかに、Places API の内容は保存しない（Google Maps の規約のため）。
package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"slices"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/usage"
)

// ErrLogNotFound は、自分の記録にない ID を指定したときに返す。
var ErrLogNotFound = errors.New("log not found")

// ErrEntryNotFound は、公開されていない記録を報告しようとしたときに返す。
var ErrEntryNotFound = errors.New("timeline entry not found")

// ErrPhotoNotFound は、写真が見つからないときに返す。
var ErrPhotoNotFound = errors.New("photo not found")

// ErrOwnEntry は、自分の記録に反応しようとしたときに返す。
var ErrOwnEntry = errors.New("own timeline entry")

// Photo は記録に付けた写真。
type Photo struct {
	Owner       string
	ContentType string
	Data        []byte
}

// ReactionKind は口コミへの反応の種類。
type ReactionKind string

const (
	// ReactionWant は「行ってみたい」。
	ReactionWant ReactionKind = "want"
	// ReactionHelpful は「参考になった」。
	ReactionHelpful ReactionKind = "helpful"
)

// Reactions は1人がその口コミに付けた反応。
type Reactions struct {
	Want    bool
	Helpful bool
}

func (r Reactions) with(kind ReactionKind, on bool) Reactions {
	switch kind {
	case ReactionWant:
		r.Want = on
	case ReactionHelpful:
		r.Helpful = on
	}
	return r
}

func boolDelta(before, after bool) int {
	switch {
	case after && !before:
		return 1
	case before && !after:
		return -1
	}
	return 0
}

// ReportReason は報告の理由。
type ReportReason string

const (
	// ReportInappropriate は、不快な・攻撃的な内容。
	ReportInappropriate ReportReason = "inappropriate"
	// ReportUnrelated は、場所と関係ない内容。
	ReportUnrelated ReportReason = "unrelated"
	// ReportPersonal は、個人情報が含まれている。
	ReportPersonal ReportReason = "personal"
	// ReportSpam は、宣伝やスパム。
	ReportSpam ReportReason = "spam"
	// ReportOther は、そのほか（理由を送らない古いアプリも含む）。
	ReportOther ReportReason = "other"
)

// ReportReasons は受け付ける報告の理由。
var ReportReasons = []ReportReason{ReportInappropriate, ReportUnrelated, ReportPersonal, ReportSpam, ReportOther}

// MaxReportNoteRunes は報告に添えるひとことの長さの上限。
const MaxReportNoteRunes = 200

// Report は報告の中身。運営が Firestore で読んで対応を決める。
type Report struct {
	Reason ReportReason
	Note   string
}

// HiddenAtReports は、タイムラインに表示しなくなる報告の数。
const HiddenAtReports = 3

// ErrNotCheckedIn は、チェックインしていない場所の思い出ログを残そうとしたときに返す。
var ErrNotCheckedIn = errors.New("not checked in")

// Log は思い出ログ1件。
type Log struct {
	ID      string
	PlaceID string
	Verdict string // "hit" / "miss"
	// Rating は★評価（1〜5）。★評価を入れる前の記録は 0。Verdict は★3以上を "hit" にする
	Rating    int
	Comment   string
	Order     int // 何人目の訪問者だったか。チェックインの記録から入れる
	PhotoPath string
	CreatedAt time.Time
	// Public は周辺のタイムラインに公開するか。
	Public bool
	// Geo はチェックインの地点の区画。保存するときにチェックインの記録から入れる。
	Geo string
	// ClientID はアプリが記録ごとに決める値。同じ値で送り直されたら、新しく作らずに保存済みの記録を返す。
	ClientID string
	// Genre は場所のジャンル（アプリの PlaceGenre の ID）。チェックインスタンプの種類を決める。古い記録は空
	Genre string
	// PhotoID は記録に付けた写真（SavePhoto の ID）。なければ空
	PhotoID string
}

// MaxFavorites は1人が登録できるお気に入りの数。一覧を開くたびに件数分の名前を Places API から読むため上限を置く。
const MaxFavorites = 100

// ErrTooManyFavorites は、お気に入りが MaxFavorites に達しているときに返す。
var ErrTooManyFavorites = errors.New("too many favorites")

// Favorite はお気に入りの場所1件。
type Favorite struct {
	PlaceID   string
	CreatedAt time.Time
}

// Profile はタイムラインで投稿者として表示するニックネームとアイコン。
// Google アカウントの名前と写真は実名と顔写真の場合があるため使わず、利用者が設定した値だけを保存する。
type Profile struct {
	Nickname string
	Icon     string // アプリが用意したアイコンの ID
}

// VerdictCount は1つの場所の当たりとハズレの数と、★評価の合計と数。
type VerdictCount struct {
	Hits, Misses int
	// RatingSum と RatingCount は★評価のある票だけを数える
	RatingSum, RatingCount int
}

func (c VerdictCount) with(verdict string, rating int) VerdictCount {
	return c.add(verdict, rating, 1)
}

func (c VerdictCount) without(verdict string, rating int) VerdictCount {
	return c.add(verdict, rating, -1)
}

func (c VerdictCount) add(verdict string, rating, n int) VerdictCount {
	if verdict == "miss" {
		c.Misses += n
	} else {
		c.Hits += n
	}
	if rating > 0 {
		c.RatingSum += rating * n
		c.RatingCount += n
	}
	return c
}

// VerdictOf は★評価から当たりかハズレを決める。★3以上を当たりにする。
func VerdictOf(rating int) string {
	if rating >= 3 {
		return "hit"
	}
	return "miss"
}

// TimelineEntry は周辺のタイムラインの1件。
type TimelineEntry struct {
	ID        string
	Author    string // 投稿者の符号（AuthorTag）。uid は公開しない
	PlaceID   string
	Verdict   string
	Rating    int
	Comment   string
	Order     int
	CreatedAt time.Time
	Geo       string
	Reports   int
	Public    bool
	Genre     string
	PhotoID   string
	// WantCount と HelpfulCount は「行ってみたい」「参考になった」を付けた人数
	WantCount    int
	HelpfulCount int
}

// AuthorTag は uid から公開用の符号を作る。同じ人の投稿だと分かり、uid は分からない。
// プロフィールの保存先のキーにも使うため、利用者が増えても重ならない長さにする。
func AuthorTag(uid string) string {
	sum := sha256.Sum256([]byte("uramichi-author:" + uid))
	return strings.ToUpper(hex.EncodeToString(sum[:16]))
}

// timelineID は uid を含めずに、利用者ごとに重ならない ID を作る。
func timelineID(uid, logID string) string {
	sum := sha256.Sum256([]byte("uramichi-timeline:" + uid + ":" + logID))
	return hex.EncodeToString(sum[:16])
}

func newTimelineEntry(uid string, l Log) TimelineEntry {
	return TimelineEntry{
		ID: timelineID(uid, l.ID), Author: AuthorTag(uid), PlaceID: l.PlaceID, Verdict: l.Verdict, Rating: l.Rating,
		Comment: l.Comment, Order: l.Order, CreatedAt: l.CreatedAt, Geo: l.Geo, Public: true,
		Genre: l.Genre, PhotoID: l.PhotoID,
	}
}

type Store interface {
	usage.Store

	// CheckIn はその場所の何人目の訪問者かを決めて記録する。at は訪問した日時。
	// geo は距離を確かめた地点の区画で、公開した思い出ログを周辺で探すために残す。
	// すでにチェックインしていれば、1回目の順番と isNew=false を返し、人数は増やさない。
	CheckIn(ctx context.Context, uid, placeID string, at time.Time, geo string) (order int, isNew bool, err error)

	// CheckinOrder は uid がその場所にチェックイン済みなら順番と true を返す。
	CheckinOrder(ctx context.Context, uid, placeID string) (order int, ok bool, err error)

	// VisitorCount はその場所の訪問者数。まだ誰も来ていなければ0。
	VisitorCount(ctx context.Context, placeID string) (int, error)

	// AddLog は思い出ログを保存する。ID、Order、Geo はここで決める（Order と Geo はチェックインの記録から入れる）。
	// 当たりとハズレの数と★評価は1人1票で、同じ人が別の評価を残すと票を入れ替える。
	// その場所にチェックインしていなければ ErrNotCheckedIn。
	AddLog(ctx context.Context, uid string, l Log) (Log, error)

	// ListLogs は自分の思い出ログを新しい順に返す。
	ListLogs(ctx context.Context, uid string) ([]Log, error)

	// UpdateLog は自分の思い出ログの★評価・ひとこと・公開状態のうち、指定したものを変える。
	// ★評価を変え、それがその場所のいちばん新しい記録なら、その場所への1人1票も入れ替える
	// （票はいちばん新しい記録の★評価にする。古い記録を直しても票は変えない）。公開中なら周辺のタイムラインにも反映する。
	// 自分の記録になければ ErrLogNotFound。
	UpdateLog(ctx context.Context, uid, logID string, u LogUpdate) (Log, error)

	// VerdictCounts は場所ごとの当たりとハズレの数を返す。記録のない場所は含めない。
	VerdictCounts(ctx context.Context, placeIDs []string) (map[string]VerdictCount, error)

	// Timeline は指定した区画の公開された記録を新しい順に返す。報告が多い記録は含めない。
	Timeline(ctx context.Context, geos []string, limit int) ([]TimelineEntry, error)

	// SavePhoto は記録に付ける写真を保存し、ID を返す。
	SavePhoto(ctx context.Context, uid string, p Photo, at time.Time) (string, error)

	// Photo は写真を返す。なければ ErrPhotoNotFound。
	Photo(ctx context.Context, id string) (Photo, error)

	// React は公開された記録に反応を付ける（on=false なら外す）。1人1回で、同じ反応を重ねても数えない。
	// 公開されていなければ ErrEntryNotFound、自分の記録なら ErrOwnEntry。反応した後の記録を返す。
	React(ctx context.Context, uid, entryID string, kind ReactionKind, on bool) (TimelineEntry, error)

	// MyReactions は uid が記録ごとに付けた反応を返す。付けていない記録は含めない。
	MyReactions(ctx context.Context, uid string, entryIDs []string) (map[string]Reactions, error)

	// TimelineEntries は ID ごとの公開された記録（反応の数を含む）を返す。ない記録は含めない。
	TimelineEntries(ctx context.Context, entryIDs []string) (map[string]TimelineEntry, error)

	// LatestTimeline は場所を問わず、公開された記録を新しい順に返す（全国の新着）。報告が多い記録は含めない。
	LatestTimeline(ctx context.Context, limit int) ([]TimelineEntry, error)

	// ReportEntry は公開された記録を理由つきで報告する。同じ人の2回目は数えない。なければ ErrEntryNotFound。
	ReportEntry(ctx context.Context, uid, entryID string, rep Report) error
	// MyReports は entryIDs のうち uid が報告した記録の ID を返す。報告した人のタイムラインからは、すぐに消すため
	MyReports(ctx context.Context, uid string, entryIDs []string) (map[string]bool, error)

	// AddFavorite は場所をお気に入りに入れる。すでに入っていれば何もしない。
	// MaxFavorites に達していれば ErrTooManyFavorites。
	AddFavorite(ctx context.Context, uid, placeID string, at time.Time) error

	// RemoveFavorite は場所をお気に入りから外す。入っていなくてもエラーにしない。
	RemoveFavorite(ctx context.Context, uid, placeID string) error

	// Favorites は自分のお気に入りを新しい順に返す。
	Favorites(ctx context.Context, uid string) ([]Favorite, error)

	// Profile は uid のプロフィールを返す。まだ保存していなければ ok=false。
	Profile(ctx context.Context, uid string) (p Profile, ok bool, err error)

	// SetProfile は uid のプロフィールを保存する。保存済みなら置き換える。
	SetProfile(ctx context.Context, uid string, p Profile) error

	// Profiles は AuthorTag ごとのプロフィールを返す。保存していない投稿者は含めない。
	Profiles(ctx context.Context, authorTags []string) (map[string]Profile, error)

	// SetAchievements は uid が解除した実績と段階（1〜MaxAchievementTier）を置き換え、全体の集計を差分で更新する。
	// 前と同じなら何も書かない。
	SetAchievements(ctx context.Context, uid string, tiers map[string]int) error

	// AchievementStats は、実績を知らせた利用者の数と、実績・段階ごとに解除した人数を返す。
	AchievementStats(ctx context.Context) (AchievementStats, error)

	Close() error
}

// LogUpdate は思い出ログの変更。nil の項目は変えない。
type LogUpdate struct {
	Rating  *int
	Comment *string
	Public  *bool
}

// apply は l に変更を当てる。★評価を変えたら当たり・ハズレも★評価から決め直す。
func (u LogUpdate) apply(l Log) Log {
	if u.Rating != nil {
		l.Rating = *u.Rating
		l.Verdict = VerdictOf(*u.Rating)
	}
	if u.Comment != nil {
		l.Comment = *u.Comment
	}
	if u.Public != nil {
		l.Public = *u.Public
	}
	return l
}

// MaxAchievementTier は実績の段階の上限（ブロンズ・シルバー・ゴールド）。
const MaxAchievementTier = 3

// AchievementStats はアプリの利用者全体の実績の集計。
type AchievementStats struct {
	// Users は実績を知らせた利用者の数（まだ何も解除していない人も含む）。
	Users int
	// Counts は実績の ID → 段階（1〜3）ごとの、その段階以上を解除した人数。
	Counts map[string][MaxAchievementTier]int
}

// achievementDiff は、ある利用者の段階が old から next に変わったときの、段階ごとの人数の増減を返す。
func achievementDiff(old, next map[string]int) map[string][MaxAchievementTier]int {
	out := map[string][MaxAchievementTier]int{}
	ids := map[string]bool{}
	for id := range old {
		ids[id] = true
	}
	for id := range next {
		ids[id] = true
	}
	for id := range ids {
		o, n := old[id], next[id]
		if o == n {
			continue
		}
		var d [MaxAchievementTier]int
		for t := 1; t <= MaxAchievementTier; t++ {
			switch {
			case t <= n && t > o:
				d[t-1] = 1
			case t <= o && t > n:
				d[t-1] = -1
			}
		}
		out[id] = d
	}
	return out
}

func sameTiers(a, b map[string]int) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}

// newLogID は思い出ログの ID を返す。clientID があれば、送り直しても同じ ID になる。
func newLogID(clientID string) string {
	if clientID != "" {
		return "lg_" + clientID
	}
	return "lg_" + ulid.Make().String()
}

// ValidPlaceID は、Firestore のドキュメントIDとして使える placeId か。
func ValidPlaceID(id string) bool {
	if id == "" || len(id) > 1500 || id == "." || id == ".." || strings.Contains(id, "/") {
		return false
	}
	return !(strings.HasPrefix(id, "__") && strings.HasSuffix(id, "__"))
}

// sortFavorites は新しい順に並べる。同じ日時なら place ID の順にして、並びを決まったものにする。
func sortFavorites(fs []Favorite) {
	slices.SortFunc(fs, func(a, b Favorite) int {
		if c := b.CreatedAt.Compare(a.CreatedAt); c != 0 {
			return c
		}
		return strings.Compare(a.PlaceID, b.PlaceID)
	})
}

// latestVisible は報告が多い記録を除き、新しい順に limit 件を返す。
func latestVisible(entries []TimelineEntry, limit int) []TimelineEntry {
	out := slices.DeleteFunc(entries, func(e TimelineEntry) bool { return !e.Public || e.Reports >= HiddenAtReports })
	slices.SortFunc(out, func(a, b TimelineEntry) int { return b.CreatedAt.Compare(a.CreatedAt) })
	if len(out) > limit {
		out = out[:limit]
	}
	return out
}

// newerVisit は a が b より後の訪問か。その場所の票（1人1票）は、いちばん後に訪問した記録の★評価にする。
// 受け取った順にしないのは、圏外で残した前の訪問が後から届いたとき、古い★評価で集計してしまうため。
// 訪問日時が同じときは ID で決め、メモリの版と Firestore の版で同じ記録を選ぶ
func newerVisit(a, b Log) bool {
	if !a.CreatedAt.Equal(b.CreatedAt) {
		return a.CreatedAt.After(b.CreatedAt)
	}
	return a.ID > b.ID
}

// newPhotoID は写真の ID を返す。推測されないよう、ランダムな 128 ビットにする（写真はログインした人なら ID で読めるため）。
func newPhotoID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return "ph_" + hex.EncodeToString(b)
}

// TimelineIDOf は uid の思い出ログ logID を公開したときの、タイムラインの記録の ID。
func TimelineIDOf(uid, logID string) string { return timelineID(uid, logID) }
