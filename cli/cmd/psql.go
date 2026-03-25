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
		psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
		if err != nil {
			return err
		}

		// Build full args: [argv0, prefix..., user_args...]
		fullArgs := append([]string{psqlPath}, prefix...)
		fullArgs = append(fullArgs, args...)

		resolvedPath, err := exec.LookPath(psqlPath)
		if err != nil {
			return err
		}

		if isTerminal() && env != nil {
			// Host psql + terminal: exec into psql (replace this process)
			return syscall.Exec(resolvedPath, fullArgs, env)
		}

		// Non-interactive or docker mode: run as child
		child := exec.Command(resolvedPath, fullArgs[1:]...)
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
