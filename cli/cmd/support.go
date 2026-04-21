package cmd

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// supportCmd is the parent group for diagnostic operations.
// The subcommands below are the "lifeline" toolkit — they must work
// even when the database is unreachable and the upgrade service is down.
var supportCmd = &cobra.Command{
	Use:   "support",
	Short: "Operator diagnostics (gather support bundle, write admin-UI state)",
	Long: `Diagnostic operations that work without a running database.

Subcommands are the "lifeline" toolkit invoked by install.sh on failure
and by operators during incident response:

  ./sb support gather            Write a self-contained plain-text diagnostic bundle.
  ./sb support write-admin-ui-row  Record a fresh-install failure for the admin UI.`,
}

// --- gather ---------------------------------------------------------------

var (
	supportGatherOut     string
	supportGatherTrigger string
)

var supportGatherCmd = &cobra.Command{
	Use:   "gather",
	Short: "Write a diagnostic bundle to a file (no database required)",
	Long: `Collect diagnostic information into a self-contained plain-text bundle.

The bundle includes:
  - Upgrade row data (best-effort from the most recent log)
  - Install-terminal.txt (named invariant that drove termination, if any)
  - Registered runtime invariants (for forward-compat diagnostics)
  - Log tail from the latest upgrade log
  - docker compose ps
  - journalctl tail (if available)
  - git log
  - caddy config
  - Redacted .env (secrets replaced with ***REDACTED***)

This command works without a running database. It is the "lifeline" tool
when a server is unresponsive and the upgrade service cannot write its own
bundle.

The --trigger flag identifies the path that asked for the bundle so SSB
triage knows which upstream contract to hold it against:

  install   install.sh caught a non-zero exit from ./sb install (default)
  adhoc     operator-initiated during incident response

The output file defaults to ./support-bundle-<timestamp>.txt. Use --out to
specify a different path. The absolute path is printed to stdout on
success so install.sh can capture it for the SYSTEM UNUSABLE banner.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		var trig upgrade.Trigger
		switch supportGatherTrigger {
		case "install":
			trig = upgrade.TriggerInstall
		case "adhoc":
			trig = upgrade.TriggerAdhoc
		default:
			return fmt.Errorf("invalid --trigger %q: must be install or adhoc", supportGatherTrigger)
		}

		logPath := latestUpgradeLog(projDir)

		outPath := supportGatherOut
		if outPath == "" {
			stamp := time.Now().UTC().Format("20060102-150405")
			outPath = filepath.Join(projDir, fmt.Sprintf("support-bundle-%s.txt", stamp))
		}

		tmpPath := outPath + ".tmp"
		f, err := os.Create(tmpPath)
		if err != nil {
			return fmt.Errorf("create %s: %w", tmpPath, err)
		}
		bw := bufio.NewWriter(f)

		// No live DB row — pass an empty JSON object so WriteBundleSections
		// can still emit the header with "id=0 commit= state=".
		upgrade.WriteBundleSections(context.Background(), bw, projDir, 0, "{}", logPath, trig)

		if err := bw.Flush(); err != nil {
			f.Close()
			os.Remove(tmpPath)
			return fmt.Errorf("flush: %w", err)
		}
		if err := f.Sync(); err != nil {
			f.Close()
			os.Remove(tmpPath)
			return fmt.Errorf("fsync: %w", err)
		}
		f.Close()
		if err := os.Rename(tmpPath, outPath); err != nil {
			os.Remove(tmpPath)
			return fmt.Errorf("rename: %w", err)
		}

		// stdout: absolute path only — install.sh captures it.
		// stderr: human-readable confirmation.
		fmt.Println(outPath)
		fmt.Fprintf(os.Stderr, "Support bundle written to %s\n", outPath)
		return nil
	},
}

// latestUpgradeLog returns the absolute path of the most recent upgrade log.
// Uses the upgrade-progress.log symlink if it resolves to an existing file,
// otherwise picks the lexicographically last .log file in tmp/upgrade-logs/.
// Returns an empty string if no log is found (WriteBundleSections will
// insert a "(log unavailable)" placeholder for that section).
func latestUpgradeLog(projDir string) string {
	symlinkPath := filepath.Join(projDir, "tmp", "upgrade-progress.log")
	if resolved, err := filepath.EvalSymlinks(symlinkPath); err == nil {
		if _, err := os.Stat(resolved); err == nil {
			return resolved
		}
	}

	logsDir := filepath.Join(projDir, "tmp", "upgrade-logs")
	entries, err := os.ReadDir(logsDir)
	if err != nil {
		return ""
	}
	var logs []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".log") {
			logs = append(logs, filepath.Join(logsDir, e.Name()))
		}
	}
	if len(logs) == 0 {
		return ""
	}
	sort.Strings(logs)
	return logs[len(logs)-1]
}

// --- write-admin-ui-row ---------------------------------------------------

var (
	supportWriteAdminRowMessage    string
	supportWriteAdminRowBundlePath string
	supportWriteAdminRowTimeoutSec int
)

var supportWriteAdminRowCmd = &cobra.Command{
	Use:   "write-admin-ui-row",
	Short: "Record a fresh-install failure in public.system_info (if DB reachable)",
	Long: `Write install_last_error + install_last_error_at to public.system_info so
the admin UI can surface a fresh-install-failure banner on its next load.

Called by install.sh after a failed ./sb install, regardless of whether
the failure happened before or after the database was reachable. If the
database is not reachable within --timeout seconds this command prints a
note to stderr and exits 0 — install.sh still has the plain-text bundle
and the SYSTEM UNUSABLE terminal banner, so DB-side state is strictly
additive.

The --message value is typically the invariant name + observed state
extracted from install-terminal.txt, or a short free-text message
when no named invariant fired. The --bundle-path value is stored as a
separate key so the admin UI can link an operator to the on-disk path.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if supportWriteAdminRowMessage == "" {
			return fmt.Errorf("--message is required")
		}
		projDir := config.ProjectDir()

		timeout := time.Duration(supportWriteAdminRowTimeoutSec) * time.Second
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		defer cancel()

		connStr, err := migrate.AdminConnStr(projDir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "write-admin-ui-row: skipped (no admin connection string: %v)\n", err)
			return nil
		}
		conn, err := pgx.Connect(ctx, connStr)
		if err != nil {
			fmt.Fprintf(os.Stderr, "write-admin-ui-row: skipped (DB unreachable within %s: %v)\n", timeout, err)
			return nil
		}
		defer conn.Close(context.Background())

		// Upsert three keys atomically. If the install actually succeeded
		// later, the upgrade-service completion path clears these (that
		// lives in Phase 4 — install success clears install_last_error).
		const sql = `
			INSERT INTO public.system_info (key, value) VALUES
				('install_last_error', $1),
				('install_last_error_at', clock_timestamp()::text),
				('install_last_bundle_path', $2)
			ON CONFLICT (key) DO UPDATE SET
				value = EXCLUDED.value,
				updated_at = clock_timestamp()
		`
		if _, err := conn.Exec(ctx, sql, supportWriteAdminRowMessage, supportWriteAdminRowBundlePath); err != nil {
			fmt.Fprintf(os.Stderr, "write-admin-ui-row: failed (upsert error: %v)\n", err)
			return nil
		}
		fmt.Fprintln(os.Stderr, "write-admin-ui-row: system_info keys updated")
		return nil
	},
}

func init() {
	supportGatherCmd.Flags().StringVar(&supportGatherOut, "out", "",
		"output file path (default: ./support-bundle-<timestamp>.txt)")
	supportGatherCmd.Flags().StringVar(&supportGatherTrigger, "trigger", "install",
		"bundle trigger: install (from install.sh) or adhoc (operator)")

	supportWriteAdminRowCmd.Flags().StringVar(&supportWriteAdminRowMessage, "message", "",
		"short description of the failure (required)")
	supportWriteAdminRowCmd.Flags().StringVar(&supportWriteAdminRowBundlePath, "bundle-path", "",
		"absolute path to the diagnostic bundle written by `./sb support gather`")
	supportWriteAdminRowCmd.Flags().IntVar(&supportWriteAdminRowTimeoutSec, "timeout", 2,
		"seconds to wait for a DB connection before giving up")

	supportCmd.AddCommand(supportGatherCmd)
	supportCmd.AddCommand(supportWriteAdminRowCmd)
	rootCmd.AddCommand(supportCmd)
}
