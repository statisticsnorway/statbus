package cmd

import (
	"fmt"
	"os"

	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
)

// announceUnitFloor prints a loud warning when this box cannot follow its
// upgrade channel, and says nothing at all when it can (STATBUS-308).
//
// WHY THE OPERATOR VERBS AND NOT ONLY THE SERVICE. The headline case is a
// MISSING unit — and a service that does not exist cannot report its own
// absence. Announcing only from inside the service would therefore cover every
// case except the one that cost demo nine days. These verbs are what a human
// runs when the upgrade page looks stale, so they are exactly where the answer
// needs to appear.
//
// To STDERR on purpose: `./sb upgrade list` output is piped and parsed, and a
// warning that corrupts a pipeline is a warning people route around. stderr
// keeps it un-ignorable to a human and invisible to a parser.
//
// Detection only — this prints. It never writes a unit, starts a service, or
// otherwise repairs; the repair stays `./sb install`, run by a person.
func announceUnitFloor() {
	if msg := unitfloor.Inspect(config.ProjectDir()).Announce(); msg != "" {
		fmt.Fprintln(os.Stderr, msg)
	}
}
