package cmd

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

var (
	restoreTo  string
	restoreYes bool
	backupKeep int

	validIdentifier = regexp.MustCompile(`^[a-zA-Z][a-zA-Z0-9_]*$`)
)

// validateIdentifier checks that a database name or slot code contains only safe characters.
func validateIdentifier(name, label string) error {
	if !validIdentifier.MatchString(name) {
		return fmt.Errorf("%s %q contains invalid characters (only letters, digits, and underscores allowed)", label, name)
	}
	return nil
}

// ── helpers ──────────────────────────────────────────────────────────────────

// dbIsRunning checks whether the database container is healthy.
func dbIsRunning(projDir string) bool {
	cmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_isready", "-U", "postgres")
	cmd.Dir = projDir
	return cmd.Run() == nil
}

// loadSlotCode reads DEPLOYMENT_SLOT_CODE from .env.config.
func loadSlotCode(projDir string) (string, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env.config"))
	if err != nil {
		return "", fmt.Errorf("load .env.config: %w", err)
	}
	code, ok := f.Get("DEPLOYMENT_SLOT_CODE")
	if !ok || code == "" {
		return "", fmt.Errorf("DEPLOYMENT_SLOT_CODE not set in .env.config")
	}
	return code, nil
}

// loadDbName reads POSTGRES_APP_DB from .env.
func loadDbName(projDir string) (string, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return "", fmt.Errorf("load .env: %w", err)
	}
	db, ok := f.Get("POSTGRES_APP_DB")
	if !ok || db == "" {
		return "", fmt.Errorf("POSTGRES_APP_DB not set in .env")
	}
	return db, nil
}

// loadSeedDbName reads POSTGRES_SEED_DB from .env. The seed DB is the
// canonical fresh-from-migrations baseline (build-time only; never
// worker-active). Source of `./sb db seed create`'s pg_dump artifact.
// Plan section R commit 4.
func loadSeedDbName(projDir string) (string, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return "", fmt.Errorf("load .env: %w", err)
	}
	db, ok := f.Get("POSTGRES_SEED_DB")
	if !ok || db == "" {
		return "", fmt.Errorf("POSTGRES_SEED_DB not set in .env. " +
			"Regenerate config to materialise it: `./sb config generate`")
	}
	return db, nil
}

// dumpTimestamp returns a filename-safe timestamp: YYYYMMDD_HHMMSS.
func dumpTimestamp() string {
	return time.Now().Format("20060102_150405")
}

// ensureDumpsDir creates the dbdumps/ directory if it does not exist.
func ensureDumpsDir(projDir string) (string, error) {
	dir := filepath.Join(projDir, "dbdumps")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("create dbdumps directory: %w", err)
	}
	return dir, nil
}

// warnIfManyDumps prints a warning when 3+ dump files exist.
func warnIfManyDumps(dir string) {
	entries, err := filepath.Glob(filepath.Join(dir, "*.pg_dump"))
	if err != nil {
		return
	}
	if len(entries) >= 3 {
		fmt.Fprintf(os.Stderr, "Warning: %d dump files in %s — consider running 'sb db dumps purge'\n", len(entries), dir)
	}
}

// humanSize formats bytes as a human-readable string.
func humanSize(bytes int64) string {
	const (
		kb = 1024
		mb = 1024 * kb
		gb = 1024 * mb
	)
	switch {
	case bytes >= gb:
		return fmt.Sprintf("%.1f GB", float64(bytes)/float64(gb))
	case bytes >= mb:
		return fmt.Sprintf("%.1f MB", float64(bytes)/float64(mb))
	case bytes >= kb:
		return fmt.Sprintf("%.1f KB", float64(bytes)/float64(kb))
	default:
		return fmt.Sprintf("%d B", bytes)
	}
}

// confirmAction reads y/n from /dev/tty. Returns true for yes.
func confirmAction(prompt string) bool {
	fmt.Fprintf(os.Stderr, "%s [y/N] ", prompt)
	tty, err := os.Open("/dev/tty")
	if err != nil {
		// If we can't open tty, read from stdin as fallback
		scanner := bufio.NewScanner(os.Stdin)
		if scanner.Scan() {
			answer := strings.TrimSpace(strings.ToLower(scanner.Text()))
			return answer == "y" || answer == "yes"
		}
		return false
	}
	defer tty.Close()
	scanner := bufio.NewScanner(tty)
	if scanner.Scan() {
		answer := strings.TrimSpace(strings.ToLower(scanner.Text()))
		return answer == "y" || answer == "yes"
	}
	return false
}

// ── db status ────────────────────────────────────────────────────────────────

var dbCmd = &cobra.Command{
	Use:   "db",
	Short: "Database operations (dump, restore, status)",
}

var dbStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check if the database is running",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		if dbIsRunning(projDir) {
			fmt.Println("Database is running")
			return nil
		}
		return fmt.Errorf("database is not running")
	},
}

// ── db dump ──────────────────────────────────────────────────────────────────

var dbDumpCmd = &cobra.Command{
	Use:   "dump",
	Short: "Dump the local database to a file",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		if !dbIsRunning(projDir) {
			return fmt.Errorf("database is not running — start it with 'sb start all'")
		}

		code, err := loadSlotCode(projDir)
		if err != nil {
			return err
		}

		dbName, err := loadDbName(projDir)
		if err != nil {
			return err
		}

		dumpsDir, err := ensureDumpsDir(projDir)
		if err != nil {
			return err
		}

		filename := fmt.Sprintf("%s_%s.pg_dump", code, dumpTimestamp())
		outPath := filepath.Join(dumpsDir, filename)

		fmt.Printf("Dumping %s to %s ...\n", dbName, filename)

		c := exec.Command("docker", "compose", "exec", "-T", "db",
			"pg_dump", "-Fc", "--no-owner",
			"--exclude-table-data=auth.secrets",
			"-U", "postgres", dbName)
		c.Dir = projDir

		outFile, err := os.Create(outPath)
		if err != nil {
			return fmt.Errorf("create output file: %w", err)
		}
		defer outFile.Close()

		c.Stdout = outFile
		c.Stderr = os.Stderr

		if err := c.Run(); err != nil {
			os.Remove(outPath)
			return fmt.Errorf("pg_dump failed: %w", err)
		}

		info, err := os.Stat(outPath)
		if err != nil {
			return err
		}
		if info.Size() == 0 {
			os.Remove(outPath)
			return fmt.Errorf("dump produced an empty file — check database connectivity")
		}

		fmt.Printf("Done: %s (%s)\n", outPath, humanSize(info.Size()))
		warnIfManyDumps(dumpsDir)
		return nil
	},
}

