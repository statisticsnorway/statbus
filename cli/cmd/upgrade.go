package cmd

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"log/syslog"
	"net/http"
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

Commands that write to the database and notify the daemon:
  discover    Tell the daemon to poll GitHub for new releases
  apply       Schedule an upgrade NOW (writes DB + sends NOTIFY)
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
	Short: "Schedule an upgrade to a specific version NOW",
	Long: `Validates the version, writes scheduled_at directly to the database,
and sends NOTIFY as a wake-up optimization for the daemon.

The direct database write ensures the upgrade is scheduled even if the
daemon misses the NOTIFY (e.g., not running, reconnecting). The NOTIFY
makes the daemon act immediately instead of waiting for its next poll.

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

		// 1. Write scheduled_at directly to the database (belt).
		// Uses psql variable binding (-v) to avoid SQL injection.
		// Matches by tag name OR commit_sha (full or prefix).
		updateSQL := `UPDATE public.upgrade SET
  scheduled_at = now(),
  started_at = NULL,
  completed_at = NULL,
  error = NULL,
  rollback_completed_at = NULL,
  skipped_at = NULL
WHERE :'target_version' = ANY(tags)
   OR commit_sha = :'target_version'
   OR commit_sha LIKE :'target_version' || '%'
RETURNING commit_sha, tags[1]`

		out, err := runUpgradePsql(updateSQL, "-v", "target_version="+version, "-t", "-A")
		if err != nil {
			return fmt.Errorf("apply (update): %w\n%s", err, out)
		}

		updated := strings.TrimSpace(string(out))
		if updated == "" {
			fmt.Printf("Version %s not yet discovered in the upgrade table.\n", version)
			fmt.Println("NOTIFY will be sent — daemon will discover and apply on next cycle.")
		} else {
			fmt.Printf("Scheduled upgrade: %s\n", updated)
		}

		// 2. Send NOTIFY as wake-up optimization (suspenders).
		// NOTIFY payload doesn't support parameterized queries in psql.
		// Safe because ValidateVersion restricts the version format
		// and ":recreate" is a fixed, non-injectable suffix.
		notifySQL := fmt.Sprintf("NOTIFY upgrade_apply, '%s'",
			strings.ReplaceAll(payload, "'", "''"))

		out, err = runUpgradePsql(notifySQL)
		if err != nil {
			return fmt.Errorf("apply (notify): %w\n%s", err, out)
		}

		fmt.Printf("Sent: NOTIFY upgrade_apply, '%s'\n", payload)

		if w, err := syslog.New(syslog.LOG_INFO, "statbus-upgrade"); err == nil {
			w.Info(fmt.Sprintf("upgrade apply: scheduled + NOTIFY '%s'", payload))
			w.Close()
		}

		return nil
	},
}

var upgradeApplyLatestCmd = &cobra.Command{
	Use:   "apply-latest",
	Short: "Discover and apply the latest available version",
	Long: `Fetches tags via git, finds the latest version matching the
configured channel (prerelease/stable/edge), and tells the daemon
to upgrade to it immediately.

