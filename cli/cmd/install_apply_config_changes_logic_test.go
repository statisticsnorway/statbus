package cmd

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/config"
)

// --- snapshotCaddyConfig -------------------------------------------------

// TestSnapshotCaddyConfig_ReadErrorNeverComparesEqualToItself is the
// architect's MUST-FIX: a genuine read error (as opposed to a legitimately
// absent file) must not be swallowed into "" — doing so let a file
// unreadable in BOTH the old and new snapshot compare equal, misreading a
// failure to observe as evidence of no change. This proves the fix holds
// even for the hardest case: the SAME persistent failure, read twice.
//
// A directory-in-place-of-a-file is used to force a non-NotExist error
// portably (permission bits can be bypassed when the test runs as root;
// "is a directory" fails for everyone).
func TestSnapshotCaddyConfig_ReadErrorNeverComparesEqualToItself(t *testing.T) {
	dir := t.TempDir()
	confDir := filepath.Join(dir, "caddy", "config")
	if err := os.MkdirAll(confDir, 0755); err != nil {
		t.Fatal(err)
	}
	target := config.CaddyConfigFiles[0]
	if err := os.MkdirAll(filepath.Join(confDir, target), 0755); err != nil {
		t.Fatal(err)
	}

	snap1 := snapshotCaddyConfig(dir)
	snap2 := snapshotCaddyConfig(dir)
	if snap1 == snap2 {
		t.Errorf("two snapshots over the SAME persistent, unchanged read failure compared EQUAL (%q) — "+
			"this is exactly the bug: a failure to observe the file was counted as evidence of no-change, "+
			"which would suppress a proxy restart a real config change needed", snap1)
	}
}

// TestSnapshotCaddyConfig_MissingFileIsNotAnError proves the OTHER half of
// the distinction still holds: a file that legitimately does not exist
// (e.g. before the very first generate) is NOT a read error — it must not
// be forced to differ from itself the way a real read failure is, or every
// snapshot taken before caddy/config exists would spuriously "change".
func TestSnapshotCaddyConfig_MissingFileIsNotAnError(t *testing.T) {
	dir := t.TempDir() // caddy/config does not exist at all
	snap1 := snapshotCaddyConfig(dir)
	snap2 := snapshotCaddyConfig(dir)
	if snap1 != snap2 {
		t.Errorf("two snapshots over an absent caddy/config directory differed (%q vs %q) — absence is a legitimate, stable observation, not a read error", snap1, snap2)
	}
}

// --- diffEnvKeys ------------------------------------------------------

func TestDiffEnvKeys_NoChangeYieldsNoKeys(t *testing.T) {
	content := "FOO=bar\nBAZ=qux\n"
	got := diffEnvKeys(content, content)
	if len(got) != 0 {
		t.Errorf("diffEnvKeys(same, same) = %v, want empty — AC#2 depends on this being exact", got)
	}
}

func TestDiffEnvKeys_DetectsChangedAddedRemoved(t *testing.T) {
	old := "UNCHANGED=1\nCHANGED=old\nREMOVED=gone\n"
	new := "UNCHANGED=1\nCHANGED=new\nADDED=fresh\n"
	got := diffEnvKeys(old, new)
	sort.Strings(got)
	want := []string{"ADDED", "CHANGED", "REMOVED"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("diffEnvKeys = %v, want %v (UNCHANGED must NOT appear)", got, want)
	}
}

// --- restartClassesForKeys ---------------------------------------------

// TestRestartClassesForKeys_IsolatedSingleClassPerKey is AC#1: changing
// ONLY a key that belongs to one class must produce EXACTLY that class —
// not the union of every class that exists, not a neighboring class.
func TestRestartClassesForKeys_IsolatedSingleClassPerKey(t *testing.T) {
	classesByKey := map[string][]config.RestartClass{
		"APP_ONLY_KEY":     {config.RestartApp},
		"WORKER_ONLY_KEY":  {config.RestartWorker},
		"REST_ONLY_KEY":    {config.RestartRest},
		"DB_ONLY_KEY":      {config.RestartDB},
		"PROXY_ONLY_KEY":   {config.RestartProxyRestart},
		"DAEMON_ONLY_KEY":  {config.RestartUpgradeDaemon},
		"MULTI_CLASS_KEY":  {config.RestartApp, config.RestartWorker, config.RestartDB},
		"NO_RESTART_KEY":   {},
		"UNCLASSIFIED_KEY": nil, // should be unreachable in production; must not panic
	}

	cases := []struct {
		key  string
		want config.RestartClass
	}{
		{"APP_ONLY_KEY", config.RestartApp},
		{"WORKER_ONLY_KEY", config.RestartWorker},
		{"REST_ONLY_KEY", config.RestartRest},
		{"DB_ONLY_KEY", config.RestartDB},
		{"PROXY_ONLY_KEY", config.RestartProxyRestart},
		{"DAEMON_ONLY_KEY", config.RestartUpgradeDaemon},
	}
	for _, c := range cases {
		got := restartClassesForKeys([]string{c.key}, classesByKey)
		if len(got) != 1 || !got[c.want] {
			t.Errorf("restartClassesForKeys([%q]) = %v, want exactly {%v}", c.key, got, c.want)
		}
	}
}

