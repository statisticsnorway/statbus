package cmd

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-327: `./sb migrate down` gains `./sb migrate up`'s --target.
//
// THE COST OF NOT HAVING IT, observed 2026-08-31 during 308's teardown: a WIP
// migration was applied to dev AND seed, `migrate down` reverted dev only, and
// the seed was left AHEAD of HEAD with no file on disk — precisely the state
// assert-db-at-head and the 313 runner gate exist to catch. The sanctioned
// recovery was a full recreate-seed replay: minutes for a two-second revert.
// The dangerous part was not the delay but the temptation it created, to delete
// the ledger row or run the down SQL by hand against the seed. The ledger is
// believable only because nothing edits it by hand, so a missing flag must never
// be the reason someone reaches for that escape.

// Both down commands must carry the flag. Registering it on `down` alone would
// leave `down all` silently dev-only — the same asymmetry, moved one level down,
// and harder to notice because the flag would appear to exist.
func TestBothDownCommandsAcceptTarget(t *testing.T) {
	if f := migrateDownCmd.Flags().Lookup("target"); f == nil {
		t.Error("`migrate down` has no --target flag — the seed is unreachable and the asymmetry stands")
	}
	if f := migrateDownAllCmd.Flags().Lookup("target"); f == nil {
		t.Error("`migrate down all` has no --target flag — it would silently stay dev-only")
	}
}

// The default must be dev, matching up. Redo defaults to seed because it is a
// build-time repair verb; down is the developer's ordinary retreat on whatever
// they are working against. A seed default here would silently redirect every
// existing `./sb migrate down` — in muscle memory, scripts and runbooks — to a
// different database, which is a worse hazard than the asymmetry being fixed.
func TestDownTargetDefaultsToDevMatchingUp(t *testing.T) {
	down := migrateDownCmd.Flags().Lookup("target")
	if down == nil {
		t.Fatal("no --target flag on down")
	}
	up := migrateUpCmd.Flags().Lookup("target")
	if up == nil {
		t.Fatal("no --target flag on up")
	}
	if down.DefValue != "dev" {
		t.Errorf("down --target default = %q, want \"dev\"", down.DefValue)
	}
	if down.DefValue != up.DefValue {
		t.Errorf("down default %q must match up's %q — the two verbs are a pair and a reader will assume symmetry",
			down.DefValue, up.DefValue)
	}
	if allFlag := migrateDownAllCmd.Flags().Lookup("target"); allFlag == nil || allFlag.DefValue != "dev" {
		t.Error("`down all` --target must default to dev as well")
	}
}

// The flag must describe the same two targets up describes, in the same terms —
// an operator reading either help text should not have to wonder whether the
// words mean different things on the two verbs.
func TestDownTargetUsageMatchesUp(t *testing.T) {
	down := migrateDownCmd.Flags().Lookup("target")
	up := migrateUpCmd.Flags().Lookup("target")
	if down == nil || up == nil {
		t.Fatal("missing --target flag")
	}
	if down.Usage != up.Usage {
		t.Errorf("usage text differs between down and up:\n  down: %s\n  up:   %s", down.Usage, up.Usage)
	}
	for _, want := range []string{"dev", "seed", "POSTGRES_APP_DB", "POSTGRES_SEED_DB"} {
		if !strings.Contains(down.Usage, want) {
			t.Errorf("down --target usage does not mention %q: %s", want, down.Usage)
		}
	}
}

// GUARD SCOPE IS PER-TARGET AND UNCHANGED BY IT. --target selects WHICH database
// is addressed; it must never widen HOW MUCH is rolled back. The scope wideners
// are --to and the `all` subcommand, exactly as before, and they behave the same
// on either database. This pins that the down path takes no target-conditional
// branch that could make the seed a wider operation than dev.
func TestTargetDoesNotWidenScope(t *testing.T) {
	// `down` and `down all` differ in the `all` argument alone — the flag plays
	// no part in that decision. Asserted structurally because the alternative
	// (running real rollbacks against two live databases) needs a DB per case
	// and would test the plumbing, not the property.
	src := mustReadRepoFile(t, "cli/cmd/migrate.go")
	if !strings.Contains(src, "runMigrateDown(migrateTo, false, cmd.Flags().Changed(\"target\"))") {
		t.Error("`down` must pass all=false regardless of target")
	}
	if !strings.Contains(src, "runMigrateDown(migrateTo, true, cmd.Flags().Changed(\"target\"))") {
		t.Error("`down all` must pass all=true regardless of target")
	}
	// No target-conditional scope logic anywhere in the down path.
	downFn := src[strings.Index(src, "func runMigrateDown("):]
	downFn = downFn[:strings.Index(downFn, "\n}\n")]
	for _, forbidden := range []string{`== "seed"`, `== "dev"`} {
		if strings.Contains(downFn, forbidden) {
			t.Errorf("runMigrateDown branches on the target (%s) — scope must be target-independent", forbidden)
		}
	}
}

// It must reuse up's targeting machinery rather than growing a parallel one.
// ResolveTargetDB and OverrideTargetDB already carry the divergence refusal
// (STATBUS-146) and the explicit-target-wins rule (STATBUS-150); a second path
// would have to re-earn both and would drift the first time either changed.
func TestDownReusesTheSharedTargetingMachinery(t *testing.T) {
	src := mustReadRepoFile(t, "cli/cmd/migrate.go")
	downFn := src[strings.Index(src, "func runMigrateDown("):]
	downFn = downFn[:strings.Index(downFn, "\n}\n")]

	for _, want := range []string{"migrate.ResolveTargetDB(", "migrate.OverrideTargetDB(", "defer restore()"} {
		if !strings.Contains(downFn, want) {
			t.Errorf("runMigrateDown does not use %s — it must share up's targeting path, not reimplement it", want)
		}
	}
}

// mustReadRepoFile reads a repo-relative file for the structural assertions
// above, via the same path helper the other cmd tests use.
func mustReadRepoFile(t *testing.T, relPath string) string {
	t.Helper()
	b, err := os.ReadFile(thisRepoFile(t, relPath))
	if err != nil {
		t.Fatalf("read %s: %v", relPath, err)
	}
	return string(b)
}
