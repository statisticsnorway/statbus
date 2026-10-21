package upgrade

import (
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/installcmd"
)

// InstallCommand is the operator's one recovery tool for the checkout at
// projDir: `cd <projDir> && ./sb install`. Every upgrade, recovery, un-park,
// restore and rollback hint names it, in the daemon journal, the progress
// log, the durable row error, Slack and refusals alike.
//
// It keeps the box's own ./sb, its target tree and its UPGRADE_CHANNEL, which
// the recovery doctrine depends on ("./sb install is the deliberate human
// retry"; "Do not replace ./sb, check out another commit"). It is never the
// public curl installer: that replaces ./sb and checks out the channel's
// latest release. The absolute path makes it work from any directory.
func InstallCommand(projDir string) string { return installcmd.Local(projDir) }

func (d *Service) installCommand() string { return InstallCommand(d.projDir) }

// ParkedResumeGuidance is what the operator reads when an upgrade parks: how
// to fix the cause and resume. A park keeps the database read-only for every
// session that has not opted out, so a database fix starts by opting the
// operator's own session out; `./sb install` then clears the park and runs
// one fresh attempt, and it is the only thing that clears a park. A newer
// release replaces the parked one without either step.
func ParkedResumeGuidance(projDir string) []string {
	psql := strings.TrimSuffix(InstallCommand(projDir), " install") + " psql"
	return []string{
		"To fix it in the database: run " + psql + ", then SET default_transaction_read_only = off; in that session before writing.",
		"Then resume with one fresh attempt: " + InstallCommand(projDir),
		"A newer release replaces this upgrade without a resume.",
	}
}

func (d *Service) writeParkedResumeGuidance(progress *ProgressLog) {
	for _, line := range ParkedResumeGuidance(d.projDir) {
		progress.Write("  %s", line)
	}
}