// ── db download ──────────────────────────────────────────────────────────────

var dbDownloadCmd = &cobra.Command{
	Use:   "download <code>",
	Short: "Download a database dump from a remote server",
	Long: `Download a database dump from a remote StatBus deployment via SSH.

The code corresponds to the deployment slot (e.g., "no", "dev", "demo").
Connects to statbus_{code}@niue.statbus.org and streams a pg_dump.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		code := args[0]
		sshUser := "statbus_" + code
		sshHost := "niue.statbus.org"
		remoteDB := "statbus_" + code

		// Check SSH connectivity
		fmt.Printf("Checking SSH connectivity to %s@%s ...\n", sshUser, sshHost)
		sshCheck := exec.Command("ssh",
			"-o", "ConnectTimeout=10",
			"-o", "BatchMode=yes",
			fmt.Sprintf("%s@%s", sshUser, sshHost),
			"echo ok")
		if out, err := sshCheck.CombinedOutput(); err != nil {
			return fmt.Errorf("SSH connection failed: %w\n%s", err, string(out))
		}

		dumpsDir, err := ensureDumpsDir(projDir)
		if err != nil {
			return err
		}

		filename := fmt.Sprintf("%s_%s.pg_dump", code, dumpTimestamp())
		outPath := filepath.Join(dumpsDir, filename)

		fmt.Printf("Downloading %s from %s@%s ...\n", remoteDB, sshUser, sshHost)

		sshCmd := exec.Command("ssh",
			fmt.Sprintf("%s@%s", sshUser, sshHost),
			fmt.Sprintf("cd statbus && docker compose exec -T db pg_dump -Fc --no-owner --exclude-table-data=auth.secrets -U postgres %s", remoteDB))

		outFile, err := os.Create(outPath)
		if err != nil {
			return fmt.Errorf("create output file: %w", err)
		}
		defer outFile.Close()

		sshCmd.Stdout = outFile
		sshCmd.Stderr = os.Stderr

		if err := sshCmd.Run(); err != nil {
			os.Remove(outPath)
			return fmt.Errorf("remote pg_dump failed: %w", err)
		}

		info, err := os.Stat(outPath)
		if err != nil {
			return err
		}
		if info.Size() == 0 {
			os.Remove(outPath)
			return fmt.Errorf("download produced an empty file — check remote database")
		}

		fmt.Printf("Done: %s (%s)\n", outPath, humanSize(info.Size()))
		warnIfManyDumps(dumpsDir)
		return nil
	},
}

// ── db dumps list ────────────────────────────────────────────────────────────

var dumpsCmd = &cobra.Command{
	Use:   "dumps",
	Short: "Manage database dump files",
}

var dumpsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List database dump files",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		dumpsDir := filepath.Join(projDir, "dbdumps")

		entries, err := filepath.Glob(filepath.Join(dumpsDir, "*.pg_dump"))
		if err != nil {
			return err
		}
		if len(entries) == 0 {
			fmt.Println("No dump files found in dbdumps/")
			return nil
		}

		sort.Strings(entries)
		for _, path := range entries {
			info, err := os.Stat(path)
			if err != nil {
				continue
			}
			fmt.Printf("  %-50s %s\n", filepath.Base(path), humanSize(info.Size()))
		}
		fmt.Printf("\n%d dump file(s)\n", len(entries))
		return nil
	},
}

// ── db dumps purge ───────────────────────────────────────────────────────────

var dumpsPurgeCmd = &cobra.Command{
	Use:   "purge [keep_count]",
	Short: "Delete old dump files, keeping newest N per source (default: 1)",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		dumpsDir := filepath.Join(projDir, "dbdumps")

		keepCount := 1
		if len(args) > 0 {
			n, err := strconv.Atoi(args[0])
			if err != nil || n < 0 {
				return fmt.Errorf("keep_count must be a non-negative integer")
			}
			keepCount = n
		}

		entries, err := filepath.Glob(filepath.Join(dumpsDir, "*.pg_dump"))
		if err != nil {
			return err
		}
		if len(entries) == 0 {
			fmt.Println("No dump files to purge")
			return nil
		}

		// Group by source prefix (everything before the timestamp).
		// Filename pattern: {prefix}_{YYYYMMDD_HHMMSS}.pg_dump
		// The prefix is the part before the last two underscore-separated date/time segments.
		groups := make(map[string][]string)
		for _, path := range entries {
			base := filepath.Base(path)
			// Find the source prefix: everything up to _YYYYMMDD_HHMMSS.pg_dump
			// The timestamp is 15 chars: YYYYMMDD_HHMMSS
			name := strings.TrimSuffix(base, ".pg_dump")
			// Split from the right: the last 15 chars should be the timestamp
			if len(name) > 16 && name[len(name)-15-1] == '_' {
				prefix := name[:len(name)-15-1]
				groups[prefix] = append(groups[prefix], path)
			} else {
				// Can't parse — treat entire name as prefix
				groups[name] = append(groups[name], path)
			}
		}

		// For each group, sort by name (timestamps sort lexically) and mark old ones for deletion.
		var toDelete []string
		for prefix, paths := range groups {
			sort.Strings(paths)
			if len(paths) <= keepCount {
				continue
			}
			// Keep the newest keepCount (last N after sort)
			cutoff := len(paths) - keepCount
			for _, p := range paths[:cutoff] {
				toDelete = append(toDelete, p)
			}
			_ = prefix
		}

		if len(toDelete) == 0 {
			fmt.Println("Nothing to purge")
			return nil
		}

		sort.Strings(toDelete)
		fmt.Println("The following files will be deleted:")
		for _, p := range toDelete {
			info, _ := os.Stat(p)
			size := "?"
			if info != nil {
				size = humanSize(info.Size())
			}
			fmt.Printf("  %-50s %s\n", filepath.Base(p), size)
		}

		if !confirmAction(fmt.Sprintf("Delete %d file(s)?", len(toDelete))) {
			fmt.Println("Aborted")
			return nil
		}

		for _, p := range toDelete {
			if err := os.Remove(p); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: could not remove %s: %v\n", filepath.Base(p), err)
			} else {
				fmt.Printf("  Deleted %s\n", filepath.Base(p))
			}
		}
		fmt.Printf("Purged %d file(s)\n", len(toDelete))
		return nil
	},
}

// ── db restore ───────────────────────────────────────────────────────────────

// restoreSQL contains the 4-phase restore logic shared between local and remote modes.

const deferCheckConstraintsSQL = `
CREATE TABLE public._deferred_checks AS
SELECT n.nspname AS schema_name, c.relname AS table_name,
    con.conname AS constraint_name,
    pg_get_constraintdef(con.oid) AS constraint_def
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE con.contype = 'c'
  AND pg_get_constraintdef(con.oid) ~ '\m[a-z_]+\.[a-z_]+\(';
DO $$ DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM public._deferred_checks
    LOOP
        RAISE NOTICE 'Deferring: %.%.%', r.schema_name, r.table_name, r.constraint_name;
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I', r.schema_name, r.table_name, r.constraint_name);
    END LOOP;
END $$;
`

const reAddCheckConstraintsSQL = `
DO $$ DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM public._deferred_checks
    LOOP
        RAISE NOTICE 'Re-adding: %.%.%', r.schema_name, r.table_name, r.constraint_name;
        EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s', r.schema_name, r.table_name, r.constraint_name, r.constraint_def);
    END LOOP;
END $$;
DROP TABLE public._deferred_checks;
`

// materializeUserRolesSQL replicates the role-creation block of
// auth.sync_user_credentials_and_roles() — see
// migrations/20260129150046_add_email_normalization_trigger.up.sql:78-95.
//
// The trigger fires per row on live INSERT/UPDATE of auth.user, but pg_dump
// places it in post-data, so it is not yet installed when COPY auth.user
// runs during pg_restore. After Phase 2.5 loads auth.user data via plain
// COPY, this block walks the table and materialises the cluster-level
// roles + memberships the trigger would have created. Cluster passwords
// are NOT set here — they aren't in the dump (encrypted_password lives in
// auth.user; the cluster-level password is only set when NEW.password is
// passed in plaintext, which restore can't provide).
const materializeUserRolesSQL = `
DO $$
DECLARE u RECORD;
BEGIN
    FOR u IN SELECT email, statbus_role::text AS sb_role FROM auth.user LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = u.email) THEN
            EXECUTE format('CREATE ROLE %I LOGIN INHERIT', u.email);
            EXECUTE format('GRANT authenticated TO %I', u.email);
            EXECUTE format('GRANT %I TO authenticator', u.email);
            EXECUTE format('GRANT %I TO %I', u.sb_role, u.email);
        END IF;
    END LOOP;
