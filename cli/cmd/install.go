package cmd

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

var nonInteractive bool
var installVersion string

// insideActiveUpgrade signals that this install invocation is a post-upgrade
// fixup spawned by the upgrade service itself. It is NOT a user-facing flag —
// operators must never pass it. The service at service.go:executeUpgrade sets
// both this CLI flag and STATBUS_INSIDE_ACTIVE_UPGRADE=1 env var on its child
// exec; either triggers the mutex bypass in runInstall.
var insideActiveUpgrade bool

// ExitCodeNeedsRoot is returned when the upgrade service step needs root.
// cloud.sh recognizes this code and SSHes as root to complete the install.
const ExitCodeNeedsRoot = 42

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install or resume StatBus installation",
	Long: `Idempotent installation of StatBus. Each run checks what's already
done and performs the next pending step. Safe to re-run — completed
steps are skipped automatically.

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
	installCmd.Flags().StringVar(&installVersion, "version", "", "version tag to checkout (for rescue installs)")
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

// checkUpgradeMutex enforces the install ↔ upgrade-service mutual exclusion.
//
// The upgrade service writes tmp/upgrade-in-progress.json before destructive
// steps of executeUpgrade (service.go:writeUpgradeFlag). The flag survives
// service crashes; it is removed on normal completion, rollback, or by
// recoverFromFlag on the next service restart.
//
// When `bypass` is true, the caller is the upgrade service's own post-upgrade
// fixup — skip the check. Otherwise:
//   - No flag → Idle state; proceed.
//   - Flag + owning PID still alive → an upgrade is genuinely running. Abort
//     and tell the operator to wait.
//   - Flag + owning PID dead → the prior upgrade crashed (or the service was
//     stopped mid-upgrade). Abort and tell the operator to start the service,
//     which triggers recoverFromFlag and cleans the flag.
//
// Install never writes the flag; it only reads. Legacy flag files (pre-Release 1,
// missing the PID field) deserialize with PID=0, which upgrade.ReadFlagFile
// reports as "not alive" — so legacy flags produce the crash-recovery message,
// which is the correct recovery path (service restart will recoverFromFlag them).
func checkUpgradeMutex(installDir string, bypass bool) error {
	flag, alive, err := upgrade.ReadFlagFile(installDir)
	if err != nil {
		// Corrupt/unreadable flag file — fail loud. Operator must investigate.
		return fmt.Errorf("upgrade flag file present but unreadable: %w\n\n  Investigate %s manually, then retry.",
			err, filepath.Join(installDir, "tmp", "upgrade-in-progress.json"))
	}
	if flag == nil {
		if bypass {
			fmt.Printf("Note: --inside-active-upgrade set but no upgrade flag found. Proceeding.\n")
		}
		return nil
	}

	if bypass {
		fmt.Printf("Upgrade mutex bypass honored (--inside-active-upgrade). Flag owned by PID %d, invoked_by=%s.\n",
			flag.PID, flag.InvokedBy)
		return nil
	}

	if alive {
		return fmt.Errorf(
			"an orchestrated upgrade is in progress: PID %d (%s, invoked_by=%s).\n\n"+
				"  Wait for it to complete:\n"+
				"    journalctl --user -u 'statbus-upgrade@*' -f\n\n"+
				"  Do NOT pass --inside-active-upgrade — that flag is the upgrade service's\n"+
				"  internal contract with its own post-upgrade install step. Using it from the\n"+
				"  command line would corrupt an upgrade that is currently running.",
			flag.PID, flag.DisplayName, flag.InvokedBy)
	}

	return fmt.Errorf(
		"a prior upgrade crashed or was stopped mid-run: flag file references PID %d (%s, invoked_by=%s)\n"+
			"but that process is no longer alive.\n\n"+
			"  Trigger the recovery path by starting the upgrade service:\n"+
			"    systemctl --user start 'statbus-upgrade@*'\n\n"+
			"  The service's startup handler will clean up the stale flag (marking the\n"+
			"  upgrade as failed or completed based on git HEAD), after which ./sb install\n"+
			"  can run normally.",
		flag.PID, flag.DisplayName, flag.InvokedBy)
}

// runInstall is the entry point for `./sb install`. It is safe to run while
// an upgrade service is active on the same host because of the mutex check
// below: if the upgrade service has written tmp/upgrade-in-progress.json
// (which it does before any destructive step in executeUpgrade), this function
// refuses to proceed. The only exception is the service's own post-upgrade
// fixup, which passes --inside-active-upgrade / STATBUS_INSIDE_ACTIVE_UPGRADE=1
// to signal "I am the active upgrade, not a conflicting actor."
func runInstall() error {
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

	// === Upgrade mutex check ===
	// If the upgrade service has written tmp/upgrade-in-progress.json, an
	// orchestrated upgrade is either in flight or crashed pending recovery.
	// Either way, install must not race it. The ONLY caller allowed to bypass
	// is the upgrade service itself (service.go:executeUpgrade spawns install
	// as a post-upgrade fixup with --inside-active-upgrade + env var set).
	bypass := insideActiveUpgrade || os.Getenv("STATBUS_INSIDE_ACTIVE_UPGRADE") == "1"
	if err := checkUpgradeMutex(installDir, bypass); err != nil {
		return err
	}

	// Pre-flight: check disk space
	if freeBytes, err := upgrade.DiskFree("."); err == nil {
		freeGB := freeBytes / (1024 * 1024 * 1024)
		if freeGB < 100 {
			return fmt.Errorf("insufficient disk space: %d GB free (need at least 100 GB for database, images, and backups)", freeGB)
		}
		fmt.Printf("Disk space: %d GB free\n", freeGB)
	}

	steps := []step{
		{"Source code", checkSourceCodeDone, runCheckoutVersion},
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

func checkSourceCodeDone(dir string) bool {
	if installVersion == "" {
		return true // No --version flag, skip (fresh install uses git clone)
	}
	// Check if HEAD already matches the requested version tag
	cmd := exec.Command("git", "describe", "--tags", "--exact-match", "HEAD")
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(out)) == installVersion
}

func runCheckoutVersion(dir string) error {
	fmt.Printf("  Checking out %s\n", installVersion)
	if err := runCmdDir(dir, "git", "fetch", "--depth", "1", "origin", "tag", installVersion, "--quiet"); err != nil {
		return fmt.Errorf("fetch tag %s: %w", installVersion, err)
	}
	return runCmdDir(dir, "git", "-c", "advice.detachedHead=false", "checkout", installVersion)
}

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

	// Remove stale devops/deploy-to-* refspecs that break git fetch
	oldBranch := fmt.Sprintf("devops/deploy-to-%s", code)
	oldRefspec := fmt.Sprintf("+refs/heads/%s:refs/remotes/origin/%s", oldBranch, oldBranch)
	cmd := exec.Command("git", "config", "--get-all", "remote.origin.fetch")
	cmd.Dir = dir
	out, _ := cmd.Output()
	if strings.Contains(string(out), oldRefspec) {
		rm := exec.Command("git", "config", "--unset", "remote.origin.fetch", fmt.Sprintf("refs/heads/%s", oldBranch))
		rm.Dir = dir
		rm.Run()
	}
	// Also remove the broad devops/* refspec if present
	if strings.Contains(string(out), "refs/heads/devops/*") {
		rm := exec.Command("git", "config", "--unset", "remote.origin.fetch", "refs/heads/devops/\\*")
		rm.Dir = dir
		rm.Run()
	}

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
		fmt.Println("  Skipping signer trust (non-interactive mode)")
		fmt.Println("  Add trusted signers later with: ./sb upgrade trust-key add <github-username>")
		return nil
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

