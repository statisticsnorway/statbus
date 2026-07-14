package upgrade

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// STATBUS-164 half #2 — the on-disk phase serialization rename oracle (i).
//
// This build writes the canonical registry slugs ("new-sb-swapped",
// "new-sb-upgrading"); pre-rename releases wrote the legacy bytes
// ("post_swap", "resuming"). The single UnmarshalJSON decode chokepoint
// normalizes the two legacy spellings to their canonical slugs so every read
// site — direct json.Unmarshal, ReadFlagFile, and the read-modify-write stamps —
// sees the typed canonical phase, while genuine drift (junk) passes through for
// the FLAG_PHASE_UNKNOWN guard in recoverFromFlag.

// baseFlagJSON returns a service-held flag JSON blob with the given raw phase
// value, so tests can feed legacy, canonical, absent, or junk phase bytes.
func baseFlagJSON(phaseKV string) []byte {
	inner := `"id":7,"commit_sha":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",` +
		`"started_at":"2026-07-14T00:00:00Z","invoked_by":"test","trigger":"recovery",` +
		`"holder":"service"`
	if phaseKV != "" {
		inner += "," + phaseKV
	}
	return []byte("{" + inner + "}")
}

func TestPhaseBytes_DecodeNormalizesLegacyThroughChokepoint(t *testing.T) {
	cases := []struct {
		name      string
		phaseKV   string // the phase JSON key/value, or "" to omit the key entirely
		wantPhase string
	}{
		{"legacy post_swap -> new-sb-swapped", `"phase":"post_swap"`, PhaseNewSbSwapped},
		{"legacy resuming -> new-sb-upgrading", `"phase":"resuming"`, PhaseNewSbUpgrading},
		{"canonical new-sb-swapped is idempotent", `"phase":"new-sb-swapped"`, PhaseNewSbSwapped},
		{"canonical new-sb-upgrading is idempotent", `"phase":"new-sb-upgrading"`, PhaseNewSbUpgrading},
		{"explicit empty phase stays old-sb-upgrading", `"phase":""`, PhaseOldSbUpgrading},
		{"absent phase key defaults to old-sb-upgrading", ``, PhaseOldSbUpgrading},
		{"junk passes through untouched (drift guard's job)", `"phase":"future-phase-xyz"`, "future-phase-xyz"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			// Path 1: the decode chokepoint directly.
			var flag UpgradeFlag
			if err := json.Unmarshal(baseFlagJSON(tc.phaseKV), &flag); err != nil {
				t.Fatalf("json.Unmarshal: %v", err)
			}
			if flag.Phase != tc.wantPhase {
				t.Errorf("json.Unmarshal Phase: got %q, want %q", flag.Phase, tc.wantPhase)
			}

			// Path 2: the exported ReadFlagFile read path (writes a real flag file).
			dir := t.TempDir()
			if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o755); err != nil {
				t.Fatalf("mkdir tmp: %v", err)
			}
			if err := os.WriteFile(flagFilePath(dir), baseFlagJSON(tc.phaseKV), 0o644); err != nil {
				t.Fatalf("write flag: %v", err)
			}
			got, err := ReadFlagFile(dir)
			if err != nil {
				t.Fatalf("ReadFlagFile: %v", err)
			}
			if got.Phase != tc.wantPhase {
				t.Errorf("ReadFlagFile Phase: got %q, want %q", got.Phase, tc.wantPhase)
			}
		})
	}
}

// A read-modify-write of a legacy-bytes flag must PERSIST the canonical slug:
// the chokepoint normalizes on read, and Marshal writes what is in memory.
func TestPhaseBytes_ReadModifyWriteRewritesLegacyToCanonical(t *testing.T) {
	// Decode a legacy "resuming" flag, then re-marshal (a rewrite).
	var flag UpgradeFlag
	if err := json.Unmarshal(baseFlagJSON(`"phase":"resuming"`), &flag); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if flag.Phase != PhaseNewSbUpgrading {
		t.Fatalf("decode: got %q, want %q", flag.Phase, PhaseNewSbUpgrading)
	}
	out, err := json.Marshal(flag)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	// The written bytes carry the canonical slug, and no legacy spelling survives.
	var reread map[string]any
	if err := json.Unmarshal(out, &reread); err != nil {
		t.Fatalf("reread: %v", err)
	}
	if reread["phase"] != PhaseNewSbUpgrading {
		t.Errorf("rewritten phase: got %v, want %q", reread["phase"], PhaseNewSbUpgrading)
	}
}

// IsServiceNewSbRecovery must return true for a LEGACY-bytes forward-phase flag —
// the recovery boot owns tree→binary, preserving the stalenessGuard self-heal
// carve-out (STATBUS-065) and the deferred-checkout gates (STATBUS-060/171). The
// alias makes a pre-rename box's flag recover correctly on the newer binary.
func TestPhaseBytes_IsServiceNewSbRecovery_AcrossSpellings(t *testing.T) {
	cases := []struct {
		name    string
		phaseKV string
		want    bool
	}{
		{"legacy post_swap is a forward recovery", `"phase":"post_swap"`, true},
		{"legacy resuming is a forward recovery", `"phase":"resuming"`, true},
		{"canonical new-sb-swapped is a forward recovery", `"phase":"new-sb-swapped"`, true},
		{"canonical new-sb-upgrading is a forward recovery", `"phase":"new-sb-upgrading"`, true},
		{"preswap (empty) is NOT a forward recovery", `"phase":""`, false},
		{"junk is NOT a forward recovery", `"phase":"future-phase-xyz"`, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var flag UpgradeFlag
			if err := json.Unmarshal(baseFlagJSON(tc.phaseKV), &flag); err != nil {
				t.Fatalf("unmarshal: %v", err)
			}
			if got := flag.IsServiceNewSbRecovery(); got != tc.want {
				t.Errorf("IsServiceNewSbRecovery(phase=%q): got %v, want %v", flag.Phase, got, tc.want)
			}
		})
	}
}

// normalizePhaseBytes is the join of the two named tables; verify canonical and
// legacy stay structurally distinct (a legacy key is never a canonical key).
func TestPhaseBytes_TablesAreDisjoint(t *testing.T) {
	for legacy := range legacyPhaseByteAliases {
		if _, isCanonical := canonicalPhaseBytes[legacy]; isCanonical {
			t.Errorf("legacy spelling %q also appears in canonicalPhaseBytes — the tables must stay disjoint", legacy)
		}
	}
}
