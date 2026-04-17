package cmd

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

var nonInteractive bool

// insideActiveUpgrade signals that this install invocation is a post-upgrade
// fixup spawned by the upgrade service itself. It is NOT a user-facing flag —
// operators must never pass it. The service at service.go:executeUpgrade sets
// both this CLI flag and STATBUS_INSIDE_ACTIVE_UPGRADE=1 env var on its child
// exec; either triggers the mutex bypass in runInstall.
var insideActiveUpgrade bool


var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install or resume StatBus installation",
	Long: `Unified entrypoint for first-install, repair, and dispatching a
pending upgrade. Probes the install state and routes:

  - Fresh directory         → runs the install step-table.
  - Existing install        → idempotent config-refresh (safe to re-run).
  - Scheduled upgrade row   → dispatches the upgrade inline through the
                              same pipeline the service uses (backup,
                              checkout, migrate, restart, health-check,
                              rollback on failure).
  - Crashed upgrade flag    → reconciles, re-probes, re-dispatches.
  - Live upgrade running    → refuses (points at journalctl).
  - Pre-1.0 database        → refuses (points at the manual upgrade path).

To upgrade an existing install, schedule the target version first:

  ./sb upgrade schedule v2026.03.1
  ./sb install                  # dispatches the scheduled upgrade

Or let the systemd upgrade service pick it up on its next tick.

Example first install (interactive):
  ./sb install

Example scripted install (non-interactive):
  # Pre-create .env.config, then:
  ./sb install --non-interactive

Example with statbus.nso.eu domain:
  ./sb install
  # Prompts for: mode=standalone, domain=statbus.nso.eu, name=StatBus, code=nso`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runInstall()
	},
}

func init() {
	installCmd.Flags().BoolVar(&nonInteractive, "non-interactive", false,
		"Run without prompts (requires .env.config to exist)")
	installCmd.Flags().BoolVar(&insideActiveUpgrade, "inside-active-upgrade", false,
		"Internal: set by the upgrade service when spawning install as a post-upgrade fixup. Operators must not pass this.")
	// Hide the internal flag from --help; it's a contract between service and child install, not a user-facing knob.
	_ = installCmd.Flags().MarkHidden("inside-active-upgrade")
	rootCmd.AddCommand(installCmd)
}

// step represents one installation step with an idempotency check.
type step struct {
	name  string
	check func(dir string) bool // returns true if step is already done
	run   func(dir string) error
}

// acquireOrBypass enforces the install ↔ upgrade-service mutual exclusion.
//
// Both the upgrade service and `./sb install` write the same marker file
// (tmp/upgrade-in-progress.json) via O_CREATE|O_EXCL — the kernel
// guarantees exactly one writer wins. The Holder field distinguishes
// service-vs-install ownership; recoverFromFlag uses Holder to decide
// what cleanup is needed when a writer crashed (DB reconciliation for
// service, file-removal-only for install).
//
// When `bypass` is true, the caller is the upgrade service's own
// post-upgrade fixup — the parent service already holds the flag, so the
// child install neither acquires nor releases. Otherwise:
//   - No flag → atomic acquire succeeds; returns a release function the
//     caller must defer.
//   - Flag exists (any holder, alive or dead) → returns a formatted error
//     guiding the operator to wait or run `./sb upgrade recover`.
//
// Returns (releaseFunc, nil) on success; (nil-no-op, err) on contention.
func acquireOrBypass(installDir string, bypass bool) (release func(), err error) {
	if bypass {
		// Verify-only diagnostic. The parent's flag is on disk; we don't
		// touch it. Print holder info for the audit log.
		if flag, _, rerr := upgrade.ReadFlagFile(installDir); rerr == nil && flag != nil {
			fmt.Printf("Upgrade mutex bypass honored (--inside-active-upgrade). Flag owned by PID %d (holder=%s), invoked_by=%s.\n",
				flag.PID, flag.Holder, flag.InvokedBy)
		} else {
			fmt.Printf("Note: --inside-active-upgrade set but no upgrade flag found. Proceeding.\n")
		}
		return func() {}, nil
	}

	displayName := fmt.Sprintf("install (PID %d)", os.Getpid())
	invokedBy := "operator"
	if u := os.Getenv("USER"); u != "" {
		invokedBy = "operator:" + u
	}
	lock, err := upgrade.AcquireInstallFlag(installDir, displayName, invokedBy)
	if err != nil {
		return nil, err
	}
	// Keep the FlagLock alive until the install completes. The returned
	// closure is deferred by the caller (runInstall) so normal exit and
	// all error paths release the flock. Crash-exit releases it via
	// kernel fd teardown.
	return func() { upgrade.ReleaseInstallFlag(lock) }, nil
}

