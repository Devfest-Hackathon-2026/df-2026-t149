package store

import (
	"context"
	"maps"
	"slices"
	"sync"
	"time"

	"github.com/UME0325/DevFest-Hackathon-2026/backend/internal/usage"
)

// MemoryStore は STORE_MODE=memory のときに使う。プロセス内に保存するので、再起動すると消える。
type MemoryStore struct {
	mu           sync.Mutex
	visitorCount map[string]int               // placeID -> 人数
	orders       map[string]map[string]int    // placeID -> uid -> 順番
	logs         map[string][]Log             // uid -> 思い出ログ（古い順）
	usage        map[string]*usage.Day        // 日付 -> 呼び出し回数
	userCalls    map[string]map[string]int    // 日付 -> uid -> 呼び出し回数
	verdicts     map[string]VerdictCount      // placeID -> 当たりとハズレの数
	votes        map[string]map[string]vote   // placeID -> uid -> 評価
	checkinGeos  map[string]map[string]string // placeID -> uid -> 区画
	timeline     map[string]TimelineEntry     // ID -> 公開された記録
	reporters    map[string]map[string]Report
	profiles     map[string]Profile              // AuthorTag -> プロフィール
	favorites    map[string]map[string]time.Time // uid -> placeID -> 登録した日時
	achievements map[string]map[string]int       // uid -> 実績 ID -> 段階
	photos       map[string]Photo                // 写真の ID -> 写真
	reactions    map[string]map[string]Reactions // 記録の ID -> uid -> 反応
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		visitorCount: map[string]int{},
		orders:       map[string]map[string]int{},
		logs:         map[string][]Log{},
		achievements: map[string]map[string]int{},
		photos:       map[string]Photo{},
		reactions:    map[string]map[string]Reactions{},
		usage:        map[string]*usage.Day{},
		userCalls:    map[string]map[string]int{},
		verdicts:     map[string]VerdictCount{},
		votes:        map[string]map[string]vote{},
		checkinGeos:  map[string]map[string]string{},
		timeline:     map[string]TimelineEntry{},
		reporters:    map[string]map[string]Report{},
		profiles:     map[string]Profile{},
		favorites:    map[string]map[string]time.Time{},
	}
}

func (s *MemoryStore) Close() error { return nil }

func (s *MemoryStore) CheckIn(_ context.Context, uid, placeID string, _ time.Time, geo string) (int, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.orders[placeID] == nil {
		s.orders[placeID] = map[string]int{}
	}
	if order, ok := s.orders[placeID][uid]; ok {
		return order, false, nil
	}
	s.visitorCount[placeID]++
	order := s.visitorCount[placeID]
	s.orders[placeID][uid] = order
	if s.checkinGeos[placeID] == nil {
		s.checkinGeos[placeID] = map[string]string{}
	}
	s.checkinGeos[placeID][uid] = geo
	return order, true, nil
}

func (s *MemoryStore) CheckinOrder(_ context.Context, uid, placeID string) (int, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	order, ok := s.orders[placeID][uid]
	return order, ok, nil
}

func (s *MemoryStore) VisitorCount(_ context.Context, placeID string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.visitorCount[placeID], nil
}

func (s *MemoryStore) AddLog(_ context.Context, uid string, l Log) (Log, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	order, ok := s.orders[l.PlaceID][uid]
	if !ok {
		return Log{}, ErrNotCheckedIn
	}
	l.ID = newLogID(l.ClientID)
	if i := slices.IndexFunc(s.logs[uid], func(old Log) bool { return old.ID == l.ID }); i >= 0 {
		return s.logs[uid][i], nil
	}
	l.Order = order
	l.Geo = s.checkinGeos[l.PlaceID][uid]
	l.CreatedAt = l.CreatedAt.UTC()
	s.logs[uid] = append(s.logs[uid], l)
	if s.isLatestLog(uid, l) {
		s.vote(uid, l.PlaceID, vote{l.Verdict, l.Rating})
	}
	if l.Public {
		s.timeline[timelineID(uid, l.ID)] = newTimelineEntry(uid, l)
	}
	return l, nil
}

// vote は1人1票の評価。
type vote struct {
	verdict string
	rating  int
}

func (s *MemoryStore) vote(uid, placeID string, v vote) {
	if s.votes[placeID] == nil {
		s.votes[placeID] = map[string]vote{}
	}
	old, voted := s.votes[placeID][uid]
	if old == v {
		return
	}
	s.votes[placeID][uid] = v
	c := s.verdicts[placeID]
	if voted {
		c = c.without(old.verdict, old.rating)
	}
	s.verdicts[placeID] = c.with(v.verdict, v.rating)
}

