package api

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/apierr"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/places"
	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/store"
)

// 新しい API は、アプリの CheckinRepository（app/lib/core/data/checkin_repository.dart）の
// 4つのメソッドに1つずつ対応する。JSON はアプリの CheckinResult と MemoryLog がそのまま読める形。

const (
	maxCommentLength = 140 // アプリの入力欄（maxLength: 140）と同じ

	// 端末の時計のずれとして許す範囲
	maxVisitedAtSkew = 5 * time.Minute
	// アプリが滞在と未送信の記録を保持する期間より長くする
	maxVisitedAtAge = 30 * 24 * time.Hour

	// 場所の代表地点と現在地の距離の上限（m）。アプリの checkinRangeMeters と同じ値にする。
	// 候補を探す半径（300 m）に、GPS の誤差と敷地の広さの余裕を足した長さ
	maxCheckinDistanceMeters = 500

	// 思い出ログの名前を同時に読む数。アプリは10秒で諦めるので、並列に読む
	logNameConcurrency = 4
	logNamesTimeout    = 8 * time.Second
)

var clientIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// visitTime はアプリが送った訪問日時を返す。読めない値や範囲の外の値はサーバーの時刻に置き換える。
//
// エラーにしないのは、圏外で端末に保存した記録の端末の時計が狂っていたときに、記録そのものを失わないようにするため。
// 順番はこの日時に関係なくサーバーが受け取った順に決まるので、値を偽っても順番は変わらない。
func (s *Server) visitTime(raw string) time.Time {
	now := s.now()
	t, err := time.Parse(time.RFC3339, raw)
	if err != nil || t.After(now.Add(maxVisitedAtSkew)) || t.Before(now.Add(-maxVisitedAtAge)) {
		return now
	}
	return t.UTC().Truncate(time.Second)
}

// POST /api/checkins — 古参チェックイン（CheckinRepository.checkIn）
//
// lat と lng は現在地、または後からチェックインするときの滞在の位置。
// 端末から送る値なので偽装は防げないが、place ID を指定するだけで記録することはできなくなる。
func (s *Server) postCheckin(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		PlaceID   string   `json:"placeId"`
		VisitedAt string   `json:"visitedAt"`
		Lat       *float64 `json:"lat"`
		Lng       *float64 `json:"lng"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	placeID, err := validPlaceID(req.PlaceID)
	if err != nil {
		return err
	}
	if req.Lat == nil || req.Lng == nil || *req.Lat < -90 || *req.Lat > 90 || *req.Lng < -180 || *req.Lng > 180 {
		return apierr.New(apierr.BadRequest, "lat と lng を数値で指定してください")
	}
	uid := currentUser(r).UID

	// チェックイン済みなら順番を返すだけなので、Places API の呼び出しを使わない
	order, checkedIn, err := s.Store.CheckinOrder(r.Context(), uid, placeID)
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "チェックインできませんでした。もう一度やり直してください")
	}
	if checkedIn {
		writeJSON(w, http.StatusOK, map[string]any{"order": order, "isNew": false})
		return nil
	}
	if err := s.verifyVisit(r, placeID, *req.Lat, *req.Lng); err != nil {
		return err
	}

	order, isNew, err := s.Store.CheckIn(r.Context(), uid, placeID, s.visitTime(req.VisitedAt), geohash(*req.Lat, *req.Lng))
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "チェックインできませんでした。もう一度やり直してください")
	}
	writeJSON(w, http.StatusOK, map[string]any{"order": order, "isNew": isNew})
	return nil
}

// verifyVisit は場所が実在し、指定された位置がその近くにあることを確かめる。
func (s *Server) verifyVisit(r *http.Request, placeID string, lat, lng float64) error {
	p, source, err := s.Places.PlaceLocation(r.Context(), placeID)
	if errors.Is(err, places.ErrPlaceNotFound) {
		return apierr.New(apierr.PlaceNotFound, "この場所は見つかりませんでした")
	}
	if err != nil {
		return apierr.Wrap(apierr.PlacesUnavailable, err, "場所を確かめられませんでした")
	}
	// API キーのない環境のダミーは、検索した地点の周りへ動かして返すので、固定の位置と比べても意味がない
	if source == places.SourceMock {
		return nil
	}
	if places.DistanceMeters(lat, lng, p.Lat, p.Lng) > maxCheckinDistanceMeters {
		return apierr.New(apierr.TooFar, "この場所から離れているため、チェックインできません")
	}
	return nil
}

// GET /api/places/{placeId}/visitors — 訪問者数（CheckinRepository.visitorCount）
func (s *Server) getVisitors(w http.ResponseWriter, r *http.Request) error {
	placeID, err := validPlaceID(r.PathValue("placeId"))
	if err != nil {
		return err
	}
	n, err := s.Store.VisitorCount(r.Context(), placeID)
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "訪問者数を読めませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"visitorCount": n})
	return nil
}

// logView は思い出ログ1件の JSON。アプリの MemoryLog.fromJson がそのまま読める形。
type logView struct {
	ID        string    `json:"id"`
	PlaceID   string    `json:"placeId"`
	PlaceName string    `json:"placeName,omitempty"`
	Verdict   string    `json:"verdict"`
	Rating    int       `json:"rating,omitempty"`
	Comment   string    `json:"comment"`
	Order     int       `json:"order"`
	PhotoPath string    `json:"photoPath,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
	Public    bool      `json:"public"`
	Genre     string    `json:"genre,omitempty"`
	PhotoID   string    `json:"photoId,omitempty"`
	// WantCount と HelpfulCount は、公開した記録にほかの人が付けた反応の数
	WantCount    int `json:"wantCount,omitempty"`
	HelpfulCount int `json:"helpfulCount,omitempty"`
}

