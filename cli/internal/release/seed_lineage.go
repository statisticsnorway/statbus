package release

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var migrationUpPathRE = regexp.MustCompile(`^(?:.*/)?(\d{14})_[^/]+\.up\.(?:sql|psql)$`)

// SeedLineageMigration records the first first-parent commit after the release
// baseline where a migration version was visible. Images publishes a
// commit-addressed seed for every master push, so this Git lineage is the
// fail-closed authority for versions that may remain in a retained cache.
type SeedLineageMigration struct {
	Version int64
	Commit  string
	Path    string
}

// MissingSeedLineageMigrations returns migration versions present in any
// first-parent commit in baselineRef..candidateRef but absent from candidateRef.
// Such a disappearance is a rename/removal even when the version never reached
// a named release. A retained seed may already contain its ledger row and schema.
func MissingSeedLineageMigrations(projDir, baselineRef, candidateRef string) ([]SeedLineageMigration, error) {
	commitsOut, err := gitOutput(projDir, "rev-list", "--first-parent", "--reverse", baselineRef+".."+candidateRef)
	if err != nil {
		return nil, fmt.Errorf("list seed lineage %s..%s: %w", baselineRef, candidateRef, err)
	}
	commits := strings.Fields(commitsOut)
	if len(commits) == 0 {
		return nil, nil
	}

	seen := make(map[int64]SeedLineageMigration)
	for _, commit := range commits {
		paths, err := migrationUpPathsAtRef(projDir, commit)
		if err != nil {
			return nil, err
		}
		for version, path := range paths {
			if _, ok := seen[version]; !ok {
				seen[version] = SeedLineageMigration{Version: version, Commit: commit, Path: path}
			}
		}
	}

	candidate, err := migrationUpPathsAtRef(projDir, candidateRef)
	if err != nil {
		return nil, err
	}
	missing := make([]SeedLineageMigration, 0)
	for version, first := range seen {
		if _, ok := candidate[version]; !ok {
			missing = append(missing, first)
		}
	}
	sort.Slice(missing, func(i, j int) bool { return missing[i].Version < missing[j].Version })
	return missing, nil
}

func migrationUpPathsAtRef(projDir, ref string) (map[int64]string, error) {
	out, err := gitOutput(projDir, "ls-tree", "-r", "--name-only", ref, "--", "migrations")
	if err != nil {
		return nil, fmt.Errorf("list migrations at %s: %w", ref, err)
	}
	paths := make(map[int64]string)
	for _, path := range strings.Split(strings.TrimSpace(out), "\n") {
		path = strings.TrimSpace(path)
		match := migrationUpPathRE.FindStringSubmatch(filepath.ToSlash(path))
		if match == nil {
			continue
		}
		version, err := strconv.ParseInt(match[1], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse migration version in %s at %s: %w", path, ref, err)
		}
		if prior, exists := paths[version]; exists && prior != path {
			return nil, fmt.Errorf("duplicate migration version %d at %s: %s and %s", version, ref, prior, path)
		}
		paths[version] = path
	}
	return paths, nil
}

func gitOutput(projDir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = projDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}
