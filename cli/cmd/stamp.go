package cmd

import "strings"

// ParseTwoLineStamp splits an H1 two-line stamp (task #123) into its
// SHA and migration-version components. Legacy single-line stamps
// return ("<sha>", "") — caller decides how to handle (typically:
// refuse with re-run guidance).
//
//	<head_sha>\n<source_db_migration_max_version>\n
//
// Trailing whitespace on each line is trimmed.
func ParseTwoLineStamp(data []byte) (sha, version string) {
	lines := strings.Split(string(data), "\n")
	if len(lines) >= 1 {
		sha = strings.TrimSpace(lines[0])
	}
	if len(lines) >= 2 {
		version = strings.TrimSpace(lines[1])
	}
	return sha, version
}
