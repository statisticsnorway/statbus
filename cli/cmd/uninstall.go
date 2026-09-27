package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
)

// uninstall delegates to the same standalone script published for curl | bash.
var uninstallCmd = &cobra.Command{
	Use:   "uninstall",
	Short: "Remove this StatBus installation (confirmation required)",
	RunE: func(cmd *cobra.Command, args []string) error {
		path := filepath.Join(os.Getenv("HOME"), "statbus", "uninstall.sh")
		if _, err := os.Stat(path); err != nil {
			return fmt.Errorf("uninstaller is missing at %s; run curl -fsSL https://statbus.org/uninstall.sh | bash: %w", path, err)
		}
		process := exec.Command("bash", path)
		process.Stdin = cmd.InOrStdin()
		process.Stdout = cmd.OutOrStdout()
		process.Stderr = cmd.ErrOrStderr()
		return process.Run()
	},
}

func init() { rootCmd.AddCommand(uninstallCmd) }
