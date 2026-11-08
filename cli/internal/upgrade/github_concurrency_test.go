package upgrade

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func git592(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@example.org", "GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@example.org", "GIT_CONFIG_NOSYSTEM=1", "GIT_CONFIG_GLOBAL=/dev/null")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func repo592(t *testing.T) (remote, local, sha string) {
	t.Helper()
	root := t.TempDir()
	remote, local = filepath.Join(root, "remote"), filepath.Join(root, "local")
	git592(t, root, "init", "-b", "master", remote)
	git592(t, remote, "commit", "--allow-empty", "-m", "initial")
	git592(t, root, "clone", remote, local)
	git592(t, remote, "commit", "--allow-empty", "-m", "release")
	sha = git592(t, remote, "rev-parse", "HEAD")
	git592(t, local, "fetch", "--no-tags", "origin", sha)
	git592(t, remote, "tag", "v2026.11.2")
	original := gitDiscoveryRetryWait
	gitDiscoveryRetryWait = func(time.Duration) {}
	t.Cleanup(func() { gitDiscoveryRetryWait = original })
	return
}

func assertTags592(t *testing.T, local, sha string) {
	t.Helper()
	tags, err := DiscoverTagsViaGit(local)
	if err != nil {
		t.Fatal(err)
	}
	if len(tags) != 1 || tags[0].TagName != "v2026.11.2" || tags[0].CommitSHA != sha {
		t.Fatalf("discovered %+v, want v2026.11.2 at %s", tags, sha)
	}
}

func TestDiscoveryCompetingRef_STATBUS592(t *testing.T) {
	for _, ref := range []string{"refs/remotes/origin/master", "refs/tags/v2026.11.2"} {
		t.Run(ref, func(t *testing.T) {
			_, local, sha := repo592(t)
			git592(t, local, "config", "fetch.prune", "true")
			git592(t, local, "tag", "stale")
			// Pruning commits before fetch updates the refs whose old values it read.
			// A real competing Git writer advances the ref at that transaction barrier.
			hook := fmt.Sprintf("#!/bin/sh\nif [ \"$1\" = committed ] && cat | grep -q refs/tags/stale; then\n git update-ref %s %s || exit 1\nfi\n", ref, sha)
			if err := os.WriteFile(filepath.Join(local, ".git/hooks/reference-transaction"), []byte(hook), 0755); err != nil {
				t.Fatal(err)
			}
			waits := 0
			gitDiscoveryRetryWait = func(time.Duration) { waits++ }
			assertTags592(t, local, sha)
			wantWaits := 1
			if strings.HasPrefix(ref, "refs/tags/") {
				wantWaits = 0 // Git already accepts a concurrently created identical tag.
			}
			if waits != wantWaits {
				t.Fatalf("retry waits=%d, want %d", waits, wantWaits)
			}
			if got := git592(t, local, "rev-parse", ref); got != sha {
				t.Fatalf("ref=%s, want %s", got, sha)
			}
			if got := git592(t, local, "tag", "-l"); got != "v2026.11.2" {
				t.Fatalf("remaining tags=%q", got)
			}
		})
	}
}

func TestDiscoveryRefLock_STATBUS592(t *testing.T) {
	for _, persistent := range []bool{false, true} {
		t.Run(fmt.Sprint(persistent), func(t *testing.T) {
			_, local, sha := repo592(t)
			lock := filepath.Join(local, ".git/refs/remotes/origin/master.lock")
			if err := os.WriteFile(lock, []byte("competing writer"), 0600); err != nil {
				t.Fatal(err)
			}
			waits := 0
			gitDiscoveryRetryWait = func(time.Duration) {
				waits++
				if !persistent {
					if err := os.Remove(lock); err != nil {
						t.Fatal(err)
					}
				}
			}
			if !persistent {
				assertTags592(t, local, sha)
			} else {
				if _, err := DiscoverTagsViaGit(local); err == nil {
					t.Fatal("persistent lock must return error")
				}
				if data, err := os.ReadFile(lock); err != nil || string(data) != "competing writer" {
					t.Fatalf("lock ownership changed: %q %v", data, err)
				}
				git592(t, local, "rev-parse", "refs/tags/v2026.11.2")
			}
			want := 1
			if persistent {
				want = preswapFetchMaxAttempts - 1
			}
			if waits != want {
				t.Fatalf("waits=%d want %d", waits, want)
			}
		})
	}
}

func TestDiscoveryMovedTagImmediate_STATBUS592(t *testing.T) {
	_, local, sha := repo592(t)
	git592(t, local, "tag", "v2026.11.2", "HEAD")
	old := git592(t, local, "rev-parse", "v2026.11.2")
	waits := 0
	gitDiscoveryRetryWait = func(time.Duration) { waits++ }
	if _, err := DiscoverTagsViaGit(local); err == nil {
		t.Fatal("moved release tag must return error")
	}
	if waits != 0 {
		t.Fatalf("moved tag retried %d times", waits)
	}
	if got := git592(t, local, "rev-parse", "v2026.11.2"); got != old || got == sha {
		t.Fatalf("tag=%s want original %s", got, old)
	}
}
