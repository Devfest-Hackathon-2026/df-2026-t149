package api

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"math"
	"net/http"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/assistant"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
)

type assistantRequest struct {
	Message string           `json:"message"`
	Lat     *float64         `json:"lat"`
	Lng     *float64         `json:"lng"`
	History []assistant.Turn `json:"history"`
	// Context は利用者の状況（時間帯など）。古いアプリは送らない
	Context *assistant.UserContext `json:"context"`
}

type assistantCenter struct {
	Name string  `json:"name"`
	Lat  float64 `json:"lat"`
	Lng  float64 `json:"lng"`
}

// assistantSearch は、同じ条件を地図で探すための条件。Genres はアプリの PlaceGenre の ID。
// Query は代わりを探した有名スポットの名前（intent が alternatives のとき）。
type assistantSearch struct {
	Genres []string `json:"genres"`
	Query  string   `json:"query,omitempty"`
}

type assistantSuggestion struct {
	Place  places.Place `json:"place"`
	Reason string       `json:"reason"`
}

type assistantResponse struct {
	// Source は文を作ったもの（gemini / fake）。1回でも簡易版を使えば fake。
	Source string `json:"source"`
	// PlacesSource は候補の出どころ（google / mock）。場所を探さなかったときは省く。
	PlacesSource string                `json:"placesSource,omitempty"`
	Intent       assistant.Intent      `json:"intent"`
	Reply        string                `json:"reply"`
	Center       *assistantCenter      `json:"center,omitempty"`
	Search       *assistantSearch      `json:"search,omitempty"`
	Suggestions  []assistantSuggestion `json:"suggestions"`
	// Targets は、利用者が穴場ではなくその場所そのものを探したとき（「近くの駅」など）に見つけた場所。近い順。
	// Suggestions は、そのうちいちばん近い場所のそばの穴場になる。
	Targets []places.Place `json:"targets,omitempty"`
}

const (
	// assistantRadius は穴場のおすすめで探す半径（m）。地図の未踏サーチの既定と同じ。
	assistantRadius = 1500
	// assistantAlternativesRadius は代わりを探す半径（m）。代わりに行くならここの既定と同じ。
	assistantAlternativesRadius = 3000
	// maxCandidates は Gemini に渡す候補の数。多いほど選ぶ幅が広がり、プロンプトが長くなる。
	maxCandidates = 8
	// targetRadius は「近くの駅」のように場所そのものを探す範囲（m）。maxTargets はその件数。
	targetRadius = 3000
	maxTargets   = 3
)

const (
	replyHelp           = "Geminiちゃんです。「近くの静かな穴場を教えて」「（有名な場所の名前）の代わりは？」「（地名）へ移動して」のように話しかけてください。"
	replyNoCenter       = "どのあたりで探しますか？「（地名）の近く」のように場所を教えてください。"
	replyNoOrigin       = "どの有名スポットの代わりを探しますか？「（有名な場所の名前）の代わり」のように教えてください。"
	replyNoDestination  = "どこへ移動しますか？「（地名）へ移動して」のように教えてください。"
	replyPlacesDown     = "いまは場所を探せませんでした。少し時間をおいて、もう一度話しかけてください。"
	replyNothingNearby  = "このあたりでは、条件に合う穴場が見つかりませんでした。ジャンルを変えるか、地図を広げて探してみてください。"
	replyNoAlternatives = "%sの近くでは、代わりになる穴場が見つかりませんでした。地図で範囲を広げて探してみてください。"
)

