package cmd

import (
	"testing"
)

func TestInstallSeedNoFetchSkipsFetchAndRestore(t *testing.T) {
	// An empty database, so without the override the seed restore would run.
	dir, sbInvoked := seedFreshnessProject(t, `case "$sql" in
  *to_regclass*) echo "" ;;
  *) echo "unexpected query: $sql" >&2; exit 3 ;;
esac
`)
	t.Setenv("STATBUS_DB_SEED_NO_FETCH", "1")
	if !checkSeedRestored(dir) {
		t.Fatal("Seed step must be skipped when STATBUS_DB_SEED_NO_FETCH=1")
	}
	if err := runSeedRestore(dir); err != nil {
		t.Fatalf("direct seed invocation with no-fetch control: %v", err)
	}
	if sbInvoked() {
		t.Fatal("seed fetch/restore invoked despite no-fetch control")
	}

	// The override is opt-in; without it the fetch path is still reached.
	t.Setenv("STATBUS_DB_SEED_NO_FETCH", "0")
	_ = runSeedRestore(dir)
	if !sbInvoked() {
		t.Fatal("expected seed fetch invocation without override")
	}
}
