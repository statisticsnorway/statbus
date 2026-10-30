package cmd

// STATBUS-547: every commit's statbus-sb image must carry a binary that names
// THAT commit. The exempt-only shortcut (STATBUS-219) copies the parent's
// images for the services whose code did not change, but sb bakes its commit
// into the binary (-X cmd.commit) and the freshness guard compares it with the
// checkout. A copied sb names the parent: on a depth-1 installed box the
// parent is unknown, `git diff` exits 128, the binary is called stale, and a
// mutating command stops with exit 69.
//
// The split this pins: retag copies ONLY app, worker, db and proxy, while sb
// is built and its multi-arch manifest published on every push, including
// exempt-only pushes. These follow the package's STATBUS-224 rule: parse the
// workflow YAML and read the job conditions, never grep the file text — a
// comment explaining the exception must neither satisfy nor defeat this test.

import (
	"slices"
	"strings"
	"testing"
)

func TestImagesSbBuiltForEveryPush_STATBUS547(t *testing.T) {
	const path = ".github/workflows/images.yaml"
	doc := workflowDoc(t, path)
	rawJobs, ok := doc["jobs"].(map[string]any)
	if !ok || len(rawJobs) == 0 {
		t.Fatalf("%s has no jobs block", path)
	}
	jobs := make(map[string]map[string]any, len(rawJobs))
	for name, raw := range rawJobs {
		job, ok := raw.(map[string]any)
		if !ok {
			t.Fatalf("%s job %q is not a mapping", path, name)
		}
		jobs[name] = job
	}

	// (a) The retag path copies the four services whose code is identical to
	// the parent's. sb must not be among them: a copied sb names the parent.
	retag, ok := jobs["retag"]
	if !ok {
		t.Fatalf("%s has no retag job — the exempt-only shortcut lost its subject", path)
	}
	if got, want := jobMatrixServices(t, path, "retag", retag), []string{"app", "worker", "db", "proxy"}; !slices.Equal(got, want) {
		t.Errorf("retag copies %v, want exactly %v — sb must be built for its own commit, never retagged", got, want)
	}

	// (b) sb is built and its manifest published on every push (and therefore
	// on an exempt-only push, since nothing about the exempt decision may
	// gate them).
	builders := jobsBuildingService(t, path, jobs, "sb")
	if len(builders) == 0 {
		t.Fatal("no job builds sb from source — a commit would only ever get a copied sb")
	}
	for _, name := range builders {
		job := jobs[name]
		if cond := jobCondition(job); conditionMentionsExempt(cond) {
			t.Errorf("sb builder %q is gated on the exempt decision (%q) — sb must be built for its own commit on every push, including exempt-only pushes", name, cond)
		}
		if got, want := jobMatrixPlatforms(t, path, name, job), []string{"amd64", "arm64"}; !slices.Equal(got, want) {
			t.Errorf("sb builder %q builds platforms %v, want %v — the published sb must be multi-arch like every other service image", name, got, want)
		}
		if !jobPushesSbForThisCommit(t, path, name, job) {
			t.Errorf("sb builder %q does not push a per-arch sb tag for needs.describe.outputs.commit_short", name)
		}
	}

	publishers := jobsPublishingServiceManifest(t, path, jobs, "sb")
	if len(publishers) == 0 {
		t.Fatal("no job publishes the sb manifest — the per-arch sb images would never become statbus-sb:<commit>")
	}
	for _, name := range publishers {
		job := jobs[name]
		if cond := jobCondition(job); conditionMentionsExempt(cond) {
			t.Errorf("sb manifest publisher %q is gated on the exempt decision (%q) — sb must be published for its own commit on every push", name, cond)
		}
		if !needsAny(job, builders) {
			t.Errorf("sb manifest publisher %q does not depend on any sb builder %v — it cannot merge images that were never pushed", name, builders)
		}
	}
}

// jobMatrixServices returns the job's strategy.matrix.service names, accepting
// both plain strings and `{name: ...}` mappings (the build matrix carries a
// Dockerfile context alongside each name).
func jobMatrixServices(t *testing.T, path, jobName string, job map[string]any) []string {
	t.Helper()
	strategy, ok := job["strategy"].(map[string]any)
	if !ok {
		t.Fatalf("%s job %q has no strategy — it has no service matrix to read", path, jobName)
	}
	matrix, ok := strategy["matrix"].(map[string]any)
	if !ok {
		t.Fatalf("%s job %q has no matrix", path, jobName)
	}
	entries, ok := matrix["service"].([]any)
	if !ok || len(entries) == 0 {
		t.Fatalf("%s job %q has no matrix.service entries", path, jobName)
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		switch v := entry.(type) {
		case string:
			names = append(names, v)
		case map[string]any:
			name, _ := v["name"].(string)
			if name == "" {
				t.Fatalf("%s job %q has a matrix.service entry without a name: %v", path, jobName, v)
			}
			names = append(names, name)
		default:
			t.Fatalf("%s job %q has an unreadable matrix.service entry %T", path, jobName, entry)
		}
	}
	return names
}

