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

Look:
  check       Fetch GitHub releases and register what it finds
  list        Show registered candidates and their status

Request (you ask; the service performs the work):
  register    Record a release tag or commit as a candidate (state=available)
  schedule    Queue an ALREADY-REGISTERED candidate to run (fails if not registered)

Run:
  service     Run the upgrade service (long-running, typically via systemd)`,
}

var upgradeCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Fetch GitHub releases and register them as candidates",
	Long: `Fetches releases from GitHub, prints them, and registers each release
newer than the running version as an upgrade candidate (state='available')
through the same path discovery uses. Subsumes the old 'discover' verb — the
service still auto-discovers on its own poll using the same register path.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return newUpgradeService(config.ProjectDir()).RunCheck(context.Background())
	},
}

var upgradeRegisterCmd = &cobra.Command{
	Use:   "register <target>",
	Short: "Record a release tag or commit as an upgrade candidate",
	Long: `Record a target as an upgrade candidate (state='available') and poke the
upgrade service to prepare it (pull images, verify build artifacts).

The target is a release tag, an 8-char commit_short, OR a full 40-char commit
SHA — git-resolved to the canonical commit. register is the prerequisite for
schedule: you cannot schedule a target whose candidate row does not exist.
Once the service reports the candidate ready, run
'./sb upgrade schedule <target>' to queue it.

Examples:
  sb upgrade register v2026.03.1
  sb upgrade register abc1234f
  sb upgrade register 1e5b5434d25a8b1efca94901fc0a9d4ddb2f64f5`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		return newUpgradeService(config.ProjectDir()).RunRegister(context.Background(), args[0])
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
		_, _ = os.Stdout.Write(out) // best-effort; a stdout write failure here is unrecoverable anyway
		return err
	},
}

var upgradeScheduleCmd = &cobra.Command{
	Use:   "schedule <target>",
	Short: "Schedule an already-registered candidate to run",
	Long: `Promote an already-registered upgrade candidate to 'scheduled'. The
database trigger then notifies the upgrade service, which runs it.

The target is a release tag, an 8-char commit_short, or a full 40-char commit
SHA — whichever you registered (git-resolved to the canonical commit). FAILS
FAST if the target is not registered: run './sb upgrade register <target>'
first.

Use --recreate to delete and recreate the database from scratch instead of
running migrations. Destructive — dev/demo servers only.

Examples:
  sb upgrade schedule v2026.03.1
  sb upgrade schedule abc1234f
  sb upgrade schedule v2026.03.1 --recreate`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		return newUpgradeService(config.ProjectDir()).RunSchedule(context.Background(), args[0], recreateFlag)
	},
}

var (
	recreateFlag bool
)