// POST /api/assistant — Geminiちゃん。一言から意図を読み取り、穴場のおすすめと理由、または検索の条件を返す
//
//  1. Gemini で一言の意図（recommend / alternatives / locate / chat）、地名、ジャンルを読み取る
//  2. 意図に応じて今の検索（Nearby Search、代わりに行くならここ、地点の検索）を呼ぶ
//  3. 候補があれば、Gemini で最大3件を選び、理由を書く
//
// Gemini が失敗したとき・上限に達したときは簡易版で答え、場所が見つからないときもエラーにせず reply で伝える。
func (s *Server) postAssistant(w http.ResponseWriter, r *http.Request) error {
	var req assistantRequest
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	msg := strings.TrimSpace(req.Message)
	if msg == "" {
		return apierr.New(apierr.BadRequest, "話しかける言葉を入力してください")
	}
	if utf8.RuneCountInString(msg) > assistant.MaxMessageRunes {
		return apierr.New(apierr.BadRequest, "%d文字以内で話しかけてください", assistant.MaxMessageRunes)
	}
	var mapCenter *assistantCenter
	if req.Lat != nil && req.Lng != nil {
		lat, lng := *req.Lat, *req.Lng
		if math.IsNaN(lat) || math.IsNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
			return apierr.New(apierr.BadRequest, "lat と lng の値が正しくありません")
		}
		mapCenter = &assistantCenter{Name: "地図の中心", Lat: lat, Lng: lng}
	}

	ctx := r.Context()
	in, src := s.Assistant.Interpret(ctx, msg, req.History)
	res := assistantResponse{Source: src, Intent: in.Intent, Suggestions: []assistantSuggestion{}}

	switch in.Intent {
	case assistant.IntentLocate:
		if in.Area == "" {
			res.Reply = replyNoDestination
			break
		}
		center, psrc, reply := s.locateForAssistant(ctx, in.Area)
		res.PlacesSource, res.Reply, res.Center = psrc, reply, center
		if center != nil {
			res.Reply = fmt.Sprintf("%sへ地図を移動します。「このあたりの穴場を教えて」と話しかけると、近くの穴場を探します。", center.Name)
		}

	case assistant.IntentRecommend:
		center := mapCenter
		if in.Area != "" {
			var reply string
			center, res.PlacesSource, reply = s.locateForAssistant(ctx, in.Area)
			if center == nil {
				res.Reply = reply
				break
			}
		}
		if center == nil {
			res.Reply = replyNoCenter
			break
		}
		// 「近くの駅」のように場所そのものを探しているときは、その場所を見せ、いちばん近い場所のそばで穴場を探す
		var targetLine string
		if in.Target != "" {
			targets, tsrc := s.findTargets(ctx, in.Target, *center)
			if len(targets) > 0 {
				res.Targets = targets
				res.PlacesSource = worseSource(res.PlacesSource, tsrc)
				nearest := targets[0]
				targetLine = fmt.Sprintf("近くの「%s」を%d件見つけました。いちばん近いのは%s（%s）です。",
					in.Target, len(targets), nearest.Name, walkLabel(*nearest.DistanceMeters))
				center = &assistantCenter{Name: nearest.Name, Lat: nearest.Lat, Lng: nearest.Lng}
			} else {
				targetLine = fmt.Sprintf("近くに「%s」は見つかりませんでした。", in.Target)
			}
		}
		res.Center = center
		res.Search = &assistantSearch{Genres: in.Genres}
		cands, psrc, err := s.recommendCandidates(ctx, *center, in.Genres)
		if err != nil {
			s.Log.WarnContext(ctx, "Geminiちゃんの検索が失敗しました", "err", err)
			res.Reply = replyPlacesDown
			break
		}
		res.PlacesSource = worseSource(res.PlacesSource, psrc)
		if len(cands) == 0 {
			res.Reply = joinReply(targetLine, replyNothingNearby)
			if len(res.Targets) > 0 {
				res.Reply = targetLine
			}
			break
		}
		s.explain(ctx, &res, msg, center.Name, cands, req.Context)
		if targetLine != "" {
			res.Reply = joinReply(targetLine, "そのそばの穴場も選びました。"+res.Reply)
		}

	case assistant.IntentAlternatives:
		if in.Area == "" {
			res.Reply = replyNoOrigin
			break
		}
		origin, picked, psrc, err := s.findAlternatives(ctx, in.Area, assistantAlternativesRadius, false, places.FeatureAssistant)
		if errors.Is(err, errOriginNotFound) {
			res.Reply = fmt.Sprintf("「%s」が見つかりませんでした。名前を変えて話しかけてください。", in.Area)
			break
		}
		if err != nil {
			s.Log.WarnContext(ctx, "Geminiちゃんの代わりの検索が失敗しました", "err", err)
			res.Reply = replyPlacesDown
			break
		}
		res.PlacesSource = psrc
		res.Center = &assistantCenter{Name: origin.Name, Lat: origin.Lat, Lng: origin.Lng}
		res.Search = &assistantSearch{Genres: in.Genres, Query: in.Area}
		if len(picked) == 0 {
			res.Reply = fmt.Sprintf(replyNoAlternatives, origin.Name)
			break
		}
		s.explain(ctx, &res, msg, origin.Name, picked[:min(len(picked), maxCandidates)], req.Context)

	default:
		res.Reply = in.Reply
		if res.Reply == "" {
			res.Reply = replyHelp
		}
	}

	if len(res.Suggestions) > 0 {
		ps := make([]places.Place, len(res.Suggestions))
		for i, sg := range res.Suggestions {
			ps[i] = sg.Place
		}
		s.addVerdictCounts(r, ps)
		for i := range res.Suggestions {
			res.Suggestions[i].Place = ps[i]
		}
	}
	writeJSON(w, http.StatusOK, res)
	return nil
}