// runInstall is the entry point for `./sb install`. It is safe to run while
// an upgrade service is active on the same host because of the mutex check
// below: if the upgrade service has written tmp/upgrade-in-progress.json
// (which it does before any destructive step in executeUpgrade), this function
// refuses to proceed. The only exception is the service's own post-upgrade
// fixup, which passes --inside-active-upgrade / STATBUS_INSIDE_ACTIVE_UPGRADE=1
// to signal "I am the active upgrade, not a conflicting actor."
func runInstall() (installErr error) {
	// Warn if running as root — the upgrade service is a user-level systemd unit now,
	// running as root would create files owned by root in the project dir.
	if os.Geteuid() == 0 {
		fmt.Println("Warning: running as root. The upgrade service is a user-level systemd unit.")
		fmt.Println("Run as the application user instead: ./sb install")
		fmt.Println()
	}

	fmt.Println("StatBus Installation")
	fmt.Println("====================")
	fmt.Println()

	// Detect non-interactive from stdin if not explicitly set
	if !nonInteractive {
		if fi, err := os.Stdin.Stat(); err == nil {
			if fi.Mode()&os.ModeCharDevice == 0 {
				nonInteractive = true
			}
		}
	}

	// Resolve project dir early — the upgrade-in-progress flag lives under it.
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot determine home directory (HOME unset?): %w", err)
	}
	installDir := filepath.Join(home, "statbus")

	// === Upgrade mutex acquire ===
	// Atomically claim tmp/upgrade-in-progress.json (Holder="install") so
	// any other actor — running upgrade service, another install — sees us
	// and aborts. ReleaseInstallFlag in defer cleans up on every exit path.
	// The ONLY caller allowed to bypass is the upgrade service itself
	// (service.go:executeUpgrade spawns install as a post-upgrade fixup
	// with --inside-active-upgrade + env var set; the service already holds
	// the flag for that exec, so the child must not try to acquire it).
	bypass := insideActiveUpgrade || os.Getenv("STATBUS_INSIDE_ACTIVE_UPGRADE") == "1"

	// === State detection + dispatch ===
	// Detect reads the install directory + DB to classify the install state.
	// In the bypass path the parent upgrade service already knows; skip
	// detection to avoid probing the DB mid-upgrade.
	//
	// Dispatch policy:
	//   StateLiveUpgrade      → refuse BEFORE acquireOrBypass so the message
	//                           is an authoritative refusal, not a flock error.
	//   StateScheduledUpgrade → hand off to executeUpgrade (the upgrade
	//                           service's pipeline) WITHOUT acquiring the
	//                           install flag — executeUpgrade writes its own
	//                           HolderService flag internally before any
	//                           destructive step. This is Option A of the
	//                           flag-lock ownership design: ownership transfer
	//                           matches the flock primitive.
	//   StateCrashedUpgrade   → run RecoverFromFlag (clears stale flag,
	//                           reconciles the DB row), re-detect, re-dispatch.
	//                           The re-detect may land us in any other state.
	//   StateLegacyNoUpgradeTable → refuse with a pointer to #65.6 (the
	//                           pre-1.0 cascade lands there).
	//   all other states      → fall through to acquireOrBypass + step-table.
	var detectedState install.State
	if !bypass {
		state, detail, derr := install.Detect(installDir, version)
		if derr != nil {
			fmt.Printf("Warning: state detection failed: %v\n", derr)
		} else {
			detectedState = state
			logInstallState(state, detail)
			if state == install.StateCrashedUpgrade {
				if err := runCrashRecovery(installDir); err != nil {
					return fmt.Errorf("crash recovery: %w", err)
				}
				state, detail, derr = install.Detect(installDir, version)
				if derr != nil {
					return fmt.Errorf("re-detect after recovery: %w", derr)
				}
				detectedState = state
				fmt.Printf("  State after recovery: %s (target=%s)\n", state, detail.TargetVersion)
			}
			if handled, err := dispatchInstallState(installDir, state, detail); handled {
				return err
			}
		}
	}

	// Pre-flight: on existing installs (.env.config exists), require at
	// least one trusted signer BEFORE doing any work. Fresh installs skip
	// this — .env.config doesn't exist yet (step 5 creates it, step 13
	// prompts for signers). Re-installs that removed their signer get a
	// fast, actionable failure instead of wasting 2 minutes on steps 1-12.
	if !bypass {
		cfgPath := filepath.Join(installDir, ".env.config")
		if _, statErr := os.Stat(cfgPath); statErr == nil && !checkSignersDone(installDir) {
			if nonInteractive {
				return fmt.Errorf("no trusted signers configured.\n" +
					"  The upgrade service requires at least one trusted signer to verify release signatures.\n" +
					"  Pre-configure before running install:\n" +
					"    ./sb upgrade trust-key add <github-username>\n" +
					"  Then re-run the install.")
			}
			fmt.Println("No trusted signers configured. You must approve at least one signer before the install can proceed.")
			if err := runTrustSigners(installDir); err != nil {
				return err
			}
		}
	}

	releaseFlag, err := acquireOrBypass(installDir, bypass)
	if err != nil {
		return err
	}
	defer releaseFlag()

	// Pre-flight: check disk space
	if freeBytes, err := upgrade.DiskFree("."); err == nil {
		freeGB := freeBytes / (1024 * 1024 * 1024)
		if freeGB < 100 {
			return fmt.Errorf("insufficient disk space: %d GB free (need at least 100 GB for database, images, and backups)", freeGB)
		}
		fmt.Printf("Disk space: %d GB free\n", freeGB)
	}

	// --- Upgrade row lifecycle ---
	// Mirror the service path: in_progress at start, completed/failed at end.
	// For re-installs (StateNothingScheduled) the DB is up — write in_progress
	// so the admin UI shows the install in progress. For fresh installs the DB
	// doesn't exist until step 10 (migrations), so we only write at the end.
	var upgradeRowID int64
	if !bypass && version != "dev" && detectedState == install.StateNothingScheduled {
		upgradeRowID = startInstallUpgradeRow(installDir)
	}
	if !bypass && version != "dev" {
		defer func() {
			if installErr != nil && upgradeRowID > 0 {
				failInstallUpgradeRow(installDir, upgradeRowID, installErr)
			} else if installErr == nil {
				completeInstallUpgradeRow(installDir, upgradeRowID)
			}
		}()
	}

	steps := []step{
		{"Prerequisites", checkPrereqDone, runPrereq},
		{"Repository", checkRepoDone, runCloneRepo},
		{"Binary", checkBinaryDone, runInstallBinary},
		{"Configuration", checkConfigDone, runCreateConfig},
		{"Credentials", checkCredsDone, runCreateCreds},
		{"Generated env", checkEnvDone, runGenerateEnv},
		{"Images", checkImagesDone, runPullImages},
		{"Services", checkServicesDone, runStartServices},
		{"Snapshot", checkSnapshotRestored, runSnapshotRestore},
		{"Migrations", checkMigrationsDone, runMigrations},
		{"JWT secret", checkJWTDone, runLoadJWT},
		{"Users", checkUsersDone, runCreateUsers},
		{"Trusted signers", checkSignersDone, runTrustSigners},
		{"Upgrade service", checkServiceDone, runInstallService},
	}

	total := len(steps)
	allDone := true

	for i, s := range steps {
		prefix := fmt.Sprintf("[%d/%d] %-20s", i+1, total, s.name)

		if s.check(installDir) {
			fmt.Printf("%s OK\n", prefix)
			continue
		}

		allDone = false
		fmt.Printf("%s RUNNING\n", prefix)

		if err := s.run(installDir); err != nil {
			fmt.Printf("%s FAILED: %v\n", prefix, err)
			if i < total-1 {
				fmt.Printf("\nFix the issue and re-run: ./sb install\n")
				fmt.Printf("(Steps 1-%d will be skipped automatically)\n", i)
			}
			return err
		}

		fmt.Printf("%s DONE\n", prefix)
	}

	fmt.Println()
	if allDone {
		fmt.Println("All steps complete. Nothing to do.")
	} else {
		fmt.Println("Installation complete!")
		fmt.Println("=====================")
		if f, err := dotenv.Load(filepath.Join(installDir, ".env.config")); err == nil {
			if domain, ok := f.Get("SITE_DOMAIN"); ok {
				fmt.Printf("Visit: https://%s\n", domain)
			}
		}
		fmt.Printf("Management: cd %s && ./sb --help\n", installDir)
	}

	return nil
}

