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

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

var (
	restoreTo  string
	restoreYes bool

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
	dropCreateSQL := fmt.Sprintf(`
DROP DATABASE IF EXISTS "%s";
CREATE DATABASE "%s";
`, dbName, dbName)

	terminateCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-c", terminateSQL)
	terminateCmd.Dir = projDir
	terminateCmd.Stdout = os.Stdout
	terminateCmd.Stderr = os.Stderr
	terminateCmd.Run() // Ignore error — no connections is fine

	dropCreateCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", "postgres", "-c", dropCreateSQL)
	dropCreateCmd.Dir = projDir
	dropCreateCmd.Stdout = os.Stdout
	dropCreateCmd.Stderr = os.Stderr
	if err := dropCreateCmd.Run(); err != nil {
		return fmt.Errorf("drop/create database failed: %w", err)
	}

	// Phase 1: pre-data (schema only)
	fmt.Println("Phase 1: Restoring schema (pre-data) ...")
	phase1File, err := os.Open(dumpFile)
	if err != nil {
		return err
	}
	phase1 := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_restore", "-U", "postgres", "-d", dbName,
		"--no-owner", "--section=pre-data")
	phase1.Dir = projDir
	phase1.Stdin = phase1File
	phase1.Stdout = os.Stdout
	phase1.Stderr = os.Stderr
	if err := phase1.Run(); err != nil {
		phase1File.Close()
		return fmt.Errorf("phase 1 (pre-data) failed: %w", err)
	}
	phase1File.Close()

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

	// Phase 3: data + post-data
	fmt.Println("Phase 3: Restoring data and post-data ...")
	phase3File, err := os.Open(dumpFile)
	if err != nil {
		return err
	}
	phase3 := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_restore", "-U", "postgres", "-d", dbName,
		"--no-owner", "--section=data", "--section=post-data",
		"--disable-triggers")
	phase3.Dir = projDir
	phase3.Stdin = phase3File
	phase3.Stdout = os.Stdout
	phase3.Stderr = os.Stderr
	if err := phase3.Run(); err != nil {
		phase3File.Close()
		// pg_restore may return non-zero for warnings — log but continue
		fmt.Fprintf(os.Stderr, "Warning: phase 3 exited with: %v (continuing)\n", err)
	}
	phase3File.Close()

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

	// Set deployment_slot_code
	slotCode, err := loadSlotCode(projDir)
	if err == nil {
		if err := validateIdentifier(slotCode, "slot code"); err != nil {
			return err
		}
		escapedSlot := strings.ReplaceAll(slotCode, "'", "''")
		slotSQL := fmt.Sprintf(`
DO $$ BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'settings') THEN
    UPDATE public.settings SET value = '%s' WHERE key = 'deployment_slot_code';
    IF NOT FOUND THEN
      INSERT INTO public.settings (key, value) VALUES ('deployment_slot_code', '%s');
    END IF;
  END IF;
END $$;
`, escapedSlot, escapedSlot)
		slotCmd := exec.Command("docker", "compose", "exec", "-T", "db",
			"psql", "-U", "postgres", "-d", dbName, "-c", slotSQL)
		slotCmd.Dir = projDir
		slotCmd.Stdout = os.Stdout
		slotCmd.Stderr = os.Stderr
		slotCmd.Run()
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

docker compose exec -T db psql -U postgres -c "
DROP DATABASE IF EXISTS \"%[1]s\";
CREATE DATABASE \"%[1]s\";
"

echo "Phase 1: Restoring schema (pre-data) ..."
docker compose exec -T db pg_restore -U postgres -d %[1]s \
    --no-owner --section=pre-data < dbdumps/%[2]s

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

echo "Phase 3: Restoring data and post-data ..."
docker compose exec -T db pg_restore -U postgres -d %[1]s \
    --no-owner --section=data --section=post-data \
    --disable-triggers < dbdumps/%[2]s || true

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

echo "Setting deployment_slot_code ..."
docker compose exec -T db psql -U postgres -d %[1]s -c "
DO \$\$ BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'settings') THEN
    UPDATE public.settings SET value = '%[3]s' WHERE key = 'deployment_slot_code';
    IF NOT FOUND THEN
      INSERT INTO public.settings (key, value) VALUES ('deployment_slot_code', '%[3]s');
    END IF;
  END IF;
END \$\$;
"

echo "Restarting worker and rest ..."
docker compose start worker rest || true

echo "Cleaning up uploaded dump ..."
rm -f dbdumps/%[2]s

echo "Restore complete"
`, remoteDB, filepath.Base(dumpFile), code)

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

// ── init ─────────────────────────────────────────────────────────────────────

func init() {
	dbRestoreCmd.Flags().StringVar(&restoreTo, "to", "", "remote deployment slot code to restore to (e.g., dev, no, demo)")
	dbRestoreCmd.Flags().BoolVar(&restoreYes, "yes", false, "skip confirmation prompt")

	dumpsCmd.AddCommand(dumpsListCmd)
	dumpsCmd.AddCommand(dumpsPurgeCmd)

	dbCmd.AddCommand(dbStatusCmd)
	dbCmd.AddCommand(dbDumpCmd)
	dbCmd.AddCommand(dbDownloadCmd)
	dbCmd.AddCommand(dumpsCmd)
	dbCmd.AddCommand(dbRestoreCmd)

	rootCmd.AddCommand(dbCmd)
}
