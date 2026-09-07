package migrate

import (
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// TestNewMigrationsSortAfterPreviousRelease prevents a migration introduced
// after a release from being inserted behind that release's migration history.
// Such a file is applied in timestamp order by a full replay but appended by an
// incrementally migrated database, producing permanently different schemas.
func TestNewMigrationsSortAfterPreviousRelease(t *testing.T) {
	root := repoRoot(t)
	tagOut, err := exec.Command("git", "-C", root, "describe", "--tags", "--abbrev=0").Output()
	if err != nil {
		t.Fatalf("resolve immediately preceding release tag: %v", err)
	}
	tag := strings.TrimSpace(string(tagOut))

	treeOut, err := exec.Command("git", "-C", root, "ls-tree", "-r", "--name-only", tag, "--", "migrations").Output()
	if err != nil {
		t.Fatalf("list migrations in %s: %v", tag, err)
	}
	released := make(map[string]bool)
	var releasedMax int64
	for _, rel := range strings.Fields(string(treeOut)) {
		released[rel] = true
		mf, parseErr := parseMigrationFile(rel)
		if parseErr == nil && mf.IsUp && mf.Version > releasedMax {
			releasedMax = mf.Version
		}
	}
	if releasedMax == 0 {
		t.Fatalf("%s contains no valid up migrations", tag)
	}

	files, err := listMigrationFiles(root)
	if err != nil {
		t.Fatalf("list current migrations: %v", err)
	}
	for _, mf := range files {
		rel, err := filepath.Rel(root, mf.Path)
		if err != nil {
			t.Fatalf("relative migration path: %v", err)
		}
		if !released[filepath.ToSlash(rel)] && mf.Version <= releasedMax {
			t.Errorf("new migration %s has version %s, which does not sort after newest migration %s in preceding release %s; a new migration must sort after every released migration", filepath.Base(mf.Path), strconv.FormatInt(mf.Version, 10), strconv.FormatInt(releasedMax, 10), tag)
		}
	}
}