func jobMatrixPlatforms(t *testing.T, path, jobName string, job map[string]any) []string {
	t.Helper()
	strategy, _ := job["strategy"].(map[string]any)
	matrix, _ := strategy["matrix"].(map[string]any)
	entries, _ := matrix["platform"].([]any)
	archs := make([]string, 0, len(entries))
	for _, entry := range entries {
		if v, ok := entry.(map[string]any); ok {
			if arch, _ := v["arch"].(string); arch != "" {
				archs = append(archs, arch)
			}
		}
	}
	if len(archs) == 0 {
		t.Fatalf("%s job %q has no matrix.platform arch entries", path, jobName)
	}
	return archs
}

// jobCondition is the job's own `if:` expression, or "" when it has none (a
// job without a condition runs on every push).
func jobCondition(job map[string]any) string {
	cond, _ := job["if"].(string)
	return cond
}

// conditionMentionsExempt reports whether a job condition routes on the
// exempt-only decision at all. Any such reference is a gate that could skip sb
// on an exempt-only push, which is exactly what STATBUS-547 forbids.
func conditionMentionsExempt(condition string) bool {
	return strings.Contains(condition, "exempt")
}

// jobsBuildingService returns the names of jobs whose service matrix builds the
// named service with docker/build-push-action.
func jobsBuildingService(t *testing.T, path string, jobs map[string]map[string]any, service string) []string {
	t.Helper()
	var names []string
	for name, job := range jobs {
		if !slices.Contains(jobMatrixServicesIfAny(job), service) {
			continue
		}
		for _, step := range jobStepMaps(t, path, name, job) {
			if uses, _ := step["uses"].(string); strings.HasPrefix(uses, "docker/build-push-action@") {
				names = append(names, name)
				break
			}
		}
	}
	slices.Sort(names)
	return names
}

// jobsPublishingServiceManifest returns the names of jobs whose service matrix
// publishes the named service's multi-arch manifest with imagetools create.
func jobsPublishingServiceManifest(t *testing.T, path string, jobs map[string]map[string]any, service string) []string {
	t.Helper()
	var names []string
	for name, job := range jobs {
		if !slices.Contains(jobMatrixServicesIfAny(job), service) {
			continue
		}
		for _, step := range jobStepMaps(t, path, name, job) {
			if script, _ := step["run"].(string); strings.Contains(script, "docker buildx imagetools create") {
				names = append(names, name)
				break
			}
		}
	}
	slices.Sort(names)
	return names
}

// jobMatrixServicesIfAny is the non-fatal service list used for scanning: jobs
// without a service matrix simply do not participate.
func jobMatrixServicesIfAny(job map[string]any) []string {
	strategy, _ := job["strategy"].(map[string]any)
	matrix, _ := strategy["matrix"].(map[string]any)
	entries, _ := matrix["service"].([]any)
	var names []string
	for _, entry := range entries {
		switch v := entry.(type) {
		case string:
			names = append(names, v)
		case map[string]any:
			if name, _ := v["name"].(string); name != "" {
				names = append(names, name)
			}
		}
	}
	return names
}

func jobStepMaps(t *testing.T, path, jobName string, job map[string]any) []map[string]any {
	t.Helper()
	rawSteps, ok := job["steps"].([]any)
	if !ok {
		t.Fatalf("%s job %q has no steps", path, jobName)
	}
	steps := make([]map[string]any, 0, len(rawSteps))
	for _, raw := range rawSteps {
		if step, ok := raw.(map[string]any); ok {
			steps = append(steps, step)
		}
	}
	if len(steps) == 0 {
		t.Fatalf("%s job %q parsed to zero steps", path, jobName)
	}
	return steps
}

// jobPushesSbForThisCommit checks the build step tags statbus-<service> by
// commit_short and per-platform arch, so the manifest step has both children.
func jobPushesSbForThisCommit(t *testing.T, path, jobName string, job map[string]any) bool {
	t.Helper()
	for _, step := range jobStepMaps(t, path, jobName, job) {
		uses, _ := step["uses"].(string)
		if !strings.HasPrefix(uses, "docker/build-push-action@") {
			continue
		}
		with, _ := step["with"].(map[string]any)
		tags, _ := with["tags"].(string)
		if strings.Contains(tags, "statbus-${{ matrix.service.name }}") &&
			strings.Contains(tags, "needs.describe.outputs.commit_short") &&
			strings.Contains(tags, "matrix.platform.arch") {
			return true
		}
	}
	return false
}

func needsAny(job map[string]any, candidates []string) bool {
	switch needs := job["needs"].(type) {
	case string:
		return slices.Contains(candidates, needs)
	case []any:
		for _, need := range needs {
			if name, ok := need.(string); ok && slices.Contains(candidates, name) {
				return true
			}
		}
	}
	return false
}
