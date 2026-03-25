package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
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
}

var upgradeCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Check for available upgrades",
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

		sql := fmt.Sprintf(
			"UPDATE public.upgrade SET scheduled_at = now() WHERE version = '%s' AND started_at IS NULL RETURNING version",
			strings.ReplaceAll(version, "'", "''"))

		out, err := runUpgradePsql(sql, "-t", "-A")
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

var upgradeApplyCmd = &cobra.Command{
	Use:   "apply <version>",
	Short: "Send NOTIFY to trigger immediate upgrade",
	Long: `Validates the version and sends NOTIFY upgrade_apply to the daemon.
The daemon creates or updates the upgrade row and executes immediately.

Examples:
  sb upgrade apply v2026.03.1
  sb upgrade apply sha-abc1234f`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		version := args[0]
		if !upgrade.ValidateVersion(version) {
			return fmt.Errorf("invalid version: %q (expected vYYYY.MM.PATCH or sha-HEXHEX)", version)
		}

		sql := fmt.Sprintf("NOTIFY upgrade_apply, '%s'",
			strings.ReplaceAll(version, "'", "''"))

		out, err := runUpgradePsql(sql)
		if err != nil {
			return fmt.Errorf("apply: %w\n%s", err, out)
		}

		fmt.Printf("Sent: NOTIFY upgrade_apply, '%s'\n", version)
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
		d := upgrade.NewDaemon(projDir, verbose)
		return d.Run(context.Background())
	},
}

var upgradeSelfVerifyCmd = &cobra.Command{
	Use:    "self-verify",
	Short:  "Verify the binary can boot and connect (used during self-update)",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("sb version: %s\n", rootCmd.Version)
		fmt.Println("Self-verify: OK")
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

func init() {
	upgradeCmd.AddCommand(upgradeCheckCmd)
	upgradeCmd.AddCommand(upgradeListCmd)
	upgradeCmd.AddCommand(upgradeScheduleCmd)
	upgradeCmd.AddCommand(upgradeApplyCmd)
	upgradeCmd.AddCommand(upgradeDaemonCmd)
	upgradeCmd.AddCommand(upgradeSelfVerifyCmd)
	upgradeCmd.AddCommand(upgradeSelfRollbackCmd)
	rootCmd.AddCommand(upgradeCmd)
}