END $$;
`

var dbRestoreCmd = &cobra.Command{
	Use:   "restore <file>",
	Short: "Restore a database dump (locally or to a remote server)",
	Long: `Restore a pg_dump file to a StatBus database.

By default restores to the local database. Use --to <code> to restore
to a remote deployment (e.g., --to dev, --to no).

The restore uses a 4-phase process to handle cross-schema CHECK constraints:
  1. Pre-data (schema only)
  2. Save and drop cross-schema CHECK constraints
  3. Data + post-data (indexes, triggers, etc.)
  4. Re-add the saved CHECK constraints`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		dumpFile := args[0]

		// Resolve bare filename against dbdumps/
		if !filepath.IsAbs(dumpFile) && !strings.Contains(dumpFile, string(os.PathSeparator)) {
			candidate := filepath.Join(projDir, "dbdumps", dumpFile)
			if _, err := os.Stat(candidate); err == nil {
				dumpFile = candidate
			}
		}
		// Also resolve relative paths
		if !filepath.IsAbs(dumpFile) {
			abs, err := filepath.Abs(dumpFile)
			if err == nil {
				dumpFile = abs
			}
		}

		if _, err := os.Stat(dumpFile); err != nil {
			return fmt.Errorf("dump file not found: %s", dumpFile)
		}

		if restoreTo != "" {
			return restoreRemote(projDir, dumpFile, restoreTo)
		}
		return restoreLocal(projDir, dumpFile)
	},
}

func restoreLocal(projDir string, dumpFile string) error {
	dbName, err := loadDbName(projDir)
	if err != nil {
		return err
	}
	if err := validateIdentifier(dbName, "database name"); err != nil {
		return err
	}

	if !dbIsRunning(projDir) {
		return fmt.Errorf("database is not running — start it with 'sb start all'")
	}

	fmt.Printf("Restore %s to local database %s\n", filepath.Base(dumpFile), dbName)
	if !restoreYes && !confirmAction("This will DROP and recreate the database. Continue?") {
		fmt.Println("Aborted")
		return nil
	}

	// Stop worker and rest
	fmt.Println("Stopping worker and rest ...")
	stopServices := exec.Command("docker", "compose", "stop", "worker", "rest")
	stopServices.Dir = projDir
	stopServices.Stdout = os.Stdout
	stopServices.Stderr = os.Stderr
	if err := stopServices.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not stop services: %v\n", err)
	}

	// Terminate connections and drop/create database
	fmt.Println("Dropping and recreating database ...")
	terminateSQL := fmt.Sprintf(`
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '%s' AND pid <> pg_backend_pid();
`, strings.ReplaceAll(dbName, "'", "''"))
	// pgx.Identifier.Sanitize returns the value already wrapped in
	// double quotes with internal " doubled and NULs stripped — the
	// canonical "always use the library's identifier quoting" path.
	// validIdentifier already rejects malformed names upstream, so this
	// is belt-and-suspenders, but uniform for any identifier
	// interpolation in this codebase.
	qDbName := pgx.Identifier{dbName}.Sanitize()
	dropSQL := fmt.Sprintf(`DROP DATABASE IF EXISTS %s;`, qDbName)
	createSQL := fmt.Sprintf(`CREATE DATABASE %s;`, qDbName)

	terminateCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-c", terminateSQL)
	terminateCmd.Dir = projDir
	terminateCmd.Stdout = os.Stdout
	terminateCmd.Stderr = os.Stderr
	terminateCmd.Run() // Ignore error — no connections is fine

	// Use separate -c flags: DROP/CREATE DATABASE cannot run inside a transaction,
	// and a single -c with multiple statements is wrapped in a transaction by psql.
	dropCreateCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-c", dropSQL, "-c", createSQL)
	dropCreateCmd.Dir = projDir
	dropCreateCmd.Stdout = os.Stdout
	dropCreateCmd.Stderr = os.Stderr
	if err := dropCreateCmd.Run(); err != nil {
		return fmt.Errorf("drop/create database failed: %w", err)
	}

	// Copy dump into container once and build TOC lists that reorder ACLs to
	// run AFTER data + post-data. pg_dump files per-relation ACLs in pre-data
	// adjacent to their CREATE TABLE; running them there fails when they
	// reference end-user roles whose names are emails — those roles only
	// exist on production because the auth.user BEFORE INSERT trigger
	// sync_user_credentials_and_roles_trigger creates them on signup. The
	// trigger itself is in post-data (pg_dump default for triggers), so it's
	// NOT installed when auth.user data loads in pg_restore — replaying the
	// trigger pathway via --section=data alone won't work.
	//
	// Pipeline:
	//   Phase 1   pre-data, --no-acl                (schema, no GRANTs)
	//   Phase 2   defer cross-schema CHECKs         (psql)
	//   Phase 2.5 auth.user data ONLY               (pg_restore -L)
	//   Phase 2.6 materialize PG roles per row      (psql, replicates trigger)
	//   Phase 3   data (minus auth.user) + post-data + ACLs in one transaction
	//   Phase 4   re-add CHECKs                     (psql)
	//
	// CREATE ROLE is transactional — Phase 2.6 inside its own psql call commits
	// the roles. Phase 3 runs in its own transaction; if it fails, data rolls
	// back but roles persist (cluster-level). On retry, Phase 2.6 is idempotent
	// (IF NOT EXISTS guard), so the second run is clean.
	fmt.Println("Copying dump into container and building TOC lists ...")
	cpCmd := exec.Command("docker", "compose", "cp", dumpFile, "db:/tmp/restore.pg_dump")
	cpCmd.Dir = projDir
	cpCmd.Stdout = os.Stdout
	cpCmd.Stderr = os.Stderr
	if err := cpCmd.Run(); err != nil {
		return fmt.Errorf("copy dump into container: %w", err)
	}
	defer func() {
		rm := exec.Command("docker", "compose", "exec", "-T", "db",
			"rm", "-f",
			"/tmp/restore.pg_dump",
			"/tmp/restore-data.list",
			"/tmp/restore-data-other.list",
			"/tmp/restore-auth-user.list",
			"/tmp/restore-post.list",
			"/tmp/restore-acl.list",
			"/tmp/restore-phase3.list")
		rm.Dir = projDir
		rm.Run()
	}()

	buildList := exec.Command("docker", "compose", "exec", "-T", "db", "sh", "-c",
		`set -e
