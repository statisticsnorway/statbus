package cmd

import (
	"path/filepath"
	"runtime"
	"testing"
)

// The REAL list (ops/release/upgrade-sensitive-paths.txt), not a fixture.
//
// Every artefact the harness executes or ships on a VM must be reachable
// by the list, otherwise an RC that changes only that artefact inherits a
// prior RC's proof it did not earn, and the smokes and the stable gate both
// skip it. install.sh is the one that sits at the repo root where no
// directory prefix reaches it; this test names each such artefact so the
// list cannot silently lose it again.
func TestUpgradeSensitivePathsListReachesEveryExecutedArtefact(t *testing.T) {
	_, here, _, _ := runtime.Caller(0)
	projDir := filepath.Clean(filepath.Join(filepath.Dir(here), "..", ".."))

	paths, err := loadUpgradeSensitivePaths(projDir)
	if err != nil {
		t.Fatalf("loading the real list: %v", err)
	}

	executed := []string{
		"install.sh",                         // operator entry point, run on every harness VM
		"cli/cmd/install.go",                 // ./sb install
		"cli/internal/upgrade/service.go",    // the upgrade service
		"docker-compose.yml",                 // what the box brings up
		"caddy/templates/x.caddyfile.tmpl",   // rendered on the box
		"migrations/20260101000000_x.up.sql", // applied on the box
		"postgres/Dockerfile",                // shipped image
		"ops/release/upgrade-sensitive-paths.txt",
		"test/install-recovery/scenarios/0-happy-install.sh",
		".github/workflows/upgrade-arc-harness.yaml",
		".github/workflows/images.yaml",
	}
	for _, file := range executed {
		if !fileMatchesSensitivePaths(file, paths) {
			t.Errorf("%s is executed or shipped on the box but NO entry in ops/release/upgrade-sensitive-paths.txt reaches it — an RC changing only this file would inherit proof it did not earn", file)
		}
	}

	notExecuted := []string{
		"app/src/app/page.tsx", // product; proven by the dev canary, not the fleet
		"doc/CLOUD.md",
		"README.md",
	}
	for _, file := range notExecuted {
		if fileMatchesSensitivePaths(file, paths) {
			t.Errorf("%s matched the sensitivity list; product-only RCs would then always pay for the fleet", file)
		}
	}
}
