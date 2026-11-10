package usage

import (
	"testing"
	"time"
)

func TestDateUsesJST(t *testing.T) {
	// UTC の 11/7 15:00 は JST の 11/8 0:00
	if got := DateOf(time.Date(2026, 11, 7, 15, 0, 0, 0, time.UTC)); got != "2026-11-08" {
		t.Errorf("DateOf = %s", got)
	}
}

func TestMonthDatesRunFromFirstToToday(t *testing.T) {
	got := MonthDates(time.Date(2026, 11, 3, 3, 0, 0, 0, jst))
	if len(got) != 3 || got[0] != "2026-11-01" || got[2] != "2026-11-03" {
		t.Errorf("MonthDates = %v", got)
	}
}

func TestSummarizeSeparatesTodayFromMonthAndRealFromSimulated(t *testing.T) {
	r := Summarize([]Day{
		{Date: "2026-11-01", Real: map[string]int{"nearby.explore": 3}},
		{Date: "2026-11-07", Real: map[string]int{"nearby.checkin": 2, "text.alternatives": 1}, Simulated: map[string]int{"nearby.explore": 5}},
	}, "2026-11-07", 100)
	if r.Today.Real.ByKind[KindNearby] != 2 || r.Today.Real.ByKind[KindText] != 1 {
		t.Errorf("today real = %+v", r.Today.Real)
	}
	if r.Month.Real.ByKind[KindNearby] != 5 {
		t.Errorf("month real = %+v", r.Month.Real)
	}
	if r.Today.Simulated.Calls["nearby.explore"] != 5 {
		t.Errorf("today simulated = %+v", r.Today.Simulated)
	}
}

func TestEstimateSubtractsFreeCapPerKind(t *testing.T) {
	r := Summarize([]Day{{Date: "2026-11-07", Real: map[string]int{
		"nearby.explore": 1200, "nearby.checkin": 800, "text.alternatives": 999,
	}}}, "2026-11-07", 100)
	// nearby は 2000 回で無料枠を 1000 回超える。text は無料枠の中
	if got := r.Month.Real.EstimatedUSD; got != 35 {
		t.Errorf("EstimatedUSD = %v", got)
	}
	if got := r.Month.Real.ListPriceUSD; got < 104.96 || got > 104.97 {
		t.Errorf("ListPriceUSD = %v", got)
	}
}
