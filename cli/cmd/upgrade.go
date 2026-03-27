package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/selfupdate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// runUpgradePsql runs a SQL string using psql with connection args from .env.
func runUpgradePsql(sql string, extraArgs ...string) ([]byte, error) {
	projDir := migrate.PsqlProjectDir()
	psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
	if err != nil {
		return nil, err
	}
	args := append(prefix, "-c", sql)
	args = append(args, extraArgs...)
	c := exec.Command(psqlPath, args...)
	c.Env = env
	c.Dir = projDir
	return c.CombinedOutput()
}

var upgradeCmd = &cobra.Command{
	Use:   "upgrade",
	Short: "Manage software upgrades",
	Long: `Manage the upgrade daemon and software releases.

Commands for operators (no daemon needed):
  check       Query GitHub Releases API directly
  list        Show upgrades tracked in the local database

Commands that talk to the running daemon:
  discover    Tell the daemon to poll GitHub for new releases
  apply       Tell the daemon to upgrade to a specific version NOW
  schedule    Mark a discovered upgrade for the daemon to execute

Daemon management:
  daemon      Run the upgrade daemon (long-running, typically via systemd)`,
}

var upgradeCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Query GitHub Releases directly (no daemon needed)",
	RunE: func(cmd *cobra.Command, args []string) error {
		releases, err := upgrade.FetchReleases()
		if err != nil {
			return err
		}

		if len(releases) == 0 {
			fmt.Println("No releases found")
			return nil
		}

		fmt.Printf("Found %d release(s):\n", len(releases))
		for _, r := range releases[:min(5, len(releases))] {
			fmt.Printf("  %s\n", upgrade.ReleaseSummary(r))
		}
		return nil
	},
}