// ── Step checks (return true if step is already done) ──

func checkPrereqDone(_ string) bool {
	_, dockerErr := exec.LookPath("docker")
	_, gitErr := exec.LookPath("git")
	composeErr := exec.Command("docker", "compose", "version").Run()
	return dockerErr == nil && gitErr == nil && composeErr == nil
}

func checkRepoDone(dir string) bool {
	gitDir := filepath.Join(dir, ".git")
	_, err := os.Stat(gitDir)
	return err == nil
}

func checkBinaryDone(dir string) bool {
	sb := filepath.Join(dir, "sb")
	info, err := os.Stat(sb)
	return err == nil && info.Mode().Perm()&0111 != 0
}

func checkConfigDone(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, ".env.config"))
	return err == nil
}

func checkCredsDone(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, ".env.credentials"))
	return err == nil
}

func checkEnvDone(dir string) bool {
	// Always regenerate .env — code checkout may change variable names
	// (e.g., NEXT_PUBLIC_* → PUBLIC_*) and .env must match docker-compose.
	return false
}

func checkImagesDone(dir string) bool {
	cmd := exec.Command("docker", "compose", "--profile", "all", "images", "-q")
	cmd.Dir = dir
	out, err := cmd.Output()
	// If we get at least 4 image IDs, images are available
	return err == nil && len(strings.Split(strings.TrimSpace(string(out)), "\n")) >= 4
}

func checkServicesDone(dir string) bool {
	cmd := exec.Command("docker", "compose", "ps", "--format", "{{.Health}}", "--filter", "name=db")
	cmd.Dir = dir
	out, err := cmd.Output()
	return err == nil && strings.Contains(string(out), "healthy")
}

func checkMigrationsDone(dir string) bool {
	// Done iff there are no pending migration files vs db.migration.
	// migrate.HasPending compares disk (migrations/*.up.sql) against the
	// applied versions table; single source of truth shared with `migrate up`.
	//
	// Historical note: this used to return true whenever MAX(version)>0 — i.e.
	// "any migration applied = all done" — which silently skipped newer
	// migrations on upgrade. That bug wedged five cloud servers on v2026.03.1.
	pending, err := migrate.HasPending(dir)
	if err != nil {
		// On error, fall through to runMigrations (it will surface the error
		// cleanly). "Done" would hide a real problem.
		return false
	}
	return !pending
}

func checkJWTDone(dir string) bool {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	args := append(prefix, "-t", "-A", "-c",
		"SELECT COUNT(*) FROM auth.secrets WHERE key = 'jwt_secret' AND value != '';")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	return err == nil && strings.TrimSpace(string(out)) == "1"
}

