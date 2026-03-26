package cmd

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var nonInteractive bool

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
	rootCmd.AddCommand(installCmd)
}

// step represents one installation step with an idempotency check.
type step struct {
	name  string
	check func(dir string) bool // returns true if step is already done
	run   func(dir string) error
}

func runInstall() error {
	// Running as root? Only do the systemd step — nothing else.
	// This prevents root from creating files owned by root in the project dir.
	if os.Geteuid() == 0 {
		return runRootInstall()
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

	home, _ := os.UserHomeDir()
	installDir := filepath.Join(home, "statbus")

	steps := []step{
		{"Prerequisites", checkPrereqDone, runPrereq},
		{"Repository", checkRepoDone, runCloneRepo},
		{"Binary", checkBinaryDone, runInstallBinary},
		{"Configuration", checkConfigDone, runCreateConfig},
		{"Credentials", checkCredsDone, runCreateCreds},
		{"Generated env", checkEnvDone, runGenerateEnv},
		{"Images", checkImagesDone, runPullImages},
		{"Services", checkServicesDone, runStartServices},
		{"Migrations", checkMigrationsDone, runMigrations},
		{"JWT secret", checkJWTDone, runLoadJWT},
		{"Users", checkUsersDone, runCreateUsers},
		{"Upgrade daemon", checkDaemonDone, runInstallDaemon},
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
	_, err := os.Stat(filepath.Join(dir, ".env"))
	return err == nil
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
	// Check if there are pending migrations by comparing file count vs applied
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	args := append(prefix, "-t", "-A", "-c",
		"SELECT COALESCE(MAX(version), 0) FROM db.migration;")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	applied := strings.TrimSpace(string(out))
	// If we got a version number, migrations have been run at least once
	return applied != "0" && applied != ""
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

func checkDaemonDone(dir string) bool {
	if runtime.GOOS != "linux" {
		return true // Skip on non-Linux
	}
	instance := daemonInstance(dir)
	if instance == "" {
		return false
	}
	cmd := exec.Command("systemctl", "is-enabled", instance)
	return cmd.Run() == nil
}

// daemonInstance returns the systemd instance name, e.g. "statbus-upgrade@statbus_dev.service"
func daemonInstance(dir string) string {
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
// e.g., for slot "dev": +refs/heads/devops/deploy-to-dev:refs/remotes/origin/devops/deploy-to-dev
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

	branch := fmt.Sprintf("devops/deploy-to-%s", code)
	refspec := fmt.Sprintf("+refs/heads/%s:refs/remotes/origin/%s", branch, branch)

	// Check if already configured
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
	sb := filepath.Join(dir, "sb")
	if err := runCmdDir(dir, sb, "config", "generate"); err != nil {
		return err
	}
	// Now that config exists, ensure deploy branch fetch is configured
	configureDeployFetch(dir)
	// Create backup directory for upgrade daemon (systemd service expects it)
	home, _ := os.UserHomeDir()
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

func runInstallDaemon(dir string) error {
	if runtime.GOOS != "linux" {
		fmt.Println("  Skipping systemd on non-Linux")
		return nil
	}

	instance := daemonInstance(dir)
	if instance == "" {
		return fmt.Errorf("could not determine daemon instance name (check DEPLOYMENT_SLOT_CODE in .env.config)")
	}

	fmt.Println()
	fmt.Println("  The upgrade daemon requires sudo to install the systemd service.")
	fmt.Println("  Re-run as root to install it:")
	fmt.Println()
	fmt.Printf("    sudo %s/sb install\n", dir)
	fmt.Println()
	fmt.Println("  This will ONLY install the systemd service — no other files will be touched.")
	return fmt.Errorf("sudo required for systemd service installation")
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

	instance := daemonInstance(dir)
	if instance == "" {
		return fmt.Errorf("could not determine daemon instance name (check DEPLOYMENT_SLOT_CODE in .env.config)")
	}

	serviceFile := filepath.Join(dir, "devops", "statbus-upgrade.service")
	destFile := "/etc/systemd/system/statbus-upgrade@.service"

	fmt.Printf("  Copying %s → %s\n", filepath.Base(serviceFile), destFile)
	if err := copyFile(serviceFile, destFile); err != nil {
		return fmt.Errorf("copy service file: %w", err)
	}

	fmt.Println("  Running systemctl daemon-reload")
	if err := runCmd("systemctl", "daemon-reload"); err != nil {
		return fmt.Errorf("daemon-reload: %w", err)
	}

	// Configure sudoers for rsync backup/restore (path-locked)
	f, err := dotenv.Load(filepath.Join(dir, ".env.config"))
	if err != nil {
		return fmt.Errorf("load .env.config for sudoers: %w", err)
	}
	code, _ := f.Get("DEPLOYMENT_SLOT_CODE")
	user := "statbus_" + code
	homeDir := filepath.Join("/home", user)
	dataDir := homeDir + "/statbus/postgres/volumes/db/data/"
	backupDir := homeDir + "/statbus-backups/pre-upgrade/"
	rsyncPath := "/usr/bin/rsync"

	tarPath := "/usr/bin/tar"
	backupsBase := homeDir + "/statbus-backups"

	sudoersContent := fmt.Sprintf("# StatBus upgrade daemon — rsync for database backup/restore\n"+
		"%s ALL=(root) NOPASSWD: %s -a --delete %s %s\n"+
		"%s ALL=(root) NOPASSWD: %s -a --delete %s %s\n"+
		"# tar for archiving backups (root-owned rsync files)\n"+
		"%s ALL=(root) NOPASSWD: %s -czf %s/*-pre.tar.gz -C %s pre-upgrade\n",
		user, rsyncPath, dataDir, backupDir,
		user, rsyncPath, backupDir, dataDir,
		user, tarPath, backupsBase, backupsBase,
	)
	sudoersFile := fmt.Sprintf("/etc/sudoers.d/statbus-upgrade-%s", user)

	fmt.Printf("  Writing sudoers for rsync: %s\n", sudoersFile)
	if err := os.WriteFile(sudoersFile, []byte(sudoersContent), 0440); err != nil {
		return fmt.Errorf("write sudoers: %w", err)
	}
	// Validate sudoers syntax
	if err := runCmd("visudo", "-cf", sudoersFile); err != nil {
		os.Remove(sudoersFile) // Remove invalid file
		return fmt.Errorf("sudoers validation failed (removed %s): %w", sudoersFile, err)
	}

	fmt.Printf("  Enabling and starting %s\n", instance)
	if err := runCmd("systemctl", "enable", "--now", instance); err != nil {
		return fmt.Errorf("enable service: %w", err)
	}

	fmt.Println()
	fmt.Printf("  Upgrade daemon installed and started: %s\n", instance)
	fmt.Printf("  Sudoers configured: %s can rsync database backups\n", user)
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