var upgradeDiscoverCmd = &cobra.Command{
	Use:   "discover",
	Short: "Tell the daemon to check for new releases",
	Long: `Sends NOTIFY upgrade_check to the running daemon, triggering it to
poll GitHub for new releases and insert them into the upgrade table.

Unlike 'check' (which queries GitHub directly), 'discover' talks to
the daemon via PostgreSQL NOTIFY. The daemon handles rate limiting,
channel filtering, and image pre-downloading.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		out, err := runUpgradePsql("NOTIFY upgrade_check")
		if err != nil {
			return fmt.Errorf("discover: %w\n%s", err, out)
		}
		fmt.Println("Sent: NOTIFY upgrade_check")
		fmt.Println("Upgrade daemon will poll GitHub for new releases")
		return nil
	},
}

var upgradeListCmd = &cobra.Command{
	Use:   "list",
	Short: "List discovered upgrades from the database",
	RunE: func(cmd *cobra.Command, args []string) error {
		sql := `SELECT version, summary,
			CASE
				WHEN completed_at IS NOT NULL THEN 'completed'
				WHEN error IS NOT NULL AND rollback_completed_at IS NOT NULL THEN 'rolled back'
				WHEN error IS NOT NULL THEN 'failed'
				WHEN started_at IS NOT NULL THEN 'in progress'
				WHEN scheduled_at IS NOT NULL THEN 'scheduled'
				WHEN skipped_at IS NOT NULL THEN 'skipped'
				ELSE 'available'
			END AS status,
			discovered_at::date AS discovered
		FROM public.upgrade
		ORDER BY discovered_at DESC
		LIMIT 20;`

		out, err := runUpgradePsql(sql)
		os.Stdout.Write(out)
		return err
	},
}

var upgradeScheduleCmd = &cobra.Command{
	Use:   "schedule <version>",
	Short: "Schedule an upgrade (sets scheduled_at = now())",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		version := args[0]
		if !upgrade.ValidateVersion(version) {
			return fmt.Errorf("invalid version: %q (expected vYYYY.MM.PATCH or sha-HEXHEX)", version)
		}

		// Use psql variable binding to avoid SQL string interpolation.
		// The -v flag safely quotes the value when referenced as :'var'.
		sql := "UPDATE public.upgrade SET scheduled_at = now() WHERE version = :'target_version' AND started_at IS NULL RETURNING version"

		out, err := runUpgradePsql(sql, "-v", "target_version="+version, "-t", "-A")
		if err != nil {
			return fmt.Errorf("schedule: %w\n%s", err, out)
		}
		if strings.TrimSpace(string(out)) == "" {
			return fmt.Errorf("version %s not found or already started", version)
		}
		fmt.Printf("Scheduled upgrade to %s\n", version)
		return nil
	},
}

var (
	applyRecreate bool
)

var upgradeApplyCmd = &cobra.Command{
	Use:   "apply <version>",
	Short: "Tell the daemon to upgrade to a specific version NOW",
	Long: `Validates the version and sends NOTIFY upgrade_apply to the daemon.
The daemon creates or updates the upgrade row and executes immediately.

Use --recreate to delete and recreate the database from scratch instead
of running migrations. This is destructive — only for dev/demo servers.

Examples:
  sb upgrade apply v2026.03.1
  sb upgrade apply sha-abc1234f
  sb upgrade apply v2026.03.1 --recreate`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		version := args[0]
		if !upgrade.ValidateVersion(version) {
			return fmt.Errorf("invalid version: %q (expected vYYYY.MM.PATCH or sha-HEXHEX)", version)
		}

		payload := version
		if applyRecreate {
			payload = version + ":recreate"
		}

		// NOTIFY payload doesn't support parameterized queries in psql.
		// Safe because ValidateVersion restricts the version format
		// and ":recreate" is a fixed, non-injectable suffix.
		sql := fmt.Sprintf("NOTIFY upgrade_apply, '%s'",
			strings.ReplaceAll(payload, "'", "''"))

		out, err := runUpgradePsql(sql)
		if err != nil {
			return fmt.Errorf("apply: %w\n%s", err, out)
		}

		fmt.Printf("Sent: NOTIFY upgrade_apply, '%s'\n", payload)
		fmt.Println("Upgrade daemon will execute this shortly")
		return nil
	},
}

var upgradeDaemonCmd = &cobra.Command{
	Use:   "daemon",
	Short: "Run the upgrade daemon (long-running process)",
	Long: `Starts the upgrade daemon which:
  - Polls GitHub Releases for new versions
  - Pre-downloads Docker images
  - Listens for NOTIFY upgrade_check and upgrade_apply
  - Executes scheduled upgrades with backup and rollback

Typically run via systemd (devops/statbus-upgrade.service).`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		// Pass the raw version (valid git ref like "v2026.03.0-rc.24"),
		// not the display string ("2026.03.0-rc.24 (commit 5bd190c0)").
		// The daemon uses this for from_version and rollback git checkout.
		daemonVersion := "v" + version // version is the raw ldflags value
		if version == "dev" {
			// Local dev build — use commit SHA if available
			if commit != "unknown" {
				daemonVersion = commit
			} else {
				daemonVersion = "dev"
			}
		}
		d := upgrade.NewDaemon(projDir, verbose, daemonVersion)
		return d.Run(context.Background())
	},
}

var upgradeSelfVerifyCmd = &cobra.Command{
	Use:    "self-verify",
	Short:  "Verify the binary can boot and connect (used during self-update)",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Self-verify: DELIBERATE FAILURE (testing self-update rejection)")
		os.Exit(1)
		return nil
	},
}

var upgradeSelfRollbackCmd = &cobra.Command{
	Use:    "self-rollback",
	Short:  "Roll back to the previous binary",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		sbPath := projDir + "/sb"
		if err := selfupdate.Rollback(sbPath); err != nil {
			return err
		}
		fmt.Println("Rolled back to previous binary")
		return nil
	},
}

var upgradeChannelCmd = &cobra.Command{
	Use:   "channel <stable|prerelease|edge>",
	Short: "Set the upgrade channel and apply the change",
	Long: `Changes the upgrade channel in .env.config, regenerates .env,
and restarts the upgrade daemon to pick up the new channel.

Channels:
  stable      Only stable releases (default for production)
  prerelease  All releases including release candidates
  edge        Every master commit (development servers only)`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		channel := args[0]
		switch channel {
		case "stable", "prerelease", "edge":
		default:
			return fmt.Errorf("invalid channel %q (must be stable, prerelease, or edge)", channel)
		}

		projDir := config.ProjectDir()

		// 1. Update .env.config
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}
		f.Set("UPGRADE_CHANNEL", channel)
		if err := f.Save(); err != nil {
			return fmt.Errorf("save .env.config: %w", err)
		}
		fmt.Printf("Set UPGRADE_CHANNEL=%s in .env.config\n", channel)

		// 2. Regenerate .env
		sb := filepath.Join(projDir, "sb")
		genCmd := exec.Command(sb, "config", "generate")
		genCmd.Dir = projDir
		genCmd.Stdout = os.Stdout
		genCmd.Stderr = os.Stderr
		if err := genCmd.Run(); err != nil {
			return fmt.Errorf("config generate: %w", err)
		}

		// 3. Restart daemon via NOTIFY (daemon re-reads config on reconnect)
		// Send a signal to make the daemon reload — simplest is to kill it
		// and let systemd restart it with the new config.
		fmt.Println("Restarting upgrade daemon...")
		restartCmd := exec.Command("systemctl", "restart",
			fmt.Sprintf("statbus-upgrade@%s.service", os.Getenv("USER")))
		if err := restartCmd.Run(); err != nil {
			// Not fatal — user may not have systemctl access
			fmt.Printf("Could not restart daemon (try: sudo systemctl restart statbus-upgrade@%s): %v\n",
				os.Getenv("USER"), err)
		} else {
			fmt.Println("Daemon restarted with new channel")
		}

		return nil
	},
}

func init() {
	upgradeApplyCmd.Flags().BoolVar(&applyRecreate, "recreate", false, "delete and recreate database from scratch (destructive — dev/demo only)")

	upgradeCmd.AddCommand(upgradeCheckCmd)
	upgradeCmd.AddCommand(upgradeDiscoverCmd)
	upgradeCmd.AddCommand(upgradeListCmd)
	upgradeCmd.AddCommand(upgradeScheduleCmd)
	upgradeCmd.AddCommand(upgradeApplyCmd)
	upgradeCmd.AddCommand(upgradeChannelCmd)
	upgradeCmd.AddCommand(upgradeDaemonCmd)
	upgradeCmd.AddCommand(upgradeSelfVerifyCmd)
	upgradeCmd.AddCommand(upgradeSelfRollbackCmd)
	rootCmd.AddCommand(upgradeCmd)
}