func checkUsersDone(dir string) bool {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	args := append(prefix, "-t", "-A", "-c",
		"SELECT COUNT(*) FROM auth.\"user\";")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	count := strings.TrimSpace(string(out))
	return count != "0" && count != ""
}

func checkServiceDone(dir string) bool {
	if runtime.GOOS != "linux" {
		return true // Skip on non-Linux
	}
	instance := serviceInstance(dir)
	if instance == "" {
		return false
	}
	// User-level systemd service — no root needed to manage.
	// Check is-active (running), not just is-enabled (starts on boot).
	cmd := exec.Command("systemctl", "--user", "is-active", instance)
	return cmd.Run() == nil
}

// serviceInstance returns the systemd instance name, e.g. "statbus-upgrade@statbus_dev.service"
func serviceInstance(dir string) string {
	f, err := dotenv.Load(filepath.Join(dir, ".env.config"))
	if err != nil {
		return ""
	}
	code, ok := f.Get("DEPLOYMENT_SLOT_CODE")
	if !ok || code == "" {
		return ""
	}
	return fmt.Sprintf("statbus-upgrade@statbus_%s.service", code)
}

// ── Step runners ──

func runPrereq(_ string) error {
	return checkPrerequisites()
}

func runCloneRepo(dir string) error {
	if err := runCmd("git", "clone", "--depth", "1",
		"https://github.com/statisticsnorway/statbus.git", dir); err != nil {
		return err
	}
	// Configure deploy branch fetch refspec if slot code is known
	configureDeployFetch(dir)
	return nil
}

// configureDeployFetch adds the slot-specific deploy branch to the git fetch refspec.
// e.g., for slot "dev": +refs/heads/ops/cloud/deploy/dev:refs/remotes/origin/ops/cloud/deploy/dev
// Idempotent — safe to call on existing repos.
func configureDeployFetch(dir string) {
	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return // no config yet, will be called again after config is created
	}
	code, ok := f.Get("DEPLOYMENT_SLOT_CODE")
	if !ok || code == "" {
		return
	}

	branch := fmt.Sprintf("ops/cloud/deploy/%s", code)
	refspec := fmt.Sprintf("+refs/heads/%s:refs/remotes/origin/%s", branch, branch)

	// Remove any stale devops/* refspecs — they refer to branches renamed
	// during R1.1 and every subsequent `git fetch` errors on them. Shared
	// helper so `./sb upgrade apply-latest` can self-heal before its own
	// fetch without duplicating the cleanup logic.
	upgrade.CleanStaleRefspecs(dir)

	cmd := exec.Command("git", "config", "--get-all", "remote.origin.fetch")
	cmd.Dir = dir
	out, _ := cmd.Output()

	if strings.Contains(string(out), refspec) {
		return // already configured
	}

	// Check if the branch exists on the remote before adding
	check := exec.Command("git", "ls-remote", "--exit-code", "--heads", "origin", branch)
	check.Dir = dir
	if check.Run() != nil {
		return // branch doesn't exist on remote, skip
	}

	add := exec.Command("git", "config", "--add", "remote.origin.fetch", refspec)
	add.Dir = dir
	add.Run()
}

func runInstallBinary(dir string) error {
	sbDst := filepath.Join(dir, "sb")
	sbSrc, err := os.Executable()
	if err != nil {
		return fmt.Errorf("find current binary: %w", err)
	}
	// Don't copy if we're already running from the install dir
	if sbSrc == sbDst {
		return nil
	}
	if err := copyFile(sbSrc, sbDst); err != nil {
		return fmt.Errorf("copy binary: %w", err)
	}
	return os.Chmod(sbDst, 0755)
}

func runCreateConfig(dir string) error {
	cfgPath := filepath.Join(dir, ".env.config")

	if nonInteractive {
		return fmt.Errorf(".env.config not found\n\n" +
			"  Create .env.config with at minimum:\n" +
			"    DEPLOYMENT_SLOT_CODE=xx\n" +
			"    CADDY_DEPLOYMENT_MODE=standalone\n" +
			"    SITE_DOMAIN=statbus.nso.eu\n" +
			"\n  Then re-run: ./sb install --non-interactive")
	}

	fmt.Println()
	mode := prompt("  Deployment mode (development/standalone/private)", "standalone")
	domain := prompt("  Domain name", "statbus.nso.eu")
	name := prompt("  Display name", "StatBus")
	code := prompt("  Deployment code (short, lowercase)", "local")

	cfgContent := fmt.Sprintf(`DEPLOYMENT_SLOT_NAME=%s
DEPLOYMENT_SLOT_CODE=%s
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=%s
SITE_DOMAIN=%s
`, name, code, mode, domain)

	return os.WriteFile(cfgPath, []byte(cfgContent), 0644)
}

func runCreateCreds(dir string) error {
	// sb config generate creates .env.credentials if missing
	sb := filepath.Join(dir, "sb")
	return runCmdDir(dir, sb, "config", "generate")
}