func newLogView(l store.Log, placeName string) logView {
	return logView{
		ID: l.ID, PlaceID: l.PlaceID, PlaceName: placeName, Verdict: l.Verdict, Rating: l.Rating, Comment: l.Comment,
		Order: l.Order, PhotoPath: l.PhotoPath, CreatedAt: l.CreatedAt.UTC(), Public: l.Public,
		Genre: l.Genre, PhotoID: l.PhotoID,
	}
}

// genres は記録に残せるジャンル（アプリの PlaceGenre の ID）。
var genres = []string{"food", "nature", "worship", "culture", "view", "shopping", "other"}

// POST /api/logs — 思い出ログを残す（CheckinRepository.addLog）
//
// order は送られても読まず、チェックインの記録から決める（本人が値を偽れないようにするため）。
// createdAt には visitedAt を使う。場所の名前は保存せず、GET /api/logs で読み直す。
//
// clientId はアプリが記録ごとに決める値で、応答を受け取れずに送り直したときに同じ記録を返す。
//
// rating は★評価（1〜5）。送られたら verdict は★3以上を hit、それ以外を miss にする。
// ★評価に対応する前のアプリは verdict だけを送るので、そのときは★評価なしで残す。
func (s *Server) postLog(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		PlaceID   string `json:"placeId"`
		Verdict   string `json:"verdict"`
		Rating    *int   `json:"rating"`
		Comment   string `json:"comment"`
		PhotoPath string `json:"photoPath"`
		VisitedAt string `json:"visitedAt"`
		ClientID  string `json:"clientId"`
		Public    bool   `json:"public"`
		Genre     string `json:"genre"`
		PhotoID   string `json:"photoId"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	if req.Genre != "" && !slices.Contains(genres, req.Genre) {
		return apierr.New(apierr.BadRequest, "genre の値が正しくありません")
	}
	placeID, err := validPlaceID(req.PlaceID)
	if err != nil {
		return err
	}
	rating := 0
	if req.Rating != nil {
		if *req.Rating < 1 || *req.Rating > 5 {
			return apierr.New(apierr.BadRequest, "rating は1から5の数にしてください")
		}
		rating = *req.Rating
		req.Verdict = store.VerdictOf(rating)
	}
	if req.Verdict != "hit" && req.Verdict != "miss" {
		return apierr.New(apierr.BadRequest, "verdict は hit か miss にしてください")
	}
	comment := strings.TrimSpace(req.Comment)
	if utf8.RuneCountInString(comment) > maxCommentLength {
		return apierr.New(apierr.BadRequest, "一言は%d文字以内にしてください", maxCommentLength)
	}
	if req.ClientID != "" && !clientIDPattern.MatchString(req.ClientID) {
		return apierr.New(apierr.BadRequest, "clientId の形が正しくありません")
	}
	uid := currentUser(r).UID
	if req.PhotoPath != "" && !strings.HasPrefix(req.PhotoPath, "users/"+uid+"/") {
		return apierr.New(apierr.PermissionDenied, "写真は自分のフォルダ（users/{uid}/）に置いてください")
	}
	if req.PhotoID != "" {
		// 自分が上げた写真だけを付けられる
		p, err := s.Store.Photo(r.Context(), req.PhotoID)
		if errors.Is(err, store.ErrPhotoNotFound) || (err == nil && p.Owner != uid) {
			return apierr.New(apierr.BadRequest, "写真が見つかりませんでした。もう一度選んでください")
		}
		if err != nil {
			return apierr.Wrap(apierr.Internal, err, "写真を確かめられませんでした")
		}
	}

	l, err := s.Store.AddLog(r.Context(), uid, store.Log{
		PlaceID: placeID, Verdict: req.Verdict, Rating: rating, Comment: comment,
		PhotoPath: req.PhotoPath, CreatedAt: s.visitTime(req.VisitedAt), ClientID: req.ClientID,
		Public: req.Public, Genre: req.Genre, PhotoID: req.PhotoID,
	})
	if errors.Is(err, store.ErrNotCheckedIn) {
		return apierr.New(apierr.NotCheckedIn, "先にこの場所にチェックインしてください")
	}
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "思い出ログを残せませんでした。もう一度やり直してください")
	}
	writeJSON(w, http.StatusCreated, newLogView(l, ""))
	return nil
}

// GET /api/logs[?names=0][&known=id1,id2] — 自分の思い出ログの一覧（新しい順。CheckinRepository.watchLogs）
//
// names=0 なら場所の名前を読まない。名前は一覧を読むたびに Places API から読み、1人あたりの1日の上限があるため、
// 名前を表示しない画面（実績など）は names=0 で読む。
// known はアプリがすでに名前を知っている場所（検索の結果などで受け取った場所）で、名前を読まない。
func (s *Server) getLogs(w http.ResponseWriter, r *http.Request) error {
	logs, err := s.Store.ListLogs(r.Context(), currentUser(r).UID)
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "思い出ログを読めませんでした")
	}
	names := map[string]string{}
	if r.URL.Query().Get("names") != "0" {
		ids := make([]string, len(logs))
		for i, l := range logs {
			ids[i] = l.PlaceID
		}
		names = s.placeNames(r.Context(), withoutKnown(ids, r), places.FeatureLogs)
	}
	// 公開した記録に付いた反応の数を添える（読めなくても記録は返す）
	uid := currentUser(r).UID
	var entryIDs []string
	for _, l := range logs {
		if l.Public {
			entryIDs = append(entryIDs, store.TimelineIDOf(uid, l.ID))
		}
	}
	entries, err := s.Store.TimelineEntries(r.Context(), entryIDs)
	if err != nil {
		s.Log.WarnContext(r.Context(), "記録の反応の数を読めません", "err", err)
	}
	out := make([]logView, 0, len(logs))
	for _, l := range logs {
		v := newLogView(l, names[l.PlaceID])
		if e, ok := entries[store.TimelineIDOf(uid, l.ID)]; ok {
			v.WantCount, v.HelpfulCount = e.WantCount, e.HelpfulCount
		}
		out = append(out, v)
	}
	writeJSON(w, http.StatusOK, map[string]any{"logs": out})
	return nil
}

// placeNames は場所の名前を Places API から読む。
// 読めなかった場所は名前を空のまま返す。名前のために記録そのものを見られなくしないため。
func (s *Server) placeNames(ctx context.Context, placeIDs []string, feature string) map[string]string {
	ctx, cancel := context.WithTimeout(ctx, logNamesTimeout)
	defer cancel()

	var (
		mu    sync.Mutex
		wg    sync.WaitGroup
		names = map[string]string{}
		slots = make(chan struct{}, logNameConcurrency)
	)
	seen := map[string]bool{}
	for _, id := range placeIDs {
		if seen[id] {
			continue
		}
		seen[id] = true
		wg.Add(1)
		slots <- struct{}{}
		go func(placeID string) {
			defer wg.Done()
			defer func() { <-slots }()
			name, err := s.Places.PlaceName(ctx, placeID, feature)
			if err != nil {
				s.Log.WarnContext(ctx, "思い出ログの場所の名前を読めません", "placeId", placeID, "err", err)
				return
			}
			mu.Lock()
			defer mu.Unlock()
			names[placeID] = name
		}(id)
	}
	wg.Wait()
	return names
}

// maxKnownPlaces は known で受け取る場所の数の上限。URL が長くなりすぎないようにする
const maxKnownPlaces = 200

// withoutKnown は、アプリが known で送った、名前を知っている場所を除く。
// 名前は Places API の1日の上限の中で読むため、同じ名前を何度も読まないようにする。
func withoutKnown(ids []string, r *http.Request) []string {
	known := map[string]bool{}
	for i, id := range splitCSV(r.URL.Query().Get("known")) {
		if i >= maxKnownPlaces {
			break
		}
		known[id] = true
	}
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if !known[id] {
			out = append(out, id)
		}
	}
	return out
}

// PATCH /api/logs/{logId} {"rating":4,"comment":"...","public":true} — 自分の記録を直す
//
// 送った項目だけを変える。rating を変えると verdict も★評価から決め直し、場所への1人1票も入れ替える。
func (s *Server) patchLog(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Rating  *int    `json:"rating"`
		Comment *string `json:"comment"`
		Public  *bool   `json:"public"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	if req.Rating == nil && req.Comment == nil && req.Public == nil {
		return apierr.New(apierr.BadRequest, "rating、comment、public のどれかを指定してください")
	}
	if req.Rating != nil && (*req.Rating < 1 || *req.Rating > 5) {
		return apierr.New(apierr.BadRequest, "rating は1から5の数にしてください")
	}
	if req.Comment != nil {
		c := strings.TrimSpace(*req.Comment)
		if utf8.RuneCountInString(c) > maxCommentLength {
			return apierr.New(apierr.BadRequest, "一言は%d文字以内にしてください", maxCommentLength)
		}
		req.Comment = &c
	}
	l, err := s.Store.UpdateLog(r.Context(), currentUser(r).UID, r.PathValue("logId"), store.LogUpdate{
		Rating: req.Rating, Comment: req.Comment, Public: req.Public,
	})
	if errors.Is(err, store.ErrLogNotFound) {
		return apierr.New(apierr.NotFound, "この記録は見つかりませんでした")
	}
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "記録を直せませんでした")
	}
	writeJSON(w, http.StatusOK, newLogView(l, ""))
	return nil
}