func TestRestartClassesForKeys_UnionsMultipleClassesForOneKey(t *testing.T) {
	classesByKey := map[string][]config.RestartClass{
		"DEBUG": {config.RestartApp, config.RestartWorker, config.RestartDB},
	}
	got := restartClassesForKeys([]string{"DEBUG"}, classesByKey)
	want := map[config.RestartClass]bool{config.RestartApp: true, config.RestartWorker: true, config.RestartDB: true}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("restartClassesForKeys([DEBUG]) = %v, want %v — a key with real multi-service consumers must produce a SET, never collapse to one class", got, want)
	}
}

func TestRestartClassesForKeys_NoChangedKeysYieldsEmptySet(t *testing.T) {
	classesByKey := map[string][]config.RestartClass{"ANY_KEY": {config.RestartApp}}
	got := restartClassesForKeys(nil, classesByKey)
	if len(got) != 0 {
		t.Errorf("restartClassesForKeys(nil) = %v, want empty — AC#2 depends on this", got)
	}
}

// --- applyPendingRestarts -----------------------------------------------

func withFakeComposeRestart(t *testing.T) *[]string {
	t.Helper()
	var calls []string
	orig := composeRestart
	composeRestart = func(dir, service string) error {
		calls = append(calls, service)
		return nil
	}
	t.Cleanup(func() { composeRestart = orig })
	return &calls
}

// TestApplyPendingRestarts_EmptyPendingRestartsNothing is AC#2 at the apply
// layer: an empty class set must issue ZERO docker compose restart calls.
func TestApplyPendingRestarts_EmptyPendingRestartsNothing(t *testing.T) {
	calls := withFakeComposeRestart(t)
	if err := applyPendingRestarts("/tmp/does-not-matter", map[config.RestartClass]bool{}); err != nil {
		t.Fatalf("applyPendingRestarts: %v", err)
	}
	if len(*calls) != 0 {
		t.Errorf("composeRestart called for %v, want no calls at all — this is exactly the AC#7 regression an unconditional-apply would introduce", *calls)
	}
}

// TestApplyPendingRestarts_RestartsExactlyThePendingClasses is AC#1 at the
// apply layer: only the classes actually present in pending get restarted.
func TestApplyPendingRestarts_RestartsExactlyThePendingClasses(t *testing.T) {
	calls := withFakeComposeRestart(t)
	pending := map[config.RestartClass]bool{config.RestartApp: true}
	if err := applyPendingRestarts("/tmp/does-not-matter", pending); err != nil {
		t.Fatalf("applyPendingRestarts: %v", err)
	}
	want := []string{"app"}
	if !reflect.DeepEqual(*calls, want) {
		t.Errorf("composeRestart calls = %v, want %v — db/rest/worker/proxy must NOT be touched for an app-only change", *calls, want)
	}
}

// TestApplyPendingRestarts_OrderIsDeterministicDBFirst pins the documented
// restart order (db heaviest-first, so dependents reconnect against an
// already-restarted db) rather than leaving it to map iteration order.
func TestApplyPendingRestarts_OrderIsDeterministicDBFirst(t *testing.T) {
	calls := withFakeComposeRestart(t)
	pending := map[config.RestartClass]bool{
		config.RestartProxyRestart: true,
		config.RestartApp:          true,
		config.RestartDB:           true,
	}
	if err := applyPendingRestarts("/tmp/does-not-matter", pending); err != nil {
		t.Fatalf("applyPendingRestarts: %v", err)
	}
	want := []string{"db", "app", "proxy"}
	if !reflect.DeepEqual(*calls, want) {
		t.Errorf("composeRestart order = %v, want %v", *calls, want)
	}
}

// TestApplyPendingRestarts_UnconditionalApplyWouldFailNoChangeNoRestart is
// AC#7: a RED-verification recorded as a test, not just a one-off manual
// mutation, so a future refactor that reintroduces "always restart
// everything" is caught the same way this ticket's own bug would have been
// caught. It asserts the CURRENT, correct behavior (empty pending → zero
// calls) and documents, in the failure message a regression would produce,
// exactly what an unconditional-apply implementation gets wrong.
func TestApplyPendingRestarts_UnconditionalApplyWouldFailNoChangeNoRestart(t *testing.T) {
	calls := withFakeComposeRestart(t)
	// Simulates the "nothing changed" outcome of the check() closure in
	// runInstall's step table (empty changedKeys, caddy config unchanged).
	noChange := map[config.RestartClass]bool{}
	if err := applyPendingRestarts("/tmp/does-not-matter", noChange); err != nil {
		t.Fatalf("applyPendingRestarts: %v", err)
	}
	if len(*calls) != 0 {
		t.Fatalf(`applyPendingRestarts restarted %v with an EMPTY pending set.

This is exactly what an "unconditional apply" implementation (restart every
class on every install run, regardless of what changed) would do wrong: a
healthy, unchanged box would restart db/rest/worker/app/proxy on every
idempotent `+"`./sb install`"+` refresh — dropping every live connection and
bouncing every container for no reason. STATBUS-332 exists specifically to
replace that behavior with DETECT-WHAT-CHANGED.`, *calls)
	}
}
