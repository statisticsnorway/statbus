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
)

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install StatBus on this server",
	Long: `Interactive installation of StatBus. Steps:
  1. Check prerequisites (Docker, git)
  2. Clone repository (shallow)
  3. Interactive configuration
  4. Generate config files
  5. Pull Docker images
  6. Start services
  7. Run migrations
  8. Install upgrade daemon (systemd)`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runInstall()
	},
}

func init() {
	rootCmd.AddCommand(installCmd)
}

func runInstall() error {
	fmt.Println("StatBus Installation")
	fmt.Println("====================")
	fmt.Println()

	// Step 1: Check prerequisites
	fmt.Println("[1/8] Checking prerequisites...")
	if err := checkPrerequisites(); err != nil {
		return err
	}

	// Step 2: Determine install directory
	home, _ := os.UserHomeDir()
	installDir := filepath.Join(home, "statbus")

	if _, err := os.Stat(installDir); err == nil {
		fmt.Printf("Directory %s already exists.\n", installDir)
		fmt.Print("Continue with existing installation? [y/N] ")
		if !confirm() {
			return fmt.Errorf("installation cancelled")
		}
	} else {
		fmt.Printf("[2/8] Cloning repository to %s...\n", installDir)
		if err := runCmd("git", "clone", "--depth", "1",
			"https://github.com/statisticsnorway/statbus.git", installDir); err != nil {
			return fmt.Errorf("git clone: %w", err)
		}
	}

	// Step 3: Move binary into place
	sbDst := filepath.Join(installDir, "sb")
	sbSrc, _ := os.Executable()
	if sbSrc != sbDst {
		fmt.Printf("[3/8] Installing binary to %s...\n", sbDst)
		if err := copyFile(sbSrc, sbDst); err != nil {
			return fmt.Errorf("install binary: %w", err)
		}
		os.Chmod(sbDst, 0755)
	}

	// Step 4: Interactive configuration
	fmt.Println()
	fmt.Println("[4/8] Configuration")
	fmt.Println("-------------------")

	mode := prompt("Deployment mode (development/standalone/private)", "standalone")
	domain := prompt("Domain name", "statbus.example.com")
	name := prompt("Deployment name", "StatBus")
	code := prompt("Deployment code (short, lowercase)", "local")

	// Write .env.config
	cfgPath := filepath.Join(installDir, ".env.config")
	cfgContent := fmt.Sprintf(`DEPLOYMENT_SLOT_NAME=%s
DEPLOYMENT_SLOT_CODE=%s
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=%s
SITE_DOMAIN=%s
`, name, code, mode, domain)

	if err := os.WriteFile(cfgPath, []byte(cfgContent), 0644); err != nil {
		return fmt.Errorf("write .env.config: %w", err)
	}

	fmt.Printf("\nWrote %s. Edit it for further customization, then press Enter.\n", cfgPath)
	fmt.Print("Press Enter to continue...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')

	// Step 5: Generate config
	fmt.Println("[5/8] Generating configuration...")
	if err := runCmdDir(installDir, filepath.Join(installDir, "sb"), "config", "generate"); err != nil {
		return fmt.Errorf("config generate: %w", err)
	}

	// Step 6: Pull images
	fmt.Println("[6/8] Pulling Docker images...")
	if err := runCmdDir(installDir, "docker", "compose", "pull"); err != nil {
		return fmt.Errorf("docker compose pull: %w", err)
	}

	// Step 7: Start services and run migrations
	fmt.Println("[7/8] Starting services...")
	if err := runCmdDir(installDir, "docker", "compose", "--profile", "all", "up", "-d"); err != nil {
		return fmt.Errorf("start: %w", err)
	}

	fmt.Println("[8/8] Running migrations...")
	if err := runCmdDir(installDir, filepath.Join(installDir, "sb"), "migrate", "up", "--verbose"); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}

	// Optional: Install systemd service
	if runtime.GOOS == "linux" {
		fmt.Print("\nInstall upgrade daemon (systemd service)? [y/N] ")
		if confirm() {
			installSystemd(installDir)
		}
	}

	fmt.Println()
	fmt.Println("Installation complete!")
	fmt.Println("=====================")
	fmt.Printf("StatBus is running at: %s\n", domain)
	fmt.Printf("Management: cd %s && ./sb --help\n", installDir)
	if mode != "development" {
		fmt.Println("Edit .users.yml and run: ./sb users create")
	}

	return nil
}

func checkPrerequisites() error {
	// Check Docker
	if _, err := exec.LookPath("docker"); err != nil {
		return fmt.Errorf("Docker is required but not found. Install from https://docs.docker.com/engine/install/")
	}
	if err := runCmd("docker", "compose", "version"); err != nil {
		return fmt.Errorf("Docker Compose is required. Install the compose plugin: https://docs.docker.com/compose/install/")
	}

	// Check git
	if _, err := exec.LookPath("git"); err != nil {
		return fmt.Errorf("git is required but not found. Install with: sudo apt install git")
	}

	fmt.Println("  Docker: OK")
	fmt.Println("  Docker Compose: OK")
	fmt.Println("  Git: OK")
	return nil
}

func prompt(label, defaultVal string) string {
	fmt.Printf("  %s [%s]: ", label, defaultVal)
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

	fmt.Printf("Installing systemd service for user %s...\n", user)

	if err := runCmd("sudo", "cp", serviceFile, destFile); err != nil {
		fmt.Printf("Failed to copy service file: %v\n", err)
		return
	}

	if err := runCmd("sudo", "systemctl", "daemon-reload"); err != nil {
		fmt.Printf("Failed to reload systemd: %v\n", err)
		return
	}

	instance := fmt.Sprintf("statbus-upgrade@%s", user)
	if err := runCmd("sudo", "systemctl", "enable", instance); err != nil {
		fmt.Printf("Failed to enable service: %v\n", err)
		return
	}
	if err := runCmd("sudo", "systemctl", "start", instance); err != nil {
		fmt.Printf("Failed to start service: %v\n", err)
		return
	}

	fmt.Printf("Upgrade daemon installed and started as %s\n", instance)
}
