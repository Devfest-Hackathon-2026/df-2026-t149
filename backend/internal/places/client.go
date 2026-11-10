package places

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/auth"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/usage"
)

type NearbyRequest struct {
	Lat, Lng      float64
	RadiusMeters  float64
	IncludedTypes []string // 空なら種類で絞らない
	// IncludedPrimaryTypes は主な種類で絞る。IncludedTypes と違い、副次的に種類が付いた場所（公園扱いの駐車場など）を含まない
	IncludedPrimaryTypes []string
	ExcludedTypes        []string // 除く種類
	// ExcludedPrimaryTypes は主な種類で除く。ExcludedTypes と違い、副次的にその種類が付いた場所は残る
	ExcludedPrimaryTypes []string
	MaxResults           int // 0 なら20
	// RankByDistance が true なら近い順の上位を受け取る。false なら Places API の既定の人気順になる。
	RankByDistance bool
}

// Client は Places API を呼ぶ部分の窓口。本物（GoogleClient）とダミー（MockClient）を差し替えられる。
type Client interface {
	// SearchNearby は円の中の場所を探す（Nearby Search）。
	SearchNearby(ctx context.Context, req NearbyRequest) ([]Place, error)
	// SearchText は文字列で場所を探す（Text Search）。有名スポットの特定に使う。
	SearchText(ctx context.Context, query string, maxResults int) ([]Place, error)
	// GetPlace は place ID から場所を読む（Place Details）。fieldMask は料金の区分を決める。
	// 存在しない場所なら ErrPlaceNotFound を返す。
	GetPlace(ctx context.Context, id, fieldMask string) (Place, error)
	// LocatePlace は文字列から地図を移動する先を1件探す。見つからなければ ErrPlaceNotFound を返す。
	LocatePlace(ctx context.Context, query string) (Place, error)
}

// Place Details で取得する項目。id だけなら無料、location は Essentials 区分、displayName は Pro 区分になる。
const (
	DetailsLocationMask = "id,location"
	DetailsNameMask     = "id,displayName"
	// DetailsBasicsMask はお気に入りの一覧で使う。displayName と同じ Pro 区分の項目だけを足し、料金は名前の取得と同じにする
	DetailsBasicsMask = "id,displayName,location,primaryType,types"
	// DetailsPhotosMask は場所の詳細の写真で使う（photos は Pro 区分）
	DetailsPhotosMask = "id,photos"
)

// TextNearClient は、地点の近くを優先して文字列で探せるクライアント（Text Search の locationBias）。
type TextNearClient interface {
	SearchTextNear(ctx context.Context, query string, lat, lng, radiusMeters float64, maxResults int) ([]Place, error)
}

// PhotoClient は写真の画像の URL を返せるクライアント。本物の Places API だけが対応する。
type PhotoClient interface {
	// PhotoURI は写真の画像の URL を返す。URL は短い時間だけ使え、API キーを含まない。
	PhotoURI(ctx context.Context, photoName string, maxWidthPx int) (string, error)
}

// MaxPhotos は場所の詳細で見せる写真の上限。1枚ごとに Place Photos の料金がかかる。
const MaxPhotos = 4

// ErrDailyLimit は、サーバーで数えている全体または1人あたりの1日の上限に達したときに返す。
var ErrDailyLimit = errors.New("Places API の1日の上限に達しました")

// ErrPlaceNotFound は、place ID の場所が存在しないときに返す。
var ErrPlaceNotFound = errors.New("場所が見つかりません")

// レスポンスの source の値。
const (
	SourceGoogle = "google"
	SourceMock   = "mock"
)

// Places API を呼ぶ機能。回数の記録で、どの機能がクレジットを消費したかを区別する。
const (
	FeatureExplore      = "explore"
	FeatureCheckin      = "checkin"
	FeatureAlternatives = "alternatives"
	FeatureLogs         = "logs"
	FeatureTimeline     = "timeline"
	FeatureFavorites    = "favorites"
	FeaturePhotos       = "photos"
	FeatureMap          = "map"
	// FeatureAssistant は Geminiちゃん（POST /api/assistant）の検索。
	FeatureAssistant = "assistant"
)

