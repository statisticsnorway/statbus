package cmd

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/syslog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
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
	args := append(prefix, extraArgs...)
	// SQL goes via stdin so psql's variable-substitution preprocessor runs.
	// `-c` bypasses the preprocessor and sends the string literally to the
	// server, which fails on :'var' with "syntax error at or near ':'".
	c := exec.Command(psqlPath, args...)
	c.Env = env
	c.Dir = projDir
	c.Stdin = strings.NewReader(sql)
	return c.CombinedOutput()
}

var upgradeCmd = &cobra.Command{
	Use:   "upgrade",
	Short: "Manage software upgrades",
	Long: `Manage the upgrade service and software releases.

Commands for operators (no service needed):
  check       Query GitHub Releases API directly
  list        Show upgrades tracked in the local database

Commands that write to the database and notify the service:
  discover    Tell the service to poll GitHub for new releases
  apply       Schedule an upgrade NOW (writes DB + sends NOTIFY)
  schedule    Mark a discovered upgrade for the service to execute

Service management:
  service     Run the upgrade service (long-running, typically via systemd)`,
}

var upgradeCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Query GitHub Releases directly (no service needed)",
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
	Short: "Tell the upgrade service to check for new releases",
	Long: `Sends NOTIFY upgrade_check to the running upgrade service, triggering it to
poll GitHub for new releases and insert them into the upgrade table.

Unlike 'check' (which queries GitHub directly), 'discover' talks to
the service via PostgreSQL NOTIFY. The service handles rate limiting,
channel filtering, and image pre-downloading.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		out, err := runUpgradePsql("NOTIFY upgrade_check")
		if err != nil {
			return fmt.Errorf("discover: %w\n%s", err, out)
		}
		fmt.Println("Sent: NOTIFY upgrade_check")
		fmt.Println("Upgrade service will poll GitHub for new releases")
		return nil
	},
}

var upgradeListCmd = &cobra.Command{
	Use:   "list",
	Short: "List discovered upgrades from the database",
	RunE: func(cmd *cobra.Command, args []string) error {
		sql := `SELECT commit_version AS version, summary,
			CASE
				WHEN completed_at IS NOT NULL THEN 'completed'
				WHEN error IS NOT NULL AND rolled_back_at IS NOT NULL THEN 'rolled back'
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
		// state='scheduled' is required by chk_upgrade_state_attributes
		// (migration 20260414180000): the CHECK rejects a scheduled_at
		// update on an 'available' row without a matching state write.
		sql := "UPDATE public.upgrade SET state = 'scheduled', scheduled_at = now() WHERE commit_version = :'target_version' AND state = 'available' RETURNING commit_version"

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
and sends NOTIFY as a wake-up optimization for the upgrade service.

The direct database write ensures the upgrade is scheduled even if the
service misses the NOTIFY (e.g., not running, reconnecting). The NOTIFY
makes the service act immediately instead of waiting for its next poll.

Use --recreate to delete and recreate the database from scratch instead
of running migrations. This is destructive — only for dev/demo servers.

Examples:
  sb upgrade apply v2026.03.1
  sb upgrade apply abc1234f
  sb upgrade apply v2026.03.1 --recreate`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		version := args[0]
		// Accept either a CalVer release tag or a commit_short reference
		// (the scheduler's resolveUpgradeTarget will validate the final shape).
		if !upgrade.ValidateVersion(version) && !upgrade.IsCommitShort(version) {
			return fmt.Errorf("invalid version: %q (expected vYYYY.MM.PATCH release tag or an 8-char commit_short)", version)
		}

		payload := version
		if applyRecreate {
			payload = version + ":recreate"
		}

		// 1. Write scheduled_at directly to the database (belt).
		// Uses psql variable binding (-v) to avoid SQL injection.
		// Matches by tag name OR commit_sha (full or prefix).
		// state='scheduled' + clearing every lifecycle timestamp satisfies
		// chk_upgrade_state_attributes regardless of prior state
		// (available / completed / failed / rolled_back / dismissed).
		updateSQL := `UPDATE public.upgrade SET
  state = 'scheduled',
  scheduled_at = now(),
  started_at = NULL,
  completed_at = NULL,
  error = NULL,
  rolled_back_at = NULL,
  skipped_at = NULL,
  dismissed_at = NULL,
  log_relative_file_path = NULL
WHERE :'target_version' = ANY(commit_tags)
   OR commit_sha = :'target_version'
   OR commit_sha LIKE :'target_version' || '%'