func (s *MemoryStore) UpdateLog(_ context.Context, uid, logID string, u LogUpdate) (Log, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	i := slices.IndexFunc(s.logs[uid], func(l Log) bool { return l.ID == logID })
	if i < 0 {
		return Log{}, ErrLogNotFound
	}
	before := s.logs[uid][i]
	l := u.apply(before)
	s.logs[uid][i] = l
	// 票は、その場所でいちばん後に訪問した記録の★評価にする（AddLog と同じ）
	if (l.Verdict != before.Verdict || l.Rating != before.Rating) && s.isLatestLog(uid, l) {
		s.vote(uid, l.PlaceID, vote{l.Verdict, l.Rating})
	}
	id := timelineID(uid, logID)
	// 報告の数は残す。消すと、非公開にして公開し直すだけで報告を取り消せてしまう
	old, existed := s.timeline[id]
	switch {
	case l.Public:
		e := newTimelineEntry(uid, l)
		e.Reports, e.WantCount, e.HelpfulCount = old.Reports, old.WantCount, old.HelpfulCount
		s.timeline[id] = e
	case existed:
		old.Public, old.Comment, old.PlaceID = false, "", ""
		s.timeline[id] = old
	}
	return l, nil
}

func (s *MemoryStore) AddFavorite(_ context.Context, uid, placeID string, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.favorites[uid] == nil {
		s.favorites[uid] = map[string]time.Time{}
	}
	if _, ok := s.favorites[uid][placeID]; ok {
		return nil
	}
	if len(s.favorites[uid]) >= MaxFavorites {
		return ErrTooManyFavorites
	}
	s.favorites[uid][placeID] = at.UTC()
	return nil
}

func (s *MemoryStore) RemoveFavorite(_ context.Context, uid, placeID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.favorites[uid], placeID)
	return nil
}

func (s *MemoryStore) Favorites(_ context.Context, uid string) ([]Favorite, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Favorite, 0, len(s.favorites[uid]))
	for id, at := range s.favorites[uid] {
		out = append(out, Favorite{PlaceID: id, CreatedAt: at})
	}
	sortFavorites(out)
	return out, nil
}

func (s *MemoryStore) VerdictCounts(_ context.Context, placeIDs []string) (map[string]VerdictCount, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]VerdictCount{}
	for _, id := range placeIDs {
		if c, ok := s.verdicts[id]; ok {
			out[id] = c
		}
	}
	return out, nil
}

func (s *MemoryStore) Timeline(_ context.Context, geos []string, limit int) ([]TimelineEntry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []TimelineEntry{}
	for _, e := range s.timeline {
		if slices.Contains(geos, e.Geo) {
			out = append(out, e)
		}
	}
	return latestVisible(out, limit), nil
}

func (s *MemoryStore) ReportEntry(_ context.Context, uid, entryID string, rep Report) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.timeline[entryID]
	if !ok || !e.Public {
		return ErrEntryNotFound
	}
	if s.reporters[entryID] == nil {
		s.reporters[entryID] = map[string]Report{}
	}
	if _, done := s.reporters[entryID][uid]; !done {
		s.reporters[entryID][uid] = rep
		e.Reports++
		s.timeline[entryID] = e
	}
	return nil
}

func (s *MemoryStore) MyReports(_ context.Context, uid string, entryIDs []string) (map[string]bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]bool{}
	for _, id := range entryIDs {
		if _, ok := s.reporters[id][uid]; ok {
			out[id] = true
		}
	}
	return out, nil
}

func (s *MemoryStore) ListLogs(_ context.Context, uid string) ([]Log, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := slices.Clone(s.logs[uid])
	slices.Reverse(out) // 同じ日時なら、後から保存したものを先にする
	slices.SortStableFunc(out, func(a, b Log) int { return b.CreatedAt.Compare(a.CreatedAt) })
	return out, nil
}

func (s *MemoryStore) day(date string) *usage.Day {
	d, ok := s.usage[date]
	if !ok {
		d = &usage.Day{Date: date, Real: map[string]int{}, Simulated: map[string]int{}}
		s.usage[date] = d
	}
	return d
}

