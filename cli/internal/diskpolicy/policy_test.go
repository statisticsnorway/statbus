package diskpolicy

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSharedThresholdAcrossCallers(t *testing.T) {
	for _, caller := range []string{"first install", "rerun", "upgrade", "fixup"} {
		for _, tc := range []struct {
			free    uint64
			allowed bool
			text    string
		}{{12, false, "at least 20 GB"}, {20, true, "40 GB is recommended"}, {39, true, "40 GB is recommended"}, {40, true, "recommendation is met"}} {
			message, ok := Evaluate(Measurement{Path: "/var/lib/docker", FreeGB: tc.free})
			if ok != tc.allowed || !strings.Contains(message, tc.text) || !strings.Contains(message, "/var/lib/docker") {
				t.Errorf("%s %d: %s %t", caller, tc.free, message, ok)
			}
		}
	}
}

func TestSavedDiskPolicySurvivesNewProcess(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte(PolicyConfig), 0600); err != nil {
		t.Fatal(err)
	}
	policy, err := Load(dir)
	if err != nil || policy.MinimumGB != 20 || policy.RecommendedGB != 40 {
		t.Fatalf("reload: %+v %v", policy, err)
	}
	for _, free := range []uint64{19, 20, 39, 40} {
		_, allowed := policy.Evaluate(Measurement{Path: "/var/lib/docker", FreeGB: free})
		if allowed != (free >= 20) {
			t.Fatalf("%d GB: allowed=%t", free, allowed)
		}
	}
}
