package config

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// TestDerivedVersion_ReleaseCheckoutVsDevCheckout pins STATBUS-422's plumbing
// end: the release install.sh resolves (--version, STATBUS_INSTALL_VERSION or
// the channel's GitHub release) reaches the generated .env as VERSION /
// PUBLIC_STATBUS_VERSION through the checkout itself. install.sh clones
// shallow with --no-checkout, fetches exactly refs/tags/<tag> and detaches at
// the tag's commit; `git describe --tags --always` must read that tag back.
// A development checkout past the tag must stay distinguishable from it.
func TestDerivedVersion_ReleaseCheckoutVsDevCheckout(t *testing.T) {
	git := func(dir string, args ...string) string {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = testgit.Env()
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	commit := func(dir, msg string) {
		git(dir, "-c", "user.name=test", "-c", "user.email=test@example.invalid",
			"-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", msg)
	}

	origin := t.TempDir()
	git(origin, "init", "-q")
	commit(origin, "base")
	commit(origin, "release")
	git(origin, "-c", "user.name=test", "-c", "user.email=test@example.invalid",
		"-c", "tag.gpgsign=false", "tag", "-a", "-m", "v2026.10.0", "v2026.10.0")
	commit(origin, "after release")

	cfg := &ConfigEnv{DeploymentSlotPortOffset: "1", DeploymentSlotCode: "test"}

	// Release install: the exact install.sh FRESH sequence.
	release := filepath.Join(t.TempDir(), "statbus")
	git(filepath.Dir(release), "clone", "-q", "--depth", "1", "--no-checkout", "file://"+origin, release)
	git(release, "fetch", "-q", "--depth", "1", "origin", "refs/tags/v2026.10.0:refs/tags/v2026.10.0")
	git(release, "-c", "advice.detachedHead=false", "checkout", "-q", "--detach", "v2026.10.0^{commit}")
	derived := computeDerivedInDir(cfg, release)
	if derived.Version != "v2026.10.0" {
		t.Fatalf("release checkout: VERSION=%q, want v2026.10.0", derived.Version)
	}
	if want := git(release, "rev-parse", "--short=8", "HEAD"); derived.CommitShort != want {
		t.Fatalf("release checkout: COMMIT_SHORT=%q, want %q", derived.CommitShort, want)
	}

	// Development checkout past the tag: a describe, never the bare release.
	dev := filepath.Join(t.TempDir(), "statbus")
	git(filepath.Dir(dev), "clone", "-q", "file://"+origin, dev)
	derived = computeDerivedInDir(cfg, dev)
	if derived.Version == "v2026.10.0" || !strings.HasPrefix(derived.Version, "v2026.10.0-1-g") {
		t.Fatalf("dev checkout: VERSION=%q, want a v2026.10.0-1-g<sha> describe distinct from the release", derived.Version)
	}
}
