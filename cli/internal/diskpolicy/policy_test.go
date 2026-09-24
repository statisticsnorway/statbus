package diskpolicy

import (
	"context"
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

func TestDockerRootUnavailableFailsClosed(t *testing.T) {
	bin := t.TempDir()
	docker := filepath.Join(bin, "docker")
	if err := os.WriteFile(docker, []byte("#!/bin/sh\nprintf '/nonexistent/docker-storage\\n'\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	_, err := DockerRoot(context.Background(), t.TempDir())
	if err == nil || err.Error() != "cannot check disk space at Docker storage: Docker root unavailable" {
		t.Fatalf("unavailable root: %v", err)
	}
}

func TestDiskRefusalRetainsOperatorRerun(t *testing.T) {
	command := "curl -fsSL https://statbus.org/install.sh | env STATBUS_ENV_CONFIG=/home/operator/answers bash -s -- --channel prerelease --non-interactive"
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", command)
	message, ok := Evaluate(Measurement{Path: "/docker", FreeGB: 1})
	if ok || !strings.Contains(message, command) {
		t.Fatalf("refusal: %q allowed=%t", message, ok)
	}
}