// mockIDPrefix はダミーの場所の place ID の接頭辞。本物の Places API に問い合わせても見つからない。
const mockIDPrefix = "mock_"

// 1人が Place Details を呼べる回数を、全体の上限の何分の1にするか。
// 少数のアカウントで全員の分を使い切れないようにする。チェックインの確認は1日に何度も行わないので小さくし、
// 名前の取得は一覧を開くたびに件数分を呼ぶので大きくする。
const (
	userShareOfLocationLimit = 10
	userShareOfNameLimit     = 3
	userShareOfLocateLimit   = 3
)

// Gateway は Places API を呼び、呼び出し回数を数える。
//
// API キーがあるときは、失敗しても上限に達してもダミーに切り替えず、エラーを返す。
// 架空の場所を本物と並べて見せないため。ダミーを使うのは、API キーのない開発環境と、mock=1 を付けた呼び出しだけ。
type Gateway struct {
	// Primary は本物のクライアント。API キーがないときは nil（常にダミー）。
	Primary  Client
	Fallback Client
	Log      *slog.Logger

	Usage usage.Store
	// DailyLimit はサーバー全体で Places API を呼ぶ1日の上限（JST の日付で区切る）。
	DailyLimit int
	// UserDailyLimit は1人が Places API を呼べる1日の回数。誰か1人が DailyLimit を使い切らないようにする。
	UserDailyLimit int
	// DetailsDailyLimit はサーバー全体で Place Details を種類ごとに呼ぶ1日の上限。
	DetailsDailyLimit int
	// TestUntil はテストのために上限をゆるめる最後の日（JST の "2006-01-02"）。空ならゆるめない。
	// この日までは1人あたりの上限をなくし、全体の上限を TestDailyLimit にする（費用の歯止めは残す）。
	TestUntil      string
	TestDailyLimit int
	// PhotosEnabled が false なら、場所の写真を読まずに空で返す（PLACES_PHOTOS=on で使う。費用が高いため既定は止める）。
	PhotosEnabled bool
	// Now はテストで時刻を固定するため。nil なら time.Now。
	Now func() time.Time
}

func (g *Gateway) now() time.Time {
	if g.Now != nil {
		return g.Now()
	}
	return time.Now()
}

// testing はテストのために上限をゆるめている期間か。
func (g *Gateway) testing() bool {
	return g.TestUntil != "" && g.TestDailyLimit > 0 && usage.DateOf(g.now()) <= g.TestUntil
}

// limits は今日の全体と1人あたりの上限を返す。テストの期間は1人あたりの上限をなくす（全体と同じにする）。
func (g *Gateway) limits(daily, user int) (int, int) {
	if g.testing() {
		return g.TestDailyLimit, g.TestDailyLimit
	}
	return daily, user
}

// IsLive は本物の Places API を呼ぶ設定か。
func (g *Gateway) IsLive() bool { return g.Primary != nil }

func (g *Gateway) Nearby(ctx context.Context, req NearbyRequest, feature string, forceMock bool) ([]Place, string, error) {
	return g.run(ctx, usage.Key(usage.KindNearby, feature), forceMock, func(c Client) ([]Place, error) {
		return c.SearchNearby(ctx, req)
	})
}

func (g *Gateway) Text(ctx context.Context, query string, maxResults int, feature string, forceMock bool) ([]Place, string, error) {
	return g.run(ctx, usage.Key(usage.KindText, feature), forceMock, func(c Client) ([]Place, error) {
		return c.SearchText(ctx, query, maxResults)
	})
}

