package upgrade

import (
	"os/exec"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// newRepoWithRefspecs builds a temp git repo whose remote.origin.fetch is
// exactly the given lines — the states real boxes were found in.
func newRepoWithRefspecs(t *testing.T, specs ...string) string {
	t.Helper()
	dir := t.TempDir()

	run := func(args ...string) {
		t.Helper()
		c := exec.Command("git", testgit.Args(args...)...)
		c.Dir = dir
		c.Env = testgit.Env()
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("git %s: %v (%s)", strings.Join(args, " "), err, out)
		}
	}
	run("init", "-q", "--initial-branch=master", ".")
	run("remote", "add", "origin", "https://example.invalid/statbus.git")
	// `remote add` writes a wildcard of its own; clear it so the test controls
	// the starting state exactly.
	unset := exec.Command("git", testgit.Args("config", "--unset-all", "remote.origin.fetch")...)
	unset.Dir = dir
	unset.Env = testgit.Env()
	_ = unset.Run()
	for _, s := range specs {
		run("config", "--add", "remote.origin.fetch", s)
	}
	return dir
}

func refspecsOf(t *testing.T, dir string) []string {
	t.Helper()
	c := exec.Command("git", testgit.Args("config", "--get-all", "remote.origin.fetch")...)
	c.Dir = dir
	c.Env = testgit.Env()
	out, err := c.Output()
	if err != nil {
		return nil
	}
	var got []string
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			got = append(got, l)
		}
	}
	return got
}

func assertCanonical(t *testing.T, dir, context string) {
	t.Helper()
	got := refspecsOf(t, dir)
	if len(got) != len(CanonicalRefspecs) {
		t.Fatalf("%s: got %d refspecs, want %d:\n  got:  %v\n  want: %v",
			context, len(got), len(CanonicalRefspecs), got, CanonicalRefspecs)
	}
	for i, want := range CanonicalRefspecs {
		if got[i] != want {
			t.Errorf("%s: refspec %d = %q, want %q", context, i, got[i], want)
		}
	}
}

// THE gh STATE, defect 1: a box born from `clone --depth 1 --branch <TAG>` has
// only the tag pin and NO wildcard, so it cannot fetch branches at all.
func TestNormalizeFixesTheNarrowCloneState(t *testing.T) {
	dir := newRepoWithRefspecs(t, "+refs/tags/v2026.08.0-rc.16:refs/tags/v2026.08.0-rc.16")

	if err := NormalizeRefspecs(dir); err != nil {
		t.Fatalf("normalize: %v", err)
	}
	assertCanonical(t, dir, "narrow clone")
}

// THE gh STATE, defect 2: `set-branches --add` appended once per rescue run, so
// gh carried three identical db-seed lines. This is the case the PREVIOUS
// mechanism could not touch — `git config --unset` refuses when multiple values
// match, so it failed silently on exactly this input.
func TestNormalizeFixesTheTripledSeedState(t *testing.T) {
	dir := newRepoWithRefspecs(t,
		"+refs/tags/v2026.08.0-rc.16:refs/tags/v2026.08.0-rc.16",
		"+refs/heads/db-seed:refs/remotes/origin/db-seed",
		"+refs/heads/db-seed:refs/remotes/origin/db-seed",
		"+refs/heads/db-seed:refs/remotes/origin/db-seed",
	)

	if err := NormalizeRefspecs(dir); err != nil {
		t.Fatalf("normalize: %v", err)
	}
	assertCanonical(t, dir, "tripled db-seed")
}

// Already canonical → unchanged. Idempotence is what lets this run on every
// install and every upgrade with no guard at the call site.
func TestNormalizeIsIdempotent(t *testing.T) {
	dir := newRepoWithRefspecs(t, CanonicalRefspecs...)

	for i := 0; i < 3; i++ {
		if err := NormalizeRefspecs(dir); err != nil {
			t.Fatalf("normalize (pass %d): %v", i+1, err)
		}
		assertCanonical(t, dir, "idempotent pass")
	}
}

// The stale devops/* entries the retired cleaner existed for must still be
// removed — the replacement has to cover its predecessor's actual job, not only
// the new cases.
func TestNormalizeRemovesStaleDevopsRefspecs(t *testing.T) {
	dir := newRepoWithRefspecs(t,
		"+refs/heads/*:refs/remotes/origin/*",
		"+refs/heads/devops/deploy-to-dev:refs/remotes/origin/devops/deploy-to-dev",
		"+refs/heads/devops/deploy-to-no:refs/remotes/origin/devops/deploy-to-no",
	)

	if err := NormalizeRefspecs(dir); err != nil {
		t.Fatalf("normalize: %v", err)
	}
	assertCanonical(t, dir, "stale devops entries")
	for _, spec := range refspecsOf(t, dir) {
		if strings.Contains(spec, "devops/") {
			t.Errorf("stale devops refspec survived: %q", spec)
		}
	}
}

