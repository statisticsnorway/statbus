package upgrade

import (
	"bytes"
	"errors"
	"log"
	"os"
	"strings"
	"testing"
)

// Tests for STATBUS-187 AC#3's uniform stale-flag-class treatment
// (warnOnStaleFlagRemoveFailure): os.IsNotExist is silent success; any
// other unlink error gets exactly one loud line naming the path, the raw
// error, and the caller-supplied consequence. Shared by removeUpgradeFlag,
// ReleaseInstallFlag, resumeNewSb's post-swap self-heal completion-flag
// remove, and cleanStaleMaintenance.

func captureLogOutput(t *testing.T, fn func()) string {
	t.Helper()
	var buf bytes.Buffer
	log.SetOutput(&buf)
	defer log.SetOutput(os.Stderr)
	fn()
	return buf.String()
}

func TestWarnOnStaleFlagRemoveFailure_NilErrorSilent(t *testing.T) {
	got := captureLogOutput(t, func() {
		warnOnStaleFlagRemoveFailure("/tmp/whatever", nil, "some consequence")
	})
	if got != "" {
		t.Errorf("nil error must be silent; got log output: %q", got)
	}
}

func TestWarnOnStaleFlagRemoveFailure_ENOENTSilent(t *testing.T) {
	dir := t.TempDir()
	_, statErr := os.Stat(dir + "/does-not-exist")
	if !os.IsNotExist(statErr) {
		t.Fatalf("test fixture broken: expected an IsNotExist error, got %v", statErr)
	}
	got := captureLogOutput(t, func() {
		warnOnStaleFlagRemoveFailure("/tmp/whatever", statErr, "some consequence")
	})
	if got != "" {
		t.Errorf("os.IsNotExist error must be silent (double-removal races must not cry wolf); got log output: %q", got)
	}
}

func TestWarnOnStaleFlagRemoveFailure_OtherErrorWarnsLoud(t *testing.T) {
	otherErr := errors.New("permission denied")
	got := captureLogOutput(t, func() {
		warnOnStaleFlagRemoveFailure("/tmp/some-flag", otherErr, "the specific consequence text")
	})
	for _, want := range []string{"/tmp/some-flag", "permission denied", "the specific consequence text"} {
		if !strings.Contains(got, want) {
			t.Errorf("warning log missing %q; got: %q", want, got)
		}
	}
}
