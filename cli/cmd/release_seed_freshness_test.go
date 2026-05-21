package cmd

import (
	"strings"
	"testing"
)

// Task #76 — exercises the pure decision function decideSeedFreshness
// across all states of the {live-probe, live-version, seed.json,
// on-disk-max} input space. Side-effect-free; no DB, no .env, no
// filesystem required.
//
// Existing checkSeedGate tests in release_seed_gate_test.go cover the
// I/O wrapper paths (read seed.json, list migrations/) plus the
// legacy-fallback Fix-line strings, indirectly. This file covers the
// pure decision branches.

func TestDecideSeedFreshness_LiveAtAllInSync(t *testing.T) {
	state, reason := decideSeedFreshness(
		"20260521160000", // seed.json
		"20260521160000", // on-disk max
		liveSeedAt,
		"20260521160000", // live
	)
	if state != seedFreshnessFresh {
		t.Errorf("want fresh, got %d (reason=%q)", state, reason)
	}
	if reason != "" {
		t.Errorf("expected empty reason for fresh, got %q", reason)
	}
}

func TestDecideSeedFreshness_LiveAtCacheStale(t *testing.T) {
	// Live DB and on-disk in sync; only seed.json is behind (cache stale).
	state, reason := decideSeedFreshness(
		"20260520000000", // seed.json (behind)
		"20260521160000", // on-disk max
		liveSeedAt,
		"20260521160000", // live (== on-disk)
	)
	if state != seedFreshnessCacheStale {
		t.Errorf("want CacheStale, got %d (reason=%q)", state, reason)
	}
	if !strings.Contains(reason, "live statbus_seed") || !strings.Contains(reason, "20260521160000") || !strings.Contains(reason, "20260520000000") {
		t.Errorf("reason should mention all three versions; got %q", reason)
	}
}

func TestDecideSeedFreshness_LiveAtCacheStale_JsonAhead(t *testing.T) {
	// seed.json ahead of live+on-disk (stale snapshot of a future state) — still CacheStale.
	state, _ := decideSeedFreshness(
		"20270101000000", // seed.json (ahead)
		"20260521160000",
		liveSeedAt,
		"20260521160000",
	)
	if state != seedFreshnessCacheStale {
		t.Errorf("want CacheStale even when json is ahead, got %d", state)
	}
}

func TestDecideSeedFreshness_LiveAtDBBehindTree(t *testing.T) {
	state, reason := decideSeedFreshness(
		"20260521160000",
		"20260521160000", // on-disk max
		liveSeedAt,
		"20260520000000", // live (< on-disk)
	)
	if state != seedFreshnessDBBehindTree {
		t.Errorf("want DBBehindTree, got %d (reason=%q)", state, reason)
	}
	if !strings.Contains(reason, "20260520000000") || !strings.Contains(reason, "20260521160000") {
		t.Errorf("reason should mention live + on-disk versions; got %q", reason)
	}
}

func TestDecideSeedFreshness_LiveAtDBBehindTree_EmptyMigrationTable(t *testing.T) {
	// live probe succeeded but db.migration is empty (no migrations applied yet)
	state, reason := decideSeedFreshness(
		"20260521160000",
		"20260521160000",
		liveSeedAt,
		"", // live empty
	)
	if state != seedFreshnessDBBehindTree {
		t.Errorf("want DBBehindTree for empty live, got %d", state)
	}
	if !strings.Contains(reason, "no applied migrations") {
		t.Errorf("reason should mention empty live; got %q", reason)
	}
}

func TestDecideSeedFreshness_LiveAtDBAheadOfTree(t *testing.T) {
	state, reason := decideSeedFreshness(
		"20270101000000",
		"20260521160000", // on-disk max
		liveSeedAt,
		"20270101000000", // live > on-disk
	)
	if state != seedFreshnessDBAheadOfTree {
		t.Errorf("want DBAheadOfTree, got %d (reason=%q)", state, reason)
	}
	if !strings.Contains(reason, "20270101000000") || !strings.Contains(reason, "20260521160000") {
		t.Errorf("reason should mention live + on-disk versions; got %q", reason)
	}
}

func TestDecideSeedFreshness_LiveMissing(t *testing.T) {
	state, reason := decideSeedFreshness(
		"20260521160000",
		"20260521160000",
		liveSeedMissing,
		"",
	)
	if state != seedFreshnessDBMissing {
		t.Errorf("want DBMissing, got %d (reason=%q)", state, reason)
	}
	if !strings.Contains(reason, "does not exist") {
		t.Errorf("reason should mention does-not-exist; got %q", reason)
	}
}

func TestDecideSeedFreshness_LegacyFallbackFresh(t *testing.T) {
	state, reason := decideSeedFreshness(
		"20260521160000",
		"20260521160000",
		liveSeedUnknown,
		"",
	)
	if state != seedFreshnessFresh {
		t.Errorf("want Fresh in legacy fallback when versions match, got %d (reason=%q)", state, reason)
	}
}

func TestDecideSeedFreshness_LegacyFallbackBehind(t *testing.T) {
	state, reason := decideSeedFreshness(
		"20260520000000", // seed.json behind
		"20260521160000", // on-disk
		liveSeedUnknown,
		"",
	)
	if state != seedFreshnessBehind {
		t.Errorf("want Behind in legacy fallback, got %d (reason=%q)", state, reason)
	}
	if !strings.Contains(reason, "<") {
		t.Errorf("reason should use < comparison; got %q", reason)
	}
}

func TestDecideSeedFreshness_LegacyFallbackAhead(t *testing.T) {
	state, reason := decideSeedFreshness(
		"20270101000000", // seed.json ahead
		"20260521160000", // on-disk
		liveSeedUnknown,
		"",
	)
	if state != seedFreshnessAhead {
		t.Errorf("want Ahead in legacy fallback, got %d (reason=%q)", state, reason)
	}
	if !strings.Contains(reason, ">") {
		t.Errorf("reason should use > comparison; got %q", reason)
	}
}

// Precedence guard: when liveState=Missing, the live-empty version
// branch on the seed.json side should NEVER be reached (Missing takes
// precedence over any comparison).
func TestDecideSeedFreshness_MissingTakesPrecedence(t *testing.T) {
	// Even if seed.json + on-disk look fine, Missing wins.
	state, _ := decideSeedFreshness(
		"20260521160000",
		"20260521160000",
		liveSeedMissing,
		"20260521160000", // shouldn't be considered
	)
	if state != seedFreshnessDBMissing {
		t.Errorf("Missing should take precedence; got %d", state)
	}
}