// TextNear は地点の近くを優先して文字列で探す（Geminiちゃんの「近くの駅」など）。検索と同じ上限で数える。
func (g *Gateway) TextNear(ctx context.Context, query string, lat, lng, radiusMeters float64, maxResults int, feature string, forceMock bool) ([]Place, string, error) {
	return g.run(ctx, usage.Key(usage.KindText, feature), forceMock, func(c Client) ([]Place, error) {
		if tc, ok := c.(TextNearClient); ok {
			return tc.SearchTextNear(ctx, query, lat, lng, radiusMeters, maxResults)
		}
		return c.SearchText(ctx, query, maxResults)
	})
}

// PlaceLocation はチェックインの確認のために場所の位置を読む。
// 本物の API が失敗してもダミーに切り替えない。ダミーの位置では、実在の確認にならないため。
func (g *Gateway) PlaceLocation(ctx context.Context, id string) (Place, string, error) {
	if g.Primary != nil && strings.HasPrefix(id, mockIDPrefix) {
		return Place{}, "", ErrPlaceNotFound
	}
	return g.budgeted(ctx, usage.KindDetailsLocation, FeatureCheckin, userShareOfLocationLimit, func(c Client) (Place, error) {
		return c.GetPlace(ctx, id, DetailsLocationMask)
	})
}

// PlaceName は思い出ログの表示のために場所の名前を読む。
func (g *Gateway) PlaceName(ctx context.Context, id, feature string) (string, error) {
	if g.Primary != nil && strings.HasPrefix(id, mockIDPrefix) {
		return "", ErrPlaceNotFound
	}
	p, _, err := g.budgeted(ctx, usage.KindDetailsName, feature, userShareOfNameLimit, func(c Client) (Place, error) {
		return c.GetPlace(ctx, id, DetailsNameMask)
	})
	return p.Name, err
}

// PlaceBasics はお気に入りの一覧のために、場所の名前・位置・種類を読む。
// 名前の取得と同じ区分と上限で数える（項目を足しても Place Details の料金の区分は変わらないため）。
func (g *Gateway) PlaceBasics(ctx context.Context, id, feature string) (Place, error) {
	if g.Primary != nil && strings.HasPrefix(id, mockIDPrefix) {
		return Place{}, ErrPlaceNotFound
	}
	p, _, err := g.budgeted(ctx, usage.KindDetailsName, feature, userShareOfNameLimit, func(c Client) (Place, error) {
		return c.GetPlace(ctx, id, DetailsBasicsMask)
	})
	return p, err
}

// PlacePhotos は場所の写真を最大 max 枚、画像の URL と撮影者を付けて返す。
// API キーがないとき（ダミー）は写真を返さない。ダミーの場所の写真はないため。
func (g *Gateway) PlacePhotos(ctx context.Context, id string, max int) ([]Photo, string, error) {
	pc, ok := g.Primary.(PhotoClient)
	if !g.PhotosEnabled || g.Primary == nil || !ok || strings.HasPrefix(id, mockIDPrefix) {
		return []Photo{}, SourceMock, nil
	}
	p, _, err := g.budgeted(ctx, usage.KindDetailsPhotos, FeaturePhotos, userShareOfNameLimit, func(c Client) (Place, error) {
		return c.GetPlace(ctx, id, DetailsPhotosMask)
	})
	if err != nil {
		return nil, "", err
	}
	out := []Photo{}
	for _, ph := range p.Photos {
		if len(out) >= max {
			break
		}
		var uri string
		_, _, err := g.budgeted(ctx, usage.KindPhoto, FeaturePhotos, userShareOfNameLimit, func(Client) (Place, error) {
			u, err := pc.PhotoURI(ctx, ph.Name, photoMaxWidth)
			uri = u
			return Place{}, err
		})
		if err != nil {
			// 1枚読めなくても、ほかの写真は見せる。上限に達したときはそこでやめる
			if errors.Is(err, ErrDailyLimit) {
				break
			}
			g.Log.WarnContext(ctx, "写真を読めません", "placeId", id, "err", err)
			continue
		}
		ph.URL = uri
		out = append(out, ph)
	}
	return out, SourceGoogle, nil
}

