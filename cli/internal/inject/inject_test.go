package inject

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// withEnv sets env vars for the duration of a test, restoring prior
// values on cleanup. Centralized so each test reads the same way.
func withEnv(t *testing.T, kv map[string]string) {
	t.Helper()
	prior := make(map[string]*string, len(kv))
	for k, v := range kv {
		if existing, ok := os.LookupEnv(k); ok {
			s := existing
			prior[k] = &s
		} else {
			prior[k] = nil
		}
		if v == "" {
			os.Unsetenv(k)
		} else {
			os.Setenv(k, v)
		}
	}
	t.Cleanup(func() {
		for k, p := range prior {
			if p == nil {
				os.Unsetenv(k)
			} else {
				os.Setenv(k, *p)
			}
		}
	})
}

// TestValidate_AllRows walks the locked truth table. Each row is a
// combination of (active class, stall file) and the expected verdict.
// A regression in any cell catches harness misconfiguration regressing
// into silent "pass".
func TestValidate_AllRows(t *testing.T) {
	const killClass = "killed-by-system-during-preswap-backup"
	const stallClass = "concurrent-install-attempted-during-migrate-up"
	const externalClass = "install-flag-released-without-clean-handoff-detected-as-stale"

	cases := []struct {
		name      string
		active    string
		stallFile string
		wantOK    bool
		wantPart  string // substring required in the error if !wantOK
	}{
		{"production-unset-unset", "", "", true, ""},
		{"file-without-class", "", "/tmp/release", false, "release file requires an active stall class"},
		{"unknown-class", "ate-my-homework", "", false, "not a known injection class"},
		{"kill-class-no-file", killClass, "", true, ""},
		{"kill-class-with-file", killClass, "/tmp/release", false, "release file is only meaningful for stall classes"},
		{"stall-class-no-file", stallClass, "", false, "stall requires a release file"},
		{"stall-class-with-file", stallClass, "/tmp/release", true, ""},
		{"external-class-no-file", externalClass, "", true, ""},
		{"external-class-with-file", externalClass, "/tmp/release", false, "release file is only meaningful for stall classes"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			withEnv(t, map[string]string{
				EnvActiveAt:         tc.active,
				EnvStallReleaseFile: tc.stallFile,
			})
			err := Validate()
			if tc.wantOK {
				if err != nil {
					t.Errorf("Validate() = %v; want nil", err)
				}
				return
			}
			if err == nil {
				t.Fatalf("Validate() = nil; want error containing %q", tc.wantPart)
			}
			if !strings.Contains(err.Error(), tc.wantPart) {
				t.Errorf("Validate() error %q does not contain %q", err.Error(), tc.wantPart)
			}
		})
	}
}

// TestValidate_UnknownClassListsValidOnes is a usability guard: when an
// operator typos a class name, the diagnostic must list valid names so
// they can self-correct without grepping the source.
func TestValidate_UnknownClassListsValidOnes(t *testing.T) {
	withEnv(t, map[string]string{
		EnvActiveAt:         "killed-by-system-during-preswap-bakcup", // typo
		EnvStallReleaseFile: "",
	})
	err := Validate()
	if err == nil {
		t.Fatal("Validate() = nil; want error")
	}
	if !strings.Contains(err.Error(), "killed-by-system-during-preswap-backup") {
		t.Errorf("diagnostic missing canonical class name; got: %v", err)
	}
}

// TestKillHere_NoOpInProduction confirms the primitive does NOT exit
// when env is unset. (We can't test the os.Exit path directly without a
// subprocess; if KillHere fired here the test process would die and the
// suite would report it.)
func TestKillHere_NoOpInProduction(t *testing.T) {
	withEnv(t, map[string]string{EnvActiveAt: ""})
	KillHere("killed-by-system-during-preswap-backup")
}

// TestKillHere_NoOpUnmatchedName confirms a primitive at site A does not
// fire when class B is active.
func TestKillHere_NoOpUnmatchedName(t *testing.T) {
	withEnv(t, map[string]string{
		EnvActiveAt: "killed-by-system-during-preswap-backup",
	})
	KillHere("killed-by-system-during-binary-swap")
}

// TestErrorHere_NilWhenUnset confirms ErrorHere returns nil on the
// production path.
func TestErrorHere_NilWhenUnset(t *testing.T) {
	withEnv(t, map[string]string{EnvActiveAt: ""})
	if err := ErrorHere("any"); err != nil {
		t.Errorf("ErrorHere() = %v; want nil", err)
	}
}

// TestErrorHere_FiresWhenActive confirms ErrorHere returns the injected
// error when its class is active. (We register a fresh class for this
// test via the unexported map; for the production registry we don't have
// an Error-kind class yet.)
//
// This test mutates the package registry temporarily. Restoring it in
// Cleanup keeps the package state pristine for parallel test packages.
func TestErrorHere_FiresWhenActive(t *testing.T) {
	const name = "test-only-error-class"
	classes[name] = KindError
	t.Cleanup(func() { delete(classes, name) })
	withEnv(t, map[string]string{EnvActiveAt: name})

	err := ErrorHere(name)
	if err == nil {
		t.Fatal("ErrorHere() = nil; want error")
	}
	if !strings.Contains(err.Error(), name) {
		t.Errorf("ErrorHere() error %q should name the class", err.Error())
	}
}

// TestStallHere_NoOpWhenUnset confirms StallHere returns immediately on
// the production path.
func TestStallHere_NoOpWhenUnset(t *testing.T) {
	withEnv(t, map[string]string{EnvActiveAt: ""})
	StallHere("concurrent-install-attempted-during-migrate-up")
}

