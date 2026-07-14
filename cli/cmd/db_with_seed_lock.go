package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// `./sb db with-seed-lock --exclusive|--shared -- <cmd...>`
//
// Holds a PostgreSQL advisory lock keyed by hashtext('statbus_seed_mutate')
// on a connection to the `postgres` system database while the wrapped
// command runs. The lock survives DROP DATABASE statbus_seed because the
// holding connection isn't to statbus_seed itself.
//
// Used by `./dev.sh recreate-seed` to serialise mutations of the seed
// against concurrent readers (`./sb types generate`,
// `./dev.sh generate-doc-db` via assert_db_at_head, which
// internally acquires the SHARED variant of the same lock).
//
// Lock is released automatically when the holding connection closes
// (PG advisory locks are session-scoped — no stale-lock cleanup needed).
// Even SIGKILL of this process releases cleanly via fd teardown.

var (
	withSeedLockExclusive bool
	withSeedLockShared    bool
)

var withSeedLockCmd = &cobra.Command{
	Use:   "with-seed-lock --exclusive|--shared -- <cmd> [args...]",
	Short: "Run a command while holding the statbus_seed mutation lock",
	Long: `Run <cmd> [args...] while holding the PG advisory lock that
serialises mutations of the canonical seed (statbus_seed) against
concurrent readers.

Specify exactly one of:
  --exclusive   Blocks ALL other holders (used by recreate-seed during
                DROP/CREATE/migrate.Up). Held until <cmd> exits.
  --shared      Allows other shared holders; blocks only against
                exclusive holders. Used internally by assert-db-at-head
                — the typical operator-facing path is --exclusive.

The lock survives DROP DATABASE statbus_seed because it's held on a
connection to the postgres system database. SIGKILL of this process
releases the lock cleanly via fd teardown.

Examples:
  ./sb db with-seed-lock --exclusive -- ./dev.sh recreate-seed
  ./sb db with-seed-lock --exclusive -- bash -c 'drop_and_rebuild_seed'`,
	Args: cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if !withSeedLockExclusive && !withSeedLockShared {
			return fmt.Errorf("specify --exclusive or --shared")
		}
		if withSeedLockExclusive && withSeedLockShared {
			return fmt.Errorf("--exclusive and --shared are mutually exclusive")
		}

		// Exclusive holders (recreate-seed) block indefinitely on
		// purpose — the mutation needs to wait until all readers have
		// finished. Shared holders never set a timeout from this
		// subcommand (callers who want a timeout — assert-db-at-head —
		// invoke AcquireSeedLock from Go directly).
		ctx := context.Background()
		conn, err := migrate.AcquireSeedLock(ctx, config.ProjectDir(), withSeedLockExclusive, 0 /* no timeout */, "./sb db with-seed-lock")
		if err != nil {
			return err
		}
		defer func() { _ = conn.Close(ctx) }()

		mode := "shared"
		if withSeedLockExclusive {
			mode = "exclusive"
		}
		fmt.Fprintf(os.Stderr, "Acquired %s seed lock; running: %v\n", mode, args)

		// Run the wrapped command. Stdin/stdout/stderr passthrough so
		// the operator sees normal interactive output, errors, etc.
		wrapped := exec.Command(args[0], args[1:]...)
		wrapped.Stdin = os.Stdin
		wrapped.Stdout = os.Stdout
		wrapped.Stderr = os.Stderr
		err = wrapped.Run()

		// Exit-code passthrough. The lock is released by the defer
		// above regardless of how we exit.
		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				// Match the wrapped command's exit code so callers can
				// propagate failure cleanly.
				os.Exit(exitErr.ExitCode())
			}
			return fmt.Errorf("wrapped command failed: %w", err)
		}
		return nil
	},
}

func init() {
	withSeedLockCmd.Flags().BoolVar(&withSeedLockExclusive, "exclusive", false, "Acquire exclusive lock (blocks all other holders)")
	withSeedLockCmd.Flags().BoolVar(&withSeedLockShared, "shared", false, "Acquire shared lock (allows other shared holders, blocks exclusive)")
	dbCmd.AddCommand(withSeedLockCmd)
}