var upgradeApplyLatestCmd = &cobra.Command{
	Use:   "apply-latest",
	Short: "Discover and apply the latest available version",
	Long: `Fetches tags via git, finds the latest version matching the
configured channel (prerelease/stable/edge), and tells the upgrade service
to upgrade to it immediately.

Used by deploy workflows — all logic is server-side, no workflow
file changes needed.`,
	// apply-latest is the deploy-workflow target. If the binary is stale
	// (e.g. a prior upgrade rolled back leaving cli/ ahead of the binary),
	// stalenessGuard rebuilds + re-execs instead of hard-failing. See
	// cli/cmd/root.go.
	Annotations: map[string]string{"selfheal": "true"},
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
			// Edge: use latest master commit short. Bare 8-char hex (no
			// "sha-" prefix) — the rc.63 canonical-naming cleanup
			// retired that prefix, and ValidateVersion's regex was
			// tightened to release-tag shape only. The bare commit-
			// short form is what the SQL match below expects via
			// `commit_sha LIKE :'target_version' || '%'`.
			if fetchOut, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "master", "--quiet"); err != nil {
				return fmt.Errorf("git fetch origin master: %w\n  output: %s", err, strings.TrimSpace(fetchOut))
			}
			sha, err := upgrade.RunCommandOutput(projDir, "git", "log", "origin/master", "-1", "--format=%H")
			if err != nil {
				return fmt.Errorf("git log origin/master: %w\n  output: %s", err, strings.TrimSpace(sha))
			}
			sha = strings.TrimSpace(sha)
			if len(sha) < 8 {
				return fmt.Errorf("unexpected git log output: %q", sha)
			}
			latestVersion = sha[:8]
		} else {
			// Stable or prerelease: find latest tag
			if fetchOut, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "--tags", "--quiet"); err != nil {
				return fmt.Errorf("git fetch --tags: %w\n  output: %s", err, strings.TrimSpace(fetchOut))
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

		// ValidateVersion answers "is this a release tag" only (rc.63
		// canonical-naming cleanup). Edge channel produces an 8-char
		// commit_short instead — accept either shape.
		if !upgrade.ValidateVersion(latestVersion) && !upgrade.IsCommitShort(latestVersion) {
			return fmt.Errorf("discovered version %q does not pass validation (expected release tag or 8-char commit_short)", latestVersion)
		}

		fmt.Printf("Channel %s: latest version is %s\n", channel, latestVersion)

		// Skip when the running binary is already at the latest. Without
		// this, apply-latest unconditionally flips state='scheduled', the
		// upgrade_notify_daemon_trigger fires NOTIFY upgrade_apply, and the
		// service runs a full no-op upgrade pipeline (stop containers,
		// backup, exit-42, restart, applyNewSbUpgrading) for nothing.
		//
		// Resolve the latest's commit via the SAME git-authoritative resolver the
		// scheduling path uses (STATBUS-169 skip-check fold: the LAST tag-as-selector
		// site — the old psql `ANY(commit_tags)` lookup — moves onto ResolveToCommit
		// so there is ONE resolution shape for every tag→commit read). Compare to the
		// running binary's compiled-in `commit` (cli/cmd/root.go:17, ldflags-set).
		// Fall-throughs to existing behavior:
		//   - commit=="unknown" (local go run): can't compare reliably.
		//   - resolve errors (discovery race / not fetched): let apply-latest
		//     register+schedule it normally — an error NEVER causes a false skip
		//     (the ON_ERROR_STOP floor, now the resolver's error → the rerr guard).
		//   - resolved commit != running binary: genuinely behind; proceed.
		if commit != "" && commit != "unknown" {
			if resolved, rerr := newUpgradeService(projDir).ResolveToCommit(context.Background(), latestVersion); rerr == nil {
				rs := string(resolved)
				if len(rs) >= 8 && len(commit) >= 8 && rs[:8] == commit[:8] {
					fmt.Printf("Already at %s (commit %s) — nothing to apply.\n", latestVersion, commit[:8])
					return nil
				}
			}
		}

		// Route through the REAL mechanism (STATBUS-086): register the latest
		// as a candidate, then schedule it. This is RACE-PROOF — register
		// upserts the row, so schedule always finds it. The old insert-if-missing
		// UPDATE+NOTIFY silently no-op'd when it lost the deploy-before-discovery
		// race (UPDATE 0 rows → NOTIFY → onScheduledNotify require-register
		// no-op → deploy didn't upgrade, and the "will apply next cycle" message
		// lied). register→schedule completes the clean break and keeps deploys
		// deployable. recreateFlag is carried by RunSchedule.
		d := newUpgradeService(projDir)
		if err := d.RunRegister(context.Background(), latestVersion); err != nil {
			return fmt.Errorf("apply-latest register %s: %w", latestVersion, err)
		}
		if err := d.RunSchedule(context.Background(), latestVersion, recreateFlag); err != nil {
			return fmt.Errorf("apply-latest schedule %s: %w", latestVersion, err)
		}

		if w, err := syslog.New(syslog.LOG_INFO, "statbus-upgrade"); err == nil {
			_ = w.Info(fmt.Sprintf("upgrade apply-latest: registered + scheduled %s (channel=%s, recreate=%v)", latestVersion, channel, recreateFlag)) // best-effort syslog note
			_ = w.Close()
		}

		return nil
	},
}

// newUpgradeService builds a Service for the current binary, deriving the
// service version (a git-checkout-able ref) from the ldflags. Shared by the
// `service` daemon and the one-shot verbs (register / schedule / check).
func newUpgradeService(projDir string) *upgrade.Service {
	// Derive serviceVersion — a valid git ref the service can git-checkout.
	// version is cmd.version: git-describe output verbatim, which carries the
	// leading "v" (the canonical CommitVersion form). Rules (priority order):
	//   1. "dev" ldflag   → 8-char commit_short or "dev" (skips downgrade guard)
	//   2. Has "v" prefix → use as-is (v-bearing CalVer from git describe / release.yaml)
	//   3. Anything else  → 8-char commit_short or "dev". Covers the bare
	//      abbreviated SHA `git describe --always` emits when no tag is
	//      reachable; downgrade guard treats it as an unversioned local build.
	//
	// No v-strip/re-prepend dance (STATBUS-064): the value already carries the
	// "v" everywhere, so there is no v-less CalVer form to re-prepend onto.
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
	default:
		// Non-v ldflag (bare --always SHA, stray tag, hand-built binary) — treat as local build.
		if commit != "unknown" {
			serviceVersion = upgrade.ShortForDisplay(commit)
		} else {
			serviceVersion = "dev"
		}
	}
	d := upgrade.NewService(projDir, verbose, serviceVersion, commit)
	// Unit name for the per-dispatch NRestarts reset (STATBUS-039 review
	// finding 2) — derivable only here in cmd; internal/upgrade must not
	// guess it.
	d.SetUnitInstance(serviceInstance(projDir))
	return d
}

var upgradeServiceRunE = func(cmd *cobra.Command, args []string) error {
	return newUpgradeService(config.ProjectDir()).Run(context.Background())
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
	// systemd entrypoint. If a previous upgrade rolled back leaving cli/
	// ahead of the binary, stalenessGuard rebuilds + re-execs instead of
	// crash-looping the service. See cli/cmd/root.go.
	Annotations: map[string]string{"selfheal": "true"},
	RunE:        upgradeServiceRunE,
}