func runGenerateEnv(dir string) error {
	// Align with latest code — but only if we're on master (not a tag/detached HEAD).
	// The upgrade service checks out a specific commit; install should respect that.
	// Servers on ops branches (e.g. ops/cloud/deploy/no) also need to align with master.
	branchOut, err := upgrade.RunCommandOutput(dir, "git", "symbolic-ref", "--short", "HEAD")
	branch := strings.TrimSpace(branchOut)
	if err == nil && (branch == "master" || strings.HasPrefix(branch, "ops/")) {
		if err := runCmdDir(dir, "git", "fetch", "origin", "master"); err != nil {
			fmt.Printf("  Warning: git fetch origin master failed: %v\n", err)
		}
		if err := runCmdDir(dir, "git", "checkout", "master"); err != nil {
			fmt.Printf("  Warning: git checkout master failed: %v\n", err)
		}
		if err := runCmdDir(dir, "git", "merge", "--ff-only", "origin/master"); err != nil {
			fmt.Printf("  Warning: git merge origin/master failed: %v\n", err)
		}
	}

	// Migrate .env.config paths from devops/ → ops/ (one-time, idempotent)
	migrateConfigPaths(dir)

	sb := filepath.Join(dir, "sb")
	if err := runCmdDir(dir, sb, "config", "generate"); err != nil {
		return err
	}
	// Now that config exists, ensure deploy branch fetch is configured
	configureDeployFetch(dir)
	// Create backup directory for upgrade service (systemd unit expects it)
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot determine home directory (HOME unset?): %w", err)
	}
	backupDir := filepath.Join(home, "statbus-backups")
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		fmt.Printf("  Warning: could not create backup dir %s: %v\n", backupDir, err)
	}
	// Create maintenance directory for Caddy volume mount
	maintDir := filepath.Join(home, "statbus-maintenance")
	if err := os.MkdirAll(maintDir, 0755); err != nil {
		fmt.Printf("  Warning: could not create maintenance dir %s: %v\n", maintDir, err)
	}
	return nil
}

func runPullImages(dir string) error {
	// Try pull first (pre-built from ghcr.io)
	if err := runCmdDir(dir, "docker", "compose", "--profile", "all", "pull"); err != nil {
		// Fall back to build for services without pre-built images
		fmt.Println("  Pull incomplete, building remaining images locally...")
		return runCmdDir(dir, "docker", "compose", "--profile", "all", "build")
	}
	return nil
}

func runStartServices(dir string) error {
	return runCmdDir(dir, "docker", "compose", "--profile", "all", "up", "-d")
}

// checkSnapshotRestored returns true if the database already has migrations
// (re-install scenario — snapshot restore would be destructive).
// Returns false only for truly fresh installs where the DB is empty.
//
// Intent: the snapshot is a FAST PATH for fresh installs only. Restoring
// over an existing database drops objects while migration records survive,
// leaving the DB in an inconsistent state.
func checkSnapshotRestored(dir string) bool {
	// If services aren't running yet, we can't check the DB.
	// Return true to skip — the Services step must run first.
	if !checkServicesDone(dir) {
		return true
	}

	// Services are running. Wait for DB to be healthy, then check migrations.
	// If we can't reach the DB after 30 seconds, FAIL HARD — don't silently
	// fall through and restore a snapshot over an existing database.
	for attempt := 0; attempt < 15; attempt++ {
		if checkMigrationsDone(dir) {
			return true // DB has migrations — do NOT restore snapshot
		}
		if attempt < 14 {
			time.Sleep(2 * time.Second)
		}
	}

	// DB is reachable (services running) but has no migrations.
	// This is a genuinely fresh database — snapshot restore is appropriate.
	return false
}

// runSnapshotRestore fetches the snapshot from origin/db-snapshot and restores
// it into the database. This makes `migrate up` fast — only migrations newer
// than the snapshot need to run.
func runSnapshotRestore(dir string) error {
	sb := filepath.Join(dir, "sb")

	// Fetch snapshot from remote.
	fmt.Println("  Fetching snapshot from origin/db-snapshot...")
	if err := runCmdDir(dir, sb, "db", "snapshot", "fetch"); err != nil {
		// Not fatal — fresh repos or private forks may not have the branch.
		fmt.Println("  No snapshot available — will run all migrations")
		return nil
	}

	// Restore into the default database (configured in .env).
	fmt.Println("  Restoring snapshot...")
	if err := runCmdDir(dir, sb, "db", "snapshot", "restore"); err != nil {
		// Not fatal — migrate up will run all migrations from scratch.
		fmt.Println("  Snapshot restore failed — will run all migrations")
		return nil
	}

	return nil
}

func runMigrations(dir string) error {
	sb := filepath.Join(dir, "sb")
	return runCmdDir(dir, sb, "migrate", "up", "--verbose")
}

func runLoadJWT(dir string) error {
	// Reuse the ensureJWTSecret function from users.go
	return ensureJWTSecret(dir)
}

func runCreateUsers(dir string) error {
	sb := filepath.Join(dir, "sb")
	return runCmdDir(dir, sb, "users", "create")
}

func checkSignersDone(dir string) bool {
	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return false
	}
	for _, key := range f.Keys() {
		if strings.HasPrefix(key, trustedSignerPrefix) {
			return true
		}
	}
	return false
}