RETURNING commit_sha, commit_tags[1]`

		out, err := runUpgradePsql(updateSQL, "-v", "target_version="+version, "-t", "-A")
		if err != nil {
			return fmt.Errorf("apply (update): %w\n%s", err, out)
		}

		updated := strings.TrimSpace(string(out))
		if updated == "" {
			fmt.Printf("Version %s not yet discovered in the upgrade table.\n", version)
			fmt.Println("NOTIFY will be sent — service will discover and apply on next cycle.")
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
configured channel (prerelease/stable/edge), and tells the upgrade service
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

		// Self-heal stale refspecs before any git fetch. Servers upgraded
		// across the R1.1 devops/→ops/cloud/deploy rename can have a
		// dangling refs/heads/devops/* refspec that makes every fetch fail.
		// CleanStaleRefspecs is a no-op when nothing stale is configured.
		upgrade.CleanStaleRefspecs(projDir)

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
		//    state='scheduled' is required so the CHECK
		//    chk_upgrade_state_attributes passes (state='scheduled' demands
		//    scheduled_at IS NOT NULL; previous state could be 'completed'
		//    or 'failed' etc., and stale timestamps are cleared to satisfy
		//    the scheduled-state invariants).
		updateSQL := `UPDATE public.upgrade SET
  state = 'scheduled',
  scheduled_at = now(),
  started_at = NULL,
  completed_at = NULL,
  error = NULL,
  rolled_back_at = NULL,
  skipped_at = NULL,
  dismissed_at = NULL,
  log_relative_file_path = NULL
WHERE :'target_version' = ANY(commit_tags)
   OR commit_sha = :'target_version'
   OR commit_sha LIKE :'target_version' || '%'
RETURNING commit_sha, commit_tags[1]`

		out, err := runUpgradePsql(updateSQL, "-v", "target_version="+latestVersion, "-t", "-A")
		if err != nil {
			return fmt.Errorf("apply-latest (update): %w\n%s", err, out)
		}

		updated := strings.TrimSpace(string(out))
		if updated == "" {
			fmt.Printf("Version %s not yet discovered in the upgrade table.\n", latestVersion)
			fmt.Println("NOTIFY will be sent — service will discover and apply on next cycle.")
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

// calVerRe matches a CalVer version string with or without a leading "v"
// (e.g. "2026.04.0-rc.56" or "v2026.04.0-rc.56"). Anything that doesn't
// match (stray non-CalVer git tags, "dev", "sha-<short>", etc.) is rejected
// and handled by the default branch below.
var calVerRe = regexp.MustCompile(`^\d{4}\.\d{2}`)

var upgradeServiceRunE = func(cmd *cobra.Command, args []string) error {
	projDir := config.ProjectDir()
	// Derive serviceVersion — a valid git ref the service can git-checkout.
	// Rules (in priority order):
	//   1. "dev" ldflag  → 8-char commit_short or "dev" (skips downgrade guard)
	//   2. Already has "v" prefix → use as-is (CalVer from release.yaml)
	//   3. Matches CalVer digits (YYYY.MM…) → prepend "v"
	//   4. Anything else → 8-char commit_short or "dev". Downgrade guard
	//      treats it as an unversioned local build.
	//
	// No "sha-" prefix anywhere (rc.63 canonical naming).
	var serviceVersion string
	switch {
	case version == "dev":
		if commit != "unknown" {
			serviceVersion = upgrade.ShortForDisplay(commit)
		} else {
			serviceVersion = "dev"
		}
	case strings.HasPrefix(version, "v"):
		serviceVersion = version
	case calVerRe.MatchString(version):
		serviceVersion = "v" + version
	default:
		// Non-CalVer ldflag (stray tag, hand-built binary, etc.) — treat as local build.
		if commit != "unknown" {
			serviceVersion = upgrade.ShortForDisplay(commit)
		} else {
			serviceVersion = "dev"
		}
	}
	d := upgrade.NewService(projDir, verbose, serviceVersion, commit)
	return d.Run(context.Background())
}

var upgradeServiceCmd = &cobra.Command{
	Use:   "service",
	Short: "Run the upgrade service (long-running process)",
	Long: `Starts the upgrade service which:
  - Polls GitHub Releases for new versions
  - Pre-downloads Docker images
  - Listens for NOTIFY upgrade_check and upgrade_apply
  - Executes scheduled upgrades with backup and rollback