Used by deploy workflows — all logic is server-side, no workflow
file changes needed.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// 1. Load channel from .env
		envPath := filepath.Join(projDir, ".env")
		f, err := dotenv.Load(envPath)
		if err != nil {
			return fmt.Errorf("load .env: %w", err)
		}
		channel := "stable"
		if v, ok := f.Get("UPGRADE_CHANNEL"); ok {
			channel = v
		}

		var latestVersion string

		if channel == "edge" {
			// Edge: use latest master commit SHA
			if _, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "master", "--quiet"); err != nil {
				return fmt.Errorf("git fetch origin master: %w", err)
			}
			sha, err := upgrade.RunCommandOutput(projDir, "git", "log", "origin/master", "-1", "--format=%H")
			if err != nil {
				return fmt.Errorf("git log origin/master: %w", err)
			}
			sha = strings.TrimSpace(sha)
			if len(sha) < 7 {
				return fmt.Errorf("unexpected git log output: %q", sha)
			}
			latestVersion = "sha-" + sha[:8]
		} else {
			// Stable or prerelease: find latest tag
			if _, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "--tags", "--quiet"); err != nil {
				return fmt.Errorf("git fetch --tags: %w", err)
			}
			tagsOutput, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", "v*", "--sort=-version:refname")
			if err != nil {
				return fmt.Errorf("git tag -l: %w", err)
			}
			tags := strings.Split(strings.TrimSpace(tagsOutput), "\n")
			for _, tag := range tags {
				tag = strings.TrimSpace(tag)
				if tag == "" {
					continue
				}
				if channel == "stable" && strings.Contains(tag, "-") {
					// Stable: skip pre-release tags (contain "-")
					continue
				}
				latestVersion = tag
				break
			}
		}

		if latestVersion == "" {
			return fmt.Errorf("no matching version found for channel %q", channel)
		}

		if !upgrade.ValidateVersion(latestVersion) {
			return fmt.Errorf("discovered version %q does not pass validation", latestVersion)
		}

		fmt.Printf("Channel %s: latest version is %s\n", channel, latestVersion)

		payload := latestVersion
		if applyRecreate {
			payload = latestVersion + ":recreate"
		}

		// 1. Write scheduled_at directly to the database (belt).
		updateSQL := `UPDATE public.upgrade SET
  scheduled_at = now(),
  started_at = NULL,
  completed_at = NULL,
  error = NULL,
  rollback_completed_at = NULL,
  skipped_at = NULL
WHERE :'target_version' = ANY(tags)
   OR commit_sha = :'target_version'
   OR commit_sha LIKE :'target_version' || '%'
RETURNING commit_sha, tags[1]`

		out, err := runUpgradePsql(updateSQL, "-v", "target_version="+latestVersion, "-t", "-A")
		if err != nil {
			return fmt.Errorf("apply-latest (update): %w\n%s", err, out)
		}

		updated := strings.TrimSpace(string(out))
		if updated == "" {
			fmt.Printf("Version %s not yet discovered in the upgrade table.\n", latestVersion)
			fmt.Println("NOTIFY will be sent — daemon will discover and apply on next cycle.")
		} else {
			fmt.Printf("Scheduled upgrade: %s\n", updated)
		}

		// 2. Send NOTIFY as wake-up optimization (suspenders).
		notifySQL := fmt.Sprintf("NOTIFY upgrade_apply, '%s'",
			strings.ReplaceAll(payload, "'", "''"))

		out, err = runUpgradePsql(notifySQL)
		if err != nil {
			return fmt.Errorf("apply-latest (notify): %w\n%s", err, out)
		}

		fmt.Printf("Sent: NOTIFY upgrade_apply, '%s'\n", payload)

		if w, err := syslog.New(syslog.LOG_INFO, "statbus-upgrade"); err == nil {
			w.Info(fmt.Sprintf("upgrade apply-latest: scheduled + NOTIFY '%s' (channel=%s)", payload, channel))
			w.Close()
		}

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

// sshKeyFingerprint returns the fingerprint for an SSH public key string.
func sshKeyFingerprint(key string) string {
	cmd := exec.Command("ssh-keygen", "-l", "-f", "/dev/stdin")
	cmd.Stdin = strings.NewReader(key)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "unknown fingerprint"
	}
	return strings.TrimSpace(string(out))
}

// fetchGitHubKeys fetches SSH public keys for a GitHub user and returns them as a slice.
func fetchGitHubKeys(username string) ([]string, error) {
	url := fmt.Sprintf("https://github.com/%s.keys", username)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("fetch keys from %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 404 {
		return nil, fmt.Errorf("GitHub user %q not found (404 from %s)", username, url)
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("unexpected status %d from %s", resp.StatusCode, url)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	var keys []string
	scanner := bufio.NewScanner(strings.NewReader(string(body)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" {
			keys = append(keys, line)
		}
	}

	if len(keys) == 0 {
		return nil, fmt.Errorf("no SSH keys found for github.com/%s", username)
	}

	return keys, nil
}

// trustSignerInteractive fetches keys for a GitHub user, displays them, prompts for
// confirmation, and stores the key in the given dotenv file. Returns true if a key was trusted.
func trustSignerInteractive(username string, f *dotenv.File, reader *bufio.Reader) (bool, error) {
	fmt.Printf("\nFetching SSH keys from GitHub for %s...\n", username)
	keys, err := fetchGitHubKeys(username)
	if err != nil {
		return false, err
	}

	fmt.Printf("Found %d key(s) for github.com/%s:\n", len(keys), username)
	for _, key := range keys {
		fingerprint := sshKeyFingerprint(key)
		fmt.Printf("  %s\n", fingerprint)
	}

	fmt.Printf("\nTrust key(s) from github.com/%s? [Y/n] ", username)
	answer, _ := reader.ReadString('\n')
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer == "n" || answer == "no" {
		return false, nil
	}

	envKey := trustedSignerPrefix + username
	f.Set(envKey, keys[0])
	if err := f.Save(); err != nil {
		return false, fmt.Errorf("save .env.config: %w", err)
	}

	fmt.Printf("Added %s to .env.config\n", envKey)
	if len(keys) > 1 {
		fmt.Printf("Note: only the first key was stored. Add others manually if needed.\n")
	}
	return true, nil
}

// trustedSignerPrefix is the env key prefix for trusted signers.
const trustedSignerPrefix = "UPGRADE_TRUSTED_SIGNER_"

var trustKeyCmd = &cobra.Command{
	Use:   "trust-key",
	Short: "Manage trusted commit signing keys",
	Long: `Manage SSH public keys trusted for verifying commit signatures.

Keys are stored as UPGRADE_TRUSTED_SIGNER_<name> in .env.config.
The upgrade daemon uses these to verify commits before applying upgrades.`,
}

var trustKeyListCmd = &cobra.Command{
	Use:   "list",
	Short: "List configured trusted signing keys",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		found := false
		for _, key := range f.Keys() {
			if !strings.HasPrefix(key, trustedSignerPrefix) {
				continue
			}
			name := strings.TrimPrefix(key, trustedSignerPrefix)
			val, _ := f.Get(key)
			fingerprint := sshKeyFingerprint(val)
			fmt.Printf("  %s: %s\n", name, fingerprint)
			found = true
		}

		if !found {
			fmt.Println("No trusted signers configured.")
			fmt.Println("Add one with: ./sb upgrade trust-key add <github-username>")
		}
		return nil
	},
}