pg_restore -l --section=data      /tmp/restore.pg_dump | grep -E '^[0-9]+;'        > /tmp/restore-data.list
pg_restore -l --section=post-data /tmp/restore.pg_dump | grep -E '^[0-9]+;'        > /tmp/restore-post.list
pg_restore -l --section=pre-data  /tmp/restore.pg_dump | grep -E '^[0-9]+;.* ACL ' > /tmp/restore-acl.list

# Split auth.user TABLE DATA out so we can load it BEFORE materializing roles.
# Triggers on auth.user are in post-data and don't exist at data-load time, so
# the role-creation trigger pathway is unavailable; the restore tool replays
# the trigger's role logic in Phase 2.6 against the just-loaded data.
grep    ' TABLE DATA auth user ' /tmp/restore-data.list > /tmp/restore-auth-user.list
grep -v ' TABLE DATA auth user ' /tmp/restore-data.list > /tmp/restore-data-other.list

cat /tmp/restore-data-other.list /tmp/restore-post.list /tmp/restore-acl.list > /tmp/restore-phase3.list`)
	buildList.Dir = projDir
	buildList.Stdout = os.Stdout
	buildList.Stderr = os.Stderr
	if err := buildList.Run(); err != nil {
		return fmt.Errorf("build TOC list: %w", err)
	}

	// Phase 1: pre-data WITHOUT ACLs (deferred to Phase 3).
	fmt.Println("Phase 1: Restoring schema (pre-data, no ACLs) ...")
	phase1 := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_restore", "-U", "postgres", "-d", dbName,
		"--no-owner", "--no-acl", "--single-transaction",
		"--section=pre-data",
		"/tmp/restore.pg_dump")
	phase1.Dir = projDir
	phase1.Stdout = os.Stdout
	phase1.Stderr = os.Stderr
	if err := phase1.Run(); err != nil {
		return fmt.Errorf("phase 1 (pre-data) failed: %w", err)
	}

	// Phase 2: save and drop cross-schema CHECK constraints
	fmt.Println("Phase 2: Deferring cross-schema CHECK constraints ...")
	deferCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-d", dbName, "-c", deferCheckConstraintsSQL)
	deferCmd.Dir = projDir
	deferCmd.Stdout = os.Stdout
	deferCmd.Stderr = os.Stderr
	if err := deferCmd.Run(); err != nil {
		return fmt.Errorf("phase 2 (defer constraints) failed: %w", err)
	}

	// Phase 2.5: Load auth.user data in isolation. Triggers don't exist yet
	// (created in post-data), so no side effects from BEFORE/AFTER triggers
	// fire during this targeted COPY.
	fmt.Println("Phase 2.5: Loading auth.user data ...")
	phase25 := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_restore", "-U", "postgres", "-d", dbName,
		"--no-owner", "--single-transaction",
		"-L", "/tmp/restore-auth-user.list",
		"/tmp/restore.pg_dump")
	phase25.Dir = projDir
	phase25.Stdout = os.Stdout
	phase25.Stderr = os.Stderr
	if err := phase25.Run(); err != nil {
		return fmt.Errorf("phase 2.5 (auth.user data) failed: %w", err)
	}

	// Phase 2.6: Materialize PG roles from auth.user. Replicates the
	// role-creation block of auth.sync_user_credentials_and_roles() (see
	// migrations/20260129150046_add_email_normalization_trigger.up.sql:78-95).
	// Idempotent (IF NOT EXISTS guard) so re-runs after a Phase 3 failure are
	// safe. Drift risk is low — the trigger's role block changes rarely.
	fmt.Println("Phase 2.6: Materializing PG roles from auth.user ...")
	materializeCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-d", dbName,
		"-v", "ON_ERROR_STOP=1",
		"-c", materializeUserRolesSQL)
	materializeCmd.Dir = projDir
	materializeCmd.Stdout = os.Stdout
	materializeCmd.Stderr = os.Stderr
	if err := materializeCmd.Run(); err != nil {
		return fmt.Errorf("phase 2.6 (materialize roles) failed: %w", err)
	}

	// Phase 3: remaining data + post-data + ACLs in one transaction. ACLs run
	// last in the TOC list order, after every grantee role has been created.
	fmt.Println("Phase 3: Restoring remaining data + post-data + ACLs (single transaction) ...")
	phase3 := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_restore", "-U", "postgres", "-d", dbName,
		"--no-owner", "--single-transaction",
		"-L", "/tmp/restore-phase3.list",
		"/tmp/restore.pg_dump")
	phase3.Dir = projDir
	phase3.Stdout = os.Stdout
	phase3.Stderr = os.Stderr
	if err := phase3.Run(); err != nil {
		return fmt.Errorf("phase 3 (data + post-data + ACLs) failed: %w", err)
	}

	// Phase 4: re-add CHECK constraints
	fmt.Println("Phase 4: Re-adding cross-schema CHECK constraints ...")
	reAddCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-d", dbName, "-c", reAddCheckConstraintsSQL)
	reAddCmd.Dir = projDir
	reAddCmd.Stdout = os.Stdout
	reAddCmd.Stderr = os.Stderr
	if err := reAddCmd.Run(); err != nil {
		return fmt.Errorf("phase 4 (re-add constraints) failed: %w", err)
	}

	// Reload JWT secret from credentials
	fmt.Println("Reloading JWT secret ...")
	credsFile, err := dotenv.Load(filepath.Join(projDir, ".env.credentials"))
	if err == nil {
		if jwtSecret, ok := credsFile.Get("JWT_SECRET"); ok && jwtSecret != "" {
			jwtSQL := fmt.Sprintf(`