func runTrustSigners(dir string) error {
	if nonInteractive {
		return fmt.Errorf("no trusted signers configured (non-interactive mode cannot prompt).\n" +
			"  The upgrade service requires at least one trusted signer to verify release signatures.\n" +
			"  Pre-configure before running install:\n" +
			"    ./sb upgrade trust-key add <github-username>\n" +
			"  Then re-run: ./sb install --non-interactive")
	}

	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return fmt.Errorf("load .env.config: %w", err)
	}

	reader := bufio.NewReader(os.Stdin)
	defaultSigner := "jhf"

	fmt.Println()
	fmt.Println("  StatBus recommends trusting the following release signer:")
	fmt.Printf("    %s (Jorgen H. Fjeld) -- https://github.com/%s\n", defaultSigner, defaultSigner)

	trusted, err := trustSignerInteractive(defaultSigner, f, reader)
	if err != nil {
		fmt.Printf("  Warning: could not fetch keys for %s: %v\n", defaultSigner, err)
		fmt.Println("  You can add trusted signers later with: ./sb upgrade trust-key add <github-username>")
		return nil // Non-fatal: don't block installation
	}
	if !trusted {
		fmt.Println("  Skipped. You can add trusted signers later with: ./sb upgrade trust-key add <github-username>")
		return nil
	}

	// Offer to add additional signers
	for {
		fmt.Print("\n  Add additional trusted signer? (GitHub username, or Enter to skip): ")
		username, _ := reader.ReadString('\n')
		username = strings.TrimSpace(username)
		if username == "" {
			break
		}

		// Reload the file in case trustSignerInteractive saved changes
		f, err = dotenv.Load(cfgPath)
		if err != nil {
			return fmt.Errorf("reload .env.config: %w", err)
		}

		trusted, err := trustSignerInteractive(username, f, reader)
		if err != nil {
			fmt.Printf("  Warning: could not fetch keys for %s: %v\n", username, err)
			continue
		}
		if !trusted {
			fmt.Println("  Skipped.")
		}
	}

	return nil
}

func runInstallService(dir string) error {
	if runtime.GOOS != "linux" {
		fmt.Println("  Skipping systemd on non-Linux")
		return nil
	}

	instance := serviceInstance(dir)
	if instance == "" {
		return fmt.Errorf("could not determine service instance name (check DEPLOYMENT_SLOT_CODE in .env.config)")
	}

	// Install as a user-level systemd service — no root needed.
	// The service file is copied to ~/.config/systemd/user/ and managed
	// with systemctl --user. This works on standalone deployments where
	// the user has no root access.
	userServiceDir := filepath.Join(os.Getenv("HOME"), ".config", "systemd", "user")
	if err := os.MkdirAll(userServiceDir, 0755); err != nil {
		return fmt.Errorf("create systemd user dir: %w", err)
	}

	serviceFile := filepath.Join(dir, "ops", "statbus-upgrade.service")
	destFile := filepath.Join(userServiceDir, "statbus-upgrade@.service")

	fmt.Printf("  Copying %s → %s\n", filepath.Base(serviceFile), destFile)
	if err := copyFile(serviceFile, destFile); err != nil {
		return fmt.Errorf("copy service file: %w", err)
	}

	fmt.Println("  Running systemctl --user daemon-reload")
	if err := runCmd("systemctl", "--user", "daemon-reload"); err != nil {
		return fmt.Errorf("systemctl daemon-reload: %w", err)
	}

	// Enable linger so the user service runs even when not logged in.
	// This requires loginctl which is available on systemd systems.
	fmt.Println("  Enabling linger for user services")
	runCmd("loginctl", "enable-linger", os.Getenv("USER"))

	fmt.Printf("  Enabling and starting %s\n", instance)
	if err := runCmd("systemctl", "--user", "enable", "--now", instance); err != nil {
		return fmt.Errorf("enable service: %w", err)
	}

	fmt.Printf("  Upgrade service installed and started: %s\n", instance)
	return nil
}

// gitHeadInfo returns the HEAD commit SHA and ISO-8601 commit date, or empty
// strings if git is unavailable (e.g., non-git install from tarball).
func gitHeadInfo(dir string) (sha, commitDate string) {
	out, err := upgrade.RunCommandOutput(dir, "git", "rev-parse", "HEAD")
	if err != nil {
		return "", ""
	}
	sha = strings.TrimSpace(out)
	if len(sha) != 40 {
		return "", ""
	}
	out, err = upgrade.RunCommandOutput(dir, "git", "log", "-1", "--format=%cI", "HEAD")
	if err != nil {
		return sha, ""
	}
	return sha, strings.TrimSpace(out)
}

func classifyReleaseStatus(ver string) string {
	if !strings.HasPrefix(ver, "v") {
		return "commit"
	}
	if strings.Contains(ver[1:], "-") {
		return "prerelease"
	}
	return "release"
}

