package cmd

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// #4 unit-reconcile (plan upgrade-resume-structural-whole.md): the upgrade
// systemd unit is copied VERBATIM (cmd/install.go copyFile: os.ReadFile →
// os.WriteFile, no templating; the %h/%i/%u specifiers resolve at runtime) to
// ~/.config/systemd/user/statbus-upgrade@.service. So a drifted on-disk unit
// (e.g. rune's stale WatchdogUSec=infinity / TimeoutStartSec=90 vs the repo's
// 120/120) is detectable by a byte-compare of the on-disk file vs the repo
// template. checkServiceDone previously only ran `systemctl --user is-active`,
// so a HEALTHY box with a drifted unit was never rewritten — the drift
// persisted indefinitely (the gap that left rune on stale timeout config).
//
// unitFileMatchesRepo is the pure, systemd-free comparison seam: true iff the
// on-disk user unit exists AND is byte-identical to <dir>/ops/statbus-upgrade.service.
// checkServiceDone ANDs this with is-active (the is-active half needs real
// systemd, so it's exercised by the Hetzner harness, not here).

// writeUnitFixture lays out a temp repo `ops/statbus-upgrade.service` (the
// source of truth) and points $HOME at a temp dir. Returns (dir, userUnitPath).
func writeUnitFixture(t *testing.T, repoContent string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "ops"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "ops", "statbus-upgrade.service"), []byte(repoContent), 0o644); err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	userUnit := filepath.Join(home, ".config", "systemd", "user", "statbus-upgrade@.service")
	if err := os.MkdirAll(filepath.Dir(userUnit), 0o755); err != nil {
		t.Fatal(err)
	}
	return dir, userUnit
}

// TestUnitFileMatchesRepo_IdenticalIsMatch: on-disk unit byte-identical to the
// repo template → match (no reconcile needed).
func TestUnitFileMatchesRepo_IdenticalIsMatch(t *testing.T) {
	content := "[Unit]\nDescription=StatBus Upgrade Service\n[Service]\nWatchdogSec=120\nTimeoutStartSec=120\n"
	dir, userUnit := writeUnitFixture(t, content)
	if err := os.WriteFile(userUnit, []byte(content), 0o755); err != nil {
		t.Fatal(err)
	}
	if !unitFileMatchesRepo(dir) {
		t.Error("byte-identical on-disk unit must MATCH the repo template (no reconcile needed)")
	}
}

// TestUnitFileMatchesRepo_DriftIsMismatch is the load-bearing #4 guard: a
// drifted on-disk unit (rune's stale 90/infinity vs the repo's 120/120) must
// be detected as a MISMATCH so checkServiceDone reports not-done and the unit
// is rewritten + re-armed. Pre-#4 there was no such compare; this guard is the
// RED→GREEN proof for the byte-compare seam.
func TestUnitFileMatchesRepo_DriftIsMismatch(t *testing.T) {
	repo := "[Unit]\nDescription=StatBus Upgrade Service\n[Service]\nWatchdogSec=120\nTimeoutStartSec=120\n"
	// Rune's drifted shape: watchdog disabled, shorter start timeout.
	drifted := "[Unit]\nDescription=StatBus Upgrade Service\n[Service]\nWatchdogSec=infinity\nTimeoutStartSec=90\n"
	dir, userUnit := writeUnitFixture(t, repo)
	if err := os.WriteFile(userUnit, []byte(drifted), 0o755); err != nil {
		t.Fatal(err)
	}
	if unitFileMatchesRepo(dir) {
		t.Error("a drifted on-disk unit (90/infinity vs repo 120/120) must be a MISMATCH so the unit is reconciled + re-armed")
	}
}

// TestUnitFileMatchesRepo_MissingDestIsMismatch: no on-disk unit yet (fresh
// box) → mismatch, so install writes it.
func TestUnitFileMatchesRepo_MissingDestIsMismatch(t *testing.T) {
	dir, _ := writeUnitFixture(t, "[Unit]\nDescription=x\n")
	// userUnit dir exists but the file does not.
	if unitFileMatchesRepo(dir) {
		t.Error("missing on-disk unit must be a MISMATCH (fresh install must write it)")
	}
}

// TestRunInstallService_RestartsOnDriftToArmTimers is the #4 re-arm guard
// (plan de-risk #2): a rewritten unit is INERT until daemon-reload + restart —
// `enable --now` does not restart an already-running unit, so a drifted-but-
// running box would keep stale timers. This pins, at the source level (the
// systemctl calls shell out, so a behavioral test would need real systemd —
// covered by the Hetzner scenario), that runInstallService restarts the unit
// when it was drifted AND active, gated off postUpgradeFixup, AFTER
// daemon-reload. Matches the source-order-guard pattern of the other install
// guards (e.g. TestRunInstallService_GatesNowOnPostUpgradeFixup).
func TestRunInstallService_RestartsOnDriftToArmTimers(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install.go"))
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	body := string(src)
	start := strings.Index(body, "func runInstallService(")
	if start < 0 {
		t.Fatal("runInstallService not found in install.go")
	}
	rest := body[start:]
	end := regexp.MustCompile(`(?m)^}\n`).FindStringIndex(rest)
	if end == nil {
		t.Fatal("runInstallService closing brace not found")
	}
	fn := rest[:end[1]]

	driftIdx := strings.Index(fn, "unitWasDrifted")
	if driftIdx < 0 {
		t.Fatal("runInstallService must capture unitWasDrifted (unitFileMatchesRepo) BEFORE the copy " +
			"to know whether the on-disk unit is changing — needed to decide whether a re-arm restart is required.")
	}
	reloadIdx := strings.Index(fn, `"daemon-reload"`)
	if reloadIdx < 0 {
		t.Fatal("runInstallService missing daemon-reload — test is stale")
	}
	// The re-arm restart must be gated on drifted AND active AND not-inside-
	// active-upgrade, and must issue `systemctl --user restart`.
	guardIdx := strings.Index(fn, "unitWasDrifted && unitWasActive && !postUpgradeFixup")
	if guardIdx < 0 {
		t.Fatal("runInstallService missing the re-arm gate `unitWasDrifted && unitWasActive && !postUpgradeFixup`. " +
			"Without restarting a drifted-but-running unit, the rewritten WatchdogSec/TimeoutStartSec stay inert " +
			"(rune would keep 90/infinity). Restarting unconditionally would churn healthy units / kill an in-flight " +
			"upgrade (postUpgradeFixup), so the gate is load-bearing.")
	}
	restartIdx := strings.Index(fn[guardIdx:], `"restart", instance`)
	if restartIdx < 0 {
		t.Error("the re-arm gate must issue `systemctl --user restart <instance>` to arm the reconciled timers.")
	}
	// Ordering: the restart gate must come AFTER daemon-reload (a restart
	// before reload would re-arm the OLD config).
	if guardIdx < reloadIdx {
		t.Errorf("the re-arm restart (idx=%d) must come AFTER daemon-reload (idx=%d) — "+
			"restarting before reload would re-arm the stale config.", guardIdx, reloadIdx)
	}
}