DO $$ BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'auth' AND tablename = 'secrets') THEN
    UPDATE auth.secrets SET value = '%s' WHERE key = 'jwt_secret';
  END IF;
END $$;
`, strings.ReplaceAll(jwtSecret, "'", "''"))
			jwtCmd := exec.Command("docker", "compose", "exec", "-T", "db",
				"psql", "-U", "postgres", "-d", dbName, "-c", jwtSQL)
			jwtCmd.Dir = projDir
			jwtCmd.Stdout = os.Stdout
			jwtCmd.Stderr = os.Stderr
			jwtCmd.Run()
		}
	}

	// Set deployment_slot_code as a per-database GUC. Consumed by
	// auth/...:1312 via current_setting('app.settings.deployment_slot_code',
	// true). Public.settings was never a (key,value) table — that shape was
	// fabricated by an earlier port; see migrations/0010_create_table_settings.up.sql
	// for the real columnar schema.
	slotCode, err := loadSlotCode(projDir)
	if err == nil {
		if err := validateIdentifier(slotCode, "slot code"); err != nil {
			return err
		}
		// validateIdentifier guarantees [a-zA-Z][a-zA-Z0-9_]*, so single-quote
		// wrapping is safe; qDbName is already sanitized as an identifier.
		slotSQL := fmt.Sprintf(`ALTER DATABASE %s SET app.settings.deployment_slot_code TO '%s';`,
			qDbName, slotCode)
		slotCmd := exec.Command("docker", "compose", "exec", "-T", "db",
			"psql", "-U", "postgres", "-c", slotSQL)
		slotCmd.Dir = projDir
		slotCmd.Stdout = os.Stdout
		slotCmd.Stderr = os.Stderr
		if err := slotCmd.Run(); err != nil {
			return fmt.Errorf("set deployment_slot_code failed: %w", err)
		}
	}

	// Re-apply local .users.yml so the operator can sign in again. Restore
	// replaces auth.user with the source deployment's rows; the bcrypt
	// hashes in encrypted_password are theirs (and cluster role passwords
	// aren't in the dump at all). Upserting via public.user_create() fires
	// the auth.user trigger, which resets encrypted_password to bcrypt of
	// the .users.yml password and runs ALTER ROLE %I WITH PASSWORD %L on
	// the cluster role. Skipped silently if .users.yml is absent.
	if _, err := os.Stat(filepath.Join(projDir, ".users.yml")); err == nil {
		fmt.Println("Re-applying .users.yml so local sign-in works ...")
		if err := applyUsersYML(projDir); err != nil {
			return fmt.Errorf("apply .users.yml: %w", err)
		}
	}

	// Restart worker and rest
	fmt.Println("Restarting worker and rest ...")
	startServices := exec.Command("docker", "compose", "start", "worker", "rest")
	startServices.Dir = projDir
	startServices.Stdout = os.Stdout
	startServices.Stderr = os.Stderr
	if err := startServices.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not restart services: %v\n", err)
	}

	fmt.Println("Restore complete")
	return nil
}

func restoreRemote(projDir string, dumpFile string, code string) error {
	if err := validateIdentifier(code, "slot code"); err != nil {
		return err
	}
	sshUser := "statbus_" + code
	sshHost := "niue.statbus.org"
	remoteDB := "statbus_" + code

	fmt.Printf("Restore %s to remote %s (%s@%s)\n", filepath.Base(dumpFile), remoteDB, sshUser, sshHost)
	if !restoreYes && !confirmAction("This will DROP and recreate the REMOTE database. Continue?") {
		fmt.Println("Aborted")
		return nil
	}

	// Check SSH connectivity
	fmt.Printf("Checking SSH connectivity to %s@%s ...\n", sshUser, sshHost)
	sshCheck := exec.Command("ssh",
		"-o", "ConnectTimeout=10",
		"-o", "BatchMode=yes",
		fmt.Sprintf("%s@%s", sshUser, sshHost),
		"echo ok")
	if out, err := sshCheck.CombinedOutput(); err != nil {
		return fmt.Errorf("SSH connection failed: %w\n%s", err, string(out))
	}

	// Upload dump file via scp
	remotePath := fmt.Sprintf("statbus/dbdumps/%s", filepath.Base(dumpFile))
	fmt.Printf("Uploading %s ...\n", filepath.Base(dumpFile))

	// Ensure remote dbdumps/ directory exists
	mkdirCmd := exec.Command("ssh",
		fmt.Sprintf("%s@%s", sshUser, sshHost),
		"mkdir -p statbus/dbdumps")
	mkdirCmd.Stderr = os.Stderr
	if err := mkdirCmd.Run(); err != nil {
		return fmt.Errorf("create remote dbdumps directory: %w", err)
	}

	scpCmd := exec.Command("scp", dumpFile,
		fmt.Sprintf("%s@%s:%s", sshUser, sshHost, remotePath))
	scpCmd.Stdout = os.Stdout
	scpCmd.Stderr = os.Stderr
	if err := scpCmd.Run(); err != nil {
		return fmt.Errorf("scp upload failed: %w", err)
	}

	// Build the remote restore script as a heredoc
	remoteScript := fmt.Sprintf(`set -e
