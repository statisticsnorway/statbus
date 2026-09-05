package cmd

import "github.com/spf13/cobra"

// Verbose reports the root --verbose flag. Read-only accessor for the
// release command package (cmd/release), which is composed onto the root
// command by main.go rather than by an init() in this package. This is the
// ONLY state cmd/release reads from cmd (STATBUS-352 Work C seam).
func Verbose() bool { return verbose }

// Mount attaches an externally constructed command tree to the root command.
// It exists so command composition happens explicitly at the process
// entrypoint (main.go) rather than via package-global init() side effects.
func Mount(c *cobra.Command) { rootCmd.AddCommand(c) }
