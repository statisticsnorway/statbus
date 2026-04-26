package release

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// ReleaseTagPattern matches the project's release tag shape:
// `vYYYY.MM.PATCH` (stable) and `vYYYY.MM.PATCH-rc.N` (prerelease).
//
// Mirrored in `cli/cmd/release.go` (private `releaseTagPattern`); the
// two are kept in sync. Exported here because the migrate runner needs
// to identify release tags from the lower `internal/migrate` package
// (which cannot import `cli/cmd`).
var ReleaseTagPattern = regexp.MustCompile(`^v\d{4}\.\d{2}\.\d+(-rc\.\d+)?$`)

// MigrationInReleasedTag returns the first release-shaped tag whose
// tree contains the file `migrations/<version>_*.up.sql`, or "" if no
// release tag contains it.
//
// Used by the migrate runner to gate `content_hash` mismatch handling:
// - Hash mismatch + version IS in a released tag → immutability
//   violation (hard fail; the migration is published, no edits allowed).
// - Hash mismatch + version NOT in any released tag → WIP edit; the
//   operator can recover via `./sb migrate redo <version>`.
//
// Implementation: enumerates `git tag -l v*`, filters by
// ReleaseTagPattern, and probes each tag's tree with
// `git rev-parse --quiet --verify <tag>:<path>`. First hit wins; the
// tags from `git tag -l` print in alphabetic order which equals
// chronological order for our CalVer scheme — so the returned tag is
// the EARLIEST release containing the migration (most-informative for
// the operator: "this shipped in <oldest tag>, you cannot edit it").
//
// Returns "" (no error) when:
//   - the file doesn't exist at HEAD (already deleted; not our concern here)
//   - no release-shaped tag contains the file (genuine WIP)
//
// Returns the tag (no error) when at least one release-shaped tag
// contains the file. Errors only on git command failure.
func MigrationInReleasedTag(projDir string, version int64) (string, error) {
	pattern := filepath.Join(projDir, "migrations", fmt.Sprintf("%d_*.up.sql", version))
	matches, _ := filepath.Glob(pattern)
	if len(matches) == 0 {
		return "", nil
	}
	rel := "migrations/" + filepath.Base(matches[0])

	tagsCmd := exec.Command("git", "tag", "-l", "v*")
	tagsCmd.Dir = projDir
	tagsOut, err := tagsCmd.Output()
	if err != nil {
		return "", fmt.Errorf("git tag -l v*: %w", err)
	}

	for _, tag := range strings.Split(strings.TrimSpace(string(tagsOut)), "\n") {
		tag = strings.TrimSpace(tag)
		if !ReleaseTagPattern.MatchString(tag) {
			continue
		}
		probe := exec.Command("git", "rev-parse", "--quiet", "--verify", tag+":"+rel)
		probe.Dir = projDir
		if probe.Run() == nil {
			return tag, nil
		}
	}
	return "", nil
}
