package cmd

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// seedDecisionProj builds a temp project with migrations 1,2,3 and returns the
// project dir and V_prev = migration 2 (so migration 3 is the "delta" above it).
func seedDecisionProj(t *testing.T) (proj string, vprev int64) {
	t.Helper()
	proj = t.TempDir()
	if err := os.MkdirAll(filepath.Join(proj, "migrations"), 0755); err != nil {
		t.Fatal(err)
	}
	for _, m := range []struct{ name, body string }{
		{"20260101000001_first.up.sql", "AAA"},
		{"20260101000002_second.up.sql", "BBB"},
		{"20260101000003_third.up.sql", "CCC"}, // > V_prev: the delta an incremental applies
	} {
		if err := os.WriteFile(filepath.Join(proj, "migrations", m.name), []byte(m.body), 0644); err != nil {
			t.Fatal(err)
		}
	}
	return proj, int64(20260101000002)
}

// priorSeedMeta returns a prior seedMeta recording V_prev + the fingerprint of
// migrations <= V_prev as they are NOW (i.e. a faithful prior seed).
func priorSeedMeta(t *testing.T, proj string, vprev int64) *seedMeta {
	t.Helper()
	fp, err := migrate.UpMigrationsFingerprintUpTo(proj, vprev)
	if err != nil {
		t.Fatal(err)
	}
	return &seedMeta{MigrationVersion: "20260101000002", MigrationsFingerprint: fp}
}

func TestSeedBuildDecision_IncrementalWhenPrefixUnchanged(t *testing.T) {
	proj, vprev := seedDecisionProj(t)
	inc, reason := SeedBuildDecision(priorSeedMeta(t, proj, vprev), proj)
	if !inc {
		t.Errorf("unchanged <=V_prev migrations must allow incremental; got full: %s", reason)
	}
}

// The normal case: only a NEW migration ABOVE V_prev was added (the delta). The
// gate must STILL allow incremental — that is the whole point of the shortcut.
func TestSeedBuildDecision_IncrementalWhenOnlyDeltaAdded(t *testing.T) {
	proj, vprev := seedDecisionProj(t)
	prior := priorSeedMeta(t, proj, vprev)
	if err := os.WriteFile(filepath.Join(proj, "migrations", "20260101000004_fourth.up.sql"), []byte("DDD"), 0644); err != nil {
		t.Fatal(err)
	}
	if inc, reason := SeedBuildDecision(prior, proj); !inc {
		t.Errorf("adding only a >V_prev migration must still allow incremental; got full: %s", reason)
	}
}

func TestSeedBuildDecision_FullWhenNoPrior(t *testing.T) {
	proj, _ := seedDecisionProj(t)
	if inc, _ := SeedBuildDecision(nil, proj); inc {
		t.Error("no prior seed must force a full rebuild")
	}
}

func TestSeedBuildDecision_FullWhenNoFingerprint(t *testing.T) {
	proj, _ := seedDecisionProj(t)
	if inc, _ := SeedBuildDecision(&seedMeta{MigrationVersion: "20260101000002"}, proj); inc {
		t.Error("a pre-116 prior seed (no fingerprint) must force a full rebuild")
	}
}

func TestSeedBuildDecision_FullWhenPrefixMigrationEdited(t *testing.T) {
	proj, vprev := seedDecisionProj(t)
	prior := priorSeedMeta(t, proj, vprev)
	// Retroactively edit a migration <= V_prev (the silent-drift hazard).
	if err := os.WriteFile(filepath.Join(proj, "migrations", "20260101000001_first.up.sql"), []byte("AAA-EDITED"), 0644); err != nil {
		t.Fatal(err)
	}
	if inc, reason := SeedBuildDecision(prior, proj); inc {
		t.Errorf("an edited <=V_prev migration must force full; got incremental: %s", reason)
	}
}

func TestSeedBuildDecision_FullWhenPrefixMigrationRemoved(t *testing.T) {
	proj, vprev := seedDecisionProj(t)
	prior := priorSeedMeta(t, proj, vprev)
	if err := os.Remove(filepath.Join(proj, "migrations", "20260101000001_first.up.sql")); err != nil {
		t.Fatal(err)
	}
	if inc, _ := SeedBuildDecision(prior, proj); inc {
		t.Error("a removed <=V_prev migration must force a full rebuild")
	}
}
