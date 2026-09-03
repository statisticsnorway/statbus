package cmd

import (
	"errors"
	"testing"

	"github.com/spf13/cobra"
)

func TestCobraExitCode_ArgumentRefusalIsUsage(t *testing.T) {
	command := &cobra.Command{
		Use:           "probe <required>",
		Args:          cobra.ExactArgs(1),
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE: func(_ *cobra.Command, _ []string) error {
			t.Fatal("RunE must not run after an argument refusal")
			return nil
		},
	}
	prepareCobraExitContract(command)
	command.SetArgs(nil)

	err := command.Execute()
	if err == nil {
		t.Fatal("wrong argument count must return an error")
	}
	if got := ExitCode(err); got != exitUsage {
		t.Fatalf("ExitCode(argument refusal) = %d, want %d (EX_USAGE)", got, exitUsage)
	}
}

func TestCobraExitCode_FlagRefusalIsUsage(t *testing.T) {
	command := &cobra.Command{
		Use:           "probe",
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE:          func(_ *cobra.Command, _ []string) error { return nil },
	}
	prepareCobraExitContract(command)
	command.SetArgs([]string{"--no-such-flag"})

	err := command.Execute()
	if err == nil {
		t.Fatal("unknown flag must return an error")
	}
	if got := ExitCode(err); got != exitUsage {
		t.Fatalf("ExitCode(flag refusal) = %d, want %d (EX_USAGE)", got, exitUsage)
	}
}

func TestCobraExitCode_MissingRequiredFlagIsUsage(t *testing.T) {
	command := &cobra.Command{
		Use:           "probe",
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE: func(_ *cobra.Command, _ []string) error {
			t.Fatal("RunE must not run after a required-flag refusal")
			return nil
		},
	}
	command.Flags().String("required", "", "required value")
	if err := command.MarkFlagRequired("required"); err != nil {
		t.Fatal(err)
	}
	prepareCobraExitContract(command)
	command.SetArgs(nil)

	err := command.Execute()
	if err == nil {
		t.Fatal("missing required flag must return an error")
	}
	if got := ExitCode(err); got != exitUsage {
		t.Fatalf("ExitCode(required-flag refusal) = %d, want %d (EX_USAGE)", got, exitUsage)
	}
}

func TestCobraExitCode_RunEFailureIsNotUsage(t *testing.T) {
	command := &cobra.Command{
		Use:           "probe",
		SilenceErrors: true,
		SilenceUsage:  false,
		RunE: func(_ *cobra.Command, _ []string) error {
			return errors.New("operational failure")
		},
	}
	prepareCobraExitContract(command)
	command.SetArgs(nil)

	err := command.Execute()
	if err == nil {
		t.Fatal("RunE failure must return an error")
	}
	if got := ExitCode(err); got == exitUsage {
		t.Fatalf("ExitCode(RunE failure) = %d, must not masquerade as EX_USAGE", got)
	}
	if !command.SilenceUsage {
		t.Fatal("RunE failure must suppress Cobra usage text")
	}
}

func TestReleaseCoveredIsGuardedAgainstStaleBinaries(t *testing.T) {
	if readOnlyCommandPaths["sb release covered"] {
		t.Fatal("release covered must pass through the staleness guard; stale coverage logic can skip required scenarios")
	}
}