Typically run via systemd (ops/statbus-upgrade.service).`,
	RunE: upgradeServiceRunE,
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
and restarts the upgrade service to pick up the new channel.

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

		// 3. Restart service via NOTIFY (service re-reads config on reconnect)
		// Send a signal to make the service reload — simplest is to kill it
		// and let systemd restart it with the new config.
		fmt.Println("Restarting upgrade service...")
		restartCmd := exec.Command("systemctl", "restart",
			fmt.Sprintf("statbus-upgrade@%s.service", os.Getenv("USER")))
		if err := restartCmd.Run(); err != nil {
			// Not fatal — user may not have systemctl access
			fmt.Printf("Could not restart service (try: sudo systemctl restart statbus-upgrade@%s): %v\n",
				os.Getenv("USER"), err)
		} else {
			fmt.Println("Service restarted with new channel")
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

// gitHubSigningKey represents one entry from the GitHub SSH signing keys API.
type gitHubSigningKey struct {
	Key string `json:"key"`
}

// fetchGitHubKeys fetches SSH public keys for a GitHub user. It tries the
// signing keys API first (correct for commit verification), falling back to
// the authentication keys endpoint for backward compatibility. Returns the
// keys and whether they came from the signing keys endpoint.
func fetchGitHubKeys(username string) (keys []string, signing bool, err error) {
	// Try signing keys first — these are what git uses for commit verification.
	sigURL := fmt.Sprintf("https://api.github.com/users/%s/ssh_signing_keys", username)
	if sk, fetchErr := fetchGitHubSigningKeys(sigURL); fetchErr == nil && len(sk) > 0 {
		return sk, true, nil
	}

	// Fall back to authentication keys (plain-text, one per line).
	authURL := fmt.Sprintf("https://github.com/%s.keys", username)
	ak, fetchErr := fetchGitHubAuthKeys(authURL, username)
	if fetchErr != nil {
		return nil, false, fetchErr
	}
	return ak, false, nil
}

// fetchGitHubSigningKeys queries the GitHub API for SSH signing keys.
// Returns (nil, nil) when the endpoint succeeds but the user has no signing keys.
func fetchGitHubSigningKeys(url string) ([]string, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-cli")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch signing keys from %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("status %d from %s", resp.StatusCode, url)
	}

	var entries []gitHubSigningKey
	if err := json.NewDecoder(resp.Body).Decode(&entries); err != nil {
		return nil, fmt.Errorf("decode signing keys JSON: %w", err)
	}

	var keys []string
	for _, e := range entries {
		if k := strings.TrimSpace(e.Key); k != "" {
			keys = append(keys, k)
		}
	}
	return keys, nil
}

// fetchGitHubAuthKeys fetches the plain-text SSH authentication keys for a GitHub user.
func fetchGitHubAuthKeys(url, username string) ([]string, error) {
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
	keys, signing, err := fetchGitHubKeys(username)
	if err != nil {
		return false, err
	}

	if signing {
		fmt.Printf("Found %d signing key(s) for github.com/%s:\n", len(keys), username)
	} else {
		fmt.Printf("Found %d auth key(s) for github.com/%s (no signing keys configured — consider adding at github.com/settings/keys):\n", len(keys), username)
	}
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
The upgrade service uses these to verify commits before applying upgrades.`,
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

var trustKeyAddYes bool

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

		if trustKeyAddYes {
			return trustSignerNonInteractive(username, f)
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

// trustSignerNonInteractive fetches keys and trusts the first one without
// prompting. Used by --yes flag for scripted / AI-driven installs.
func trustSignerNonInteractive(username string, f *dotenv.File) error {
	fmt.Printf("Fetching SSH keys from GitHub for %s...\n", username)
	keys, signing, err := fetchGitHubKeys(username)
	if err != nil {
		return err
	}
	if signing {
		fmt.Printf("Found %d signing key(s) for github.com/%s:\n", len(keys), username)
	} else {
		fmt.Printf("Found %d auth key(s) for github.com/%s (no signing keys configured — consider adding at github.com/settings/keys):\n", len(keys), username)
	}
	for _, key := range keys {
		fmt.Printf("  %s\n", sshKeyFingerprint(key))
	}

	envKey := trustedSignerPrefix + username
	f.Set(envKey, keys[0])
	if err := f.Save(); err != nil {
		return fmt.Errorf("save .env.config: %w", err)
	}
	fmt.Printf("Added %s to .env.config (--yes, no prompt)\n", envKey)
	return nil
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

	trustKeyAddCmd.Flags().BoolVarP(&trustKeyAddYes, "yes", "y", false, "skip confirmation prompt (for scripted / AI-driven installs)")
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
	upgradeCmd.AddCommand(upgradeServiceCmd)
	upgradeCmd.AddCommand(upgradeSelfVerifyCmd)
	upgradeCmd.AddCommand(upgradeSelfRollbackCmd)
	upgradeCmd.AddCommand(trustKeyCmd)
	rootCmd.AddCommand(upgradeCmd)
}