// photoMaxWidth は写真の画像の幅の上限（px）。スマホの画面の幅の2倍程度にする
const photoMaxWidth = 960

// Locate は地図を移動する先を文字列から探す。forceMock ならダミーから探す。
func (g *Gateway) Locate(ctx context.Context, query string, forceMock bool) (Place, string, error) {
	if forceMock {
		p, err := g.Fallback.LocatePlace(ctx, query)
		return p, SourceMock, err
	}
	return g.budgeted(ctx, usage.KindLocate, FeatureMap, userShareOfLocateLimit, func(c Client) (Place, error) {
		return c.LocatePlace(ctx, query)
	})
}

// budgeted は検索とは別の上限の中で Places API を呼ぶ。キーがないときはダミーを読み、本物なら呼んでいた回数を数える。
func (g *Gateway) budgeted(ctx context.Context, kind, feature string, userShare int, call func(Client) (Place, error)) (Place, string, error) {
	key := usage.Key(kind, feature)
	if g.Primary == nil {
		if err := g.Usage.AddSimulated(ctx, usage.DateOf(g.now()), key); err != nil {
			g.Log.WarnContext(ctx, "呼び出し回数を記録できません", "err", err)
		}
		p, err := call(g.Fallback)
		return p, SourceMock, err
	}
	uid := ""
	if u, ok := auth.FromContext(ctx); ok {
		uid = u.UID + ":" + kind
	}
	daily, user := g.limits(g.DetailsDailyLimit, max(1, g.DetailsDailyLimit/userShare))
	ok, err := g.Usage.TakeCall(ctx, usage.DateOf(g.now()), key, uid, daily, user)
	if err != nil {
		return Place{}, "", fmt.Errorf("呼び出し回数を確かめられません: %w", err)
	}
	if !ok {
		return Place{}, "", ErrDailyLimit
	}
	g.Log.InfoContext(ctx, "places_call", "key", key)
	p, err := call(g.Primary)
	return p, SourceGoogle, err
}

func (g *Gateway) run(ctx context.Context, key string, forceMock bool, call func(Client) ([]Place, error)) ([]Place, string, error) {
	switch {
	case forceMock:
	case g.Primary == nil:
		if err := g.Usage.AddSimulated(ctx, usage.DateOf(g.now()), key); err != nil {
			g.Log.WarnContext(ctx, "呼び出し回数を記録できません", "err", err)
		}
	default:
		ps, err := g.callPrimary(ctx, key, call)
		if err != nil {
			return nil, "", err
		}
		return ps, SourceGoogle, nil
	}
	ps, err := call(g.Fallback)
	if err != nil {
		return nil, "", err
	}
	return ps, SourceMock, nil
}

func (g *Gateway) callPrimary(ctx context.Context, key string, call func(Client) ([]Place, error)) ([]Place, error) {
	uid := ""
	if u, ok := auth.FromContext(ctx); ok {
		uid = u.UID
		// チェックインの候補は、地図の検索とは別に1人あたりの回数を数える
		if b := usage.BudgetOf(key); b == usage.BudgetCheckin {
			uid += ":" + b
		}
	}
	daily, user := g.limits(g.DailyLimit, g.UserDailyLimit)
	ok, err := g.Usage.TakeCall(ctx, usage.DateOf(g.now()), key, uid, daily, user)
	if err != nil {
		// 回数を確かめられないまま呼ぶと上限を超える可能性があるため、呼ばない
		return nil, fmt.Errorf("呼び出し回数を確かめられません: %w", err)
	}
	if !ok {
		return nil, ErrDailyLimit
	}
	// Google Cloud のコンソールの回数と突き合わせられるよう、呼び出しごとに記録する
	g.Log.InfoContext(ctx, "places_call", "key", key)
	return call(g.Primary)
}
