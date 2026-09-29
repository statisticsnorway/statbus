package upgrade

import (
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
)

// RefusalClass names one kind of upgrade refusal whose remedy the product
// states to the operator. `./sb install` recognises the class with errors.As
// and shows the refusal's Text plus a fixed cause/fix pair (cli/cmd
// installRefusalCatalogue), instead of the generic failure line.
//
// Why a type and not message matching: rc.16's upgrade arcs (run 36468921894)
// found two named refusals, the severed proxy route (STATBUS-143) and the
// git-corrupt restore re-attempt (STATBUS-111), swallowed into "The
// installation stopped before it could finish." A class survives rewording and
// wrapping; a substring match does not.
type RefusalClass string

const (
	// RefusalProxyRouteMissing: crash recovery found no proxy container, the
	// route the service reaches PostgreSQL through (STATBUS-143 AC#3).
	RefusalProxyRouteMissing RefusalClass = "proxy-route-missing"
	// RefusalRestoreGitCorrupt: a restore re-attempt refused before any
	// destructive step because the source working tree cannot be resolved.
	RefusalRestoreGitCorrupt RefusalClass = "restore-git-corrupt"
	// RefusalRestoreDaemonOwnsLock: a restore re-attempt refused because a
	// running upgrade daemon still owns the upgrade lock.
	RefusalRestoreDaemonOwnsLock RefusalClass = "restore-daemon-owns-lock"
	// RefusalClaimImagesBuilding: the scheduled release's images are still
	// being published.
	RefusalClaimImagesBuilding RefusalClass = "claim-images-building"
	// RefusalClaimImagesFailed: the scheduled release's images failed to publish.
	RefusalClaimImagesFailed RefusalClass = "claim-images-failed"
	// RefusalClaimTaken: another actor claimed the scheduled row first.
	RefusalClaimTaken RefusalClass = "claim-taken"
	// RefusalClaimDaemonOwnsLock: a running upgrade daemon owns the upgrade
	// lock and claims scheduled rows itself.
	RefusalClaimDaemonOwnsLock RefusalClass = "claim-daemon-owns-lock"
	// RefusalRecoveryDBUnreachable: crash recovery cannot reach the database on
	// the service's own route, and starting the existing containers did not
	// help (the category-3 operator-investigate path; cli/cmd).
	RefusalRecoveryDBUnreachable RefusalClass = "recovery-db-unreachable"
	// RefusalUnparkFailed: `./sb install` could not clear a park marker, so it
	// cannot grant the parked upgrade its deliberate new attempt (cli/cmd).
	RefusalUnparkFailed RefusalClass = "unpark-failed"
	// RefusalRestoreDegraded: a restore re-attempt ran and failed again; the
	// box stays degraded on purpose and needs support, not a re-run (cli/cmd).
	RefusalRestoreDegraded RefusalClass = "restore-degraded"
)

// RefusalClasses lists every RefusalClass, so install's catalogue test can
// prove each one has operator guidance.
func RefusalClasses() []RefusalClass {
	return []RefusalClass{
		RefusalProxyRouteMissing,
		RefusalRestoreGitCorrupt,
		RefusalRestoreDaemonOwnsLock,
		RefusalClaimImagesBuilding,
		RefusalClaimImagesFailed,
		RefusalClaimTaken,
		RefusalClaimDaemonOwnsLock,
		RefusalRecoveryDBUnreachable,
		RefusalUnparkFailed,
		RefusalRestoreDegraded,
	}
}

// OperatorRefusalError is a refusal with product-authored operator guidance.
// Text is fixed wording (identifiers such as a row id or the configured
// administrator contact may appear; internal errors never do). Detail carries
// the internal cause, which belongs in logs: Error() appends it so rows,
// journals and wrapped errors keep the full diagnosis.
type OperatorRefusalError struct {
	Class  RefusalClass
	Text   string
	Detail error
}

func (e *OperatorRefusalError) Error() string {
	if e.Detail == nil {
		return e.Text
	}
	return fmt.Sprintf("%s (%v)", e.Text, e.Detail)
}

func (e *OperatorRefusalError) Unwrap() error { return e.Detail }

// NewProxyRouteMissingError is the STATBUS-143 category-3 refusal for the
// severed-route case: the proxy container the service reaches PostgreSQL
// THROUGH does not exist. Deliberately NOT auto-recreated — `up -d proxy` under
// the operator's binary can pull a different image tag than the in-flight
// upgrade target (the rc.66 → rc.67 mismatch class). Names the state + the
// manual operator option with that caveat, so a re-run of `./sb install` gives
// an actionable path out rather than a silent identical connection-refused loop.
func NewProxyRouteMissingError() error {
	return &OperatorRefusalError{
		Class: RefusalProxyRouteMissing,
		Text: "the db's connection route — the proxy container — does not exist; the crash that interrupted this upgrade may have removed it mid-recreate.\n" +
			"  Recovery reaches PostgreSQL THROUGH this proxy (Caddy layer4 on CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT), so it cannot connect, and it will not auto-recreate the proxy: `docker compose up -d proxy` under the current binary may pull a different image tag than the interrupted upgrade's target.\n" +
			"  Operator action: inspect `docker compose ps -a`; recreate the proxy deliberately with `docker compose up -d proxy` (accepting that version caveat), then re-run `" + diskpolicy.RerunCommand() + "`",
	}
}

// NewRestoreGitCorruptError is ReattemptRestore's refusal when the source
// working tree cannot be resolved: nothing destructive has run, and the
// operator must not proceed. contact is the configured administrator contact.
func NewRestoreGitCorruptError(detail error, contact string) error {
	return &OperatorRefusalError{
		Class: RefusalRestoreGitCorrupt,
		Text: fmt.Sprintf("%s: cannot resolve the source working tree before the database re-attempt — the git tree is corrupt; do NOT proceed. Manual recovery required: contact SSB support and involve your IT staff%s",
			ErrRollbackGitCorrupt, contactSuffix(contact)),
		Detail: detail,
	}
}