// TestStallHere_ReleasesWhenFileRemoved confirms the stall primitive
// blocks while the release file exists and returns once it is deleted.
// Drives a real timing: the goroutine deletes after 50ms; the stall
// should observe the deletion within one poll interval (100ms).
func TestStallHere_ReleasesWhenFileRemoved(t *testing.T) {
	dir := t.TempDir()
	releaseFile := filepath.Join(dir, "release")
	if err := os.WriteFile(releaseFile, []byte("hold"), 0o644); err != nil {
		t.Fatalf("create release file: %v", err)
	}

	withEnv(t, map[string]string{
		EnvActiveAt:         "concurrent-install-attempted-during-migrate-up",
		EnvStallReleaseFile: releaseFile,
	})

	var wg sync.WaitGroup
	wg.Add(1)
	start := time.Now()
	go func() {
		defer wg.Done()
		StallHere("concurrent-install-attempted-during-migrate-up")
	}()

	// Wait briefly to be sure StallHere is actually stalling.
	time.Sleep(50 * time.Millisecond)
	if err := os.Remove(releaseFile); err != nil {
		t.Fatalf("remove release file: %v", err)
	}

	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
		elapsed := time.Since(start)
		if elapsed > 500*time.Millisecond {
			t.Errorf("StallHere returned after %v; expected ~150ms", elapsed)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("StallHere did not return within 2s after release file removed")
	}
}

// TestStallHere_NoOpUnmatchedName confirms a stall primitive at site A
// does not block when class B is active.
func TestStallHere_NoOpUnmatchedName(t *testing.T) {
	withEnv(t, map[string]string{
		EnvActiveAt:         "killed-by-system-during-preswap-backup",
		EnvStallReleaseFile: "/nonexistent/should-not-be-checked",
	})

	done := make(chan struct{})
	go func() {
		StallHere("concurrent-install-attempted-during-migrate-up")
		close(done)
	}()

	select {
	case <-done:
		// expected — primitive returned immediately
	case <-time.After(1 * time.Second):
		t.Fatal("StallHere blocked when class did not match — should be no-op")
	}
}

// TestKindOf covers the basic registry lookup contract.
func TestKindOf(t *testing.T) {
	if k, ok := KindOf("killed-by-system-during-preswap-backup"); !ok || k != KindKill {
		t.Errorf("KindOf(preswap-backup kill class) = (%v, %v); want (KindKill, true)", k, ok)
	}
	if k, ok := KindOf("migrate-subprocess-killed-after-commit-before-recorded"); !ok || k != KindStall {
		t.Errorf("KindOf(subprocess-killed stall class) = (%v, %v); want (KindStall, true)", k, ok)
	}
	if k, ok := KindOf("concurrent-install-attempted-during-migrate-up"); !ok || k != KindStall {
		t.Errorf("KindOf(concurrent stall class) = (%v, %v); want (KindStall, true)", k, ok)
	}
	if _, ok := KindOf("ate-my-homework"); ok {
		t.Errorf("KindOf(unknown) = (_, true); want false")
	}
}

// TestRegistry_AllClassesSeeded is a structural guard: if the inventory
// in the dispatch is incomplete, this test should be the first place an
// operator sees the gap. Add classes here as they are registered in
// classes; the failure message names what's missing.
func TestRegistry_AllClassesSeeded(t *testing.T) {
	required := map[string]Kind{
		// Layer 2 kill classes — placeholders for sites that land as
		// scenarios surface them. The canonical "after-commit-before-
		// recorded" case is modeled as two stall classes below
		// (real-SIGKILL via harness, observably different from
		// in-process os.Exit).
		"killed-by-system-during-preswap-backup":                 KindKill,
		"killed-by-system-during-preswap-checkout":               KindKill,
		"killed-by-system-during-binary-swap":                    KindKill,
		"killed-by-system-during-individual-migration-execution": KindKill,
		"killed-by-system-between-migrations":                    KindKill,
		"killed-by-system-during-container-restart":              KindKill,
		"killed-by-system-during-builtin-rollback":               KindKill,
		// Canonical Layer 2 case — harness sends real SIGKILL.
		"migrate-subprocess-killed-after-commit-before-recorded":     KindStall,
		"upgrade-service-parent-killed-after-commit-before-recorded": KindStall,
		// Layer 1 systemd-timeout cases (call sites land with scenarios).
		"service-startup-slower-than-systemd-unit-timeout": KindStall,
		"migration-slower-than-systemd-unit-timeout":       KindStall,
		// Concurrent-install detection.
		"concurrent-install-attempted-during-migrate-up": KindStall,
		// Forensics-surfaced classes (call sites + scenarios land later).
		"migration-deadlocks-with-running-worker-holding-table-lock":          KindStall,
		"install-flag-released-without-clean-handoff-detected-as-stale":       KindExternal,
		"service-watchdog-timeout-during-db-reconnect-after-container-restart": KindStall,
		"advisory-lock-attempted-before-db-ready-after-container-restart":     KindExternal,
		"seed-restore-runs-on-populated-database-destroying-data":             KindStall,
	}
	for name, want := range required {
		got, ok := classes[name]
		if !ok {
			t.Errorf("class %q missing from registry", name)
			continue
		}
		if got != want {
			t.Errorf("class %q registered as %v; want %v", name, got, want)
		}
	}
}

// errIsNotExist confirms our reliance on os.ErrNotExist in StallHere is
// stable across the filesystems we run on. Smoke test only.
func TestErrIsNotExist(t *testing.T) {
	_, err := os.Stat("/nonexistent/sentinel/path/should/not/exist")
	if !errors.Is(err, os.ErrNotExist) {
		t.Errorf("Stat on bogus path: errors.Is(%v, os.ErrNotExist) = false; want true", err)
	}
}