// STATBUS-248: the retired deploy transport left an explicit per-slot refspec
// on live boxes. Once the corresponding remote branch is deleted, Git refuses
// every fetch with "couldn't find remote ref". Normalization must remove that
// latent fetch failure and leave exactly the two canonical lines.
func TestNormalizeRemovesRetiredCloudDeployRefspec(t *testing.T) {
	dir := newRepoWithRefspecs(t,
		CanonicalRefspecs[0],
		CanonicalRefspecs[1],
		"+refs/heads/ops/cloud/deploy/dev:refs/remotes/origin/ops/cloud/deploy/dev",
	)

	if err := NormalizeRefspecs(dir); err != nil {
		t.Fatalf("normalize: %v", err)
	}
	assertCanonical(t, dir, "retired cloud deploy refspec")
	for _, spec := range refspecsOf(t, dir) {
		if strings.Contains(spec, "ops/cloud/deploy/") {
			t.Errorf("retired deploy refspec survived: %q", spec)
		}
	}
}

// A box with no refspec at all (the --unset-all "key missing" case, git exit 5)
// must be brought to canonical rather than reported as an error.
func TestNormalizeFromEmpty(t *testing.T) {
	dir := newRepoWithRefspecs(t)

	if err := NormalizeRefspecs(dir); err != nil {
		t.Fatalf("normalize: %v", err)
	}
	assertCanonical(t, dir, "empty")
}

// Not a git repo — a fresh box before the clone. Must be a silent no-op, not an
// error the caller would report as a problem.
func TestNormalizeNoRepoIsNotAnError(t *testing.T) {
	if err := NormalizeRefspecs(t.TempDir()); err != nil {
		t.Errorf("no repo should be a silent no-op, got: %v", err)
	}
}

// ── STATBUS-324: origin URL normalization ────────────────────────────────────

func originURLOf(t *testing.T, dir string) string {
	t.Helper()
	c := exec.Command("git", testgit.Args("config", "--get", "remote.origin.url")...)
	c.Dir = dir
	c.Env = testgit.Env()
	out, err := c.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func setOriginURL(t *testing.T, dir, url string) {
	t.Helper()
	c := exec.Command("git", testgit.Args("config", "remote.origin.url", url)...)
	c.Dir = dir
	c.Env = testgit.Env()
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("set origin url: %v (%s)", err, out)
	}
}

// The case this exists for: a box born before the HTTPS convention. SSH to
// GitHub needs a key the box may not have, for a repository that is public and
// needs none.
func TestNormalizeOriginURLRewritesSSHEraRemotes(t *testing.T) {
	for _, sshURL := range []string{
		"git@github.com:statisticsnorway/statbus.git",
		"ssh://git@github.com/statisticsnorway/statbus.git",
		"git@github.com:statisticsnorway/statbus",
	} {
		t.Run(sshURL, func(t *testing.T) {
			dir := newRepoWithRefspecs(t)
			setOriginURL(t, dir, sshURL)

			if err := NormalizeOriginURL(dir); err != nil {
				t.Fatalf("normalize: %v", err)
			}
			if got := originURLOf(t, dir); got != CanonicalOriginURL {
				t.Errorf("origin = %q, want %q", got, CanonicalOriginURL)
			}
		})
	}
}

// Already canonical → untouched. Idempotence is what lets this run on every
// install with no guard at the call site.
func TestNormalizeOriginURLIsIdempotent(t *testing.T) {
	dir := newRepoWithRefspecs(t)
	setOriginURL(t, dir, CanonicalOriginURL)

	for i := 0; i < 3; i++ {
		if err := NormalizeOriginURL(dir); err != nil {
			t.Fatalf("normalize (pass %d): %v", i+1, err)
		}
		if got := originURLOf(t, dir); got != CanonicalOriginURL {
			t.Fatalf("pass %d: origin = %q, want %q", i+1, got, CanonicalOriginURL)
		}
	}
}

// Not a git repo — a fresh box before the clone. Silent no-op, never a reported
// failure, matching NormalizeRefspecs' behaviour so the two agree on what
// "nothing to do here" means.
func TestNormalizeOriginURLNoRepoIsNotAnError(t *testing.T) {
	if err := NormalizeOriginURL(t.TempDir()); err != nil {
		t.Errorf("no repo should be a silent no-op, got: %v", err)
	}
}

// A repo with no origin at all: adding a remote is the clone's job, not this
// function's. Must not invent one, and must not report a failure.
func TestNormalizeOriginURLWithNoOriginIsNotAnError(t *testing.T) {
	dir := t.TempDir()
	c := exec.Command("git", testgit.Args("init", "-q", "--initial-branch=master", ".")...)
	c.Dir = dir
	c.Env = testgit.Env()
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("git init: %v (%s)", err, out)
	}

	if err := NormalizeOriginURL(dir); err != nil {
		t.Errorf("missing origin should be a silent no-op, got: %v", err)
	}
	if got := originURLOf(t, dir); got != "" {
		t.Errorf("must not invent a remote; got origin = %q", got)
	}
}
