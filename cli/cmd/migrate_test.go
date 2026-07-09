package cmd

import (
	"os"
	"strings"
	"testing"
)

// TestMigrateFingerprintCmdIsUnbounded pins STATBUS-126 (architect review
// rider): the `./sb migrate fingerprint` verb must call
// UpMigrationsFingerprintUpTo with math.MaxInt64 — the WHOLE on-disk set,
// never a bounded maxVersion. dev.sh's test-template staleness stamp is this
// verb's output; a bounded call would silently resurrect the exact disease
// this ticket closed (a stamp blind to edits past the bound, so a stale
// template gets silently reused). Source-level pin (mirrors
// internal/upgrade/daemon_dsn_tag_test.go's style) so a future edit to the
// verb cannot drop the unbounded call without a test noticing.
func TestMigrateFingerprintCmdIsUnbounded(t *testing.T) {
	path := thisRepoFile(t, "cli/cmd/migrate.go")
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	const want = "migrate.UpMigrationsFingerprintUpTo(config.ProjectDir(), math.MaxInt64)"
	if !strings.Contains(string(body), want) {
		t.Errorf("STATBUS-126: migrateFingerprintCmd must call %q — a bounded "+
			"maxVersion would silently resurrect the stale-template-stamp disease "+
			"this ticket closes", want)
	}
}
