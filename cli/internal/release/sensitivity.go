package release

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// SensitivePathsFile is the ONE checked-in list of paths whose change makes
// a candidate need fresh install/upgrade/recovery proof. Every reader of
// that list, in the CLI and in CI, goes through this file: there is no
// second implementation of the rule (the release chain calls `./sb release
// covered`, which calls DecideCoverage, which calls DiffTouchesSensitivePath).
const SensitivePathsFile = "ops/release/upgrade-sensitive-paths.txt"

// LoadSensitivePaths reads SensitivePathsFile under projDir: one substring
// per line, blank lines and #-comments ignored. An empty list is an error,
// because an empty list would make every diff "not sensitive".
func LoadSensitivePaths(projDir string) ([]string, error) {
	data, err := os.ReadFile(filepath.Join(projDir, SensitivePathsFile))
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", SensitivePathsFile, err)
	}
	var paths []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		paths = append(paths, line)
	}
	if len(paths) == 0 {
		return nil, fmt.Errorf("%s lists no paths — refusing an empty sensitivity list, which would call every change safe", SensitivePathsFile)
	}
	return paths, nil
}

// MatchesSensitivePath is the ONE matching rule: substring containment of
// any list entry in the repo-root-relative path (as `git diff --name-only`
// prints it). Deliberately over-inclusive, as the list's header documents:
// a coincidental hit costs one fleet run, a miss costs an unproven promotion.
func MatchesSensitivePath(file string, sensitivePaths []string) bool {
	for _, p := range sensitivePaths {
		if strings.Contains(file, p) {
			return true
		}
	}
	return false
}

// DiffTouchesSensitivePath runs `git diff --name-only fromRef..toRef` in
// projDir and returns every changed file that MatchesSensitivePath.
func DiffTouchesSensitivePath(projDir, fromRef, toRef string, sensitivePaths []string) (touched bool, matchedFiles []string, err error) {
	cmd := exec.Command("git", "diff", "--name-only", fromRef+".."+toRef)
	cmd.Dir = projDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false, nil, fmt.Errorf("git diff %s..%s: %w: %s", fromRef, toRef, err, strings.TrimSpace(string(out)))
	}
	for _, file := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		file = strings.TrimSpace(file)
		if file == "" {
			continue
		}
		if MatchesSensitivePath(file, sensitivePaths) {
			matchedFiles = append(matchedFiles, file)
		}
	}
	return len(matchedFiles) > 0, matchedFiles, nil
}
