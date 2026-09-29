package cmd

import (
	"errors"
	"fmt"
	"io"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// installKeepBoxFix is the outside fix for refusals where running the install
// again is the wrong advice: the box must stay as it is for support. install.sh
// recognises this exact sentence and ends without "run the same install
// command again".
const installKeepBoxFix = "Keep this box as it is and contact StatBus support with your IT staff."

// installRefusalGuidance is the fixed cause/fix pair a named upgrade refusal
// shows through install.sh. Like installFailureCauses, these are the only
// sentences that cross the log boundary for a refusal: never interpolate an
// error into them. install.sh's INSTALL_CAUSE/INSTALL_FIX allowlist must accept
// every pair (TestInstallRefusalGuidanceMatchesShellAllowlist).
type installRefusalGuidance struct {
	cause string
	fix   string
}

// installRefusalCatalogue maps every upgrade.RefusalClass to its guidance.
// TestEveryRefusalClassHasInstallGuidance fails when a class is added without
// an entry here.
var installRefusalCatalogue = map[upgrade.RefusalClass]installRefusalGuidance{
	upgrade.RefusalProxyRouteMissing: {
		"The database connection route is missing: the web server (proxy) container was removed while an upgrade was interrupted, and recovery does not recreate it automatically.",
		// STATBUS-143: the product's deliberate remedy names the command.
		"Recreate the web server deliberately: in the StatBus installation directory run docker compose up -d proxy, then retry.",
	},
	upgrade.RefusalRestoreGitCorrupt: {
		"The program files of the previous version cannot be found, so the database restore was refused before anything changed.",
		installKeepBoxFix,
	},
	upgrade.RefusalRestoreDaemonOwnsLock: {
		"The automatic update service is still running, so the database restore was not attempted.",
		"Wait for the automatic update service to stop, then retry.",
	},
	upgrade.RefusalClaimImagesBuilding: {
		"The images for the scheduled upgrade are still being published.",
		"Wait a few minutes, then retry.",
	},
	upgrade.RefusalClaimImagesFailed: {
		"The images for the scheduled upgrade failed to publish.",
		"Register the release again or choose a later release, then retry.",
	},
	upgrade.RefusalClaimTaken: {
		"Another process already started the scheduled upgrade.",
		"Wait for it to finish, then retry.",
	},
	upgrade.RefusalClaimDaemonOwnsLock: {
		"The automatic update service is starting the scheduled upgrade itself.",
		"Wait for it to finish, then retry.",
	},
	upgrade.RefusalRecoveryDBUnreachable: {
		"The database cannot be reached, and starting the existing database and web server did not restore the connection.",
		"Check Docker and database service health, then retry.",
	},
	upgrade.RefusalUnparkFailed: {
		"The paused upgrade could not be released for a new attempt because the database could not be updated.",
		"Check Docker and database service health, then retry.",
	},
	upgrade.RefusalRestoreDegraded: {
		"The database restore could not be completed; the system is still degraded.",
		installKeepBoxFix,
	},
}

// installRefusal returns the named refusal carried anywhere in err's chain.
func installRefusal(err error) (*upgrade.OperatorRefusalError, bool) {
	var refusal *upgrade.OperatorRefusalError
	if errors.As(err, &refusal) {
		return refusal, true
	}
	return nil, false
}

// printInstallRefusal shows a named refusal to the operator: the refusal's
// product-authored text (never its internal Detail), then the fixed cause/fix
// lines install.sh shows through its allowlist.
func printInstallRefusal(w io.Writer, refusal *upgrade.OperatorRefusalError) {
	_, _ = fmt.Fprintln(w, refusal.Text)
	guidance, ok := installRefusalCatalogue[refusal.Class]
	if !ok {
		return
	}
	_, _ = fmt.Fprintln(w, "INSTALL_CAUSE: "+guidance.cause)
	if guidance.fix != "" {
		_, _ = fmt.Fprintln(w, "INSTALL_FIX: "+guidance.fix)
	}
}

// restoreReattemptFailure classifies a failed restore re-attempt. A named
// refusal (git-corrupt, daemon owns the lock) stopped it before anything
// changed and keeps its own remedy: rc.16's restore-broke arc (run
// 36468921894) lost the git-corrupt refusal behind the generic line. Any other
// failure is the degraded FORECAST: the restore failed again.
func restoreReattemptFailure(err error, projDir string) error {
	if _, named := installRefusal(err); named {
		return err
	}
	return &upgrade.OperatorRefusalError{
		Class: upgrade.RefusalRestoreDegraded,
		Text: "  The database restore could not be completed; the system is still degraded.\n" +
			"  Next: contact SSB support and involve your IT staff. Keep this box as-is for diagnosis;\n" +
			fmt.Sprintf("  re-running `%s` will re-attempt the same restore", upgrade.InstallCommand(projDir)),
		Detail: err,
	}
}

// recoveryDBRouteRefusal classifies crash recovery's database-route failure.
// A named refusal from the start fallback (the severed proxy route,
// STATBUS-143) is returned as itself, so its remedy reaches the operator.
// Anything else is the category-3 operator-investigate refusal; the probe and
// start errors ride along as Detail for the log.
func recoveryDBRouteRefusal(reachErr, startErr error, projDir string) error {
	if _, ok := installRefusal(startErr); ok {
		return fmt.Errorf("%w (reachability probe: %v)", startErr, reachErr)
	}
	return &upgrade.OperatorRefusalError{
		Class: upgrade.RefusalRecoveryDBUnreachable,
		Text: "the database cannot be reached on the upgrade service's own route (CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT), and starting the existing db and proxy containers did not restore it.\n" +
			"  Recovery will not recreate containers: the current program could start a different version than the interrupted upgrade.\n" +
			fmt.Sprintf("  Operator action: check that Docker is running and that both db and proxy are present and healthy, then re-run `%s`", upgrade.InstallCommand(projDir)),
		Detail: errors.Join(reachErr, startErr),
	}
}
