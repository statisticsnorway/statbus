package migrate

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
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
// (e.g. "./sb types generate", "./dev.sh generate-doc-db").
//
// Mirrors the bash assert_db_at_head() helper in dev.sh. Keep the two
// in sync — both shapes the same actionable diagnostic.
func AssertDBAtHead(projDir, dbName, caller string) (string, error) {
	psqlPath, prefix, env, err := PsqlCommand(projDir)
	if err != nil {
		return "", fmt.Errorf("%s: %w", caller, err)
	}

	// Acquire a SHARED advisory lock on hashtext(SeedMutationLockKey)
	// on a connection to the postgres system DB. Blocks (with 60s
	// timeout) while an EXCLUSIVE holder (recreate-seed via
	// `./sb db with-seed-lock --exclusive`) is mid-mutation. Without
	// this gate, a parallel `./sb types generate` or
	// `./dev.sh generate-doc-db` could hit statbus_seed
	// during its DROP window and fail with a confusing "database does
	// not exist" mid-rebuild.
	//
	// Defensive: lock failures (postgres unreachable, timeout) surface
	// with the lock-acquisition error directly. That's MORE informative
	// than the downstream "BEHIND by N" diagnostic that the empty
	// query would otherwise produce. Lock is coordination, not the
	// correctness gate.
	//
	// The conn is held for the duration of this function — released
	// automatically by defer Close (PG advisory locks are
	// session-scoped, so close = release).
	ctx := context.Background()
	lockConn, err := AcquireSeedLock(ctx, projDir, false /* shared */, 60*time.Second, caller)
	if err != nil {
		return "", fmt.Errorf("%s: %w", caller, err)
	}
	defer func() { _ = lockConn.Close(ctx) }()

	// Refuse PG template DBs (datistemplate=true, e.g. statbus_test_template
	// after create-test-template sets IS_TEMPLATE=true + ALLOW_CONNECTIONS=false).
	// Templates aren't directly queryable; a plain psql -d <template> returns
	// empty stdout silently and we'd compute a false "BEHIND HEAD" diagnostic
	// — the silent-failure bug class this defense closes. Callers should point at the SEED
	// (canonical source-of-truth: POSTGRES_SEED_DB, queryable, has full
	// db.migration set), NOT downstream template artifacts. Mirrors the
	// same defense in dev.sh assert_db_at_head.
	tmplArgs := append([]string(nil), prefix...)
	tmplArgs = append(tmplArgs, "-d", "postgres", "-t", "-A", "-c",
		fmt.Sprintf("SELECT datistemplate FROM pg_database WHERE datname = '%s'", dbName))
	tmplCmd := exec.Command(psqlPath, tmplArgs...)
	tmplCmd.Dir = projDir
	tmplCmd.Env = env
	tmplOut, tmplErr := tmplCmd.Output()
	if tmplErr == nil && strings.TrimSpace(string(tmplOut)) == "t" {
		return "", fmt.Errorf(
			"REFUSED: %s\n"+
				"Reason:  %q is a PG template (datistemplate=true, ALLOW_CONNECTIONS=false) — not directly queryable.\n"+
				"Fix:     callers should assert against the SEED (canonical source-of-truth: ${POSTGRES_SEED_DB:-statbus_seed}), NOT downstream template artifacts",
			caller, dbName)
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