cd statbus

echo "Stopping worker and rest ..."
docker compose stop worker rest || true

echo "Terminating connections and recreating database ..."
docker compose exec -T db psql -U postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '%[1]s' AND pid <> pg_backend_pid();
" || true

docker compose exec -T db psql -U postgres \
    -c 'DROP DATABASE IF EXISTS %[4]s;' \
    -c 'CREATE DATABASE %[4]s;'

echo "Copying dump into container and building TOC lists ..."
docker compose cp dbdumps/%[2]s db:/tmp/restore.pg_dump
docker compose exec -T db sh -c '
set -e
pg_restore -l --section=data      /tmp/restore.pg_dump | grep -E "^[0-9]+;"        > /tmp/restore-data.list
pg_restore -l --section=post-data /tmp/restore.pg_dump | grep -E "^[0-9]+;"        > /tmp/restore-post.list
pg_restore -l --section=pre-data  /tmp/restore.pg_dump | grep -E "^[0-9]+;.* ACL " > /tmp/restore-acl.list
grep    " TABLE DATA auth user " /tmp/restore-data.list > /tmp/restore-auth-user.list
grep -v " TABLE DATA auth user " /tmp/restore-data.list > /tmp/restore-data-other.list
cat /tmp/restore-data-other.list /tmp/restore-post.list /tmp/restore-acl.list > /tmp/restore-phase3.list
'

echo "Phase 1: Restoring schema (pre-data, no ACLs) ..."
docker compose exec -T db pg_restore -U postgres -d %[1]s \
    --no-owner --no-acl --single-transaction \
    --section=pre-data /tmp/restore.pg_dump

echo "Phase 2: Deferring cross-schema CHECK constraints ..."
docker compose exec -T db psql -U postgres -d %[1]s -c "
CREATE TABLE public._deferred_checks AS
SELECT n.nspname AS schema_name, c.relname AS table_name,
    con.conname AS constraint_name,
    pg_get_constraintdef(con.oid) AS constraint_def
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE con.contype = 'c'
  AND pg_get_constraintdef(con.oid) ~ '\m[a-z_]+\.[a-z_]+\(';
DO \$\$ DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM public._deferred_checks
    LOOP
        RAISE NOTICE 'Deferring: %%.%%.%%', r.schema_name, r.table_name, r.constraint_name;
        EXECUTE format('ALTER TABLE %%I.%%I DROP CONSTRAINT %%I', r.schema_name, r.table_name, r.constraint_name);
    END LOOP;
END \$\$;
"

echo "Phase 2.5: Loading auth.user data ..."
docker compose exec -T db pg_restore -U postgres -d %[1]s \
    --no-owner --single-transaction \
    -L /tmp/restore-auth-user.list /tmp/restore.pg_dump

echo "Phase 2.6: Materializing PG roles from auth.user ..."
docker compose exec -T db psql -U postgres -d %[1]s -v ON_ERROR_STOP=1 -c "
DO \$\$
DECLARE u RECORD;
BEGIN
    FOR u IN SELECT email, statbus_role::text AS sb_role FROM auth.user LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = u.email) THEN
            EXECUTE format('CREATE ROLE %%I LOGIN INHERIT', u.email);
            EXECUTE format('GRANT authenticated TO %%I', u.email);
            EXECUTE format('GRANT %%I TO authenticator', u.email);
            EXECUTE format('GRANT %%I TO %%I', u.sb_role, u.email);
        END IF;
    END LOOP;
END \$\$;
"

echo "Phase 3: Restoring remaining data + post-data + ACLs (single transaction) ..."
docker compose exec -T db pg_restore -U postgres -d %[1]s \
    --no-owner --single-transaction \
    -L /tmp/restore-phase3.list /tmp/restore.pg_dump

echo "Phase 4: Re-adding cross-schema CHECK constraints ..."
docker compose exec -T db psql -U postgres -d %[1]s -c "
DO \$\$ DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM public._deferred_checks
    LOOP
        RAISE NOTICE 'Re-adding: %%.%%.%%', r.schema_name, r.table_name, r.constraint_name;
        EXECUTE format('ALTER TABLE %%I.%%I ADD CONSTRAINT %%I %%s', r.schema_name, r.table_name, r.constraint_name, r.constraint_def);
    END LOOP;
END \$\$;
DROP TABLE public._deferred_checks;
"

docker compose exec -T db rm -f \
    /tmp/restore.pg_dump \
    /tmp/restore-data.list /tmp/restore-data-other.list /tmp/restore-auth-user.list \
    /tmp/restore-post.list /tmp/restore-acl.list /tmp/restore-phase3.list

echo "Setting deployment_slot_code ..."
docker compose exec -T db psql -U postgres -c \
    "ALTER DATABASE %[4]s SET app.settings.deployment_slot_code TO '%[3]s';"

echo "Restarting worker and rest ..."
docker compose start worker rest || true

echo "Cleaning up uploaded dump ..."
rm -f dbdumps/%[2]s

