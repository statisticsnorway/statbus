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

func checkDaemonDone(_ string) bool {
	if runtime.GOOS != "linux" {
		return true // Skip on non-Linux
	}
	cmd := exec.Command("systemctl", "is-enabled", "statbus-upgrade@*")
	return cmd.Run() == nil
}

// ── Step runners ──

func runPrereq(_ string) error {
	return checkPrerequisites()
}

func runCloneRepo(dir string) error {
	return runCmd("git", "clone", "--depth", "1",
		"https://github.com/statisticsnorway/statbus.git", dir)
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
	return runCmdDir(dir, sb, "config", "generate")
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

	if nonInteractive {
		installSystemd(dir)
		return nil
	}

	fmt.Print("  Install upgrade daemon (systemd service)? [y/N] ")
	if confirm() {
		installSystemd(dir)
	} else {
		fmt.Println("  Skipped (run later with: sudo systemctl enable --now statbus-upgrade@<code>)")
	}
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

func confirm() bool {
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	line = strings.TrimSpace(strings.ToLower(line))
	return line == "y" || line == "yes"
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

func installSystemd(installDir string) {
	user := os.Getenv("USER")
	serviceFile := filepath.Join(installDir, "devops", "statbus-upgrade.service")
	destFile := "/etc/systemd/system/statbus-upgrade@.service"

	fmt.Printf("  Installing systemd service for user %s...\n", user)

	if err := runCmd("sudo", "cp", serviceFile, destFile); err != nil {
		fmt.Printf("  Failed to copy service file: %v\n", err)
		return
	}
	if err := runCmd("sudo", "systemctl", "daemon-reload"); err != nil {
		fmt.Printf("  Failed to reload systemd: %v\n", err)
		return
	}

	instance := fmt.Sprintf("statbus-upgrade@%s", user)
	if err := runCmd("sudo", "systemctl", "enable", "--now", instance); err != nil {
		fmt.Printf("  Failed to enable service: %v\n", err)
		return
	}

	fmt.Printf("  Upgrade daemon installed and started as %s\n", instance)
}
