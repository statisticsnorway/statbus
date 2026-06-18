package upgrade

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// TestMaintenancePathAlignment pins the STATBUS-089 invariant: the upgrade
// service's maintenance flag-file path must agree across all THREE sources —
// the WRITER (setMaintenance, this package), the Caddy templates' @maintenance
// MATCHER, and the compose bind MOUNT. A split silently disables maintenance
// mode (it was dead on every standalone+private box from 2026-04-14 until this
// fix, because the writer wrote ~/maintenance — outside the mounted dir). This
// guard ties the Go writer constants to the rendered templates so a re-split
// can't merge unnoticed. Mirrors TestVersionTrackedAlignedWithUpgradePipeline.
func TestMaintenancePathAlignment(t *testing.T) {
	const repoRoot = "../../.." // cli/internal/upgrade → repo root

	containerPath := maintenanceFlagContainerPath() // /statbus-maintenance/active

	// 1. Both Caddy templates' @maintenance matcher must check EXACTLY the
	//    in-container path the writer targets through the mount.
	for _, rel := range []string{
		"caddy/templates/standalone.caddyfile.tmpl",
		"caddy/templates/private.caddyfile.tmpl",
	} {
		body := readRepoFile(t, repoRoot, rel)
		want := "file " + containerPath
		if !strings.Contains(body, want) {
			t.Errorf("%s: @maintenance matcher must contain %q (writer↔template split — STATBUS-089); the writer targets host %s",
				rel, want, maintenanceFlagHostPath())
		}
	}

	// 2. The compose bind mount must expose the host dir at the mount target,
	//    so the host file the writer creates appears at containerPath in-container.
	compose := readRepoFile(t, repoRoot, "caddy/docker-compose.yml")
	wantMount := maintenanceFlagDir + ":" + maintenanceMountTarget // statbus-maintenance:/statbus-maintenance
	if !strings.Contains(compose, wantMount) {
		t.Errorf("caddy/docker-compose.yml: must bind-mount %q (mount↔writer split — STATBUS-089)", wantMount)
	}

	// 3. The host write path must end in <dir>/<name> — the mount source side.
	if got, suffix := maintenanceFlagHostPath(), filepath.Join(maintenanceFlagDir, maintenanceFlagName); !strings.HasSuffix(got, suffix) {
		t.Errorf("host write path %q must end in %q", got, suffix)
	}

	// 4. Helper self-consistency: container path == mount target + flag name.
	if want := maintenanceMountTarget + "/" + maintenanceFlagName; containerPath != want {
		t.Errorf("maintenanceFlagContainerPath() = %q, want %q", containerPath, want)
	}
}

// composeMountRe extracts the container-side of each docker-compose volume
// (the absolute path after a ':' — e.g. ":/statbus-tmp" from "../tmp:/statbus-tmp:ro").
// Port lines (":80/tcp") have no '/'-prefixed field, so they never match.
var composeMountRe = regexp.MustCompile(`:(/[^:\s]+)`)

// caddyAbsServePathRe extracts the ABSOLUTE filesystem path a Caddy directive
// serves FROM: `root * <abs>` and the `file <abs>` matcher. try_files is
// EXCLUDED on purpose — its args are resolved RELATIVE to the active `root`
// (e.g. `try_files /maintenance.html` under `root * /maintenance-page`), so it
// is not a standalone mount path; an absolute /home/ in try_files is still
// caught by the /home/ ban below.
var caddyAbsServePathRe = regexp.MustCompile(`(?:root\s+\*|file)\s+(/\S+)`)

// TestCaddyTemplatePathsAreMounted enforces the whole STATBUS-089 bug CLASS (the
// broadened guard): a Caddy template may only serve paths the proxy container
// actually mounts. (1) NO template may reference /home/ — the host home is never
// mounted into the proxy; the three /home/ refs (progress-log root, maintenance
// flag, 503 HTML root) silently 404'd. (2) every absolute root*/file path must
// live under a declared caddy/docker-compose.yml mount target. Scoped to the
// per-instance proxy modes (standalone/private/development) that run
// caddy/docker-compose.yml; public* is the host-level multi-tenant proxy with a
// different compose/mount model.
func TestCaddyTemplatePathsAreMounted(t *testing.T) {
	const repoRoot = "../../.."

	compose := readRepoFile(t, repoRoot, "caddy/docker-compose.yml")
	mounts := map[string]bool{}
	for _, m := range composeMountRe.FindAllStringSubmatch(compose, -1) {
		mounts[m[1]] = true
	}
	if len(mounts) == 0 {
		t.Fatal("parsed no mount targets from caddy/docker-compose.yml")
	}

	for _, mode := range []string{"standalone", "private", "development"} {
		rel := "caddy/templates/" + mode + ".caddyfile.tmpl"
		body := readRepoFile(t, repoRoot, rel)
		for i, raw := range strings.Split(body, "\n") {
			line := strings.TrimSpace(raw)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if strings.Contains(line, "/home/") {
				t.Errorf("%s:%d references /home/ — the proxy never mounts the host home (STATBUS-089 bug class): %q", rel, i+1, line)
			}
			m := caddyAbsServePathRe.FindStringSubmatch(line)
			if m == nil {
				continue
			}
			p := m[1]
			mounted := false
			for mt := range mounts {
				if p == mt || strings.HasPrefix(p, mt+"/") {
					mounted = true
					break
				}
			}
			if !mounted {
				t.Errorf("%s:%d serves %q — not under any caddy/docker-compose.yml mount %v; unmounted path is dead in-container",
					rel, i+1, p, sortedKeys(mounts))
			}
		}
	}
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func readRepoFile(t *testing.T, root, rel string) string {
	t.Helper()
	p := filepath.Join(root, rel)
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("read %s: %v", p, err)
	}
	return string(b)
}
