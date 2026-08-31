package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-307 acceptance criterion 6: UPGRADE_ROLE appears NOWHERE outside
// historical migrations and era-accurate fixtures.
//
// WHY A GREP TEST AND NOT A CODE ASSERTION. The key is retired, so there is no
// function left to test — the only way it comes back is textually, in a file
// someone writes later. A reintroduction would not break a build: the string
// would simply sit in a .env.config or a script, be silently ignored by every
// reader, and the box would follow its mode while its configuration said
// otherwise. That is the invisible-wrong-channel failure the whole design
// exists to remove, arriving through the back door. So the guard is textual,
// because the hazard is textual.
//
// Deliberately built by concatenation so this file does not match its own
// search.
var retiredRoleKey = "UPGRADE_" + "ROLE"

// allowedRoleMentions are the files permitted to name the retired key, each for
// a stated reason. An allowlist rather than a directory skip: every entry is a
// decision someone can disagree with, and a reviewer can see all of them here.
var allowedRoleMentions = map[string]string{
	// The transition itself must name what it translates.
	"cli/internal/config/upgrade_channel.go":      "the one-time fleet transition; deleted when the fleet has run it",
	"cli/internal/config/upgrade_channel_test.go": "tests that transition",
	// ERA-ACCURATE FIXTURES (STATBUS-297's rule). A harness must construct
	// states history could have produced, and boxes in the field genuinely have
	// this key today. Removing it here would test only already-migrated boxes —
	// the ones least at risk.
	"test/install-recovery/lib/vm-bootstrap.sh":       "era-accurate: a 254-era box carried this key",
	"cli/internal/upgrade/service_cli_config_test.go": "era-accurate: .env text a pre-307 binary wrote, still on disk in the field",
	// This file.
	"cli/cmd/upgrade_role_retired_test.go": "the guard itself",
}

func TestRetiredUpgradeRoleAppearsNowhere(t *testing.T) {
	root := repoRootForRoleScan(t)

	// SCAN GIT-TRACKED FILES, NOT THE FILESYSTEM. The hazard is a retired key
	// COMMITTED to the repository; a developer's own .env and .env.config are
	// gitignored local state, and on a box that has not yet run the transition
	// they legitimately still carry the key — that is precisely the state the
	// transition exists to fix, not a defect in the tree. A filesystem walk
	// reported those as violations and would have failed this test on every
	// un-migrated developer machine, which is a guard that cries wolf about the
	// thing it is supposed to be repairing.
	out, err := exec.Command("git", "-C", root, "ls-files").Output()
	if err != nil {
		t.Skipf("not a git checkout (%v) — this guard polices committed files", err)
	}

	skipPrefix := []string{
		// Historical migrations are immutable by doctrine: one naming the key is
		// a record of what was true when it ran.
		"migrations/",
		// The project's own history and commentary.
		".backlog/",
	}

	var offenders []string
	for _, rel := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if rel == "" {
			continue
		}
		if _, allowed := allowedRoleMentions[rel]; allowed {
			continue
		}
		skip := false
		for _, p := range skipPrefix {
			if strings.HasPrefix(rel, p) {
				skip = true
				break
			}
		}
		if skip {
			continue
		}
		info, serr := os.Stat(filepath.Join(root, rel))
		if serr != nil || info.IsDir() || info.Size() > 2<<20 {
			continue
		}
		b, rerr := os.ReadFile(filepath.Join(root, rel))
		if rerr != nil {
			continue
		}
		if strings.Contains(string(b), retiredRoleKey) {
			offenders = append(offenders, rel)
		}
	}

	if len(offenders) > 0 {
		t.Errorf(`the retired key %s appears in %d committed file(s) outside the allowlist:

  %s

STATBUS-307 removed this key: a box declares CADDY_DEPLOYMENT_MODE, and the
channel is derived from it unless UPGRADE_CHANNEL is written explicitly.

A reintroduced role key is WORSE than a missing setting, because nothing reads
it: the file would say one thing and the box would do another, silently — the
exact failure that put five production installations on release candidates for
two months.

If a new file legitimately needs to name it (an era-accurate fixture, or the
transition itself), add it to allowedRoleMentions with the reason.`,
			retiredRoleKey, len(offenders), strings.Join(offenders, "\n  "))
	}
}

// repoRootForRoleScan walks up from the test's working directory to the repo
// root, identified by go.mod's parent — the same anchor thisRepoFile uses.
func repoRootForRoleScan(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	for i := 0; i < 10; i++ {
		if _, err := os.Stat(filepath.Join(dir, "install.sh")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	t.Fatal("could not locate the repository root (no install.sh found walking up)")
	return ""
}
