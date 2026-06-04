package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// TestLivenessSidecarPresent pins the detection half of the liveness-sidecar
// retirement step (runRetireLivenessSidecar): the install ladder reconciles
// toward "both observer template-unit files absent". A box installed before the
// single-unit collapse still has them; a fresh/retired box does not.
func TestLivenessSidecarPresent(t *testing.T) {
	dir := t.TempDir()

	// Empty dir → retired (nothing to do).
	if livenessSidecarPresent(dir) {
		t.Error("empty systemd user dir: no sidecar units present, want false")
	}

	// Either template file present → not retired (the step must run).
	for _, name := range livenessSidecarUnitNames {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte("[Unit]\n"), 0o644); err != nil {
			t.Fatalf("write %s: %v", p, err)
		}
		if !livenessSidecarPresent(dir) {
			t.Errorf("%s present: want true", name)
		}
		if err := os.Remove(p); err != nil {
			t.Fatalf("remove %s: %v", p, err)
		}
	}

	// Removed again → retired.
	if livenessSidecarPresent(dir) {
		t.Error("after removing both units: want false (retired)")
	}
}
