package migrate

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// AssertDBAtHead refuses if dbName's db.migration row set doesn't match the
// on-disk migrations/*.up.{sql,psql} file set at projDir. Symmetric: catches
// both "DB behind HEAD" (template needs new migrations applied) and "DB ahead
// of HEAD" (feature-branch contamination where the template applied migrations
// the current working tree doesn't have).
//
// On success returns the source DB's max migration version (a 14-digit
// YYYYMMDDHHMMSS string). Callers use this for H1 two-line stamp writes:
//
//	tmp/<artifact>-passed-sha:
//	  line 1: git rev-parse HEAD       (the SHA the artifact was generated from)
//	  line 2: source DB migration max  (the schema state the artifact reflects)
//
// On failure returns "" + an actionable error that names dbName, the
// drift direction (behind / ahead / both), the missing versions, and the
// Fix-line for the operator. Designed to be printed directly to the
// terminal by the calling cobra command.
//
// caller is the human-readable command name printed in the diagnostic
// (e.g. "./sb types generate", "./dev.sh generate-db-documentation").
//
// Mirrors the bash assert_db_at_head() helper in dev.sh. Keep the two
// in sync — both shapes the same actionable diagnostic.
func AssertDBAtHead(projDir, dbName, caller string) (string, error) {
	psqlPath, prefix, env, err := PsqlCommand(projDir)
	if err != nil {
		return "", fmt.Errorf("%s: %w", caller, err)
	}
	args := append([]string(nil), prefix...)
	args = append(args, "-d", dbName, "-t", "-A", "-c",
		"SELECT version FROM db.migration ORDER BY version")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("%s: querying %s.db.migration: %w", caller, dbName, err)
	}

	dbVersions := map[string]struct{}{}
	var dbList []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if _, dup := dbVersions[line]; dup {
			continue
		}
		dbVersions[line] = struct{}{}
		dbList = append(dbList, line)
	}

	diskVersions, err := listDiskMigrationVersions(projDir)
	if err != nil {
		return "", fmt.Errorf("%s: listing on-disk migrations: %w", caller, err)
	}

	var behind, ahead []string
	for v := range diskVersions {
		if _, ok := dbVersions[v]; !ok {
			behind = append(behind, v)
		}
	}
	for v := range dbVersions {
		if _, ok := diskVersions[v]; !ok {
			ahead = append(ahead, v)
		}
	}
	sort.Strings(behind)
	sort.Strings(ahead)

	if len(behind) == 0 && len(ahead) == 0 {
		if len(dbList) == 0 {
			// Edge: empty DB AND empty migrations/. Treat as success
			// with version="" — caller can decide if that's acceptable.
			return "", nil
		}
		sort.Strings(dbList)
		return dbList[len(dbList)-1], nil
	}

	var msg strings.Builder
	fmt.Fprintf(&msg, "REFUSED: %s\n", caller)
	if len(behind) > 0 {
		fmt.Fprintf(&msg, "Reason:  source DB %q is BEHIND HEAD by %d migration(s):\n", dbName, len(behind))
		for _, v := range behind {
			fmt.Fprintf(&msg, "  + %s\n", v)
		}
		fmt.Fprintf(&msg, "Fix:     ./dev.sh migrate-and-test fast    (rebuilds seed + template)\n")
	}
	if len(ahead) > 0 {
		fmt.Fprintf(&msg, "Reason:  source DB %q is AHEAD of HEAD by %d migration(s):\n", dbName, len(ahead))
		for _, v := range ahead {
			fmt.Fprintf(&msg, "  - %s\n", v)
		}
		fmt.Fprintf(&msg, "Fix:     ./dev.sh recreate-database   (or check out the right branch first)\n")
	}
	return "", fmt.Errorf("%s", strings.TrimRight(msg.String(), "\n"))
}

// LatestOnDiskMigrationVersion returns the max 14-digit version timestamp
// across migrations/*.up.{sql,psql}. Used by stamp writers that don't
// have an open DB connection (e.g., CI-fallback path in
// cli/cmd/release.go's fast-test stamp reader, which writes a fresh
// stamp when CI passed but no local stamp exists).
//
// Returns "" if no migrations exist on disk.
func LatestOnDiskMigrationVersion(projDir string) (string, error) {
	versions, err := listDiskMigrationVersions(projDir)
	if err != nil {
		return "", err
	}
	var keys []string
	for v := range versions {
		keys = append(keys, v)
	}
	if len(keys) == 0 {
		return "", nil
	}
	sort.Strings(keys)
	return keys[len(keys)-1], nil
}

// listDiskMigrationVersions returns the set of 14-digit version
// timestamps parsed from migrations/*.up.{sql,psql} filename prefixes.
// Shared helper for AssertDBAtHead + LatestOnDiskMigrationVersion.
func listDiskMigrationVersions(projDir string) (map[string]struct{}, error) {
	versions := map[string]struct{}{}
	for _, glob := range []string{"*.up.sql", "*.up.psql"} {
		matches, err := filepath.Glob(filepath.Join(projDir, "migrations", glob))
		if err != nil {
			return nil, err
		}
		for _, m := range matches {
			base := filepath.Base(m)
			parts := strings.SplitN(base, "_", 2)
			if len(parts) > 0 && len(parts[0]) == 14 {
				versions[parts[0]] = struct{}{}
			}
		}
	}
	return versions, nil
}
