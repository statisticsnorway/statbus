// Package releasecmd owns the `sb release ...` command family: the release
// engine's operator surface (prerelease, stable, list, check, covered,
// covered-subset, verify-tag, verify-images).
//
// It is composed onto the root command explicitly by main.go through
// cmd.Mount; this package has NO init() and registers nothing as a side
// effect of import. The dependency direction is enforced by
// architecture_test.go:
//
//	main -> cmd
//	main -> cmd/release
//	cmd/release -> cmd (two read-only accessors) and internal/*
//	cmd -X-> cmd/release
//	cmd -X-> internal/release (directly or transitively)
//
// That last edge is the policy closure STATBUS-352 makes compiler-checkable:
// ordinary box commands cannot depend on release-engine code.
package releasecmd

import (
	"github.com/spf13/cobra"

	"github.com/statisticsnorway/statbus/cli/cmd"
)

// verboseFlag reads the root --verbose flag. A variable so tests can set it
// without reaching into cmd's private state.
var verboseFlag = cmd.Verbose

// Command builds the fully wired `release` command tree. Flags and
// sub-commands are attached here, once, in the order the former init()
// functions ran (covered, verify, then the top-level release family).
func Command() *cobra.Command {
	releaseCoveredCmd.Flags().StringVar(&releaseCoveredWorkflow, "workflow", "", "workflow home for an ambiguous scenario name")
	releaseCmd.AddCommand(releaseCoveredCmd)
	releaseCoveredSubsetCmd.Flags().StringVar(&coveredSubsetDetailsFile, "details-file", "", "write per-scenario markdown details for a workflow step summary")
	releaseCmd.AddCommand(releaseCoveredSubsetCmd)

	releaseCmd.AddCommand(releaseVerifyTagCmd)
	releaseCmd.AddCommand(releaseVerifyImagesCmd)

	releaseCheckCmd.Flags().StringVar(&releaseCheckTag, "tag", "", "specific tag to check (mutually exclusive with --channel)")
	releaseCheckCmd.Flags().StringVar(&releaseCheckChannel, "channel", "", "channel to check: stable | prerelease | edge (mutually exclusive with --tag)")
	releaseCmd.AddCommand(releasePrereleaseCmd)
	releaseCmd.AddCommand(releaseStableCmd)
	releaseCmd.AddCommand(releaseListCmd)
	releaseCmd.AddCommand(releaseCheckCmd)
	return releaseCmd
}