// runInstallSQL runs a single psql statement with named-parameter binding.
// vars is a flat list of name, value pairs (e.g., "sha", "abc123", "version", "v1.0").
// Returns combined output and any error.
func runInstallSQL(dir, sql string, vars ...string) (string, error) {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return "", err
	}
	args := append(append([]string{}, prefix...), "-v", "ON_ERROR_STOP=on", "-X", "-A", "-t")
	for i := 0; i+1 < len(vars); i += 2 {
		args = append(args, "-v", fmt.Sprintf("%s=%s", vars[i], vars[i+1]))
	}
	args = append(args, "-c", sql)
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// startInstallUpgradeRow inserts an in_progress row for the current HEAD so the
// admin UI shows the install in progress. Only called for re-installs where the
// DB is already up (StateNothingScheduled). Returns the row ID, or 0 on failure.
func startInstallUpgradeRow(dir string) int64 {
	sha, commitDate := gitHeadInfo(dir)
	if sha == "" || commitDate == "" {
		return 0
	}

	sql := `INSERT INTO public.upgrade (
  commit_sha, committed_at, summary, state,
  version, release_status, scheduled_at, started_at, from_version
) VALUES (
  :'sha', :'committed_at'::timestamptz,
  :'summary', 'in_progress',
  :'version', :'release_status'::release_status_type,
  clock_timestamp(), clock_timestamp(),
  (SELECT version FROM public.upgrade WHERE state = 'completed' ORDER BY completed_at DESC NULLS LAST LIMIT 1)
)
ON CONFLICT (commit_sha) DO UPDATE SET
  state = 'in_progress',
  started_at = COALESCE(upgrade.started_at, clock_timestamp()),
  scheduled_at = COALESCE(upgrade.scheduled_at, clock_timestamp()),
  completed_at = NULL,
  error = NULL,
  rolled_back_at = NULL,
  from_version = COALESCE(upgrade.from_version, EXCLUDED.from_version),
  version = COALESCE(EXCLUDED.version, upgrade.version)
WHERE upgrade.state NOT IN ('in_progress', 'completed')
RETURNING id`

	out, err := runInstallSQL(dir, sql,
		"sha", sha,
		"committed_at", commitDate,
		"summary", fmt.Sprintf("Installing via ./sb install (%s)", version),
		"version", version,
		"release_status", classifyReleaseStatus(version))
	if err != nil {
		fmt.Printf("  Note: could not start upgrade row: %v\n", err)
		return 0
	}
	line := strings.TrimSpace(out)
	if line == "" {
		return 0
	}
	id, err := strconv.ParseInt(line, 10, 64)
	if err != nil {
		return 0
	}
	fmt.Printf("  Upgrade row %d: in_progress (%s)\n", id, version)
	return id
}

// completeInstallUpgradeRow marks the upgrade row completed (or creates a new
// completed row if no in_progress row was started — e.g., fresh installs).
func completeInstallUpgradeRow(dir string, rowID int64) {
	if rowID > 0 {
		sql := `UPDATE public.upgrade SET state = 'completed', completed_at = clock_timestamp()
WHERE id = :'row_id' AND state = 'in_progress'`
		if _, err := runInstallSQL(dir, sql, "row_id", strconv.FormatInt(rowID, 10)); err != nil {
			fmt.Printf("  Note: could not mark upgrade row %d completed: %v\n", rowID, err)
			return
		}
		fmt.Printf("  Upgrade row %d: completed\n", rowID)
		return
	}

	sha, commitDate := gitHeadInfo(dir)
	if sha == "" || commitDate == "" {
		fmt.Printf("  Note: could not determine commit SHA; skipping upgrade row\n")
		return
	}

	sql := `INSERT INTO public.upgrade (
  commit_sha, committed_at, summary, state, completed_at,
  version, release_status, scheduled_at, started_at, from_version
) VALUES (
  :'sha', :'committed_at'::timestamptz,
  :'summary', 'completed', clock_timestamp(),
  :'version', :'release_status'::release_status_type,
  clock_timestamp(), clock_timestamp(),
  (SELECT version FROM public.upgrade WHERE state = 'completed' ORDER BY completed_at DESC NULLS LAST LIMIT 1)
)
ON CONFLICT (commit_sha) DO UPDATE SET
  state = 'completed',
  completed_at = COALESCE(upgrade.completed_at, clock_timestamp()),
  started_at = COALESCE(upgrade.started_at, clock_timestamp()),
  scheduled_at = COALESCE(upgrade.scheduled_at, clock_timestamp()),
  error = NULL,
  rolled_back_at = NULL,
  version = COALESCE(EXCLUDED.version, upgrade.version)
WHERE upgrade.state != 'completed'`

	if _, err := runInstallSQL(dir, sql,
		"sha", sha,
		"committed_at", commitDate,
		"summary", fmt.Sprintf("Installed via ./sb install (%s)", version),
		"version", version,
		"release_status", classifyReleaseStatus(version)); err != nil {
		fmt.Printf("  Note: could not record upgrade row: %v\n", err)
		return
	}
	fmt.Printf("  Recorded installed version %s in upgrade table\n", version)
}

// failInstallUpgradeRow marks the in_progress row as failed.
func failInstallUpgradeRow(dir string, rowID int64, stepErr error) {
	errMsg := stepErr.Error()
	if len(errMsg) > 500 {
		errMsg = errMsg[:500]
	}
	sql := `UPDATE public.upgrade SET state = 'failed', error = :'error_msg'
WHERE id = :'row_id' AND state = 'in_progress'`
	if _, err := runInstallSQL(dir, sql,
		"row_id", strconv.FormatInt(rowID, 10),
		"error_msg", errMsg); err != nil {
		fmt.Printf("  Note: could not mark upgrade row %d failed: %v\n", rowID, err)
		return
	}
	fmt.Printf("  Upgrade row %d: failed\n", rowID)
}