echo "Restore complete"
`, remoteDB, filepath.Base(dumpFile), code, pgx.Identifier{remoteDB}.Sanitize())

	fmt.Println("Running remote restore ...")
	sshRestore := exec.Command("ssh",
		fmt.Sprintf("%s@%s", sshUser, sshHost),
		"bash", "-s")
	sshRestore.Stdin = strings.NewReader(remoteScript)
	sshRestore.Stdout = os.Stdout
	sshRestore.Stderr = os.Stderr
	if err := sshRestore.Run(); err != nil {
		return fmt.Errorf("remote restore failed: %w", err)
	}

	return nil
}

// ── db backup ─────────────────────────────────────────────────────────────────

// backupTimestamp returns a filename-safe ISO-ish timestamp: 2006-01-02T15-04-05.
func backupTimestamp() string {
	return time.Now().Format("2006-01-02T15-04-05")
}

// loadVolumeName reads COMPOSE_INSTANCE_NAME from .env and derives the Docker volume name.
func loadVolumeName(projDir string) (string, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return "", fmt.Errorf("load .env: %w", err)
	}
	name, ok := f.Get("COMPOSE_INSTANCE_NAME")
	if !ok || name == "" {
		return "", fmt.Errorf("COMPOSE_INSTANCE_NAME not set in .env")
	}
	return name + "-db-data", nil
}

// backupsDir returns ~/statbus-backups, creating it if needed.
func backupsDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("determine home directory: %w", err)
	}
	dir := filepath.Join(home, "statbus-backups")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("create backups directory: %w", err)
	}
	return dir, nil
}

// dockerComposeStop stops a docker compose profile (e.g., "all" or specific service).
func dockerComposeStop(projDir string, profileOrService string) error {
	var cmd *exec.Cmd
	if profileOrService == "db" || profileOrService == "worker" || profileOrService == "rest" || profileOrService == "app" {
		cmd = exec.Command("docker", "compose", "stop", profileOrService)
	} else {
		cmd = exec.Command("docker", "compose", "--profile", profileOrService, "down", "--remove-orphans")
	}
	cmd.Dir = projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// dockerComposeStart starts a docker compose profile.
func dockerComposeStart(projDir string, profileOrService string) error {
	var cmd *exec.Cmd
	if profileOrService == "db" || profileOrService == "worker" || profileOrService == "rest" || profileOrService == "app" {
		cmd = exec.Command("docker", "compose", "start", profileOrService)
	} else {
		cmd = exec.Command("docker", "compose", "--profile", profileOrService, "up", "-d")
	}
	cmd.Dir = projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

var backupCmd = &cobra.Command{
	Use:   "backup",
	Short: "Manage volume-level database backups",
	Long: `Manage volume-level database backups via rsync.

These backups copy the raw PostgreSQL data directory from the Docker named volume,
providing a complete snapshot that can be restored without pg_dump/pg_restore.

Backups are stored as tar.gz archives in ~/statbus-backups/.

Subcommands:
  create    Create a new backup (stops db briefly)
  restore   Restore a backup to the Docker volume
  list      List available backup archives
  purge     Delete old archives`,
}

var backupCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create a volume-level backup of the database",
	Long: `Stop the database, rsync the Docker volume to a local directory,
restart the database, then archive to a tar.gz file.

The database will be briefly unavailable during the rsync.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		volumeName, err := loadVolumeName(projDir)
		if err != nil {
			return err
		}

		bkDir, err := backupsDir()
		if err != nil {
			return err
		}

		ts := backupTimestamp()
		stagingDir := filepath.Join(bkDir, "staging")

		// Create staging directory
		if err := os.MkdirAll(stagingDir, 0755); err != nil {
			return fmt.Errorf("create staging directory: %w", err)
		}

		// Step 1: Stop the database for a consistent backup
		fmt.Println("Stopping database ...")
		if err := dockerComposeStop(projDir, "db"); err != nil {
			return fmt.Errorf("stop database: %w", err)
		}

		// Step 2: rsync from Docker volume to staging directory
		fmt.Printf("Copying volume %s to staging ...\n", volumeName)
		rsyncCmd := exec.Command("docker", "run", "--rm",
			"-v", volumeName+":/source:ro",
			"-v", stagingDir+":/backup",
			"alpine", "sh", "-c",
			"apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /source/ /backup/",
		)
		rsyncCmd.Dir = projDir
		rsyncCmd.Stdout = os.Stdout
		rsyncCmd.Stderr = os.Stderr
		if err := rsyncCmd.Run(); err != nil {
			// Try to restart db even if rsync fails
			fmt.Println("Restarting database after rsync failure ...")
			dockerComposeStart(projDir, "db")
			return fmt.Errorf("rsync from volume failed: %w", err)
		}

		// Step 3: Restart the database
		fmt.Println("Restarting database ...")
		if err := dockerComposeStart(projDir, "db"); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not restart database: %v\n", err)
		}

		// Step 4: Archive to tar.gz
		archiveName := fmt.Sprintf("backup-%s.tar.gz", ts)
		archivePath := filepath.Join(bkDir, archiveName)
		fmt.Printf("Archiving to %s ...\n", archiveName)
		tarCmd := exec.Command("tar", "-czf", archivePath,
			"-C", bkDir, "staging")
		tarCmd.Stdout = os.Stdout
		tarCmd.Stderr = os.Stderr
		if err := tarCmd.Run(); err != nil {
			return fmt.Errorf("tar archive failed: %w", err)
		}

		// Clean up staging directory
		os.RemoveAll(stagingDir)

		info, err := os.Stat(archivePath)
		if err != nil {
			return err
		}

		fmt.Printf("Done: %s (%s)\n", archivePath, humanSize(info.Size()))
		return nil
	},
}

