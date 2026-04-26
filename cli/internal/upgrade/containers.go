package upgrade

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// dockerPsEntry mirrors the fields of `docker compose ps --format json` we
// care about. The JSON keys are upper-camel as Compose v2 emits them.
type dockerPsEntry struct {
	Service string `json:"Service"`
	State   string `json:"State"`
	Image   string `json:"Image"`
}

// parseDockerComposePsJSON tolerates both forms of `docker compose ps
// --format json`:
//   - Compose v2 NDJSON: one entry per line.
//   - Older Compose: a single JSON array.
// Empty/whitespace input → empty slice, no error (matches `ps` on empty
// project).
func parseDockerComposePsJSON(out []byte) ([]dockerPsEntry, error) {
	trimmed := bytes.TrimSpace(out)
	if len(trimmed) == 0 {
		return nil, nil
	}
	if trimmed[0] == '[' {
		var arr []dockerPsEntry
		if err := json.Unmarshal(trimmed, &arr); err != nil {
			return nil, fmt.Errorf("parse docker compose ps json array: %w", err)
		}
		return arr, nil
	}
	// NDJSON path. Iterate line-by-line — robust against trailing whitespace
	// and embedded blank lines.
	var entries []dockerPsEntry
	for _, line := range bytes.Split(trimmed, []byte("\n")) {
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		var entry dockerPsEntry
		if err := json.Unmarshal(line, &entry); err != nil {
			return nil, fmt.Errorf("parse docker compose ps json line %q: %w", string(line), err)
		}
		entries = append(entries, entry)
	}
	return entries, nil
}

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
func evaluateContainersAtFlagTarget(statuses []dockerPsEntry, commitSHA, displayName string) (ok bool, mismatched []string) {
	versionTracked := map[string]bool{"db": true, "app": true, "worker": true, "proxy": true}
	expected := []string{"db", "app", "worker", "proxy", "rest"}

	seen := map[string]dockerPsEntry{}
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
			mismatched = append(mismatched, fmt.Sprintf("%s: missing", svc))
			continue
		}
		if s.State != "running" {
			mismatched = append(mismatched, fmt.Sprintf("%s: state=%q (want running)", svc, s.State))
			continue
		}
		if !versionTracked[svc] {
			continue // rest: state-only
		}
		tag := extractImageTag(s.Image)
		if tag != sha8 && tag != displayName {
			mismatched = append(mismatched, fmt.Sprintf(
				"%s: tag=%q (want %q or %q) image=%q",
				svc, tag, sha8, displayName, s.Image))
		}
	}
	return len(mismatched) == 0, mismatched
}

// containersAtFlagTarget probes `docker compose ps` and reports whether
// the production container set runs at the flag's target. Used by
// resumePostSwap as a self-heal canary: when the flag is stale but the
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
	statuses, perr := parseDockerComposePsJSON(out)
	if perr != nil {
		return false, []string{fmt.Sprintf("parse docker compose ps json failed: %v", perr)}
	}
	return evaluateContainersAtFlagTarget(statuses, flag.CommitSHA, flag.Label())
}
