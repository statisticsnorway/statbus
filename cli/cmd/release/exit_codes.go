package releasecmd

// Verdict exit codes of `sb release covered` / `covered-subset`. Part of the
// CI caller contract (release-fleet-orchestrator.yaml branches on them).
// Exported so the exit-contract test can prove they never collide with the
// pre-dispatch refusals cmd owns (64 EX_USAGE, 69 EX_UNAVAILABLE).
const (
	ExitCovered   = 0
	ExitMustRun   = 1
	ExitUndecided = 2
)

const (
	exitCovered   = ExitCovered
	exitMustRun   = ExitMustRun
	exitUndecided = ExitUndecided
)
