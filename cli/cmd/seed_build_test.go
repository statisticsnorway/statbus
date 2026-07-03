package cmd

import "testing"

// STATBUS-116 AC#1 — pure cores of the seed-build wiring. The dangerous failure
// is chaining incrementals past the depth cap (unbounded drift); the routing
// also must fall back to full whenever the fingerprint decision says full or no
// prior is injected. These pin the routing + the ancestor-walk with no git /
// docker / DB. (The external enable-flag was retired — the in-code gates below
// ARE the gate.)

// ── ancestor-walk (Step 2) ───────────────────────────────────────────────────

func TestFirstPublishedAncestor_NearestWins(t *testing.T) {
	ancestors := []string{"aaaaaaaa", "bbbbbbbb", "cccccccc"}
	// bbbbbbbb is the closest published (aaaaaaaa isn't) → it must win.
	exists := func(s string) bool { return s == "bbbbbbbb" || s == "cccccccc" }
	tag, found, capHit := firstPublishedAncestor(ancestors, exists, 40)
	if !found || capHit || tag != seedImageRepo+":bbbbbbbb" {
		t.Errorf("nearest published ancestor must win; got tag=%q found=%v cap=%v", tag, found, capHit)
	}
}

func TestFirstPublishedAncestor_NoneFound(t *testing.T) {
	tag, found, capHit := firstPublishedAncestor([]string{"aaaaaaaa", "bbbbbbbb"}, func(string) bool { return false }, 40)
	if found || capHit || tag != "" {
		t.Errorf("no published ancestor must be found=false, no cap; got tag=%q found=%v cap=%v", tag, found, capHit)
	}
}

// The cap must STOP the walk (bounded registry probes) and report capHit so the
// caller logs it — never a silent cap.
func TestFirstPublishedAncestor_CapHitStopsAndReports(t *testing.T) {
	ancestors := []string{"a1a1a1a1", "b2b2b2b2", "c3c3c3c3", "d4d4d4d4"}
	probed := 0
	exists := func(string) bool { probed++; return false } // nothing published
	tag, found, capHit := firstPublishedAncestor(ancestors, exists, 2)
	if found || tag != "" {
		t.Errorf("cap-hit must not find; got tag=%q found=%v", tag, found)
	}
	if !capHit {
		t.Error("exhausting the cap with no hit must report capHit=true (no silent cap)")
	}
	if probed != 2 {
		t.Errorf("walk must stop AT the cap: probed %d, want 2", probed)
	}
}

// A hit within the cap must NOT report capHit.
func TestFirstPublishedAncestor_HitWithinCapNoCapFlag(t *testing.T) {
	_, found, capHit := firstPublishedAncestor([]string{"aaaaaaaa", "bbbbbbbb"}, func(s string) bool { return s == "bbbbbbbb" }, 40)
	if !found || capHit {
		t.Errorf("a hit within the cap must be found without capHit; found=%v cap=%v", found, capHit)
	}
}

// ── build routing (Step 3a) ──────────────────────────────────────────────────

// THE INVARIANT (replaces the retired must-not-flip-live guard): now that the
// external enable-flag is gone and the incremental path runs unconditionally,
// resolveSeedPath is the sole routing gate. It returns INCREMENTAL for EXACTLY
// ONE combination — the fingerprint decision approved AND a prior is present AND
// depth is under the cap — and DEGRADES TO FULL for every other combination.
// This always-on table locks that: no input can produce a build that isn't
// either a safe incremental or a safe full (there is no broken-build branch).
func TestResolveSeedPath_IncrementalOnlyWhenAllGatesPass(t *testing.T) {
	underCap := &seedMeta{IncrementalDepth: 1}                    // 1+1=2 < 5
	atCap := &seedMeta{IncrementalDepth: MaxIncrementalDepth - 1} // hits the cap
	cases := []struct {
		name        string
		incremental bool
		prior       *seedMeta
		wantUse     bool
	}{
		{"decision=full, prior present -> FULL", false, underCap, false},
		{"decision=full, nil prior -> FULL", false, nil, false},
		{"decision=incremental, nil prior (empty context / resolve failure) -> FULL", true, nil, false},
		{"decision=incremental, prior at depth cap -> FULL", true, atCap, false},
		{"decision=incremental, prior under cap -> INCREMENTAL (the ONLY yes)", true, underCap, true},
	}
	yesCount := 0
	for _, tc := range cases {
		use, depth, _ := resolveSeedPath(tc.incremental, tc.prior)
		if use != tc.wantUse {
			t.Errorf("%s: use=%v, want %v", tc.name, use, tc.wantUse)
		}
		if !use && depth != 0 {
			t.Errorf("%s: FULL must yield depth 0, got %d", tc.name, depth)
		}
		if use {
			yesCount++
		}
	}
	if yesCount != 1 {
		t.Errorf("exactly one input combination may yield incremental; got %d", yesCount)
	}
}

// The fingerprint gate said full ⇒ full (even with a prior present).
func TestResolveSeedPath_DecisionFullStaysFull(t *testing.T) {
	use, depth, _ := resolveSeedPath(false, &seedMeta{IncrementalDepth: 1})
	if use || depth != 0 {
		t.Errorf("decision=full must stay full; got use=%v depth=%d", use, depth)
	}
}

// Decision incremental + prior present + under the cap ⇒ incremental, depth+1.
func TestResolveSeedPath_IncrementalBumpsDepth(t *testing.T) {
	use, depth, note := resolveSeedPath(true, &seedMeta{IncrementalDepth: 3})
	if !use || depth != 4 || note != "" {
		t.Errorf("incremental under cap must bump depth to prior+1; got use=%v depth=%d note=%q", use, depth, note)
	}
}

// The depth cap forces a full baseline (drift bound) and explains why.
func TestResolveSeedPath_DepthCapForcesFull(t *testing.T) {
	// prior depth = cap-1 ⇒ prior+1 == cap ⇒ must force full.
	use, depth, note := resolveSeedPath(true, &seedMeta{IncrementalDepth: MaxIncrementalDepth - 1})
	if use || depth != 0 {
		t.Errorf("hitting the depth cap must force full; got use=%v depth=%d", use, depth)
	}
	if note == "" {
		t.Error("the depth-cap fallback must explain itself (loud, not silent)")
	}
	// One below the cap boundary still goes incremental.
	if use2, depth2, _ := resolveSeedPath(true, &seedMeta{IncrementalDepth: MaxIncrementalDepth - 2}); !use2 || depth2 != MaxIncrementalDepth-1 {
		t.Errorf("just under the cap must still be incremental; got use=%v depth=%d", use2, depth2)
	}
}

// A nil prior (empty/absent injected context) can never be incremental.
func TestResolveSeedPath_NilPriorFull(t *testing.T) {
	if use, depth, _ := resolveSeedPath(true, nil); use || depth != 0 {
		t.Errorf("nil prior must be full; got use=%v depth=%d", use, depth)
	}
}
