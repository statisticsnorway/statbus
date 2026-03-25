package cmd

import (
	"os"
	"os/exec"
	"syscall"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var psqlCmd = &cobra.Command{
	Use:                "psql [flags for psql]",
	Short:              "Open a psql shell connected to the StatBus database",
	Long:               "Opens psql with the correct connection settings from .env.\nAll arguments are passed through to psql.",
	DisableFlagParsing: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := migrate.PsqlProjectDir()
		psqlArgs, env, err := migrate.PsqlArgs(projDir)
		if err != nil {
			return err
		}

		// Append user's extra args
		fullArgs := append(psqlArgs, args...)

		// If stdin is a terminal, exec into psql (replace this process)
		// Otherwise, run as a child process (for piped input)
		psqlPath, err := exec.LookPath("psql")
		if err != nil {
			return err
		}

		if isTerminal() {
			// Replace current process with psql
			return syscall.Exec(psqlPath, fullArgs, env)
		}

		// Non-interactive: run as child
		child := exec.Command(psqlPath, fullArgs[1:]...)
		child.Env = env
		child.Stdin = os.Stdin
		child.Stdout = os.Stdout
		child.Stderr = os.Stderr
		child.Dir = projDir
		return child.Run()
	},
}

func isTerminal() bool {
	fi, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	return fi.Mode()&os.ModeCharDevice != 0
}

func init() {
	rootCmd.AddCommand(psqlCmd)
}