// timelineLimit は周辺のタイムラインの件数。場所の名前を読む回数の上限にもなる。
const timelineLimit = 20

// GET /api/timeline?lat=34.69&lng=135.19[&known=id1,id2] — 周辺の公開された記録
// GET /api/timeline?scope=all[&known=id1,id2] — 全国の公開された記録の新着
//
// known は GET /api/logs と同じく、アプリが名前を知っている場所で、名前を読まない。
func (s *Server) getTimeline(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	var entries []store.TimelineEntry
	var err error
	if q.Get("scope") == "all" {
		// 全国の新着。場所を問わないので、lat と lng はいらない
		entries, err = s.Store.LatestTimeline(r.Context(), timelineLimit)
	} else {
		lat, okLat := parseFloat(q.Get("lat"))
		lng, okLng := parseFloat(q.Get("lng"))
		if !okLat || !okLng || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
			return apierr.New(apierr.BadRequest, "lat と lng を数値で指定してください")
		}
		entries, err = s.Store.Timeline(r.Context(), geohashesAround(lat, lng), timelineLimit)
	}
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "タイムラインを読めませんでした")
	}
	// 自分が報告した記録は、ほかの人の報告を待たずに、自分のタイムラインからすぐに消す
	entries = s.withoutReported(r, entries)
	ids := make([]string, len(entries))
	for i, e := range entries {
		ids[i] = e.PlaceID
	}
	names := s.placeNames(r.Context(), withoutKnown(ids, r), places.FeatureTimeline)
	authors := make([]string, len(entries))
	for i, e := range entries {
		authors[i] = e.Author
	}
	profiles, err := s.Store.Profiles(r.Context(), authors)
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "タイムラインを読めませんでした")
	}
	me := store.AuthorTag(currentUser(r).UID)
	entryIDs := make([]string, len(entries))
	for i, e := range entries {
		entryIDs[i] = e.ID
	}
	mine, err := s.Store.MyReactions(r.Context(), currentUser(r).UID, entryIDs)
	if err != nil {
		s.Log.WarnContext(r.Context(), "自分の反応を読めません", "err", err)
	}
	out := make([]map[string]any, 0, len(entries))
	for _, e := range entries {
		// プロフィールを保存していない投稿者は空の文字列にし、表示はアプリが決める
		p := profiles[e.Author]
		out = append(out, map[string]any{
			"id": e.ID, "author": e.Author, "authorName": p.Nickname, "authorIcon": p.Icon,
			"mine": e.Author == me, "placeId": e.PlaceID,
			"placeName": names[e.PlaceID], "verdict": e.Verdict, "comment": e.Comment, "rating": e.Rating,
			"order": e.Order, "createdAt": e.CreatedAt.UTC(),
			"genre": e.Genre, "photoId": e.PhotoID,
			"wantCount": e.WantCount, "helpfulCount": e.HelpfulCount,
			"myWant": mine[e.ID].Want, "myHelpful": mine[e.ID].Helpful,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": out})
	return nil
}

// withoutReported は、今の利用者が報告した記録を除く。読めなければ除かずに返す
func (s *Server) withoutReported(r *http.Request, entries []store.TimelineEntry) []store.TimelineEntry {
	ids := make([]string, len(entries))
	for i, e := range entries {
		ids[i] = e.ID
	}
	reported, err := s.Store.MyReports(r.Context(), currentUser(r).UID, ids)
	if err != nil {
		s.Log.WarnContext(r.Context(), "自分の報告を読めません", "err", err)
		return entries
	}
	return slices.DeleteFunc(entries, func(e store.TimelineEntry) bool { return reported[e.ID] })
}

// POST /api/timeline/{entryId}/report — 公開された記録を理由つきで報告する。
// ボディは {"reason": "inappropriate|unrelated|personal|spam|other", "note": "ひとこと（200文字まで）"}。
// 理由を送らない古いアプリの報告は other として受け付ける。3人が報告すると、だれのタイムラインにも出さなくなる
func (s *Server) postReport(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Reason string `json:"reason"`
		Note   string `json:"note"`
	}
	if r.ContentLength != 0 {
		if err := decodeJSON(r, &body); err != nil {
			return err
		}
	}
	rep := store.Report{Reason: store.ReportReason(body.Reason), Note: strings.TrimSpace(body.Note)}
	if rep.Reason == "" {
		rep.Reason = store.ReportOther
	}
	if !slices.Contains(store.ReportReasons, rep.Reason) {
		return apierr.New(apierr.BadRequest, "報告の理由が正しくありません")
	}
	if utf8.RuneCountInString(rep.Note) > store.MaxReportNoteRunes {
		return apierr.New(apierr.BadRequest, "ひとことは%d文字までにしてください", store.MaxReportNoteRunes)
	}
	err := s.Store.ReportEntry(r.Context(), currentUser(r).UID, r.PathValue("entryId"), rep)
	if errors.Is(err, store.ErrEntryNotFound) {
		return apierr.New(apierr.NotFound, "この記録は見つかりませんでした")
	}
	if err != nil {
		return apierr.Wrap(apierr.Internal, err, "報告できませんでした")
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	return nil
}

func validPlaceID(id string) (string, error) {
	id = strings.TrimSpace(id)
	if id == "" {
		return "", apierr.New(apierr.BadRequest, "placeId を指定してください")
	}
	if !store.ValidPlaceID(id) {
		return "", apierr.New(apierr.BadRequest, "placeId の形が正しくありません")
	}
	return id, nil
}