var trustKeyAddCmd = &cobra.Command{
	Use:   "add <github-username>",
	Short: "Add trusted signing keys from a GitHub user",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		username := args[0]

		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		reader := bufio.NewReader(os.Stdin)
		trusted, err := trustSignerInteractive(username, f, reader)
		if err != nil {
			return err
		}
		if !trusted {
			fmt.Println("Cancelled.")
		}
		return nil
	},
}

var trustKeyRemoveCmd = &cobra.Command{
	Use:   "remove <name>",
	Short: "Remove a trusted signing key",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		name := args[0]
		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		envKey := trustedSignerPrefix + name
		if !f.Delete(envKey) {
			return fmt.Errorf("no trusted signer named %q found in .env.config", name)
		}

		if err := f.Save(); err != nil {
			return fmt.Errorf("save .env.config: %w", err)
		}

		fmt.Printf("Removed %s from .env.config\n", envKey)
		return nil
	},
}

var trustKeyVerifyCmd = &cobra.Command{
	Use:   "verify",
	Short: "Verify the current HEAD commit signature against trusted keys",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		// Collect trusted signers
		var signerLines []string
		for _, key := range f.Keys() {
			if !strings.HasPrefix(key, trustedSignerPrefix) {
				continue
			}
			name := strings.TrimPrefix(key, trustedSignerPrefix)
			val, _ := f.Get(key)
			// allowed_signers format: <principal> <key>
			signerLines = append(signerLines, fmt.Sprintf("%s %s", name, val))
		}

		if len(signerLines) == 0 {
			return fmt.Errorf("no trusted signers configured (UPGRADE_TRUSTED_SIGNER_*)")
		}

		// Write allowed-signers file
		allowedSignersPath := filepath.Join(projDir, "tmp", "allowed-signers")
		os.MkdirAll(filepath.Join(projDir, "tmp"), 0755)
		if err := os.WriteFile(allowedSignersPath, []byte(strings.Join(signerLines, "\n")+"\n"), 0644); err != nil {
			return fmt.Errorf("write allowed-signers: %w", err)
		}

		// Verify HEAD
		verifyCmd := exec.Command("git", "-c",
			fmt.Sprintf("gpg.ssh.allowedSignersFile=%s", allowedSignersPath),
			"verify-commit", "HEAD")
		verifyCmd.Dir = projDir
		out, verifyErr := verifyCmd.CombinedOutput()
		fmt.Print(string(out))

		if verifyErr != nil {
			return fmt.Errorf("HEAD commit signature verification failed")
		}
		fmt.Println("HEAD commit signature is valid and trusted.")
		return nil
	},
}

func init() {
	upgradeApplyCmd.Flags().BoolVar(&applyRecreate, "recreate", false, "delete and recreate database from scratch (destructive — dev/demo only)")
	upgradeApplyLatestCmd.Flags().BoolVar(&applyRecreate, "recreate", false, "delete and recreate database from scratch (destructive — dev/demo only)")

	trustKeyCmd.AddCommand(trustKeyListCmd)
	trustKeyCmd.AddCommand(trustKeyAddCmd)
	trustKeyCmd.AddCommand(trustKeyRemoveCmd)
	trustKeyCmd.AddCommand(trustKeyVerifyCmd)

	upgradeCmd.AddCommand(upgradeCheckCmd)
	upgradeCmd.AddCommand(upgradeDiscoverCmd)
	upgradeCmd.AddCommand(upgradeListCmd)
	upgradeCmd.AddCommand(upgradeScheduleCmd)
	upgradeCmd.AddCommand(upgradeApplyCmd)
	upgradeCmd.AddCommand(upgradeApplyLatestCmd)
	upgradeCmd.AddCommand(upgradeChannelCmd)
	upgradeCmd.AddCommand(upgradeDaemonCmd)
	upgradeCmd.AddCommand(upgradeSelfVerifyCmd)
	upgradeCmd.AddCommand(upgradeSelfRollbackCmd)
	upgradeCmd.AddCommand(trustKeyCmd)
	rootCmd.AddCommand(upgradeCmd)
}