func (s *MemoryStore) TakeCall(_ context.Context, date, key, uid string, limit, userLimit int) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d := s.day(date)
	total := 0
	for k, n := range d.Real {
		if usage.SameBudget(k, key) {
			total += n
		}
	}
	if total >= limit {
		return false, nil
	}
	if uid != "" {
		if s.userCalls[date] == nil {
			s.userCalls[date] = map[string]int{}
		}
		if s.userCalls[date][uid] >= userLimit {
			return false, nil
		}
		s.userCalls[date][uid]++
	}
	d.Real[key]++
	return true, nil
}

func (s *MemoryStore) AddSimulated(_ context.Context, date, key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.day(date).Simulated[key]++
	return nil
}

func (s *MemoryStore) Days(_ context.Context, dates []string) ([]usage.Day, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []usage.Day{}
	for _, date := range dates {
		if d, ok := s.usage[date]; ok {
			out = append(out, usage.Day{Date: date, Real: maps.Clone(d.Real), Simulated: maps.Clone(d.Simulated)})
		}
	}
	return out, nil
}

func (s *MemoryStore) Profile(_ context.Context, uid string) (Profile, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.profiles[AuthorTag(uid)]
	return p, ok, nil
}

func (s *MemoryStore) SetProfile(_ context.Context, uid string, p Profile) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.profiles[AuthorTag(uid)] = p
	return nil
}

func (s *MemoryStore) Profiles(_ context.Context, authorTags []string) (map[string]Profile, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]Profile{}
	for _, tag := range authorTags {
		if p, ok := s.profiles[tag]; ok {
			out[tag] = p
		}
	}
	return out, nil
}

func (s *MemoryStore) SetAchievements(_ context.Context, uid string, tiers map[string]int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.achievements[uid] = maps.Clone(tiers)
	return nil
}

func (s *MemoryStore) AchievementStats(context.Context) (AchievementStats, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := AchievementStats{Users: len(s.achievements), Counts: map[string][MaxAchievementTier]int{}}
	for _, tiers := range s.achievements {
		for id, d := range achievementDiff(nil, tiers) {
			c := out.Counts[id]
			for i := range c {
				c[i] += d[i]
			}
			out.Counts[id] = c
		}
	}
	return out, nil
}

// isLatestLog は l が、uid がその場所でいちばん後に訪問した記録か。
func (s *MemoryStore) isLatestLog(uid string, l Log) bool {
	for _, other := range s.logs[uid] {
		if other.PlaceID == l.PlaceID && other.ID != l.ID && newerVisit(other, l) {
			return false
		}
	}
	return true
}

func (s *MemoryStore) LatestTimeline(_ context.Context, limit int) ([]TimelineEntry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []TimelineEntry{}
	for _, e := range s.timeline {
		if e.Public {
			out = append(out, e)
		}
	}
	return latestVisible(out, limit), nil
}

func (s *MemoryStore) SavePhoto(_ context.Context, uid string, p Photo, _ time.Time) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	id := newPhotoID()
	p.Owner = uid
	s.photos[id] = p
	return id, nil
}

func (s *MemoryStore) Photo(_ context.Context, id string) (Photo, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	p, ok := s.photos[id]
	if !ok {
		return Photo{}, ErrPhotoNotFound
	}
	return p, nil
}

func (s *MemoryStore) React(_ context.Context, uid, entryID string, kind ReactionKind, on bool) (TimelineEntry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.timeline[entryID]
	if !ok || !e.Public {
		return TimelineEntry{}, ErrEntryNotFound
	}
	if e.Author == AuthorTag(uid) {
		return TimelineEntry{}, ErrOwnEntry
	}
	if s.reactions[entryID] == nil {
		s.reactions[entryID] = map[string]Reactions{}
	}
	before := s.reactions[entryID][uid]
	after := before.with(kind, on)
	s.reactions[entryID][uid] = after
	e.WantCount += boolDelta(before.Want, after.Want)
	e.HelpfulCount += boolDelta(before.Helpful, after.Helpful)
	s.timeline[entryID] = e
	return e, nil
}

func (s *MemoryStore) MyReactions(_ context.Context, uid string, entryIDs []string) (map[string]Reactions, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]Reactions{}
	for _, id := range entryIDs {
		if r, ok := s.reactions[id][uid]; ok && (r.Want || r.Helpful) {
			out[id] = r
		}
	}
	return out, nil
}

func (s *MemoryStore) TimelineEntries(_ context.Context, entryIDs []string) (map[string]TimelineEntry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := map[string]TimelineEntry{}
	for _, id := range entryIDs {
		if e, ok := s.timeline[id]; ok && e.Public {
			out[id] = e
		}
	}
	return out, nil
}
