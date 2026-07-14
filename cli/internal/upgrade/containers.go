package upgrade

import (
	"context"
	"fmt"
	"os/exec"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

// extractImageTag returns the tag suffix from an image reference, or "" if
// the reference has no tag. Examples:
//
//	"ghcr.io/statisticsnorway/statbus-app:9ac0666c" → "9ac0666c"
//	"postgres:18-alpine"                            → "18-alpine"
//	"postgrest/postgrest:v12.2.8"                   → "v12.2.8"
//	"postgres"                                      → ""
//	"registry.example.com:5000/myapp"               → "" (port, not tag)
func extractImageTag(image string) string {
	idx := strings.LastIndex(image, ":")
	if idx < 0 {
		return ""
	}
	tag := image[idx+1:]
	// "host:port/repo" — tag would contain a slash; treat as no tag.
	if strings.Contains(tag, "/") {
		return ""
	}
	return tag
}

// containerCheckResult is the per-service outcome of evaluating a probe.
// Carries the detail used in the log line at the call site.
type containerCheckResult struct {
	Service string
	Image   string
	State   string
	Reason  string // populated only on mismatch; empty on match
}

// versionTrackedServices is the list of services whose container image
// tag the upgrade canary (evaluateContainersAtFlagTarget) requires to
// match the post-upgrade target SHA. Every service in this list MUST
// also be restarted by the upgrade pipeline (step 9's docker compose up
// -d --no-build db, OR step 11's analogous call) — otherwise the canary
// waits forever for a container whose tag the upgrade never touches.
// The TestVersionTrackedAlignedWithUpgradePipeline invariant in
// containers_invariants_test.go asserts this alignment statically.
//
// Cross-reference: step11RestartServices in service.go (the step-11
// docker compose up arg list) MUST contain every entry in this slice
// except "db" (which is restarted at step 9).
//
// "rest" is intentionally absent — postgrest is upstream-pinned to a
// fixed tag (postgrest:v12.2.8 in docker-compose.rest.yml), so its
// image tag never matches CommitSHA[:8] / DisplayName. The expected
// list below INCLUDES "rest" for the state=="running" check; only the
// tag check is suppressed.
var versionTrackedServices = []string{"db", "app", "worker", "proxy"}

// evaluateContainersAtFlagTarget is the pure decision: given the set of
// container statuses returned by docker compose ps and the flag's target
// commit SHA + display name, determine whether the production set is fully
// at the target.
//
// Five services checked:
//   - db, app, worker, proxy: State == "running" AND image tag matches
//     either CommitSHA[:8] (rc.65+ scheme: COMMIT_SHORT = git short SHA)
//     OR DisplayName (rc.55-era scheme: COMMIT_SHORT = release tag —
//     observed on rune, ma, tcc, ug). Both schemes accepted because
//     deployments span eras.
//   - rest: postgrest is upstream-pinned (postgrest:v12.2.8 in the
//     compose file), so only the State == "running" check applies.
//
// Returns (true, nil) when every expected service is present, running,
// and (where applicable) at the right tag. On any deviation, returns
// (false, mismatched) with a human-readable reason per service.
func evaluateContainersAtFlagTarget(statuses []compose.PsEntry, commitSHA, displayName string) (ok bool, mismatched []string) {
	versionTracked := make(map[string]bool, len(versionTrackedServices))
	for _, s := range versionTrackedServices {
		versionTracked[s] = true
	}
	expected := []string{"db", "app", "worker", "proxy", "rest"}

	seen := map[string]compose.PsEntry{}
	for _, s := range statuses {
		seen[s.Service] = s
	}

	sha8 := commitSHA
	if len(sha8) > 8 {
		sha8 = sha8[:8]
	}

	for _, svc := range expected {
		s, found := seen[svc]
		if !found {
			mismatched = append(mismatched, fmt.Sprintf("%s: old version not running, new version not started yet", svc))
			continue
		}
		if s.State != "running" {
			mismatched = append(mismatched, fmt.Sprintf("%s: old version not running, new version not started yet", svc))
			continue
		}
		if !versionTracked[svc] {
			continue // rest: state-only
		}
		tag := extractImageTag(s.Image)
		if tag != sha8 && tag != displayName {
			mismatched = append(mismatched, fmt.Sprintf("%s: old version running, new version not started yet", svc))
		}
	}
	return len(mismatched) == 0, mismatched
}

// containersAtFlagTarget probes `docker compose ps` and reports whether
// the production container set runs at the flag's target. Used by
// resumeNewSb as a self-heal canary: when the flag is stale but the
// world has actually converged on the target, mark the row completed
// instead of rolling back a successful upgrade.
//
// Failure modes are absorbed into the (false, [...]) result — the caller
// falls through to the existing rollback path when this returns false.
func (d *Service) containersAtFlagTarget(ctx context.Context, flag UpgradeFlag) (bool, []string) {
	cmd := exec.CommandContext(ctx, "docker", "compose", "ps", "--format", "json")
	cmd.Dir = d.projDir
	prepareCmd(cmd)
	out, err := cmd.Output()
	if err != nil {
		return false, []string{fmt.Sprintf("docker compose ps failed: %v", err)}
	}
	statuses, perr := compose.ParsePsJSON(out)
	if perr != nil {
		return false, []string{fmt.Sprintf("parse docker compose ps json failed: %v", perr)}
	}
	return evaluateContainersAtFlagTarget(statuses, flag.CommitSHA, flag.Label())
}
