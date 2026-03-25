package cmd

import (
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
)

var testCmd = &cobra.Command{
	Use:                "test [args...]",
	Short:              "Run pg_regress tests",
	Long:               "Runs pg_regress tests via dev.sh.\nAll arguments are passed through (e.g., 'all', 'fast', or specific test names).",
	DisableFlagParsing: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		script := filepath.Join(projDir, "dev.sh")

		fullArgs := append([]string{script, "test"}, args...)
		c := exec.Command("bash", fullArgs...)
		c.Dir = projDir
		c.Stdin = os.Stdin
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		return c.Run()
	},
}

func init() {
	rootCmd.AddCommand(testCmd)
}
