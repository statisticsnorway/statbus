package cmd

import (
	"os"
	"strings"
	"testing"
)

// TestTrustGitHubUserRunsBeforeDispatch pins STATBUS-027: the --trust-github-user
// pre-flight MUST run before dispatchInstallState in runInstall.
//
// Why the order is load-bearing: dispatchInstallState returns early (handled=true)
// for StateScheduledUpgrade (hands off to executeUpgrade) and the crashed-upgrade
// path also returns early — so a trust block placed AFTER dispatch never runs on a
// box with a pending/wedged upgrade, making `./sb install --trust-github-user X` a
// SILENT no-op exactly when the upgrade pipeline needs that signer to verify the
// target commit (the operator then hits "no trusted signers configured" with no
// clue the flag was dropped).
//
// The fix landed in c891fbaef (2026-06-18, "install: honor --trust-github-user
// before dispatch"); this is the missing pin (AC#3) so a future reorder cannot
// silently regress it. Source-order structural test — the established cli/cmd
// install pattern (cf. TestNoSilentNotesInInstall) — because a behavioral test
// would need a live DB + install state + a GitHub API call (trustSignerNonInteractive).
func TestTrustGitHubUserRunsBeforeDispatch(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install.go"))
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	body := string(src)

	// The --trust-github-user processing (unique in install.go — the dispatch
	// definition lives in install_upgrade.go).
	trustIdx := strings.Index(body, "trustSignerNonInteractive(trustGitHubUser")
	if trustIdx < 0 {
		t.Fatal("could not find the --trust-github-user processing (trustSignerNonInteractive) in install.go — test is stale")
	}
	dispatchIdx := strings.Index(body, "dispatchInstallState(installDir, state, detail)")
	if dispatchIdx < 0 {
		t.Fatal("could not find the dispatchInstallState call in runInstall — test is stale")
	}
	if trustIdx > dispatchIdx {
		t.Errorf("STATBUS-027 regressed: the --trust-github-user pre-flight (offset %d) must run BEFORE dispatchInstallState (offset %d) — otherwise `./sb install --trust-github-user X` is a silent no-op on a scheduled/crashed upgrade (dispatch returns early, handing off to executeUpgrade before the signer is trusted)",
			trustIdx, dispatchIdx)
	}
}