// runRootInstall handles `sudo sb install` — ONLY installs the systemd service.
// Does not touch any project files to avoid creating root-owned files.
func runRootInstall() error {
	fmt.Println("StatBus — Installing systemd service (running as root)")
	fmt.Println()

	if runtime.GOOS != "linux" {
		return fmt.Errorf("systemd service installation is only supported on Linux")
	}

	// Find the project directory from the binary location
	sbPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("find executable: %w", err)
	}
	dir := filepath.Dir(sbPath)

	instance := serviceInstance(dir)
	if instance == "" {
		return fmt.Errorf("could not determine service instance name (check DEPLOYMENT_SLOT_CODE in .env.config)")
	}

	serviceFile := filepath.Join(dir, "ops", "statbus-upgrade.service")
	destFile := "/etc/systemd/system/statbus-upgrade@.service"

	fmt.Printf("  Copying %s → %s\n", filepath.Base(serviceFile), destFile)
	if err := copyFile(serviceFile, destFile); err != nil {
		return fmt.Errorf("copy service file: %w", err)
	}

	fmt.Println("  Running systemctl daemon-reload")
	if err := runCmd("systemctl", "daemon-reload"); err != nil {
		return fmt.Errorf("systemctl daemon-reload: %w", err)
	}

	// No sudoers needed — backup/restore runs rsync inside a Docker container,
	// which can read/write the named volume without host-level sudo.

	fmt.Printf("  Enabling and starting %s\n", instance)
	if err := runCmd("systemctl", "enable", "--now", instance); err != nil {
		return fmt.Errorf("enable service: %w", err)
	}

	fmt.Println()
	fmt.Printf("  Upgrade service installed and started: %s\n", instance)
	fmt.Println("  Re-run without sudo to verify: ./sb install")
	return nil
}

// ── Helpers ──

func checkPrerequisites() error {
	if _, err := exec.LookPath("docker"); err != nil {
		return fmt.Errorf("Docker is required but not found. Install from https://docs.docker.com/engine/install/")
	}
	if err := runCmd("docker", "compose", "version"); err != nil {
		return fmt.Errorf("Docker Compose is required. Install the compose plugin: https://docs.docker.com/compose/install/")
	}
	if _, err := exec.LookPath("git"); err != nil {
		return fmt.Errorf("git is required but not found. Install with: sudo apt install git")
	}
	return nil
}

func prompt(label, defaultVal string) string {
	fmt.Printf("%s [%s]: ", label, defaultVal)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	line = strings.TrimSpace(line)
	if line == "" {
		return defaultVal
	}
	return line
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func runCmdDir(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0755)
}

// migrateConfigPaths rewrites devops/ → ops/ paths in .env.config.
// Idempotent — only changes values that still use the old prefix.
func migrateConfigPaths(dir string) {
	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return
	}
	changed := false
	for _, key := range f.Keys() {
		val, _ := f.Get(key)
		if strings.Contains(val, "./devops/") {
			f.Set(key, strings.ReplaceAll(val, "./devops/", "./ops/"))
			changed = true
		}
	}
	if changed {
		if err := f.Save(); err != nil {
			fmt.Printf("  Warning: could not migrate .env.config paths: %v\n", err)
		} else {
			fmt.Println("  Migrated .env.config: devops/ → ops/")
		}
	}
}

// logInstallState prints the state classification produced by install.Detect.
// Dispatch policy lives in runInstall; this function is print-only.
func logInstallState(state install.State, detail *install.Detail) {
	fmt.Printf("Detected install state: %s (current=%s, target=%s)\n",
		state, detail.CurrentVersion, detail.TargetVersion)
	switch state {
	case install.StateFresh:
		fmt.Printf("  Fresh install; target version = %s (binary).\n", detail.TargetVersion)
	case install.StateLiveUpgrade:
		if detail.Flag != nil {
			fmt.Printf("  Upgrade in progress (PID %d, %s). Install will refuse.\n",
				detail.Flag.PID, detail.Flag.DisplayName)
		}
	case install.StateCrashedUpgrade:
		if detail.Flag != nil {
			fmt.Printf("  Prior upgrade crashed (PID %d, %s). The stale lock was released when the PID died; recovering.\n",
				detail.Flag.PID, detail.Flag.DisplayName)
		}
	case install.StateHalfConfigured:
		fmt.Println("  .env.credentials missing; step-table will generate it.")
	case install.StateDBUnreachable:
		fmt.Println("  Database not reachable; step-table will start services.")
	case install.StateLegacyNoUpgradeTable:
		fmt.Println("  Pre-1.0 install detected (public.upgrade absent). Install will refuse; automatic upgrade from pre-1.0 tracked as #65.6.")
	case install.StateScheduledUpgrade:
		fmt.Printf("  Upgrade scheduled (id=%d, version=%s). Dispatching inline upgrade.\n",
			detail.ScheduledRowID, detail.TargetVersion)
	case install.StateNothingScheduled:
		fmt.Println("  Existing install, no upgrade scheduled; running idempotent step-table to refresh.")
	}
	fmt.Println()
}
