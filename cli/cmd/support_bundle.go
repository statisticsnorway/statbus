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

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

var supportBundleOut string

var supportBundleCmd = &cobra.Command{
	Use:   "support-bundle",
	Short: "Write a diagnostic bundle to a file (no database required)",
	Long: `Collect diagnostic information into a self-contained plain-text bundle.

The bundle includes:
  - Upgrade row data (best-effort from the most recent log)
  - Log tail from the latest upgrade log
  - docker compose ps
  - journalctl tail (if available)
  - git log
  - Redacted .env (secrets replaced with ***REDACTED***)

This command works without a running database. It is the "lifeline" tool
when a server is unresponsive and the upgrade service cannot write its own
bundle.

The output file defaults to ./support-bundle-<timestamp>.txt. Use --out to
specify a different path.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// Find the most recent upgrade log, using the upgrade-progress.log
		// symlink as first choice (points to the latest log the service
		// wrote), then falling back to lexicographic-last in upgrade-logs/.
		logPath := latestUpgradeLog(projDir)

		outPath := supportBundleOut
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
		upgrade.WriteBundleSections(context.Background(), bw, projDir, 0, "{}", logPath)

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

		fmt.Printf("Support bundle written to %s\n", outPath)
		return nil
	},
}

// latestUpgradeLog returns the absolute path of the most recent upgrade log.
// Uses the upgrade-progress.log symlink if it resolves to an existing file,
// otherwise picks the lexicographically last .log file in tmp/upgrade-logs/.
// Returns an empty string if no log is found (WriteBundleSections will
// insert a "(log unavailable)" placeholder for that section).
func latestUpgradeLog(projDir string) string {
	// Prefer the symlink — it always points to the latest log the service wrote.
	symlinkPath := filepath.Join(projDir, "tmp", "upgrade-progress.log")
	if resolved, err := filepath.EvalSymlinks(symlinkPath); err == nil {
		if _, err := os.Stat(resolved); err == nil {
			return resolved
		}
	}

	// Fallback: find the newest .log file in tmp/upgrade-logs/.
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

func init() {
	supportBundleCmd.Flags().StringVar(&supportBundleOut, "out", "", "output file path (default: ./support-bundle-<timestamp>.txt)")
	rootCmd.AddCommand(supportBundleCmd)
}
