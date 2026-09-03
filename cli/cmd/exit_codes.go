package cmd

import (
	"errors"

	"github.com/spf13/cobra"
)

// Process exit codes whose meaning is part of an external caller contract.
// Keep them together: the release-covered verdicts must never collide with a
// pre-dispatch refusal that means the command did not run.
const (
	exitCovered        = 0
	exitMustRun        = 1
	exitUndecided      = 2
	exitUsage          = 64 // EX_USAGE, sysexits.h
	exitBinaryUnusable = 69 // EX_UNAVAILABLE, sysexits.h
)

// commandExecutionError distinguishes an error returned by a Cobra run hook
// from Cobra's own command-line refusals. Cobra does not expose a typed usage
// error: unknown commands/flags, Args validation, and required-flag validation
// all return ordinary errors. They do, however, happen before RunE. Wrapping
// the run hooks preserves that structural boundary without matching prose.
type commandExecutionError struct {
	err error
}

func (e *commandExecutionError) Error() string { return e.err.Error() }
func (e *commandExecutionError) Unwrap() error { return e.err }

func wrapCommandExecutionHook(hook func(*cobra.Command, []string) error) func(*cobra.Command, []string) error {
	if hook == nil {
		return nil
	}
	return func(command *cobra.Command, args []string) error {
		err := hook(command, args)
		if err == nil {
			return nil
		}
		// Usage text is actionable for a command-line refusal, but noise after
		// an operational failure in a command that already started.
		command.SilenceUsage = true
		var executionErr *commandExecutionError
		if errors.As(err, &executionErr) {
			return err
		}
		return &commandExecutionError{err: err}
	}
}

// prepareCobraExitContract wraps every error-returning execution hook. Cobra's
// parse/Args/required-flag errors remain unwrapped and therefore map to
// EX_USAGE; errors from command execution retain the CLI's ordinary exit 1.
func prepareCobraExitContract(command *cobra.Command) {
	command.PersistentPreRunE = wrapCommandExecutionHook(command.PersistentPreRunE)
	command.PreRunE = wrapCommandExecutionHook(command.PreRunE)
	command.RunE = wrapCommandExecutionHook(command.RunE)
	command.PostRunE = wrapCommandExecutionHook(command.PostRunE)
	command.PersistentPostRunE = wrapCommandExecutionHook(command.PersistentPostRunE)
	for _, child := range command.Commands() {
		prepareCobraExitContract(child)
	}
}

// ExitCode maps the error returned by Execute to the process boundary. Exit 1
// remains the established generic operational failure outside subcommands
// that own a more specific os.Exit contract. An unwrapped Cobra error is a
// command-line refusal and therefore EX_USAGE (64).
func ExitCode(err error) int {
	var executionErr *commandExecutionError
	if errors.As(err, &executionErr) {
		return 1
	}
	return exitUsage
}