// findTargets は、地図の中心の近くで、利用者が探している場所（「駅」など）を近い順に返す。
// 探せなかったときや近くになかったときは空にし、穴場のおすすめだけを続ける。
func (s *Server) findTargets(ctx context.Context, target string, center assistantCenter) ([]places.Place, string) {
	found, src, err := s.Places.TextNear(ctx, target, center.Lat, center.Lng, targetRadius, 10, places.FeatureAssistant, false)
	if err != nil {
		s.Log.WarnContext(ctx, "Geminiちゃんの場所の検索が失敗しました", "target", target, "err", err)
		return nil, ""
	}
	out := []places.Place{}
	for _, p := range found {
		d := int(math.Round(places.DistanceMeters(center.Lat, center.Lng, p.Lat, p.Lng)))
		// locationBias は範囲の外の場所も返すので、範囲の中だけにする
		if d > targetRadius {
			continue
		}
		p = s.Scorer.Apply(p)
		p.DistanceMeters = &d
		out = append(out, p)
	}
	slices.SortStableFunc(out, func(a, b places.Place) int { return cmp.Compare(*a.DistanceMeters, *b.DistanceMeters) })
	return out[:min(len(out), maxTargets)], src
}

// walkLabel は距離を「徒歩5分」のように書く（分速80m）。
func walkLabel(meters int) string {
	return fmt.Sprintf("徒歩%d分", max(1, int(math.Ceil(float64(meters)/80))))
}

// joinReply は2つの文をつなぐ。片方が空ならもう片方だけにする。
func joinReply(a, b string) string {
	switch {
	case a == "":
		return b
	case b == "":
		return a
	}
	return a + b
}

// locateForAssistant は地名から中心を探す。見つからないときは center を nil にし、利用者に返す文を返す。
func (s *Server) locateForAssistant(ctx context.Context, area string) (*assistantCenter, string, string) {
	p, src, err := s.Places.Locate(ctx, area, false)
	if errors.Is(err, places.ErrPlaceNotFound) {
		return nil, "", fmt.Sprintf("「%s」が見つかりませんでした。名前を変えて話しかけてください。", area)
	}
	if err != nil {
		s.Log.WarnContext(ctx, "Geminiちゃんの地点の検索が失敗しました", "err", err)
		return nil, "", replyPlacesDown
	}
	return &assistantCenter{Name: p.Name, Lat: p.Lat, Lng: p.Lng}, src, ""
}

// recommendCandidates は中心の周りを探し、超有名でない場所を未知度の高い順（同じなら近い順）に返す。
func (s *Server) recommendCandidates(ctx context.Context, center assistantCenter, genres []string) ([]places.Place, string, error) {
	included, excluded, err := places.GenreFilter(genres)
	if err != nil {
		return nil, "", err // genres は assistant で検査済みなので、ここには来ない
	}
	found, src, err := s.Places.Nearby(ctx, places.NearbyRequest{
		Lat: center.Lat, Lng: center.Lng, RadiusMeters: assistantRadius, MaxResults: 20, RankByDistance: true,
		IncludedTypes: included, ExcludedTypes: excluded, ExcludedPrimaryTypes: places.NonVisitablePrimaryTypes,
	}, places.FeatureAssistant, false)
	if err != nil {
		return nil, "", err
	}
	out := []places.Place{}
	for _, p := range found {
		if !places.IsVisitable(p) {
			continue
		}
		p = s.Scorer.Apply(p)
		if p.Title == places.TitleFamous {
			continue
		}
		d := int(math.Round(places.DistanceMeters(center.Lat, center.Lng, p.Lat, p.Lng)))
		p.DistanceMeters = &d
		out = append(out, p)
	}
	slices.SortStableFunc(out, func(a, b places.Place) int {
		if c := cmp.Compare(*b.Obscurity, *a.Obscurity); c != 0 {
			return c
		}
		return cmp.Compare(*a.DistanceMeters, *b.DistanceMeters)
	})
	return out[:min(len(out), maxCandidates)], src, nil
}

// explain は候補から選んで理由を付け、res の reply と suggestions に入れる。
func (s *Server) explain(ctx context.Context, res *assistantResponse, msg, centerName string, cands []places.Place, user *assistant.UserContext) {
	req := assistant.ExplainRequest{Message: msg, Intent: res.Intent, Center: centerName}
	if user != nil {
		req.Situation = user.Describe()
	}
	for i, p := range cands {
		d := 0
		if p.DistanceMeters != nil {
			d = *p.DistanceMeters
		}
		req.Candidates = append(req.Candidates, assistant.Candidate{
			Index: i, Name: p.Name, PrimaryType: p.PrimaryType, ReviewCount: p.UserRatingCount, Title: p.Title, DistanceMeters: d,
		})
	}
	// 理由の文は Places API の結果から作るため Gemini を使わない。Source は一言の読み取りに使ったものを表す
	e := s.Assistant.Explain(ctx, req)
	res.Reply = e.Reply
	for _, pick := range e.Picks {
		res.Suggestions = append(res.Suggestions, assistantSuggestion{Place: cands[pick.Index], Reason: pick.Reason})
	}
	if res.Reply == "" {
		res.Reply = fmt.Sprintf("%sの近くで、穴場を%d件選びました。", centerName, len(res.Suggestions))
	}
}

// worseSource は2つの出どころのうち、ダミーを含むほうを返す。
func worseSource(a, b string) string {
	if a == places.SourceMock || b == places.SourceMock {
		return places.SourceMock
	}
	return cmp.Or(a, b)
}