var backupRestoreCmd = &cobra.Command{
	Use:   "restore <name>",
	Short: "Restore a volume-level backup",
	Long: `Stop all services, extract the backup archive, rsync to the Docker volume,
then restart all services.

The name can be a full filename (backup-2026-03-27T14-30-00.tar.gz),
a basename without extension, or just the timestamp portion.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		name := args[0]

		volumeName, err := loadVolumeName(projDir)
		if err != nil {
			return err
		}

		bkDir, err := backupsDir()
		if err != nil {
			return err
		}

		// Resolve the archive path
		archivePath, err := resolveBackupArchive(bkDir, name)
		if err != nil {
			return err
		}

		fmt.Printf("Restore %s to volume %s\n", filepath.Base(archivePath), volumeName)
		if !confirmAction("This will REPLACE the database volume contents. Continue?") {
			fmt.Println("Aborted")
			return nil
		}

		stagingDir := filepath.Join(bkDir, "staging")

		// Clean staging first
		os.RemoveAll(stagingDir)

		// Step 1: Extract archive to staging
		fmt.Printf("Extracting %s ...\n", filepath.Base(archivePath))
		tarCmd := exec.Command("tar", "-xzf", archivePath, "-C", bkDir)
		tarCmd.Stdout = os.Stdout
		tarCmd.Stderr = os.Stderr
		if err := tarCmd.Run(); err != nil {
			return fmt.Errorf("extract archive failed: %w", err)
		}

		// Step 2: Stop all services
		fmt.Println("Stopping all services ...")
		if err := dockerComposeStop(projDir, "all"); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not stop all services: %v\n", err)
		}

		// Step 3: rsync from staging to Docker volume
		fmt.Printf("Restoring to volume %s ...\n", volumeName)
		rsyncCmd := exec.Command("docker", "run", "--rm",
			"-v", stagingDir+":/source:ro",
			"-v", volumeName+":/dest",
			"alpine", "sh", "-c",
			"apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /source/ /dest/",
		)
		rsyncCmd.Dir = projDir
		rsyncCmd.Stdout = os.Stdout
		rsyncCmd.Stderr = os.Stderr
		if err := rsyncCmd.Run(); err != nil {
			return fmt.Errorf("rsync to volume failed: %w", err)
		}

		// Clean up staging
		os.RemoveAll(stagingDir)

		// Step 4: Start all services
		fmt.Println("Starting all services ...")
		if err := dockerComposeStart(projDir, "all"); err != nil {
			return fmt.Errorf("start services: %w", err)
		}

		fmt.Println("Restore complete")
		return nil
	},
}

// resolveBackupArchive finds the archive file matching a user-provided name.
// Accepts: full filename, basename without .tar.gz, or just a timestamp.
func resolveBackupArchive(bkDir, name string) (string, error) {
	// Try exact path first
	if filepath.IsAbs(name) {
		if _, err := os.Stat(name); err == nil {
			return name, nil
		}
	}

	// Try as-is in backup directory
	candidate := filepath.Join(bkDir, name)
	if _, err := os.Stat(candidate); err == nil {
		return candidate, nil
	}

	// Try with .tar.gz suffix
	candidate = filepath.Join(bkDir, name+".tar.gz")
	if _, err := os.Stat(candidate); err == nil {
		return candidate, nil
	}

	// Try with backup- prefix and .tar.gz suffix
	candidate = filepath.Join(bkDir, "backup-"+name+".tar.gz")
	if _, err := os.Stat(candidate); err == nil {
		return candidate, nil
	}

	return "", fmt.Errorf("backup archive not found: %s\nRun 'sb db backup list' to see available backups", name)
}

var backupListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available backup archives",
	RunE: func(cmd *cobra.Command, args []string) error {
		bkDir, err := backupsDir()
		if err != nil {
			return err
		}

		entries, err := filepath.Glob(filepath.Join(bkDir, "*.tar.gz"))
		if err != nil {
			return err
		}
		if len(entries) == 0 {
			fmt.Printf("No backup archives found in %s\n", bkDir)
			return nil
		}

		sort.Strings(entries)
		fmt.Printf("Backup archives in %s:\n\n", bkDir)
		for _, path := range entries {
			info, err := os.Stat(path)
			if err != nil {
				continue
			}
			fmt.Printf("  %-45s %8s  %s\n",
				filepath.Base(path),
				humanSize(info.Size()),
				info.ModTime().Format("2006-01-02 15:04:05"),
			)
		}
		fmt.Printf("\n%d archive(s)\n", len(entries))
		return nil
	},
}

var backupPurgeCmd = &cobra.Command{
	Use:   "purge",
	Short: "Delete old backup archives, keeping newest N (default 7)",
	RunE: func(cmd *cobra.Command, args []string) error {
		bkDir, err := backupsDir()
		if err != nil {
			return err
		}

		entries, err := filepath.Glob(filepath.Join(bkDir, "*.tar.gz"))
		if err != nil {
			return err
		}
		if len(entries) == 0 {
			fmt.Println("No backup archives to purge")
			return nil
		}

		if len(entries) <= backupKeep {
			fmt.Printf("Only %d archive(s), keeping all (--keep %d)\n", len(entries), backupKeep)
			return nil
		}

		// Sort lexically — timestamps sort correctly
		sort.Strings(entries)
		toDelete := entries[:len(entries)-backupKeep]

		fmt.Println("The following archives will be deleted:")
		var totalSize int64
		for _, p := range toDelete {
			info, _ := os.Stat(p)
			size := "?"
			if info != nil {
				size = humanSize(info.Size())
				totalSize += info.Size()
			}
			fmt.Printf("  %-45s %s\n", filepath.Base(p), size)
		}
		fmt.Printf("\n%d archive(s), %s total\n", len(toDelete), humanSize(totalSize))

		if !confirmAction(fmt.Sprintf("Delete %d archive(s)?", len(toDelete))) {
			fmt.Println("Aborted")
			return nil
		}

		for _, p := range toDelete {
			if err := os.Remove(p); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: could not remove %s: %v\n", filepath.Base(p), err)
			} else {
				fmt.Printf("  Deleted %s\n", filepath.Base(p))
			}
		}
		fmt.Printf("Purged %d archive(s)\n", len(toDelete))
		return nil
	},
}

// ── init ─────────────────────────────────────────────────────────────────────

func init() {
	dbRestoreCmd.Flags().StringVar(&restoreTo, "to", "", "remote deployment slot code to restore to (e.g., dev, no, demo)")
	dbRestoreCmd.Flags().BoolVar(&restoreYes, "yes", false, "skip confirmation prompt")

	dumpsCmd.AddCommand(dumpsListCmd)
	dumpsCmd.AddCommand(dumpsPurgeCmd)

	backupPurgeCmd.Flags().IntVar(&backupKeep, "keep", 7, "number of newest archives to keep")
	backupCmd.AddCommand(backupCreateCmd)
	backupCmd.AddCommand(backupRestoreCmd)
	backupCmd.AddCommand(backupListCmd)
	backupCmd.AddCommand(backupPurgeCmd)

	dbCmd.AddCommand(dbStatusCmd)
	dbCmd.AddCommand(dbDumpCmd)
	dbCmd.AddCommand(dbDownloadCmd)
	dbCmd.AddCommand(dumpsCmd)
	dbCmd.AddCommand(dbRestoreCmd)
	dbCmd.AddCommand(backupCmd)

	rootCmd.AddCommand(dbCmd)
}
