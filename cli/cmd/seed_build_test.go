package cmd

import "testing"

// STATBUS-116 AC#1 — pure cores of the seed-build wiring. Dangerous failures:
// (a) taking incremental while the enable-gate is OFF (must-not-flip-live), and
// (b) chaining incrementals past the depth cap (unbounded drift). These pin the
// routing + the ancestor-walk with no git / docker / DB.

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

// THE must-not-flip-live guarantee: enable-gate OFF ⇒ full, even when the
// fingerprint decision said incremental.
func TestResolveSeedPath_GateOffForcesFull(t *testing.T) {
	use, depth, note := resolveSeedPath(false, true, &seedMeta{IncrementalDepth: 3})
	if use || depth != 0 || note != "" {
		t.Errorf("enable-gate off must force full (no note); got use=%v depth=%d note=%q", use, depth, note)
	}
}

// Enabled but the fingerprint gate said full ⇒ full.
func TestResolveSeedPath_DecisionFullStaysFull(t *testing.T) {
	use, depth, _ := resolveSeedPath(true, false, &seedMeta{IncrementalDepth: 1})
	if use || depth != 0 {
		t.Errorf("decision=full must stay full; got use=%v depth=%d", use, depth)
	}
}

// Enabled + decision incremental + under the cap ⇒ incremental, depth+1.
func TestResolveSeedPath_IncrementalBumpsDepth(t *testing.T) {
	use, depth, note := resolveSeedPath(true, true, &seedMeta{IncrementalDepth: 3})
	if !use || depth != 4 || note != "" {
		t.Errorf("incremental under cap must bump depth to prior+1; got use=%v depth=%d note=%q", use, depth, note)
	}
}

// The depth cap forces a full baseline (drift bound) and explains why.
func TestResolveSeedPath_DepthCapForcesFull(t *testing.T) {
	// prior depth = cap-1 ⇒ prior+1 == cap ⇒ must force full.
	use, depth, note := resolveSeedPath(true, true, &seedMeta{IncrementalDepth: MaxIncrementalDepth - 1})
	if use || depth != 0 {
		t.Errorf("hitting the depth cap must force full; got use=%v depth=%d", use, depth)
	}
	if note == "" {
		t.Error("the depth-cap fallback must explain itself (loud, not silent)")
	}
	// One below the cap boundary still goes incremental.
	if use2, depth2, _ := resolveSeedPath(true, true, &seedMeta{IncrementalDepth: MaxIncrementalDepth - 2}); !use2 || depth2 != MaxIncrementalDepth-1 {
		t.Errorf("just under the cap must still be incremental; got use=%v depth=%d", use2, depth2)
	}
}

// A nil prior (empty/absent injected context) can never be incremental.
func TestResolveSeedPath_NilPriorFull(t *testing.T) {
	if use, depth, _ := resolveSeedPath(true, true, nil); use || depth != 0 {
		t.Errorf("nil prior must be full; got use=%v depth=%d", use, depth)
	}
}