// selfVerifyExpectCommit is bound to `upgrade self-verify --expect-commit`. When
// set (by selfupdate.ReplaceBinaryOnDisk's step 3b), self-verify asserts THIS
// binary's embedded commit equals the named upgrade target. See STATBUS-171.
var selfVerifyExpectCommit string

var upgradeSelfVerifyCmd = &cobra.Command{
	Use:    "self-verify",
	Short:  "Verify the binary can boot and embeds the expected target commit (used during self-update)",
	Hidden: true,
	// STATBUS-171: guard-exempt, exactly like the `committed-drift` probe. This
	// command runs mid-upgrade INSIDE the freshly-procured target binary, while
	// STATBUS-060 deliberately leaves the worktree at the SOURCE commit until the
	// recovery boot. A worktree-relative stalenessGuard here would ALWAYS —
	// correctly, per its own binary-matches-worktree contract — judge the target
	// binary "stale" and abort the swap (BINARY_REPLACE_FAILED; dev row 331014).
	// That is a category error: the question at this site is not "does the binary
	// match the worktree" but "is the binary we just wrote the TARGET we intended",
	// which --expect-commit answers below. stalenessGuard's contract stays the
	// right check at DAEMON BOOT (post-recovery-checkout, HEAD=target) — that
	// coverage is untouched; only this mid-upgrade call site is exempted.
	Annotations: map[string]string{"freshness_probe": "true"},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("sb version: %s\n", rootCmd.Version)
		if err := selfVerifyIdentity(string(commitSHA), selfVerifyExpectCommit); err != nil {
			return err
		}
		fmt.Println("Self-verify: OK")
		return nil
	},
}

// selfVerifyIdentity is the pure core of `upgrade self-verify --expect-commit`
// (STATBUS-171). It confirms a freshly-procured binary whose EMBEDDED build commit
// is `embedded` is the intended upgrade target `expect` — comparing against the
// TARGET, never the worktree. Under STATBUS-060 the worktree is deliberately left
// at the SOURCE commit during the swap, so a worktree-relative check here is a
// category error that fails every tag-identified upgrade.
//
//   - expect == "":   boot-only self-verify (legacy caller); no identity assertion.
//   - embedded == "": unidentifiable binary (no ldflags) with a target demanded →
//     hard fail; we cannot confirm it is the target.
//   - otherwise: prefix-both-ways match (short-vs-full SHA), mirroring the manifest
//     anti-tamper check (the adjacent 060 fix in service.go executeUpgrade).
func selfVerifyIdentity(embedded, expect string) error {
	if expect == "" {
		return nil
	}
	if embedded == "" {
		return fmt.Errorf("self-verify: this binary has no reliable commit identity (built without ldflags) — cannot confirm it is the upgrade target %s",
			upgrade.ShortForDisplay(expect))
	}
	if !strings.HasPrefix(embedded, expect) && !strings.HasPrefix(expect, embedded) {
		return fmt.Errorf("self-verify: procured binary embeds commit %s but the upgrade target is %s — wrong or mis-built artifact",
			upgrade.ShortForDisplay(embedded), upgrade.ShortForDisplay(expect))
	}
	return nil
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
	defer func() { _ = resp.Body.Close() }()

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
	defer func() { _ = resp.Body.Close() }()

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
		_ = os.MkdirAll(filepath.Join(projDir, "tmp"), 0755) // best-effort; the WriteFile right after surfaces any real failure
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
	upgradeScheduleCmd.Flags().BoolVar(&recreateFlag, "recreate", false, "delete and recreate database from scratch (destructive — dev/demo only)")
	upgradeApplyLatestCmd.Flags().BoolVar(&recreateFlag, "recreate", false, "delete and recreate database from scratch (destructive — dev/demo only)")

	trustKeyAddCmd.Flags().BoolVarP(&trustKeyAddYes, "yes", "y", false, "skip confirmation prompt (for scripted / AI-driven installs)")
	trustKeyCmd.AddCommand(trustKeyListCmd)
	trustKeyCmd.AddCommand(trustKeyAddCmd)
	trustKeyCmd.AddCommand(trustKeyRemoveCmd)
	trustKeyCmd.AddCommand(trustKeyVerifyCmd)

	upgradeCmd.AddCommand(upgradeCheckCmd)
	upgradeCmd.AddCommand(upgradeRegisterCmd)
	upgradeCmd.AddCommand(upgradeListCmd)
	upgradeCmd.AddCommand(upgradeScheduleCmd)
	upgradeCmd.AddCommand(upgradeApplyLatestCmd)
	upgradeCmd.AddCommand(upgradeChannelCmd)
	upgradeCmd.AddCommand(upgradeServiceCmd)
	upgradeSelfVerifyCmd.Flags().StringVar(&selfVerifyExpectCommit, "expect-commit", "",
		"assert this binary embeds the given target commit (used by the upgrade self-update; STATBUS-171)")
	upgradeCmd.AddCommand(upgradeSelfVerifyCmd)
	upgradeCmd.AddCommand(upgradeSelfRollbackCmd)
	upgradeCmd.AddCommand(trustKeyCmd)
	rootCmd.AddCommand(upgradeCmd)
}
