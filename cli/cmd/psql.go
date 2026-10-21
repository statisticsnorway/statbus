package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var psqlCmd = &cobra.Command{
	Use:     "psql [flags for psql]",
	Short:   "Open a psql shell connected to the StatBus database",
	GroupID: operationsGroupID,
	Long: "Opens psql with the correct connection settings from .env.\nAll arguments are passed through to psql.\n\n" +
		"STATBUS_PSQL=recovery ./sb psql opens a session that can write while an\n" +
		"upgrade holds the database read-only, for fixing the cause of a parked\n" +
		"upgrade. Other sessions stay read-only. Then resume the upgrade with the\n" +
		"install command the park message names.",
	DisableFlagParsing: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := migrate.PsqlProjectDir()
		psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
		if err != nil {
			return err
		}

		sessionArgs, env, err := psqlSessionArgs(os.Getenv("STATBUS_PSQL"), psqlPath, prefix, args, env)
		if err != nil {
			return err
		}
		fullArgs := append([]string{psqlPath}, sessionArgs...)

		resolvedPath, err := exec.LookPath(psqlPath)
		if err != nil {
			return err
		}

		if isTerminal() && env != nil {
			// Host psql + terminal: exec into psql (replace this process)
			// authority:pinned-reexec
			return syscall.Exec(resolvedPath, fullArgs, env)
		}

		// Non-interactive or docker mode: run as child
		child, buildErr := migrate.Command(projDir, psqlPath, fullArgs[1:]...)
		if buildErr != nil {
			return buildErr
		}
		child.Env = env
		child.Stdin = os.Stdin
		child.Stdout = os.Stdout
		child.Stderr = os.Stderr
		return child.Run()
	},
}

// psqlSessionArgs returns the psql arguments and environment for one session.
// Every argument reaches psql unchanged. The session mode comes from STATBUS_PSQL,
// never from the arguments, so it cannot collide with a psql flag.
// STATBUS_PSQL=recovery opens the session for writing while an upgrade holds the
// database read-only (default_transaction_read_only on), so an operator can
// fix the cause of a parked upgrade before resuming it with ./sb install. Only
// this session is exempt; it names itself "sb psql recovery" in
// pg_stat_activity.
func psqlSessionArgs(mode, psqlPath string, prefix, args, env []string) ([]string, []string, error) {
	full := append(append(make([]string, 0, len(prefix)+len(args)), prefix...), args...)
	switch mode {
	case "":
		return full, env, nil
	case "recovery":
		full, env = migrate.PsqlWriteArgs(psqlPath, full, env, "sb psql recovery")
		return full, env, nil
	default:
		return nil, nil, fmt.Errorf("STATBUS_PSQL=%q is not a psql session mode; the one mode is STATBUS_PSQL=recovery", mode)
	}
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
