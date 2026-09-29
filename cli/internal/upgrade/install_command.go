package upgrade

import "github.com/statisticsnorway/statbus/cli/internal/installcmd"

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
