package main

import (
	"os"

	"github.com/statisticsnorway/statbus/cli/cmd"
	releasecmd "github.com/statisticsnorway/statbus/cli/cmd/release"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

func main() {
	// Explicit composition (STATBUS-352). The release command family is a
	// separate package so ordinary box commands cannot import release-engine
	// code; it is mounted here, at the process entrypoint, not by init().
	// Migration code's four release questions are answered by callbacks
	// handed in here for the same reason.
	migrate.ReleaseProbe = releasecmd.MigrateProbes()
	cmd.Mount(releasecmd.Command())
	if err := cmd.Execute(); err != nil {
		os.Exit(cmd.ExitCode(err))
	}
}
