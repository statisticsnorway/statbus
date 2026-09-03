package upgrade

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/dbdump"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/inject"
	"github.com/statisticsnorway/statbus/cli/internal/invariants"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/sbimage"
	"github.com/statisticsnorway/statbus/cli/internal/selfupdate"
	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
)

// markTerminal pins invariants.MarkTerminal to this service's projDir.
// Every fail-fast guard site in this file calls markTerminal before
// returning/continuing so the support bundle's install-terminal.txt has
// a named-invariant anchor for SSB triage.
func (d *Service) markTerminal(name, observed string) {
	invariants.MarkTerminal(d.projDir, name, observed)
}

// bootMigrateIsDeterministic reports whether a boot-migrate failure is the
// DETERMINISTIC class of the migrate exit-code contract (exit 20 = a migration's
// SQL failed identically on every apply — psql exit 3 under ON_ERROR_STOP; see
// cli/internal/migrate/exit_codes.go). STATBUS-144: the FLAGLESS boot-migrate
// handler stays alive-idle on this class (log-loud-once + continue) instead of
// the exit-and-restart-churn that a systemd Restart=always unit turns into a
// StartLimit death. Classifies on the numeric EXIT CODE ONLY, never stderr text
// (doc-022). `sb migrate up` maps its deterministic failure to os.Exit(20)
// (cli/cmd/migrate.go), and runCommandToLogCapture returns cmd.Run's raw
// *exec.ExitError unwrapped on a clean (non-timeout) failure, so errors.As reads
// the code directly. A timeout is ErrCommandTimeout (not an *exec.ExitError) and
// every other failure (unclassified exit 1, resource exit 22, a non-ExitError)
// is NOT this class — the caller keeps exit-and-restart for those (a re-run might
// succeed), matching the transient/unclassified rule.
func bootMigrateIsDeterministic(err error) bool {
	var exitErr *exec.ExitError
	return errors.As(err, &exitErr) && exitErr.ExitCode() == migrate.ExitDeterministic
}

// configGenerateIsPrincipledRefusal classifies a `./sb config generate`
// subprocess failure on its EXIT CODE ONLY (doc-022, same discipline as
// bootMigrateIsDeterministic above), never stderr text: exit 78/EX_CONFIG
// is exitPrincipledConfigRefusal, selected by configGenerateCmd.RunE
// (cli/cmd/config.go) exactly when config.ErrPrincipledRefusal is the
// cause. Every other failure (a timeout — ErrCommandTimeout, not an
// *exec.ExitError — permissions, disk full, an unclassified exit 1) is
// NOT this class and keeps the existing exit-and-let-systemd-retry
// behavior, because a retry might actually help there (STATBUS-298).
func configGenerateIsPrincipledRefusal(err error) bool {
	var exitErr *exec.ExitError
	return errors.As(err, &exitErr) && exitErr.ExitCode() == exitPrincipledConfigRefusal
}

// thisLine returns the caller's source line number. Guard-site transcripts
// embed it so the stderr message always points at the real code location
// even as the file is edited.
func thisLine() int {
	_, _, line, ok := runtime.Caller(1)
	if !ok {
		return 0
	}
	return line
}

// markPgInvariantTerminal inspects err for a pgx constraint violation
// that maps to a registered DB-enforced invariant. On a match it emits
// the INVARIANT-violated stderr transcript and writes install-terminal.txt
// so the on-disk audit channel is identical whether the check fired in
// Go or in PG. Returns the invariant name on match; empty string when
// err is nil or not a mapped constraint — caller then follows its
// usual error path.
//
// The caller string identifies the UPDATE/INSERT site; pass a stable
// label like "service.go:executeScheduled:claim" so support-bundle grep
// survives file edits.
func (d *Service) markPgInvariantTerminal(err error, caller string) string {
	if err == nil {
		return ""
	}
	name, observed := invariants.MapPgConstraint(err)
	if name == "" {
		return ""
	}
	fmt.Fprintf(os.Stderr,
		"INVARIANT %s violated (DB-enforced): %s (%s, pid=%d)\n",
		name, observed, caller, os.Getpid())
	d.markTerminal(name, fmt.Sprintf("caller=%s %s", caller, observed))
	return name
}

// retryBackoff is the sleep duration between bounded-retry attempts on
// transient DB connection errors (isConnError). Attempt 0 is the initial
// try (never reached from a retry branch); attempts 1/2/3 back off by
// 100ms/500ms/1s. Keep tight — the upgrade service's pipeline must not
// stall the admin UI for long.
func retryBackoff(attempt int) time.Duration {
	switch attempt {
	case 1:
		return 100 * time.Millisecond
	case 2:
		return 500 * time.Millisecond
	default:
		return 1 * time.Second
	}
}

// step11RestartServices lists the services brought up by applyNewSbUpgrading's
// step 11 (docker compose up -d --no-build ...). Together with step 9's
// "db", these are EXACTLY the containers whose image tag the upgrade
// pipeline advances to the post-upgrade target SHA.
//
// "proxy" is included here (Bug 2 fix, 2026-05-25). Pre-fix, proxy was
// in containers.go's `versionTrackedServices` (canary required tag
// match) but NOT restarted by step 11 — the canary returned `false`
// forever in any deployment where proxy was on a pre-upgrade tag
// (rune.statbus.org's 2026-05-25 hang). Re-aligned by adding proxy
// here: every upgrade now swaps the proxy image alongside app/worker/
// rest, so the new release's Caddyfile / cert / port config takes
// effect (the architectural reason proxy SHOULD be version-tracked).
// Brief interruption of the maintenance page during proxy restart is
// acceptable — Caddy restarts in <2 s; step 11's typical wall-clock is
// under a minute.
//
// containers.go's versionTrackedServices MUST equal `{"db"} ∪ (step11RestartServices \ {"rest"})`
// — "rest" is in step 11 (state-only check) but excluded from
// versionTrackedServices because postgrest's image tag is upstream-
// pinned. Drift between the two lists either wedges the canary
// (`containersAtFlagTarget` waits forever for a tag that never
// advances — the Bug 2 symptom) or skips verification of a container
// that DID advance. TestVersionTrackedAlignedWithUpgradePipeline
// asserts the invariant statically.
var step11RestartServices = []string{"app", "worker", "rest", "proxy"}

// Service is the long-running upgrade service.
type Service struct {
	projDir    string
	version    string    // compiled-in version from ldflags (e.g., v2026.03.0-rc.11)
	listenConn *pgx.Conn // dedicated to LISTEN/NOTIFY — never use for queries
	queryConn  *pgx.Conn // for all SELECT/INSERT/UPDATE queries
	verbose    bool
	channel    string
	interval   time.Duration
	autoDL     bool
	// DB-clock boundary sampled before READY=1. retireOffChannelOffers may repair
	// only rows that already existed before this daemon became externally ready;
	// a new candidate row created by `upgrade register` after READY must not be
	// mistaken for pre-filter shelf residue while boot migration/recovery finishes.
	offChannelSweepCutoff time.Time
	// STATBUS-308: last observed unit-floor state, so a tick journals only on a
	// TRANSITION. Zero value is unitfloor.OK, which is why the start-up announce
	// runs unconditionally — otherwise a box that boots already-breached would
	// compare equal to its zero value and never say anything.
	lastUnitFloorState unitfloor.State
	// Scheduled logical-backup settings (STATBUS-113), read from .env by loadConfig.
	backupEnabled   bool          // BACKUP_ENABLED — false opts the box out entirely
	backupInterval  time.Duration // BACKUP_INTERVAL — cadence of the pg_dump (default 24h)
	backupRetention int           // BACKUP_RETENTION_COUNT — dumps kept per prefix (default 7)
	backupMu        sync.Mutex    // single-flight guard: never two backups at once
	// pinnedVer removed — use "skip" in the UI instead of a channel that hides all releases
	upgrading      bool               // true during executeUpgrade; prevents ticker/notify from using nil conn
	cachedURL      string             // cached health check URL (derived from .env at startup)
	cachedReadyURL string             // cached PostgREST admin /ready URL (derived from .env; warmup gate before the RPC probe)
	listenCancel   context.CancelFunc // cancels the listenLoop goroutine
	listenDone     chan struct{}      // closed when the active listenLoop goroutine exits
	// listenWg retired in favour of listenDone: we need to tolerate a leaked
	// goroutine after a force-close timeout (task #40 / #37 root cause), and
	// sync.WaitGroup's counter would go negative on the leaked goroutine's
	// eventual Done() if the field was reassigned during restart. A per-run
	// channel has no state to corrupt.
	allowedSignersPath string    // path to tmp/allowed-signers file (empty if no signers configured)
	flagLock           *FlagLock // holds the flock on tmp/upgrade-in-progress.json during executeUpgrade
	runningAsService   bool      // true when Run() is the entry point; false for one-shot callers
	// STATBUS-046 / STATBUS-044 comment #6 — the crash-resume attempt is counted
	// ONCE per process lifetime, at the START of the recovery pass (before the boot
	// migrate). RecoveryBudgetGuard sets these; whichever downstream regime runs
	// afterwards (resumeNewSb / recoveryRollback) reuses the count instead of
	// double-incrementing. A fresh process (new boot) starts false — that is the
	// per-attempt reset (each boot IS one attempt).
	recoveryPassCounted  bool // true once this process counted its recovery attempt
	recoveryPassAttempts int  // recovery_attempts value from that increment
	// binaryCommit is the compile-time commit SHA (ldflags -X cmd.commit=<sha>),
	// a observed-state anchor the service uses to answer "what version is this
	// binary itself?" independent of git checkout state or row-recorded
	// targets. Used by completeInProgressUpgrade's observed-state verification
	// (task #49): if an in_progress row's commit_sha differs from
	// binaryCommit at post-restart recovery time, the upgrade did not
	// actually complete — mark failed, don't silently lie.
	//
	// "unknown" when the build has no ldflags (local go-run paths); in that
	// case the observed-state check degrades to a skip rather than a false
	// failure, since we can't know the binary's true identity.
	binaryCommit   string
	stuckLoopFired bool // set to true after SERVICE_STUCK_RETRY_LOOP is emitted, to avoid spam
	// unitInstance is the systemd unit name for this deployment's upgrade
	// service (e.g. statbus-upgrade.service), set by cmd via SetUnitInstance
	// where the name is derivable. Used by executeUpgrade to reset the
	// unit's restart counter at dispatch (STATBUS-039 review finding 2):
	// NRestarts accumulates across upgrades — every healthy exit-42 handoff
	// is an auto-restart (RestartForceExitStatus=42) and bumps it — so
	// without a per-upgrade reset, a box's 3rd+ legitimate upgrade would
	// trip the install takeover's crash-loop gate (NRestarts >= 3) and get
	// SIGKILL-taken-over mid-flight by a concurrent ./sb install. Empty on
	// non-systemd platforms / unknown unit → the reset is skipped and the
	// gate stays merely as conservative as pre-039.
	unitInstance string
	// STATBUS-338 test seams for the Norway rc.02 preswap fetch path. Production
	// leaves both nil: fetchCommitObjects delegates to fetchWithStallDetection and
	// fetchRetryWait uses a context-aware timer. Tests inject only the boundary
	// that failed on rune, never the surrounding upgrade state machine.
	fetchCommitObjects func(context.Context, io.Writer, string) error
	fetchRetryWait     func(context.Context, time.Duration) error
	// removeFile is a test seam for the two filesystem cleanup boundaries whose
	// failure changes recovery direction. Production leaves it nil and uses
	// os.Remove through removePath.
	removeFile func(string) error
}

// SetUnitInstance records the systemd unit name for the deployment's
// upgrade service. cmd calls this at construction where the unit name is
// derivable (serviceInstance); internal code must not guess it.
func (d *Service) SetUnitInstance(instance string) {
	d.unitInstance = instance
}

// NewService creates a new upgrade service.
//
// binaryCommit is the compile-time commit SHA from cli/cmd/root.go's
// `commit` ldflag. Pass cmd.commit directly from the caller. Leave
// "unknown" in non-release builds (go run, local test); the observed-state
// checks in completeInProgressUpgrade degrade to skip-with-log rather
// than false-negative in that case.
func NewService(projDir string, verbose bool, version, binaryCommit string) *Service {
	return &Service{
		projDir:      projDir,
		version:      version,
		verbose:      verbose,
		binaryCommit: binaryCommit,
	}
}

// HolderService and HolderInstall identify which actor wrote the flag.
// The recovery path branches on Holder: "service" needs DB reconciliation
// (mark public.upgrade row completed/failed); "install" has no DB row to
// touch — just remove the file. Empty Holder (legacy flags written before
// Release 1.1) is treated as "service" for backward compatibility.
const (
	HolderService = "service"
	HolderInstall = "install"
)

// Phase discriminates where executeUpgrade had reached when the holder's
// process last ran. The service swaps the ./sb binary on disk mid-flow then
// hands off to a fresh process via exit 42 / systemd restart so the remaining
// steps run against the NEW compiled Go. recoverFromFlag branches on Phase to
// distinguish a crashed pre-swap run (rollback) from an expected post-swap
// handoff (resume).
//
// Legacy flags pre-dating Option C lack the field and deserialize as empty;
// recoverFromFlag treats empty as PhaseOldSbUpgrading, preserving the prior
// "HEAD=target => self-heal to completed" semantics.
// CANONICAL phase slugs — the wire bytes THIS build writes (registry vocabulary,
// doc/upgrade-vocabulary.md). PhaseOldSbUpgrading stays the empty string: absence
// is the value (omitempty), never written, legacy-compatible by construction.
// Legacy wire bytes ("post_swap"/"resuming") written by pre-rename releases are
// normalized to these slugs at the UnmarshalJSON chokepoint — see
// legacyPhaseByteAliases below. This is the CANONICAL half of the two-part table
// the decode chokepoint joins; the legacy-alias half is kept structurally and
// nominally separate so canonical and legacy spellings never merge.
const (
	PhaseOldSbUpgrading = ""               // default: written before replaceBinaryOnDisk, or legacy (absence is the value)
	PhaseNewSbSwapped   = "new-sb-swapped" // stamped after binary swap, before exit-42 handoff
	// PhaseNewSbUpgrading is stamped the instant resumeNewSb commits to running
	// applyNewSbUpgrading on the new binary. A recovery that finds it means the planned
	// post-swap resume began and the process died before completing. Observed
	// state decides direction (STATBUS-039): at-or-past target (or
	// unverifiable) → resume FORWARD again; confirmed behind → one-shot
	// rollback to THIS upgrade's own snapshot. See upgrade-timeline.md
	// § Binary-swap restart + resume.
	PhaseNewSbUpgrading = "new-sb-upgrading"
)

// canonicalPhaseBytes is the set of wire values THIS build writes (the empty
// string included — PhaseOldSbUpgrading is canonical-by-absence). The decode
// chokepoint passes these through unchanged.
var canonicalPhaseBytes = map[string]struct{}{
	PhaseOldSbUpgrading: {},
	PhaseNewSbSwapped:   {},
	PhaseNewSbUpgrading: {},
}

// LEGACY-PHASE-BYTES: legacyPhaseByteAliases maps the two historical wire
// spellings that pre-rename releases stamped to their canonical slugs. It is the
// LEGACY half of the two-part table (kept separate from canonicalPhaseBytes so
// canonical and legacy spellings are never indistinguishable — King's refinement,
// STATBUS-164). This is a COMPATIBILITY FLOOR, not read-both-forever: the same
// genre as the empty-Holder⇒service and empty-Phase⇒old-sb-upgrading rules the
// format already carries. It exists because the unrecognized-sentinel read is
// MAINLINE, not a crash corner — during the one upgrade that crosses the rename
// boundary the OLD binary stamps "post_swap" and exits 42, and the NEW binary
// reads those bytes on its normal handoff (architect ruling, STATBUS-164 #2/#3).
//
// REMOVAL CONDITION: drop this table when pre-rename releases are no longer
// supported upgrade sources (the newest ./sb, fetched by install.sh to recover a
// broken box, must read every flag spelling still in the field until then).
//
// REVERSE-BOUNDARY RESIDUAL (documented, not fixed): a crash inside the rollback
// window after ./sb.old (a pre-rename binary) is restored but before flag removal
// leaves the OLD binary reading NEW bytes → its shipped FLAG_PHASE_UNKNOWN loud
// stop. Safe (stop, touch nothing), rare (crash inside rollback), and unfixable
// retroactively (the pre-rename binary already shipped).
var legacyPhaseByteAliases = map[string]string{
	"post_swap": PhaseNewSbSwapped,   // pre-rename updateFlagNewSbSwapped stamp
	"resuming":  PhaseNewSbUpgrading, // pre-rename resumeNewSb stamp
}

// normalizePhaseBytes joins the two named tables at the decode chokepoint,
// canonical-then-legacy: a canonical slug passes through; a legacy spelling
// normalizes to its slug; anything else is left untouched so the downstream
// FLAG_PHASE_UNKNOWN drift guard (recoverFromFlag) still fires on genuine drift.
func normalizePhaseBytes(phase string) string {
	if _, ok := canonicalPhaseBytes[phase]; ok {
		return phase
	}
	if canonical, ok := legacyPhaseByteAliases[phase]; ok {
		return canonical
	}
	return phase
}

// UpgradeFlag is written to tmp/upgrade-in-progress.json before destructive
// steps begin (by either the upgrade service or `./sb install`). The file
// doubles as the kernel-enforced mutex: holders take a flock(LOCK_EX) on
// the open fd and keep it alive for the duration of the work. Kernel
// auto-release on fd close (graceful exit, crash, or kill) makes stale
// locks impossible.
//
// If a holder crashes, the flag file content persists on the filesystem
// (NOT in the DB volume which gets rolled back). The next acquirer reads
// that prior metadata for audit + reconciliation, then truncates and
// writes its own metadata. On next service startup recoverFromFlag
// consults the file to decide what DB-level cleanup is needed based on
// Holder.
//
// STATBUS-111: liveness is the FLOCK ALONE (IsFlockHeld). A stored PID is a
// footgun — after a crash the OS can reuse the number for an unrelated process,
// so a PID-liveness check could read a stranger as "still running" and wrongly
// refuse recovery. The flock has no such hole (the OS frees it on holder death,
// reused PID or not). There is no PID field and no pidAlive(); operator messages
// that need to point at the holder emit the hint `lsof tmp/upgrade-in-progress.json`.
//
// Legacy flag files written before Release 1 lack StartedAt/InvokedBy and
// deserialize with zero values; Holder also defaults to empty (treated as
// "service"). A pre-111 flag's "pid" JSON key is simply ignored on unmarshal.
type UpgradeFlag struct {
	ID         int       `json:"id"`                    // 0 when Holder=="install"
	CommitSHA  string    `json:"commit_sha"`            // "" when Holder=="install"
	CommitTags []string  `json:"commit_tags,omitempty"` // release tags at CommitSHA; empty for install-held and untagged commits
	StartedAt  time.Time `json:"started_at"`            // time.Now() at write time
	InvokedBy  string    `json:"invoked_by"`            // specific trigger (e.g. "notify:v2026.04.1", "operator:jhf")
	Trigger    string    `json:"trigger"`               // coarse bucket ("notify"|"scheduled"|"recovery"|"install")
	Holder     string    `json:"holder"`                // HolderService or HolderInstall
	Phase      string    `json:"phase,omitempty"`       // PhaseOldSbUpgrading (default) or PhaseNewSbSwapped
	Recreate   bool      `json:"recreate,omitempty"`    // durable recreate intent (from public.upgrade.recreate) so resumeNewSb can replay --recreate
	BackupPath string    `json:"backup_path,omitempty"` // finalized backup dir, populated at Phase=PhaseNewSbSwapped so resumeNewSb can roll back without DB
	// OriginalError is the failure text captured before rollback begins. The flag
	// lives outside the database volume, so it survives exactly the process-death
	// gap that hid Norway rc.02's returned git error behind a nil-queryConn panic
	// and a manufactured INSTALL_PRECONDITION_FAILED on restart (STATBUS-338).
	OriginalError string `json:"original_error,omitempty"`
	// STATBUS-046 (doc-021): the dying-step fields for the crash-resume attempt
	// budget. Step is rewritten to the currently-executing Phase-3 step as each
	// step BEGINS (recordFlagStep), so a crash freezes the step it died at.
	// PriorDeathStep is the Step observed at the PREVIOUS resume — resumeNewSb
	// rolls Step→PriorDeathStep on each new attempt so resumeEscalation can detect
	// two consecutive deaths at the SAME step (deterministic hang → park early).
	Step           string `json:"step,omitempty"`
	PriorDeathStep string `json:"prior_death_step,omitempty"`
	// RetreatedToSourceAt (STATBUS-229) records a FACT that the Phase vocabulary
	// cannot express: this attempt's park restoration SUCCEEDED, so the box was
	// brought all the way back to the source version and nothing is in flight any
	// more. Set only on parkServiceRecovery's era-permitted success arm.
	//
	// It exists because every Phase value is a POSITION INSIDE an in-flight
	// upgrade — died-before-swap, binary-swapped, resume-began — and after a
	// completed retreat all of them are lies. STATBUS-210 expressed this state by
	// blanking Phase to PhaseOldSbUpgrading, a value that ALREADY means "died
	// before the swap"; two distinct states then shared one wire value, and
	// recoverFromFlag's unconditional PreSwap rollback (:1341) arrived on
	// schedule to roll back the very attempt an operator had just un-parked.
	// A new state gets its OWN name rather than borrowing one.
	//
	// ABSENCE IS MEANINGFUL AND LOAD-BEARING: a park whose restoration was
	// REFUSED (era guard said the box is not provably at source) leaves this
	// unset, and that flag still truthfully describes a mid-upgrade box that
	// RecoverFromFlag must handle. The two park outcomes must stay
	// distinguishable — collapsing them was 210's defect.
	RetreatedToSourceAt *time.Time `json:"retreated_to_source_at,omitempty"`
}

// HasRetreatedToSource reports whether this attempt's park restoration completed
// — the box is back at the source version with nothing in flight (STATBUS-229).
// Nil-safe so call sites can ask without a prior nil check.
func (f *UpgradeFlag) HasRetreatedToSource() bool {
	return f != nil && f.RetreatedToSourceAt != nil
}

// UnmarshalJSON is the ONE decode chokepoint for the on-disk flag: every read
// site (ReadFlagFile, recoverFromFlag, and the in-place read-modify-write stamps)
// decodes into an UpgradeFlag and so passes through here. It defers to the default
// struct decode, then normalizes the Phase wire byte through normalizePhaseBytes —
// so a pre-rename flag's legacy spelling ("post_swap"/"resuming") becomes its
// canonical slug before any semantic compare sees it, and a read-modify-write
// rewrite therefore persists the NEW bytes. No raw-byte phase comparison survives
// downstream; the state machine (the four Phase compares) is unchanged.
func (f *UpgradeFlag) UnmarshalJSON(data []byte) error {
	// Alias type strips the method set to avoid infinite recursion.
	type rawUpgradeFlag UpgradeFlag
	var raw rawUpgradeFlag
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	*f = UpgradeFlag(raw)
	f.Phase = normalizePhaseBytes(f.Phase)
	return nil
}

// Label returns a human-readable label for the flag. For service-held
// flags, the label is renderDisplayName(CommitSHA, CommitTags). For
// install-held flags, returns "install" (there is no commit-centric label,
// and STATBUS-111 removed the PID — liveness/identity is the flock, not a
// stored number).
func (f *UpgradeFlag) Label() string {
	if f == nil {
		return ""
	}
	if f.Holder == HolderInstall {
		return "install"
	}
	return renderDisplayName(CommitSHA(f.CommitSHA), f.CommitTags)
}

// IsServiceNewSbRecovery reports whether this flag represents an in-flight,
// service-held upgrade that crashed in a FORWARD phase (new-sb-swapped or new-sb-upgrading):
// the binary was already swapped on disk and the recovery boot must roll the
// upgrade FORWARD, reconciling the working tree to the target via the deferred
// target checkout (STATBUS-060). It is the single predicate shared by every
// site that must distinguish "let the recovery boot own tree→binary" from
// "treat as a fresh / genuinely-stale state":
//   - Service.Run's recovery-boot checkout gate,
//   - runCrashRecovery's checkout gate,
//   - stalenessGuard's self-heal carve-out (STATBUS-065) — such a flag means the
//     recovery boot, NOT a `make` rebuild, reconciles the tree, so the guard
//     must defer instead of rebuilding (tagged-release hosts have no toolchain).
//
// PreSwap (empty Phase) is deliberately EXCLUDED: that case rolls back, and the
// rollback's restoreGitState owns the tree (→ source commit). Nil-safe — a nil
// receiver (no flag file) is not a recovery.
func (f *UpgradeFlag) IsServiceNewSbRecovery() bool {
	return f != nil &&
		f.Holder == HolderService &&
		f.CommitSHA != "" &&
		(f.Phase == PhaseNewSbSwapped || f.Phase == PhaseNewSbUpgrading)
}

// flagFilePath returns the canonical flag file location under projDir.
// Package-level (vs. method on Service) so the install path — which has
// no Service instance — uses the same path computation.
func flagFilePath(projDir string) string {
	return filepath.Join(projDir, "tmp", "upgrade-in-progress.json")
}

func (d *Service) flagPath() string {
	return flagFilePath(d.projDir)
}

// configRefusalMarkerPath returns the canonical location for the STATBUS-298
// config-refusal marker, alongside the flag file it mirrors the pattern of.
// Package-level like flagFilePath, so ./sb install (no Service instance)
// reads the exact path the daemon writes.
func configRefusalMarkerPath(projDir string) string {
	return filepath.Join(projDir, "tmp", "config-refused.json")
}

// ConfigRefusalMarker is a REPORT of what the last daemon (or ./sb install)
// start concluded — NOT a second record of intent. The decision lives in
// .env.config; this only says what the last attempt to apply it found.
// Cleared on any successful start (ClearConfigRefusalMarker), which is what
// keeps that reading true (architect ruling, STATBUS-298 ticket comment #1).
type ConfigRefusalMarker struct {
	RefusedAt time.Time `json:"refused_at"`
	Message   string    `json:"message"`
}

// writeConfigRefusalMarker records a principled config-generate refusal.
// Best-effort: a write failure here must never mask the refusal itself —
// the caller exits 78 and the journal carries the full message regardless;
// this is a convenience surface for ./sb install, not the record of truth.
func writeConfigRefusalMarker(projDir, message string) {
	marker := ConfigRefusalMarker{RefusedAt: time.Now().UTC(), Message: message}
	data, err := json.MarshalIndent(marker, "", "  ")
	if err != nil {
		log.Printf("writeConfigRefusalMarker: marshal failed (refusal still reported via exit code + journal): %v", err)
		return
	}
	path := configRefusalMarkerPath(projDir)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		log.Printf("writeConfigRefusalMarker: mkdir failed: %v", err)
		return
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		log.Printf("writeConfigRefusalMarker: write failed: %v", err)
	}
}

// ClearConfigRefusalMarker removes the marker on a successful start.
// Cleared-on-success is the whole trustworthiness property: the marker's
// PRESENCE then always means "the last start refused," and it can never
// mislead once the config is fixed. Exported: ./sb install's own
// successful config generate must clear it too, not just the daemon's.
func ClearConfigRefusalMarker(projDir string) {
	if err := os.Remove(configRefusalMarkerPath(projDir)); err != nil && !os.IsNotExist(err) {
		log.Printf("ClearConfigRefusalMarker: remove failed: %v", err)
	}
}

// ReadConfigRefusalMarker reads the marker if present. (nil, nil) means
// absent — no start has ever refused, or a later successful start cleared
// it. Exported for ./sb install to surface the marker to the operator.
func ReadConfigRefusalMarker(projDir string) (*ConfigRefusalMarker, error) {
	path := configRefusalMarkerPath(projDir)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var marker ConfigRefusalMarker
	if err := json.Unmarshal(data, &marker); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &marker, nil
}

// acquireFlock opens the flag file with O_CREAT|O_RDWR, takes an
// exclusive kernel-level flock (LOCK_EX|LOCK_NB), then truncates and
// writes the given metadata. Caller keeps the returned *os.File open for
// the full duration of the work — closing it releases the flock. On
// crash the kernel closes fds automatically, so stale locks are
// impossible.
//
// Succeeds → returns a *FlagLock whose Close() releases the lock.
// Fails (another live holder) → returns a formatted error with the
// prior holder's metadata for diagnostics.
//
// Thread-safety: flock is kernel-enforced across the whole system;
// multiple processes racing on the same file are serialised by the
// kernel, no userland synchronisation needed.
func acquireFlock(projDir string, flag UpgradeFlag) (*FlagLock, error) {
	data, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("marshal flag: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
		return nil, fmt.Errorf("mkdir tmp: %w", err)
	}
	path := flagFilePath(projDir)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0644)
	if err != nil {
		return nil, fmt.Errorf("open flag: %w", err)
	}
	if lerr := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); lerr != nil {
		// Contention: another LIVE holder has the lock (the flock failing IS
		// the liveness signal — STATBUS-111). Read what's on disk for
		// diagnostics, without holding a lock.
		_ = f.Close() // best-effort; already erroring out
		existing, readErr := ReadFlagFile(projDir)
		if readErr != nil {
			return nil, fmt.Errorf("flag file unreadable while locked: %w\n  Investigate %s manually",
				readErr, path)
		}
		if existing == nil {
			// Pathological: flock failed but file was removed before we
			// could read it. Report generically.
			return nil, fmt.Errorf("flag file at %s is locked by another process (could not read metadata)", path)
		}
		return nil, formatContentionError(existing)
	}
	// We hold the lock. Truncate existing content and write ours.
	if _, err := f.Seek(0, 0); err != nil {
		_ = f.Close() // best-effort; already erroring out
		return nil, fmt.Errorf("seek flag: %w", err)
	}
	if err := f.Truncate(0); err != nil {
		_ = f.Close() // best-effort; already erroring out
		return nil, fmt.Errorf("truncate flag: %w", err)
	}
	if _, err := f.Write(data); err != nil {
		_ = f.Close() // best-effort; already erroring out
		return nil, fmt.Errorf("write flag: %w", err)
	}
	if err := f.Sync(); err != nil {
		_ = f.Close() // best-effort; already erroring out
		return nil, fmt.Errorf("sync flag: %w", err)
	}
	return &FlagLock{file: f}, nil
}

// acquireFlockVerbatim acquires the upgrade flag's flock WITHOUT changing what the
// flag says (STATBUS-212). acquireFlock TRUNCATES the file and writes whatever flag
// value it is handed (see the "We hold the lock" block above), so an acquisition
// whose only purpose is to GAIN THE HOLD must read the current content first and
// hand that exact value back — a naive acquire clobbers the very marker it meant to
// protect. That read-then-acquire-verbatim idiom already lives inline at
// RecoveryBudgetGuard (`base := *flag`); this is its named form, so an acquisition
// that must not change the flag's meaning says so at the call site and the failure
// arm lives in ONE place.
//
// Returns (nil, nil) when NO flag file exists. There is then no marker to hold and
// none to protect — and acquireFlock's O_CREATE would otherwise CONJURE an
// upgrade-in-progress marker out of nothing, which is strictly worse than not
// holding. Callers must treat a nil lock as "nothing to adopt", never as an error.
//
// A contended flock returns acquireFlock's error carrying the live holder's
// metadata; what a live holder MEANS is the caller's decision (STATBUS-111: the
// flock failing IS the liveness signal that another actor owns box mutations).
func acquireFlockVerbatim(projDir string) (*FlagLock, error) {
	existing, err := ReadFlagFile(projDir)
	if err != nil {
		return nil, fmt.Errorf("read flag before verbatim acquire: %w", err)
	}
	if existing == nil {
		return nil, nil
	}
	return acquireFlock(projDir, *existing)
}

// adoptOrAcquireFlagHold gives its caller a HELD flag lock for the duration of its
// work — whether or not the caller's own caller happened to hold one — and returns
// the release for EXACTLY what it acquired (STATBUS-212). A helper that must write
// through the held flock can then own that requirement instead of depending on
// ambient caller state it neither owns nor checks.
//
// Three outcomes, all releasable by calling the returned func:
//   - ALREADY HELD (the same `d.flagLock != nil && d.flagLock.file != nil` predicate
//     mutateHeldFlag itself uses, deliberately not a new one): adopt it — do not
//     acquire, and release NOTHING. Closing a lock this call did not open would pull
//     it out from under its owner mid-flow; the adopting path must stay byte-for-byte
//     as it was.
//   - NOT HELD, flag file present: acquire VERBATIM (acquireFlock rewrites the file
//     with whatever it is handed) and hand back the release for that lock.
//   - NOT HELD, NO flag file: nothing to hold and no marker that could be lying —
//     succeed with a no-op release rather than conjuring a marker into existence.
//
// A CONTENDED flock is returned as an error, never swallowed: the live holder is the
// signal that another actor owns box mutations (STATBUS-111), and only the caller can
// say what that means for its own work.
func (d *Service) adoptOrAcquireFlagHold() (release func(), err error) {
	if d.flagLock != nil && d.flagLock.file != nil {
		return func() {}, nil
	}
	lock, lerr := acquireFlockVerbatim(d.projDir)
	if lerr != nil {
		return nil, lerr
	}
	if lock == nil {
		return func() {}, nil
	}
	d.flagLock = lock
	return func() {
		d.flagLock = nil
		lock.Close()
	}, nil
}

// FlagLock holds the fd whose flock protects the upgrade-in-progress
// marker. Close releases the lock; fd death via crash also releases the
// lock automatically via kernel fd teardown.
type FlagLock struct {
	file *os.File
}

// Close releases the flock by closing the fd. Safe to call multiple
// times. File content persists on disk for the next acquirer to read
// and reconcile.
func (l *FlagLock) Close() {
	if l == nil || l.file == nil {
		return
	}
	_ = l.file.Close() // best-effort; Close() has no return value for callers to act on anyway
	l.file = nil
}

// writeUpgradeFlag is the service's acquire. On success, the FlagLock
// held on d.flagLock keeps the flock alive for the duration of
// executeUpgrade. removeUpgradeFlag closes it to release.
//
// Phase is initialised to PhaseOldSbUpgrading; updateFlagNewSbSwapped rewrites it to
// PhaseNewSbSwapped after replaceBinaryOnDisk, right before the exit-42
// handoff. Recreate carries the durable recreate intent (public.upgrade.recreate,
// read at claim) so the resumed post-swap process can replay --recreate identically.
func (d *Service) writeUpgradeFlag(id int, commitSHA string, commitTags []string, invokedBy, trigger string, recreate bool) error {
	flag := UpgradeFlag{
		ID:         id,
		CommitSHA:  commitSHA,
		CommitTags: commitTags,
		StartedAt:  time.Now(),
		InvokedBy:  invokedBy,
		Trigger:    trigger,
		Holder:     HolderService,
		Phase:      PhaseOldSbUpgrading,
		Recreate:   recreate,
	}
	lock, err := acquireFlock(d.projDir, flag)
	if err != nil {
		return err
	}
	d.flagLock = lock
	return nil
}

// updateFlagNewSbSwapped rewrites the on-disk flag JSON without releasing the
// flock: sets Phase=PhaseNewSbSwapped and stores backupPath so the new
// binary's recoverFromFlag → resumeNewSb can resume without a live DB
// connection (queryConn is closed mid-flow for the consistent backup).
//
// Preconditions: d.flagLock holds the flock (set by writeUpgradeFlag).
// Uses the already-open fd so the flock is preserved across the rewrite.
func (d *Service) updateFlagNewSbSwapped(backupPath string) error {
	if d.flagLock == nil || d.flagLock.file == nil {
		return fmt.Errorf("updateFlagNewSbSwapped: no flag file held")
	}
	f := d.flagLock.file
	if _, err := f.Seek(0, 0); err != nil {
		return fmt.Errorf("seek flag for read: %w", err)
	}
	data, err := io.ReadAll(f)
	if err != nil {
		return fmt.Errorf("read flag: %w", err)
	}
	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		return fmt.Errorf("unmarshal flag: %w", err)
	}
	// LOAD-BEARING COUPLING (STATBUS-228): these two assignments must stay in
	// the SAME write. This function is the ONLY writer of flag.BackupPath, and
	// it flips the phase away from PreSwap in the same breath — that is what
	// enforces "a PreSwap flag carries an empty BackupPath by construction"
	// (:1300-1353's safety argument) structurally rather than by convention.
	// Splitting these for tidiness reopens STATBUS-197's defect: a PreSwap
	// flag carrying a snapshot identity turns the PreSwap rollback no-op into
	// a destructive restore that rewinds recovery_attempts.
	flag.Phase = PhaseNewSbSwapped
	flag.BackupPath = backupPath
	newData, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal flag: %w", err)
	}
	if _, err := f.Seek(0, 0); err != nil {
		return fmt.Errorf("seek flag for write: %w", err)
	}
	if err := f.Truncate(0); err != nil {
		return fmt.Errorf("truncate flag: %w", err)
	}
	if _, err := f.Write(newData); err != nil {
		return fmt.Errorf("write flag: %w", err)
	}
	if err := f.Sync(); err != nil {
		return fmt.Errorf("sync flag: %w", err)
	}
	return nil
}

// recordFlagStep (STATBUS-046 doc-021) rewrites the held flag's Step field to
// the currently-executing Phase-3 step as each step BEGINS, so a crash/kill
// freezes the step it died at. resumeNewSb reads it on the next resume to
// detect same-step-twice (deterministic hang → park early). Same in-place
// seek/truncate/rewrite pattern as updateFlagNewSbSwapped (flock held throughout).
// Best-effort: a failure to persist the step name must not abort the upgrade —
// it only degrades same-step-twice detection to the plain attempt budget — so
// callers log and continue rather than fail the step.
// mutateHeldFlag reads the held on-disk flag, applies fn, and rewrites it in
// place (seek/truncate/rewrite under the held flock) — the shared core of
// recordFlagStep + recordRollbackCommit so the flag-rewrite pattern lives once.
func (d *Service) mutateHeldFlag(fn func(*UpgradeFlag)) error {
	if d.flagLock == nil || d.flagLock.file == nil {
		return fmt.Errorf("no flag file held")
	}
	f := d.flagLock.file
	if _, err := f.Seek(0, 0); err != nil {
		return fmt.Errorf("seek flag for read: %w", err)
	}
	data, err := io.ReadAll(f)
	if err != nil {
		return fmt.Errorf("read flag: %w", err)
	}
	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		return fmt.Errorf("unmarshal flag: %w", err)
	}
	fn(&flag)
	newData, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal flag: %w", err)
	}
	if _, err := f.Seek(0, 0); err != nil {
		return fmt.Errorf("seek flag for write: %w", err)
	}
	if err := f.Truncate(0); err != nil {
		return fmt.Errorf("truncate flag: %w", err)
	}
	if _, err := f.Write(newData); err != nil {
		return fmt.Errorf("write flag: %w", err)
	}
	if err := f.Sync(); err != nil {
		return fmt.Errorf("sync flag: %w", err)
	}
	return nil
}

func (d *Service) recordFlagStep(step string) error {
	return d.mutateHeldFlag(func(f *UpgradeFlag) { f.Step = step })
}

// recordOriginalError preserves the error that caused a claimed upgrade to
// stop before rollback can touch connections, services, or the database volume.
// Norway rc.02 returned a real git fetch error after queryConn had been cleared;
// rollback then panicked and the next boot had only a PreSwap flag, so recovery
// invented INSTALL_PRECONDITION_FAILED and discarded the true retryable cause.
// The held flag is the smallest truthful carrier across that process-death gap.
// Best-effort callers keep the original error in memory even if this audit write
// itself fails.
func (d *Service) recordOriginalError(reason string) error {
	reason = strings.TrimSpace(reason)
	if reason == "" || d.flagLock == nil || d.flagLock.file == nil {
		return nil
	}
	return d.mutateHeldFlag(func(f *UpgradeFlag) { f.OriginalError = reason })
}

// recordRollbackCommit stamps the held flag as a committed rollback attempt
// (STATBUS-046 slice 1B): it ROLLS the death history — PriorDeathStep←(current
// flag.Step, i.e. where the last death was), THEN Step←StepRollback (this
// attempt is a rollback). Two consecutive mid-rollback deaths thus make BOTH
// Step and PriorDeathStep == StepRollback → rollbackResumeIsTerminal fires. On
// the forward→rollback handoff PriorDeathStep receives the FORWARD step (never
// StepRollback), so the first rollback resume is free by construction. Order
// matters: prior←Step BEFORE Step←StepRollback. Best-effort like markStep — a
// failure only degrades same-step-twice detection, never aborts the rollback.
func (d *Service) recordRollbackCommit() {
	if err := d.mutateHeldFlag(func(f *UpgradeFlag) {
		f.PriorDeathStep = f.Step
		f.Step = StepRollback
	}); err != nil {
		log.Printf("recordRollbackCommit: %v — same-step-twice detection degraded for this rollback", err)
	}
}

// markStep records the current Phase-3 step on the held flag (best-effort). A
// failure to persist only degrades same-step-twice detection to the plain
// attempt budget (which still bounds the loop), so it logs and never aborts the
// step. STATBUS-046 doc-021.
func (d *Service) markStep(step string) {
	if err := d.recordFlagStep(step); err != nil {
		log.Printf("recordFlagStep(%s): %v — same-step-twice detection degraded; the attempt budget still bounds the loop", step, err)
	}
}

// ClearFlagStepHistory zeroes the on-disk flag's Step + PriorDeathStep
// (STATBUS-044 comment #6, architect F2). It is the flag-side companion to the
// row-side UnparkByID: a deliberate ./sb install un-park resets recovery_attempts
// in the row, but the flag's frozen death history survives on disk — so the very
// next escalation consult would read Step==PriorDeathStep==<the killer step> and
// same-step-twice INSTA-RE-PARK the fresh attempt at attempts==1, breaking the
// "install grants ONE fresh attempt" contract. Clearing both fields makes the
// fresh attempt start from a clean history (no prior death).
//
// Caller contract: invoked ONLY when no flock is held (the ./sb install
// crash-recovery path, where stopRestartUpgradeUnit has quiesced the unit and
// released the flock). It acquires the flock itself, rewrites the two fields, and
// releases — never touches the row. A missing/unreadable/non-service flag is a
// no-op (nothing to clear). Best-effort by contract of its single caller (a
// clear-failure only risks a re-park the operator can retry), but it returns the
// error so the caller can log it.
func (d *Service) ClearFlagStepHistory() error {
	flag, err := ReadFlagFile(d.projDir)
	if err != nil {
		return err
	}
	if flag == nil || flag.Holder != HolderService {
		return nil // no service-held flag → nothing to clear
	}
	flag.Step = ""
	flag.PriorDeathStep = ""
	lock, lerr := acquireFlock(d.projDir, *flag) // truncate-rewrites the flag with the cleared fields
	if lerr != nil {
		return lerr
	}
	lock.Close() // release immediately; downstream recovery re-acquires
	return nil
}

// RemoveFlagAfterRetreat deletes the upgrade marker for an attempt that already
// RETREATED TO SOURCE (STATBUS-229) — the park restoration completed, so the box
// is back at the source version with nothing in flight and the whole flag is
// stale, not one field of it. The scheduled row is then claimed FRESH through
// the normal path rather than "recovered".
//
// It REFUSES on a flag that does not carry the retreat marker, so the decision
// cannot be made accidentally by a caller that skipped the check: an
// era-REFUSED park leaves the marker unset and its flag truthfully describes a
// mid-upgrade box that RecoverFromFlag must still handle. Sibling of
// ClearFlagStepHistory and it shares that caller contract exactly — invoked ONLY
// where no flock is held (the ./sb install crash-recovery path, unit quiesced,
// flock free). It acquires the flock itself so the removal cannot race a live
// holder, and never touches the row.
func (d *Service) RemoveFlagAfterRetreat() error {
	flag, err := ReadFlagFile(d.projDir)
	if err != nil {
		return err
	}
	if flag == nil {
		return nil // already gone — the outcome the caller wanted
	}
	if flag.Holder != HolderService {
		return fmt.Errorf("refusing to remove a %q-held upgrade flag: only a service-held flag can carry a completed retreat", flag.Holder)
	}
	if !flag.HasRetreatedToSource() {
		return fmt.Errorf("refusing to remove the upgrade flag for id=%d: it carries no completed-retreat marker, so it still describes an in-flight upgrade that crash recovery must reconcile (an era-REFUSED park looks exactly like this)", flag.ID)
	}
	// Take the flock before unlinking: the caller's contract says the unit is
	// quiesced, and acquiring proves it rather than assuming it. A live holder
	// fails here instead of having its marker deleted underneath it.
	lock, lerr := acquireFlock(d.projDir, *flag)
	if lerr != nil {
		return lerr
	}
	defer lock.Close()
	const consequence = "the un-parked attempt will be treated as a crash recovery instead of a fresh attempt, and may be rolled back rather than resumed forward"
	rerr := os.Remove(d.flagPath())
	warnOnStaleFlagRemoveFailure(d.flagPath(), rerr, consequence)
	if rerr != nil && !os.IsNotExist(rerr) {
		return rerr
	}
	return nil
}

// warnOnStaleFlagRemoveFailure is STATBUS-187 AC#3's uniform stale-flag-
// class treatment (architect ruling, ticket comment #7), shared by every
// flag-owning function's unlink: removeUpgradeFlag's two internal sites,
// ReleaseInstallFlag, the post-swap self-heal completion-flag remove, and
// cleanStaleMaintenance's maintenance-flag remove.
//
// LOUD-WARN, never hard-fail — these are cleanup-AFTER-terminal sites;
// hard-failing would convert a successful upgrade/rollback/install into a
// reported failure over a janitorial unlink. os.IsNotExist is SILENT
// success: a double-removal race (two actors both cleaning up the same
// already-gone file) must not cry wolf. Any OTHER unlink error gets
// exactly one loud line naming the path, the raw error, the consequence
// (caller-supplied — what a later boot/run will misread the stale file
// as), and the remedy: remove it manually if it persists — a filesystem
// that refuses unlink is a box-level problem, not a code bug.
func warnOnStaleFlagRemoveFailure(path string, err error, consequence string) {
	if err == nil || os.IsNotExist(err) {
		return
	}
	log.Printf("WARNING: could not remove stale flag file %s: %v — %s. Remove it manually if it persists; a filesystem that refuses unlink is a box-level problem.", path, err, consequence)
}

func (d *Service) removePath(path string) error {
	if d.removeFile != nil {
		return d.removeFile(path)
	}
	return os.Remove(path)
}

// execObserved runs a write whose failure does not change control flow but
// must never be invisible. "Best-effort, retried next cycle" was the comment on
// the pruner's UPDATE while it was rejected by a NOT NULL constraint on every
// tick for two days (40baf42fe): a swallowed error turns a retry loop into a
// silent livelock that looks like activity. Every discarded Exec in this
// package now routes through here, so a constraint rejection, a lost
// connection, or a schema mismatch is on the journal with the statement's
// purpose and its arguments, even when the caller has no branch to take.
func (d *Service) execObserved(ctx context.Context, purpose, sql string, args ...any) error {
	if d.queryConn == nil {
		log.Printf("%s: skipped, no query connection", purpose)
		return fmt.Errorf("%s: no query connection", purpose)
	}
	ct, err := d.queryConn.Exec(ctx, sql, args...)
	if err != nil {
		log.Printf("%s: write did not land (args=%v): %v", purpose, args, err)
		return err
	}
	if ct.RowsAffected() == 0 && strings.HasPrefix(strings.TrimSpace(strings.ToUpper(sql)), "UPDATE") {
		// Zero rows on an UPDATE is a fact, not an error: the guard did not
		// match. Callers that need to distinguish "already so" from "row gone"
		// branch on the return; the log line makes the miss visible either way.
		log.Printf("%s: UPDATE matched 0 rows (args=%v)", purpose, args)
	}
	return nil
}

// removeUpgradeFlag releases the service's flock AND removes the
// on-disk JSON. Symmetric with ReleaseInstallFlag (line 314): once
// the service has reconciled the upgrade row to a terminal state,
// the flag file's reconciliation purpose is exhausted, and leaving
// it on disk creates a ghost flag that the install probe
// misclassifies as StateCrashedUpgrade.
//
// On a true crash the kernel releases the flock automatically (fd
// teardown) but the file persists — that's the genuine recovery
// case, handled by recoverFromFlag at next service startup.
//
// NEVER unlink a mutex you do not hold AT THE INSTANT OF THE UNLINK
// (STATBUS-039 finding 3 hardening + the F4 TOCTOU review note): unlinking
// a file whose flock another live actor holds split-brains the mutex — the
// holder's flock survives on the unlinked inode while the next acquirer
// flocks a freshly created file, and two destructive recoveries can then
// run concurrently. Check-then-remove forms leave µs windows (a new
// acquirer can win between the check and the unlink), so every branch
// removes WHILE HOLDING the flock:
//
//   - Own lock held: unlink FIRST, then Close. A concurrent acquirer
//     either blocks on our flock until the close (then creates a fresh
//     file) or creates the fresh file right after the unlink — its file
//     can never be the one we unlinked.
//   - No lock of ours (ghost cleanup, e.g. completeInProgressUpgrade's
//     deferred cleanup after a recoveryRollback flock-gate YIELD): take
//     the flock non-blocking and remove while holding — the same flock
//     that CHECKS also SERIALIZES, so no acquirer can win mid-removal.
//     EWOULDBLOCK → a live actor owns it → not ours to remove, leave it.
//     File absent → nothing to do (and no O_CREATE — never manufacture a
//     flag while cleaning one up).
func (d *Service) removeUpgradeFlag() error {
	const consequence = "a later boot will read this stale flag and route to crash-recovery/ghost-flag reconcile (an availability wedge, not corruption; that path re-attempts this same removal every boot)"
	path := d.flagPath()
	if d.flagLock != nil {
		removeErr := d.removePath(path)
		warnOnStaleFlagRemoveFailure(path, removeErr, consequence)
		d.flagLock.Close()
		d.flagLock = nil
		if os.IsNotExist(removeErr) {
			return nil
		}
		return removeErr
	}
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer func() { _ = f.Close() }() // releases the flock (on the unlinked inode after removal)
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		log.Printf("removeUpgradeFlag: upgrade flock held by another live actor — leaving the flag file in place (not ours to remove)")
		return err
	}
	removeErr := d.removePath(path)
	warnOnStaleFlagRemoveFailure(path, removeErr, consequence)
	if os.IsNotExist(removeErr) {
		return nil
	}
	return removeErr
}

// releaseUpgradeFlagLockKeepingFile turns the current attempt into a genuine
// crash-recovery shape without waiting for process death: the kernel flock is
// released, but the JSON marker stays on disk for DetectState and ./sb install.
// Use only when the row is durably failed and unresolved machine cleanup still
// requires an explicit recovery pass.
func (d *Service) releaseUpgradeFlagLockKeepingFile() {
	if d.flagLock == nil {
		return
	}
	d.flagLock.Close()
	d.flagLock = nil
}

// writeGoroutineDump captures all goroutine stacks via runtime.Stack and
// writes them to a timestamped file under <projDir>/tmp/. Non-destructive
// — the service keeps running. Called from the SIGUSR1 handler installed
// in Run().
//
// The dump size is unpredictable (proportional to goroutine count × stack
// depth). Start at 64 KB, double until runtime.Stack returns a length
// less than the buffer — that's the reliable "fit" signal.
//
// Returns the file path (for the caller to log) and any error encountered.
func (d *Service) writeGoroutineDump() (string, error) {
	buf := make([]byte, 64*1024)
	for {
		n := runtime.Stack(buf, true)
		if n < len(buf) {
			buf = buf[:n]
			break
		}
		// Dump filled the buffer — may have been truncated. Grow and retry.
		buf = make([]byte, 2*len(buf))
	}
	dumpDir := filepath.Join(d.projDir, "tmp")
	if err := os.MkdirAll(dumpDir, 0755); err != nil {
		return "", fmt.Errorf("mkdir %s: %w", dumpDir, err)
	}
	name := fmt.Sprintf("upgrade-service-goroutines-%s.txt",
		time.Now().UTC().Format("20060102T150405Z"))
	path := filepath.Join(dumpDir, name)
	if err := os.WriteFile(path, buf, 0644); err != nil {
		return "", fmt.Errorf("write %s: %w", path, err)
	}
	return path, nil
}

// AcquireInstallFlag atomically claims the upgrade-mutex marker for an
// `./sb install` invocation. Returns a *FlagLock on success — the caller
// MUST keep it alive for the full install duration and Close() it when
// done (typically via defer).
//
// On contention (another actor — service, install, or migrate — holds
// the flock), returns an error formatted to guide the operator to the
// right recovery action. The prior holder's metadata is read from the
// file for the diagnostic.
func AcquireInstallFlag(projDir, invokedBy string) (*FlagLock, error) {
	flag := UpgradeFlag{
		StartedAt: time.Now(),
		InvokedBy: invokedBy,
		Trigger:   "install",
		Holder:    HolderInstall,
	}
	return acquireFlock(projDir, flag)
}

// ReleaseInstallFlag releases the install flock AND removes the flag file.
// Install flags (Holder="install") have no DB row to reconcile — they're
// purely a mutex. Leaving them on disk creates a false "crashed-upgrade"
// detection on the next install run.
// Accepts the *FlagLock returned by AcquireInstallFlag. Safe to call
// multiple times; safe to call with a nil lock.
//
// Remove WHILE HOLDING, then close (STATBUS-039 F4 TOCTOU): close-then-
// remove leaves a µs window where a new acquirer wins the flock on the
// file and our remove unlinks ITS mutex — split-brain. Unlink-first means
// a concurrent acquirer either blocks until our close (then creates a
// fresh file) or creates the fresh file right after the unlink; its file
// is never the one we unlinked. Same discipline as removeUpgradeFlag.
func ReleaseInstallFlag(lock *FlagLock) {
	if lock != nil && lock.file != nil {
		// STATBUS-187 AC#3 (architect ruling, ticket comment #7): uniform
		// stale-flag-class treatment — see warnOnStaleFlagRemoveFailure.
		path := lock.file.Name()
		warnOnStaleFlagRemoveFailure(path, os.Remove(path),
			"a later `./sb install` run will read this stale flag and misdetect a crashed install (an availability wedge, not corruption; that path re-attempts this same removal every boot)")
		lock.Close()
	} else {
		lock.Close()
	}
}

// formatContentionError builds the operator-facing message for a failed
// acquireFlock. It is called ONLY from the flock-contention branch, where
// another process demonstrably HOLDS the flock — so the holder is LIVE by
// construction (STATBUS-111: liveness = the flock alone; there is no
// PID-liveness branch and thus no "crashed" case here — a crashed holder frees
// the flock, so acquireFlock succeeds and the recovery path takes over). It
// branches on Holder to tailor the wait guidance, and emits the `lsof` hint so
// the operator can see WHICH process holds the marker without a PID baked into
// the file.
//
// Empty Holder (legacy pre-Release-1.1 flags) is treated as service.
func formatContentionError(flag *UpgradeFlag) error {
	holder := flag.Holder
	if holder == "" {
		holder = HolderService
	}
	const lsofHint = "  See which process holds it:\n    lsof tmp/upgrade-in-progress.json"
	switch holder {
	case HolderInstall:
		return fmt.Errorf(
			"another ./sb install is already running (%s, invoked_by=%s).\n\n%s\n\n"+
				"  Wait for it to complete, then retry",
			flag.Label(), flag.InvokedBy, lsofHint)
	default: // HolderService
		return fmt.Errorf(
			"an orchestrated upgrade is in progress (%s, invoked_by=%s).\n\n%s\n\n"+
				"  Wait for it to complete:\n"+
				"    journalctl --user -u 'statbus-upgrade@*' -f\n\n"+
				"  Do NOT pass --post-upgrade-fixup — that flag is the upgrade service's\n"+
				"  internal contract with its own post-upgrade install step. Using it from the\n"+
				"  command line would corrupt an upgrade that is currently running",
			flag.Label(), flag.InvokedBy, lsofHint)
	}
}

// ReadFlagFile inspects the upgrade-in-progress flag at <projDir>/tmp/upgrade-in-progress.json.
// Returns (nil, nil) when the flag file is absent (upgrade-mutex is "Idle"),
// (flag, nil) when it exists. STATBUS-111: it no longer reports liveness — a
// stored PID is a reuse footgun. Callers that need to know whether a LIVE holder
// exists call IsFlockHeld (the flock is the sole liveness source).
//
// Callers outside this package should treat this as read-only: never remove or modify
// the flag file. Ownership belongs to the upgrade service (service.go:writeUpgradeFlag
// and removeUpgradeFlag).
func ReadFlagFile(projDir string) (*UpgradeFlag, error) {
	path := filepath.Join(projDir, "tmp", "upgrade-in-progress.json")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		return nil, fmt.Errorf("parse upgrade flag file: %w", err)
	}
	return &flag, nil
}

// isConnError returns true for errors that indicate a dead/stale TCP
// connection rather than a database-level error like a CHECK constraint
// violation. Used to gate a single reconnect-and-retry on the final
// state='completed' UPDATE, which can hit a stale queryConn if Docker
// recreation RSTs the TCP socket during runInstallFixup.
//
// Widened for rune-stuck fix B (Apr 24): pgx surfaces a TCP RST as
// "timeout: context already done: context canceled" when its internal
// context-watcher fires on the dropped conn. The prior matcher looked
// for "conn closed" / "connection reset" and missed this shape, so
// the stale-conn retry never ran — first attempt failed, invariant
// fired, upgrade stuck in_progress. We now also match the
// context-cancellation sentinels via errors.Is + substring fallback
// for pgx-wrapped variants.
func isConnError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
		return true
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	msg := err.Error()
	return strings.Contains(msg, "conn closed") ||
		strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "context already done") ||
		strings.Contains(msg, "context canceled") ||
		strings.Contains(msg, "context deadline exceeded")
}

// IsFlockHeld tries a non-blocking LOCK_EX on the flag file. Returns true
// if the flock is held (genuinely active upgrade), false if the flock is
// free (ghost flag from a completed upgrade whose file wasn't cleaned up).
// Returns false when the file doesn't exist or can't be opened.
//
// Used by install.defaultProbe.ReadFlag to distinguish a ghost flag
// (service alive but flock released — completed upgrade) from a live flag
// (service holding flock — upgrade in progress). pidAlive alone can't
// distinguish these because the service survives SHA upgrades.
func IsFlockHeld(projDir string) bool {
	path := flagFilePath(projDir)
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return false
	}
	defer func() { _ = f.Close() }()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return true // flock held → genuinely live upgrade
	}
	_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	return false // flock was free → ghost flag
}

// loadLogRelPath fetches the per-upgrade log basename stored on
// public.upgrade.log_relative_file_path. Returns "" if the row is missing,
// the column is NULL, or the query errors — all of which are non-fatal
// because the on-disk log is an operator-facing artifact, not load-bearing
// for reconciliation logic.
func (d *Service) loadLogRelPath(ctx context.Context, id int64) string {
	if id <= 0 {
		return ""
	}
	// STATBUS-190: bound the read — this is the FIRST DB read on the recovery
	// classify path; a paused/frozen DB would otherwise hang it before recovery
	// even reaches the observed-state verify. The timeout degrades to the existing
	// "" fallback (the on-disk log is operator-facing, not load-bearing).
	readCtx, cancel := context.WithTimeout(ctx, recoveryReadTimeout)
	defer cancel()
	var relPath sql.NullString
	if err := d.queryConn.QueryRow(readCtx,
		"SELECT log_relative_file_path FROM public.upgrade WHERE id = $1", id).
		Scan(&relPath); err != nil {
		return ""
	}
	return relPath.String
}

// recoverFromFlag checks for a flag file from a previous interrupted upgrade.
// Distinguishes between a real crash (mark failed) and a self-update restart
// (mark completed) by checking if git HEAD matches the upgrade target.
//
// All narrative lines go through logRecover, which writes to stdout AND
// appends to the crashed run's progress log file (if it still exists).
// That way operators reading the admin UI's "Log" panel after
// reconciliation see both the pre-crash story and the recovery summary
// in one place — no need to SSH in for systemd logs.
func (d *Service) recoverFromFlag(ctx context.Context) (err error) {
	data, readErr := os.ReadFile(d.flagPath())
	if readErr != nil {
		return nil // no flag file — normal startup
	}

	var flag UpgradeFlag
	if jsonErr := json.Unmarshal(data, &flag); jsonErr != nil {
		fmt.Printf("FLAG_CORRUPT: upgrade flag file unreadable, removing: %v\n", jsonErr)
		// STATBUS-187 #10 (architect ruling, ticket comment #9):
		// ACCEPT-BOUNDED, formal. A failed Remove here re-enters this SAME
		// branch next boot by construction — the corrupt flag is re-read
		// as corrupt and re-removed; no decision is taken on the stale
		// artifact in the meantime, so no lie follows the failure. The
		// FLAG_CORRUPT print above already names the event.
		_ = os.Remove(d.flagPath())
		return nil
	}

	holder := flag.Holder
	if holder == "" {
		holder = HolderService // legacy flags pre-Release 1.1
	}

	// Append recovery narrative to the crashed run's progress log so the
	// on-disk log (served via /upgrade-logs/<name>) captures both the
	// pre-crash lines and the reconciliation summary. If the log file
	// doesn't exist (legacy flag, missing run, row already cleared), the
	// lookup returns an empty relPath and AppendProgressLog returns nil —
	// logRecover then falls back to stdout.
	logRelPath := d.loadLogRelPath(ctx, int64(flag.ID))
	appendLog := AppendProgressLog(d.projDir, logRelPath)
	if appendLog != nil {
		defer appendLog.Close()
	}
	logRecover := func(format string, args ...interface{}) {
		if appendLog != nil {
			appendLog.Write(format, args...)
		} else {
			fmt.Printf(format+"\n", args...)
		}
	}

	// STATBUS-318: the string now follows the comment that has stood here since
	// the neutral-wording change — "interrupted" was misleading for the planned
	// post-swap continuation, and the fix is to stop saying it in that case
	// rather than to keep apologising for it.
	//
	// THE DISCRIMINATOR IS THE PHASE, and it is exact rather than a guess:
	//   PhaseNewSbSwapped   — stamped after the binary swap, immediately before
	//                         the deliberate exit-42 handoff. A fresh process
	//                         finding this flag is the DESIGN working: it is
	//                         meeting a marker its own predecessor left for it
	//                         one moment earlier. Nothing was interrupted.
	//   PhaseNewSbUpgrading — the post-swap resume had begun and that process
	//                         DIED before completing (watchdog, OOM, reboot).
	//   PhaseOldSbUpgrading — a crash before the swap, on the old binary.
	// The latter two are genuine recovery and keep recovery language.
	//
	// WHY THIS IS WORTH THE BRANCH: an operator watching the planned handoff
	// read "Recovering an interrupted upgrade" at the exact moment the upgrade
	// was proceeding perfectly, and reasonably concluded the system had lost
	// track of itself. A log that accuses itself of crashing during normal
	// operation teaches its reader to distrust it — and then the message means
	// nothing on the day something HAS actually crashed.
	//
	// Both branches keep the same detail suffix: high level first, in the
	// operator's words, then the precise identifiers for diagnosis.
	if opening := recoveryOpeningLine(flag, holder); opening != "" {
		logRecover("%s", opening)
	}

	// Guard removed: DetectState's flock-try is now authoritative for
	// distinguishing ghost flags from live upgrades. If we reach here, the
	// caller (DetectState → StateCrashedUpgrade, or service startup) has
	// already confirmed the flock is NOT held. A stored PID was unreliable:
	// the service survives SHA upgrades, so the PID stayed alive after the
	// upgrade completed — a ghost flag a PID check couldn't detect. The flock
	// has no such hole; STATBUS-111 removed the PID entirely.

	// Install-held flag from a crashed install. The flock was released by
	// the kernel when the install's fd closed; the on-disk JSON is pure
	// audit now. Install never writes public.upgrade, so there's no DB
	// state to reconcile — delete the stale file so tmp/ stays tidy and
	// inspecting the directory doesn't suggest something is in flight.
	// (If install ever grows DB-write semantics, add reconciliation here.)
	if holder == HolderInstall {
		logRecover("A previous install exited without finishing cleanup; clearing its leftover marker and continuing. (detail: stale install flag, invoked_by=%s)", flag.InvokedBy)
		// STATBUS-187 #10 (architect ruling, ticket comment #9):
		// ACCEPT-BOUNDED, formal. A failed Remove here re-enters this SAME
		// branch next boot by construction — every subsequent boot just
		// re-logs and re-attempts this same removal; tmp/ stays untidy but
		// nothing wedges, and no decision is taken on the stale artifact
		// in between.
		_ = os.Remove(d.flagPath())
		return nil
	}

	// A healthy rollback can crash or hit an unlink error after restoring the
	// previous version but before removing its marker and writing rolled_back.
	// That row carries an explicit cleanup-only discriminator. Intercept it before
	// phase routing: PhaseOldSbUpgrading would otherwise replay the already-
	// successful snapshot and overwrite writes made after SQL was unblocked.
	rollbackFinishPending, pendingErr := d.isRollbackFinishPending(ctx, flag.ID)
	if pendingErr != nil {
		return fmt.Errorf("check rollback finishing state for upgrade %d: %w", flag.ID, pendingErr)
	}
	if rollbackFinishPending {
		logRecover("Rollback for upgrade %d (%s) already restored the previous version; retrying stale-marker cleanup and the final database-row transition only. The snapshot will not be restored again.", flag.ID, flag.Label())
		d.finalizePendingRollbacks(ctx)
		stillPending, checkErr := d.isRollbackFinishPending(ctx, flag.ID)
		if checkErr != nil {
			return fmt.Errorf("re-check rollback finishing state for upgrade %d: %w", flag.ID, checkErr)
		}
		if stillPending {
			return fmt.Errorf("rollback for upgrade %d is restored and healthy, but stale-marker cleanup remains pending; refusing to route through snapshot recovery", flag.ID)
		}
		logRecover("Rollback finishing cleanup for upgrade %d completed without restoring the snapshot again.", flag.ID)
		return nil
	}

	// Resuming-phase flag → the planned post-swap resume began (resumeNewSb
	// re-acquired the flock and stamped Resuming) and THAT process died before
	// completing applyNewSbUpgrading (watchdog SIGABRT on a hung step, OOM, reboot,
	// kill).
	//
	// Observed state decides DIRECTION before any rollback (STATBUS-039, the
	// transactional model): a died attempt is NOT impossibility.
	//
	//   - AtTarget (binary at-or-descendant + migrations at-or-past on-disk
	//     max): forward is logically possible — resume again. Restoring an
	//     already-at-new box is forbidden: it sits past (or at) the maintenance-
	//     off commit point, where API integrators may have written data the
	//     snapshot predates (the app's upgrade guard only gates browsers).
	//     The pre-039 one-shot latch made ONE transient failure latch the
	//     NEXT recovery straight into a restore — one failure, no second
	//     chance, data loss behind it (the rune id=187 shape). Loop-bounding
	//     is not lost: every attempt is loud (progress log + journal),
	//     applyNewSbUpgrading heartbeats through its WATCHDOG ticker, and systemd
	//     StartLimit still catches a thrashing daemon. An already-at-new box that
	//     keeps failing forward stays in_progress and LOUD — it never
	//     destroys state to escape (rune sat 18 days already-at-new with zero
	//     data loss precisely because nothing rolled back).
	//
	//   - Unknown (DB unreachable): destroying state under uncertainty is
	//     forbidden — resume forward; the resume re-attempts db-up and the
	//     next pass re-checks.
	//
	//   - Behind (positively verified): forward is impossible without new
	//     code — one-shot rollback to THIS upgrade's own snapshot
	//     (flag.BackupPath, identity-keyed) to regain a runnable state to go
	//     forward from when the fix ships (§ Complete / rollback).
	if flag.Phase == PhaseNewSbUpgrading {
		// STATBUS-109 classify-then-act (doc-022 §4). The observed state decides
		// DIRECTION; an Unknown verdict is no longer a blanket forward-on-a-guess.
		// A NAMED intermittent cause (db-unreachable / commit-not-fetched) is
		// retried IN-PROCESS (never exit-spin); it clears → re-read + dispatch the
		// resolved verdict; it exhausts → data-safe rollback (STATBUS-110's
		// read-only window makes an exhausted-transient rollback lose no data). An
		// UNRECOGNISED cause STOPS for a human (the STATBUS-039 forward-on-unknown
		// conservatism is retired now that 110 makes rollback safe).
		closeAppend := func() {
			if appendLog != nil {
				appendLog.Close()
				appendLog = nil
			}
		}
		// One backoff budget per cause per recovery pass: a cause that clears
		// then re-fails is treated as exhausted (→ rollback), never re-retried.
		retried := map[UnknownCause]bool{}
		// STATBUS-109 transient-backoff proof hook (AC#5 sanctioned residue). The
		// window between the recovery boot's EnsureDBUp+connect and this verify is a
		// sub-second Go-internal span nothing external can reach; the arc stalls HERE
		// (before the first observed-state read), induces the transient condition
		// (docker pause db → the db.migration SELECT below fails → CauseDBUnreachable
		// → backoffRetry), then releases + clears it (docker unpause). No-op in
		// production (env unset). Stalls once — StallHere is a no-op once its release
		// file is gone, so the loop's later re-verifies proceed unhindered.
		inject.StallHere("stalled-before-resuming-verify")
		for {
			obsState, cause, obsReason := d.verifyUpgradeObservedStateEx(ctx, flag.CommitSHA)
			switch obsState {
			case ObservedAlreadyAtNew:
				logRecover("Upgrade %d (%s) was interrupted while finishing; the database is already at the new version — continuing forward, not rolling back. Your data is safe. (detail: new-sb-upgrading, observed-state=already-at-new, STATBUS-039 rule 1)",
					flag.ID, flag.Label())
				closeAppend()
				return d.resumeNewSb(ctx, flag)

			case ObservedCannotReachNew:
				logRecover("Upgrade %d (%s) was interrupted while finishing and the database is confirmed behind the new version; restoring this upgrade's pre-upgrade snapshot (one attempt, no retry). Data is restored to before the upgrade. (detail: new-sb-upgrading, observed-state=cannot-reach-new: %s)",
					flag.ID, flag.Label(), obsReason)
				closeAppend()
				d.recoveryRollback(ctx, flag, flag.Label(), logRelPath, fmt.Sprintf(
					"%s: the upgrade was interrupted while finishing and was rolled back to the previous version (data restored). Re-run with ./sb install once the cause is fixed. (detail: observed-state=cannot-reach-new: %s)",
					ErrResumeDied, obsReason))
				return nil

			case ObservedPositionUnreadable:
				var spec retrySpec
				switch cause {
				case CauseDBUnreachable:
					spec = d.dbUnreachableSpec()
				// STATBUS-071: NO CauseCommitNotFetched dispatch arm. The
				// classifier still NAMES the cause (verifyBinaryObservedState,
				// :2545) — but it is STRUCTURALLY UNREACHABLE here, proven by three
				// invariants: (1) the ONLY caller that uses the cause for dispatch is
				// this Phase==NewSbUpgrading block; (2) a NewSbUpgrading flag exists
				// only AFTER executeUpgrade's pre-swap fetch (the objects are local
				// by construction of the phase, :1893); (3) the recovery-boot checkout
				// gate (:1903) runs `git checkout flag.CommitSHA` and FAILS the boot on
				// a missing object, so a missing commit never reaches this verify.
				// A live path was designed for a shallow-clone edge the phase invariant
				// excludes here. Retiring the arm (architect ruling 2026-07-15) sends
				// the cause to the default human-stop below WITH THE CAUSE NAMED:
				// loud + actionable, zero retry of a structurally-impossible state. If
				// a future refactor breaks any invariant, the box stops and says why.
				default: // CauseUnrecognized (or the retired CauseCommitNotFetched) → human stop, cause named
					logRecover("Upgrade %d (%s) was interrupted while finishing and its position cannot be verified for an unretryable reason — STOPPING rather than guessing; please contact support. (detail: new-sb-upgrading, observed-state=position-unreadable, cause=%s: %s)",
						flag.ID, flag.Label(), cause, obsReason)
					closeAppend()
					// Non-nil return → the :recoverFromFlag call site exits so
					// systemd's StartLimit surfaces the human-stop (unchanged
					// backstop; now the ONLY thing that reaches it is `unknown`).
					return fmt.Errorf("recoverFromFlag: position unreadable while continuing after a crash-restart (cause=%s): %s — refusing to guess", cause, obsReason)
				}

				if retried[cause] {
					// Cleared once then the same cause recurred → treat as
					// exhausted; roll back (data-safe) rather than loop forever.
					logRecover("Upgrade %d (%s): %s recurred after a cleared backoff-retry — treating as exhausted and rolling back to the pre-upgrade snapshot (data restored). (detail: new-sb-upgrading, cause=%s)",
						flag.ID, flag.Label(), spec.name, cause)
					closeAppend()
					d.recoveryRollback(ctx, flag, flag.Label(), logRelPath, fmt.Sprintf(
						"%s: %s recurred after a cleared backoff-retry and was rolled back to the previous version (data restored). Re-run with ./sb install once the cause is fixed. (detail: new-sb-upgrading, cause=%s)",
						ErrResumeDied, spec.name, cause))
					return nil
				}
				retried[cause] = true
				logRecover("Upgrade %d (%s) was interrupted while finishing; its position is temporarily unverifiable (%s) — retrying in-process before deciding, not exiting. Your data is safe. (detail: new-sb-upgrading, cause=%s)",
					flag.ID, flag.Label(), obsReason, cause)
				if err := d.backoffRetry(ctx, spec); err != nil {
					// Budget exhausted (or ctx cancelled) → data-safe rollback (110).
					logRecover("Upgrade %d (%s): %s did not clear within the retry budget (%v) — rolling back to the pre-upgrade snapshot (data-safe via the read-only window). (detail: new-sb-upgrading, cause=%s)",
						flag.ID, flag.Label(), spec.name, err, cause)
					closeAppend()
					d.recoveryRollback(ctx, flag, flag.Label(), logRelPath, fmt.Sprintf(
						"%s: %s did not clear within the retry budget and was rolled back to the previous version (data restored). Re-run with ./sb install once the cause is fixed. (detail: new-sb-upgrading, cause=%s, %v)",
						ErrResumeDied, spec.name, cause, err))
					return nil
				}
				// Cleared → loop re-reads the observed state and dispatches the resolved verdict.

			default:
				// ObservedState is a closed tri-state; a 4th value is state-machine
				// drift — fail loud rather than spin.
				closeAppend()
				return fmt.Errorf("recoverFromFlag: unexpected observed-state value %d for upgrade %d — refusing to act", obsState, flag.ID)
			}
		}
	}

	// Post-swap restart (exit 42 after replaceBinaryOnDisk): this is NOT a
	// crash. The prior process image intentionally handed off to the new
	// binary so that migrate + health-check + post-swap steps run against
	// the freshly-compiled Go. Resume the pipeline from config-generate
	// onward rather than marking the row completed — the upgrade isn't
	// actually done yet.
	if flag.Phase == PhaseNewSbSwapped {
		logRecover("New binary continuing upgrade %d to %s (pid %d)",
			flag.ID, flag.Label(), os.Getpid())
		if appendLog != nil {
			appendLog.Close()
			appendLog = nil
		}
		return d.resumeNewSb(ctx, flag)
	}

	// PreSwap-phase flag → roll back, NEVER self-heal (engineer audit task
	// #3 Q3 + scenario 2-preswap-backup-kill RED proof from run 26607271739).
	//
	// A PreSwap-phase flag means the upgrade was killed BEFORE the binary
	// swap commit boundary (replaceBinaryOnDisk had not yet run when the
	// process died, or it was about to but never wrote Phase=post_swap).
	// Filesystem state at this point is:
	//   - pre-upgrade-syncing/ exists, mid-rsync, INCOMPLETE.
	//   - No pre-upgrade-active/ from this upgrade attempt.
	//   - ./sb still at the OLD binary; no ./sb.old.
	//   - DB volume UNCHANGED (preswap-backup is rsync OUT, not IN).
	//   - public.upgrade row still in_progress.
	// The right move is to roll back: mark the row rolled_back, remove the
	// flag, restart services at the CURRENT (unchanged) binary, leave the
	// DB alone. recoveryRollback → rollback → restoreDatabase is data-safe
	// here BY IDENTITY (STATBUS-039/-031): a PreSwap flag carries an empty
	// BackupPath (updateFlagNewSbSwapped — which stamps it — never ran), and
	// the identity-keyed restoreDatabase refuses to touch the volume when
	// no snapshot was recorded. The pre-039 recency selector
	// (pickLatestBackup) only happened to be safe on legacy-free boxes; on
	// a box still carrying legacy pre-upgrade-<stamp> dirs it would have
	// restored ANOTHER upgrade's months-old backup over the untouched live
	// volume — the exact silent-loss path the identity key closes.
	// restoreBinary is also a no-op because ./sb.old does not exist
	// (replaceBinaryOnDisk never created it) — see restoreBinary's
	// ENOENT branch.
	//
	// Why this guard exists: the success branch below (line 765+) uses
	// `headSHA == flag.CommitSHA` as the discriminator for self-heal. That
	// invariant is sound for POST-swap recovery (where the binary swap +
	// migrations + healthcheck genuinely landed before the crash), but for
	// a PreSwap-phase flag, headSHA-matches-target says NOTHING about
	// whether the upgrade reached the commit boundary — the harness has
	// HEAD == target by construction (its scenarios register+schedule
	// HEAD against a binary that is also HEAD via upload_sb_to_vm), and real customers can also have HEAD == target
	// after `git checkout` step 6 but before replaceBinaryOnDisk step 6b
	// (the comment at line 773-778 already documents this window for
	// PostSwap; it applies symmetrically here for PreSwap). Without this
	// guard, scenario 2-preswap-backup-kill's RED-confirmed PreSwap kill would route into the
	// self-heal UPDATE and mark `state='completed'` for an upgrade that
	// was killed before any commit happened.
	if flag.Phase == PhaseOldSbUpgrading {
		reason := preSwapRecoveryReason(flag)
		if flag.OriginalError != "" {
			// STATBUS-338, Norway rc.02: the prior process returned a concrete git
			// error, then died in nil-unsafe rollback. The flag now carries that
			// cause, so recovery reports it and its retryable class instead of
			// manufacturing INSTALL_PRECONDITION_FAILED/do-not-reschedule advice.
			logRecover("Upgrade %d (%s) stopped before it changed anything; rolling back the unchanged attempt. The database was not modified, so nothing needs restoring. Original failure: %s",
				flag.ID, flag.Label(), flag.OriginalError)
		} else {
			logRecover("Upgrade %d (%s) was interrupted before it changed anything; rolling back to the previous version. The database was not modified, so nothing needs restoring. (detail: before booting the new binary, no snapshot recorded)",
				flag.ID, flag.Label())
		}
		if appendLog != nil {
			appendLog.Close()
			appendLog = nil
		}
		// flag.BackupPath is empty by construction at PreSwap (stamped only
		// by updateFlagNewSbSwapped) — restoreDatabase refuses on empty.
		d.recoveryRollback(ctx, flag, flag.Label(), logRelPath, reason)
		return nil
	}

	// Every flag phase the codebase writes is handled above: install-held,
	// "" (PreSwap — PhaseOldSbUpgrading is the empty string, so it also covers
	// legacy flags), new-sb-swapped, and new-sb-upgrading (legacy wire bytes
	// post_swap/resuming normalize to these at the UnmarshalJSON chokepoint before
	// this point, so they route through the same branches). The headSHA-reconcile +
	// forward-recovery + self-heal segment that used to follow here was
	// UNREACHABLE for every producible flag — the PreSwap guard intercepted
	// every empty-phase flag first (verified 2026-06-09 and again 2026-06-12,
	// STATBUS-039) — and its observed-state routing now lives in the LIVE
	// branches above (Resuming) and in resumeNewSb/newSbUpgradingFailure.
	// Removed per the clean-break discipline rather than kept as plausible-
	// looking cover.
	//
	// A phase value outside the produced set is state-machine drift (a
	// future writer added a phase without teaching recovery about it) —
	// fail loud, touch nothing.
	logRecover("FLAG_PHASE_UNKNOWN: upgrade %d (%s) is in an unrecognized state %q — stopping rather than guessing; please contact support. (detail: investigate %s)",
		flag.ID, flag.Label(), flag.Phase, d.flagPath())
	return fmt.Errorf("recoverFromFlag: unknown flag phase %q for upgrade %d — refusing to act", flag.Phase, flag.ID)
}

// (shortSHA helper deleted in rc.63; use commit.go's commitShort for
// typed CommitSHA values and ShortForDisplay for untyped log strings.)

// markImagesFailed transitions a discovery row to
// docker_images_status='failed' with an actionable error string. Called
// from verifyArtifacts on two paths: (a) gh reported the CI workflow as
// failed; (b) gh is unavailable AND the manifest-timeout grace window
// elapsed. Either UPDATE that fails escalates to fail-fast under
// CI_FAILURE_DETECTED_TRANSITIONS_ROW — admin UI spinning on a failed CI
// is the exact bug this whole invariant was written to prevent.
//
// No bundle is emitted — no upgrade is in progress; the service log
// (journald) already has the narrative. See plan C-head "End-state
// contract".
func (d *Service) markImagesFailed(ctx context.Context, id int, sha, reason string) {
	// Atomic WHERE-clause guard.
	//
	// Terminal lifecycle states (completed, failed, rolled_back, skipped,
	// dismissed, superseded) reject docker_images_status writes via
	// chk_upgrade_state_attributes. Including a state filter in the
	// same UPDATE makes the check atomic — the row is either
	// transitionable or silently skipped. Pre-rc.63 this site
	// erroneously fired CI_FAILURE_DETECTED_TRANSITIONS_ROW on terminal
	// rows (observed on statbus_dev rc.62).
	//
	// The `error` column is written alongside docker_images_status.
	// Rc.63's chk_upgrade_state_attributes relaxation (migration
	// 20260424160235) permits `error` on pre-terminal states
	// (available/scheduled/in_progress) — so the CI failure reason is
	// durably attached to the row instead of being log-only. Admin UI
	// renders `error` in the upgrade list.
	result, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade
		   SET docker_images_status = 'failed',
		       error = $1
		 WHERE id = $2
		   AND docker_images_status = 'building'
		   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded')`,
		reason, id)
	if err != nil {
		// SQLSTATE 23514 on chk_upgrade_state_attributes: the row is in a
		// pre-terminal state with timestamp columns inconsistent with that
		// state — historical contamination from pre-rc.63 lifecycle bugs.
		// Migration 20260425163029_dismiss_corrupt_upgrade_lifecycle_rows
		// sweeps every such row to state='dismissed'; this branch is the
		// belt-and-braces guard against any future bypass path that
		// re-creates the shape (e.g., manual UPDATE, recovery tooling).
		//
		// The row is NOT in the spinning admin-UI shape that
		// CI_FAILURE_DETECTED_TRANSITIONS_ROW guards against — the admin
		// UI surfaces it via the `error` column on the upgrade row, not
		// through `docker_images_status='building'` alone. Treat as
		// silent-skip (parallel to the 0-rows-affected branch below); do
		// NOT fire INVARIANT and do NOT increment the attempt tracker
		// (this isn't "service is stuck retrying", it's "this specific
		// row needs the data migration to run").
		var pgerr *pgconn.PgError
		if errors.As(err, &pgerr) && pgerr.Code == "23514" && pgerr.ConstraintName == "chk_upgrade_state_attributes" {
			var probeState, probeImgStatus string
			_ = d.queryConn.QueryRow(ctx,
				"SELECT state::text, docker_images_status::text FROM public.upgrade WHERE id = $1",
				id).Scan(&probeState, &probeImgStatus)
			log.Printf("verifyArtifacts: skipping docker_images_status='failed' UPDATE for commit %s: row %d has corrupted state/timestamp combination (state=%s, docker_images_status=%s, sqlstate=23514, constraint=chk_upgrade_state_attributes; reason would have been %q). Migration 20260425163029_dismiss_corrupt_upgrade_lifecycle_rows repairs these rows.",
				ShortForDisplay(sha), id, probeState, probeImgStatus, reason)
			tracker := NewAttemptTracker(d.projDir, 3)
			decision := fmt.Sprintf("markImagesFailed/%s", sha[:12])
			tracker.Clear(decision)
			return
		}
		// Real DB error (connection dead, unexpected constraint
		// violation). Escalate — but first check if we're in a retry loop
		// (item #5 rc.64: attempt tracker for SERVICE_STUCK_RETRY_LOOP).
		tracker := NewAttemptTracker(d.projDir, 3)
		decision := fmt.Sprintf("markImagesFailed/%s", sha[:12])
		var errCode string
		if pgerr := ((*pgconn.PgError)(nil)); errors.As(err, &pgerr) {
			errCode = pgerr.Code
		}
		if abandon, n := tracker.Record(decision, errCode, err.Error()); abandon {
			// Fire SERVICE_STUCK_RETRY_LOOP exactly once to avoid audit-channel spam.
			// After the first invariant emission, subsequent ticks are no-ops.
			if !d.stuckLoopFired {
				d.markTerminal("SERVICE_STUCK_RETRY_LOOP",
					fmt.Sprintf("decision=%s failed %d consecutive times with sqlstate=%s (last: %v); "+
						"operator must investigate and clear manually", decision, n, errCode, err))
				d.stuckLoopFired = true
			}
			return
		}

		fmt.Fprintf(os.Stderr,
			"INVARIANT CI_FAILURE_DETECTED_TRANSITIONS_ROW violated: UPDATE docker_images_status=failed failed for sha=%s: %v (service.go:%d, pid=%d)\n",
			sha, err, thisLine(), os.Getpid())
		d.markTerminal("CI_FAILURE_DETECTED_TRANSITIONS_ROW",
			fmt.Sprintf("sha=%s; UPDATE err=%v", sha, err))
		return
	}
	if result.RowsAffected() == 0 {
		// The WHERE clause filtered out the row. Either docker_images_status
		// is no longer 'building' (already transitioned by another path),
		// or state is terminal. Not an invariant breach: the row is not
		// stuck in the spinning admin-UI shape that the invariant guards
		// against.
		var probeState, probeImgStatus string
		_ = d.queryConn.QueryRow(ctx,
			"SELECT state::text, docker_images_status::text FROM public.upgrade WHERE id = $1",
			id).Scan(&probeState, &probeImgStatus)
		log.Printf("verifyArtifacts: skipping docker_images_status='failed' UPDATE for commit %s: row %d is already in terminal state (state=%s, docker_images_status=%s; reason would have been %q)",
			ShortForDisplay(sha), id, probeState, probeImgStatus, reason)
		// Clear attempt counter on the silent-skip path (row already in terminal state)
		tracker := NewAttemptTracker(d.projDir, 3)
		decision := fmt.Sprintf("markImagesFailed/%s", sha[:12])
		tracker.Clear(decision)
		return
	}
	// Clear attempt counter on success
	tracker := NewAttemptTracker(d.projDir, 3)
	decision := fmt.Sprintf("markImagesFailed/%s", sha[:12])
	tracker.Clear(decision)
	log.Printf("CI images marked failed for commit %s: %s", ShortForDisplay(sha), reason)
}

// verifyArtifacts runs the declarative artifact readiness check for every
// public.upgrade row that hasn't already been completed, rolled back, or
// skipped. Two independent levels are tracked by separate columns so the
// admin UI can tell an operator exactly what it is waiting for:
//
//	docker_images_status           — the four Docker images (db/app/worker/proxy)
//	                          exist at the runtime VERSION tag
//	                          (git-describe output). Verified via
//	                          `docker manifest inspect` — a registry-only
//	                          query that doesn't pull. Three states:
//	                          building (CI in progress), ready (verified),
//	                          failed (CI workflow failed).
//	release_builds_status          — for tagged releases only: the GitHub Release
//	                          + `sb` binary + manifest.json exist. Set
//	                          by the discovery loop above via FetchManifest.
//	                          For commits this defaults to ready (edge
//	                          channel doesn't use release artifacts).
//	                          Three states: building, ready, failed.
//
// manifestTimeout is the shared "give up waiting for CI" grace window —
// package-level (not local to verifyArtifacts) so STATBUS-046 slice 3c's
// image-claim gate (image_claim_gate.go, evaluateImageClaimGate) claims-past-
// grace on EXACTLY the same duration verifyArtifacts uses to mark a row
// 'failed', by construction rather than by two independently-tuned magic
// numbers. Used as the fallback grace when `gh` is absent or errors: once a
// discovery row has been in docker_images_status='building' longer than this
// AND the registry manifests are still missing, verifyArtifacts marks the row
// 'failed' so the admin UI stops spinning (production hosts typically have no
// `gh`, so this ensures CI_FAILURE_DETECTED_TRANSITIONS_ROW still holds
// without it) — and the claim gate stops waiting and claims anyway, loud.
const manifestTimeout = 20 * time.Minute

// Scoped to the 30 most recent pending rows to bound per-cycle cost.
func (d *Service) verifyArtifacts(ctx context.Context) {
	const registryPrefix = "ghcr.io/statisticsnorway/statbus-"
	services := []string{"db", "app", "worker", "proxy"}

	rows, err := d.queryConn.Query(ctx, `
		SELECT id, commit_sha, release_status::text, docker_images_status::text, release_builds_status::text, commit_version, discovered_at
		  FROM public.upgrade
		 WHERE docker_images_status != 'ready'
		   AND state IN ('available', 'scheduled', 'in_progress', 'failed')
		 ORDER BY committed_at DESC
		 LIMIT 30`)
	if err != nil {
		return
	}

	type pendingRow struct {
		id                  int
		sha                 string
		releaseStatus       string
		dockerImagesStatus  string
		releaseBuildsStatus string
		version             *string // NULL for rows predating the version column
		discoveredAt        time.Time
	}
	var pending []pendingRow
	for rows.Next() {
		var r pendingRow
		if err := rows.Scan(&r.id, &r.sha, &r.releaseStatus, &r.dockerImagesStatus, &r.releaseBuildsStatus, &r.version, &r.discoveredAt); err == nil {
			pending = append(pending, r)
		}
	}
	rows.Close()

	for _, r := range pending {
		// STATBUS-195: this loop runs on the MAIN goroutine (the discovery tick), and
		// each cold candidate costs up to four `docker manifest inspect` network calls
		// (~20s observed per candidate). Eight cold candidates exceeded WatchdogSec=120
		// with no WATCHDOG=1 emitted, and systemd killed a demonstrably-progressing
		// daemon (run 29743621767 — the false-kill class of the boot-migrate precedent
		// above). Each completed candidate IS genuine progress, so feed the watchdog
		// per candidate. Hang detection is preserved by construction: a verify stuck
		// on ONE candidate emits nothing further and still starves the watchdog —
		// which is then a correct kill.
		emitHeartbeat(d.projDir)
		if r.dockerImagesStatus == "failed" {
			continue // Already marked as failed — don't re-check
		}
		dockerImagesReady := false
		{
			// Rc.63: images are tagged by commit_short (8-char) only, so
			// the manifest-inspect reference is deterministic from the
			// row's commit_sha — no more dependence on describe output
			// drift, and no special-case for rows predating the column.
			tag := ShortForDisplay(r.sha)
			allPresent := true
			for _, svc := range services {
				ref := fmt.Sprintf("%s%s:%s", registryPrefix, svc, tag)
				if _, mErr := runCommandOutput(d.projDir, "docker", "manifest", "inspect", ref); mErr != nil {
					allPresent = false
					break
				}
			}
			if allPresent {
				// STATBUS-187 #12 (architect ruling, ticket comment #9):
				// ACCEPT-DOCUMENTED — self-correcting by construction, not a
				// behavior-change candidate: verifyArtifacts runs on every
				// discovery cycle (periodic poll), so a failed UPDATE here
				// just gets retried next cycle; no decision reads the
				// outcome in between.
				_ = d.execObserved(ctx, "verifyArtifacts: mark docker images ready",
					"UPDATE public.upgrade SET docker_images_status = 'ready' WHERE id = $1 AND docker_images_status != 'ready'",
					r.id)
				fmt.Printf("Images verified for commit %s (tag=%s)\n", ShortForDisplay(r.sha), tag)
				dockerImagesReady = true

				// Auto-supersede intermediate commit rows that are ancestors of
				// this commit but will never have CI images of their own.
				// images.yaml triggers once per push and only tags images for
				// the push tip (github.sha). Intermediate commits from the same
				// push have docker_images_status != 'ready' permanently, keeping
				// a stale "Images building..." badge in the UI.
				//
				// Guards:
				//   release_status='commit' — never touch tagged release rows.
				//   docker_images_status != 'ready' — don't supersede a sibling
				//     that just had its own images verified earlier in this cycle.
				for _, anc := range pending {
					if anc.sha == r.sha || anc.releaseStatus != "commit" {
						continue
					}
					if _, isAncErr := runCommandOutput(d.projDir, "git", "merge-base", "--is-ancestor", anc.sha, r.sha); isAncErr != nil {
						continue // exit 1 = not an ancestor, or git error — skip either way
					}
					res, dbErr := d.queryConn.Exec(ctx,
						`UPDATE public.upgrade
						    SET state = 'superseded', superseded_at = now()
						  WHERE id = $1
						    AND state = 'available'
						    AND release_status = 'commit'
						    AND superseded_at IS NULL
						    AND docker_images_status != 'ready'`,
						anc.id)
					if dbErr == nil && res.RowsAffected() > 0 {
						fmt.Printf("Superseded intermediate commit %s (no CI images; ancestor of %s)\n", ShortForDisplay(anc.sha), ShortForDisplay(r.sha))
					}
				}
			} else {
				// Images not in registry per the docker-manifest-inspect loop
				// above. STATBUS-302: this used to ask `gh api` for the
				// images.yaml workflow's conclusion — gh is not installed on
				// production boxes (ops/setup-ubuntu-lts-24.sh never installs
				// it), so this call ALWAYS failed there, and the "gh
				// unavailable" branch below then ASSERTED build failure from a
				// probe that never actually observed one: "CI images absent
				// ...; gh probe err=exec: \"gh\": executable file not found in
				// $PATH" — the King's screenshots (demo.statbus.org and a
				// second slot). A failure to observe is not evidence about the
				// observed (architect ruling, ticket comment #1).
				//
				// Replaced with the anonymous ghcr.io manifest-HEAD probe
				// (verified tokenless-for-public-images, ruling comment #1's
				// curl transcript): a clean 404 CONFIRMS what
				// docker-manifest-inspect already found moments ago (still
				// absent) and lets the existing elapsed-time threshold below
				// decide when "still building" has run long enough to call it
				// failed — the "not built" half of the ruling's three states.
				// Any OTHER probe outcome (anonymous-token fetch failure,
				// network error, an unexpected HTTP status, or a stray 200
				// meaning the images landed since the loop above ran) is a
				// PROBE failure, not a build verdict: fails closed (no
				// failure is ever recorded from a check that could not
				// complete) and reports honest (logged as "could not
				// determine", never folded into "images failed").
				ghcrStatus, ghcrErr := probeAllImagesGhcr(ghcrRegistryBase, owner, services, tag)
				switch ghcrStatus {
				case ghcrAbsent:
					// if the row has been waiting in 'building' longer than
					// manifestTimeout and ghcr.io confirms no manifests, CI
					// must have failed (or been skipped) — mark failed.
					age := time.Since(r.discoveredAt)
					if age > manifestTimeout {
						d.markImagesFailed(ctx, r.id, r.sha, fmt.Sprintf(
							"no CI images published for commit %s after %s (ghcr.io confirms absent)", ShortForDisplay(r.sha), manifestTimeout))
					}
				case ghcrIndeterminate:
					log.Printf(
						"verifyArtifacts: could not determine build status for %s (ghcr probe: %v) — leaving docker_images_status unchanged",
						ShortForDisplay(r.sha), ghcrErr)
				}
				// ghcrPresent: a race against the docker-manifest-inspect loop
				// above — do nothing here; the next discovery cycle's
				// docker-manifest-inspect marks it ready normally.
			}
		}

		_ = dockerImagesReady // value recorded via the UPDATE above when applicable
	}
}

// RecoverFromFlag is the exported form of recoverFromFlag — the
// reconciliation step that runs at service startup and is also called by
// ./sb install's crashed-upgrade path (StateCrashedUpgrade) before
// re-detecting and re-dispatching.
//
// The caller MUST call LoadConfigAndConnect first so queryConn is live,
// and Close after to release connections.
//
// Returns nil for category-1 (success) and category-2 (auto-rolled-back)
// outcomes; returns a non-nil error for category-3 divergences per the
// recovery trifecta — the caller (./sb install) surfaces these to the
// operator instead of silently continuing.
func (d *Service) RecoverFromFlag(ctx context.Context) error {
	return d.recoverFromFlag(ctx)
}

// LoadConfigAndConnect performs the startup steps needed before
// RecoverFromFlag, ExecuteUpgradeInline, or any other one-shot that
// reads/writes public.upgrade: load .env config, load trusted signers
// (so verifyCommitSignature enforces signatures), acquire the query /
// listen conns.
//
// Does NOT acquire the advisory lock. One-shot recovery is meant to run
// when the service is stopped — by definition there is no running service
// to conflict with. If the service IS running, it has already done (or
// will do) the recovery itself; calling recover as a one-shot is then
// redundant but safe (the flag file is gone, RecoverFromFlag returns).
func (d *Service) LoadConfigAndConnect(ctx context.Context) error {
	if err := d.loadConfig(); err != nil {
		return fmt.Errorf("load config: %w", err)
	}
	// Trusted signers must be loaded before executeUpgrade runs, or
	// verifyCommitSignature silently no-ops (service.go:1265) — a security
	// regression on the inline-upgrade path. Run() calls loadTrustedSigners
	// directly; this mirrors that for one-shot callers.
	if err := d.loadTrustedSigners(); err != nil {
		return fmt.Errorf("load trusted signers: %w", err)
	}
	return d.connect(ctx)
}

// Close releases the query/listen connections acquired by LoadConfigAndConnect.
// Safe to call when connections were never opened.
func (d *Service) Close() {
	if d.queryConn != nil {
		_ = d.queryConn.Close(context.Background()) // best-effort; process/caller is tearing down regardless
	}
	if d.listenConn != nil {
		_ = d.listenConn.Close(context.Background()) // best-effort; process/caller is tearing down regardless
	}
}

// ExecuteUpgradeInline runs executeUpgrade from a one-shot caller (./sb install
// inline upgrade dispatch). Caller is responsible for:
//   - opening DB connections via LoadConfigAndConnect,
//   - ensuring the public.upgrade row at `id` exists and is in 'scheduled'
//     state with started_at IS NULL (the claim UPDATE below enforces this).
//
// This function does NOT acquire the install flag-lock: executeUpgrade writes
// its own HolderService flag internally before any destructive step
// (service.go:writeUpgradeFlag), which serialises against concurrent actors
// via the kernel flock.
//
// Concurrency: the claim UPDATE mirrors executeScheduled's claim with the
// same state guard. If a racing upgrade service claimed the row first,
// RowsAffected() == 0 and we bail cleanly so the operator can re-run once
// the other path finishes.
//
// invokedBy / trigger are hardcoded to distinguish operator-driven inline
// upgrades from scheduler-driven service runs in post-mortem queries.
func (d *Service) ExecuteUpgradeInline(ctx context.Context, id int, commitSHA, _ string) error {
	// STATBUS-046 slice 3c — images-ready CLAIM GATE (evaluateImageClaimGate,
	// image_claim_gate.go), identical to executeScheduled's gate. Read-only
	// pre-claim probe of the row's own state — a caller-supplied `id` is
	// trusted to already be 'scheduled' (per this function's contract), so a
	// row that vanished/changed between this SELECT and the claim UPDATE
	// below is caught by the claim's own ErrNoRows branch, unaffected by
	// this gate.
	var scheduledAt time.Time
	var dockerImagesStatus string
	if gerr := d.queryConn.QueryRow(ctx,
		"SELECT scheduled_at, docker_images_status::text FROM public.upgrade WHERE id = $1",
		id).Scan(&scheduledAt, &dockerImagesStatus); gerr == nil {
		switch evaluateImageClaimGate(dockerImagesStatus, scheduledAt, time.Now(), manifestTimeout) {
		case imageClaimFailed:
			return fmt.Errorf("upgrade row %d: images failed to publish (CI failed) — re-push or ./sb upgrade register again", id)
		case imageClaimWait:
			fmt.Printf("Upgrade row %d: scheduled, images still building — waiting for publication.\n", id)
			d.verifyArtifacts(ctx) // one immediate re-probe, same as executeScheduled's gate
			return fmt.Errorf("upgrade row %d: images not yet verified ready (still building) — re-run ./sb install shortly", id)
		case imageClaimPastGrace:
			fmt.Printf("Upgrade row %d: images unverified past %s — proceeding; the warm-up pull will fail actionably if truly absent.\n", id, manifestTimeout)
		case imageClaimReady:
			// Claim as today — no gate interference on the common path.
		}
	}
	// gerr != nil (row vanished, or a pre-046 DB during the migration's own
	// deferral window — mirrors resumeNewSb's fail-open posture on a read
	// error): fall through to the claim UPDATE unchanged; its own ErrNoRows /
	// state-guard branches are the correct diagnostic for a genuinely-absent
	// or already-claimed row.

	// STATBUS-077: claim records only the display version (from_commit_version).
	// The recovery restore target is the pinned `pre-upgrade` branch (single source);
	// the from_commit_sha column was removed.
	// STATBUS-092: claim + read (commit_tags, recreate) atomically via RETURNING,
	// so the flag captures the full commit identity AND the durable recreate
	// intent in one round-trip. ErrNoRows = the row is no longer 'scheduled'
	// (another actor claimed it first).
	// STATBUS-159: claimScheduledUpgrade is the shared claim path — it displaces
	// any standing park before claiming, so a fix release proceeds while a park
	// stands. commit_tags comes from the claim's RETURNING here.
	claim, claimErr := d.claimScheduledUpgrade(ctx, id)
	if errors.Is(claimErr, pgx.ErrNoRows) {
		return fmt.Errorf("upgrade row %d no longer in 'scheduled' state (another actor claimed it first); re-run ./sb install after it finishes", id)
	}
	if claimErr != nil {
		d.markPgInvariantTerminal(claimErr, "service.go:ExecuteUpgradeInline:claim")
		return fmt.Errorf("claim scheduled upgrade row %d: %w", id, claimErr)
	}
	displayName := renderDisplayName(CommitSHA(claim.Snapshot.CommitSHA), claim.CommitTags)
	return d.executeUpgrade(ctx, claim.Snapshot, displayName, claim.CommitTags, "operator:install", "install-cli", claim.Recreate)
}

// Label taxonomy used by logUpgradeRow() to tag terminal-state transitions in
// journalctl output. Each label corresponds to exactly one call path; grep the
// label string to jump to its site. Add new labels here when adding new terminal
// transition sites.
//
// Search the journal: journalctl -u statbus-upgrade | grep 'upgrade row \[<label>\]'
//
//	LabelCompletedNormal         — executeUpgrade normal path: health check passed, upgrade finished cleanly
//	LabelCompletedSelfHeal       — recoverFromFlag: prior binary died mid-upgrade; new binary found app
//	                               healthy and self-healed the stuck in_progress row to completed
//	LabelCompletedFromInProgress — completeInProgressUpgrade: upgrade left in_progress by a prior run;
//	                               completion health check passed, row finalised to completed
//	LabelCompletedInstall        — completeInstallUpgradeRow: `./sb install` recorded the running
//	                               version as a completed row (the install-side sibling of the
//	                               recovery / executeUpgrade completion paths; see the two-row model
//	                               in doc/upgrade-timeline.md)
//	LabelFailedRollbackPendingFinish — rollback restored the prior version, but the lock
//	                                   and final rolled_back transition are still pending
//	LabelRolledBackNormal        — rollback normal path: upgrade failed, git restore succeeded,
//	                               prior version restarted cleanly and the lock released
//	LabelRolledBackFinishRecovery — startup/heartbeat completed the final failed -> rolled_back
//	                                transition after a crash in the post-lock-release window
//	LabelFailedAbort             — rollback ABORT: git restore itself failed; row is failed
//	                               (degraded — services down, maintenance on, manual recovery)
//	LabelFailedAbortServicesLive — rollback ABORT (STATBUS-187): the pre-restore `docker compose
//	                               stop` did not actually stop every service; refused BEFORE any
//	                               restore step rather than risk a torn-restore under a live postgres
//	                               (degraded — maintenance on, manual recovery)
//	LabelFailedRollbackIncomplete — rollback normal path BUT a restore step failed (DB snapshot
//	                               restore or services-up): row is failed (degraded), not rolled_back
//	LabelRolledBackCrashRecovery — recoverFromFlag: prior binary crashed mid-upgrade; new binary
//	                               could not self-heal and triggered a rollback to recover
//	LabelFailed                  — two sites: (1) completeInProgressUpgrade health check failed,
//	                               (2) failUpgrade explicit failure during executeUpgrade
const (
	LabelCompletedNormal             = "completed-normal"
	LabelCompletedSelfHeal           = "completed-self-heal"
	LabelCompletedFromInProgress     = "completed-from-in-progress"
	LabelCompletedInstall            = "completed-install"
	LabelFailedRollbackPendingFinish = "failed-rollback-pending-finish"
	LabelRolledBackNormal            = "rolled-back-normal"
	LabelRolledBackFinishRecovery    = "rolled-back-finish-recovery"
	LabelFailedAbort                 = "failed-abort"
	LabelFailedAbortServicesLive     = "failed-abort-services-live"
	LabelFailedRollbackIncomplete    = "failed-rollback-incomplete"
	LabelRolledBackCrashRecovery     = "rolled-back-crash-recovery"
	LabelFailed                      = "failed"
)

// upgradeRowReturning is the RETURNING clause appended to every terminal-state
// UPDATE. Returns the full row as JSON for greppable state-transition logging.
const upgradeRowReturning = ` RETURNING to_jsonb(upgrade.*)`

// logUpgradeRow prints the full upgrade row snapshot at a terminal state
// transition. Uses raw %s (never %q) so the JSON is greppable:
//
//	journalctl -u statbus-upgrade | grep '"state":"completed"'
func logUpgradeRow(label string, row string) {
	fmt.Printf("upgrade row [%s] %s\n", label, row)
}

// Stable error codes written as a prefix to public.upgrade.error.
// Operator-searchable, translation-friendly, machine-filterable.
// Sub-coded where the distinction drives a different recovery action.
// Always use codedError() or fmt.Sprintf("%s: ...", ErrX, ...) — never
// embed the code as a raw string literal in the error message.
//
//	ErrMigrationFailed       — ./sb migrate up or ./dev.sh recreate-database failed
//	ErrBackupFailed          — pre-upgrade database backup failed
//	ErrDockerUpFailed        — docker compose pull / up / start failed
//	ErrHealthcheckRESTDown   — PostgREST health probe failed
//	ErrHealthcheckAppDown    — Next.js application health probe failed
//	ErrHealthcheckDBDown     — PostgreSQL health probe / reconnect failed
//	ErrRollbackGitCorrupt    — rollback git-restore failed: other / corrupt (support-only)
//	ErrRollbackDBRestore     — rollback database volume restore failed
//	ErrRollbackServicesUp    — rollback docker compose up failed after DB restore
//	ErrRollbackServicesNotStopped — pre-restore `docker compose stop` did not actually stop every service (STATBUS-187); refused before any restore step
//	ErrRollbackBinaryCorrupt — rollback could not restore ./sb from ./sb.old (operator must mv manually)
//	ErrBinaryReplaceFailed   — mid-flow binary replacement (download/verify/swap) failed before migrations
//	ErrBinaryBuildFailed     — mid-flow sb image procurement failed (pull miss + in-container build fallback failed; edge channel, no release artifact)
//	ErrInstallFixupFailed    — post-upgrade ./sb install fixup step failed (non-fatal)
//	ErrResumeDied            — post-swap resume began (flag Phase=resuming) then the process died → roll back, no retry
const (
	ErrMigrationFailed     = "MIGRATION_FAILED"
	ErrBackupFailed        = "BACKUP_FAILED"
	ErrDockerUpFailed      = "DOCKER_UP_FAILED"
	ErrHealthcheckRESTDown = "HEALTHCHECK_REST_DOWN"
	ErrHealthcheckAppDown  = "HEALTHCHECK_APP_DOWN"
	ErrHealthcheckDBDown   = "HEALTHCHECK_DB_DOWN"
	ErrRollbackGitCorrupt  = "ROLLBACK_FAILED_GIT_CORRUPT"
	ErrRollbackDBRestore   = "ROLLBACK_FAILED_DB_RESTORE"
	// ErrUpgradeStoppedUnchanged (STATBUS-240, King-approved name and text) —
	// the upgrade declined to proceed and left the system exactly as it found
	// it. It BREAKS THE NAMING PATTERN ON PURPOSE: every other class here names
	// a failure of something that was attempted, and this one must not, because
	// nothing failed in that sense. If it read UPGRADE_FAILED_PRESWAP it would
	// sit in this list looking like its neighbours and an operator scanning for
	// damage would assume there is some. The name reads differently because the
	// operator's next action is different, and the name is the one surface
	// nobody can skip.
	//
	// "NOTHING_CHANGED" rather than "PRESWAP": PreSwap is our word for our
	// machinery. It names the internal phase boundary correctly and tells the
	// operator nothing they can act on; this class is read by people who have
	// never heard of a swap.
	ErrUpgradeStoppedUnchanged    = "UPGRADE_STOPPED_NOTHING_CHANGED"
	ErrRollbackServicesUp         = "ROLLBACK_FAILED_SERVICES_UP"
	ErrRollbackServicesNotStopped = "ROLLBACK_FAILED_SERVICES_NOT_STOPPED"
	ErrRollbackBinaryCorrupt      = "ROLLBACK_FAILED_BINARY_CORRUPT"
	ErrBinaryReplaceFailed        = "BINARY_REPLACE_FAILED"
	ErrBinaryBuildFailed          = "BINARY_BUILD_FAILED"
	ErrInstallFixupFailed         = "INSTALL_FIXUP_FAILED"
	// ErrGitFetchRetryable names a pre-swap object-fetch failure whose bounded
	// retries exhausted. The target tree, services, and database are unchanged,
	// so retrying the same candidate is legitimate. Norway rc.02 was wrongly
	// relabelled INSTALL_PRECONDITION_FAILED with do-not-reschedule advice.
	ErrGitFetchRetryable = "GIT_FETCH_FAILED_RETRYABLE"
	// ErrInstallPreconditionFailed — an installable precondition was not
	// met at recovery time (binary SHA mismatch, migration gap, etc.).
	// Used by completeInProgressUpgrade's observed-state check (task #49)
	// to mark rows FAILED rather than silently completing them.
	ErrInstallPreconditionFailed = "INSTALL_PRECONDITION_FAILED"
	// ErrResumeDied — the planned post-swap resume began (flag Phase=resuming),
	// the process died before completing (watchdog SIGABRT on a hung step,
	// OOM, reboot, kill), AND observed state verified the system confirmed
	// behind the target (STATBUS-039) — recoverFromFlag rolled back to this
	// upgrade's own snapshot and marked the row terminal. At-or-past-target
	// deaths resume forward instead and never carry this code. See
	// upgrade-timeline.md § Binary-swap restart + resume.
	ErrResumeDied = "UPGRADE_DIED_DURING_RESUME"
)

// exitPrincipledConfigRefusal (78 = EX_CONFIG, sysexits.h) mirrors
// cli/cmd/config.go's constant of the same name and value — a bare literal
// per side, not a shared Go constant, matching this codebase's existing
// convention for cross-process exit-code contracts (exit 42, the post-swap
// handoff: documented independently here and in
// ops/statbus-upgrade.service's SuccessExitStatus=42/RestartForceExitStatus=42).
// `./sb config generate` selects this exit code for a principled,
// non-retriable configuration refusal (config.ErrPrincipledRefusal); Run's
// pre-flight config-generate call below inspects the SUBPROCESS'S exit code
// for exactly this value, since the Go sentinel error cannot cross the exec
// boundary itself (STATBUS-298).
const exitPrincipledConfigRefusal = 78

// Run starts the upgrade service main loop.
func (d *Service) Run(ctx context.Context) error {
	d.runningAsService = true

	ctx, cancel := signal.NotifyContext(ctx, syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// SIGUSR1 → non-destructive goroutine dump. Contrast with SIGQUIT
	// (Go's default: dump + exit). Operator workflow for a hung service:
	//
	//     kill -USR1 <pid>
	//     # dump written to tmp/upgrade-service-goroutines-<utc>.txt
	//     # service keeps running
	//
	// The dump names every goroutine, its current stack, and the call
	// that parked it — enough to diagnose pgx cancellation races, mutex
	// deadlocks, netpoll hangs, etc. without killing the forensic target.
	sigUSR1 := make(chan os.Signal, 1)
	signal.Notify(sigUSR1, syscall.SIGUSR1)
	go func() {
		defer signal.Stop(sigUSR1)
		for {
			select {
			case <-ctx.Done():
				return
			case <-sigUSR1:
				if path, err := d.writeGoroutineDump(); err != nil {
					fmt.Fprintf(os.Stderr, "SIGUSR1: failed to write goroutine dump: %v\n", err)
				} else {
					fmt.Printf("SIGUSR1: wrote goroutine dump to %s\n", path)
				}
			}
		}
	}()

	if err := d.loadConfig(); err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	// STATBUS-308: announce a floor breach into the journal at start.
	//
	// The service can only ever report the breaches it SURVIVES — a drifted unit
	// (running an old definition) or a unit that was started manually while
	// something else is wrong. It cannot report its own absence, which is why
	// the operator verbs carry the same announce. Both call the same inspector,
	// so they cannot disagree about what "correct" means.
	//
	// Detection only: this logs. It never rewrites the unit or restarts itself.
	d.announceUnitFloor()

	// Load trusted commit signers for signature verification
	if err := d.loadTrustedSigners(); err != nil {
		return err
	}

	// Pre-flight A — regenerate config UNCONDITIONALLY, before any docker
	// compose call. The daemon's .env must match THIS binary's compose template
	// before EnsureDBUp's `docker compose up -d db`, which config-load-parses the
	// WHOLE project (docker-compose.yml `include:`s docker-compose.rest.yml) and
	// dies on any unsatisfied `${VAR:?}` (e.g. REST_ADMIN_BIND_ADDRESS). The
	// running binary can be AHEAD of the on-disk .env with NO flag present:
	//   - post-swap exit-42 handoff (flag is post_swap — covered, but not only),
	//   - a staged-binary unit restart BEFORE any upgrade flag exists (0-happy
	//     Phase 3 restarts onto the pre-staged HEAD binary before fabricating the
	//     flag in Phase 4 — STATBUS-058 first cut gated on the flag and so
	//     SKIPPED the regen here, leaving the stale .env → EnsureDBUp died),
	//   - a manual `systemctl restart` onto a newer pre-staged binary.
	// So this is NOT gated on a flag — the binary-ahead-of-.env state exists
	// without one. config generate is idempotent (a healthy boot rewrites
	// identical files), DB-independent, and seconds (pre-READY, within
	// TimeoutStartSec). Mirrors runCrashRecovery (cli/cmd/install_upgrade.go:164-170),
	// which already regenerates unconditionally before its DB probe. Fatal on
	// failure: EnsureDBUp would fail anyway, and a clear "regenerate config"
	// error is the actionable signal.
	if flag, ferr := ReadFlagFile(d.projDir); ferr == nil && flag.IsServiceNewSbRecovery() {
		// Recovery boot, FORWARD phases ONLY (post_swap / resuming). executeUpgrade
		// defers the target checkout to here (STATBUS-060) so the OLD binary never
		// materializes target-compose. A post-swap/resuming recovery resumes
		// FORWARD and needs the target tree NOW — BEFORE the config-generate below
		// (so it emits the target's keys + VERSION) AND before boot-migrate-up
		// later in Run (which reads the working tree's migrations to satisfy the
		// schema-skew guard before recoverFromFlag's renamed-column queries).
		// flag.CommitSHA is the upgrade target; git checkout errors on a bad ref.
		// The objects are local (executeUpgrade fetched them pre-swap).
		//
		// A PreSwap flag is GATED OUT (STATBUS-061 part ii): it rolls back, and the
		// rollback's restoreGitState owns the tree (→ OLD via the pinned
		// `pre-upgrade` branch). Checking out the target here would advance the
		// tree forward, and boot-migrate-up would then apply the TARGET migrations
		// to a DB about to be rolled back — leaving git=OLD + schema=TARGET, the
		// schema/git skew this gate removes. For PreSwap the tree stays where
		// executeUpgrade left it (source); the config-generate below emits the
		// source's keys, matching the rollback direction.
		fmt.Printf("Recovery boot (service-held flag phase=%q, upgrade id=%d, target=%s) — restoring target tree + regenerating config before db up\n",
			flag.Phase, flag.ID, flag.Label())
		if out, err := runCommandOutput(d.projDir, "git", "-c", "advice.detachedHead=false", "checkout", flag.CommitSHA); err != nil {
			return fmt.Errorf("recovery boot: git checkout target %s: %w (%s)", ShortForDisplay(flag.CommitSHA), err, strings.TrimSpace(out))
		}
	}
	sbBin := filepath.Join(d.projDir, "sb")
	// KEEP THE OUTPUT (STATBUS-297). This captured CombinedOutput and threw it
	// away, so a failing config generate reached the journal as bare "exit
	// status 1" — while the git-checkout call four lines above appends its
	// output and says what went wrong. Three fleet runs were attributed to two
	// unrelated tickets (293's version lottery, then 294's listener crash) on a
	// fingerprint that carried no cause, because the one byte that named it was
	// discarded HERE. config generate refuses with a precise, actionable
	// message; this is the line that decided nobody would read it.
	if out, err := runCommandOutput(d.projDir, sbBin, "config", "generate"); err != nil {
		// STATBUS-298: a principled refusal (config.ErrPrincipledRefusal,
		// selected as exit 78/EX_CONFIG by configGenerateCmd.RunE in
		// cli/cmd/config.go — the sentinel cannot cross this subprocess
		// boundary itself, so the exit code IS the contract) is NOT a
		// transient failure. Before this fix, EVERY exit here (refusal or
		// otherwise) returned the same generic error, systemd restarted the
		// unit into the IDENTICAL refusal every ~30s (the config does not
		// edit itself), and five restarts later the rate limiter killed the
		// unit — with the db left down, because every attempt failed HERE,
		// before ever reaching EnsureDBUp below. The refusal never destroyed
		// anything; it permanently prevented restoration (architect ruling,
		// STATBUS-298 ticket comment #1, superseding the ticket's original
		// "leaves the box serving" framing — decoupling this refusal from
		// whatever else the box was already doing is STATBUS-307, filed,
		// deliberately not this round).
		//
		// On a confirmed refusal: write the marker (./sb install's lever,
		// cleared on any successful start below), print the refusal's own
		// actionable text (already preserved in `out` since STATBUS-297),
		// and exit 78 directly — RestartPreventExitStatus=78 on the unit
		// (ops/statbus-upgrade.service) stops systemd retrying THIS exit
		// code while leaving every other exit's restart policy untouched.
		if configGenerateIsPrincipledRefusal(err) {
			refusalText := strings.TrimSpace(out)
			writeConfigRefusalMarker(d.projDir, refusalText)
			// STATBUS-307: a policy refusal (which release CHANNEL to follow)
			// must not decide whether the DATABASE comes back — those are two
			// different criticalities that this single all-or-nothing call used
			// to conflate. The fork: does a PREVIOUSLY GENERATED .env already
			// exist? That is the box's proof it has served successfully before
			// under a config that worked; a refusal now is about NEW input
			// (e.g. an operator hand-added a second key), not about whether the
			// box can serve at all.
			//
			//   - NO prior .env (a fresh box, first-ever config generate): there
			//     is nothing to fall back to — serving was never established —
			//     so this stays a hard refusal exactly as STATBUS-298 built it.
			//   - A prior .env EXISTS: do not exit. PARK instead — the marker
			//     just written above IS the park (STATBUS-298's file-level hook;
			//     there is no db connection yet to park a public.upgrade ROW,
			//     so the marker is the only mechanism available at this point
			//     in boot) — and fall through to EnsureDBUp below so the
			//     database returns. The box serves on the .env it already has;
			//     only the policy this run tried to resolve stays unresolved,
			//     loud in the journal and in the marker, until an operator fixes
			//     .env.config and a later successful config generate clears it.
			envPath := filepath.Join(d.projDir, ".env")
			if _, statErr := os.Stat(envPath); statErr != nil {
				fmt.Printf("Recovery boot: config generate refused (principled, not retriable — STATBUS-298), and no prior generated config exists at %s — nothing to serve on, hard refusing: %s\n", envPath, refusalText)
				os.Exit(exitPrincipledConfigRefusal)
			}
			fmt.Printf("Recovery boot: config generate refused (principled, not retriable — STATBUS-298), but a prior generated config exists at %s (STATBUS-307) — PARKING the upgrade (marker written, %s) and continuing so the database returns; the box serves on its existing config, only the upgrade is blocked: %s\n",
				envPath, configRefusalMarkerPath(d.projDir), refusalText)
			// Deliberately no exit, no return: fall through to EnsureDBUp below.
		} else {
			return fmt.Errorf("pre-flight: regenerate config before db up: %w (%s)", err, strings.TrimSpace(out))
		}
	}
	// else (err == nil, config generate succeeded): falls through to
	// Pre-flight B below with no explicit clear-on-success needed here —
	// STATBUS-298: `./sb config generate` (configGenerateCmd.RunE,
	// cli/cmd/config.go) clears the marker itself on ITS OWN success, and
	// that subprocess just exited 0 two lines above. Clearing again here
	// would be redundant policy duplication of the exact same operation on
	// the exact same path; see the comment there for why the CLI command is
	// the one right place for every caller (this one included) to share.
	//
	// STATBUS-307: if we instead reached this point via the has-config PARK
	// fall-through above, the marker was just WRITTEN, not cleared —
	// correctly so; it stays present until a later config generate actually
	// succeeds.

	// Pre-flight B — ensure DB is up. Idempotent (no-op when already up).
	// Covers the post-swap recovery path where the prior process image exited
	// 42 after stamping Phase=post_swap and intentionally stopped the DB
	// (applyNewSbUpgrading step 2 for the consistent backup). Without this pre-start,
	// connect() would fail against the stopped DB and systemd would loop-restart
	// us before recoverFromFlag → resumeNewSb → applyNewSbUpgrading ever runs.
	if err := d.EnsureDBUp(ctx); err != nil {
		return fmt.Errorf("ensure DB up: %w", err)
	}

	if err := d.connect(ctx); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	// STATBUS-338, Norway rc.02: executeUpgrade deliberately closes and nils both
	// connections before stopping the database. A returned preswap error unwinds
	// through these defers, so cleanup must tolerate the connections already being
	// gone instead of repanicking and hiding the original error.
	defer func() {
		if d.listenConn != nil {
			_ = d.listenConn.Close(context.Background())
		}
	}()
	defer func() {
		if d.queryConn != nil {
			_ = d.queryConn.Close(context.Background())
		}
	}()

	// Acquire advisory lock to prevent multiple instances
	if err := d.acquireAdvisoryLock(ctx); err != nil {
		return err
	}

	// Capture the off-channel repair boundary BEFORE READY=1, using the database
	// clock that also stamps public.upgrade.discovered_at. READY deliberately
	// precedes boot migration and the startup sweep, so a register command may
	// legitimately create a row while those steps are still running. Rows created
	// after this boundary are new operator input, not historical shelf residue.
	if err := d.queryConn.QueryRow(ctx, "SELECT clock_timestamp()").Scan(&d.offChannelSweepCutoff); err != nil {
		return fmt.Errorf("capture off-channel sweep cutoff: %w", err)
	}

	// Harness-only stall site (C11): simulates a startup pipeline that runs
	// longer than the unit's TimeoutStartSec budget. Activated by
	// STATBUS_INJECT_AT=service-startup-slower-than-systemd-unit-timeout and
	// held by STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE. Fires in the unit's
	// `activating` phase — BEFORE the sdNotify("READY=1") below. After plan
	// piece #2 (upgrade-resume-structural-whole.md) the only work that runs
	// pre-READY=1 is the cheap init (EnsureDBUp → connect → advisory lock), so
	// this is the genuine remaining start-phase window; if it exceeds the
	// static TimeoutStartSec the unit is killed (bounded by StartLimitBurst),
	// recovery is `./sb install`. No-op in production. Drives scenario 1-boot-startup-timeout.
	inject.StallHere("service-startup-slower-than-systemd-unit-timeout")

	// LISTEN on channels (must use listenConn — queryConn is for queries).
	// Registered BEFORE READY=1 (and before recoverFromFlag/boot-migrate below)
	// so the service is already listening the instant systemd marks the unit
	// active — a NOTIFY (e.g. upgrade_apply, fired by the upgrade_notify_daemon
	// trigger when a row is scheduled, or by ./sb upgrade apply-latest) sent right after activation,
	// or during the resume, BUFFERS on the session rather than being lost.
	// Notifications are not *processed* until startListenLoop runs in the main
	// loop below, so registering early only prevents missed wakeups; it does
	// not let a NOTIFY interleave with recovery.
	if _, err := d.listenConn.Exec(ctx, "LISTEN upgrade_check"); err != nil {
		return fmt.Errorf("LISTEN upgrade_check: %w", err)
	}
	if _, err := d.listenConn.Exec(ctx, "LISTEN upgrade_apply"); err != nil {
		return fmt.Errorf("LISTEN upgrade_apply: %w", err)
	}

	// Signal readiness BEFORE boot-migrate + recoverFromFlag (plan piece #2,
	// B1 + boot-migrate-move). The cheap, genuine init that SHOULD gate
	// readiness has run (EnsureDBUp → connect → advisory lock + LISTEN). The
	// heavy, DB-size-scaled work below — boot-migrate-up and recoverFromFlag →
	// resumeNewSb → applyNewSbUpgrading (rune: a large-DB migration) — must NOT
	// run under the fixed start-phase
	// TimeoutStartSec, which can never bound DB-size-scaled work (the NO/rune
	// 40 h wedge). Emitting READY=1 here moves all of it into systemd's ACTIVE
	// phase, governed by WatchdogSec. Nothing forces READY=1 to follow
	// recovery: Type=notify + Restart=always + advisory lock + flag still
	// serialise a genuine crash; "active while it works" is more honest than a
	// unit stuck `activating` until a start-timeout kill.
	fmt.Printf("Upgrade service started (channel=%s, interval=%s)\n", d.channel, d.interval)
	sdNotify("READY=1") // Tell systemd we're initialized

	// Schema-skew guard (rc.65 structural fix). The binary's column-name
	// expectations must match the running schema before any service-level
	// query touches public.upgrade (recoverFromFlag below is the first such
	// query). STATBUS-145: `./sb migrate up --to DaemonSchemaFloor` brings the
	// schema up ONLY to the daemon's operating floor — sufficient for every daemon
	// query by the floor guarantee (migrate.DaemonRelationNames + the bump guard),
	// NOT to HEAD. Idempotent — a no-op when already at/above the floor.
	//
	// Background: rc.63 renamed three columns (version → commit_version,
	// from_version → from_commit_version, tags → commit_tags). When a new
	// binary boots against an unmigrated schema, ~23 SELECT/INSERT/UPDATE
	// sites in this file fail with SQLSTATE 42703. Rather than scatter
	// per-site compat shims, we migrate forward at boot. If migrate up
	// itself fails, refuse to enter the loop — operator must fix the
	// migration or restore the DB from backup.
	//
	// Runs AFTER READY=1 (plan piece #2 boot-migrate-move): a large-DB boot
	// migration is DB-size-scaled and would blow the fixed start-phase
	// TimeoutStartSec; active-phase it runs under WatchdogSec instead. Stays
	// BEFORE recoverFromFlag so the schema is at the daemon floor before the first
	// public.upgrade query. A kill leaves a clean resumable state
	// (transactional migrations + db.migration version table).
	//
	// STATBUS-012: active-phase alone is NOT survival. The watchdog armed at
	// READY=1 above; the main-loop idle heartbeat ticker does not exist yet
	// (created below, after recovery); the applyNewSbUpgrading gated ticker is not
	// armed; and the main goroutine parks inside runCommandToLog's cmd.Run()
	// — so without its own cover boot-migrate has ZERO WATCHDOG=1 sources,
	// and a single >120 s migration is SIGABRT'd by WatchdogSec into an
	// unbounded restart loop (~160 s/cycle stays under StartLimitBurst=5 per
	// 600 s — the rune wedge, WatchdogSec edition). PRE-STATBUS-145 this site
	// consumed every upgrade's migration delta (executeUpgrade Step 6b's post-swap
	// handoff routed the delta through the re-exec'd boot-migrate); under 145 boot
	// goes only to the floor and the delta runs at the protected applyNewSbUpgrading
	// migrate step, so this cover now protects the (small, rare) FLOOR migrations +
	// unknown boot crashes — kept belt-and-suspenders. Cover: the same always-ping
	// bounded ticker the
	// applyNewSbUpgrading migrate gets via deferGating (nil progress = ping
	// unconditionally, see runGatedWatchdogTicker; the stall-threshold arg
	// is INERT under nil progress — passed for signature parity only),
	// bounded by the shared MigrateUpTimeout so the two migrate sites
	// cannot drift. Stated tradeoff: a genuinely HUNG boot-migrate is now
	// caught at MigrateUpTimeout + the #14 orphan-terminate below, not at
	// WatchdogSec — identical to the protected applyNewSbUpgrading site, and the
	// point: the 120 s "detection" was a FALSE kill of legitimate slow
	// migrations. Cancel+join is EXPLICIT and inline (before the error
	// handling), not deferred: Run() IS the main loop, so a defer would
	// leak the ticker for the whole service lifetime — pinging past a
	// markTerminal refuse and masking a genuinely dead unit from systemd.
	//
	// STATBUS-044 comment #6 — count the crash-resume attempt at the START of the
	// recovery pass, BEFORE this boot migrate, so a death IN it self-counts (the r12
	// window where resume-time migrations actually run). The guard also stamps
	// StepBootMigrate on the flag (same-step-twice covers the boot window) and, for
	// a PARKED row, returns skip=true so we do NOT re-run the killer migration — the
	// unit stays alive-idle. The guard owns + releases the flock internally; it is a
	// no-op (returns false) for a non-forward-recovery boot.
	skipBootMigrate := d.RecoveryBudgetGuard(ctx)
	if skipBootMigrate {
		fmt.Printf("Recovery boot: skipping the boot migrate for a parked upgrade — the unit stays alive-idle; recoverFromFlag's parked-skip (resume or rollback arm) keeps it that way. Re-trigger the upgrade or run ./sb install to un-park.\n")
	}
	if !skipBootMigrate {
		bootMigrateTickerCtx, bootMigrateTickerCancel := context.WithCancel(ctx)
		bootMigrateTickerDone := make(chan struct{})
		go runGatedWatchdogTicker(bootMigrateTickerCtx, nil,
			applyNewSbUpgradingStallThreshold, applyNewSbUpgradingWatchdogCadence,
			func() { sdNotify("WATCHDOG=1") }, bootMigrateTickerDone)
		// runCommandToLogCapture (not runCommandToLog) so a DETERMINISTIC failure's
		// verbose tail is available as DATA for the STATBUS-144 operator report
		// below (contract-blessed: exit_codes.go — "a stderr tail is text-as-DATA;
		// text-as-CLASSIFIER is the banned thing"). Streaming to os.Stdout/os.Stderr
		// (the journal) and the ErrCommandTimeout mapping are identical to the
		// non-capturing variant; only the returned tail is added.
		//
		// STATBUS-145: `--to DaemonSchemaFloor` — boot catches the schema up only to
		// the daemon's own operating floor, NOT to HEAD. Migrations above the floor
		// are the real upgrade delta; they run EXACTLY ONCE inside the guarded
		// applyNewSbUpgrading migrate step (write-ahead stamp, 12h ceiling + orphan reap,
		// exit-20/22 classification, observed-state Behind → data-safe rollback), so
		// no migration runs blindly at boot. On the normal single-release upgrade the
		// floor migrations shipped earlier and are already applied → this is a no-op.
		bootMigrateTail, bootMigrateErr := runCommandToLogCapture(d.projDir, MigrateUpTimeout, io.Discard, "boot-migrate-up", nil,
			filepath.Join(d.projDir, "sb"), "migrate", "up", "--to", strconv.FormatInt(migrate.DaemonSchemaFloor, 10), "--verbose")
		bootMigrateTickerCancel()
		<-bootMigrateTickerDone
		if err := bootMigrateErr; err != nil {
			// #14: a boot-migrate TIMEOUT (MigrateUpTimeout) leaves the same orphaned in-container
			// psql backend as the resume-migrate path (docker-exec doesn't forward
			// the process-group SIGKILL). Terminate it on the live conn before
			// refusing — so it isn't left holding locks against the next start's
			// migrate. queryConn is live here (connect ran earlier in Run setup);
			// nil progress (boot has no progress log) — terminateMigrateOrphan is
			// nil-safe. Timeout-only: a clean boot-migrate failure means psql exited.
			if errors.Is(err, ErrCommandTimeout) {
				d.terminateMigrateOrphan(ctx, nil)
			}
			// STATBUS-144: classify a FLAGLESS boot-migrate failure by the migrate
			// exit-code contract (cli/internal/migrate/exit_codes.go). exit 20 =
			// DETERMINISTIC — a migration's SQL failed identically on every apply
			// (psql exit 3 under ON_ERROR_STOP). Classify on the numeric EXIT CODE
			// ONLY, never stderr text (doc-022). runCommandToLogCapture returns
			// cmd.Run's raw *exec.ExitError unwrapped on a clean (non-timeout)
			// failure, so errors.As reads the code directly; a timeout is
			// ErrCommandTimeout (handled just above), NOT an ExitError, so it is
			// correctly NOT deterministic → falls to the transient refuse branch.
			bootMigrateDeterministic := bootMigrateIsDeterministic(err)
			// STATBUS-017: a service-held in-progress flag means an interrupted upgrade
			// left a half-applied migration the schema-skew guard CANNOT re-apply
			// ("relation already exists" for an after-commit-but-unrecorded migration,
			// or a deterministic migration error). recoverFromFlag (next, :1689) owns the
			// snapshot-restore path: its Resuming/PostSwap one-shot latch rolls the DB
			// back to the pre-upgrade snapshot. Defer to it instead of refusing —
			// markTerminal+return here IS the rune wedge (a half-applied migration
			// boot-loops forever instead of restoring). Keep refuse for the no-flag /
			// install-held case: a genuine stale-schema refusal with no recovery owner
			// (recoverFromFlag only clears install-held flags — no snapshot to restore).
			// Inert in every green scenario: the branch is reached only when
			// boot-migrate-up FAILS, which it never does when the migration re-applies
			// cleanly.
			//
			// STATBUS-145 (domain shrink): boot migrates only to the floor, so a
			// service-held-flag boot-migrate failure here is a FLOOR-migration failure
			// during recovery — the upgrade DELTA now applies at the guarded
			// applyNewSbUpgrading step (recoverFromFlag → resumeNewSb → applyNewSbUpgrading),
			// not here. The defer-to-recoverFromFlag path is unchanged; its domain is
			// just the (small, rare) floor migrations plus the after-commit-unrecorded
			// half-applied case, which the observed-state Behind → snapshot restore
			// still owns.
			if flag, ferr := ReadFlagFile(d.projDir); ferr == nil && flag != nil && flag.Holder == HolderService {
				fmt.Printf("boot-migrate-up failed but a service-held in-progress upgrade flag is present "+
					"(id=%d, %s, phase=%q) — deferring to recoverFromFlag for snapshot restore (STATBUS-017): %v\n",
					flag.ID, flag.Label(), flag.Phase, err)
				// fall through — do NOT markTerminal/return; recoverFromFlag below handles it
			} else if bootMigrateDeterministic {
				// STATBUS-144: FLAGLESS + DETERMINISTIC (exit 20). The natural aftermath
				// of a git-corrupt rollback ABORT (STATBUS-136): the abort's git restore
				// FAILED, so the new version's broken migration REMAINS on disk with
				// row=failed and NO flag. The refuse branch below would return here → the
				// process exits → systemd Restart=always re-runs it every RestartSec
				// until StartLimit kills the unit into a silent 'failed' state (observed
				// live: NRestarts climbing +1/30s on VM 65.108.158.151). A re-run cannot
				// help — the SQL fails identically — so the ratified deterministic-failure
				// rule applies: fail-fast + actionable ONCE, then STAY ALIVE. The daemon's
				// normal duties (discovery, backup ticker, LISTEN) do not need the pending
				// migration's schema; the broken migration resurfaces actionably on the
				// next deliberate upgrade.
				//
				// STATBUS-145 (domain shrink): boot now migrates only to the floor, so a
				// FLAGLESS boot-migrate runs ONLY floor migrations — this branch fires for
				// a broken FLOOR migration (our own upgrade-lifecycle migrations, rare +
				// small), NEVER for a broken upgrade DELTA. A broken delta is above the
				// floor and runs only at the guarded applyNewSbUpgrading step, where it routes
				// observed-state Behind → data-safe rollback, not here.
				//
				// So LOG LOUD ONCE + CONTINUE into the main loop
				// alive-idle: NO markTerminal (that is the refuse-and-exit signal) and NO
				// return. recoverFromFlag below no-ops (no flag). The "once" is structural
				// — not looping means it logs once per boot. The install-ladder twin
				// (install_upgrade.go boot-migrate handler) is intentionally NOT changed:
				// it is operator-invoked, one-shot, human-present — fail-fast to the
				// terminal is correct there and it cannot churn (no systemd auto-restart).
				fmt.Fprintf(os.Stderr,
					"\n════════════════════════════════════════════════════════════════\n"+
						"  BOOT MIGRATE FAILED DETERMINISTICALLY (exit %d) — upgrade daemon staying ALIVE\n"+
						"════════════════════════════════════════════════════════════════\n"+
						"  A pending database migration fails the SAME way on every attempt\n"+
						"  (a deterministic SQL error). Re-running it cannot help, so this box\n"+
						"  will NOT restart-loop — the upgrade service keeps serving its normal\n"+
						"  duties and will apply/schedule NO upgrade until this is resolved.\n"+
						"\n"+
						"  OPERATOR ACTION — fix or remove the failing migration, then re-run install:\n"+
						"     1. See the failure:   ./sb migrate up\n"+
						"     2. Fix the broken migration file (or remove it if it should not ship).\n"+
						"     3. Apply the fix:     ./sb install\n"+
						"\n"+
						"  Failing boot-migrate output (tail):\n%s\n"+
						"════════════════════════════════════════════════════════════════\n",
					migrate.ExitDeterministic, strings.TrimSpace(bootMigrateTail))
				// fall through — alive-idle; do NOT markTerminal/return.
			} else {
				d.markTerminal("BOOT_MIGRATE_UP_FAILED",
					fmt.Sprintf("./sb migrate up at boot failed: %v; service refuses to enter the loop on a stale schema", err))
				return fmt.Errorf("boot migrate up: %w", err)
			}
		}
	}

	// STATBUS-145: on a FLAGLESS boot the schema was caught up only to the daemon
	// floor (above) — any migrations BEYOND the floor are the real upgrade delta,
	// applied only by a deliberate upgrade or `./sb install`, never blindly here.
	// Log ONE loud line naming how many are deferred so the state is visible in the
	// journal (pre-145, boot silently applied them). Best-effort — a counting error
	// never blocks the boot. Skipped on a recovery boot (a service-held flag), where
	// recoverFromFlag below owns the delta's fate (resume forward, or roll back).
	if flag, ferr := ReadFlagFile(d.projDir); ferr != nil || flag == nil || flag.Holder != HolderService {
		if pending, n, perr := migrate.HasPendingAbove(d.projDir, migrate.DaemonSchemaFloor); perr == nil && pending {
			fmt.Printf("STATBUS-145: %d migration(s) pending beyond the daemon floor (%d) — they apply on the next deliberate upgrade or `./sb install`, not at boot.\n",
				n, migrate.DaemonSchemaFloor)
		}
	}

	// Recover from interrupted upgrades. The flag file survives DB rollbacks
	// (it's on the filesystem, not in the DB volume). Must run BEFORE
	// completeInProgressUpgrade so the flag-based recovery takes priority.
	//
	// A non-nil return is a category-3 divergence per the recovery trifecta
	// (rc.67) — exit so systemd's StartLimit (Item L: 10 in 600s) catches a
	// thrashing daemon that can't reconcile its own state instead of letting
	// the loop schedule new upgrades against a broken world.
	if err := d.recoverFromFlag(ctx); err != nil {
		return fmt.Errorf("recover from flag: %w", err)
	}
	// A crash or unlink failure after rollback restored the previous version but
	// before the final failed -> rolled_back UPDATE leaves a deliberately marked
	// failed row. Finish marker cleanup and that harmless DB-only transition before
	// considering any new work; never restore the snapshot again.
	d.finalizePendingRollbacks(ctx)

	// Complete any in-progress upgrade from a previous service instance
	// (e.g., after self-update restart via exit code 42)
	d.completeInProgressUpgrade(ctx)

	// Sync UPGRADE_* config from .env to system_info table
	d.syncConfigToSystemInfo(ctx)

	// Clean stale maintenance file
	d.cleanStaleMaintenance(ctx)

	// STATBUS-163: clear a stale read-only window (near-unreachable post-fix; its
	// firing indicts a broken terminal OFF flip — see clearStaleReadOnlyWindow).
	d.clearStaleReadOnlyWindow(ctx)

	// Check for missed scheduled upgrades
	d.checkMissedUpgrades(ctx)

	// LISTEN + READY=1 + boot-migrate-up were emitted earlier (right after the
	// advisory lock, before boot-migrate/recoverFromFlag) so the heavy
	// DB-size-scaled startup work runs in the ACTIVE phase under WatchdogSec
	// rather than the start phase under TimeoutStartSec. See the "Signal
	// readiness" block above and plan upgrade-resume-structural-whole.md #2.

	// Main loop: use a goroutine for LISTEN/NOTIFY, select on channels
	notifyCh := make(chan *pgconn.Notification, 1)
	errCh := make(chan error, 1)
	d.startListenLoop(ctx, notifyCh, errCh)

	ticker := time.NewTicker(d.interval)
	defer ticker.Stop()

	// Unified liveness heartbeat. 30s cadence is tuned for
	// WatchdogSec=120 in the systemd unit (ping at 1/4 the
	// deadline gives plenty of jitter tolerance).
	//
	// This ticker runs ON the main goroutine via the select below —
	// NOT in a separate goroutine (contrast the prior newWatchdog
	// helper, which this commit removes). The failure mode we're
	// closing: if the main goroutine parks on a deadlock, a
	// goroutine-local ticker keeps pinging systemd and the hang is
	// invisible for hours (observed Apr 23 2026, task #37). With
	// the ticker case in this select, a hung main goroutine stops
	// emitting heartbeats → systemd kills + restarts within 120s.
	heartbeatTicker := time.NewTicker(30 * time.Second)
	defer heartbeatTicker.Stop()

	// Scheduled logical-backup ticker (STATBUS-113). Fires on the configured
	// BACKUP_INTERVAL; the handler runs in a GOROUTINE (see the select case) so a
	// long pg_dump can never block the heartbeat case above — a synchronous
	// handler exceeding WatchdogSec=120 would get the service SIGKILLed mid-backup.
	backupTicker := time.NewTicker(d.backupInterval)
	defer backupTicker.Stop()

	// STATBUS-328 arm 1: retire rows that were never on this box's channel,
	// BEFORE the first discovery. Ordering matters for what an operator sees:
	// discover() may register new rows and print what it found, and a sweep
	// running afterwards would retire residue in a second pass, so the shelf is
	// briefly wrong in exactly the window someone reads the startup log. Sweeping
	// first means the ledger is already consistent with the declared channel by
	// the time anything new is added to it.
	//
	// Startup only, not per tick: intake has been filtered since 291, so new
	// off-channel rows cannot appear. This exists for rows that entered BEFORE
	// the filter, and for a box whose channel has just narrowed — both of which
	// are settled by the time the service is running.
	d.retireOffChannelOffers(ctx)

	// Initial discovery on startup
	d.discover(ctx)
	// STATBUS-098: also CLAIM any already-'scheduled' row at startup, not just
	// discover. A row scheduled while the daemon was down or restarting (e.g. a
	// NOTIFY lost during an upgrade's DB-restart reconnect window) would otherwise
	// sit unclaimed until the 6h discovery tick — on Albania, a web-UI-scheduled
	// upgrade silently delayed up to 6h. The claim is atomic (UPDATE ... WHERE
	// state='scheduled' AND started_at IS NULL → single winner), so this is safe
	// alongside the NOTIFY + tick claims. Restart the LISTEN loop if a claimed
	// upgrade stopped it (mirrors the ticker/notify cases).
	d.executeScheduled(ctx)
	if d.listenCancel == nil {
		d.startListenLoop(ctx, notifyCh, errCh)
	}

	// STATBUS-113 catch-up: if a scheduled backup was missed while the service was
	// down (the box was off over the cadence window), run it now rather than
	// waiting a full BACKUP_INTERVAL. maybeRunBackup's due-check makes this a
	// no-op when a recent dump already covers the window. Goroutine for the same
	// heartbeat-safety reason as the ticker case.
	go d.maybeRunBackup(ctx)

	for {
		select {
		case <-ctx.Done():
			fmt.Println("Upgrade service shutting down")
			d.stopListenLoop()
			return nil
		case <-heartbeatTicker.C:
			// Main-goroutine liveness heartbeat. Fires while idle; during
			// executeUpgrade, progress.Write covers heartbeats via its
			// embedded emitHeartbeat call, and this case does not fire
			// because the main goroutine is deep inside executeUpgrade.
			emitHeartbeat(d.projDir)
			// STATBUS-098: claim a pending 'scheduled' row within ≤30s even when
			// its NOTIFY was lost (dropped during an upgrade's DB-restart reconnect
			// window) — otherwise it waits for the 6h discovery tick. Guarded by
			// !d.upgrading; the case can't fire mid-upgrade anyway (the main
			// goroutine is blocked in executeUpgrade, whose own heartbeats feed the
			// watchdog). emitHeartbeat already fired above, so a long claimed
			// upgrade keeps the watchdog alive via executeUpgrade's heartbeats. The
			// claim is atomic; the 6h ticker stays for DISCOVERY only.
			if !d.upgrading {
				d.finalizePendingRollbacks(ctx)
				d.executeScheduled(ctx)
				if d.listenCancel == nil { // executeUpgrade may have stopped the loop
					d.startListenLoop(ctx, notifyCh, errCh)
				}
			}
		case <-ticker.C:
			fmt.Printf("Poll tick (next in %s)\n", d.interval)
			// STATBUS-308: cheap re-check on the poll tick, journaling only on a
			// transition. Catches a unit that drifts under a long-running service
			// (an install writes a new template while this process keeps running
			// the old definition) without turning the journal into noise.
			d.announceUnitFloorIfChanged()
			// The STAMP fires every tick, unlike the announce above. That is
			// deliberate and is what makes the missing-unit case observable at
			// all: the admin UI reads system_info.updated_at, so a box whose
			// service has stopped simply stops refreshing it, and the staleness
			// is the report. Stamping only on change would leave a healthy-looking
			// row frozen at its last transition forever.
			StampUnitFloor(ctx, d.queryConn, d.projDir, d.interval)
			if !d.upgrading {
				// Belt: reconcile any in_progress row whose final UPDATE was
				// lost (e.g. stale DB connection during executeUpgrade). Low-
				// cost — returns immediately when no orphan row exists.
				d.completeInProgressUpgrade(ctx)
				d.discover(ctx)
				d.executeScheduled(ctx)
				if d.listenCancel == nil { // restart if executeUpgrade stopped the loop
					d.startListenLoop(ctx, notifyCh, errCh)
				}
				// Catch up on work missed during any upgrade that just completed
				// (LISTEN connection was closed, NOTIFYs were lost)
				d.discover(ctx)
				d.executeScheduled(ctx)
				d.reportDiskSpace(ctx)
				d.reconcileBackupDir(ctx) // reconcile before prune: avoids BACKUP_MISSING for just-pruned rows
				d.pruneBackups(ctx, 3)
				d.pruneUpgradeLogs(20)               // keep the 20 newest upgrade-log + bundle pairs
				d.runRetentionPurge(ctx, "all", nil) // time-safety sweep over public.upgrade
			}
		case <-backupTicker.C:
			// Scheduled logical backup (STATBUS-113). GOROUTINE: a large-DB
			// pg_dump can run for minutes — longer than WatchdogSec — so it must
			// not block this select (the heartbeat case lives here too). All
			// guards (enabled / upgrade-in-progress skip / single-flight / due
			// check) live in maybeRunBackup.
			go d.maybeRunBackup(ctx)
		case n := <-notifyCh:
			if !d.upgrading {
				d.handleNotification(ctx, n)
				d.executeScheduled(ctx)
				if d.listenCancel == nil { // restart if executeUpgrade stopped the loop
					d.startListenLoop(ctx, notifyCh, errCh)
				}
				// Catch up on work missed during any upgrade that just completed
				// (LISTEN connection was closed, NOTIFYs were lost)
				d.discover(ctx)
				d.executeScheduled(ctx)
			}
		case err := <-errCh:
			d.stopListenLoop() // clears listenCancel so startListenLoop at line 756 doesn't short-circuit
			if ctx.Err() != nil {
				return nil // shutdown
			}
			fmt.Printf("LISTEN error: %v, reconnecting...\n", err)
			// Retry reconnection with exponential backoff.
			// The DB may be temporarily down during an upgrade on this or
			// another instance sharing the same host.
			var reconnErr error
			for attempt := 1; attempt <= 30; attempt++ {
				reconnErr = d.reconnect(ctx)
				if reconnErr == nil {
					break
				}
				if ctx.Err() != nil {
					return nil // shutdown
				}
				delay := time.Duration(attempt) * 2 * time.Second
				if delay > 30*time.Second {
					delay = 30 * time.Second
				}
				if attempt%5 == 0 {
					fmt.Printf("Reconnect attempt %d failed: %v (retrying in %s)\n", attempt, reconnErr, delay)
				}
				time.Sleep(delay)
			}
			if reconnErr != nil {
				return fmt.Errorf("reconnect failed after 30 attempts: %w", reconnErr)
			}
			// Restart listen goroutine
			d.startListenLoop(ctx, notifyCh, errCh)
		}
	}
}

// startListenLoop launches a new listenLoop goroutine with a cancellable context.
// Idempotent: if the goroutine is already running (listenCancel != nil), returns immediately.
// Invariant: stopListenLoop() clears listenCancel; only startListenLoop sets it.
//
// STATBUS-294: reads d.listenConn into a local ONCE, here, and hands that
// value to listenLoop as a parameter — the goroutine never touches the
// shared field again. stopListenLoop's 10s cleanup budget can still time
// out and leave this goroutine running (that is by design, see its own
// comment); when it does, executeUpgrade goes on to close AND NIL the
// shared d.listenConn (:5981-5984) while the abandoned goroutine is still
// looping. Before this fix that nil write raced the loop's own read of the
// field (write :5984 vs read :2625) and, if the loop read after the write,
// crashed with SIGSEGV inside pgx (WaitForNotification on a nil *pgx.Conn).
// With the connection captured locally instead, the abandoned loop keeps
// its own copy: the shared field going to nil cannot reach it, and the
// Close() that precedes the nil write turns its next WaitForNotification
// into an ordinary error the existing branch below already handles.
func (d *Service) startListenLoop(ctx context.Context, notifyCh chan<- *pgconn.Notification, errCh chan<- error) {
	if d.listenCancel != nil {
		return // already running
	}
	conn := d.listenConn

	// ── NO CONNECTION: ANNOUNCE AND LEAVE THE GUARD UNTOUCHED (STATBUS-306) ──
	//
	// Checked HERE, before any guard state exists, and that placement IS the
	// fix. The previous shape set d.listenCancel and d.listenDone first and let
	// the goroutine discover the nil conn — so a start that listened to nothing
	// still left the guard looking like a live listener. Nothing but
	// stopListenLoop clears that, and nothing calls stopListenLoop on an idle
	// box, so every later `if d.listenCancel == nil { startListenLoop }` in the
	// main loop was permanently false. The daemon went deaf for the rest of the
	// process's life: `./sb upgrade register` reported its poke sent, and it was
	// sent, into a service that could never hear it again. Reactivity silently
	// degraded from on-poke to the 6-hour tick.
	//
	// This happens on a real path, not a hypothetical one: recoveryRollback's
	// park closes both connections before returning, and Run() then reaches its
	// one and only startListenLoop for that boot with d.listenConn already nil.
	//
	// RETURNING BEFORE ASSIGNMENT rather than assigning and unwinding is
	// deliberate. The requirement is that the resulting state be
	// INDISTINGUISHABLE FROM NEVER-STARTED for every consumer — startListenLoop's
	// own guard, stopListenLoop's early return, and the four restart guards in
	// the idle loop. Never writing it satisfies that by construction; writing
	// then clearing would have to keep listenCancel and listenDone consistent
	// with each other at every exit, which is a thing to get wrong later.
	if conn == nil {
		fmt.Println("listenLoop NOT started: no database connection — the service will act " +
			"only on its own tick, and will start listening when a connection returns (STATBUS-294, STATBUS-306)")
		return
	}

	listenCtx, cancel := context.WithCancel(ctx)
	d.listenCancel = cancel
	done := make(chan struct{})
	d.listenDone = done
	fmt.Println("listenLoop started (channels: upgrade_check, upgrade_apply)")
	go func() {
		defer close(done)
		d.listenLoop(listenCtx, conn, notifyCh, errCh)
	}()
}

// stopListenLoop terminates the listenLoop goroutine and waits bounded time
// for its clean exit. The order is deliberate:
//
//  1. Force-close listenConn first. pgx v5.9.0 has a race where a NOTIFY
//     arriving simultaneously with a ctx.Cancel() keeps the WaitForNotification
//     reader parked on netpoll forever (observed on statbus_dev Apr 23 2026,
//     PID 902940 wedged 9h54m+; full forensic in task #37 /
//     tmp/engineer-dev-hang-meticulous.md). Closing the underlying net.Conn
//     from outside wakes the in-flight socket read with EBADF regardless
//     of pgx's internal state.
//  2. Cancel the listenLoop's ctx for state consistency.
//  3. Wait up to 10s on d.listenDone. 10s is generous: with the connection
//     closed, WaitForNotification returns in milliseconds. The timeout is a
//     LOUD cleanup budget, not a silent hang-extender.
//  4. On timeout: warn to stderr and continue. The listenLoop goroutine is
//     leaked (bounded to service lifetime — the next systemd restart frees
//     it). Better than blocking executeUpgrade forever, which is the
//     failure mode this replaces.
//
// This is not a blind timeout — the force-close is ACTIVE detection: we force
// the state we want rather than hope pgx notices. The 10s bound is a cleanup
// budget with loud failure, respecting the task #37 principle "you should be
// able to detect what you're waiting for."
func (d *Service) stopListenLoop() {
	if d.listenCancel == nil {
		return
	}
	if d.listenConn != nil {
		closeCtx, closeCancel := context.WithTimeout(context.Background(), 2*time.Second)
		_ = d.listenConn.Close(closeCtx)
		closeCancel()
	}
	d.listenCancel()
	done := d.listenDone
	d.listenCancel = nil
	d.listenDone = nil
	if done == nil {
		return // never started (startListenLoop wasn't reached)
	}
	select {
	case <-done:
		// clean exit
	case <-time.After(10 * time.Second):
		fmt.Fprintf(os.Stderr,
			"WARNING: listenLoop goroutine did not exit within 10s after force-close + ctx cancel; leaking goroutine and continuing (pid=%d)\n",
			os.Getpid())
	}
}

// listenLoop runs WaitForNotification in a goroutine, sending results on channels.
//
// STATBUS-294: conn is passed BY VALUE from startListenLoop's one-time read
// of d.listenConn, never read from the shared field here — see that
// function's comment for why. nil is handled explicitly (defensive: today's
// only caller never hands a nil conn, but "never crash on a value this
// function did not choose" is the whole point of taking conn as a
// parameter instead of reaching for shared state).
//
// The sends to notifyCh/errCh are select'd against ctx.Done() so an
// abandoned loop (stopListenLoop timed out and moved on) cannot block
// forever offering a result to a reader that may no longer exist — the
// same ownership gap this ticket closes, one channel-op earlier.
//
// DROPPING on ctx.Done is correct here, but the reason is a DEPENDENCY:
// a dropped upgrade_check/upgrade_apply notification is recovered by the
// service's own periodic tick polling the pending row. If the tick were
// ever removed and the service became purely notification-driven, this
// drop would become a lost wakeup — a box that silently never acts on a
// scheduled upgrade. (Dropped errCh values are noise about our own
// teardown: the error is almost always the conn close that accompanied
// the very cancellation being selected on.)
func (d *Service) listenLoop(ctx context.Context, conn *pgx.Conn, notifyCh chan<- *pgconn.Notification, errCh chan<- error) {
	defer fmt.Printf("listenLoop exiting (ctx.Err=%v)\n", ctx.Err())
	if conn == nil {
		// Loud by design (architect, STATBUS-294 review): a silent return here
		// would make the listener quietly not listen — the box keeps working on
		// its tick, degraded and looking healthy, which is the 263 failure shape.
		//
		// SECOND LINE OF DEFENCE since STATBUS-306. The production caller
		// (startListenLoop) now refuses a nil conn before it creates any guard
		// state, so this branch is not reached from there. It stays because
		// listenLoop's contract is its own: any future caller that hands it a
		// nil conn must still get a loud, safe return rather than the 294 panic.
		fmt.Println("listenLoop: no connection — NOT listening for notifications; " +
			"the service will act only on its own tick (STATBUS-294)")
		return
	}
	for {
		notification, err := conn.WaitForNotification(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return // context canceled, clean exit
			}
			select {
			case errCh <- err:
			case <-ctx.Done():
			}
			return
		}
		select {
		case notifyCh <- notification:
		case <-ctx.Done():
			return
		}
	}
}

func (d *Service) handleNotification(ctx context.Context, n *pgconn.Notification) {
	switch n.Channel {
	case "upgrade_check":
		fmt.Println("Received NOTIFY upgrade_check")
		d.discover(ctx)
	case "upgrade_apply":
		payload := strings.TrimSpace(n.Payload)
		if payload == "" {
			// Empty payload = run whatever is scheduled
			return
		}
		fmt.Printf("Received NOTIFY upgrade_apply: %s\n", payload)
		// STATBUS-092: recreate intent is DURABLE on the public.upgrade row (set
		// at schedule time), read by executeScheduled at claim — NOT carried in
		// the NOTIFY payload. A legacy ':recreate' suffix (a pre-092 sender) is
		// stripped and IGNORED so it never mis-parses as a version; the row is
		// the single source of truth.
		version := strings.TrimSuffix(payload, ":recreate")
		// No pre-validation: onScheduledNotify calls resolveUpgradeTarget,
		// which is the sole parser for operator/NOTIFY payloads. It accepts
		// CalVer tags, commit_sha, commit_short, and the legacy `sha-<hex>`
		// form the pre-Commit-B trigger emits (transitional). Bad payloads
		// surface as clear error messages from there. A NOTIFY for an
		// unregistered commit is a loud no-op (STATBUS-086, require-register).
		d.onScheduledNotify(ctx, version)
	}
}

func (d *Service) acquireAdvisoryLock(ctx context.Context) error {
	var locked bool
	// advisory lock objid: hashtext('upgrade_daemon') = 959307579
	err := d.queryConn.QueryRow(ctx, "SELECT pg_try_advisory_lock(hashtext('upgrade_daemon'))").Scan(&locked)
	if err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}
	if !locked {
		return fmt.Errorf("another upgrade service is already running (advisory lock held)")
	}
	return nil
}

// verifyBinaryObservedState is Check 1 of the observed-state verification
// (extracted as a pure function for testability — no DB access, no migration-
// version check). Tri-state (STATBUS-039 review finding 1):
//
//	binary == "" / "unknown"   → tier-1/tier-2 ambiguous; skip check
//	                              (degraded path per verifyUpgradeObservedState's
//	                              docstring). AtTarget with no reason.
//	binary == rowCommitSHA     → trivially AtTarget.
//	`git merge-base --is-ancestor rowCommitSHA binary` exit 0
//	                            → binary descends from target; AtTarget.
//	                              The upgrade reached at-or-past the goal,
//	                              even if a later commit landed on top.
//	merge-base exit 1           → DEFINITIVE negative: both commits resolved
//	                              and ancestry is positively absent → Behind.
//	merge-base any other error  → NOT a verdict on ancestry (exit 128 =
//	                              unresolvable commit in a shallow/pruned
//	                              clone; spawn error; timeout) → Unknown.
//	                              The pre-039 code conflated this with
//	                              exit-1 into a single false — which the
//	                              destructive callers then read as Behind
//	                              and RESTORED on clone-state evidence,
//	                              violating the Unknown→forward rule. A
//	                              cat-file probe distinguishes "target
//	                              commit absent" for an actionable reason.
//
// Mirrors the pattern in resumeNewSb (search for "binaryDescendsFlag")
// so the at-or-descendant predicate is uniform across post-restart
// recovery paths (resumeNewSb's copy stays conservative-false because
// its disposition is fail-loud-refuse, never restore).
func (d *Service) verifyBinaryObservedState(rowCommitSHA string) (ObservedState, UnknownCause, string) {
	if d.binaryCommit == "" || d.binaryCommit == "unknown" {
		fmt.Printf("Ground-truth: binary SHA unknown (local build?); skipping binary check.\n")
		return ObservedAlreadyAtNew, CauseNone, ""
	}
	if d.binaryCommit == rowCommitSHA {
		return ObservedAlreadyAtNew, CauseNone, ""
	}
	_, err := runCommandOutput(d.projDir, "git", "merge-base", "--is-ancestor", rowCommitSHA, d.binaryCommit)
	if err == nil {
		return ObservedAlreadyAtNew, CauseNone, ""
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) && exitErr.ExitCode() == 1 {
		return ObservedCannotReachNew, CauseNone, fmt.Sprintf(
			"binary commit %s != row target %s and is not its descendant (upgrade crashed before binary swap)",
			ShortForDisplay(d.binaryCommit), ShortForDisplay(rowCommitSHA))
	}
	// merge-base failed for a reason OTHER than a clean exit-1 (behind). If the
	// target commit is simply absent from the local clone (shallow/pruned), that
	// is a KNOWN-INTERMITTENT condition — a fetch acquires it — so classify it
	// CauseCommitNotFetched for backoff-retry. Any other merge-base failure with
	// the commit present is genuinely unrecognised → stop for a human.
	if _, probeErr := runCommandOutput(d.projDir, "git", "cat-file", "-e", rowCommitSHA+"^{commit}"); probeErr != nil {
		return ObservedPositionUnreadable, CauseCommitNotFetched, fmt.Sprintf(
			"target commit %s is not present in the local git clone (shallow or pruned?) — cannot verify binary ancestry (merge-base: %v)",
			ShortForDisplay(rowCommitSHA), err)
	}
	return ObservedPositionUnreadable, CauseUnrecognized, fmt.Sprintf(
		"git merge-base --is-ancestor failed (%v) — cannot verify binary ancestry", err)
}

// verifyUpgradeObservedState is the observed-state verification step for
// completeInProgressUpgrade (task #49). Given an in_progress row's target
// commit SHA, it checks TWO independent facts about the running system:
//
//  1. The binary's compile-time commit (d.binaryCommit, from cli/cmd/root.go
//     `commit` ldflag) matches the row's target commit_sha. A mismatch
//     means the binary was never actually swapped — the upgrade crashed
//     before replaceBinaryOnDisk, or the swap silently rolled back.
//
//  2. The DB's max applied migration (db.migration.version) is ≥ the max
//     on-disk migration version (migrations/*.up.sql). A gap means new
//     migrations shipped with the target version but never ran — the
//     upgrade crashed between git checkout and migrate up.
//
// Returns (ok, reason). `reason` is a descriptive string suitable for
// surfacing as the row's `error` column when ok == false.
//
// Degraded paths (returns ok=true to avoid false-positive FAILED rows):
//   - d.binaryCommit == "unknown" (non-release build, no ldflags): skip
//     binary check with a log line. Migration check still runs.
//
// This two-state form maps ObservedPositionUnreadable (cannot verify — DB
// unreachable) to ok=false, which is conservative-CORRECT for its callers:
// both use it as a READ-ONLY gate ("refuse to mark completed"). Destructive
// dispositions (restore) must use verifyUpgradeObservedStateEx directly and
// only restore on a POSITIVE ObservedCannotReachNew verdict — destroying state
// under uncertainty is forbidden (STATBUS-039 rule 1).
func (d *Service) verifyUpgradeObservedState(ctx context.Context, rowCommitSHA string) (ok bool, reason string) {
	obsState, _, reason := d.verifyUpgradeObservedStateEx(ctx, rowCommitSHA)
	return obsState == ObservedAlreadyAtNew, reason
}

// ObservedState is the tri-state verdict on whether the running system is
// at-or-past an upgrade row's target (STATBUS-039, the transactional model:
// "forward when logically possible — observed state decides possibility").
type ObservedState int

const (
	// ObservedAlreadyAtNew — binary at-or-descendant-of target AND DB
	// migrations at-or-past the on-disk max. Forward is logically possible;
	// recovery must go forward, never restore.
	ObservedAlreadyAtNew ObservedState = iota
	// ObservedCannotReachNew — POSITIVELY verified behind (binary mismatch, or
	// migrations missing with a reachable DB). Forward is impossible without
	// new code/migrations; backward to THIS upgrade's own snapshot regains a
	// runnable state to go forward from later.
	ObservedCannotReachNew
	// ObservedPositionUnreadable — cannot verify (DB unreachable mid-check). NOT a
	// licence to restore: destructive paths must treat Unknown as "retry
	// forward, loudly" — the next pass re-checks. Read-only paths (mark
	// completed) treat Unknown as "refuse to claim success".
	ObservedPositionUnreadable
)

func (d *Service) verifyUpgradeObservedStateEx(ctx context.Context, rowCommitSHA string) (ObservedState, UnknownCause, string) {
	// Check 1: binary SHA at-or-descendant-of target. Pure git + ldflags —
	// no DB involved. Tri-state: merge-base exit 1 is the only POSITIVE
	// behind verdict; unresolvable commits (shallow clone) are Unknown
	// (STATBUS-039 review finding 1 — never restore on clone-state evidence).
	if binObs, bcause, reason := d.verifyBinaryObservedState(rowCommitSHA); binObs != ObservedAlreadyAtNew {
		return binObs, bcause, reason
	}

	// Check 2: migration max version — DB vs on-disk
	// STATBUS-190: bound the read with the shared classify-path timeout. A paused/
	// frozen DB makes this query HANG on the live-but-unanswering conn; the timeout
	// turns that hang into a DeadlineExceeded error that classifies as
	// CauseDBUnreachable below — so a HANG and a fast connection-refusal are ONE
	// class at the classifier, both routed to the in-process backoff.
	readCtx, cancel := context.WithTimeout(ctx, recoveryReadTimeout)
	defer cancel()
	var dbMaxVersion int64
	queryErr := d.queryConn.QueryRow(readCtx,
		`SELECT COALESCE(MAX(version), 0) FROM db.migration`).Scan(&dbMaxVersion)
	if queryErr != nil {
		// Cannot verify — DB unreachable (mid-restart). Loud, never silent (the
		// pre-task-#49 shape returned ok=true here and silently marked rows
		// completed). Typed CauseDBUnreachable so recovery backoff-retries the DB
		// probe in-process instead of exiting (STATBUS-109). Read-only gates still
		// refuse to mark success on Unknown.
		return ObservedPositionUnreadable, CauseDBUnreachable, fmt.Sprintf(
			"DB migration-version query failed: %v (cannot verify migrations applied)",
			queryErr)
	}

	// STATBUS-138: the on-disk max comes from migrate.MaxDiskVersion — the SAME
	// shared lister the applier (migrate.Up) uses — so an invalid-named file
	// (skipped + warned there) is invisible here too. The comparator can no longer
	// read a version migrate would refuse (the r17 permanent-false-Behind that
	// drove the recoveryRollback crash loop), nor miss a pending .up.psql (the
	// inverse false-AtNew). The old service-local latestDiskMigrationVersion —
	// which globbed .up.sql only and accepted any numeric prefix (99999999999999
	// passed) — is deleted; this reader and the applier cannot disagree anymore.
	diskMaxVersion, diskErr := migrate.MaxDiskVersion(d.projDir)
	if diskErr != nil {
		// A real migrations-dir defect (e.g. a duplicate migration version) —
		// unverifiable; never silently assume AtNew. Unrecognized → stop for a
		// human, not a destructive auto-action.
		return ObservedPositionUnreadable, CauseUnrecognized, fmt.Sprintf(
			"cannot compute on-disk migration max: %v (cannot verify migrations applied)", diskErr)
	}
	if diskMaxVersion == 0 {
		// No valid on-disk migrations found (odd but non-fatal); skip check.
		fmt.Printf("Ground-truth: no on-disk migrations found; skipping migration check.\n")
		return ObservedAlreadyAtNew, CauseNone, ""
	}

	if dbMaxVersion < diskMaxVersion {
		return ObservedCannotReachNew, CauseNone, fmt.Sprintf(
			"db.migration max version %d < on-disk max %d (migrations did not run)",
			dbMaxVersion, diskMaxVersion)
	}

	return ObservedAlreadyAtNew, CauseNone, ""
}

// recoveryRollback is the recovery-path wrapper around d.rollback() used by
// completeInProgressUpgrade and recoverFromFlag (task #49). It bridges the
// recovery context — where we have an upgrade row id + log relative path
// but the in-process rollback() machinery expects a live ProgressLog and
// restoreTargetSHA string — to a real rollback invocation.
//
// User principle (task #49): every code path that today marks
// `failed`/`rolled_back` WITHOUT calling rollback() must now call it.
// "Status without reality-restore is a lie."
//
// Steps:
//  1. Resolve the restore target as the pinned `pre-upgrade` branch
//     (restoreTargetSHA="" -> restoreGitState's pre-upgrade fallback).
//     STATBUS-077 made the branch the single source of truth and removed the
//     from_commit_sha column. NEVER use d.version: it is a CommitVersion = the
//     running binary's version = the TARGET in a HEAD-recovery (061 #1).
//     A working restore target is what restoreGitState needs to know
//     what to git-checkout back to.
//  2. Open the row's log in append mode so the rollback narrative lands
//     on the same on-disk log the prior pre-crash run wrote to. If the
//     log is gone (manually pruned), open a fresh one.
//  3. Invoke d.rollback(). It runs the full robust rollback pipeline:
//     captureContainerLogs → docker stop → restoreGitState →
//     restoreDatabase → restoreBinary → docker up → reconnect →
//     setMaintenance(false) → UPDATE state='rolled_back' → removeFlag.
//     For the pre-backup-crash case (no destructive state to undo), the
//     restore steps are mostly no-ops — that's fine; the UPDATE still
//     transitions the row coherently.
//
// flag identifies the upgrade being recovered AND carries the restore
// identity: flag.BackupPath is the snapshot THIS upgrade recorded — the
// only legal restore source (identity-keyed, STATBUS-039/-031). Empty by
// construction for PreSwap-phase recoveries: restoreDatabase then refuses
// to touch the never-mutated volume. Flagless callers
// (completeInProgressUpgrade) synthesize a faithful record from the row.
//
// FLOCK GATE (STATBUS-039 review finding 3 — fleet-wide corruption fix):
// the destructive restore is serialized on the upgrade flock BEFORE any
// work. Install's inline recovery (runCrashRecovery → RecoverFromFlag)
// holds neither the install flag nor the daemon advisory lock here, and a
// concurrently (re)spawned service's recovery is equally lock-free — so
// without this gate two recoveryRollback instances can rsync --delete the
// same DB volume at once. The flock is the codebase's existing mutex for
// destructive upgrade work; the loser YIELDS loudly and touches nothing
// (the winner owns the row; the loser's caller re-evaluates on its next
// pass — install re-detects into a live-upgrade refusal, the service
// retries next tick). acquireFlock truncates the flag file only AFTER
// winning, so a losing attempt never clobbers the holder's record.
//
// Callers are all PRE-ACQUIRE — the in-process failure path
// (resumeNewSb → applyNewSbUpgrading → newSbUpgradingFailure → rollback) already
// holds the flock and must NOT route through here: a second flock on the
// same file fails even within one process (see
// TestUpdateFlagNewSbSwapped_RewritesInPlace). The d.flagLock != nil guard
// fails fast if that wiring ever drifts.
func (d *Service) recoveryRollback(ctx context.Context, flag UpgradeFlag, displayName, logRelPath, reason string) {
	id := flag.ID

	if d.flagLock != nil {
		// Mis-wiring: recoveryRollback is the PRE-ACQUIRE recovery wrapper;
		// an in-process caller that already holds the flock must call
		// d.rollback directly (newSbUpgradingFailure does). Proceeding would
		// self-deadlock on the second flock — fail loud instead.
		fmt.Fprintf(os.Stderr,
			"recoveryRollback: called while already holding the upgrade flock (id=%d) — in-process failures must route via newSbUpgradingFailure/rollback, not recoveryRollback; refusing to proceed\n", id)
		return
	}
	lock, lerr := acquireFlock(d.projDir, flag)
	if lerr != nil {
		// Another recovery actor (service tick, concurrent install, or a
		// respawned unit) holds the destructive-work mutex. Yield — it owns
		// the row; racing it was the corruption this gate exists to prevent.
		fmt.Printf("recoveryRollback: upgrade flock held by another recovery actor — yielding (id=%d): %v\n", id, lerr)
		return
	}
	// Hand the lock to the Service so rollback()'s existing terminal
	// machinery (removeUpgradeFlag on success / keep-flag on failed write)
	// releases it uniformly; process exit releases it at the kernel level
	// on every other path.
	d.flagLock = lock

	// STATBUS-044 comment #6 (architect F1) — a PARKED row must never be rolled back.
	// This is the single chokepoint for that guarantee: recoveryRollback is reached
	// by EVERY automatic-restore route (recoverFromFlag's positively-Behind arm, both
	// Unknown-exhaust arms, and the flagless completeInProgressUpgrade path). Once
	// RecoveryBudgetGuard parks a Resuming-phase row (and skips the boot migrate), the
	// skipped migrations can leave observed state Behind — without this check that would
	// AUTO-RESTORE the very row we just sirened as parked. Park stays park until a
	// DELIBERATE operator trigger (./sb install un-parks into the careful routing,
	// which can then roll a genuinely-behind box back). Skip → release the flock but
	// KEEP the flag on disk (parked rows keep their flag) → alive-idle. FAIL-OPEN on a
	// read error (42703 bootstrap: a pre-migrate schema has no recovery_parked_at, so
	// the row cannot be parked — proceed with the rollback).
	parked, parkReason, perr := d.upgradeParkedReason(ctx, id)
	if parkStateUnknown(perr) {
		// UNKNOWN => treat as parked. This path RESTORES; proceeding without
		// knowing would rewind a live park's columns and silently un-park the
		// row into the failure it stopped at (STATBUS-229's shape).
		parked = true
		parkReason = fmt.Sprintf("park state UNKNOWN — the read failed (%v); refusing to restore on an unverified row", perr)
	} else if perr != nil {
		log.Printf("recoveryRollback: recovery_parked_at does not exist for upgrade %d (%v) — the row CANNOT be parked on this schema, so the rollback proceeds on knowledge, not on a guess", id, perr)
	}
	if parked {
		log.Printf("recoveryRollback: upgrade %d is PARKED (%s) — refusing the automatic rollback; the row stays parked and the unit alive-idle. Re-trigger the upgrade or run ./sb install to make a fresh deliberate attempt.", id, parkReason)
		d.flagLock = nil
		lock.Close() // release the flock; leave the flag file on disk (parked rows keep it)
		return
	}

	// STATBUS-046 slice 1B — the rollback-pipeline resume budget. A rollback that
	// crash-loops (watchdog kill mid-restore, OOM, reboot) must not re-run forever
	// any more than the forward path may. The counter is SHARED and never reset at
	// the forward→rollback handoff; but the rollback TERMINAL is NOT the forward
	// exhaust (architect pin): a Phase-1 budget-exhaust ROUTES here, so terminating
	// on the shared count would insta-restore-broke the first rollback resume. The
	// ONLY budget-side rollback terminal is SAME-STEP-TWICE via the single
	// StepRollback marker — computed by the sibling rollbackResumeIsTerminal, NEVER
	// resumeEscalation (whose exhaust must not fire here). Terminal → restore-broke
	// HUMAN stop (state='failed'; ./sb install), NOT park, NOT another rollback
	// (pin 3). git-restore-fail — the genuine restore failure — stays inside
	// rollback() itself; this bounds the CRASH loop (net: 3 forward + 2 rollback).
	//
	// STATBUS-044 comment #6: count ONCE per pass. When RecoveryBudgetGuard already
	// counted this pass at boot (a Resuming→Behind pass, where the forward guard ran
	// before observed state routed here), reuse its count rather than double-count.
	// A PreSwap→rollback pass (guard is a no-op — PreSwap is not a forward flag) still
	// increments here, exactly as before. rollbackResumeIsTerminal is UNCHANGED: the
	// guard's StepBootMigrate stamp is non-rollback, so the first rollback resume stays
	// free by construction.
	attempts, aerr := d.countRecoveryAttemptOnce(ctx, id)
	if aerr != nil {
		log.Printf("recoveryRollback: could not increment recovery_attempts for %d (%v) — continuing", id, aerr)
	}
	if rollbackResumeIsTerminal(flag.Step, flag.PriorDeathStep) {
		// STATBUS-240: ONE terminal, TWO routes, and until now one label for
		// both. On the POST-SWAP route the label is TRUE — a restore genuinely
		// ran and did not complete. On the PRESWAP route it lied three times:
		// no restore was ever attempted (the volume was never touched), the
		// system is not degraded (the same log shows the install ladder
		// completing and the box healthy), and the operator was sent to support
		// for something they can self-serve. For an unattended box in a
		// statistical office that converts a self-serviceable state into a
		// support ticket measured in days.
		//
		// THE DISCRIMINATOR IS THE FLAG, not a remembered variable (the
		// STATBUS-241 rule): IsServiceNewSbRecovery is the single predicate
		// every other site already uses to tell "the binary was swapped" from
		// "nothing moved", and the flag is the authoritative carrier across
		// exactly this gap.
		msg := preSwapStoppedMessage(attempts)
		label := "STOPPED-UNCHANGED"
		if flag.IsServiceNewSbRecovery() {
			msg = fmt.Sprintf("%s: rollback could not complete — two consecutive crash-deaths during rollback (recovery attempt %d). The system is in a degraded state; manual CLI recovery is required (%s); contact SSB support and involve your IT staff.",
				ErrRollbackDBRestore, attempts, INSTALL_CMD)
			label = "RESTORE-BROKE"
		}
		log.Printf("recoveryRollback: %s upgrade %d after %d attempt(s) — two consecutive rollback deaths", label, id, attempts)
		if d.writeRollbackTerminal(id,
			"UPDATE public.upgrade SET state = 'failed', error = $1, recovery_attempts = $2"+terminalBackupPathSQL+" WHERE id = $3"+upgradeRowReturning,
			msg, LabelFailedRollbackIncomplete, attempts) {
			_ = d.removeUpgradeFlag()
		} else {
			d.releaseUpgradeFlagLockKeepingFile()
		}
		hostname, _ := os.Hostname()
		d.runCallback(displayName, map[string]string{
			"STATBUS_EVENT":           "rollback_failed", // STATBUS-137 (LabelFailedRollbackIncomplete)
			"STATBUS_ROLLBACK_FAILED": "1",
			"STATBUS_ROLLBACK_ERROR":  msg,
			"STATBUS_RECOVERY_CMD":    fmt.Sprintf(`ssh %s "cd statbus && ./sb install"`, hostname),
		})
		return
	}
	// COMMIT to the rollback: ROLL the death history — PriorDeathStep←(current
	// flag.Step), Step←StepRollback (recordRollbackCommit). On the forward→rollback
	// handoff PriorDeathStep naturally receives the FORWARD step (never
	// StepRollback), so the first rollback resume is free BY CONSTRUCTION and the
	// rollback gets its designed idempotent re-run (architect (a), no special
	// case). Only after TWO consecutive mid-rollback deaths does PriorDeathStep
	// also become StepRollback → the next resume terminals to restore-broke.
	d.recordRollbackCommit()

	// STATBUS-077: single source of truth = the pinned `pre-upgrade` branch
	// (executeUpgrade pins it before destructive steps). Resolve unconditionally
	// via restoreTargetSHA="" -> restoreGitStateFn's pre-upgrade fallback. NEVER
	// d.version (a CommitVersion = the TARGET in a HEAD-recovery; STATBUS-061).
	restoreTargetSHA := ""

	// Reopen the per-upgrade log in append mode so the rollback narrative
	// continues the existing file. AppendProgressLog returns nil when the
	// file is gone; in that case open a fresh log so rollback() has a
	// writable channel for its progress.Write calls.
	rollbackLog := AppendProgressLog(d.projDir, logRelPath)
	if rollbackLog == nil {
		rollbackLog = NewUpgradeLog(d.projDir, int64(id), displayName, time.Now().UTC())
	}
	defer rollbackLog.Close()

	d.rollback(ctx, id, displayName, restoreTargetSHA, reason, flag.BackupPath, rollbackLog)
}

// completeInProgressUpgrade checks for an upgrade that was started but not
// completed (e.g., service restarted after self-update). If found, verifies
// health and marks completed_at. This ensures "completed" truly means
// the new version is running and verified.
func (d *Service) completeInProgressUpgrade(ctx context.Context) {
	var id int
	var commitSHA string
	var displayName string
	var rowBackupPath sql.NullString
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, commit_sha,
		        COALESCE(commit_tags[array_upper(commit_tags, 1)], left(commit_sha, 8)) as display_name,
		        backup_path
		 FROM public.upgrade
		 WHERE state = 'in_progress'
		 LIMIT 1`).Scan(&id, &commitSHA, &displayName, &rowBackupPath)
	if err != nil {
		return // no in-progress upgrade
	}

	// STATBUS-135 — PARKED-SKIP, before the defer arms. A parked row is
	// state='in_progress' by design, so the SELECT above matches it. This routine
	// has zero parked awareness and would (a) STRIP THE FLAG via the unconditional
	// defer below — violating "parked rows keep their flag" and leaving the next
	// boot flag-blind (RecoveryBudgetGuard no-op → ungated boot-migrate boot-loop),
	// and (b) for a parked AT-TARGET row whose app containers are broken, mark it
	// 'completed' on passing binary+migrations+db-health checks — a silent lie that
	// un-parks by a non-deliberate path. Skip both: leave the flag on disk and the
	// row untouched (a parked row un-parks ONLY via a deliberate operator trigger).
	// Placed BEFORE the defer so `return` here never strips the flag. FAIL-OPEN on a
	// read error (42703 bootstrap, service.go:5792-5804 rationale verbatim): a
	// pre-migrate schema has no recovery_parked_at, so the row cannot be parked —
	// proceed with the normal reconciliation.
	parked, parkReason, perr := d.upgradeParkedReason(ctx, id)
	if parkStateUnknown(perr) {
		// Same hazard as recoveryRollback: this routine can reach d.rollback,
		// so an unverified row must not be reconciled.
		parked = true
		parkReason = fmt.Sprintf("park state UNKNOWN — the read failed (%v); refusing to reconcile an unverified row", perr)
	} else if perr != nil {
		log.Printf("completeInProgressUpgrade: recovery_parked_at does not exist for upgrade %d (%v) — the row CANNOT be parked on this schema, so reconciliation proceeds on knowledge, not on a guess", id, perr)
	}
	if parked {
		log.Printf("completeInProgressUpgrade: upgrade %d is PARKED (%s) — skipping reconciliation; the flag stays on disk and the row stays parked/in_progress. Re-trigger the upgrade or run ./sb install to make a fresh deliberate attempt.", id, parkReason)
		return
	}

	// Guarantee flag cleanup on every exit path of this recovery routine.
	// The explicit removeUpgradeFlag() at the end of the happy path
	// (post-completed-UPDATE) remains — this defer only fires if that path
	// was not reached, e.g. the post-restart DB health check failed or a
	// terminal-state UPDATE persistently errored. Without it, a stale flag
	// survives the crash-recovery attempt and the next `./sb install`
	// misclassifies the state as StateCrashedUpgrade instead of reaching
	// the step-table that reinstalls the upgrade service.
	// removeUpgradeFlag is idempotent: nil flagLock falls through to
	// os.Remove, and a second invocation after the explicit call is a
	// harmless no-op.
	//
	// STATBUS-192: the serve-proof start/health-fail PARK path (below) materializes a
	// faithful flag so `./sb install` can un-park it — that flag MUST survive this
	// defer. parkedExit is set true on that path and is the truth of THIS pass; do NOT
	// re-read park state here (a failed read would default wrong). 135's principle:
	// parked rows keep their flag.
	parkedExit := false
	defer func() {
		if !parkedExit {
			_ = d.removeUpgradeFlag()
		}
	}()

	// Append recovery narrative to the prior run's progress log so the
	// on-disk log (served via /upgrade-logs/<name>) captures both the
	// pre-crash lines and the post-restart verification summary.
	logRelPath := d.loadLogRelPath(ctx, int64(id))
	appendLog := AppendProgressLog(d.projDir, logRelPath)
	if appendLog != nil {
		defer appendLog.Close()
	}
	logRecover := func(format string, args ...interface{}) {
		if appendLog != nil {
			appendLog.Write(format, args...)
		} else {
			fmt.Printf(format+"\n", args...)
		}
	}

	logRecover("Service restarted. Found in-progress upgrade to %s, verifying...", displayName)

	// Verify services are healthy
	if err := d.waitForDBHealth(30 * time.Second); err != nil {
		logRecover("Post-restart health check failed for %s: %v", displayName, err)
		// Close so post-restart lines are on disk before the bundle
		// reads them; bundle BEFORE the terminal UPDATE.
		if appendLog != nil {
			appendLog.Close()
		}
		d.writeDiagnosticBundle(ctx, int(id), appendLog)
		appendLog = nil
		failedSQL := "UPDATE public.upgrade SET state = 'failed', error = $1 WHERE id = $2" + upgradeRowReturning
		errStr := fmt.Sprintf("%s: post-restart health check failed: %v", ErrHealthcheckDBDown, err)
		var failedJSON string
		var scanErr error
		for attempt := 0; attempt < 4; attempt++ {
			scanErr = d.queryConn.QueryRow(ctx, failedSQL, errStr, id).Scan(&failedJSON)
			if scanErr == nil {
				logUpgradeRow(LabelFailed, failedJSON)
				break
			}
			if attempt < 3 && isConnError(scanErr) {
				time.Sleep(retryBackoff(attempt + 1))
				continue
			}
			// C3: POST_RESTART_FAILED_TRANSITION_PERSISTED — bounded retry
			// exhausted. Row was just in_progress, no concurrent writer, CHECK
			// permits in_progress → failed with non-null error. Persistent
			// failure is bug-class.
			fmt.Fprintf(os.Stderr,
				"INVARIANT POST_RESTART_FAILED_TRANSITION_PERSISTED violated: state transition to failed matched 0 rows or errored (id=%d, err=%v) after %d attempts (service.go:%d, pid=%d)\n",
				id, scanErr, attempt+1, thisLine(), os.Getpid())
			d.markTerminal("POST_RESTART_FAILED_TRANSITION_PERSISTED",
				fmt.Sprintf("id=%d; final Scan err=%v; attempts=%d", id, scanErr, attempt+1))
			d.writeDiagnosticBundle(ctx, int(id), nil)
			break
		}
		return
	}

	// Observed-state verification (task #49). The row is about to be marked
	// completed because the DB is healthy after restart — but "DB healthy"
	// doesn't prove the upgrade actually finished. A crash between
	// writeUpgradeFlag and binary swap leaves the DB perfectly healthy
	// while the binary is still the OLD version and the new migrations
	// are unapplied. Marking completed in that state is a silent lie in
	// the operator-facing history.
	//
	// Two checks:
	//   1. Binary SHA == row.commit_sha — the running binary IS the one
	//      the upgrade was supposed to deliver.
	//   2. db.migration's max version >= on-disk max migration — all
	//      migrations that the current tree expects are applied.
	//
	// Tri-state disposition (STATBUS-039, the transactional model):
	//   - Behind (positively verified): invoke d.rollback() — restores
	//     git/DB/binary/services to the previous version using THIS row's
	//     own snapshot (identity-keyed) and marks state='rolled_back'. The
	//     alternative — just marking state='failed' — would leave the
	//     system in a half-broken state that contradicts the row's claim.
	//   - Unknown (DB unreachable mid-check): destroying state under
	//     uncertainty is forbidden. Leave the row in_progress, log loud,
	//     return — the next recovery pass re-checks.
	//   - AtTarget: fall through to the mark-completed path below.
	obsState, _, reason := d.verifyUpgradeObservedStateEx(ctx, commitSHA)
	if obsState == ObservedPositionUnreadable {
		logRecover("Ground-truth UNVERIFIABLE for %s: %s — leaving row in_progress (no restore under uncertainty); next recovery pass re-checks.", displayName, reason)
		return
	}
	if obsState == ObservedCannotReachNew {
		logRecover("Ground-truth verification FAILED for %s: %s", displayName, reason)
		if appendLog != nil {
			appendLog.Close()
			appendLog = nil
		}
		// Flagless recovery: synthesize a faithful flag record for the
		// flock gate (the file on disk is absent here — acquireFlock
		// creates it as the destructive-work mutex and rollback's terminal
		// machinery removes it). Phase stays "" (PreSwap, the
		// least-claiming value); BackupPath carries the row's recorded
		// snapshot — the restore identity. Trigger "recovery" is a
		// documented coarse bucket on the flag schema.
		d.recoveryRollback(ctx, UpgradeFlag{
			ID:         id,
			CommitSHA:  commitSHA,
			StartedAt:  time.Now(),
			InvokedBy:  "recovery:completeInProgressUpgrade",
			Trigger:    "recovery",
			Holder:     HolderService,
			Phase:      PhaseOldSbUpgrading,
			BackupPath: rowBackupPath.String,
		}, displayName, logRelPath, fmt.Sprintf(
			"%s: observed-state check after service restart failed: %s",
			ErrInstallPreconditionFailed, reason))
		return
	}

	// STATBUS-192 — SERVE-PROVEN completed. At-target (binary + migrations, verified
	// above) is necessary but NOT sufficient: the STATBUS-160 doctrine is that
	// 'completed' means THIS VERSION VERIFIABLY SERVES, at EVERY writer including this
	// flagless self-heal. A flagless-state producer (corrupt-flag removal, tmp/ flag
	// loss) can land at a pre-StartServices point — app/worker/rest DOWN while
	// binary+migrations sit at target. The old code marked 'completed' on DB-health +
	// at-target alone, certifying a dark box (and STATBUS-170's poll inherits the lie).
	// Run the SAME tail applyNewSbUpgrading runs: app set up → app health gate →
	// maintenance off → completed → read-only-window lift (STATBUS-192 refinement 1).
	restoreTargetSHA := "" // at-target; a Behind rollback (ruled out above) is its only use

	// The tail + its dispositions write to a progress log unconditionally; ensure one
	// exists even if AppendProgressLog returned nil (missing on-disk log), mirroring
	// resumeNewSb's fallback. Kept OPEN through the completed write + window flip so the
	// whole serve-proof narrative reaches the on-disk log served at /upgrade-logs
	// (STATBUS-192 build note a). The deferred Close (armed above, or here) closes it.
	if appendLog == nil {
		appendLog = NewUpgradeLog(d.projDir, int64(id), displayName, time.Now().UTC())
		defer appendLog.Close()
	}

	// parkAtTarget is the start/health-fail disposition (STATBUS-192 refinement 2):
	// materialize a FAITHFUL flag BEFORE parking so `./sb install` can un-park it. A
	// row-only park (parkUpgrade) from THIS flagless caller would be invisible to the
	// install ladder — UnparkByID is reachable only via StateCrashedUpgrade (flag
	// present) — yet parkForDeterministicFailure's operator message promises "./sb
	// install for a fresh attempt". Phase=PhaseNewSbSwapped is the at-target truth →
	// next boot's recoverFromFlag routes to resumeNewSb, whose parked-skip holds the
	// unit alive-idle with the flag kept. Written DIRECTLY (no acquireFlock: the flock
	// is the destructive-work mutex and this pass is going idle; flag-present +
	// flock-free is exactly the un-parkable shape, and install quiesces the unit before
	// takeover). Order: flag FIRST, then park the row — a crash between the two leaves
	// an ordinary crashed-upgrade, never the invisible row-only shape. A flag-write
	// failure (ENOSPC is itself a live park cause) does NOT block the park: warn that
	// install-un-park is unavailable (a fix-release schedule remains the trigger) and
	// park anyway.
	parkAtTarget := func(reason string) {
		flag := UpgradeFlag{
			ID:         id,
			CommitSHA:  commitSHA,
			StartedAt:  time.Now(),
			InvokedBy:  "recovery:completeInProgressUpgrade",
			Trigger:    "recovery",
			Holder:     HolderService,
			Phase:      PhaseNewSbSwapped,
			BackupPath: rowBackupPath.String,
		}
		_ = os.MkdirAll(filepath.Dir(d.flagPath()), 0755)
		if data, merr := json.MarshalIndent(flag, "", "  "); merr != nil {
			logRecover("WARNING: could not marshal the recovery flag before parking %s (%v) — `./sb install` un-park is UNAVAILABLE for this park; schedule a fix release to retrigger. Parking anyway.", displayName, merr)
		} else if werr := os.WriteFile(d.flagPath(), data, 0644); werr != nil {
			logRecover("WARNING: could not write the recovery flag before parking %s (%v) — `./sb install` un-park is UNAVAILABLE for this park; schedule a fix release to retrigger. Parking anyway.", displayName, werr)
		} else {
			parkedExit = true // the defer must NOT strip this flag (STATBUS-192/135)
		}
		_ = d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, rowBackupPath.String, reason, appendLog)
	}

	// STATBUS-192 MUST-FIX 1 — WATCHDOG COVER for the serve-proof tail. This runs in the
	// daemon's ACTIVE phase under WatchdogSec=120 (READY=1 fired before recoverFromFlag,
	// :2222). Subprocess output only bump()s the progress gate (PrefixWriter onLine); it
	// never sd_notify. A `--no-build` compose that pulls images pruned since the crash can
	// stay >120s between our explicit Write()s → the daemon SIGKILLs the heal mid-flight →
	// StartLimit loop → dark box. Wrap the tail (compose + health) in the SAME gated
	// ticker applyNewSbUpgrading uses (:5874): it pings WATCHDOG=1 while the gate is open
	// (real progress) and goes quiet on a true stall (the 5-min command timeout then
	// bounds it → forward retry — the gate closing on a real hang IS the watchdog
	// working). Cancel+join via ONE deferred closure — every post-ticker path returns from
	// the function, so the Run() no-defer rationale at :2038 does not apply here.
	appendLog.bump() // gate-open on entry (structural, matches applyNewSbUpgrading :5872)
	healTickerCtx, healTickerCancel := context.WithCancel(ctx)
	healTickerDone := make(chan struct{})
	go runGatedWatchdogTicker(healTickerCtx, appendLog,
		applyNewSbUpgradingStallThreshold, applyNewSbUpgradingWatchdogCadence,
		func() { sdNotify("WATCHDOG=1") }, healTickerDone)
	defer func() {
		healTickerCancel()
		<-healTickerDone
	}()

	if reason := d.diskPrecheckReason(StepStartServices); reason != "" {
		parkAtTarget(reason)
		return
	}
	logRecover("At-target verified; starting application services to prove %s serves...", displayName)
	composeArgs := append([]string{"compose", "up", "-d", "--no-build"}, step11RestartServices...)
	if stderrTail, cerr := runCommandToLogCapture(d.projDir, 5*time.Minute, appendLog.File(), "docker-compose", appendLog.bump, "docker", composeArgs...); cerr != nil {
		// STATBUS-192 refinement 3: mirror applyNewSbUpgrading's three-way
		// (service.go:6074-6093). ENOSPC (classResource) → park; anything else →
		// newSbUpgradingFailure, which AT-TARGET reduces to recordInProgressFailure (row
		// stays in_progress, forward retry on the next tick/boot) — never a completed
		// lie, never a hand-rolled disposition. (The diskPrecheck park above is the
		// class-C primary; this is the in-flight ENOSPC backstop.)
		if classifyDockerFailure(cerr, stderrTail) == classResource {
			parkAtTarget(fmt.Sprintf("disk full starting services at %s (no space left on device) — free disk space, then re-trigger the upgrade", displayName))
			return
		}
		_ = d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, rowBackupPath.String,
			fmt.Sprintf("%s: could not start the application at %s during flagless recovery: %v", ErrDockerUpFailed, displayName, cerr), appendLog)
		return
	}
	if hcErr := d.healthCheck(appendLog, 5, 5*time.Second); hcErr != nil {
		parkAtTarget(fmt.Sprintf("%s: the application cannot serve at %s past warmup after flagless recovery — %v; fix the cause, then re-trigger the upgrade", ErrHealthcheckRESTDown, displayName, hcErr))
		return
	}
	if err := d.setMaintenance(false, ""); err != nil {
		parkAtTarget(fmt.Sprintf("maintenance mode could not be lifted after %s passed its serving health check: %v; fix the maintenance flag path or permissions, then re-trigger the upgrade", displayName, err))
		return
	}

	// error = NULL: chk_upgrade_state_attributes forbids a non-NULL error on
	// completed, and recordInProgressFailure may have stamped one during an
	// earlier forward-retry pass (STATBUS-039). Completing resolves it; the
	// full narrative survives in the on-disk progress log.
	// STATBUS-081: log_relative_file_path = COALESCE(...) — chk_upgrade_state_attributes
	// requires it NOT NULL on completed. Real upgrades are stamped at claim time
	// (LOG_POINTER_STAMPED invariant) so $2 is a no-op fallback for legacy NULL rows only.
	completedSQL := "UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready', error = NULL, log_relative_file_path = COALESCE(log_relative_file_path, $2) WHERE id = $1" + upgradeRowReturning
	// STATBUS-154: teardown-immune completed write (fresh daemon-tagged conn +
	// context.Background + bounded retry). Best-effort — on failure it marks the
	// invariant + bundle and continues to cleanup (removeUpgradeFlag etc.), as
	// before; the row stays in_progress for the next pass.
	fromInProgressJSON, scanErr := d.terminalUpdate(completedSQL, id, appendLog.RelPath())
	completionRecorded := scanErr == nil
	finishingClean := completionRecorded
	if scanErr == nil {
		logUpgradeRow(LabelCompletedFromInProgress, fromInProgressJSON)
		d.deleteRollbackBinaryOnCompletion() // STATBUS-197 C3: swap resolved → ./sb.old must not linger
	} else if dbName := d.markPgInvariantTerminal(scanErr, "service.go:completeInProgressUpgrade:completed"); dbName != "" {
		// C4: DB-enforced invariant → prefer the specific name in the bundle.
		d.writeDiagnosticBundle(ctx, int(id), nil)
	} else {
		fmt.Fprintf(os.Stderr,
			"INVARIANT POST_RESTART_COMPLETED_TRANSITION_PERSISTED violated: state transition to completed matched 0 rows or errored (id=%d, err=%v) (service.go:%d, pid=%d)\n",
			id, scanErr, thisLine(), os.Getpid())
		d.markTerminal("POST_RESTART_COMPLETED_TRANSITION_PERSISTED",
			fmt.Sprintf("id=%d; final err=%v", id, scanErr))
		d.writeDiagnosticBundle(ctx, int(id), nil)
	}

	// STATBUS-192 refinement 1: lift the read-only window. It engaged at step 2
	// (service.go:5305) and every flagless at-target orphan carries it ON; a 'completed'
	// box that still rejects every write with 25006 is "a broken box masquerading as
	// healthy" (:6209). This flip runs REGARDLESS of the completed-write outcome above —
	// a DELIBERATE divergence from applyNewSbUpgrading, which returns on a completed-write
	// failure (:6168): this routine's contract is continue-to-cleanup (the completed-write
	// failure already escalated loudly and the tick-belt at :2312 retries it next pass),
	// and the box is SERVING now, so holding an NSO's registry read-only over a
	// bookkeeping write would be the wrong trade. When the completed UPDATE DID land it is
	// senior truth and the flip simply follows it. This flagless belt has no backstop
	// after :2312, so the escalation is the signal. terminalExec is the teardown-immune
	// fresh-conn writer.
	if _, werr := d.liftReadOnlyWindow("flagless-recovery completion"); werr != nil {
		finishingClean = false
		fmt.Fprintf(os.Stderr,
			"INVARIANT COMPLETION_READ_ONLY_WINDOW_LIFTED violated: the read-only window did not lift at flagless-recovery completion after %d attempts (err=%v) — the database default is still read-only, so every fresh non-exempt session fails with 25006 (read_only_sql_transaction). Remedy: run `./sb install` to clear it (or the daemon's boot backstop clears it on the next start). (service.go:%d, pid=%d)\n",
			terminalWriteMaxAttempts, werr, thisLine(), os.Getpid())
		d.markTerminal("COMPLETION_READ_ONLY_WINDOW_LIFTED",
			fmt.Sprintf("window OFF flip failed at flagless-recovery completion after retries: %v; DB default still read-only; ./sb install clears it", werr))
		logRecover("FATAL: read-only window did NOT lift at completion (%v) — the box rejects external writes until `./sb install` clears it.", werr)
	}

	if err := d.removeUpgradeFlag(); err != nil {
		finishingClean = false
		logRecover("FATAL: the upgrade lock did NOT release at flagless-recovery completion (%v) — run `./sb install` to reconcile it.", err)
	}
	// Layer 3 of the rollback-on-SIGKILL hole plug — also fire pruneBackups
	// after the post-restart completion path. See the matching call in the
	// resumeNewSb branch for full rationale. keep=3.
	d.pruneBackups(ctx, 3)

	// Skip older releases that are still "available" — no point upgrading to an older version
	d.supersedeOlderReleases(ctx, commitSHA)
	d.supersedeCompletedPrereleases(ctx, commitSHA)
	if finishingClean {
		d.runUpgradeCallback(displayName)
		logRecover("Upgrade to %s complete (verified serving after flagless recovery).", displayName)
	} else if completionRecorded {
		logRecover("Upgrade to %s was recorded as successful, but flagless-recovery finishing did not complete; see the failed step(s) above.", displayName)
	} else {
		logRecover("Upgrade to %s was not recorded as complete; automatic reconciliation will retry the database transition.", displayName)
	}
}

// syncConfigToSystemInfo writes UPGRADE_* values from .env to system_info.
// This keeps the admin UI in sync with the config file.
func (d *Service) syncConfigToSystemInfo(ctx context.Context) {
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: cannot load .env for system_info sync: %v\n", err)
		return
	}

	keys := []string{"upgrade_channel", "upgrade_check_interval", "upgrade_auto_download"}
	envKeys := []string{"UPGRADE_CHANNEL", "UPGRADE_CHECK_INTERVAL", "UPGRADE_AUTO_DOWNLOAD"}

	for i, key := range keys {
		if v, ok := f.Get(envKeys[i]); ok {
			if _, err := d.queryConn.Exec(ctx,
				`INSERT INTO public.system_info (key, value, updated_at)
				 VALUES ($1, $2, clock_timestamp())
				 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp()`,
				key, v); err != nil {
				fmt.Fprintf(os.Stderr, "warning: failed to sync %s to system_info: %v\n", key, err)
			}
		}
	}
}

// reportDiskSpace writes the current free disk space to system_info.
func (d *Service) reportDiskSpace(ctx context.Context) {
	if err := d.ensureConnected(ctx); err != nil {
		return
	}
	if freeBytes, err := DiskFree(d.projDir); err == nil {
		freeGB := freeBytes / (1024 * 1024 * 1024)
		// Best-effort; a periodic informational report (admin UI display),
		// not load-bearing for any decision logic — self-corrects next cycle.
		_ = d.execObserved(ctx, "reportDiskSpace: record disk_free_gb",
			`INSERT INTO public.system_info (key, value, updated_at)
			 VALUES ('disk_free_gb', $1::text, clock_timestamp())
			 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp()`,
			fmt.Sprintf("%d", freeGB))
	}
}

// supersedeOlderReleases marks available releases older than the selected commit as superseded.
// Ordering is by topological_order then committed_at as fallback.
func (d *Service) supersedeOlderReleases(ctx context.Context, selectedCommitSHA string) {
	// Call the shared SQL procedure — single source of truth for both
	// the service (pgx) and the step-table install path (psql).
	var superseded int
	err := d.queryConn.QueryRow(ctx,
		"CALL public.upgrade_supersede_older($1, 0)",
		selectedCommitSHA).Scan(&superseded)
	if err != nil {
		fmt.Printf("Failed to supersede older releases: %v\n", err)
		return
	}
	if superseded > 0 {
		fmt.Printf("Superseded %d older release(s)\n", superseded)
	}
}

// supersedeCompletedPrereleases supersedes older completed prereleases in the
// same version family when a prerelease completes. Safe to call for any row —
// the procedure is a no-op for non-prereleases.
func (d *Service) supersedeCompletedPrereleases(ctx context.Context, commitSHA string) {
	var superseded int
	err := d.queryConn.QueryRow(ctx,
		"CALL public.upgrade_supersede_completed_prereleases($1, 0)",
		commitSHA).Scan(&superseded)
	if err != nil {
		fmt.Printf("Failed to supersede completed prereleases: %v\n", err)
		return
	}
	if superseded > 0 {
		fmt.Printf("Superseded %d completed prerelease(s) in same family\n", superseded)
	}
}

func (d *Service) loadConfig() error {
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return err
	}

	if v, ok := f.Get("UPGRADE_CHANNEL"); ok {
		d.channel = v
	} else {
		// STATBUS-307: config generate writes this key unconditionally into .env,
		// deriving it from CADDY_DEPLOYMENT_MODE unless .env.config declares one.
		// So its absence means .env was hand-edited or is stale — and a daemon
		// that quietly assumes "stable" here is the same invisible-wrong-channel
		// failure this design exists to remove, just moved one layer down.
		//
		// It still starts: a box with no upgrade service is worse than one on a
		// conservative channel. But it says so, loudly, naming the fix.
		d.channel = "stable"
		fmt.Fprintf(os.Stderr, "WARN: UPGRADE_CHANNEL is missing from .env — assuming %q.\n"+
			".env is a GENERATED file; run `./sb config generate` to rewrite it. The channel\n"+
			"is derived from CADDY_DEPLOYMENT_MODE in .env.config, unless that file declares an\n"+
			"explicit UPGRADE_CHANNEL. Until then this service may be following a channel this\n"+
			"box was never meant to follow.\n", d.channel)
	}

	intervalStr := DefaultPollInterval.String()
	if v, ok := f.Get("UPGRADE_CHECK_INTERVAL"); ok {
		intervalStr = v
	}
	d.interval, err = time.ParseDuration(intervalStr)
	if err != nil {
		d.interval = DefaultPollInterval
	}

	d.autoDL = true
	if v, ok := f.Get("UPGRADE_AUTO_DOWNLOAD"); ok {
		d.autoDL = v == "true"
	}

	// Scheduled logical-backup settings (STATBUS-113). Default ON with a 24h
	// cadence and 7-dump retention; a malformed interval/count falls back to the
	// default rather than disabling the safety net.
	d.backupEnabled = true
	if v, ok := f.Get("BACKUP_ENABLED"); ok {
		d.backupEnabled = v != "false"
	}
	d.backupInterval = 24 * time.Hour
	if v, ok := f.Get("BACKUP_INTERVAL"); ok {
		if dur, perr := time.ParseDuration(v); perr == nil && dur > 0 {
			d.backupInterval = dur
		}
	}
	d.backupRetention = 7
	if v, ok := f.Get("BACKUP_RETENTION_COUNT"); ok {
		if n, perr := strconv.Atoi(v); perr == nil && n >= 0 {
			d.backupRetention = n
		}
	}

	return nil
}

// loadTrustedSigners reads UPGRADE_TRUSTED_SIGNER_* keys from .env and
// writes an allowed-signers file for git verify-commit.
// Signing enforcement: if keys are configured, verification is enforced at
// upgrade time (#114). If no keys, the service starts but upgrades refuse to
// execute until at least one signer is added.
func (d *Service) loadTrustedSigners() error {
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return fmt.Errorf("load .env for signers: %w", err)
	}

	// Collect trusted signers
	var signerLines []string
	for _, key := range f.Keys() {
		if !strings.HasPrefix(key, "UPGRADE_TRUSTED_SIGNER_") {
			continue
		}
		name := strings.TrimPrefix(key, "UPGRADE_TRUSTED_SIGNER_")
		val, _ := f.Get(key)
		if val == "" {
			continue
		}
		// Log each signer with fingerprint
		cmd := exec.Command("ssh-keygen", "-l", "-f", "/dev/stdin")
		cmd.Stdin = strings.NewReader(val)
		fpOut, fpErr := cmd.CombinedOutput()
		fingerprint := "unknown"
		if fpErr == nil {
			fingerprint = strings.TrimSpace(string(fpOut))
		}
		fmt.Printf("Trusted signer: %s (%s)\n", name, fingerprint)
		// allowed_signers format: <principal> <key>
		signerLines = append(signerLines, fmt.Sprintf("%s %s", name, val))
	}

	if len(signerLines) == 0 {
		fmt.Println("No trusted signers configured (UPGRADE_TRUSTED_SIGNER_*) — upgrades will refuse to execute until at least one signer is added via: ./sb upgrade trust-key add <github-username>")
		d.allowedSignersPath = ""
		return nil
	}

	// Write allowed-signers file
	tmpDir := filepath.Join(d.projDir, "tmp")
	_ = os.MkdirAll(tmpDir, 0755) // best-effort; the WriteFile right after surfaces any real failure
	allowedSignersPath := filepath.Join(tmpDir, "allowed-signers")
	if err := os.WriteFile(allowedSignersPath, []byte(strings.Join(signerLines, "\n")+"\n"), 0644); err != nil {
		return fmt.Errorf("write allowed-signers: %w", err)
	}
	d.allowedSignersPath = allowedSignersPath

	// Configure git to use the allowed-signers file. If this fails
	// verifyCommitSignature downstream will refuse to verify and the
	// next upgrade that reaches signature verification will fail there
	// with a hard error — so this is a log-only breadcrumb whose primary
	// failure path is owned elsewhere.
	if err := runCommand(d.projDir, "git", "config", "gpg.ssh.allowedSignersFile", allowedSignersPath); err != nil {
		log.Printf("could not set git gpg.ssh.allowedSignersFile: %v", err)
	}

	fmt.Printf("Commit signature verification enabled (%d trusted signer(s))\n", len(signerLines))
	return nil
}

// verifyCommitSignature verifies an SSH signature on a git commit.
// Returns nil if the signature is valid and trusted.
// Returns a hard error when no signers are configured — signature
// verification is mandatory. Operators must run
// `./sb upgrade trust-key add <github-username>` before upgrades work.
func (d *Service) verifyCommitSignature(sha string) error {
	if d.allowedSignersPath == "" {
		return fmt.Errorf("no trusted signers configured — signature verification is mandatory. Run: ./sb upgrade trust-key add <github-username>")
	}

	out, err := runCommandOutput(d.projDir, "git", "-c",
		fmt.Sprintf("gpg.ssh.allowedSignersFile=%s", d.allowedSignersPath),
		"verify-commit", sha)
	if err != nil {
		return fmt.Errorf("commit %s signature verification failed: %s", ShortForDisplay(sha), strings.TrimSpace(out))
	}

	fmt.Printf("Commit %s signature verified: %s\n", ShortForDisplay(sha), strings.TrimSpace(out))
	return nil
}

// connectTimeout bounds the pgx dial+handshake in connect(). connStr sets no
// connect_timeout and callers pass the service-lifetime ctx (no deadline), so
// without this a hung connect would block forever — the latent gap that made
// the applyNewSbUpgrading reconnect unbounded (plan upgrade-resume-structural-whole.md
// piece #3: deferring watchdog gating during reconnect is only safe if reconnect
// is itself bounded). 5 min comfortably exceeds a legitimately slow reconnect
// (scenario 3-postswap-watchdog-reconnect's 180 s synthetic stall) with margin. Package var, not const, so
// tests can shrink it to drive a deterministic hung-connect → DeadlineExceeded
// assertion without a 5-min wait.
var connectTimeout = 5 * time.Minute

// connectAttemptTimeout bounds ONE dial inside connect()'s sub-attempt loop
// (STATBUS-299). connectTimeout above remains the TOTAL budget; this is the
// step size within it.
//
// THE VALUE IS CHOSEN AGAINST WatchdogSec=120s, not picked for roundness. It
// must be comfortably below it so a wedged attempt's silence reaches systemd
// as a missing heartbeat well before the watchdog's own deadline — that is what
// keeps real-hang detection alive INSIDE the covered phase. It must also be
// long enough that a legitimately slow dial (cold container, loaded host) is
// not chopped up into pointless retries.
//
// Package vars, not consts, so tests drive the loop deterministically instead
// of waiting real minutes — the same seam discipline as waitForRestReadyNow.
var (
	connectAttemptTimeout = 30 * time.Second
	connectRetryDelay     = 2 * time.Second
	// connectRetryAfter is the loop's only contact with the passage of time.
	// Held as a var so a test can supply a channel it controls; production code
	// must never assign it, and tests restore it via t.Cleanup.
	connectRetryAfter = time.After
)

// connectOnce performs exactly ONE dial of both connections, bounded by the
// caller's ctx. Extracted from connect() so the sub-attempt loop has a unit to
// repeat; it holds no retry policy of its own on purpose — the budget, the
// pacing and the heartbeat all live in one place above, where they can be read
// together.
func (d *Service) connectOnce(ctx context.Context, config *pgx.ConnConfig) error {
	var err error
	d.listenConn, err = pgx.ConnectConfig(ctx, config)
	if err != nil {
		return fmt.Errorf("listen connection: %w", err)
	}
	d.queryConn, err = pgx.ConnectConfig(ctx, config)
	if err != nil {
		_ = d.listenConn.Close(context.Background())
		d.listenConn = nil
		return fmt.Errorf("query connection: %w", err)
	}
	return nil
}

// recoveryDSN is the SINGLE SOURCE OF TRUTH for how this box reaches its
// database: the TCP-via-Caddy-layer4 route (CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT),
// the production-real path the whole service connects on. STATBUS-143: both
// connect() and the crash-recovery reachability probe (EnsureDBReachable) dial
// THIS exact DSN, so a probe can never again pass against a path the real
// connection doesn't use (the observed severed-proxy dead end, where a
// docker-exec psql probe reached the db container directly while the real pgx
// connection — through the now-absent proxy — refused). The probe follows the
// connection, never the reverse.
//
// The service runs on the host (not inside Docker), so it reaches PostgreSQL
// through Caddy's Layer4 proxy; CADDY_DB_BIND_ADDRESS is where Caddy listens
// (typically 127.0.0.1). Using SITE_DOMAIN would resolve to the public IP, which
// Caddy doesn't listen on in private deployment mode. No fallback defaults — a
// missing key means a broken .env, so we fail loud (actionable) rather than
// silently connect to the wrong place. The password CAN be empty (trust auth).
//
// Per-call .env read is DELIBERATE (not an optimization miss): the crash-recovery
// ladder regenerates .env immediately before probing, so an init-cached DSN would
// dial the stale pre-regen route — a route-skew variant of the very bug this
// function exists to kill. Both callers are low-frequency recovery paths.
func (d *Service) recoveryDSN() (string, error) {
	f, err := dotenv.Load(filepath.Join(d.projDir, ".env"))
	if err != nil {
		return "", err
	}
	requireKey := func(key string) (string, error) {
		if v, ok := f.Get(key); ok && v != "" {
			return v, nil
		}
		return "", fmt.Errorf("%s not found in .env — regenerate with: ./sb config generate", key)
	}
	dbHost, err := requireKey("CADDY_DB_BIND_ADDRESS")
	if err != nil {
		return "", err
	}
	dbPort, err := requireKey("CADDY_DB_PORT")
	if err != nil {
		return "", err
	}
	dbName, err := requireKey("POSTGRES_APP_DB")
	if err != nil {
		return "", err
	}
	dbUser, err := requireKey("POSTGRES_ADMIN_USER")
	if err != nil {
		return "", err
	}
	dbPass, _ := f.Get("POSTGRES_ADMIN_PASSWORD") // password CAN be empty (trust auth)
	// STATBUS-149: tag the session application_name so install.cleanOrphanSessions
	// can tell the daemon's OWN live advisory-lock connection from a genuine
	// zombie. Mirrors migrate.acquireAdvisoryLock's 'statbus-migrate-<pid>'
	// (migrate.go:833). This one DSN feeds both connect()'s d.queryConn +
	// d.listenConn, and thus daemon startup, the inline-dispatch service instance,
	// and every d.reconnect() — so the tag rides every daemon backend. Without it,
	// classifyAdvisoryHolder read the daemon's empty app_name as an unidentified
	// zombie and killed the live lock connection on every sessions-step pass; the
	// daemon reconnected with a fresh (also untagged) backend, self-regenerating
	// the "zombie" until the settle loop's bound tripped. The value has no spaces,
	// so it needs no DSN quoting.
	return fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=disable application_name=statbus-upgrade-daemon-%d",
		dbHost, dbPort, dbName, dbUser, dbPass, os.Getpid()), nil
}

func (d *Service) connect(ctx context.Context) error {
	// STATBUS-143: the DSN comes from the single-source recoveryDSN() — the SAME
	// route the crash-recovery reachability probe (EnsureDBReachable) dials, so a
	// probe-pass implies this connection works by construction.
	connStr, err := d.recoveryDSN()
	if err != nil {
		return err
	}

	// Build a pgx config with aggressive TCP keepalive so a dead peer is
	// detected at the kernel level within ~60s (30s idle + 3 × 10s probes)
	// instead of the ~2h+ kernel default. pgx v5.9.0's default dialer is
	// `&net.Dialer{}` (zero KeepAlive = kernel default TCP_KEEPIDLE=7200)
	// — see cli forensic doc tmp/engineer-dev-hang-meticulous.md §3. This
	// doesn't cure every stale-conn failure (Docker's userland-proxy can
	// absorb keepalive probes), but it reliably catches the common case.
	config, err := pgx.ParseConfig(connStr)
	if err != nil {
		return fmt.Errorf("parse connection string: %w", err)
	}
	config.DialFunc = keepaliveDialer

	// Bound the dial+handshake. connStr sets no connect_timeout and the ctx
	// handed in by callers (e.g. applyNewSbUpgrading's reconnect) is the
	// service-lifetime ctx with NO deadline — so a hung pgx.ConnectConfig
	// (DB-side slow handshake, half-open socket the keepalive dialer can't
	// catch because the conn isn't established yet, a wedged userland-proxy)
	// would block INDEFINITELY. That is the latent gap that made the
	// applyNewSbUpgrading reconnect unbounded; the #3 watchdog defers gating during
	// reconnect (it's a legitimately silent step), which is only SAFE if
	// reconnect is itself bounded — mirroring how the migrate step is bounded
	// by its runCommandToLog timeout. pgx honours a ctx deadline across the
	// WHOLE connect, not just the TCP dial: pgconn's contextWatcher
	// (pgconn.go connectOne → contextWatcher.Watch(ctx)) closes the conn if the
	// deadline fires mid-startup/auth, so a handshake hang is bounded too — not
	// only TCP connect. 5 min comfortably exceeds a legitimately slow
	// reconnect (scenario 3-postswap-watchdog-reconnect holds 180 s) with margin; a genuine hang is killed
	// at 5 min → connect() returns context.DeadlineExceeded → the caller fails
	// out (applyNewSbUpgrading → newSbUpgradingFailure → rollback; task #7 backstops a
	// loop) instead of pinging the watchdog forever.
	connectCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()

	// ── BOUNDED SUB-ATTEMPTS (STATBUS-299) ──────────────────────────────────
	// connectTimeout above is now the TOTAL budget; each individual dial gets
	// connectAttemptTimeout. Patience overall is unchanged — what changes is
	// that the phase is made of steps instead of one opaque wait.
	//
	// WHY THIS EXISTS. A daemon starting while the database is briefly down sat
	// in ONE five-minute dial on the main goroutine. That goroutine carries the
	// steady-state heartbeat deliberately — a separate ticker would keep pinging
	// systemd through a real deadlock and make a hang invisible — so nothing
	// pinged, and systemd's WatchdogSec=120 SIGABRTed a service that was riding
	// out the outage exactly as designed. Two correct designs met at one site
	// and left a ~118-second hole.
	//
	// A HEARTBEAT MUST ATTEST TO PROGRESS, NOT TO THE PASSAGE OF TIME. That is
	// why the ping sits at the ATTEMPT BOUNDARY and nowhere else: a completed
	// attempt is evidence the loop advanced. A timer would ping while wedged,
	// which is the property that makes a watchdog worthless.
	//
	// REAL-HANG DETECTION IS PRESERVED INSIDE THE COVERED PHASE, and that is the
	// point of the per-attempt bound being well under WatchdogSec: an attempt
	// that genuinely wedges below the context layer (a syscall that ignores
	// cancellation) produces no boundary, so no ping, and systemd still kills at
	// 120s. The cover cannot mask the thing it sits next to.
	//
	// IT IS ALSO A BETTER CONNECTION DESIGN ON ITS OWN. A single five-minute
	// attempt takes five minutes to report ANY failure — a wrong password was
	// indistinguishable from a down database for five minutes. Bounded retries
	// surface the first error in seconds while waiting just as long overall.
	var lastErr error
	for attempt := 1; ; attempt++ {
		attemptCtx, attemptCancel := context.WithTimeout(connectCtx, connectAttemptTimeout)
		lastErr = d.connectOnce(attemptCtx, config)
		attemptCancel()
		if lastErr == nil {
			break
		}

		// The attempt finished — that is the progress this heartbeat attests to.
		// Emitted BEFORE the budget check so the final attempt of a failing phase
		// still reports liveness on its way out.
		sdNotify("WATCHDOG=1")

		if connectCtx.Err() != nil {
			return fmt.Errorf("connect: %d attempt(s) within %s budget, last error: %w",
				attempt, connectTimeout, lastErr)
		}
		fmt.Printf("Database connect attempt %d failed (%v) — retrying within the %s budget\n",
			attempt, lastErr, connectTimeout)

		// Brief pause between attempts, bounded by the total budget so a
		// cancelled ctx never waits out the delay. Deliberately short: the
		// per-attempt timeout already supplies the pacing.
		select {
		case <-connectCtx.Done():
			return fmt.Errorf("connect: %d attempt(s) within %s budget, last error: %w",
				attempt, connectTimeout, lastErr)
		case <-connectRetryAfter(connectRetryDelay):
		}
	}

	// STATBUS-110 read-only upgrade window — per-session self-exempt. The window
	// sets `ALTER DATABASE ... SET default_transaction_read_only = on` before the
	// DB stop, so EVERY reconnecting session (this one included) would inherit
	// read-only. The upgrade's own writers MUST stay read-write — the
	// state='completed' UPDATE, flag writes, and recovery observed-state writes all
	// go through queryConn. Issue the exempt (USERSET, needs no special role) on
	// EVERY (re)connect: reconnect() routes through connect(), so this one place
	// covers pre-swap, post-swap, the completion-reconnect, and recovery's
	// sessions. Harmless no-op when the window is inactive (already off). queryConn
	// is the writer, so its exempt is load-bearing (fail the connect if it can't be
	// set — a read-only writer session is unusable); listenConn only does LISTEN
	// (allowed under read-only), so its exempt is belt-and-suspenders / best-effort.
	if _, err := d.queryConn.Exec(ctx, "SET default_transaction_read_only = off"); err != nil {
		_ = d.listenConn.Close(context.Background())
		_ = d.queryConn.Close(context.Background())
		return fmt.Errorf("self-exempt query connection from read-only window: %w", err)
	}
	if _, err := d.listenConn.Exec(ctx, "SET default_transaction_read_only = off"); err != nil {
		fmt.Printf("read-only window: could not self-exempt listen connection (LISTEN is allowed read-only; continuing): %v\n", err)
	}
	return nil
}

// keepaliveDialer is the pgx DialFunc used by connect(). It delegates to
// newKeepaliveDialer() which is platform-specific (keepalive_linux.go /
// keepalive_other.go). On Linux all three TCP keepalive knobs are set;
// on other platforms only TCP_KEEPIDLE is set via net.Dialer.KeepAlive.
// See keepalive_linux.go for timing details.
func keepaliveDialer(ctx context.Context, network, addr string) (net.Conn, error) {
	return newKeepaliveDialer().DialContext(ctx, network, addr)
}

// ensureConnected pings queryConn and reconnects both connections if dead.
// Called at the top of discover/executeScheduled/reportDiskSpace to detect
// a dead queryConn (e.g., after DB restart during deploy). The listenConn
// has its own reconnect path via errCh in the main loop.
func (d *Service) ensureConnected(ctx context.Context) error {
	if d.queryConn == nil || d.queryConn.Ping(ctx) != nil {
		fmt.Println("Database connection lost, reconnecting...")
		return d.reconnect(ctx)
	}
	return nil
}

func (d *Service) reconnect(ctx context.Context) error {
	if d.listenConn != nil {
		_ = d.listenConn.Close(context.Background())
	}
	if d.queryConn != nil {
		_ = d.queryConn.Close(context.Background())
	}
	if err := d.connect(ctx); err != nil {
		return err
	}
	// Re-acquire advisory lock on new session
	if err := d.acquireAdvisoryLock(ctx); err != nil {
		return fmt.Errorf("re-acquire lock after reconnect: %w", err)
	}
	if _, err := d.listenConn.Exec(ctx, "LISTEN upgrade_check"); err != nil {
		return err
	}
	if _, err := d.listenConn.Exec(ctx, "LISTEN upgrade_apply"); err != nil {
		return err
	}
	return nil
}

func (d *Service) cleanStaleMaintenance(ctx context.Context) {
	// Same flag-file path the writer (setMaintenance) uses — see the
	// maintenance path convention in exec.go (STATBUS-089).
	maintenanceFile := maintenanceFlagHostPath()
	if _, err := os.Stat(maintenanceFile); os.IsNotExist(err) {
		return
	}

	// Check if an upgrade is actually in progress.
	// Only clean the file if we successfully confirm no active upgrade.
	// If DB is unreachable, leave the file (safer to stay in maintenance).
	var count int
	err := d.queryConn.QueryRow(ctx,
		"SELECT COUNT(*) FROM public.upgrade WHERE state = 'in_progress'").Scan(&count)
	if err != nil {
		fmt.Printf("Cannot check upgrade status (DB error: %v), leaving maintenance file\n", err)
		return
	}
	if count == 0 {
		// STATBUS-187 AC#3 / ranked #7 (architect ruling, ticket comment
		// #7): same loud-warn SHAPE as the upgrade-flag sites above
		// (warnOnStaleFlagRemoveFailure), but a DIFFERENT consequence —
		// cleanStaleMaintenance runs ONCE at daemon boot (Run()'s startup
		// sequence), not on a periodic ticker, so a failed Remove here
		// leaves the site stuck in maintenance mode (Caddy serving 503)
		// until the next FULL DAEMON RESTART, not the next recovery pass.
		// Only claim "Cleaned" once the removal is confirmed — the log
		// must not claim what didn't happen.
		removeErr := os.Remove(maintenanceFile)
		warnOnStaleFlagRemoveFailure(maintenanceFile, removeErr,
			"the site stays in maintenance mode (Caddy serving 503) until the next daemon restart, not the next recovery pass")
		if removeErr == nil {
			fmt.Println("Cleaned stale maintenance file")
		}
	}
}

// clearStaleReadOnlyWindow is the STATBUS-163 boot-time reconciliation sibling of
// cleanStaleMaintenance: clear a STALE read-only window. When NO upgrade is in
// flight (no service flag, no in_progress row) yet the app database's default is
// still read-only, a terminal OFF flip must have broken its invariant on a prior
// boot. This is a NAMED, one-time, loud reconciliation — the cleanStaleMaintenance
// precedent, NOT a silent standing self-heal.
//
// RECURRENCE INDICTS (carry this): post-STATBUS-163 the terminal flips ride the
// teardown-immune terminalExec, so this stale case is near-unreachable — the flip
// no longer dies with the pass conn. So if this backstop EVER fires, the flip
// broke its invariant and that firing is the INVESTIGATION TRIGGER, not routine.
// Without it, the unreachable residue is a frozen NSO registry rejecting every
// write (25006), waiting for a human who cannot SSH in — a travel event.
func (d *Service) clearStaleReadOnlyWindow(ctx context.Context) {
	// A flag present (or unreadable) means an upgrade may be in flight → leave the
	// window; it is legitimately engaged and its own terminal will lift it.
	if flag, err := ReadFlagFile(d.projDir); err != nil || flag != nil {
		return
	}
	var inProgress int
	if err := d.queryConn.QueryRow(ctx,
		"SELECT COUNT(*) FROM public.upgrade WHERE state = 'in_progress'").Scan(&inProgress); err != nil {
		return // DB unreachable → leave it (safer, mirrors cleanStaleMaintenance)
	}
	if inProgress > 0 {
		return // an upgrade IS in flight → the window is legitimately engaged
	}
	// STATBUS-209 ARM A — PRESERVE THE ABORT HOLD. A restore-reattemptable row (state='failed'
	// with a retained backup_path) means a human-gated `./sb install` replay is pending, and the
	// replay's OWN restore→:7981 lift clears the window. The git-restore-fail ABORT deliberately
	// holds read-only on a broken volume until that replay — this backstop must NOT strip that
	// protection early, whether invoked at boot OR from the install ladder (ARM A's second
	// invoker). Pinned by unit so a future cleanup can't drop it. (A read error → leave it, the
	// safe direction, mirroring the in_progress read above.)
	var reattemptPending int
	if err := d.queryConn.QueryRow(ctx,
		"SELECT COUNT(*) FROM public.upgrade WHERE state = 'failed' AND backup_path IS NOT NULL").Scan(&reattemptPending); err != nil {
		return
	}
	if reattemptPending > 0 {
		return // a restore replay is pending → its own lift owns the window; never strip the ABORT hold
	}
	// Read the DATABASE-level default (pg_db_role_setting, setrole=0), independent
	// of this daemon session's own read-only-off exemption.
	var stale bool
	if err := d.queryConn.QueryRow(ctx, `SELECT EXISTS (
	    SELECT 1 FROM pg_db_role_setting s
	      JOIN pg_database d ON d.oid = s.setdatabase
	     WHERE d.datname = current_database()
	       AND s.setrole = 0
	       AND 'default_transaction_read_only=on' = ANY(s.setconfig))`).Scan(&stale); err != nil {
		return
	}
	if !stale {
		return
	}
	fmt.Fprintln(os.Stderr,
		"STATBUS-163 BACKSTOP: the read-only upgrade window is STILL ON with NO upgrade in flight (no flag, no in_progress row) — a prior terminal OFF flip broke its invariant. This is near-unreachable post-fix; its firing INDICTS the flip and is an investigation trigger. Clearing it now so the box stops rejecting writes.")
	if _, err := d.liftReadOnlyWindow("the STATBUS-163 boot backstop"); err != nil {
		fmt.Fprintf(os.Stderr,
			"STATBUS-163 BACKSTOP: FAILED to clear the stale read-only window (%v) — the box still rejects writes; `./sb install` clears it.\n", err)
		return
	}
	fmt.Println("STATBUS-163 BACKSTOP: cleared the stale read-only window (no upgrade in flight).")
}

// ClearStaleReadOnlyWindowIfUnowned is the STATBUS-209 ARM A exported entrypoint: it lets the
// install ladder invoke the SAME ownership-gated backstop the daemon runs at boot (:2226), so a
// stale read-only window left by a crash between a restore and its lift (the pair-terminal
// residue) is cleared for the box's APP sessions — which legitimately never self-exempt — the
// moment an install pass has the DB up and establishes that no upgrade owns the box. The window
// is legitimate only while a live upgrade owns it; any actor bringing the DB to health with no
// owner present (no flag, no in_progress row, no restore-reattempt pending) is looking at stale
// residue and clears it loudly. Requires a live queryConn (LoadConfigAndConnect). Install's own
// completion INSERT is covered separately by ARM B (session self-exemption).
func (d *Service) ClearStaleReadOnlyWindowIfUnowned(ctx context.Context) {
	d.clearStaleReadOnlyWindow(ctx)
}

func (d *Service) checkMissedUpgrades(ctx context.Context) {
	var count int
	err := d.queryConn.QueryRow(ctx,
		"SELECT COUNT(*) FROM public.upgrade WHERE state = 'scheduled'").Scan(&count)
	if err == nil && count > 0 {
		fmt.Printf("Found %d missed scheduled upgrade(s)\n", count)
	}
}

// candidateMeta carries the metadata for a candidate-row upsert. A candidate
// with release tags is "tagged" (the normal release path); one without is an
// "edge"/untagged commit. Mirrors the TaggedTarget/UntaggedTarget union in
// commit.go.
type candidateMeta struct {
	committedAt   time.Time
	tags          []string // release tags at the commit; empty ⇒ untagged (edge) commit
	commitVersion string   // display label for an untagged commit ("" ⇒ NULL); tagged uses tags[0]
	summary       string
	releaseStatus string // public.release_status_type; only meaningful for tagged candidates
}

// manifestSweepTags bounds GitHub Release manifest probes to tags that can still
// become an upgrade on this box. Release artifacts are immutable, and tags at or
// below the installed version are historical here, so re-probing all of them on
// every discovery pass can produce no useful state transition. Norway's
// prerelease box made 198 requests in one pass versus roughly 10 on stable
// (STATBUS-338). Keep only orderable tags newer than the installed release.
func manifestSweepTags(tags []GitTag, installedVersion string) []GitTag {
	bounded := make([]GitTag, 0, len(tags))
	for _, tag := range tags {
		ord, ordered := CompareVersions(tag.TagName, installedVersion)
		if ordered && ord > 0 {
			bounded = append(bounded, tag)
		}
	}
	return bounded
}

// upsertCandidate records (or refreshes the metadata of) a candidate upgrade
// row. THE single insert path (STATBUS-086): release discovery, edge discovery,
// AND `./sb upgrade register` all flow through here. It NEVER sets a lifecycle
// state — a candidate is born 'available' (the table default) and scheduling is
// a separate explicit step (`schedule` / executeScheduled). Returns the number
// of rows affected.
//
// Two shapes, branched on whether the commit carries release tags. Each branch
// is the exact SQL previously inlined in discoverReleases (tagged) and
// discoverEdge (untagged), so routing discovery through here is behavior-neutral.
func (d *Service) upsertCandidate(ctx context.Context, sha CommitSHA, meta candidateMeta) (int64, error) {
	if len(meta.tags) > 0 {
		tag := meta.tags[0]
		// STATBUS-169 AC#1: never write a false fact. A tag may be recorded on a
		// row ONLY if git says the tag points at that commit. A tag that rev-parses
		// to a DIFFERENT commit — or that git cannot resolve — is machinery about to
		// write a corrupt commit_tags cache entry fresh; refuse loudly. (A tag that
		// MOVES after a valid write is a separate concern the pruner reconciles;
		// this guard stops a bad write at the source.)
		if resolved, rerr := d.RevParse(ctx, tag); rerr != nil {
			return 0, fmt.Errorf("refusing to register tag %s on commit %s: cannot verify the tag points here (git rev-parse %s: %w)", tag, commitShort(CommitSHA(sha)), tag, rerr)
		} else if resolved != sha {
			return 0, fmt.Errorf("refusing to register: tag %s points at commit %s in git, not %s — a tag may only be recorded on the commit it points at (STATBUS-169 AC#1)", tag, commitShort(resolved), commitShort(CommitSHA(sha)))
		}
		// Tagged: ON CONFLICT appends the tag and promotes release_status
		// (a newer release shape re-flags release_builds_status='building').
		ct, err := d.queryConn.Exec(ctx,
			`INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, has_migrations, commit_version)
			 VALUES ($1, $2, ARRAY[$3]::text[], $4::public.release_status_type, $5, false, $3)
			 ON CONFLICT (commit_sha) DO UPDATE SET
			   commit_tags = CASE WHEN $3 = ANY(upgrade.commit_tags) THEN upgrade.commit_tags
			                      ELSE array_append(upgrade.commit_tags, $3) END,
			   release_status = GREATEST(upgrade.release_status, EXCLUDED.release_status),
			   release_builds_status = CASE
			       WHEN EXCLUDED.release_status > upgrade.release_status THEN 'building'::public.release_builds_status_type
			       ELSE upgrade.release_builds_status
			   END,
			   commit_version = (CASE WHEN $3 = ANY(upgrade.commit_tags) THEN upgrade.commit_tags
			                          ELSE array_append(upgrade.commit_tags, $3) END)[1]
			 WHERE NOT ($3 = ANY(upgrade.commit_tags))
			    OR upgrade.release_status < EXCLUDED.release_status`,
			string(sha), meta.committedAt, tag, meta.releaseStatus, meta.summary)
		if err != nil {
			return 0, err
		}
		return ct.RowsAffected(), nil
	}
	// Untagged (edge) commit: release_builds_status='ready' (no release.yaml
	// output needed); ON CONFLICT only backfills a missing commit_version.
	ct, err := d.queryConn.Exec(ctx,
		`INSERT INTO public.upgrade (commit_sha, committed_at, summary, has_migrations, release_builds_status, commit_version)
		 VALUES ($1, $2, $3, false, 'ready'::public.release_builds_status_type, NULLIF($4, ''))
		 ON CONFLICT (commit_sha) DO UPDATE SET commit_version = EXCLUDED.commit_version WHERE upgrade.commit_version IS NULL`,
		string(sha), meta.committedAt, meta.summary, meta.commitVersion)
	if err != nil {
		return 0, err
	}
	return ct.RowsAffected(), nil
}

func (d *Service) discover(ctx context.Context) {
	if err := d.ensureConnected(ctx); err != nil {
		fmt.Printf("Reconnect failed in discover: %v\n", err)
		return
	}

	// (The edge-channel commit discovery that ran here is retired with the
	// channel itself — King, 2026-08-19. It fetched recent master commits and
	// offered them as candidates, which is what "track every master commit"
	// meant. Running a SPECIFIC commit is unaffected and still works exactly as
	// before: `./sb upgrade register <commit>` then `schedule`. What retires is
	// continuously following master, which no box should do unattended.)

	// Use git fetch for discovery — no API rate limit, no GITHUB_TOKEN needed.
	tags, err := DiscoverTagsViaGit(d.projDir)
	if err != nil {
		fmt.Printf("Discovery error: %v\n", err)
		// STATBUS-345 (rc.10 forensics): a GitHub tag-fetch failure must not
		// block ghcr image verification — pending rows and the registry are
		// independent of the tag ledger. During a GitHub 401 storm every
		// discovery cycle aborted here and verifyArtifacts below never ran,
		// so an already-registered candidate sat docker_images_status=
		// 'building' for 25 minutes while all four images were pullable.
		d.verifyArtifacts(ctx)
		return
	}

	filtered := FilterTagsByChannel(tags, d.channel)
	fmt.Printf("Discovery: %d tag(s) via git, %d match channel %q\n", len(tags), len(filtered), d.channel)

	// The service's compiled-in version — used to skip older releases.
	currentVersion := d.version

	// ── THE COMPARABILITY GATE (STATBUS-293) ─────────────────────────────────
	// Automatic discovery decides what to offer by RANKING each release against
	// the running version. On a box installed from an untagged commit there is
	// no release ordering to rank against, so this path registers NOTHING and
	// says so — rather than guessing.
	//
	// It used to guess, silently. CompareVersions fell back to comparing raw
	// text, so an installed commit whose SHA began 0 or 1 sorted below the
	// literal "2026" and EVERY release in the channel — back to v2026.03.0 —
	// was registered as an available upgrade for a box running much newer code.
	// The operator was offered a three-month-old downgrade labelled an upgrade,
	// and nothing anywhere said anything was wrong.
	//
	// Self-comparison is the orderability probe: it consults the same gate
	// CompareVersions applies, so this can never drift from that definition.
	//
	// THE REFUSAL NAMES BOTH WAYS FORWARD, because a guard that only says "no"
	// replaces a wrong answer with a dead end — no better for the operator
	// standing in front of it, and this box may be an NSO's production install
	// whose only lever is this command.
	_, versionOrderable := CompareVersions(currentVersion, currentVersion)
	if !versionOrderable {
		fmt.Printf(`Automatic upgrade discovery is INACTIVE on this box.

  Installed version: %s — this is a commit, not a release tag, so no release
  can be ranked against it. Nothing has been registered as available, because
  the only alternative is to guess, and a wrong guess offers a DOWNGRADE as an
  upgrade (STATBUS-293).

  Two ways forward:
    - Install a specific version now:        ./sb upgrade apply <version>
    - Restore automatic discovery: install a release tag (./sb upgrade apply
      <release-tag>). Once the box is ON a tag, it follows its channel again
      with no further action.
`, currentVersion)
	}

	for _, t := range filtered {
		// Skip releases older than or equal to what we're currently running,
		// and every release when the installed version is unorderable (the
		// refusal above is printed once, not once per tag).
		ord, ordered := CompareVersions(t.TagName, currentVersion)
		if !ordered || ord <= 0 {
			if d.verbose && ordered {
				fmt.Printf("  Skipping %s (not newer than %s)\n", t.TagName, currentVersion)
			}
			continue
		}

		// STATBUS-307 — THE SAME-COMMIT SHORT-CIRCUIT.
		//
		// AN "UPGRADE" THAT CHANGES NO CODE IS NOT AN UPGRADE. A release and its
		// final release candidate are two NAMES FOR ONE COMMIT: v2026.08.1 and
		// v2026.08.1-rc.01 both point at 0da0f202dcf3, because a release IS the
		// last gated prerelease, promoted.
		//
		// Widening the prerelease channel to admit releases (TagMatchesChannel,
		// this ticket) makes that case MORE common rather than less. Before the
		// widening a prerelease box never saw the stable name at all; now it sees
		// both, and CompareVersions correctly ranks the release above its own
		// prerelease — so without this, the box would be offered the stable name
		// for the commit it is already running. The operator would take a full
		// backup, maintenance window, migration pass and health check to install
		// the software already installed.
		//
		// Compared by COMMIT, not by version string, because the version strings
		// are exactly what differ here — the commit is the identity, the tags are
		// labels on it (the commit-is-authoritative doctrine).
		if installed := d.installedCommitSHA(); installed != "" && t.CommitSHA == installed {
			if d.verbose {
				fmt.Printf("  Skipping %s — same commit as the running version (%s); an upgrade that changes no code is not an upgrade\n",
					t.TagName, ShortForDisplay(installed))
			}
			continue
		}

		// Determine release_status from the tag's shape via the single shared
		// classifier (NOT "any hyphen = prerelease"). After FilterTagsByChannel
		// this set holds only release / -rc. shapes, so this resolves to
		// "release" or "prerelease". Manifest availability is checked at upgrade
		// execution time, not discovery.
		targetStatus := ClassifyReleaseShape(t.TagName).ReleaseStatus()

		// Verify commit signature before recording
		if err := d.verifyCommitSignature(t.CommitSHA); err != nil {
			fmt.Printf("Skipping %s: %v\n", t.TagName, err)
			continue
		}

		// has_migrations will be determined from the manifest during actual upgrade.
		// For now, default to false — the manifest check happens in executeUpgrade.
		// ON CONFLICT: add tag to array if not already present, promote release_status.
		// version: for tagged releases the tag name IS the docker image
		// tag (git describe on the exact commit returns the tag directly). Store it
		// so verifyArtifacts uses it even if new tags are later pushed past this commit.
		affected, err := d.upsertCandidate(ctx, CommitSHA(t.CommitSHA), candidateMeta{
			committedAt:   t.PublishedAt,
			tags:          []string{t.TagName},
			releaseStatus: targetStatus,
			summary:       t.TagName,
		})
		if err != nil {
			fmt.Printf("Failed to record release %s: %v\n", t.TagName, err)
			continue
		}

		if affected > 0 {
			fmt.Printf("Discovered: %s (%s)\n", t.TagName, t.PublishedAt.Format("2006-01-02"))
		}
	}

	// Enrich existing rows with tag data. Separate from the discovery loop above
	// which only INSERTs rows for versions NEWER than current. This UPDATE pass
	// associates tags with commits already in the DB (e.g., from edge discovery),
	// regardless of whether the tag is newer, equal, or older than the service.
	for _, t := range filtered {
		targetStatus := ClassifyReleaseShape(t.TagName).ReleaseStatus()
		// Best-effort; discover() runs on every discovery cycle (6h ticker or
		// NOTIFY), so a failed enrichment UPDATE here is retried next cycle.
		_ = d.execObserved(ctx, "discover: enrich tag identity",
			`UPDATE public.upgrade SET
			   commit_tags = CASE WHEN $2 = ANY(upgrade.commit_tags) THEN upgrade.commit_tags
			                      ELSE array_append(upgrade.commit_tags, $2) END,
			   release_status = GREATEST(upgrade.release_status, $3::public.release_status_type),
			   commit_version = (CASE WHEN $2 = ANY(upgrade.commit_tags) THEN upgrade.commit_tags
			                          ELSE array_append(upgrade.commit_tags, $2) END)[1]
			 WHERE commit_sha = $1
			   AND (NOT ($2 = ANY(upgrade.commit_tags)) OR upgrade.release_status < $3::public.release_status_type)`,
			t.CommitSHA, t.TagName, targetStatus)
	}

	// Check GitHub Release manifest availability for tagged releases and
	// update release_builds_status. The manifest lives alongside the `sb`
	// binary and changelog in the GitHub Release — if FetchManifest
	// succeeds, all three are published. Commits never have this.
	// If manifest is missing, check if the release workflow has failed.
	manifestTags := manifestSweepTags(filtered, currentVersion)
	if d.verbose && len(manifestTags) != len(filtered) {
		fmt.Printf("  Manifest sweep bounded to %d newer tag(s); skipped %d historical tag(s) at or below %s\n",
			len(manifestTags), len(filtered)-len(manifestTags), currentVersion)
	}
	for _, t := range manifestTags {
		if _, err := FetchManifest(t.TagName); err == nil {
			// Best-effort; same self-correcting shape as the enrichment
			// UPDATE above — retried on the next discovery cycle.
			_ = d.execObserved(ctx, "discover: mark release builds ready",
				"UPDATE public.upgrade SET release_builds_status = 'ready' WHERE commit_sha = $1 AND release_builds_status != 'ready'",
				t.CommitSHA)
		} else {
			// Manifest not available. STATBUS-302: this used to ask `gh api`
			// for the release.yaml workflow's conclusion to decide whether
			// release_builds_status should flip to 'failed' — gh is not
			// installed on production boxes, so on every real installation
			// ciErr was always non-nil and this whole block was ALREADY a
			// no-op there (there was no `else` branch on ciErr != nil,
			// unlike the images.yaml site above, which had one — and that
			// missing branch's timeout-based promotion is exactly what
			// LOOKED like the fix to reach for here too). It doesn't apply:
			// this resource is a GitHub RELEASE asset (release-manifest.json,
			// fetched via FetchManifest above, already tried and already
			// failed to reach this branch) — not a container image, so
			// ghcr.io is the wrong registry entirely; there is no anonymous
			// HTTP probe for "did this GitHub Actions workflow conclude with
			// failure" that doesn't go through the Actions API `gh` was
			// wrapping. Per the ruling's explicit carve-out ("if a site
			// genuinely needs workflow-conclusion semantics the manifest
			// can't provide, say so per-site rather than force-fitting"):
			// removed the always-dead-on-production gh exec outright rather
			// than force a ghcr check onto a resource it cannot answer for.
			// Behavior on production is UNCHANGED (release_builds_status
			// already stayed 'building' forever here when gh was absent —
			// this is the pre-existing default, not a new one); the only
			// change is an honest log line instead of silent nothing, and
			// gh is never invoked (removing the shared-IP rate-limit
			// exposure named in the ticket). A real failure signal for this
			// resource — e.g. a manifestTimeout-style promotion, mirroring
			// the images.yaml site's fallback — is a genuine behavior change
			// this ticket did not ask for and is left to Half B / a
			// follow-up, not invented here.
			log.Printf(
				"discoverTaggedReleases: could not determine release build status for %s (no gh CLI; release manifest not yet published) — release_builds_status remains 'building'",
				t.TagName)
		}
	}

	// Two-level declarative verification covering every pending row:
	//   1. docker_images_status — queries ghcr.io for each of the four images at
	//      the runtime VERSION tag (building → ready or failed).
	//   2. release_builds_status — for tagged releases: GitHub Release + sb binary
	//      + manifest.json exist. Set by discoverTaggedReleases via FetchManifest.
	//      Commits skip this level (default ready). Three states: building/ready/failed.
	// Runs on every discovery cycle; cheap (bounded per-cycle) and
	// idempotent. Gives the admin UI accurate "what are we waiting for"
	// signal without coupling to CI workflow telemetry.
	d.verifyArtifacts(ctx)

	// Prune tags deleted upstream against ALL tags that exist in git, never the
	// channel-filtered offer list. The channel decides what discovery displays
	// and offers on this box; it does not decide whether a tag exists. Passing
	// `filtered` here silently stripped live off-channel tags from manually
	// registered rows and demoted their release identity (STATBUS-336).
	d.pruneDeletedTags(ctx, tags)

	// Self-heal the ledger: retire any available/scheduled row that is not newer
	// than the installed version (tier-independent, version-based). The SQL
	// supersede proc's peer hierarchy guard cannot retire a genuine older release
	// when the installed version is a prerelease, which left phantom "available"
	// upgrades older than what is running (STATBUS-050 / STATBUS-047 B2). A cheap
	// single UPDATE — grouped with the verifyArtifacts/pruneDeletedTags
	// reconciliation passes above, before the "last checked" timestamp, so the
	// ledger is honest when the admin-UI check resolves.
	d.supersedeBelowInstalled(ctx)

	// Record last-discover timestamp for the admin UI "Last checked" display.
	// Best-effort — ignore error so observability noise never blocks the main path.
	// WRITTEN BEFORE the background pre-download: the admin-UI check resolves on
	// this timestamp, so the pre-download must not delay it. Previously the
	// (synchronous, oldest-first, 3-at-a-time) pre-download ran first and pushed
	// this write minutes later — the "Checking…" spin (STATBUS-047 B1).
	_ = d.execObserved(ctx, "discover: stamp upgrade_last_discover_at",
		`INSERT INTO public.system_info (key, value, updated_at)
		 VALUES ('upgrade_last_discover_at', now()::text, now())
		 ON CONFLICT (key) DO UPDATE
		   SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`)

	// Background pre-download runs LAST, after the check has answered. It pulls
	// only the single newest candidate newer than installed (preDownloadImages).
	if d.autoDL {
		d.preDownloadImages(ctx)
	}
}

// keepTagForRow reports whether a tag on a row survives a prune pass: the tag
// must still EXIST in git AND still POINT at that row's commit. A deleted tag
// (absent) or a MOVED tag (git points it at a different commit now) is dropped —
// commit_tags is a CACHE of git tag state (STATBUS-169), so a non-pointing entry
// is stale, not truth.
func keepTagForRow(tag string, gitTagSHAs map[string]CommitSHA, rowSHA CommitSHA) bool {
	target, exists := gitTagSHAs[tag]
	return exists && target == rowSHA
}

// pruneDeletedTags reconciles commit_tags to its git source: it drops any tag
// that no longer EXISTS in git (deleted upstream) OR no longer POINTS at the
// row's commit (moved — STATBUS-169). commit_tags is a cache of git tag state,
// so this is the cache honoring its source, not self-heal — a moved tag (e.g.
// rune's row 222) heals on the pruner's normal cycle. One log line per drop.
func (d *Service) pruneDeletedTags(ctx context.Context, currentTags []GitTag) {
	// Map each git tag to the commit it points at NOW (GitTag carries it).
	gitTagSHAs := make(map[string]CommitSHA, len(currentTags))
	for _, t := range currentTags {
		gitTagSHAs[t.TagName] = CommitSHA(t.CommitSHA)
	}

	rows, err := d.queryConn.Query(ctx,
		`SELECT id, commit_sha, commit_tags FROM public.upgrade WHERE array_length(commit_tags, 1) > 0`)
	if err != nil {
		return
	}
	// Drain fully BEFORE any UPDATE — an Exec on the same conn while rows are
	// still open would contend with the open portal.
	type pruneRow struct {
		id     int
		rowSHA CommitSHA
		tags   []string
	}
	var pending []pruneRow
	for rows.Next() {
		var id int
		var rowSHA string
		var tags []string
		if err := rows.Scan(&id, &rowSHA, &tags); err != nil {
			continue
		}
		pending = append(pending, pruneRow{id: id, rowSHA: CommitSHA(rowSHA), tags: tags})
	}
	rows.Close()

	for _, p := range pending {
		// Non-nil by construction: commit_tags is NOT NULL, and pgx encodes a
		// nil []string as SQL NULL. Before this, a row whose EVERY tag was
		// pruned (moved or deleted) hit the constraint on each discovery tick,
		// the swallowed error hid it, and the same "Pruned ..." lines repeated
		// every 5 minutes forever (dev: 25 rows, 744 identical lines in 48h).
		kept := make([]string, 0, len(p.tags))
		dropped := false
		for _, tag := range p.tags {
			if keepTagForRow(tag, gitTagSHAs, p.rowSHA) {
				kept = append(kept, tag)
				continue
			}
			dropped = true
			if target, exists := gitTagSHAs[tag]; exists {
				fmt.Printf("Pruned MOVED tag %s from upgrade %d (commit %s): the tag now points at commit %s — commit_tags is a cache of git state (STATBUS-169)\n",
					tag, p.id, commitShort(p.rowSHA), commitShort(target))
			} else {
				fmt.Printf("Pruned DELETED tag %s from upgrade %d (commit %s): the tag no longer exists in git\n",
					tag, p.id, commitShort(p.rowSHA))
			}
		}
		if !dropped {
			continue
		}
		// Demote release_status to match the surviving tags.
		newStatus := "commit"
		for _, tag := range kept {
			if !strings.Contains(tag, "-") {
				newStatus = "release"
				break
			}
			newStatus = "prerelease"
		}
		// Retried on the next discovery cycle if it fails, but never silently:
		// a swallowed error here is exactly how the NULL-encoding defect above
		// stayed invisible while the journal claimed the prune had happened.
		_ = d.execObserved(ctx, fmt.Sprintf("pruneDeletedTags: reconcile upgrade %d tags", p.id),
			`UPDATE public.upgrade SET commit_tags = $1, release_status = $2::public.release_status_type WHERE id = $3`,
			kept, newStatus, p.id)
	}
}

// downloadCandidate is one image set the background pre-download could fetch.
// Version is the CalVer release tag (e.g. "v2026.06.0-rc.02"); CommitSHA is the
// row's commit — its 8-char short form (ShortForDisplay) is the actual Docker
// image tag (${COMMIT_SHORT}).
type downloadCandidate struct {
	Version   string
	CommitSHA string
}

// selectNewestDownloadCandidate is the version-targeting decision for the
// background pre-download, factored out as a PURE function so it is unit-tested
// directly (no Docker, no DB). It returns the single candidate that is the
// newest release STRICTLY NEWER than installed, or ok=false when none qualifies
// (the box is already at or ahead of every candidate).
//
// installed and each candidate Version must be a CalVer tag: a non-CalVer
// candidate is ignored, and a non-CalVer installed version (e.g. "dev") yields
// no candidate — we never guess an ordering, we just skip pre-download. This is
// the defect the function exists to prevent: the daemon used to select via
// `ORDER BY discovered_at LIMIT 3` (the OLDEST rows, never re-checked against
// the installed version), so after an upgrade it ground through ancient
// releases the box would never install (STATBUS-047 A3).
func selectNewestDownloadCandidate(installed string, candidates []downloadCandidate) (downloadCandidate, bool) {
	if !ValidateVersion(installed) {
		return downloadCandidate{}, false
	}
	var best downloadCandidate
	found := false
	for _, c := range candidates {
		if !ValidateVersion(c.Version) {
			continue // not a CalVer tag — no defined ordering
		}
		ord, ordered := CompareVersions(c.Version, installed)
		if !ordered || ord <= 0 {
			continue // unorderable, older, or equal — never go backward
		}
		bestOrd, bestOrdered := CompareVersions(c.Version, best.Version)
		if !found || (bestOrdered && bestOrd > 0) {
			best = c
			found = true
		}
	}
	return best, found
}

// staleCandidate is one available/scheduled ledger row evaluated for retirement
// against the installed version. Tags is the row's commit_tags — a single commit
// can carry several (e.g. a final rc and its release tag on the same commit, as
// in {v2026.05.1-rc.01, v2026.05.1}).
type staleCandidate struct {
	ID   int
	Tags []string
}

// selectNewestTag returns the newest CalVer tag in tags (CompareVersions order),
// or "" if none is a valid CalVer tag. A row is judged by its NEWEST tag so a
// commit double-tagged with a final rc and its release is compared on the
// release, never wrongly on the rc.
func selectNewestTag(tags []string) string {
	newest := ""
	for _, tag := range tags {
		if !ValidateVersion(tag) {
			continue // not a CalVer tag — no defined ordering
		}
		ord, ordered := CompareVersions(tag, newest)
		if newest == "" || (ordered && ord > 0) {
			newest = tag
		}
	}
	return newest
}

// selectStaleBelowInstalled returns the IDs of available/scheduled ledger rows
// that no longer represent an upgrade — i.e. whose newest CalVer tag is NOT NEWER
// than the installed version — so discover() can retire them (state='superseded').
// The decision is TIER-INDEPENDENT: it compares CalVer versions only
// (CompareVersions), never release_status.
//
// This is the vs-installed counterpart to the SQL upgrade_supersede_older proc's
// PEER hierarchy guard (release_status <= installed's status). That guard is
// correct for peer supersede — a prerelease must not hide an older tagged release
// as a peer — but WRONG against the installed version: a genuine release (e.g.
// v2026.05.3) that is older than an installed prerelease (v2026.06.0-rc.02) is
// still not an upgrade, because 05.3 < 06.0 by version. The proc therefore left
// such rows lingering as phantom "available" upgrades (STATBUS-050 /
// STATBUS-047 B2); this rule retires them regardless of tier or install path.
//
// Guards mirror selectNewestDownloadCandidate (STATBUS-047 item A): a non-CalVer
// installed version (e.g. "dev") retires nothing — we never guess an ordering —
// and a row with no CalVer tag (e.g. an edge commit) is left alone.
func selectStaleBelowInstalled(installed string, candidates []staleCandidate) []int {
	if !ValidateVersion(installed) {
		return nil
	}
	var retire []int
	for _, c := range candidates {
		newest := selectNewestTag(c.Tags)
		if newest == "" {
			continue // no CalVer tag on this row — no defined ordering
		}
		ord, ordered := CompareVersions(newest, installed)
		if !ordered {
			// Cannot order this row against the installed version, so we
			// cannot know it is stale. LEAVE IT ALONE (STATBUS-293 ruling):
			// wrongly retiring a legitimate candidate silently removes an
			// upgrade the operator needs, which is strictly worse than
			// leaving a stale row visible for a human to dismiss.
			continue
		}
		if ord <= 0 {
			retire = append(retire, c.ID)
		}
	}
	return retire
}

// preDownloadImages pre-stages, in the background, the images for the single
// newest release strictly newer than the installed version — and only once its
// images are confirmed present in the registry (docker_images_status='ready',
// set by verifyArtifacts) and not already fetched. The version-targeting
// decision lives in the pure selectNewestDownloadCandidate; the pull is keyed by
// the candidate's COMMIT_SHORT (its real image tag) via pullImagesForCommitShort
// so it fetches the CANDIDATE's images rather than re-pulling current
// (STATBUS-047 A3). Called by discover() AFTER the "last checked" timestamp is
// recorded, so it never delays the admin-UI check (B1).
func (d *Service) preDownloadImages(ctx context.Context) {
	// Eligibility filter is SQL; the version DECISION is the pure function.
	// Close rows before the pull + UPDATE: queryConn is a single *pgx.Conn, so
	// the result set must be drained/closed before the next query on it.
	rows, err := d.queryConn.Query(ctx,
		`SELECT commit_sha, commit_version
		 FROM public.upgrade
		 WHERE docker_images_downloaded = false
		   AND docker_images_status = 'ready'
		   AND state IN ('available', 'scheduled')
		   AND commit_version IS NOT NULL
		 ORDER BY committed_at DESC
		 LIMIT 50`)
	if err != nil {
		return
	}
	var candidates []downloadCandidate
	for rows.Next() {
		var commitSHA, version string
		if err := rows.Scan(&commitSHA, &version); err != nil {
			continue
		}
		candidates = append(candidates, downloadCandidate{Version: version, CommitSHA: commitSHA})
	}
	rows.Close()

	chosen, ok := selectNewestDownloadCandidate(d.version, candidates)
	if !ok {
		return // already at/ahead of every candidate — nothing to pre-stage
	}

	fmt.Printf("Pre-downloading images for %s (newest candidate newer than installed %s)...\n", chosen.Version, d.version)
	if err := d.pullImagesForCommitShort(ShortForDisplay(chosen.CommitSHA)); err != nil {
		fmt.Printf("Pre-download failed for %s: %v\n", chosen.Version, err)
		return
	}

	// Best-effort; called from discover()'s periodic pass — a failed marker
	// UPDATE here just costs a redundant re-download attempt next cycle,
	// not a correctness issue.
	_ = d.execObserved(ctx, "preDownloadImages: mark images downloaded",
		"UPDATE public.upgrade SET docker_images_downloaded = true WHERE commit_sha = $1",
		chosen.CommitSHA)
}

// supersedeBelowInstalled retires (state='superseded') every available/scheduled
// ledger row whose newest tag is not newer than the installed version. Runs on
// every discover() cycle so the ledger self-heals regardless of which path
// recorded the rows. The version DECISION is the pure selectStaleBelowInstalled;
// this method is the SQL eligibility query + UPDATE, mirroring preDownloadImages.
//
// Why it exists alongside upgrade_supersede_older: that proc's release_status
// hierarchy guard is correct for PEER supersede but cannot retire a genuine older
// RELEASE when the installed version is a PRERELEASE (release > prerelease in the
// tier order), so older releases lingered as phantom "available" upgrades
// (STATBUS-050 / STATBUS-047 B2). This is the tier-independent, version-based
// vs-installed retire. No migration: CalVer ordering (CompareVersions) lives in
// Go; the proc is left untouched for its peer-supersede job.
func (d *Service) supersedeBelowInstalled(ctx context.Context) {
	// queryConn is a single *pgx.Conn — drain/close the SELECT before the UPDATE.
	// Only tagged rows are eligible: edge commits (no tags) have no CalVer
	// ordering and are not an upgrade target on the tagged channels.
	rows, err := d.queryConn.Query(ctx,
		`SELECT id, commit_tags
		 FROM public.upgrade
		 WHERE state IN ('available', 'scheduled')
		   AND array_length(commit_tags, 1) > 0`)
	if err != nil {
		return
	}
	var candidates []staleCandidate
	for rows.Next() {
		var id int
		var tags []string
		if err := rows.Scan(&id, &tags); err != nil {
			continue
		}
		candidates = append(candidates, staleCandidate{ID: id, Tags: tags})
	}
	rows.Close()

	retire := selectStaleBelowInstalled(d.version, candidates)
	if len(retire) == 0 {
		return
	}

	// state='superseded' is NOT in ('available','scheduled'), so the
	// upgrade_block_obsolete_pending BEFORE trigger no-ops on this transition.
	// Re-assert the source state in the WHERE so a concurrent change can't be
	// clobbered. superseded_at via COALESCE matches upgrade_supersede_older.
	ct, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade
		    SET state = 'superseded',
		        superseded_at = COALESCE(superseded_at, now())
		  WHERE id = ANY($1::int[])
		    AND state IN ('available', 'scheduled')`,
		retire)
	if err != nil {
		fmt.Printf("Failed to supersede releases not newer than installed: %v\n", err)
		return
	}
	if n := ct.RowsAffected(); n > 0 {
		fmt.Printf("Superseded %d release(s) not newer than installed %s\n", n, d.version)
	}
}

// scheduleResult is the database-owned outcome of public.upgrade_schedule.
type scheduleResult string

const (
	scheduleResultScheduled                scheduleResult = "scheduled"
	scheduleResultSuperseded               scheduleResult = "superseded"
	scheduleResultAlreadyScheduled         scheduleResult = "already_scheduled"
	scheduleResultInProgress               scheduleResult = "in_progress"
	scheduleResultRestoreReattemptRequired scheduleResult = "restore_reattempt_required"
	scheduleResultUnregistered             scheduleResult = "unregistered"
)

func classifyScheduleResult(raw string) (scheduleResult, error) {
	result := scheduleResult(raw)
	switch result {
	case scheduleResultScheduled,
		scheduleResultSuperseded,
		scheduleResultAlreadyScheduled,
		scheduleResultInProgress,
		scheduleResultRestoreReattemptRequired,
		scheduleResultUnregistered:
		return result, nil
	default:
		return "", fmt.Errorf("unknown public.upgrade_schedule result %q", raw)
	}
}

func scanScheduleResult(row pgx.Row) (scheduleResult, error) {
	var raw string
	var upgradeID sql.NullInt64
	var landedState sql.NullString
	var supersededCount int
	if err := row.Scan(&raw, &upgradeID, &landedState, &supersededCount); err != nil {
		return "", err
	}
	return classifyScheduleResult(raw)
}

// errNotRegistered is the actionable fail-fast (STATBUS-086, AC#3) for
// scheduling a target that has no candidate row. Require-register: `schedule`
// NEVER inserts — it names the fix instead. Unit-tested.
func errNotRegistered(displayName, input string) error {
	return fmt.Errorf("%s is not registered — run `./sb upgrade register %s` first", displayName, input)
}

// applyNotifyFetchTimeout bounds the STATBUS-183 apply-race fetch inside the
// NOTIFY handler. The handler runs on the daemon's main goroutine under
// WatchdogSec=120s, so this is deliberately short (A3) — a hung fetch fails fast
// into a durable refusal rather than blocking the heartbeat.
const applyNotifyFetchTimeout = 30 * time.Second

// onScheduledNotify REACTS to a NOTIFY upgrade_apply (fired by
// upgrade_notify_daemon_trigger when a row is promoted to 'scheduled', or sent
// directly by `./sb upgrade apply-latest`). The CLI `./sb upgrade schedule` is
// what actually promotes a row; this handler does NOT schedule from scratch.
//
// STATBUS-086 (Option A, UNIFORM): schedule REQUIRES register EVERYWHERE — the
// CLI verb AND this handler. The old scheduleImmediate's insert-if-missing
// upsert is REMOVED: a NOTIFY for a commit with no candidate row is a LOUD,
// ACTIONABLE NO-OP (matching the CLI `schedule` fail-fast), never a silent
// insert. For a registered row it (re)promotes to 'scheduled' — resetting the
// lifecycle so a completed/failed/rolled_back candidate can re-run — and
// supersedes older releases. executeScheduled claims and runs it.
//
// The input may be a full 40-char commit_sha, an 8-char commit_short, or a
// CalVer release tag (see resolveUpgradeTarget for the parse contract).
func (d *Service) onScheduledNotify(ctx context.Context, input string) {
	// STATBUS-183 piece 2: an apply NOTIFY can beat the box's own fetch of a
	// freshly-cut release (the rc.06 race). Make the target local with ONE targeted
	// fetch before resolving — best-effort, a SINGLE attempt (never a backoff loop
	// in a NOTIFY handler); ensureCommitLocal short-circuits with no network when the
	// ref is already present (the common case, once discovery has fetched it).
	//
	// A3: this handler runs SYNCHRONOUSLY on the daemon's main goroutine (see the
	// `case n := <-notifyCh` in Run's select), which also carries the WatchdogSec=120s
	// heartbeat — so the fetch is bounded to applyNotifyFetchTimeout (well under 120s),
	// never the 2m default: a hung fetch must fail fast into a durable refusal, not
	// starve the heartbeat into a systemd SIGKILL.
	if ferr := d.ensureCommitLocal(input, applyNotifyFetchTimeout); ferr != nil {
		fmt.Printf("apply: pre-resolve fetch of %q did not land (continuing to resolve): %v\n", input, ferr)
	}

	target, err := resolveUpgradeTarget(ctx, d, input)
	if err != nil {
		// STATBUS-183 piece 3: even after the fetch the input names nothing git can
		// resolve — refuse DURABLY (not just a stdout line 170 phase-2 cannot see).
		fmt.Printf("Cannot resolve %q: %v\n", input, err)
		d.recordApplyRefused(ctx, input, fmt.Sprintf("cannot resolve target: %v", err))
		return
	}

	var commitSHA CommitSHA
	var displayName string
	switch t := target.(type) {
	case TaggedTarget:
		commitSHA = t.SHA
		displayName = string(t.Tag)
	case UntaggedTarget:
		commitSHA = t.SHA
		displayName = string(commitShort(t.SHA))
	default:
		fmt.Printf("unhandled UpgradeTarget type %T\n", target)
		return
	}

	res, err := d.promoteExistingCandidate(ctx, commitSHA)
	if err != nil {
		fmt.Printf("Failed to schedule %s: %v\n", displayName, err)
		return
	}
	switch res {
	case scheduleResultScheduled:
		d.onApplyScheduled(ctx, displayName)
	case scheduleResultAlreadyScheduled:
		fmt.Printf("Version %s is already scheduled — no action needed\n", displayName)
		d.clearApplyRefused(ctx) // the named version is already actioned
	case scheduleResultInProgress:
		fmt.Printf("Version %s is already in progress — no action needed\n", displayName)
		d.clearApplyRefused(ctx)
	case scheduleResultRestoreReattemptRequired:
		reason := "the failed upgrade retained a backup; run ./sb install to reattempt the restore"
		fmt.Printf("Cannot schedule %s: %s\n", displayName, reason)
		d.recordApplyRefused(ctx, input, reason)
	case scheduleResultSuperseded:
		reason := "the candidate is older than an installed completed candidate and was not queued"
		fmt.Printf("Cannot schedule %s: %s\n", displayName, reason)
		d.recordApplyRefused(ctx, input, reason)
	case scheduleResultUnregistered:
		// STATBUS-183 piece 1: the tag/commit resolved (git says it exists) but has
		// no candidate row yet — the rc.06 race. Instead of the old drop, register it
		// through the SAME guarded path the drop message prescribed ("Register it
		// first: ./sb upgrade register …"), then re-run the promote. upsertCandidate
		// carries the STATBUS-169 tag↔commit write-guard INTERNALLY, so no candidate
		// row is ever created except via that guard; a garbage-but-resolvable input
		// still dies later at verifyArtifacts/images gating, never at execute.
		if _, _, rerr := d.registerTarget(ctx, target); rerr != nil {
			// The class guard (e.g. the 169 tag-pointing check) refused — durable.
			fmt.Printf("NOTIFY upgrade_apply: refusing to register %s: %v\n", displayName, rerr)
			d.recordApplyRefused(ctx, input, fmt.Sprintf("register refused: %v", rerr))
			return
		}
		// The row now exists via the guarded upsert — re-run the SAME promote so
		// supersedeOlderReleases fires on the promoted path exactly as usual.
		res2, err2 := d.promoteExistingCandidate(ctx, commitSHA)
		if err2 != nil {
			fmt.Printf("Failed to schedule %s after registering: %v\n", displayName, err2)
			d.recordApplyRefused(ctx, input, fmt.Sprintf("promote after register failed: %v", err2))
			return
		}
		switch res2 {
		case scheduleResultScheduled:
			d.onApplyScheduled(ctx, displayName)
		case scheduleResultAlreadyScheduled:
			// The independent discovery+schedule (or a concurrent apply) beat us to
			// it — benign; the deploy still converges (race hygiene: upsertCandidate
			// is idempotent on commit_sha, so both orders land the same row).
			fmt.Printf("Version %s is already scheduled — no action needed\n", displayName)
			d.clearApplyRefused(ctx)
		case scheduleResultInProgress:
			fmt.Printf("Version %s is already in progress — no action needed\n", displayName)
			d.clearApplyRefused(ctx)
		case scheduleResultRestoreReattemptRequired:
			reason := "the failed upgrade retained a backup; run ./sb install to reattempt the restore"
			fmt.Printf("Cannot schedule %s after registering: %s\n", displayName, reason)
			d.recordApplyRefused(ctx, input, reason)
		case scheduleResultSuperseded:
			reason := "the candidate is older than an installed completed candidate and was not queued"
			fmt.Printf("Cannot schedule %s after registering: %s\n", displayName, reason)
			d.recordApplyRefused(ctx, input, reason)
		case scheduleResultUnregistered:
			// Registered but promote found no row: impossible (the upsert guaranteed
			// it) — surface it durably rather than silently.
			fmt.Printf("NOTIFY upgrade_apply: %s registered but did not promote (unexpected)\n", displayName)
			d.recordApplyRefused(ctx, input, "registered but promote found no row (unexpected)")
		}
	}
}

// onApplyScheduled finishes a successful database-owned schedule: announce and
// clear any prior durable apply-refusal (STATBUS-183 piece 3). Older-candidate
// supersede is part of public.upgrade_schedule's transaction.
func (d *Service) onApplyScheduled(ctx context.Context, displayName string) {
	fmt.Printf("Scheduled upgrade to %s\n", displayName)
	d.clearApplyRefused(ctx)
}

// promoteExistingCandidate calls the one database-owned schedule door (NO insert);
// shared by the first pass and the post-register re-run in onScheduledNotify.
func (d *Service) promoteExistingCandidate(ctx context.Context, commitSHA CommitSHA) (scheduleResult, error) {
	result, err := scanScheduleResult(d.queryConn.QueryRow(ctx,
		`SELECT schedule_result, upgrade_id, landed_state, superseded_count
		   FROM public.upgrade_schedule($1, false)`,
		string(commitSHA)))
	if err != nil {
		d.markPgInvariantTerminal(err, "service.go:promoteExistingCandidate:upgrade_schedule")
		return "", err
	}
	return result, nil
}

// registerTarget registers an already-resolved target through the SINGLE guarded
// register path (upsertCandidate, which carries the STATBUS-169 tag↔commit
// write-guard internally). RunRegister (the CLI verb) and onScheduledNotify (the
// STATBUS-183 apply-race fix) both go through here, so NO candidate row is ever
// created except via that guard — the surviving-and-stronger form of the 086
// require-register invariant. Returns the target's commit + display name.
func (d *Service) registerTarget(ctx context.Context, target UpgradeTarget) (CommitSHA, string, error) {
	var sha CommitSHA
	var tag, displayName string
	switch t := target.(type) {
	case TaggedTarget:
		sha, tag, displayName = t.SHA, string(t.Tag), string(t.Tag)
	case UntaggedTarget:
		sha, displayName = t.SHA, string(commitShort(t.SHA))
	default:
		return "", "", fmt.Errorf("unhandled target type %T", target)
	}
	committedAt, describe, subject, err := d.commitMeta(sha)
	if err != nil {
		return sha, displayName, err
	}
	meta := candidateMeta{committedAt: committedAt}
	if tag != "" {
		meta.tags = []string{tag}
		meta.releaseStatus = ClassifyReleaseShape(tag).ReleaseStatus()
		meta.summary = tag
	} else {
		meta.commitVersion = describe
		meta.summary = subject
	}
	if _, err := d.upsertCandidate(ctx, sha, meta); err != nil {
		return sha, displayName, err
	}
	return sha, displayName, nil
}

// recordApplyRefused persists a durable apply-refusal signal (STATBUS-183 piece 3)
// so a refused/undeliverable poke is visible to STATBUS-170 phase-2 polling and the
// admin UI, not just the daemon journal — killing the incident's silence class even
// for refuse paths we have not imagined yet. Single latest-outcome key; occurred_at
// is DB-authoritative. Best-effort: a signal-write failure must not mask the refusal.
func (d *Service) recordApplyRefused(ctx context.Context, input, reason string) {
	if _, err := d.queryConn.Exec(ctx,
		`INSERT INTO public.system_info (key, value, updated_at)
		 VALUES ('upgrade_apply_refused',
		         jsonb_build_object('input', $1::text, 'reason', $2::text, 'occurred_at', clock_timestamp())::text,
		         clock_timestamp())
		 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp()`,
		input, reason); err != nil {
		fmt.Printf("could not persist upgrade_apply_refused signal: %v\n", err)
	}
}

// clearApplyRefused removes the durable apply-refusal signal on the next successful
// schedule (STATBUS-183 piece 3). Best-effort.
func (d *Service) clearApplyRefused(ctx context.Context) {
	if _, err := d.queryConn.Exec(ctx,
		`DELETE FROM public.system_info WHERE key = 'upgrade_apply_refused'`); err != nil {
		fmt.Printf("could not clear upgrade_apply_refused signal: %v\n", err)
	}
}

// --- One-shot CLI entrypoints (register / schedule / check) ----------
//
// These run as a short-lived `./sb upgrade <verb>` process, NOT the daemon.
// They connect LOCK-FREE (runOneShot → connect, never acquireAdvisoryLock) so
// they are safe to run alongside a live daemon, and reuse the daemon's pgx code
// paths (resolveUpgradeTarget, upsertCandidate) instead of re-expressing SQL in
// psql. STATBUS-086.

// runOneShot opens a DB connection (no advisory lock — that is the daemon's,
// taken only in Run), invokes fn, and closes the connection on return.
func (d *Service) runOneShot(ctx context.Context, fn func(context.Context) error) error {
	if err := d.connect(ctx); err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}
	defer func() {
		if d.listenConn != nil {
			_ = d.listenConn.Close(context.Background())
		}
		if d.queryConn != nil {
			_ = d.queryConn.Close(context.Background())
		}
	}()
	return fn(ctx)
}

// commitMeta resolves the committed-at time, git-describe label, and subject
// line for a commit from the local repo — the metadata register needs to upsert
// a candidate (mirrors what discovery captures from the tag/commit).
func (d *Service) commitMeta(sha CommitSHA) (committedAt time.Time, describe, subject string, err error) {
	out, e := runCommandOutput(d.projDir, "git", "show", "-s", "--format=%cI%n%s", string(sha))
	if e != nil {
		return time.Time{}, "", "", fmt.Errorf("git show %s: %w (%s)", commitShort(CommitSHA(sha)), e, strings.TrimSpace(out))
	}
	parts := strings.SplitN(strings.TrimSpace(out), "\n", 2)
	committedAt, err = time.Parse(time.RFC3339, strings.TrimSpace(parts[0]))
	if err != nil {
		return time.Time{}, "", "", fmt.Errorf("parse committed-at %q for %s: %w", parts[0], commitShort(CommitSHA(sha)), err)
	}
	if len(parts) > 1 {
		subject = strings.TrimSpace(parts[1])
		if len(subject) > 120 {
			subject = subject[:120]
		}
	}
	desc, _ := runCommandOutput(d.projDir, "git", "describe", "--tags", "--always", string(sha))
	describe = strings.TrimSpace(desc)
	return committedAt, describe, subject, nil
}

// ensureCommitLocal makes a full-SHA commit available in the local repo before
// register resolves and reads it. The deploy-by-commit doctrine (STATBUS-169)
// promises any box can be poked to any commit; but a standalone box only fetches
// during an upgrade it is already running, so a fresh `register <sha>` for an
// unfetched commit otherwise died at `git show <sha>: bad object` (rune, commit
// 5e037225 — same fetch-before-use class as STATBUS-153). Idempotent: a commit
// already present is a no-op (no network). Gated to the full 40-hex shape by the
// caller — GitHub's want-by-SHA needs the full SHA, and that is the shape the
// deploy poke sends; a release TAG carries its own `git fetch --tags` concern
// (discovery / apply-latest), out of scope here.
// ensureCommitLocal makes <ref> resolvable in the LOCAL repo (STATBUS-169
// deploy-by-commit; generalized for tags in STATBUS-183 A1). cat-file
// short-circuits with NO network when the ref is already present. On a miss it
// fetches by CLASS (A1):
//   - a full commit SHA → `git fetch origin <sha>` (the rc.04 register-by-commit form).
//   - ANYTHING ELSE (a release tag) → the REFSPEC form
//     `git fetch origin refs/tags/<ref>:refs/tags/<ref>`. Plain `git fetch origin
//     <tag>` lands the commit in FETCH_HEAD ONLY and does NOT create the local tag
//     ref, so a subsequent `git rev-parse <tag>` still fails — the exact rc.06 race
//     this fix targets. The explicit refspec writes refs/tags/<ref> locally.
//
// fetchTimeout bounds the network fetch: RunRegister (a one-shot CLI process) can
// use the 2m default, but onScheduledNotify runs on the daemon's MAIN goroutine
// under WatchdogSec=120s, so it passes a short timeout (STATBUS-183 A3).
func (d *Service) ensureCommitLocal(ref string, fetchTimeout time.Duration) error {
	if d.commitObjectPresent(ref) {
		return nil // already local — no network
	}
	var fetchArgs []string
	if isCommitSHAShape(ref) {
		fetchArgs = []string{"fetch", "origin", ref}
	} else {
		fetchArgs = []string{"fetch", "origin", "refs/tags/" + ref + ":refs/tags/" + ref}
	}
	if out, err := runCommandOutputTimeout(d.projDir, fetchTimeout, "git", fetchArgs...); err != nil {
		return fmt.Errorf("could not fetch %s to make it local: %w\n  output: %s",
			ShortForDisplay(ref), err, strings.TrimSpace(out))
	}
	return nil
}

// RunRegister records a release tag or commit as an upgrade candidate
// (state='available') and pokes the service to prepare it (NOTIFY upgrade_check).
// Shares the same upsertCandidate path as discovery. `./sb upgrade register`.
// RunDismiss marks a candidate DISMISSED — the operator's deliberate "not this
// one" (STATBUS-250's first deliverable). Until now dismissal existed only as an
// app action (a PATCH from the admin UI), so an operator who decided against a
// candidate had no CLI way to say so, and a script could not do it at all
// without writing the row directly.
//
// THE WRITE IS THE PAIR, NOT THE TIMESTAMP. state='dismissed' AND dismissed_at
// go together, matching the app's own PATCH: chk_upgrade_state_attributes
// REJECTS a row whose state and timestamp columns disagree, so a half-write is a
// failed statement rather than a silently contradictory row (STATBUS-242's
// state+_at pair ruling). One UPDATE, both columns.
//
// A DISMISSAL OF NOTHING IS A TYPO, NOT A NO-OP. If no row matches, this refuses
// and prints what rows DO exist — an operator who mistypes a version must not be
// told "done" while the candidate they meant to stop stays offered.
//
// WHY DISMISSED ROWS STOP BEING OFFERED, by construction rather than by a new
// filter: every offer path selects state IN ('available', 'scheduled') —
// supersedeBelowInstalled (:4455), the pending-candidate sweeps (:4511, :4541),
// and the supersede-on-claim guard (:1709). 'dismissed' is in none of them, so
// no automatic path can pick the row up again.
// operator (STATBUS-317): see RunSchedule's doc comment — same contract.
func (d *Service) RunDismiss(ctx context.Context, input string, operator string) error {
	return d.runOneShot(ctx, func(ctx context.Context) error {
		// Same resolution as register (tag, commit_short, or full SHA), so an
		// operator uses one vocabulary across the subcommand set.
		target, err := resolveUpgradeTarget(ctx, d, input)
		if err != nil {
			return fmt.Errorf("resolve %q: %w", input, err)
		}
		// Same type-switch every other target consumer uses (:4631, :4758).
		var commitSHA CommitSHA
		var targetLabel string
		switch t := target.(type) {
		case TaggedTarget:
			commitSHA = t.SHA
			targetLabel = string(t.Tag)
		case UntaggedTarget:
			commitSHA = t.SHA
			targetLabel = string(commitShort(t.SHA))
		default:
			return fmt.Errorf("unhandled upgrade target type %T for %q", target, input)
		}
		sha := string(commitSHA)
		_ = targetLabel

		var id int
		var state string
		var displayVersion string
		err = d.queryConn.QueryRow(ctx,
			`SELECT id, state, COALESCE(commit_version, '')
			   FROM public.upgrade
			  WHERE commit_sha = $1
			  ORDER BY id DESC LIMIT 1`, sha).Scan(&id, &state, &displayVersion)
		if err != nil {
			return d.dismissNoSuchRow(ctx, input, sha, err)
		}

		switch state {
		case "dismissed":
			fmt.Printf("%s (commit %s) is already dismissed — nothing to do.\n", labelOrCommit(displayVersion, sha), commitShort(CommitSHA(sha)))
			return nil
		case "completed":
			// Refusing here is the honest answer: dismissing an installed
			// version does not uninstall it, and pretending otherwise would be
			// the most expensive kind of wrong.
			return fmt.Errorf("%s is the version this box has COMPLETED — dismissing it would not uninstall anything.\n  To move to a different version, register and schedule that version instead", labelOrCommit(displayVersion, sha))
		}

		// STATBUS-317: see the matching comment in scheduleStep — actor GUC
		// and this UPDATE must share one transaction.
		var ct pgconn.CommandTag
		err = d.withActorTx(ctx, operator, func(ctx context.Context, tx pgx.Tx) error {
			var execErr error
			ct, execErr = tx.Exec(ctx,
				`UPDATE public.upgrade
				    SET state = 'dismissed', dismissed_at = now()
				  WHERE id = $1 AND state <> 'dismissed'`, id)
			return execErr
		})
		if err != nil {
			return fmt.Errorf("dismiss %s: %w", labelOrCommit(displayVersion, sha), err)
		}
		if ct.RowsAffected() == 0 {
			return fmt.Errorf("dismiss %s: the row changed underneath this command (state was %q) — re-run to see its current state", labelOrCommit(displayVersion, sha), state)
		}

		fmt.Printf("Dismissed %s (commit %s), previously %s.\n", labelOrCommit(displayVersion, sha), commitShort(CommitSHA(sha)), state)
		fmt.Println("It will not be offered or installed automatically again.")
		fmt.Printf("To take it after all: %s %s\n", "./sb upgrade schedule", labelOrCommit(displayVersion, sha))
		return nil
	})
}

// dismissNoSuchRow renders the refusal for a version with no candidate row, and
// SHOWS WHAT EXISTS. A bare "not found" leaves the operator guessing whether
// they mistyped the version or the box never saw it.
func (d *Service) dismissNoSuchRow(ctx context.Context, input, sha string, cause error) error {
	var lines []string
	rows, qerr := d.queryConn.Query(ctx,
		`SELECT COALESCE(commit_version, commit_sha), state
		   FROM public.upgrade ORDER BY id DESC LIMIT 10`)
	if qerr == nil {
		defer rows.Close()
		for rows.Next() {
			var v, st string
			if rows.Scan(&v, &st) == nil {
				lines = append(lines, fmt.Sprintf("    %-28s %s", v, st))
			}
		}
	}
	msg := fmt.Sprintf("no candidate row for %q (commit %s) — nothing was dismissed", input, commitShort(CommitSHA(sha)))
	if len(lines) > 0 {
		msg += ".\n  Rows this box knows about (newest first):\n" + strings.Join(lines, "\n")
	} else if qerr != nil {
		msg += fmt.Sprintf(".\n  (could not list the existing rows: %v)", qerr)
	} else {
		msg += ".\n  This box has no upgrade rows at all."
	}
	_ = cause
	return errors.New(msg)
}

// labelOrCommit prefers the human version string and falls back to the short
// commit, so no message ever prints an empty name.
func labelOrCommit(version, sha string) string {
	if strings.TrimSpace(version) != "" {
		return version
	}
	return string(commitShort(CommitSHA(sha)))
}

func (d *Service) RunRegister(ctx context.Context, input string) error {
	return d.runOneShot(ctx, func(ctx context.Context) error {
		return d.registerStep(ctx, input)
	})
}

// registerStep is RunRegister's body WITHOUT the one-shot wrapper, so `apply`
// can compose register and schedule inside a SINGLE connection (STATBUS-258).
// Two runOneShots would open two connections and leave a window between them in
// which the row exists but is unscheduled — visible to an operator watching
// `upgrade list`, and a state nothing else in the product ever produces.
func (d *Service) registerStep(ctx context.Context, input string) error {
	{
		// Register-by-commit owns "make the target commit local" (STATBUS-169
		// deploy-by-commit doctrine) — BEFORE resolveUpgradeTarget, so its
		// TagsAtCommit probe and the later commitMeta both read a present commit.
		if isCommitSHAShape(input) {
			// One-shot CLI process (no watchdog) → the 2m default is fine here.
			if err := d.ensureCommitLocal(input, 2*time.Minute); err != nil {
				return err
			}
		}
		target, err := resolveUpgradeTarget(ctx, d, input)
		if err != nil {
			return fmt.Errorf("resolve %q: %w", input, err)
		}
		// Register through the SINGLE guarded path shared with onScheduledNotify
		// (STATBUS-183) — the STATBUS-169 tag↔commit write-guard lives inside
		// upsertCandidate, so a candidate row is only ever created here.
		sha, displayName, err := d.registerTarget(ctx, target)
		if err != nil {
			return fmt.Errorf("register %s: %w", displayName, err)
		}
		fmt.Printf("Registered candidate %s (commit %s)\n", displayName, commitShort(CommitSHA(sha)))
		if _, err := d.queryConn.Exec(ctx, "NOTIFY upgrade_check"); err != nil {
			fmt.Printf("(could not poke the service to prepare — NOTIFY upgrade_check: %v)\n", err)
		} else {
			fmt.Println("Poked the service to prepare it (NOTIFY upgrade_check).")
		}
		return nil
	}
}

// RunSchedule promotes an ALREADY-REGISTERED candidate to 'scheduled' (the DB
// trigger then fires NOTIFY upgrade_apply and the service runs it). FAILS FAST
// if the target has no candidate row — schedule REQUIRES register (STATBUS-086).
// `./sb upgrade schedule <target> [--recreate]`.
// operator (STATBUS-317) is the human identity to record for this
// transition — empty means none was given (CLI resolves --operator / an
// interactive prompt / absent BEFORE calling this; see cli/cmd/upgrade.go's
// resolveOperator). Threaded through, never resolved here: this package has
// no TTY concerns, only the write.
func (d *Service) RunSchedule(ctx context.Context, input string, recreate bool, operator string) error {
	return d.runOneShot(ctx, func(ctx context.Context) error {
		return d.scheduleStep(ctx, input, recreate, operator)
	})
}

// scheduleStep is RunSchedule's body without the one-shot wrapper. See
// registerStep for why the split exists.
func (d *Service) scheduleStep(ctx context.Context, input string, recreate bool, operator string) error {
	{
		target, err := resolveUpgradeTarget(ctx, d, input)
		if err != nil {
			return fmt.Errorf("resolve %q: %w", input, err)
		}
		var sha CommitSHA
		var displayName string
		switch t := target.(type) {
		case TaggedTarget:
			sha = t.SHA
			displayName = string(t.Tag)
		case UntaggedTarget:
			sha = t.SHA
			displayName = string(commitShort(t.SHA))
		default:
			return fmt.Errorf("unhandled target type %T", target)
		}

		// STATBUS-291: A DELIBERATE TARGET OFF THIS BOX'S CHANNEL IS ANNOUNCED,
		// NOT REFUSED — and the asymmetry with RunCheck is the whole design.
		//
		// Automatic discovery FILTERS: a box is never OFFERED something outside
		// its channel. But a named target arriving here is an INSTRUCTION from a
		// human who typed the version, and that is the King's candidate-addressed
		// deliberate deployment (STATBUS-258). Refusing it would break the one
		// mechanism that replaced the retired master-to-X buttons.
		//
		// Silence would be just as wrong in the other direction: putting a
		// prerelease onto a production installation is a real deviation, and a
		// deviation nobody is told about is how a box quietly stops being what
		// the fleet believes it is. So it is stated plainly, once, at the moment
		// it happens — then it proceeds.
		//
		// ONLY A TAGGED TARGET IS CHECKED, DELIBERATELY. A bare commit SHA has no
		// channel to be off: channels are defined over TAG SHAPE
		// (TagMatchesChannel / ClassifyReleaseShape), and an untagged commit has
		// no shape to classify. Announcing "off-channel" for it would be inventing
		// a judgement the model cannot make.
		//
		// The visible consequence, stated so the next reader does not file it as a
		// bug: CI's own dev door schedules untagged commits silently, and that is
		// correct — deploy-by-commit is a distinct, deliberate mechanism
		// (STATBUS-169), not an off-channel accident.
		//
		// The alternative — resolve the SHA to a tag just to announce — was
		// considered and rejected: a commit may carry several tags or none, so the
		// resolution would sometimes have to GUESS which tag "means" the target,
		// and a guess is a poor basis for a deviation notice whose entire value is
		// that it states a fact.
		if tagged, ok := target.(TaggedTarget); ok {
			if !TagMatchesChannel(string(tagged.Tag), d.channel) {
				fmt.Printf("NOTE: %s is not on this box's %q channel — scheduling it anyway because you named it explicitly.\n", displayName, d.channel)
				fmt.Printf("      Automatic discovery would not have offered this version here; a deliberate install is not blocked, only announced.\n")
			}
		}

		// public.upgrade_schedule is the one reset, refusal, supersede, and
		// un-park contract. STATBUS-317: the actor GUC (if operator is non-empty)
		// and the function call must share one transaction so the state-log trigger
		// records the operator rather than an absent actor.
		var result scheduleResult
		err = d.withActorTx(ctx, operator, func(ctx context.Context, tx pgx.Tx) error {
			var queryErr error
			result, queryErr = scanScheduleResult(tx.QueryRow(ctx,
				`SELECT schedule_result, upgrade_id, landed_state, superseded_count
				   FROM public.upgrade_schedule($1, $2)`,
				string(sha), recreate))
			return queryErr
		})
		if err != nil {
			return fmt.Errorf("schedule %s: %w", displayName, err)
		}

		switch result {
		case scheduleResultScheduled:
			fmt.Printf("Scheduled upgrade to %s\n", displayName)
			if recreate {
				fmt.Printf("Recreate mode requested for %s (persisted on the upgrade row)\n", displayName)
			}
		case scheduleResultAlreadyScheduled:
			fmt.Printf("Version %s is already queued — no action needed\n", displayName)
		case scheduleResultInProgress:
			return fmt.Errorf("%s is in_progress — refusing to reschedule; let the in-progress upgrade finish or recover first", displayName)
		case scheduleResultRestoreReattemptRequired:
			return fmt.Errorf("%s has a retained backup and requires a restore reattempt — run ./sb install; it was not queued", displayName)
		case scheduleResultUnregistered:
			return errNotRegistered(displayName, input)
		case scheduleResultSuperseded:
			return fmt.Errorf("%s is older than an installed completed candidate — it was not queued", displayName)
		}

		// STATBUS-092: recreate intent is DURABLE on the row (set in the UPDATE
		// inside public.upgrade_schedule), read by executeScheduled at claim time. No out-of-band
		// ':recreate' NOTIFY — that raced the trigger's sha-NOTIFY, which the
		// daemon processed first and ran the upgrade as normal before the
		// ':recreate' NOTIFY was dequeued. The scheduling UPDATE's trigger
		// (upgrade_notify_daemon) already NOTIFYs the daemon to wake up.
		return nil
	}
}

// ResolveToCommit resolves any upgrade-target reference (release tag, commit
// short, or full sha) to its canonical commit via the SINGLE git-authoritative
// resolver (resolveUpgradeTarget) — one resolution shape for every tag→commit
// read (STATBUS-169: the last tag-as-selector site, apply-latest's "already at
// latest?" skip-check, folds onto this). Runs in a one-shot connection because
// the resolver's cache cross-check reads the DB.
func (d *Service) ResolveToCommit(ctx context.Context, input string) (CommitSHA, error) {
	var sha CommitSHA
	err := d.runOneShot(ctx, func(ctx context.Context) error {
		target, terr := resolveUpgradeTarget(ctx, d, input)
		if terr != nil {
			return terr
		}
		switch t := target.(type) {
		case TaggedTarget:
			sha = t.SHA
		case UntaggedTarget:
			sha = t.SHA
		default:
			return fmt.Errorf("unhandled target type %T", target)
		}
		return nil
	})
	return sha, err
}

// RunCheck fetches releases from GitHub and registers each one newer than the
// running version as a candidate (via the shared upsertCandidate path), then
// pokes the service to prepare. `./sb upgrade check`.
func (d *Service) RunCheck(ctx context.Context) error {
	// STATBUS-255: discovery reads GIT TAGS, not the GitHub releases API.
	//
	// THIS is the command that exhausted the quota. The unauthenticated API
	// allows 60 requests/hour PER IP; all seven niue slots share one and dev
	// polls every five minutes, so on 2026-08-19 every notify job 403'd (run
	// 32247740861). Resolving the CHANNEL over git (the first half of this
	// entry) did not fix it, because this command never went through the
	// resolver — it called FetchReleases directly.
	//
	// EVERY FIELD IT NEEDS, git already has: the tag name; the commit (git IS
	// the authority, and the old path already fell back to RevParse when the
	// payload omitted it); the timestamp; and the release status, which was
	// ALREADY derived from the tag name via ClassifyReleaseShape rather than
	// from GitHub's prerelease flag. Nothing here ever needed the API.
	//
	// THE ONE REAL DIFFERENCE, and why it is safe — verified, not assumed. The
	// API returned PUBLISHED RELEASES; git returns every tag, including one
	// pushed without a release. Such a tag can now become a candidate, and it
	// CANNOT be installed: verifyArtifacts marks release_builds_status when the
	// manifest is absent (:4111-4144), and the scheduled path then UNSCHEDULES
	// it with "Release assets not ready … Will be available when CI finishes"
	// (:5604-5634) instead of attempting an install. The failure mode is a
	// visible wait, not a broken box — loud, and self-correcting when CI lands.
	tags, err := DiscoverTagsViaGit(d.projDir)
	if err != nil {
		return fmt.Errorf("discover tags via git: %w", err)
	}
	if len(tags) == 0 {
		fmt.Println("No release tags found")
		return nil
	}

	// STATBUS-291: THIS COMMAND DISCOVERS WHAT THE BOX MAY TAKE, SO IT FILTERS
	// BY CHANNEL — exactly as the service's own discovery does at :4047.
	//
	// Without this, `./sb upgrade check` on a production box registered every
	// tag merely NEWER than the running version, and `upgrade list` then showed
	// a release candidate as "available" on a stable box. Observed on ua (born
	// rc.10, channel stable) listing v2026.08.0-rc.11. The topology's promise —
	// production boxes are never OFFERED candidates — was broken at the one
	// surface a human actually reads, and nothing downstream would have stopped
	// them scheduling it.
	//
	// The gap predates the git-discovery switch (the API-based version had the
	// same single version guard), but git discovery WIDENS it: git returns every
	// tag, including ones with no published release, where the old API path
	// returned published releases only.
	//
	// PLACEMENT IS DELIBERATE AND MUST NOT MOVE. The filter belongs HERE, not in
	// the shared upsertCandidate, because that helper is also reached by
	// registerStep — the named-target path behind `./sb upgrade register/apply`.
	// That is how a human deliberately installs a specific candidate on a
	// specific box, and filtering there would block every off-channel deliberate
	// deployment fleet-wide. AUTOMATIC DISCOVERY FILTERS; A NAMED TARGET IS AN
	// INSTRUCTION, NOT AN OFFER, and is announced rather than refused (see
	// scheduleStep).
	filtered := FilterTagsByChannel(tags, d.channel)
	if len(filtered) == 0 {
		// Distinct from "no tags at all": tags exist, none are for this box.
		// Saying "none found" here would read as a discovery failure and send
		// an operator hunting for a problem that is correct behaviour.
		//
		// THIS RETURNS BEFORE runOneShot, AND THAT COSTS NOTHING — checked, not
		// assumed, because on a stable box where every current tag is an rc this
		// is the DEFAULT path of every `upgrade check`, not an edge case.
		//
		// runOneShot (:4779) is only a database connection lifecycle: connect,
		// defer close, call the closure. It carries no poke of its own. The one
		// signal this command sends is `NOTIFY upgrade_check` at the end of the
		// closure, and that is ALREADY conditional on `registered > 0`. With no
		// tag matching the channel nothing can be registered, so the notify would
		// not fire even if we did enter the closure. Skipping it therefore loses
		// exactly one thing: a connect/close pair and a line reading
		// "Registered 0 new candidate(s)."
		//
		// The poke means "a new candidate exists, go prepare it". Sending it when
		// the box was offered nothing would be a lie in the direction that wastes
		// the service's time, not one that loses work.
		fmt.Printf("Found %d release tag(s), none matching channel %q — nothing to register\n", len(tags), d.channel)
		return nil
	}
	// ── THE COMPARABILITY GATE (STATBUS-293) ─────────────────────────────────
	// The same rule discovery applies, at the OTHER path that registers
	// candidates. Both must apply it or the defect simply moves: this is the
	// CLI-reached twin (`./sb upgrade check`), and it is the path an operator
	// runs by hand when something already looks wrong — the worst possible
	// moment to hand back a list of downgrades presented as upgrades.
	//
	// Refused BEFORE runOneShot: with nothing registrable there is no candidate
	// to prepare, so opening the connection and sending the poke would only
	// cost a connect/close pair and tell the service to go prepare nothing.
	if _, versionOrderable := CompareVersions(d.version, d.version); !versionOrderable {
		fmt.Printf(`Found %d release tag(s), %d matching channel %q — registering NONE.

  Installed version: %s — this is a commit, not a release tag, so no release
  can be ranked against it. Registering anyway would mean guessing, and a wrong
  guess offers a DOWNGRADE as an upgrade (STATBUS-293).

  Two ways forward:
    - Install a specific version now:        ./sb upgrade apply <version>
    - Restore automatic discovery: install a release tag (./sb upgrade apply
      <release-tag>). Once the box is ON a tag, discovery resumes by itself.
`, len(tags), len(filtered), d.channel, d.version)
		return nil
	}

	return d.runOneShot(ctx, func(ctx context.Context) error {
		fmt.Printf("Found %d release tag(s), %d matching channel %q:\n", len(tags), len(filtered), d.channel)
		registered := 0
		for _, t := range filtered {
			fmt.Printf("  %s (%s)\n", t.TagName, t.PublishedAt.Format("2006-01-02"))
			// Register only tags strictly newer than the running version — the
			// same guard discovery uses; avoids re-recording ancient tags.
			// Orderability is settled above, before this closure runs.
			if ord, ordered := CompareVersions(t.TagName, d.version); !ordered || ord <= 0 {
				continue
			}
			sha := t.CommitSHA
			if !IsCommitSHA(sha) {
				resolved, rerr := d.RevParse(ctx, t.TagName)
				if rerr != nil {
					fmt.Printf("    (could not resolve commit for %s: %v — not registered)\n", t.TagName, rerr)
					continue
				}
				sha = string(resolved)
			}
			if _, uerr := d.upsertCandidate(ctx, CommitSHA(sha), candidateMeta{
				committedAt:   t.PublishedAt,
				tags:          []string{t.TagName},
				releaseStatus: ClassifyReleaseShape(t.TagName).ReleaseStatus(),
				summary:       t.TagName,
			}); uerr != nil {
				fmt.Printf("    (failed to register %s: %v)\n", t.TagName, uerr)
				continue
			}
			registered++
		}
		fmt.Printf("Registered %d new candidate(s).\n", registered)
		if registered > 0 {
			if _, err := d.queryConn.Exec(ctx, "NOTIFY upgrade_check"); err != nil {
				fmt.Printf("(could not poke the service to prepare — NOTIFY upgrade_check: %v)\n", err)
			}
		}
		return nil
	})
}

// --- CommitLookup implementation -------------------------------------
//
// Service satisfies the CommitLookup interface used by
// resolveUpgradeTarget (see commit.go). These methods are the
// DB/git-accessing primitives; all shape detection lives in commit.go.

// CommitSHAsByTag satisfies CommitLookup — returns the DISTINCT commit_shas of
// every row whose commit_tags cache carries the tag (STATBUS-169). No LIMIT: a
// tag on more than one commit is a stale-cache signal the resolver must SEE, not
// a nondeterministic single pick.
func (d *Service) CommitSHAsByTag(ctx context.Context, tag ReleaseTag) ([]CommitSHA, error) {
	rows, err := d.queryConn.Query(ctx,
		"SELECT DISTINCT commit_sha FROM public.upgrade WHERE $1 = ANY(commit_tags)",
		string(tag))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []CommitSHA
	for rows.Next() {
		var sha string
		if err := rows.Scan(&sha); err != nil {
			return nil, err
		}
		out = append(out, CommitSHA(sha))
	}
	return out, rows.Err()
}

// RevParse satisfies CommitLookup.
func (d *Service) RevParse(_ context.Context, ref string) (CommitSHA, error) {
	// Peel with ^{commit} (STATBUS-169 follow-up). Release tags are ANNOTATED (cut
	// with `git tag -m`), and a bare `git rev-parse <annotated-tag>` returns the TAG
	// OBJECT sha, not the commit it points at. ^{commit} dereferences an annotated
	// tag to its commit and is a no-op on a commit or a lightweight tag — so every
	// caller (all want the commit; this method's return type is CommitSHA) gets the
	// commit regardless of tag shape. Same idiom already used at restoreGitState /
	// the pre-upgrade probe. Found live: the AC#1 write-guard refused every rc.04
	// register with "tag <t> points at commit <tag-object>, not <commit>".
	out, err := runCommandOutput(d.projDir, "git", "rev-parse", "--verify", ref+"^{commit}")
	if err != nil {
		return "", err
	}
	return NewCommitSHA(strings.TrimSpace(out))
}

// TagsAtCommit satisfies CommitLookup.
func (d *Service) TagsAtCommit(ctx context.Context, sha CommitSHA) ([]string, error) {
	var tags []string
	err := d.queryConn.QueryRow(ctx,
		"SELECT commit_tags FROM public.upgrade WHERE commit_sha = $1",
		string(sha)).Scan(&tags)
	if err != nil {
		// Not in DB yet — consult git for tags at this commit.
		out, gErr := runCommandOutput(d.projDir, "git", "tag", "--points-at", string(sha))
		if gErr != nil {
			return nil, nil
		}
		for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
			if t := strings.TrimSpace(line); t != "" {
				tags = append(tags, t)
			}
		}
	}
	return tags, nil
}

// claimScheduledUpgrade is the single claim path (STATBUS-159): before claiming
// scheduled row `id` for this daemon, it DISPLACES any standing park to an honest
// 'superseded' terminal — so a fix release proceeds while a park stands (a parked
// row exists precisely to WAIT for that fix; the park itself must not block it).
// Consolidates the two former claim sites (ExecuteUpgradeInline, executeScheduled):
// their mutating claim SQL (SET + WHERE) was byte-identical; only the RETURNING
// projection differed, so this returns the SUPERSET (commit_tags, recreate) and
// each caller uses what it needs.
//
// Ladder, crash-safe by ordering:
//
//	step A — if a service-held flag points at the parked in_progress row we are
//	  about to displace, remove it FIRST. A displaced row's flag is dead weight;
//	  removing it before the displace closes the window where a stale flag could
//	  route resumeNewSb at a now-superseded row. Crash after A leaves B parked
//	  with no flag — a state no recovery resumes; the next claim re-runs this
//	  idempotent ladder.
//	step B — ONE explicit transaction: displace THEN claim. Two statements, NOT a
//	  data-modifying CTE (an unreferenced CTE's order vs the outer UPDATE's
//	  unique-index check is unspecified). The displacement WHERE (state='in_progress'
//	  AND recovery_parked_at IS NOT NULL) is the guard: a LIVE unparked in_progress
//	  row matches 0 rows, so the claim still hits upgrade_single_in_progress's 23505
//	  loudly — single-in-progress protection is UNCHANGED for genuinely live
//	  upgrades. parked⇒in_progress + single-in-progress guarantee at most ONE
//	  displaceable row. The marker is cleared in the SAME UPDATE, so
//	  chk_upgrade_parked_requires_in_progress (STATBUS-154) holds by construction;
//	  the 154 upgrade_state_log trigger audits the in_progress→superseded,
//	  parked→NULL transition under this daemon's application_name. No new siren —
//	  the park sirened at park time; the displacement is the remedy arriving.
//
// upgradeClaimSnapshot freezes the immutable public.upgrade columns at the claim
// boundary. The upgrade later closes every database connection before entering
// maintenance, so this value is the only truthful source for the maintenance
// flag's immutable row snapshot.
//
// Field order mirrors the claim SELECT and its Scan destinations. ImmutableJSON
// is PostgreSQL's to_json rendering of the same RETURNING row, with an explicit
// projection preserving the maintenance-file contract's key order.
type upgradeClaimSnapshot struct {
	ID                int
	CommitVersion     string
	CommitSHA         string
	FromCommitVersion string
	StartedAt         time.Time
	ImmutableJSON     string
}

type scheduledUpgradeClaim struct {
	CommitTags []string
	Recreate   bool
	Snapshot   upgradeClaimSnapshot
}

// Returns pgx.ErrNoRows verbatim when the claim matched 0 rows (row no longer
// 'scheduled' — another actor claimed it first); callers map it to their own message.
func (d *Service) claimScheduledUpgrade(ctx context.Context, id int) (scheduledUpgradeClaim, error) {
	var claim scheduledUpgradeClaim
	// STATBUS-307 (architect ruling: block-by-absence is not an acceptable
	// contract) — the arriving job's own first act, before anything else in
	// this function: refuse if the last config generate parked on an
	// unresolved policy ambiguity (which release CHANNEL this box follows).
	// This is the ONE function both dispatch paths share (ExecuteUpgradeInline
	// for ./sb install's inline dispatch, executeScheduled for the daemon's own
	// periodic pickup — see this function's header comment), so checking here
	// covers both with no duplication, matching the same "the arriving job
	// checks for itself" principle STATBUS-246 already applies to the release
	// chain's decision points.
	//
	// WHY THIS IS LOAD-BEARING, not belt-and-suspenders: today a parked box
	// only fails to execute because the upgrade path happens to need a fresh
	// config, which it cannot get — a property held BY ACCIDENT. A future
	// refactor that tolerates a stale-but-valid config (exactly what
	// STATBUS-307's own boot-time fix just taught the daemon to do) would
	// silently unpark every parked box with nothing going red, because
	// nothing here was ever checking. Executing a scheduled candidate while
	// the channel is genuinely ambiguous risks installing it for the WRONG
	// channel on a production box (the STATBUS-291 harm) — this is a
	// different "park" than the recovery_parked_at row-level one displaced
	// below: that one is about a SPECIFIC upgrade's own recovery outcome;
	// this one is a FILE-level marker about whether the box's release
	// policy is even resolved at all, and it must gate every dispatch
	// regardless of which specific row is being claimed.
	//
	// FAILS CLOSED ON A READ ERROR TOO (STATBUS-039/111/159's standing
	// doctrine: unverified is not permission) — if the marker cannot be
	// read, that is not evidence the box is fine; refuse rather than guess.
	if marker, merr := ReadConfigRefusalMarker(d.projDir); merr != nil {
		return scheduledUpgradeClaim{}, fmt.Errorf("refusing to execute upgrade id=%d: could not confirm the box's config-policy state (%v) — resolve the marker read before dispatching", id, merr)
	} else if marker != nil {
		return scheduledUpgradeClaim{}, fmt.Errorf(
			"refusing to execute upgrade id=%d: the last config generate refused with an unresolved policy ambiguity (refused at %s) — the box does not know which release channel it follows, so dispatching a candidate now could install it for the wrong one. %s",
			id, marker.RefusedAt.Format(time.RFC3339), marker.Message)
	}

	// Serialize the claim transaction with cleanup-only rollback finalization.
	// The daemon's session-level lock is re-entrant on this same connection; an
	// inline ./sb install gets the transaction lock only when no live service owns
	// it. This closes the check-then-claim race around ROLLBACK_FINISH_PENDING.
	tx, txErr := d.queryConn.Begin(ctx)
	if txErr != nil {
		return scheduledUpgradeClaim{}, fmt.Errorf("claim id=%d: begin tx: %w", id, txErr)
	}
	defer func() { _ = tx.Rollback(ctx) }() // no-op after a successful Commit
	var claimLockHeld bool
	if lockErr := tx.QueryRow(ctx, "SELECT pg_try_advisory_xact_lock(hashtext('upgrade_daemon'))").Scan(&claimLockHeld); lockErr != nil {
		return scheduledUpgradeClaim{}, fmt.Errorf("claim id=%d: acquire upgrade transaction lock: %w", id, lockErr)
	}
	if !claimLockHeld {
		return scheduledUpgradeClaim{}, fmt.Errorf("refusing to claim upgrade id=%d: a running upgrade service owns the upgrade lock and claims scheduled rows itself (within its 30s heartbeat); wait for it, or stop the service before dispatching inline with ./sb install", id)
	}

	// A ROLLBACK_FINISH_PENDING row means the previous version is already
	// restored, but its marker and final rolled_back transition are not yet clean.
	// Check under the same transaction lock used by finalization, so no cleanup can
	// commit between this decision and the claim below.
	var rollbackFinishingID int
	rollbackFinishingErr := tx.QueryRow(ctx,
		`SELECT id FROM public.upgrade WHERE `+rollbackFinishPendingSQL+` ORDER BY id LIMIT 1`).Scan(&rollbackFinishingID)
	if rollbackFinishingErr == nil {
		return scheduledUpgradeClaim{}, fmt.Errorf("refusing to claim upgrade id=%d: rollback finishing cleanup for upgrade id=%d is still pending; wait for the daemon to remove its stale marker and finalize the row", id, rollbackFinishingID)
	}
	if !errors.Is(rollbackFinishingErr, pgx.ErrNoRows) {
		return scheduledUpgradeClaim{}, fmt.Errorf("refusing to claim upgrade id=%d: could not verify rollback finishing state: %w", id, rollbackFinishingErr)
	}

	// Read the standing park once (if any): its id feeds step A's flag match and
	// its reason names the displacement in the loud line after commit.
	var parkedID int
	var parkedReason string
	hasPark := tx.QueryRow(ctx,
		"SELECT id, COALESCE(recovery_parked_reason, '') FROM public.upgrade WHERE state = 'in_progress' AND recovery_parked_at IS NOT NULL").
		Scan(&parkedID, &parkedReason) == nil

	// step A: a service-held flag pointing at the parked row is dead weight once we
	// displace it — remove it FIRST (crash-after-A is a safe, resumable state).
	if hasPark {
		if flag, ferr := ReadFlagFile(d.projDir); ferr == nil && flag != nil &&
			flag.Holder == HolderService && flag.ID == parkedID {
			if removeErr := d.removeUpgradeFlag(); removeErr != nil {
				return scheduledUpgradeClaim{}, fmt.Errorf("refusing to claim upgrade id=%d: could not remove parked upgrade id=%d's stale flag: %w", id, parkedID, removeErr)
			}
			fmt.Printf("STATBUS-159: removed the parked row's stale service-held flag (id=%d) before displacing it for the id=%d claim\n", parkedID, id)
		}
	}

	// step B: in the same transaction — displace the standing park, then claim.
	displaced := false
	if hasPark {
		ct, dispErr := tx.Exec(ctx,
			`UPDATE public.upgrade
			    SET state = 'superseded',
			        superseded_at = now(),
			        error = COALESCE(error, '') || $1,
			        recovery_parked_at = NULL,
			        recovery_parked_reason = NULL
			  WHERE state = 'in_progress' AND recovery_parked_at IS NOT NULL`,
			// STATBUS-159 FIX: name the CLAIMANT (the row taking over), not d.version —
			// d.version is the running binary, which post-swap is the displaced row
			// itself (the FROM side in every topology), so it would name itself.
			fmt.Sprintf(" — displaced by the claim of upgrade id=%d", id))
		if dispErr != nil {
			return scheduledUpgradeClaim{}, fmt.Errorf("claim id=%d: displace standing park: %w", id, dispErr)
		}
		displaced = ct.RowsAffected() > 0
	}

	// The claim itself: mutating SET + WHERE identical to the two former sites;
	// RETURNING the superset so both callers are served by one helper.
	claimErr := tx.QueryRow(ctx,
		`WITH claimed AS (
			UPDATE public.upgrade
			   SET state = 'in_progress', started_at = now(), from_commit_version = $1
			 WHERE id = $2 AND state = 'scheduled' AND started_at IS NULL
			 RETURNING commit_tags, recreate, id, commit_version, commit_sha, from_commit_version, started_at
		),
		labelled AS (
			-- commit_version is NULLABLE (an untagged commit registered by SHA
			-- carries none; dev holds 8 such rows, Norway 1). Scanning NULL into
			-- the snapshot's string failed the claim outright (found by the live
			-- twin TestLiveRollbackFinishing). The display fallback is the same
			-- one every other reader uses: the 8-char commit short.
			SELECT c.commit_tags,
			       c.recreate,
			       c.id,
			       COALESCE(c.commit_version, left(c.commit_sha, 8)) AS commit_version,
			       c.commit_sha,
			       COALESCE(c.from_commit_version, '') AS from_commit_version,
			       c.started_at
			  FROM claimed AS c
		)
		SELECT l.commit_tags,
		       l.recreate,
		       l.id,
		       l.commit_version,
		       l.commit_sha,
		       l.from_commit_version,
		       l.started_at,
		       (SELECT to_json(t)::text
		          FROM (SELECT l.id AS id,
		                       l.commit_version AS commit_version,
		                       l.commit_sha AS commit_sha,
		                       l.from_commit_version AS from_commit_version,
		                       l.started_at AS started_at) AS t)
		  FROM labelled AS l`,
		d.version, id).Scan(
		&claim.CommitTags,
		&claim.Recreate,
		&claim.Snapshot.ID,
		&claim.Snapshot.CommitVersion,
		&claim.Snapshot.CommitSHA,
		&claim.Snapshot.FromCommitVersion,
		&claim.Snapshot.StartedAt,
		&claim.Snapshot.ImmutableJSON,
	)
	if claimErr != nil {
		return scheduledUpgradeClaim{}, claimErr // includes pgx.ErrNoRows — callers map it to their own message
	}

	if commitErr := tx.Commit(ctx); commitErr != nil {
		return scheduledUpgradeClaim{}, fmt.Errorf("claim id=%d: commit displace+claim: %w", id, commitErr)
	}

	// Loud line only after the displacement actually committed (never before —
	// a rolled-back claim must not leave a false "displaced" line in the journal).
	if displaced {
		fmt.Printf("STATBUS-159: displaced parked upgrade id=%d (park reason: %q) → superseded; claimed upgrade id=%d\n",
			parkedID, parkedReason, id)
	}
	return claim, nil
}

func (d *Service) executeScheduled(ctx context.Context) {
	if err := d.ensureConnected(ctx); err != nil {
		return
	}
	var id int
	var commitSHA string
	var commitTags []string
	var scheduledAt time.Time
	var dockerImagesStatus string
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, commit_sha, commit_tags, scheduled_at, docker_images_status::text
		 FROM public.upgrade
		 WHERE state = 'scheduled'
		   AND scheduled_at <= now()
		 ORDER BY scheduled_at LIMIT 1`).Scan(&id, &commitSHA, &commitTags, &scheduledAt, &dockerImagesStatus)
	if err != nil {
		return // no pending upgrades
	}
	fmt.Printf("Claiming id=%d, lag=%s\n", id, time.Since(scheduledAt).Truncate(time.Second))

	// STATBUS-046 slice 3c — images-ready CLAIM GATE (evaluateImageClaimGate,
	// image_claim_gate.go). Don't claim a scheduled row whose images aren't
	// verified ready — a mid-publication image-404 would otherwise reach the
	// warm-up pull. Fail-open-loud past the shared manifestTimeout grace
	// (never wedge), same posture as the parked-check + statfs rulings.
	switch evaluateImageClaimGate(dockerImagesStatus, scheduledAt, time.Now(), manifestTimeout) {
	case imageClaimFailed:
		fmt.Printf("Scheduled upgrade id=%d: images failed to publish (CI failed) — re-push or ./sb upgrade register again.\n", id)
		return
	case imageClaimWait:
		fmt.Printf("Scheduled upgrade id=%d: scheduled, images still building — waiting for publication.\n", id)
		// Re-probe now rather than waiting for the next 6h/NOTIFY discovery
		// cycle: executeScheduled runs every 30s off the daemon's
		// heartbeatTicker, but verifyArtifacts only runs from discover()
		// (6h ticker or a NOTIFY), so without this explicit call a
		// 'building' row could sit unclaimed for up to 6h even after CI
		// actually finishes. verifyArtifacts is cheap/idempotent by design
		// ("Runs on every discovery cycle") — safe to call an extra time here.
		d.verifyArtifacts(ctx)
		return
	case imageClaimPastGrace:
		fmt.Printf("Scheduled upgrade id=%d: images unverified past %s — proceeding; the warm-up pull will fail actionably if truly absent.\n", id, manifestTimeout)
	case imageClaimReady:
		// Claim as today — no gate interference on the common path.
	}

	// Claim immediately: mark started_at + state='in_progress' so the UI
	// shows "In Progress" and the user can no longer unschedule.
	// State guard makes the claim safe against a racing inline install
	// (./sb install dispatching StateScheduledUpgrade): whichever UPDATE
	// commits first wins, the other gets 0 rows affected and bails.
	//
	// STATBUS-077: claim records only the display version (from_commit_version).
	// The recovery restore target is the pinned `pre-upgrade` branch (single source);
	// the from_commit_sha column was removed.
	// STATBUS-092: read the durable recreate intent atomically WITH the claim
	// (RETURNING) so it can never be lost to NOTIFY timing. ErrNoRows = the state
	// guard matched 0 rows (another actor claimed first) — a benign skip.
	// STATBUS-159: claimScheduledUpgrade is the shared claim path — it displaces
	// any standing park before claiming. Take commit_tags from the helper's claim
	// RETURNING, not the pending-row SELECT above: the value comes atomically from
	// the claim UPDATE, so a write landing between that SELECT and the claim can't
	// hand a stale commit_tags to executeUpgrade (architect-confirmed — strictly
	// better than the old shape). The SELECT's commit_tags stays for displayName +
	// the image gate, both computed before the claim.
	claim, claimErr := d.claimScheduledUpgrade(ctx, id)
	if errors.Is(claimErr, pgx.ErrNoRows) {
		fmt.Printf("Scheduled upgrade id=%d already claimed by another actor; skipping.\n", id)
		return
	}
	if claimErr != nil {
		d.markPgInvariantTerminal(claimErr, "service.go:executeScheduled:claim")
		fmt.Printf("UPGRADE_CLAIM_FAILED: could not claim scheduled upgrade id=%d: %v\n", id, claimErr)
		return
	}

	// STATBUS-159 (take-from-helper residue): render displayName from the
	// claim's atomic commit_tags so the post-claim messages + executeUpgrade
	// can't carry a stale-tag rendering. STATBUS-176 lint burn-down: this
	// used to be a RE-render (ineffassign flagged the pre-claim first render
	// as dead — the pre-claim gate log lines below use `id`, not
	// displayName, so the earlier SELECT-based render was never read); the
	// stale comment claiming otherwise is gone too.
	displayName := renderDisplayName(CommitSHA(claim.Snapshot.CommitSHA), claim.CommitTags)

	fmt.Printf("Executing upgrade to %s...\n", displayName)
	// Invoker context for the flag file: the row was picked up from the scheduled queue.
	// This covers admin-UI "Apply now", NOTIFY upgrade_apply from ./sb upgrade apply-latest,
	// and the discovery loop's auto-schedule — we don't currently distinguish among them
	// at this layer. Later improvement: record originator in public.upgrade when scheduling.
	if err := d.executeUpgrade(ctx, claim.Snapshot, displayName, claim.CommitTags, "scheduled", "scheduled", claim.Recreate); err != nil {
		fmt.Printf("Upgrade to %s failed: %v\n", displayName, err)
	}
}

// executeUpgrade runs the end-to-end upgrade pipeline: pre-flight, flag-file
// write, maintenance mode, backup, git checkout, migrations, service restart,
// health check, completion (or rollback on failure).
//
// Concurrency safety: the advisory DB lock at Run() prevents a second upgrade
// service instance from running. The flag file written at writeUpgradeFlag
// prevents `./sb install` (and `./cloud.sh install` → install.sh → ./sb install)
// from racing this function — those callers read the flag, check the PID is
// alive, and abort. The only install invocation allowed through during this
// function is the post-upgrade fixup at runInstallFixup, which sets the
// --post-upgrade-fixup flag and STATBUS_POST_UPGRADE_FIXUP=1 env var.
func (d *Service) executeUpgrade(ctx context.Context, claim upgradeClaimSnapshot, displayName string, commitTags []string, invokedBy, trigger string, recreate bool) error {
	id := claim.ID
	commitSHA := claim.CommitSHA
	d.upgrading = true
	defer func() { d.upgrading = false }()

	// Reset the unit's restart counter at dispatch (STATBUS-039 review
	// finding 2): a legitimate upgrade is starting, so NRestarts must count
	// ONLY this upgrade's restarts from here. The planned exit-42 handoff
	// bumps it to 1; only a genuine crash loop reaches the install
	// takeover's gate (>= 3). Without this, the counter accumulates one per
	// healthy upgrade since the last manual unit start, and a concurrent
	// ./sb install could SIGKILL-take-over a progressing upgrade. Best
	// effort: reset-failed also resets the restart counter (systemd >= 244);
	// where it doesn't apply (older systemd, non-linux, unknown unit) the
	// gate is merely as conservative as before — logged, never fatal.
	if runtime.GOOS == "linux" && d.unitInstance != "" {
		if err := exec.Command("systemctl", "--user", "reset-failed", d.unitInstance).Run(); err != nil {
			log.Printf("systemctl --user reset-failed %s at upgrade dispatch: %v (NRestarts takeover gate stays conservative)", d.unitInstance, err)
		}
	}

	projDir := d.projDir
	progress := NewUpgradeLog(projDir, int64(id), displayName, time.Now().UTC())
	defer progress.Close()

	// Stamp log_relative_file_path on the row as early as possible so crash
	// recovery, the admin UI, and the support-bundle collector can all find
	// the on-disk log. If the pointer is lost, later crash-recovery cannot
	// find the log file — so a persistent failure is fail-fast + bundle.
	logPathSQL := "UPDATE public.upgrade SET log_relative_file_path = $1 WHERE id = $2"
	insertCompletedAt := time.Now()
	var stampErr error
	for attempt := 0; attempt < 4; attempt++ {
		_, stampErr = d.queryConn.Exec(ctx, logPathSQL, progress.RelPath(), id)
		if stampErr == nil {
			break
		}
		if attempt < 3 && isConnError(stampErr) {
			time.Sleep(retryBackoff(attempt + 1))
			continue
		}
		// C5: LOG_POINTER_STAMPED — bounded retry exhausted. INSERT just
		// succeeded ms ago on the same connection; no state change. A
		// persistent failure is a real DB issue, and the crash-recovery
		// + admin UI + bundle collector all depend on this pointer.
		elapsedMs := time.Since(insertCompletedAt).Milliseconds()
		fmt.Fprintf(os.Stderr,
			"INVARIANT LOG_POINTER_STAMPED violated: could not set log_relative_file_path for upgrade %d after %d attempts: %v; elapsedMs=%d (service.go:%d, pid=%d)\n",
			id, attempt+1, stampErr, elapsedMs, thisLine(), os.Getpid())
		d.markTerminal("LOG_POINTER_STAMPED",
			fmt.Sprintf("id=%d; final Exec err=%v; elapsedMs=%d", id, stampErr, elapsedMs))
		d.writeDiagnosticBundle(ctx, int(id), progress)
		return fmt.Errorf("LOG_POINTER_STAMPED: %w", stampErr)
	}

	progress.Write("Upgrading to %s (from %s)", displayName, claim.FromCommitVersion)
	// For untagged-commit targets (edge channel), displayName is the
	// 8-char commit_short — it identifies the commit but says nothing
	// about how far it is from the nearest tag. `git describe` fills
	// that gap ("v2026.03.1-9-gea46d58" → nearest tag + N commits
	// ahead + shortened SHA). Also emit the commit subject so an
	// operator watching the maintenance page sees what the upgrade
	// actually brings without tailing git log. Suppress describe when
	// it equals displayName (tagged-channel case) to avoid redundancy.
	if out, err := runCommandOutput(projDir, "git", "describe", "--tags", "--always", commitSHA); err == nil {
		if desc := strings.TrimSpace(out); desc != "" && desc != displayName {
			progress.Write("  Target version: %s", desc)
		}
	}
	// Show only the durable short SHA. Commit subjects are implementation detail
	// and proved actively misleading in the operator progress narrative.
	if out, err := runCommandOutput(projDir, "git", "log", "-1", "--pretty=%h", commitSHA); err == nil {
		if line := strings.TrimSpace(out); line != "" {
			progress.Write("  Target commit: %s", line)
		}
	}

	// === Pre-flight checks (BEFORE marking started_at) ===
	// These checks reject the upgrade without setting started_at, so the
	// maintenance guard never activates and the upgrade page stays clean.

	// Downgrade protection: refuse to apply an older version than currently running.
	// Downgrades require restoring from backup instead.
	//
	// Applies only when BOTH sides are valid CalVer release tags — the
	// only case where CompareVersions returns a meaningful ordering.
	// Untagged commits (commit_short, describe-off-tag) and the "dev"
	// placeholder are not release-ordered, so ValidateVersion() rejects
	// them and the guard short-circuits. No shape detection needed.
	if ValidateVersion(displayName) && ValidateVersion(d.version) {
		if ord, ordered := CompareVersions(displayName, d.version); ordered && ord < 0 {
			// TODO: pick code — downgrade precondition; consider adding ErrInstallPreconditionFailed
			msg := fmt.Sprintf("Version %s is older than current version %s. Downgrades are not supported. To restore a previous state, use: ./sb db backup restore <name>", displayName, d.version)
			d.failUpgrade(ctx, id, msg, progress)
			return fmt.Errorf("%s", msg)
		}
	}

	// Verify release manifest and binary exist before starting.
	// If CI hasn't finished building, return the claim to 'scheduled' and keep
	// the original scheduled_at — operator intent does not expire because
	// publication is still in progress. executeScheduled re-picks the row on its
	// next tick and proceeds once the artifacts are ready (STATBUS-336).
	// Only tagged releases have a manifest; untagged commits skip this check.
	if ValidateVersion(displayName) {
		manifest, err := FetchManifest(displayName)
		if err != nil {
			// Clear only claim-owned fields. scheduled_at is deliberately retained:
			// it is both the durable record of the operator's decision and the clock
			// used by the CLI/UI to make a long publication wait visible.
			//
			// STATBUS-187 fix unit #3 (architect-ruled, ticket comment #4):
			// HARD-FAIL if this step-back doesn't land — check both the Exec
			// error and RowsAffected==0 (an id-scoped UPDATE affecting 0
			// rows means the step-back never happened even though Exec itself
			// returned no error). Return the error, never nil, so an in_progress
			// row cannot silently wedge outside the scheduled retry loop.
			result, resetErr := d.queryConn.Exec(ctx,
				"UPDATE public.upgrade SET state = 'scheduled', started_at = NULL, from_commit_version = NULL WHERE id = $1 AND state = 'in_progress'", id)
			if resetErr != nil {
				// A second explicit schedule can land while this row is briefly
				// claimed. The single-scheduled index then correctly refuses to
				// put both rows in the slot. The later operator decision wins: make
				// this claimed row visibly superseded instead of reverting it to the
				// sweepable 'available' state or wedging it in_progress.
				var pgErr *pgconn.PgError
				if errors.As(resetErr, &pgErr) && pgErr.ConstraintName == "upgrade_single_scheduled" {
					supersedeResult, supersedeErr := d.queryConn.Exec(ctx,
						"UPDATE public.upgrade SET state = 'superseded', superseded_at = now(), started_at = NULL, from_commit_version = NULL WHERE id = $1 AND state = 'in_progress'", id)
					if supersedeErr != nil {
						d.markPgInvariantTerminal(supersedeErr, "service.go:executeUpgrade:ci-not-ready-supersede")
						return fmt.Errorf("CI not ready for %s, another row now owns the scheduled slot, and superseding this claim failed: %w", displayName, supersedeErr)
					}
					if supersedeResult.RowsAffected() == 0 {
						noRowsErr := fmt.Errorf("CI-not-ready supersede UPDATE affected 0 rows for upgrade id %d", id)
						d.markPgInvariantTerminal(noRowsErr, "service.go:executeUpgrade:ci-not-ready-supersede")
						return noRowsErr
					}
					progress.Write("Verifying release assets ... not ready; a newer scheduled upgrade superseded %s.", displayName)
					return nil
				}
				d.markPgInvariantTerminal(resetErr, "service.go:executeUpgrade:ci-not-ready-reschedule")
				return fmt.Errorf("CI not ready for %s, and returning the claim to scheduled also failed: %w", displayName, resetErr)
			}
			if result.RowsAffected() == 0 {
				noRowsErr := fmt.Errorf("CI-not-ready reschedule UPDATE affected 0 rows for upgrade id %d — claim not returned to 'scheduled'", id)
				d.markPgInvariantTerminal(noRowsErr, "service.go:executeUpgrade:ci-not-ready-reschedule")
				return noRowsErr
			}
			progress.Write("Verifying release assets ... not ready; keeping %s scheduled for an automatic retry.", displayName)
			return nil
		}
		platform := selfupdate.Platform()
		if _, ok := manifest.Binaries[platform]; !ok {
			msg := fmt.Sprintf("release %s has no binary for platform %s — upgrade cannot proceed without a matching binary", displayName, platform)
			d.failUpgrade(ctx, id, msg, progress)
			return fmt.Errorf("%s", msg)
		}
		progress.Write("Verifying release assets ... ok")
	}

	// Check disk space. Need room for backup (~= DB size) + new images (~2GB).
	// Refuse to start if less than 5GB free to avoid mid-upgrade disk-full failures.
	var (
		freeGB         uint64
		diskSpaceKnown bool
	)
	if freeBytes, err := DiskFree(d.projDir); err == nil {
		freeGB = freeBytes / (1024 * 1024 * 1024)
		diskSpaceKnown = true
		if freeGB < 5 {
			// TODO: pick code — disk-space preflight; consider ErrRollbackGitDiskFull or a new ErrInstallPreconditionFailed
			msg := fmt.Sprintf("Insufficient disk space: %d GB free (need at least 5 GB for backup + images)", freeGB)
			d.failUpgrade(ctx, id, msg, progress)
			return fmt.Errorf("%s", msg)
		}
	}

	// Re-verify commit signature before proceeding.
	// This defends against DB tampering between discovery and execution.
	if err := d.verifyCommitSignature(commitSHA); err != nil {
		// TODO: pick code — signature verification; consider adding ErrInstallPreconditionFailed
		msg := fmt.Sprintf("Commit %s signature verification failed: %v", ShortForDisplay(commitSHA), err)
		d.failUpgrade(ctx, id, msg, progress)
		return fmt.Errorf("%s", msg)
	}
	progress.Write("Verifying commit signature ... ok")
	if diskSpaceKnown {
		progress.Write("Disk space: %d GB free — enough for the upgrade", freeGB)
	}

	// === All pre-flight checks passed — mark the upgrade as started ===
	// Acquire a kernel-exclusive flock on the flag file BEFORE any
	// destructive steps. The flock (held on d.flagLock for the duration
	// of executeUpgrade) blocks racing `./sb install` or another service
	// instance. If the service crashes after this point, the kernel
	// auto-releases the flock via fd teardown; the JSON metadata on disk
	// survives and recoverFromFlag at the next service startup reconciles
	// it (it's on the filesystem, not in the DB volume which gets rolled
	// back).
	if err := d.writeUpgradeFlag(id, commitSHA, commitTags, invokedBy, trigger, recreate); err != nil {
		// TODO: pick code — mutex flag acquisition failure; consider adding ErrInstallPreconditionFailed
		msg := fmt.Sprintf("Could not acquire upgrade-mutex flag file: %v", err)
		d.failUpgrade(ctx, id, msg, progress)
		return fmt.Errorf("%s", msg)
	}
	progress.Write("Writing lock file for exclusive upgrade (%s) ... ok", homeRelativePath(d.flagPath()))

	// started_at and from_version were already set by executeScheduled() when
	// it claimed this task. From this point on, the maintenance guard will activate.

	// Step 1: Prepare images
	// Fine-grained progress lines bracket each state transition here so that
	// if the service hangs (as seen on statbus_dev Apr 23 2026 — task #37),
	// the LAST journalctl line identifies the exact step that failed to
	// return. Zero behaviour change; pure observability.
	pullStart := time.Now()

	// pullImagesForCommitShort is the one step in executeUpgrade that can
	// legitimately exceed the 120s watchdog window (large registry pulls over
	// slow links). Emit a periodic "still pulling" progress line so each tick
	// fires emitHeartbeat and systemd sees liveness. 30s cadence matches
	// the main-loop heartbeatTicker's; net effect is at most ~30s of
	// silence between watchdog pings regardless of where the main
	// goroutine is executing.
	//
	// Known blind spot: this ticker fires from a background goroutine.
	// If the pull hangs and the main goroutine is stuck inside
	// cmd.Run, the ticker keeps pinging and systemd doesn't restart.
	// Bounded by pullImagesForCommitShort's own 10-minute ctx timeout (see
	// exec.go) — cmd.Run returns at the 10-min mark even on subprocess hang, so
	// the main goroutine resumes within that budget.
	pullDone := make(chan struct{})
	pullTicker := time.NewTicker(30 * time.Second)
	go func() {
		defer pullTicker.Stop()
		for {
			select {
			case <-pullDone:
				return
			case <-pullTicker.C:
				progress.Write("Still downloading images (%s elapsed) ...",
					time.Since(pullStart).Truncate(time.Second))
			}
		}
	}()
	// Pre-stage the TARGET's images (by its COMMIT_SHORT = ShortForDisplay of the
	// target commit), not whatever COMMIT_SHORT is currently in .env. This is a
	// genuine warm-up: the same images applyNewSbUpgrading Step 8 needs post-swap are
	// fetched now, before the swap, and a missing-image failure surfaces here —
	// before any destructive step — rather than after. (The old form passed the
	// display name to a VERSION-only override, which fetched current images.)
	pullErr := d.pullImagesForCommitShort(ShortForDisplay(commitSHA))
	close(pullDone)
	if pullErr != nil {
		d.failUpgrade(ctx, id, fmt.Sprintf("%s: Failed to pull images for %s: %v", ErrDockerUpFailed, displayName, pullErr), progress)
		return pullErr
	}
	progress.Write("Downloading images ... ok (%s)", formatProgressDuration(time.Since(pullStart), false))

	// Step 1b: ensure the target commit object is local before the service crosses
	// the read-only/maintenance boundary. Discovery already fetched and signature-
	// verified this object, so the normal path is one local `git cat-file` and zero
	// network calls. Norway rc.02 repeated `git fetch origin <sha>` only after
	// maintenance mode and the DB stop; a brief GitHub failure therefore bought an
	// outage and entered rollback even though the required object was already here.
	//
	// This position is safe: git objects are read-only local state, and nothing
	// before the binary swap depends on the target object's absence. The upgrade
	// flag is already stamped, while the read-only window, service stops, branch
	// pin, and backup retain their existing relative order below. A real miss gets
	// bounded stall-detected retries here, while the old version keeps serving.
	if err := d.ensureUpgradeCommitObjects(ctx, progress.File(), commitSHA); err != nil {
		errMsg := fmt.Sprintf("%s: %v", ErrGitFetchRetryable, err)
		d.failUpgrade(ctx, id, errMsg, progress)
		return fmt.Errorf("%s", errMsg)
	}

	// CHANGE 2 (task #12): the rsync snapshot is a single persistent dir
	// committed by atomic rename to pre-upgrade-active. Record THAT path as
	// backup_path before the DB connection is closed — it is deterministic (no
	// stamp), and it is the identity the restore consumes (restoreDatabase is
	// identity-keyed, STATBUS-039/-031: it restores ONLY a recorded path,
	// never a recency scan). This is a MUTABLE pointer (the same dir is reused
	// across upgrades); H2 — safe only because the upgrade-mutex serializes:
	// the persistent flag file (written at writeUpgradeFlag above, before this
	// point) forces any competing actor through RecoverFromFlag, which RESUMES
	// rather than starting a fresh backup, so no overlapping upgrade
	// overwrites active before recovery consumes it.
	// backupStamp is retained ONLY for the per-upgrade archive tar +
	// upgrade-logs-<stamp> correlation (still per-upgrade); it no longer names
	// the rsync dir.
	backupStamp := time.Now().UTC().Format("20060102T150405Z")

	// L2 — stale-connection detection before the first DB write after the
	// multi-second pullImagesForCommitShort step. The pull leaves queryConn idle for the
	// duration of the docker pull; in networking environments that absorb
	// TCP keepalive probes (Docker userland-proxy is a documented example —
	// see tmp/engineer-dev-hang-meticulous.md §3), an otherwise-dead socket
	// still appears ESTABLISHED to the kernel and L1's keepalive doesn't
	// fire. The explicit Ping forces actual bidirectional traffic and
	// detects staleness in ~5s regardless of kernel keepalive state. On
	// detected staleness we reconnect via the existing d.reconnect(ctx)
	// and proceed to the Exec, which then acts as the single retry.
	pingCtx, pingCancel := context.WithTimeout(ctx, 5*time.Second)
	pingErr := d.queryConn.Ping(pingCtx)
	pingCancel()
	if pingErr != nil {
		progress.Write("Reconnecting to the database before blocking SQL writes ...")
		if reErr := d.reconnect(ctx); reErr != nil {
			progress.Write("Reconnecting to the database before blocking SQL writes ... failed (continuing): %v", reErr)
		} else {
			progress.Write("Reconnecting to the database before blocking SQL writes ... ok")
		}
	}

	// STATBUS-197 C1: backup_path is NO LONGER recorded here as early intent. Recording it
	// BEFORE the snapshot commits violated the identity contract — a flag-lost heal in the
	// [record → snapshot] span would restore the PREVIOUS attempt's snapshot (weeks-of-data
	// regression). "backup_path == '' ⇔ nothing moved" is the invariant the rollback
	// no-touch guard (C2) keys on. reconcileBackupDir keeps its on-disk-stamp fallback.
	//
	// STATBUS-228: the two carriers become honest at DIFFERENT MOMENTS, BY DESIGN — this
	// is not a weaker version of the C1 contract, it is the only implementable one.
	//   - THE FLAG is stamped at the SWAP (updateFlagNewSbSwapped, below). That is the
	//     point of no return: before it the database volume is untouched, so an EMPTY
	//     BackupPath is not a gap — it is the CORRECT value, and it is what makes the
	//     PreSwap recovery branch's no-touch guarantee true (:1315-1318, :1348-1349).
	//   - THE ROW is recorded at the first RECONNECT after the backup (applyNewSbUpgrading,
	//     the write right after "Database reconnected."). It cannot be recorded any
	//     earlier: Step 4 STOPS the postgres SERVER for the consistent backup, and no
	//     write of any kind can land while it is down. 197 recorded it here anyway and
	//     the UPDATE failed on every upgrade — silently on successful ones, which the
	//     later reconnect write repaired, and permanently on crashed ones, which are the
	//     population that needs it (STATBUS-228).
	// Across the DB-down gap the FLAG is the authoritative carrier. That is not a
	// degradation: the flag is the only carrier that CAN be written with the server
	// stopped, which is exactly why recovery has always been flag-driven.

	// STATBUS-110: engage the read-only upgrade window NOW — before we tear down
	// connections and stop the DB — while queryConn is still live. The ALTER
	// persists in the catalog, so it survives the stop and every phase-3
	// reconnecting session inherits read-only (crash-freeze if we die mid-window).
	// Set BEFORE the stop (not at the phase-3 restart) to close the race where a
	// session reconnects before the ALTER lands and gets read-write (F3). The
	// upgrade's own writers stay read-write via the connect() + migrate.psqlEnv
	// exemptions. Best-effort accident-guard: log, do not abort the upgrade.
	// THE RULE FOR EVERY LINE BELOW (STATBUS-318, the King's principle): this
	// progress log IS the product for the person watching an upgrade. High level
	// first, clearly — what is happening, in the words an operator thinks in —
	// then the exact detail for precision. Never only one of the two. A line
	// that gives only the detail (goroutines, contexts, connection objects)
	// tells the reader what the author was doing, not what the system is doing.
	readOnlyStatement, readOnlyErr := d.setDatabaseReadOnly(ctx, true)
	if readOnlyErr != nil {
		progress.Write("Blocking SQL writes while upgrading ... failed (continuing; guard is best-effort): %v", readOnlyErr)
	} else if readOnlyStatement != "" {
		progress.Write("Blocking SQL writes while upgrading ... ok")
		progress.Write("  ran: %s", readOnlyStatement)
	}

	// Step 2: Enter maintenance mode and restart proxy first
	// Guards let one-shot callers (./sb install inline upgrade) reach
	// executeUpgrade without a listenConn.
	//
	// ONE HEADLINE, THEN ITS DETAILS. The old sequence emitted "Listen-loop
	// goroutine stopped." immediately followed by "Closing listen connection to
	// the database..." — two adjacent lines an operator cannot tell apart, where
	// neither is the plain statement and neither earns its precision. What is
	// actually happening is one thing: the service is letting go of the database
	// so the database can be stopped. That is the headline; the individual
	// connections are the detail underneath it.
	maintenanceContent, contentErr := maintenanceFlagContent(claim)
	maintenanceErr := contentErr
	if maintenanceErr == nil {
		maintenanceErr = d.setMaintenance(true, maintenanceContent)
	}
	if maintenanceErr != nil {
		progress.Write("Entering maintenance mode (browsers redirect to the progress page, APIs get HTTP 503 Service Unavailable) ... failed: %v", maintenanceErr)
		errMsg := fmt.Sprintf("could not enter maintenance mode before stopping services: %v", maintenanceErr)
		needsRecovery := false
		// os.WriteFile can truncate or partially create the active marker before
		// returning an error. Always remove it so Caddy cannot keep serving HTTP 503
		// after this attempt aborts. A failed cleanup is itself recovery-worthy.
		if cleanupErr := d.setMaintenance(false, ""); cleanupErr != nil {
			needsRecovery = true
			progress.Write("Cleaning up the incomplete maintenance marker ... failed: %v", cleanupErr)
			errMsg += fmt.Sprintf("; incomplete maintenance marker may remain: %v", cleanupErr)
		} else {
			progress.Write("Cleaning up the incomplete maintenance marker ... ok")
		}
		// The ON attempt above can fail after PostgreSQL committed it but before the
		// client observed success. Always issue the idempotent OFF flip. If OFF also
		// fails, keep the recovery flag so ./sb install has the durable breadcrumb
		// needed to reconcile a database that may still reject fresh writes.
		offStatement, liftErr := d.liftReadOnlyWindow("maintenance activation failure")
		if liftErr != nil {
			needsRecovery = true
			progress.Write("Unblocking SQL writes after the maintenance-mode failure ... failed: %v", liftErr)
			errMsg += fmt.Sprintf("; SQL writes may remain blocked: %v", liftErr)
		} else {
			progress.Write("Unblocking SQL writes after the maintenance-mode failure ... ok")
			progress.Write("  ran: %s", offStatement)
		}
		if needsRecovery {
			d.failUpgradeKeepingFlag(ctx, id, errMsg, progress)
		} else {
			d.failUpgrade(ctx, id, errMsg, progress)
		}
		return fmt.Errorf("%s", errMsg)
	} else {
		progress.Write("Entering maintenance mode (browsers redirect to the progress page, APIs get HTTP 503 Service Unavailable) ... ok")
		progress.Write("  wrote: %s (%q; file contains the psql command for the live row)",
			homeRelativePath(maintenanceFlagHostPath()), maintenanceFlagHeadline(claim))
	}
	progress.Write("Stopping services:")
	d.stopListenLoop()
	var disconnectErr error
	if d.listenConn != nil {
		disconnectErr = errors.Join(disconnectErr, d.listenConn.Close(context.Background()))
		d.listenConn = nil
	}
	if d.queryConn != nil {
		disconnectErr = errors.Join(disconnectErr, d.queryConn.Close(context.Background()))
		d.queryConn = nil
	}
	if disconnectErr != nil {
		progress.Write("  Disconnecting upgrade service from the database ... failed (continuing): %v", disconnectErr)
	} else {
		progress.Write("  Disconnecting upgrade service from the database ... ok")
	}

	// Step 3: Stop application services (proxy stays running for maintenance page).
	// Hard error: running services during backup risk inconsistent state.
	if err := runCommand(projDir, "docker", "compose", "stop", "app", "worker", "rest"); err != nil {
		errMsg := fmt.Sprintf("could not stop application services before backup: %v", err)
		progress.Write("  Stopping app, worker, rest ... failed: %s", errMsg)
		errMsg = d.abortFailedPreBackupStop(ctx, id, "application-stop", errMsg, []string{"app", "worker", "rest"}, progress)
		return fmt.Errorf("%s", errMsg)
	}
	progress.Write("  Stopping app, worker, rest ... ok")

	// Step 4: Stop database for consistent backup.
	// Hard error: rsync of a running Postgres data dir is NOT crash-consistent.
	if err := runCommand(projDir, "docker", "compose", "stop", "db"); err != nil {
		errMsg := fmt.Sprintf("could not stop database for consistent backup: %v", err)
		progress.Write("  Stopping database ... failed: %s", errMsg)
		errMsg = d.abortFailedPreBackupStop(ctx, id, "database-stop", errMsg, []string{"app", "worker", "rest", "db"}, progress)
		return fmt.Errorf("%s", errMsg)
	}
	progress.Write("  Stopping database ... ok")

	// Pin the pre-upgrade commit as a persistent branch BEFORE we touch
	// anything destructive. The branch survives process crashes and tag
	// pruning — restoreGitState falls back to it if `restoreTargetSHA`
	// (a tag or describe-string) won't resolve later. Best-effort: log
	// failure, don't abort the upgrade.
	if out, err := runCommandOutput(projDir, "git", "branch", "-f", "pre-upgrade", "HEAD"); err != nil {
		progress.Write("Pinning the pre-upgrade source revision ... failed (continuing): %v\n%s", err, out)
	}

	// Step 5: Backup database
	// STATBUS-077: single source = the `pre-upgrade` branch pinned just above.
	restoreTargetSHA := ""
	backup, err := d.backupDatabase(progress, backupStamp)
	if err != nil {
		progress.Write("Backing up database ... failed: %v", err)
		// No snapshot was finalised (the partial lives in the syncing dir,
		// never recorded) — pass "" so the identity-keyed restore refuses to
		// touch the volume; it was never mutated.
		d.rollback(ctx, id, displayName, restoreTargetSHA, fmt.Sprintf("%s: %v", ErrBackupFailed, err), "", progress)
		return err
	}
	backupPath := backup.Path
	progress.Write("Backing up database ... ok (%s in %s)", humanBytes(backup.Bytes), formatProgressDuration(backup.Elapsed, false))
	progress.Write("  at %s", homeRelativePath(backup.Path))

	// STATBUS-228: NOTHING RECORDS backup_path HERE. The postgres SERVER is stopped at
	// this point (Step 4, above) for the consistent backup, so no row write can land —
	// and the flag must NOT be stamped either, because the swap has not happened yet.
	//
	// 197 recorded on both carriers here, and both were wrong in different ways:
	//   - The row UPDATE rode terminalExec, justified as "teardown-immune". terminalExec
	//     survives OUR CONNECTION dying (STATBUS-154/163) — it opens a fresh one. It
	//     cannot reach a server that is not running. The write failed on EVERY upgrade;
	//     on crashed ones the column stayed NULL forever, killing STATBUS-111's
	//     human-gated replay AND failing the :3761 abort-hold guard OPEN.
	//   - The flag stamp gave a PreSwap flag a BackupPath, which silently falsified the
	//     PreSwap recovery branch's stated premise ("empty by construction at PreSwap",
	//     :1348-1349). restoreDatabase then stopped refusing, and a database no-op became
	//     a full volume rewind — which also reverted recovery_attempts to the snapshot's
	//     value, the hazard writeRollbackTerminal documents at its own contract.
	//
	// The identity is recorded where each carrier can hold it truthfully: the FLAG at the
	// swap (updateFlagNewSbSwapped, below), the ROW at the first reconnect after it.

	// Step 6: Install from the target's already-local git objects, but do NOT check
	// out the working tree here (STATBUS-060). A pre-swap checkout materializes the target's
	// compose template while the OLD binary + key-deficient .env are still in
	// control; a crash there restarts the OLD binary, whose every `docker
	// compose` call dies on the target's new mandatory var (window 3). The
	// checkout is deferred to the NEW binary's recovery boot (Service.Run /
	// runCrashRecovery, before boot-migrate-up). Step 1b already proved the objects
	// local, before maintenance, with a bounded fetch fallback only on a real miss.
	// Full history lets git-describe find tags for config generate (VERSION).
	progress.Write("Installing %s:", displayName)

	// Harness-only kill site (C4): the OS / orchestrator kills the process here
	// — after the target's objects are fetched but BEFORE the binary swap.
	// STATBUS-060 NOTE: the pre-swap `git checkout` was removed, so the working
	// tree is STILL the SOURCE's here (not the target's) — the OLD binary never
	// sees target-compose, which is the whole point of the deferral. The kill
	// leaves: objects fetched, NO checkout, no binary swap (./sb still OLD),
	// flag PreSwap. Recovery via the next install's recoverFromFlag PreSwap
	// branch → restoreGitState reverts to restoreTargetSHA, discards the .tmp
	// backup, clears the flag; binary on disk was never touched. No-op in
	// production. The 2-preswap-checkout-kill scenario's RED assertion ("working
	// tree at target") is now stale — updated under STATBUS-026 (genuine-binary
	// variant).
	inject.KillHere("killed-by-system-during-preswap-checkout")

	// Verify the commit being installed matches the manifest (detect tag
	// spoofing). STATBUS-060: compares commitSHA (the upgrade target) directly
	// to the manifest's commit — NOT `git rev-parse HEAD`, because the working-
	// tree checkout is deferred to the recovery boot, so HEAD is still the
	// source's here. Same anti-tampering property: the commit handed off to the
	// new binary (and checked out by it) must be the one the manifest claims for
	// this version; the deferred `git checkout commitSHA` errors if that ref is
	// absent. Only tagged releases carry a manifest; untagged commits skip.
	if ValidateVersion(displayName) {
		if manifest, mErr := FetchManifest(displayName); mErr == nil && manifest.CommitSHA != "" {
			if !strings.HasPrefix(commitSHA, manifest.CommitSHA) && !strings.HasPrefix(manifest.CommitSHA, commitSHA) {
				// TODO: pick code — tag-tampering detection; consider adding ErrInstallPreconditionFailed
				errMsg := fmt.Sprintf("Version verification failed: target commit %s does not match manifest commit %s. Possible tag tampering.",
					ShortForDisplay(commitSHA), ShortForDisplay(manifest.CommitSHA))
				progress.Write("%s", errMsg)
				d.rollback(ctx, id, displayName, restoreTargetSHA, errMsg, backupPath, progress)
				return fmt.Errorf("%s", errMsg)
			}
		}
	}

	// Step 6b: Procure a fresh ./sb on disk, then ALWAYS hand off to a new
	// process so the remaining pipeline runs against the NEW compiled Go
	// code. Without this handoff, bugs fixed between releases (e.g.
	// rc.48→rc.51's healthURL) stay latent because the running daemon's
	// .text segment still holds the old binary image even though ./sb on
	// disk is the new version.
	//
	// Two procurement sources, one swap+handoff path:
	//   - tagged release: replaceBinaryOnDisk pulls the manifest artifact
	//   - edge commit:    buildBinaryOnDisk extracts ./sb from the commit-tagged
	//                     statbus-sb image (sbimage.ProcureShort) — no host
	//                     toolchain; falls back to an in-container build only
	//                     when the image is unpublished AND the tree is at target
	//
	// Both produce ./sb at the target commit and preserve ./sb.old for
	// rollback. Both upgrades go through the same swap+handoff plumbing,
	// so every upgrade exercises the path — no rarely-run "skip handoff"
	// branch can rot silently (the failure mode that bit edge in rc.70).
	// STATBUS-171 condition-vs-circumstance (STRUCTURAL, proven on dev evidence):
	// only the tagged branch runs a self-verify subprocess, so only it needed the
	// target-identity fix. replaceBinaryOnDisk → selfupdate.ReplaceBinaryOnDisk
	// EXECS `upgrade self-verify` (step 3b) — that is where the STATBUS-060
	// deferred-checkout worktree tripped the old stalenessGuard. buildBinaryOnDisk
	// → procureSbFromImage swaps ./sb via `docker create`+`docker cp`+chmod and
	// NEVER execs the new binary mid-swap, so it never invoked the guard: the
	// commit/edge path survived BY CONSTRUCTION, not by circumstance, and carries
	// no latent copy of the bug. (dev row 331014: tag rc.02 rolled back; the
	// same-night commit-identified deploys completed.)
	var (
		procureErr  error
		procureCode string
	)
	if ValidateVersion(displayName) {
		procureErr = d.replaceBinaryOnDisk(displayName, progress)
		procureCode = ErrBinaryReplaceFailed
	} else {
		procureErr = d.buildBinaryOnDisk(commitSHA, displayName, progress)
		procureCode = ErrBinaryBuildFailed
	}
	if procureErr != nil {
		d.rollback(ctx, id, displayName, restoreTargetSHA, fmt.Sprintf("%s: %v", procureCode, procureErr), backupPath, progress)
		return procureErr
	}

	// Canonical C5 injection site. The new sb binary has just been
	// written to disk (replaceBinaryOnDisk completed) but the flag
	// hasn't been stamped Phase=PostSwap yet — kill here leaves the
	// system with: new binary on disk, PreSwap flag (or no flag
	// state-stamp), migrations NOT yet applied. The next install's
	// recoverFromFlag must classify the binary state (HEAD matches
	// target? migrations missing?) and either roll forward via
	// migrate.Up or roll back via restoreBinary. No-op in production.
	inject.KillHere("killed-by-system-during-binary-swap")

	// Stamp the flag as post-swap and store the finalised backup path so
	// the next process (after exit-42 restart or syscall.Exec) can roll
	// back without a live DB connection. queryConn was closed back at
	// Step 2 for the consistent-backup stop, so we can't persist to
	// public.upgrade here — the flag file is the handoff channel.
	if err := d.updateFlagNewSbSwapped(backupPath); err != nil {
		d.rollback(ctx, id, displayName, restoreTargetSHA, fmt.Sprintf("stamp post_swap flag: %v", err), backupPath, progress)
		return err
	}
	progress.Write("  Old binary exiting so the new binary can take over ...")
	progress.Close()

	// Hand off to fresh process. Mechanism differs by mode; the semantic
	// (next process sees post_swap flag → dispatches resumeNewSb →
	// re-enters the pipeline at applyNewSbUpgrading) is the same.
	if d.runningAsService {
		// systemd-managed daemon: exit-42 → unit restarts on the new binary.
		os.Exit(42)
	}
	// Install-inline (one-shot foreground): replace this process image
	// with the new ./sb in-place. argv/env preserved; the new binary
	// hits recoverFromFlag at startup and resumes at applyNewSbUpgrading.
	sbPath := filepath.Join(d.projDir, "sb")
	if err := syscall.Exec(sbPath, os.Args, os.Environ()); err != nil {
		// exec is rare-fail (ENOEXEC on a corrupted just-built binary,
		// EACCES on a perm bug). Surface rather than fall back to the
		// in-process orchestrator — the post-swap flag is set, so the
		// operator's next ./sb invocation will pick up resume-from-flag.
		return fmt.Errorf("exec into new binary at %s: %w", sbPath, err)
	}
	// unreachable
	return nil
}

// newSbUpgradingFailure is the single failure path for the steps inside
// applyNewSbUpgrading. All step failures share one narrative and one return shape
// — operators reading the row's `error` column see the same prefix
// regardless of which post-swap step tripped.
//
// Observed state decides DIRECTION before anything destructive runs
// (STATBUS-039, the transactional model):
//
//   - ObservedAlreadyAtNew: the binary and migrations are already at-or-past
//     the target — the failed step is reconcile/bookkeeping territory and
//     forward remains logically possible. A restore here is forbidden: the
//     maintenance-off commit point may already have passed, and snapshot-
//     restoring an already-at-new box destroys anything written since (browser
//     users are gated by the app's upgrade guard while the row is
//     in_progress, but API integrators are not). Record the failure on the
//     row (non-terminal — `error` is legal on in_progress per
//     chk_upgrade_state_attributes), keep the flag on disk, and return: the
//     next recovery pass (systemd restart or ./sb install) consults observed
//     state and resumes forward.
//
//   - ObservedPositionUnreadable: cannot verify (DB unreachable mid-failure).
//     Destroying state under uncertainty is forbidden — same disposition as
//     already-at-new: loud, non-terminal, forward retry on the next pass (which
//     re-attempts db-up and re-checks).
//
//   - ObservedCannotReachNew: confirmed behind (migrations missing with a
//     reachable DB, or binary mismatch). Forward is impossible without new
//     code — run the full rsync-restore pipeline via d.rollback(), which
//     restores THIS upgrade's own snapshot (identity-keyed backupPath),
//     marks the row 'rolled_back', clears the flag, restarts containers,
//     and exits the process. Backward exists to regain a runnable state to
//     go forward from when the fix ships.
//
// The error return is reached on the already-at-new/unknown branches, and on the
// rare degraded path where d.rollback() returns without exiting.
func (d *Service) newSbUpgradingFailure(ctx context.Context, id int, displayName, restoreTargetSHA, commitSHA, backupPath, reason string, progress *ProgressLog) error {
	// STATBUS-109 (doc-022 §5): NAME the forward-step failure class explicitly.
	// A recognised deterministic failure is `persistent-error`; anything
	// unrecognised is `unknown-error` (the default). This is a diagnostic label
	// only — the DISPOSITION stays observed-state-driven (STATBUS-039): destroying
	// state under an already-at-new/unknown position is forbidden regardless of the
	// error class. The label makes the classification visible in the row/log.
	stepClass := classifyStepMessage(reason)
	obsState, _, obsReason := d.verifyUpgradeObservedStateEx(ctx, commitSHA)
	if obsState != ObservedCannotReachNew {
		verdict := "already at the new version"
		if obsState == ObservedPositionUnreadable {
			verdict = fmt.Sprintf("unverifiable (%s)", obsReason)
		}
		progress.Write("Checking the failed upgrade's position ... %s; keeping it ready to continue on the next recovery pass. Cause: %s", verdict, reason)
		d.recordInProgressFailure(ctx, id,
			fmt.Sprintf("forward step failed [%s]: %s; observed state %s — no rollback, will resume forward on the next recovery pass (service restart or ./sb install)", stepClass, reason, verdict))
		return fmt.Errorf("%s: step failed after booting the new binary [%s] with observed state %s (forward retry on next recovery): %s",
			ErrInstallPreconditionFailed, stepClass, verdict, reason)
	}
	progress.Write("Checking the failed upgrade's position ... confirmed behind the target (%s); restoring this upgrade's snapshot.", obsReason)
	d.rollback(ctx, id, displayName, restoreTargetSHA,
		fmt.Sprintf("forward failed: %s; auto-restored from snapshot", reason), backupPath, progress)
	return fmt.Errorf("%s: failure after booting the new binary auto-restored: %s",
		ErrInstallPreconditionFailed, reason)
}

// parkForDeterministicFailure (STATBUS-046 slice 2) handles a STRUCTURALLY B/C
// step failure at a Phase-3 site: park on the FIRST occurrence instead of letting
// it burn the death budget over three crash-resumes. Observed state still governs
// DIRECTION (STATBUS-039), exactly as newSbUpgradingFailure: positively-Behind →
// data-safe rollback; at-or-past-target OR unverifiable → PARK (retrying a
// deterministic failure cannot help, and already-at-new can't safely roll back —
// integrators may have written past maintenance-off). Returns an error so
// applyNewSbUpgrading stops; the row is now parked, so the next recovery pass's
// parked-skip keeps the unit alive-idle. Fires the degraded siren exactly once
// (freshlyParked), consistent with the budget-park path.
func (d *Service) parkForDeterministicFailure(ctx context.Context, id int, displayName, restoreTargetSHA, commitSHA, backupPath, reason string, progress *ProgressLog) error {
	obsState, _, obsReason := d.verifyUpgradeObservedStateEx(ctx, commitSHA)
	if obsState == ObservedCannotReachNew {
		progress.Write("Checking the failed upgrade's position ... confirmed behind the target (%s); restoring this upgrade's snapshot.", obsReason)
		d.rollback(ctx, id, displayName, restoreTargetSHA,
			fmt.Sprintf("deterministic forward failure: %s; auto-restored from snapshot", reason), backupPath, progress)
		return fmt.Errorf("%s: deterministic failure after booting the new binary auto-restored: %s", ErrInstallPreconditionFailed, reason)
	}
	// The narrative now rides parkUpgrade's SINGLE immune write (STATBUS-071): today's
	// exact bytes, so the arcs' `error LIKE '%parked on deterministic forward failure%'`
	// asserts stand. The former recordInProgressFailure call here was the split-write's
	// vulnerable half (nil-conn no-op on a dying pass) and is deleted.
	freshlyParked, perr := d.parkUpgrade(ctx, id, reason, "parked on deterministic forward failure: "+reason)
	if perr != nil {
		return fmt.Errorf("park deterministic forward failure for upgrade %d: %w", id, perr)
	}
	progress.Write("Pausing automatic upgrade retries after a deterministic failure ... ok")
	progress.Write("  Cause: %s", reason)
	progress.Write("  The service remains available for a later release or a deliberate ./sb install retry.")
	if freshlyParked {
		d.runCallback(displayName, map[string]string{"STATBUS_EVENT": "parked", "STATBUS_PARKED": "1", "STATBUS_PARK_REASON": reason})
	}
	// STATBUS-200: the park write has landed (the ordering pin — park FIRST, restoration
	// SECOND: a crash inside parkServiceRecovery leaves an already-parked row, so the
	// parked-skip invariant holds on the next boot and no attempt is consumed). Now bring the
	// SOURCE version's services back so the parked box stays OPERABLE — the North Star: a park
	// is alive-idle AND the operator's remedy lever (the web UI) is up, never a silent dark
	// outage. Era-guarded + narrative-only on refuse/failure; it only ever STARTS services on
	// permit and never stops anything. Run unconditionally (not gated on freshlyParked) so a
	// next-boot re-entry safely completes a restoration interrupted by a mid-restore crash —
	// both restores are idempotent no-ops when nothing moved.
	d.parkServiceRecovery(ctx, id, restoreTargetSHA, progress)
	return fmt.Errorf("parked on deterministic forward failure: %s", reason)
}

// parkServiceRecovery — STATBUS-200. The shared park-service-recovery helper, invoked after
// EVERY park write via the single chokepoint parkForDeterministicFailure (parkAtTarget
// delegates here too, so all park sites are covered by this one call). It brings the SOURCE
// version's services back so a parked box stays OPERABLE — the North Star: a park is alive-idle
// AND the operator's remedy lever (the web UI) is up, never a silent dark outage. ERA-GUARDED
// (the safety core): it starts source services ONLY when the DB is provably at the source
// version's schema. HARD RULE (ruling Q4): it only ever STARTS services on permit; on refuse or
// failure it stops NOTHING and changes nothing but the park narrative (appendParkNarrative).
func (d *Service) parkServiceRecovery(ctx context.Context, id int, restoreTargetSHA string, progress *ProgressLog) {
	// STATBUS-204: this helper OWNS its own watchdog cover. Its slow span — parkEraVerdict's
	// StartDBForRecovery (waits up to ~60s for DB health) plus restoreSourceServices (compose up
	// + bounded health + the restores) — can exceed WatchdogSec=120s on a cold box. The
	// deterministic park callers run under an outer gated ticker, but the budget-park callers
	// (RecoveryBudgetGuard, resumeNewSb) run post-READY in the ACTIVE phase with NONE, so without
	// this a SIGABRT would crash-loop the very park the fix makes operable. The ticker sits at
	// the TOP, spanning verdict + restoration together (the DB-health wait is inside the danger
	// window and precedes the restore). ALWAYS-PING is correct here (nil gate): every covered
	// sub-step is itself time-bounded (StartDBForRecovery's health wait, compose-up's command
	// timeout, healthCheck's bounded attempts), so a genuine hang cannot outlive the bounds' sum
	// — cover-with-bounds is hang-detection by construction (the boot-migrate always-ping
	// precedent). Owning the cover at this chokepoint covers every caller — deterministic,
	// budget, and future — at ONE point (the 200 Q4 / 197 C3 shape); the nested ticker at the
	// deterministic sites is harmless (both layers just emit WATCHDOG=1).
	tickerCtx, tickerCancel := context.WithCancel(ctx)
	tickerDone := make(chan struct{})
	go runGatedWatchdogTicker(tickerCtx, nil,
		applyNewSbUpgradingStallThreshold, applyNewSbUpgradingWatchdogCadence,
		func() { sdNotify("WATCHDOG=1") }, tickerDone)
	defer func() {
		tickerCancel()
		<-tickerDone
	}()

	// STATBUS-212 — ADOPT-OR-ACQUIRE THE FLAG HOLD. The truth-restoration below
	// (mutateHeldFlag) can only write through a HELD flock, and until now this helper
	// depended on its caller happening to hold one: the deterministic path does, but
	// BOTH budget-park sites do not (RecoveryBudgetGuard releases before calling here;
	// resumeNewSb's same-step-twice branch never acquired at all), so there the rewrite
	// silently warned and the marker kept lying — exactly the un-park→rollback collision
	// STATBUS-210 exists to kill. A contract that depends on ambient caller state it
	// neither owns nor checks is the drift class the STATBUS-196 gate hunts, and the
	// same one STATBUS-204 already ruled on for this very function: THE CHOKEPOINT OWNS
	// ITS INVARIANT. So the hold is owned here, once, for every caller present and
	// future — no call site changes.
	//
	// Already held (the SAME predicate mutateHeldFlag uses, deliberately not a new one):
	// use it, do not acquire, do not release — the deterministic path stays
	// byte-for-byte unchanged, so STATBUS-210's arc-proven coverage is untouched.
	// Not held: acquire VERBATIM (acquireFlock rewrites the file with whatever it is
	// handed) and release exactly what was acquired. No deadlock risk: neither
	// parkEraVerdict nor restoreSourceServices touches the flock anywhere in its body.
	releaseFlagHold, lerr := d.adoptOrAcquireFlagHold()
	if lerr != nil {
		// CONTENDED — REFUSE THE WHOLE HELPER, before any service is started. A live
		// holder is this codebase's liveness signal that ANOTHER actor owns box
		// mutations (STATBUS-111), and that actor may be mid-upgrade: starting the
		// SOURCE version's services underneath it is precisely the mixed-era guess
		// parkEraVerdict refuses on every other anomaly ("the fail-safe direction is
		// ALWAYS dark-behind-the-maintenance-page, never a guess toward serving
		// mixed-era"). Not "restore anyway and skip the rewrite" — that would trade a
		// lying marker for a possibly-mixed-era box. Near-unreachable in practice (the
		// only realistic contender, ./sb install crash recovery, quiesces this unit
		// SIGKILL-class before it could hold the lock), but the arm must be correct.
		d.appendParkNarrative(id, fmt.Sprintf("services held down: the upgrade flag's lock is held by another live actor (%v) — another process owns box mutations right now, so the source version's services are NOT started (starting them underneath a possibly mid-upgrade actor would serve a mixed era). The box stays behind the maintenance page; re-trigger the upgrade or run ./sb install once that actor is done", lerr))
		return
	}
	defer releaseFlagHold()

	permit, refusal := d.parkEraVerdict(ctx, id)
	if !permit {
		d.appendParkNarrative(id, refusal)
		return
	}
	if err := d.restoreSourceServices(ctx, restoreTargetSHA, progress); err != nil {
		d.appendParkNarrative(id, fmt.Sprintf("source-version service restore did not complete (%v) — the box stays behind the maintenance page until the cause is fixed and the upgrade re-triggered", err))
		return
	}
	// STATBUS-210, AS AMENDED BY STATBUS-229 — RECORD THE RETREAT AS ITS OWN FACT.
	//
	// The successful restoration returned the box to its PRE-SWAP reality (source git + source
	// binary + source config, via restoreSourceServices), so the held flag's post-swap phase
	// marker no longer describes the box. 210 was right about that and right that a stale
	// marker gets the un-parked row rolled back; its REMEDY was the defect.
	//
	// 210 expressed "this box retreated to source" by blanking Phase to PhaseOldSbUpgrading —
	// a value that ALREADY means "died before the swap" (it is the empty string, :259). Two
	// distinct states then shared one wire value, and recoverFromFlag's PreSwap branch (:1341)
	// rolls back UNCONDITIONALLY — so the un-park granted a fresh attempt and the next step
	// rolled it back, which is precisely the collision 210 set out to prevent (STATBUS-229;
	// observed at rc.03 in un-park-to-completion, plus a DB restore on an at-target lineage).
	//
	// The phase vocabulary describes POSITIONS INSIDE AN IN-FLIGHT UPGRADE. After a completed
	// retreat every one of its values is a lie, so there is no honest phase to write. Record
	// the FACT instead, in a field named for it, and leave Phase alone: readers that ask
	// "where was this upgrade?" still get a truthful answer, and the new question ("is it
	// over?") gets its own field rather than a borrowed one. The un-park then removes the flag
	// outright (cli/cmd/install_upgrade.go, beside ClearFlagStepHistory) — after a completed
	// retreat the WHOLE flag is stale, not one more field of it.
	//
	// ONLY on this era-permitted SUCCESS arm: a refusal (no restoration ran → the flag still
	// truthfully describes a mid-upgrade box) and a restoration failure (box state unproven)
	// both leave the flag byte-untouched via the early returns above. That distinction is
	// load-bearing — see the un-park's conditional.
	retreatAt := time.Now()
	if err := d.mutateHeldFlag(func(f *UpgradeFlag) { f.RetreatedToSourceAt = &retreatAt }); err != nil {
		progress.Write("Recording the restored source state in the upgrade lock file ... failed: %v", err)
	}
	progress.Write("Restoring source-version services for operator access ... ok (automatic retries remain paused)")
}

// parkEraVerdict is the STATBUS-200 ERA GUARD — the safety core. It permits source-service
// restoration ONLY when the DB is provably at the SOURCE version's schema, via a SOURCE-IDENTITY
// comparison (architect ruling Q1), NOT a pending-count: migrate.HasPending is inverted for this
// — a pre-delta park has pending=true on a pure-source DB (must permit), a post-delta park has
// pending=false on a migrated DB (must refuse). Permit iff db.migration's applied max EQUALS the
// source version's expected max — the source resolved from the row's recorded from_commit_version
// (git rev-parse → git ls-tree, no checkout, so it works while the tree sits at the target).
// EVERY anomaly REFUSES with a named narrative: the fail-safe direction is ALWAYS
// dark-behind-the-maintenance-page, never a guess toward serving mixed-era.
func (d *Service) parkEraVerdict(ctx context.Context, id int) (permit bool, refusalNarrative string) {
	const held = "services held down"
	// The DB may be stopped at a pre-start park (StepImagePull is before StepDBUp). Bring the
	// EXISTING db+proxy up (start, never recreate — StartDBForRecovery) so the applied-max read
	// can run; a running DB under the still-engaged read-only window is harmless (ruling Q1).
	if err := d.StartDBForRecovery(ctx); err != nil {
		return false, fmt.Sprintf("%s: the database could not be started to verify source-version identity (%v)", held, err)
	}
	// Reads ride the teardown-immune fresh-conn primitive (terminalUpdate), so they do not
	// depend on d.queryConn's state (nil at the pre-reconnect StepImagePull park).
	dbMaxStr, err := d.terminalUpdate("SELECT COALESCE(MAX(version), 0)::text FROM db.migration")
	if err != nil {
		return false, fmt.Sprintf("%s: the applied migration version could not be read (%v)", held, err)
	}
	dbMax, perr := strconv.ParseInt(strings.TrimSpace(dbMaxStr), 10, 64)
	if perr != nil {
		return false, fmt.Sprintf("%s: the applied migration version %q was unparseable (%v)", held, dbMaxStr, perr)
	}
	fromCommit, err := d.terminalUpdate("SELECT COALESCE(from_commit_version, '') FROM public.upgrade WHERE id = $1", id)
	if err != nil {
		return false, fmt.Sprintf("%s: the source version could not be read from the row (%v)", held, err)
	}
	fromCommit = strings.TrimSpace(fromCommit)
	if fromCommit == "" {
		return false, held + ": the source version was not recorded on this row — cannot verify source-version identity"
	}
	srcSHA, rerr := d.RevParse(ctx, fromCommit)
	if rerr != nil {
		return false, fmt.Sprintf("%s: the source version %q could not be resolved to a commit (%v)", held, fromCommit, rerr)
	}
	srcMax, serr := migrationMaxInGitTree(d.projDir, string(srcSHA))
	if serr != nil {
		return false, fmt.Sprintf("%s: the source version's migration set could not be read (%v)", held, serr)
	}
	return parkEraDecision(dbMax, srcMax)
}

// parkEraDecision is the pure SOURCE-IDENTITY comparison at the heart of the era guard
// (extracted for direct testing). Permit iff the DB's applied migration max EQUALS the source
// version's expected max — covering BOTH the codeonly (no-delta; both 0 or equal) and pre-delta
// (delta pending but unapplied; DB still at source) cases. db_max > source_max REFUSES (the delta
// partially or fully applied — the mixed-era class). db_max < source_max REFUSES as an anomaly.
// This is deliberately NOT a pending-count: migrate.HasPending is inverted here (pending=true on a
// pure-source pre-delta DB that must permit; pending=false on a migrated post-delta DB that must
// refuse). The fail-safe direction is always refuse.
func parkEraDecision(dbMax, srcMax int64) (permit bool, refusalNarrative string) {
	const held = "services held down"
	switch {
	case dbMax == srcMax:
		return true, "" // DB provably at source — the codeonly (no-delta) and pre-delta cases
	case dbMax > srcMax:
		return false, held + ": migration delta applied, source version incompatible — the database is past the source schema; starting source containers against a migrated DB is the mixed-era class"
	default: // dbMax < srcMax — an unexpected state; fail safe
		return false, fmt.Sprintf("%s: the database (applied max %d) is behind the source version (max %d), an unexpected state", held, dbMax, srcMax)
	}
}

// migrationMaxInGitTree returns the highest migration version present in a git tree's
// migrations/ directory WITHOUT checking it out — `git ls-tree <sha> -- migrations/`,
// filename-parsing the 14-digit version prefix of each *.up.sql / *.up.psql. Used by the
// STATBUS-200 era guard to read the SOURCE version's migration set while the working tree sits
// at the target. Returns 0 with no error when the tree has no migrations (a codeonly source is a
// legitimate empty set); a git failure is a real error (the guard then fails safe → refuse).
func migrationMaxInGitTree(projDir, sha string) (int64, error) {
	out, err := runCommandOutput(projDir, "git", "ls-tree", "--name-only", sha, "--", "migrations/")
	if err != nil {
		return 0, fmt.Errorf("git ls-tree %s -- migrations/: %w (%s)", sha, err, strings.TrimSpace(out))
	}
	var max int64
	for _, line := range strings.Split(out, "\n") {
		base := filepath.Base(strings.TrimSpace(line))
		if !strings.HasSuffix(base, ".up.sql") && !strings.HasSuffix(base, ".up.psql") {
			continue
		}
		if len(base) < 14 {
			continue
		}
		v, perr := strconv.ParseInt(base[:14], 10, 64)
		if perr != nil {
			continue // non-conforming name — the applier (migrate.MaxDiskVersion) ignores it too
		}
		if v > max {
			max = v
		}
	}
	return max, nil
}

// restoreSourceServices brings the SOURCE version's application services back on a parked box
// (STATBUS-200, ruling Q2): the rollback restore tail MINUS restoreDatabase — restore the git
// tree + binary + config to the source, then start app/worker/rest/proxy from the LOCAL source
// images (--no-build, NO pull; the disk is full — that is the whole point), a bounded health
// gate, and maintenance OFF + the read-only window LIFT ONLY on a passing health check
// (serve-proven — never claim serving without proving it). restoreDatabase is DELIBERATELY
// skipped: the era guard already proved the DB is at the source version, so there is nothing to
// restore and the mixed-era hazard cannot arise. Both restores are idempotent no-ops when
// nothing moved (git checkout -f onto the current HEAD; restoreBinary is silent without sb.old),
// so a pre-checkout park needs no special case (ruling Q2 rider i). The 197 boundary (rider ii):
// this runs only in attempts that got past backup — their pin and sb.old are their own, so
// identity holds; the never-ran class (empty backupPath) is 197's guard and the two never collide.
func (d *Service) restoreSourceServices(ctx context.Context, restoreTargetSHA string, progress *ProgressLog) error {
	progress.Write("Restoring source-version services:")
	if err := d.restoreGitState(restoreTargetSHA, progress); err != nil {
		return fmt.Errorf("restore git tree to source: %w", err)
	}
	d.restoreBinary(progress)
	if err := runCommandToLog(d.projDir, 2*time.Minute, progress.File(), "park-config-generate", progress.bump, filepath.Join(d.projDir, "sb"), "config", "generate"); err != nil {
		return fmt.Errorf("config generate at source: %w", err)
	}
	// LOCAL source images only (--no-build, no pull): the whole point is that the disk is full.
	composeArgs := append([]string{"compose", "up", "-d", "--no-build"}, step11RestartServices...)
	if out, err := runCommandOutput(d.projDir, "docker", composeArgs...); err != nil {
		return fmt.Errorf("start source services (compose up --no-build): %w (%s)", err, strings.TrimSpace(out))
	}
	if err := d.healthCheck(progress, 5, 5*time.Second); err != nil {
		return fmt.Errorf("source services did not pass the health gate: %w", err)
	}
	// Serve-proven: health passed, so lift the operator-facing gates. maintenance OFF first
	// (mirrors the completion sites), then the read-only window via the teardown-immune flip.
	if err := d.setMaintenance(false, ""); err != nil {
		return fmt.Errorf("source services are up and healthy but maintenance mode did not lift: %w", err)
	}
	if _, err := d.liftReadOnlyWindow("serve-proven health check"); err != nil {
		return fmt.Errorf("source services are up and healthy but the read-only window did not lift (%v) — reads serve, writes are refused until `./sb install` or the next boot clears it", err)
	}
	return nil
}

// appendParkNarrative (STATBUS-200, ruling Q3) APPENDS a note to an ALREADY-parked row's reason
// + error via the teardown-immune terminal write — a narrative-ONLY operation. It is guarded
// `recovery_parked_at IS NOT NULL AND state='in_progress'` and NEVER sets recovery_parked_at,
// never consumes an attempt, never flips state — so the single-park-writer discipline is
// preserved: parkUpgrade remains the ONLY site setting recovery_parked_at (the STATBUS-196
// SingleParkWriter drift gate counts the park-timestamp write — the assignment of now() to
// recovery_parked_at — which this narrative-only append never performs).
// Best-effort — the park itself (the senior parkUpgrade write) already landed; a failed append
// only loses the row-level note, never crashes, never a second park write. Single caller:
// parkServiceRecovery.
func (d *Service) appendParkNarrative(id int, note string) {
	suffix := " — " + note
	if _, err := d.terminalUpdate(
		"UPDATE public.upgrade SET recovery_parked_reason = COALESCE(recovery_parked_reason, '') || $2, error = COALESCE(error, '') || $2 WHERE id = $1 AND state = 'in_progress' AND recovery_parked_at IS NOT NULL"+upgradeRowReturning,
		id, suffix); err != nil {
		fmt.Printf("appendParkNarrative: could not extend the parked narrative on row %d: %v\n", id, err)
	}
}

// dockerStepMinFreeGB is the free-space floor a docker pull/up needs (doc-021
// C-row intent). This is the "will this step fail" bar — the image set + layer
// unpack headroom — NOT the install ladder's "should we install here" bar
// (cli/cmd/install.go:441 defaults 100 GB). Below this floor the pull/unpack WILL
// hit ENOSPC, so we park BEFORE the step rather than after (retrying a
// disk-exhausted step amplifies it). Tunable at build/arc.
const dockerStepMinFreeGB = 5

// diskPrecheckReason (STATBUS-046 slice 2, Q2 amendment) is the PRIMARY class-C
// (resource) signal for the docker steps — a LOCAL statfs check via DiskFree
// (cross-platform), fully STRUCTURED (no text). Returns a non-empty park reason
// when free space is below dockerStepMinFreeGB; "" otherwise (proceed). A
// DiskFree read error returns "" — don't false-park on an unreadable statfs; the
// in-flight ENOSPC backstop + the death budget still bound the step.
func (d *Service) diskPrecheckReason(step string) string {
	freeBytes, err := DiskFree(d.projDir)
	if err != nil {
		log.Printf("disk pre-check before %s: statfs failed (%v) — proceeding; the ENOSPC backstop + death budget still bound this step", step, err)
		return ""
	}
	freeGB := freeBytes / (1024 * 1024 * 1024)
	if freeGB < dockerStepMinFreeGB {
		return fmt.Sprintf("disk nearly full: %d GB free (< %d GB needed) before %s — free disk space, then re-trigger the upgrade",
			freeGB, dockerStepMinFreeGB, step)
	}
	return ""
}

// recordInProgressFailure persists a failure narrative on an in_progress row
// WITHOUT transitioning it to a terminal state. chk_upgrade_state_attributes
// permits a non-NULL `error` on in_progress (only completed forbids it), so
// the admin UI shows WHY the upgrade is still in progress between forward
// retries. Best-effort: the progress log already carries the narrative; a
// failed UPDATE here (stale conn — plausible, given we are on a failure
// path) only loses the row-level mirror.
func (d *Service) recordInProgressFailure(ctx context.Context, id int, errMsg string) {
	if d.queryConn == nil {
		return
	}
	if _, err := d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET error = $1 WHERE id = $2 AND state = 'in_progress'",
		errMsg, id); err != nil {
		fmt.Printf("recordInProgressFailure: could not persist error on row %d: %v\n", id, err)
	}
}

// applyNewSbUpgrading runs the upgrade steps that require the target binary's
// compiled code: config generate → docker pull → db up → waitForDBHealth →
// reconnect → persist final backup_path → migrate → app/worker/rest up →
// health check → maintenance off → archive → install-fixup → state=completed.
//
// Single entry point: resumeNewSb, dispatched by recoverFromFlag when
// a fresh process (post exit-42 systemd restart for service mode, post
// syscall.Exec for inline mode) sees Phase=PhaseNewSbSwapped. Every
// upgrade — tagged or edge, service or inline — handsoff in executeUpgrade
// before reaching here, so applyNewSbUpgrading always runs against the NEW
// compiled Go code.
//
// Step failures route through newSbUpgradingFailure (single rollback path with
// unified narrative). The legacy direct d.rollback() pattern was retired
// so the row's `error` column reads consistently across all nine sites.
//
// Preconditions on entry: db container stopped; maintenance mode on; backup
// on disk at backupPath; git HEAD at target commit; ./sb binary at target
// version; d.queryConn is nil (reopened via reconnect() below). Flag file
// and its flock are held by d.flagLock.
func (d *Service) applyNewSbUpgrading(ctx context.Context, id int, commitSHA, displayName, restoreTargetSHA, backupPath string, recreate bool, progress *ProgressLog) error {
	projDir := d.projDir

	// SINGLE progress-gated WATCHDOG=1 ticker for the ENTIRE applyNewSbUpgrading body
	// (config-generate → docker pull → docker up db → waitForDBHealth →
	// reconnect → migrations → step-11 docker up → health → terminal UPDATE).
	// All of these can run for many minutes on real data (cold image pull on a
	// slow box; a large-DB migration runs for ~minutes); the main goroutine is
	// parked in subprocess or pgx waits with
	// no opportunity to ping WATCHDOG=1 from the main loop. Without this
	// goroutine, WatchdogSec=120 s (per ops/statbus-upgrade.service) fires and
	// systemd SIGABRTs the unit → restart loop → never reaches
	// `state='completed'`.
	//
	// applyNewSbUpgrading runs in the unit's ACTIVE phase on BOTH entries (READY=1
	// fired in Service.Run before the main loop / before recoverFromFlag since
	// plan piece #2), so systemd enforces WatchdogSec, and per sd_notify(3)
	// only WATCHDOG=1 — not the deleted EXTEND_TIMEOUT_USEC — resets that
	// deadline.
	//
	// PROGRESS-GATED (plan upgrade-resume-structural-whole.md piece #3): the
	// ticker pings only while the pipeline is advancing (shouldPingWatchdog).
	// A HUNG step stops bumping lastAdvanceAt → the gate closes → pings stop →
	// WatchdogSec fires and the unit is reaped (instead of a blind ticker
	// pinging forever past a wedged step). The uniform principle: GATE every
	// output-emitting step (output distinguishes slow-from-hung) and DEFER only
	// the genuinely-SILENT-but-BOUNDED blocking steps. Output steps bump via
	// per-line output (progress.bump threaded as runCommandToLog's onAdvance —
	// covers config-generate, docker pull, docker up, step-11 up) or
	// step-boundary progress.Write. The two silent steps are exempted
	// (deferGating, always-ping) because output-gating can't tell them from a
	// hang, each bounded by its OWN timeout instead of by the watchdog:
	//   - migrate / recreate-database — silent for minutes on one big DDL;
	//     bounded by its runCommandToLog timeout (30 m) + task #7.
	//   - reconnect — pgx dial+handshake emits nothing; bounded by connect()'s
	//     5-min ctx deadline (added with this piece) + task #7.
	//
	// STARTED AT THE TOP (engineer #2-trace coverage finding): the pre-reconnect
	// steps (config-generate, docker pull, docker up db, waitForDBHealth) each
	// run a SILENT subprocess after a single progress.Write; a cold large-image
	// pull >120 s would otherwise blow WatchdogSec mid-pull (the ticker must
	// already be running AND fed by their per-line bumps, not started after
	// them). So the ticker starts here, before config-generate, and the per-line
	// progress.bump on those steps keeps a live-but-slow pull alive while a hung
	// one (no output > 3 min) trips.
	//
	// COLLAPSE: this one ticker replaces the prior TWO unconditional tickers —
	// the reconnect-scoped one (which protected only d.reconnect) and the
	// applyNewSbUpgrading-remainder one (d416a50a0's migrate-only ticker, later
	// widened). Both were blind 30 s timers; an unconditional ticker is itself
	// a blind-watchdog hole — the old reconnect ticker would have pinged forever
	// past a wedged pgx.Connect (which was unbounded). The fix is twofold: the
	// gate stops pinging a hung OUTPUT step, and the two silent steps are bounded
	// by their own timeouts (migrate→runCommandToLog, reconnect→connect()'s new
	// 5-min ctx) so deferring gating during them is safe, not blind-forever.
	// Reproduced empirically by scenario 19 (reconnect stall).
	//
	// Cancelled via defer so every error-return path in applyNewSbUpgrading reaps the
	// goroutine cleanly. The first tick is gated like every other (no special
	// unconditional initial ping); reaching applyNewSbUpgrading IS an advance, so we
	// bump lastAdvanceAt right here — making the gate-open-on-entry guarantee
	// structural (independent of whether an upstream progress.Write happened to
	// fire recently) so the deadline resets before config-generate can run long.
	progress.bump()
	applyExtendCtx, applyExtendCancel := context.WithCancel(ctx)
	applyTickerDone := make(chan struct{})
	go runGatedWatchdogTicker(applyExtendCtx, progress,
		applyNewSbUpgradingStallThreshold, applyNewSbUpgradingWatchdogCadence,
		func() { sdNotify("WATCHDOG=1") }, applyTickerDone)
	defer func() {
		applyExtendCancel()
		<-applyTickerDone
	}()

	// Regenerate config via the NEW binary. VERSION comes from git describe
	// --tags --always against the just-checked-out HEAD.
	d.markStep(StepConfigGenerate)
	if err := runCommandToLog(projDir, 2*time.Minute, progress.File(), "config-generate", progress.bump, filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
		// STATBUS-046 slice 2: config generate renders templates from .env.config
		// (no network/DB), so a NON-TIMEOUT failure is deterministic (B) — PARK on
		// FIRST with a named reason instead of burning three deaths. A timeout is
		// classUnknown → the existing forward-retry (death-budget-bounded).
		if classifyStepFailure(StepConfigGenerate, err).parksOnFirst() {
			return d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath,
				fmt.Sprintf("config generate failed at %s: %v", displayName, err), progress)
		}
		return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, fmt.Sprintf("./sb config generate: %v", err), progress)
	}
	progress.Write("Regenerating configuration (.env, Caddyfile) ... ok")

	// Step 8: Pull updated images. --profile all is MANDATORY, not cosmetic:
	// every service in this compose project is profile-gated (app/worker/db/
	// rest/proxy all carry profiles: all / all_except_app / app — none is
	// profile-less) and COMPOSE_PROFILES is never set. A bare `docker compose
	// pull` therefore selects ZERO services and silently pulls nothing, leaving
	// the real fetch to fall through to step 11's named `up -d` — AFTER the
	// destructive migration (the STATBUS-047 item-A hazard). `all` is the
	// superset fresh-install (cli/cmd/install.go:1034) and rollback (below) use.
	d.markStep(StepImagePull)
	// STATBUS-046 slice 2: PRIMARY class-C disk pre-check (structured statfs) —
	// park BEFORE the pull if free space can't hold the images.
	if reason := d.diskPrecheckReason(StepImagePull); reason != "" {
		return d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, reason, progress)
	}
	pullStart := time.Now()
	if stderrTail, err := runCommandToLogCapture(projDir, 5*time.Minute, progress.File(), "docker-compose", progress.bump, "docker", "compose", "--profile", "all", "pull"); err != nil {
		// ENOSPC backstop: disk filled DURING the pull (past the pre-check) → C park.
		if classifyDockerFailure(err, stderrTail) == classResource {
			return d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath,
				fmt.Sprintf("disk full during image pull at %s (no space left on device) — free disk space, then re-trigger the upgrade", displayName), progress)
		}
		return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, fmt.Sprintf("%s: docker compose pull: %v", ErrDockerUpFailed, err), progress)
	}
	progress.Write("Pulling updated images ... ok (%s)", formatProgressDuration(time.Since(pullStart), false))

	// Step 9: Start database. --no-build forces compose to USE THE PULLED IMAGE
	// and fail if it's absent, rather than silently falling back to a local
	// build from source (which for the db service means compiling pgrx
	// extensions — pg_graphql, sql_saga_native, jsonb_stats — from Rust/cargo,
	// a 10+ minute operation that blows past the 5m command timeout and gives
	// no useful error). If the image isn't in the registry yet, CI hasn't
	// built it. Tell the operator to wait for images.yaml and retry.
	d.markStep(StepDBUp)
	dbStart := time.Now()
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "docker-compose", progress.bump, "docker", "compose", "up", "-d", "--no-build", "db"); err != nil {
		reason := fmt.Sprintf(
			"%s: docker compose up -d db: %v\n\n"+
				"The db image for %s is not available locally or in the registry. "+
				"CI builds images on every master push (images.yaml); commit-tagged "+
				"images take a few minutes to land. Wait for that workflow to finish, "+
				"then retry the upgrade. Check status: "+
				"gh run list --workflow=images.yaml",
			ErrDockerUpFailed, err, displayName)
		return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, reason, progress)
	}

	// Wait for DB health — STATBUS-046 slice 3 (doc-021 3.3): class-A readiness
	// allowance, size-scaled-intent to the WAL-replay worst case (NewSbUpgradingDBHealthTimeout,
	// generous fixed budget) so a healthy-but-replaying large volume isn't
	// mis-read as a failure. In-place; never consumes a death.
	if err := d.waitForDBHealth(NewSbUpgradingDBHealthTimeout); err != nil {
		return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, fmt.Sprintf("%s: DB health check: %v", ErrHealthcheckDBDown, err), progress)
	}
	progress.Write("Starting database ... healthy (%s)", formatProgressDuration(time.Since(dbStart), false))

	// Reconnect service DB connection — a legitimately SILENT blocking step
	// (pgx dial+handshake emits no per-line output), so output-gating can't
	// distinguish a slow-but-live reconnect from a hang. Like the migrate step,
	// it is therefore deferGating-EXEMPT (the gated ticker always pings during
	// it) — SAFE only because reconnect is now itself BOUNDED: connect() wraps
	// the dial+handshake in a 5-min ctx deadline (see connect()), mirroring how
	// migrate is bounded by its runCommandToLog timeout. A genuine hang is
	// killed at 5 min → reconnect returns DeadlineExceeded → newSbUpgradingFailure →
	// rollback (task #7 backstops a loop), NOT pinged forever (the
	// blind-unbounded hole the old unconditional reconnect ticker left open).
	//
	// The deferGating span covers the harness stall point (C15 / Race D) through
	// reconnect completion: set true here, reset via defer after the reconnect
	// returns (scoped to this block via the closure so an error-return mid-block
	// can't leave gating disabled for migrate / step 11). A
	// genuinely slow reconnect under the 5-min bound survives (the exempt ticker
	// keeps the unit alive); a > 5-min hang is reaped by reconnect's own bound.
	reconnErr := func() error {
		progress.setDeferGating(true)
		defer progress.setDeferGating(false)

		// Harness-only stall site (C15 / Race D): simulates a slow DB reconnect
		// after the DB container restart earlier in this method (docker compose
		// up -d --no-build db). It parks the main goroutine; the deferGating
		// ticker keeps WATCHDOG=1 firing so systemd's WatchdogSec can't trip
		// during a legitimately slow reconnect. Activated by
		// STATBUS_INJECT_AT=service-watchdog-timeout-during-db-reconnect-after-container-restart
		// and held by STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE. No-op in
		// production. (A REAL > 5-min hang here is bounded by connect()'s 5-min
		// ctx, not by the watchdog — see the block comment above.)
		inject.StallHere("service-watchdog-timeout-during-db-reconnect-after-container-restart")

		// d.queryConn was nil on entry (the pre-swap teardown closed it);
		// reconnect reopens both conns (bounded by connect()'s 5-min ctx) and
		// re-acquires the advisory lock.
		d.markStep(StepReconnect)
		return d.reconnect(ctx)
	}()
	if reconnErr != nil {
		return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, fmt.Sprintf("%s: reconnect to DB: %v", ErrHealthcheckDBDown, reconnErr), progress)
	}
	progress.Write("Reconnecting to database ... ok")

	// STATBUS-228: THE SINGLE ROW RECORDER of backup_path, and deliberately the FIRST
	// write after the reconnect — before anything else in this phase can fail and skip
	// it. The server was STOPPED from Step 4 through the swap, so this is the earliest
	// instant the row CAN be told the truth; recording it any earlier is not a stricter
	// contract, it is a write that silently never lands (that was the 197 defect).
	//
	// Until this line the FLAG is the authoritative carrier (stamped at the swap), and
	// it stays authoritative for crash recovery either way — the row's copy exists for
	// the readers that cannot see the flag: STATBUS-111's human-gated restore replay
	// (state='failed' AND backup_path IS NOT NULL) and the :3761 abort-hold guard, which
	// FAILS OPEN when the column is NULL and would strip the read-only hold protecting a
	// broken volume. Both were dead fleet-wide while this was the second recorder rather
	// than the only one.
	//
	// Log on failure: the DB still holds no path; reconcileBackupDir will emit
	// BACKUP_MISSING on the next tick, surfacing the issue.
	if _, err := d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET backup_path = $1 WHERE id = $2", backupPath, id); err != nil {
		progress.Write("Recording the database backup path ... failed: %v", err)
	}

	// R1 quiesce: stop worker / app / rest if any are still running
	// before step 10's DDL phase. In the normal applyNewSbUpgrading flow the
	// pre-swap teardown already stopped them, so this is usually a
	// no-op; the defensive call covers recovery paths where
	// resumeNewSb re-enters applyNewSbUpgrading and a prior partial run
	// may have left clients up. Step 11 below starts worker/app/rest
	// unconditionally as the natural resume point — no separate
	// ResumeClients call needed here. db, proxy, caddy stay running
	// throughout (db is the DDL target).
	quiescedClients, quiesceErr := compose.QuiesceClients(projDir)
	if quiesceErr != nil {
		return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath,
			fmt.Sprintf("quiesce clients before migrations: %v (must not proceed with DDL on live services)", quiesceErr), progress)
	}
	if len(quiescedClients) > 0 {
		progress.Write("Stopping app, worker, rest before database changes ... ok")
	}

	// Step 10: Run migrations (or recreate database if requested).
	// `recreate` arrives via parameter — sourced from the DURABLE
	// public.upgrade.recreate column read atomically at claim (STATBUS-092) and
	// carried through executeUpgrade → writeUpgradeFlag → flag.Recreate →
	// applyNewSbUpgrading. No volatile in-memory flag to reset.
	d.markStep(StepMigrateUp)
	if recreate {
		// deferGating: recreate-database runs the full migration set + seed; it
		// can be silent for minutes on a single big DDL, so output-gating would
		// false-trip it. Exempt it (always-ping) for the duration of THIS call,
		// bounded by the 30-min runCommandToLog timeout + task #7's cumulative-
		// activating cap on a restart loop (same docker-exec orphan caveat as
		// the migrate arm below — the clean in-container kill is task #14). The
		// defer-reset is scoped to this arm via the closure, so a panic /
		// early-return inside runCommandToLog can never leave gating disabled
		// for a later step.
		err := func() error {
			progress.setDeferGating(true)
			defer progress.setDeferGating(false)
			return runCommandToLog(projDir, 30*time.Minute, progress.File(), "recreate-database", progress.bump, filepath.Join(projDir, "dev.sh"), "recreate-database")
		}()
		if err != nil {
			if errors.Is(err, ErrCommandTimeout) {
				// #14: recreate-database also runs psql in the db container, so a
				// timeout leaves the same orphaned backend — terminate it before
				// rollback (timeout-only; see the migrate arm below).
				d.terminateMigrateOrphan(ctx, progress)
			}
			return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, fmt.Sprintf("%s: ./dev.sh recreate-database: %v", ErrMigrationFailed, err), progress)
		}
		progress.Write("Recreating database from scratch (--recreate) ... ok")
	} else {

		// Phase note: applyNewSbUpgrading runs in the unit's ACTIVE phase on BOTH
		// entries. SCHEDULED path: the main loop dispatches executeUpgrade
		// after Service.Run sent READY=1. RESUME path (recoverFromFlag →
		// resumeNewSb → applyNewSbUpgrading): since plan
		// upgrade-resume-structural-whole.md piece #2, READY=1 is emitted
		// BEFORE recoverFromFlag, so the resume is active-phase too. Active-
		// phase systemd enforces WatchdogSec (=120 s per
		// ops/statbus-upgrade.service); only WATCHDOG=1 resets that deadline.
		//
		// The single gated ticker started at the top of applyNewSbUpgrading
		// handles the active-phase WATCHDOG=1 heartbeat for the remainder of
		// applyNewSbUpgrading -- migrate-up + step 11 + step 12 + terminal UPDATE. On
		// BOTH paths it keeps the unit alive across long
		// steps WHILE THEY ADVANCE (plan piece #3 progress-gating).
		//
		// migrate is the one step that can be legitimately SILENT for minutes
		// (a single CREATE INDEX on a huge table emits no output), so output-
		// gating can't distinguish it from a hang. We exempt it via deferGating
		// (always-ping) for the duration of the runCommandToLog call, bounded by
		// the step's own 30-min timeout — an EXPLICIT BOUNDED defer, not a
		// blind-forever ping. A hung migrate is therefore caught at 30 min (the
		// runCommandToLog CommandContext deadline) and its restart LOOP is
		// further capped by task #7 (cumulative-activating > 30 min → unit
		// failed). NB: the 30-min host-side SIGKILL does NOT cleanly roll back
		// the in-container backend — migrate runs psql IN the db container via
		// `docker compose exec -T` (migrate.go), and docker-exec does not forward
		// SIGKILL, so the in-container psql is ORPHANED (txn open, locks held).
		// deferGating + #7 bound the LOOP; the CLEAN kill (server-side
		// pg_terminate_backend by app_name on migrate-timeout) is task #14, a
		// pre-existing hole closed separately. The defer-reset is scoped to this
		// arm via the closure so a panic / early-return inside runCommandToLog
		// can never leave gating disabled for step 11.
		// progress.bump is threaded as onAdvance so a migration that DOES emit
		// per-line output also bumps lastAdvanceAt (belt-and-suspenders;
		// deferGating already keeps the gate open here).
		//
		// History: d416a50a0 introduced a narrower migrate-only ticker
		// (extendCtx/extendCancel around just runCommandToLog) which
		// cancelled BEFORE step 11 -- leaving the remaining heavy steps
		// uncovered, causing a watchdog kill in the post-migrate active phase;
		// the unified gated ticker above subsumes the migrate-only one and
		// closes the gap.
		migrateStart := time.Now() // STATBUS-096: baseline for the db-container StartedAt comparison
		pendingMigrations := 0
		err := func() error {
			progress.setDeferGating(true)
			defer progress.setDeferGating(false)
			// STATBUS-201 — DELTA-scoped migrate stall (KindStall). Fires ONLY here, in
			// the daemon's applyNewSbUpgrading DELTA migrate — NEVER in boot-migrate. The
			// generic runPsqlFile marker (migration-slower-than-systemd-unit-timeout,
			// migrate.go:537) cannot be armed via unit-env for the timeout arc: since
			// STATBUS-116 post_restore fixups run through runPsqlFile on EVERY migrate-up,
			// so the daemon's OWN boot stalls there before listenLoop and never claims the
			// scheduled row. This marker lives in the daemon parent inside the migrate
			// step's deferGating span, so the WATCHDOG=1 gated ticker (the STATBUS-012
			// cover) is exercised while the row is genuinely in_progress — identical cover,
			// delta-only by construction. No-op in production (env unset).
			inject.StallHere("upgrade-delta-migration-slower-than-systemd-unit-timeout")
			var runErr error
			pendingMigrations, runErr = runMigrateUpToLog(projDir, MigrateUpTimeout, progress.File(), progress.bump, filepath.Join(projDir, "sb"), "migrate", "up", "--verbose")
			return runErr
		}()

		if err != nil {
			// #14: a migrate TIMEOUT means the host-side process-group SIGKILL
			// reaped the docker-exec client but left the in-container psql
			// backend orphaned (docker-exec doesn't forward SIGKILL) — txn open,
			// locks held, commit-after-rollback hazard. Terminate it on the live
			// conn BEFORE the rollback so its txn is deterministically aborted.
			// Only on timeout: a clean migrate failure means psql exited.
			if errors.Is(err, ErrCommandTimeout) {
				// STATBUS-095: the migrate subprocess ran past MigrateUpTimeout (the 12h
				// ceiling, or a STATBUS_MIGRATE_UP_TIMEOUT override) and was SIGKILLed at
				// the ctx deadline. Emit the NAMED ceiling marker to the daemon journal
				// BEFORE the orphan-reap + rollback so it precedes them — the greppable
				// observable the STATBUS-095 ceiling arc keys on. The failure then routes
				// by the existing path (a timeout is classUnknown → not parksOnFirst →
				// newSbUpgradingFailure → observed state Behind → in-process rollback →
				// rolled_back); no new classification.
				fmt.Printf("migration exceeded the ceiling (%s) — killed; rolling back\n", MigrateUpTimeout)
				d.terminateMigrateOrphan(ctx, progress)
			}
			// STATBUS-096 slice 3: best-effort OS-kill (OOM) EVIDENCE probe at the
			// now-single migrate-failure site. Structured docker inspect of the db
			// container (OOMKilled / ExitCode / StartedAt-vs-migrate-start) + a bounded
			// db-log tail scan for the postmaster crash constant. Conjunctive +
			// positive-match-only (the ENOSPC asymmetry): only an AFFIRMATIVE OS-kill
			// signature adds named data to the reason ("the database was killed by the
			// OS while migration <v> ran — it likely exceeds this box's memory"); no
			// evidence → empty suffix → today's reason unchanged. NEVER changes the
			// disposition — the probe is downstream of the failure, only enriches the
			// reason, and its own failure returns "" (leniency, never a wrong abort).
			oomEvidence := probeMigrateOOMEvidence(ctx, projDir, displayName, migrateStart)
			// STATBUS-046 slice 2 (Q5): read the `sb migrate up` exit-code contract
			// (migrate/exit_codes.go) STRUCTURALLY — 20 = deterministic SQL (B),
			// 22 = resource/SQLSTATE-class-53 (C) → PARK on FIRST with a class-real
			// reason (the %v stderr tail is DATA in the reason, never the classifier).
			// A conn-blip / timeout / any other exit → classUnknown → the existing
			// budget-bounded forward-retry. Inert until the producer emits 20/22.
			if cls := classifyStepFailure(StepMigrateUp, err); cls.parksOnFirst() {
				reason := fmt.Sprintf("migration failed deterministically at %s — fix the migration, then re-trigger the upgrade: %v", displayName, err)
				if cls == classResource {
					reason = fmt.Sprintf("disk full during migration at %s (SQLSTATE class 53) — free disk space, then re-trigger the upgrade: %v", displayName, err)
				}
				return d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, reason+oomEvidence, progress)
			}
			return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, fmt.Sprintf("%s: ./sb migrate up: %v", ErrMigrationFailed, err)+oomEvidence, progress)
		}
		progress.Write("Applying database migrations: %d pending ... ok", pendingMigrations)
	}

	// STATBUS-071 AT-TARGET resume-crash producer (KindKill). Fires HERE — the
	// migrate step returned success (db.migration at on-disk max) and the binary is
	// the target, so a crash-recovery reads ObservedAlreadyAtNew — yet the forward
	// tail (start services → health → maintenance-off → archive → state=completed)
	// is ALL still to redo. Earliest at-target instant + maximal remaining forward
	// work: the resume must genuinely re-run everything below to reach completed.
	// No-op in production (env unset). DUAL-USE (see inject.go — do not remove after
	// the first consumer): (1) the transient-db-backoff arc's RESOLVES arm needs an
	// at-target crashed flag so the post-backoff re-read resolves FORWARD; (2) the
	// flagless-selfheal real-path successor needs exactly this at-target killed state.
	inject.KillHere("killed-by-system-after-migrations-before-completion")

	// Step 11: Start application services — the FULL version-tracked set,
	// INCLUDING the proxy. (A drifted older note here claimed "proxy already
	// running from step 2"; that was only true on the fresh executeUpgrade
	// path, never on a resume — exactly the Bug-2 gap that froze rune's
	// proxy on a stale tag for 18 days. step11RestartServices is the
	// authoritative list.)
	// --no-build for the same reason as step 9: the app/worker/rest images
	// must come from the registry, not a local build that may time out.
	//
	// The service list lives at step11RestartServices (package var below)
	// so the canary's `versionTrackedServices` (in containers.go) can
	// reference the exact same list. Drift between these two lists would
	// either wedge the canary (proxy-style "wait forever") or skip
	// verification (silent drift) — TestVersionTrackedAlignedWithUpgradePipeline
	// asserts the invariant.
	d.markStep(StepStartServices)
	// STATBUS-046 slice 2: PRIMARY class-C disk pre-check (structured statfs).
	if reason := d.diskPrecheckReason(StepStartServices); reason != "" {
		return d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, reason, progress)
	}
	composeArgs := append([]string{"compose", "up", "-d", "--no-build"}, step11RestartServices...)
	servicesStart := time.Now()
	if stderrTail, err := runCommandToLogCapture(projDir, 5*time.Minute, progress.File(), "docker-compose", progress.bump, "docker", composeArgs...); err != nil {
		// ENOSPC backstop: disk filled DURING start (past the pre-check) → C park.
		if classifyDockerFailure(err, stderrTail) == classResource {
			return d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath,
				fmt.Sprintf("disk full starting services at %s (no space left on device) — free disk space, then re-trigger the upgrade", displayName), progress)
		}
		reason := fmt.Sprintf(
			"%s: docker compose up -d %s: %v\n\n"+
				"One or more application images for %s are not available locally or in the registry. "+
				"CI builds images on every master push (images.yaml). "+
				"Wait for that workflow to finish, then retry the upgrade. Check status: "+
				"gh run list --workflow=images.yaml",
			ErrDockerUpFailed, strings.Join(step11RestartServices, " "), err, displayName)
		return d.newSbUpgradingFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath, reason, progress)
	}
	progress.Write("Starting services (app, worker, proxy, rest) ... ok (%s)", formatProgressDuration(time.Since(servicesStart), false))

	// C8 injection site. Containers have been started (docker compose
	// up -d returned ok — meaning create+start was initiated, NOT that
	// health checks have passed) but step 12's health check has not
	// yet confirmed them serving. Kill here leaves the system with:
	// new binary, migrations applied, containers in an indeterminate
	// state (some up, some not, health checks not yet validated).
	// The next install must complete the restart by re-running
	// step 11 + step 12 — the recoverFromFlag PostSwap path resumes
	// applyNewSbUpgrading from the top. No-op in production.
	inject.KillHere("killed-by-system-during-container-restart")

	// Step 12: Verify health. STATBUS-046 slice 3 (doc-021 3.7): healthCheck IS
	// the class-A warmup allowance — it first waits for PostgREST /ready
	// (waitForRestReady, 5-min warmup) THEN retries the functional RPC in place.
	// An error here means the warmup allowance is EXHAUSTED: the running version
	// still can't serve past warmup = a persistent B failure → PARK on first with
	// a named reason, not another death-budget attempt (retrying a version that
	// can't serve won't fix it). A transient DB/REST blip within warmup is
	// absorbed in-place by the retries above and never reaches here.
	d.markStep(StepHealthCheck)
	if err := d.healthCheck(progress, 5, 5*time.Second); err != nil {
		return d.parkForDeterministicFailure(ctx, id, displayName, restoreTargetSHA, commitSHA, backupPath,
			fmt.Sprintf("%s: the application cannot serve at %s past warmup — %v; fix the cause, then re-trigger the upgrade", ErrHealthcheckRESTDown, displayName, err), progress)
	}

	// Done — deactivate maintenance. The terminal state='completed' UPDATE +
	// removeUpgradeFlag run below BEFORE any post-completion cleanup, so a kill
	// in the post-completion window leaves a COMPLETED upgrade the next start
	// no-ops past (recovery-arc-flaw-timeoutstartsec.md §4a — the ordering
	// invariant; its original motivating slow tail, a post-completion forensic
	// tar, was removed in STATBUS-112).
	finishing := newSuccessfulUpgradeFinishingNarrative(displayName, maintenanceFlagHostPath(), d.flagPath())
	finishingClean := true
	var finishingErr error
	progress.Write("%s", finishing.heading())
	d.markStep(StepMaintenanceOff)
	if err := d.setMaintenance(false, ""); err != nil {
		finishingClean = false
		finishingErr = errors.Join(finishingErr, fmt.Errorf("lift maintenance mode: %w", err))
		progress.Write("  Lifting maintenance mode ... failed: %v", err)
	} else {
		writeProgressLines(progress, finishing.maintenanceLines()...)
	}

	// STATBUS-071 P5 — the CONVERGED-but-bookkeeping-unlanded resume-crash producer. Fires
	// AFTER healthCheck success + setMaintenance(false) but BEFORE the completed terminalUpdate
	// below: the box is fully converged (services healthy at target, maintenance off) and only
	// the ledger's 'completed' write is unlanded — the live rune class (the Apr-24 SDNOTIFY
	// collision) minus its now-extinct route. A KindKill here (os.Exit(137), no defers run)
	// leaves a service-held flag + an in_progress row on a genuinely-serving box, so the next
	// boot's resumeNewSb self-heal (containers-at-target + no-pending + health) completes it for
	// real — the [completed-self-heal] path. No-op in production (STATBUS_INJECT_AT unset).
	inject.KillHere("killed-after-health-before-completed-write")

	// selfUpdate is intentionally NOT invoked here: Option C moved the
	// binary-swap handoff earlier (right after replaceBinaryOnDisk in
	// executeUpgrade) so the current process is already running the target
	// binary. A second exit-42 here would be a no-op systemd restart
	// costing ~30s of extra downtime for nothing.

	// Mark complete. Task rune-stuck fix A (Apr 24): the terminal UPDATE
	// MUST happen BEFORE runInstallFixup, not after. Install-fixup runs
	// `./sb install --post-upgrade-fixup` which triggers docker
	// compose up and can restart the DB container mid-run, RST'ing the
	// pgx TCP socket. Running fixup first would leave the parent's
	// queryConn dead when it tries to issue the state='completed'
	// UPDATE, producing "context already done: context canceled" and
	// firing NORMAL_COMPLETED_TRANSITION_PERSISTED on the first (and
	// only, because isConnError didn't match ctx-cancel pre-rc.59)
	// attempt. The "Upgrade complete!" log must also wait until the
	// UPDATE actually lands — emitting it earlier was a lie in the
	// operator-facing log. Fixup moves to AFTER the UPDATE + flag
	// removal + supersede/retention; its failure is still non-fatal.
	var normalJSON string
	// error = NULL: a prior forward-retry pass may have stamped a non-terminal
	// error via recordInProgressFailure (STATBUS-039); chk_upgrade_state_attributes
	// forbids carrying it onto completed. Completing resolves it.
	// STATBUS-081: log_relative_file_path = COALESCE(...) — chk_upgrade_state_attributes
	// requires it NOT NULL on completed. Real upgrades are stamped at claim time
	// (LOG_POINTER_STAMPED invariant) so $2 is a no-op fallback for legacy NULL rows only.
	// STATBUS-046: Phase 4.2 — record the dying step so a crash during the terminal
	// write reports StepComplete (not the prior maintenance-off) for same-step-twice.
	d.markStep(StepComplete)
	completedSQL := "UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready', error = NULL, log_relative_file_path = COALESCE(log_relative_file_path, $2) WHERE id = $1" + upgradeRowReturning
	// STATBUS-154: the completed terminal write goes through the teardown-immune
	// terminalUpdate (fresh daemon-tagged conn + context.Background + bounded
	// retry — this generalizes the former inline C6 047-H reconnect save). The
	// bespoke terminal escalation (DB-invariant naming + diagnostic bundle) stays
	// here.
	var cerr error
	normalJSON, cerr = d.terminalUpdate(completedSQL, id, progress.RelPath())
	if cerr != nil {
		// C7: terminal UPDATE errored. If it's a DB-enforced invariant (e.g.
		// chk_upgrade_state_attributes log-pointer arm), prefer the specific name
		// so the support bundle surfaces the precise cause.
		if dbName := d.markPgInvariantTerminal(cerr, "service.go:applyNewSbUpgrading:completed-terminal"); dbName != "" {
			d.writeDiagnosticBundle(ctx, id, progress)
			return fmt.Errorf("%s: %w", dbName, cerr)
		}
		fmt.Fprintf(os.Stderr,
			"INVARIANT NORMAL_COMPLETED_TRANSITION_PERSISTED violated: terminal state transition to completed errored for id=%d: %v (service.go:%d, pid=%d)\n",
			id, cerr, thisLine(), os.Getpid())
		d.markTerminal("NORMAL_COMPLETED_TRANSITION_PERSISTED",
			fmt.Sprintf("id=%d; final err=%v", id, cerr))
		d.writeDiagnosticBundle(ctx, id, progress)
		return fmt.Errorf("NORMAL_COMPLETED_TRANSITION_PERSISTED: %w", cerr)
	}
	progress.Write("%s", finishing.recordedLine())
	log.Println("state=completed")
	logUpgradeRow(LabelCompletedNormal, normalJSON)
	d.deleteRollbackBinaryOnCompletion() // STATBUS-197 C3: swap resolved → ./sb.old must not linger
	// Notify the frontend the upgrade state changed — fired AFTER the terminal
	// state='completed' UPDATE above, NOT before it (its prior position fired
	// while the row was still in_progress, so a client returning from the
	// maintenance page and refetching saw a stale 'in_progress' → the "lagging"
	// bug, STATBUS-090). The completed UPDATE's DB trigger also fires the real
	// completion NOTIFY; this explicit belt guarantees delivery if the app's
	// LISTEN wasn't yet established when the trigger fired. Mirrors the recovery
	// self-heal path's NOTIFY-after-completed ordering (resumeNewSb).
	// Best-effort; this is an explicit BELT on top of the completed UPDATE's
	// own DB trigger NOTIFY (see comment above) — if this one fails, the
	// trigger-fired NOTIFY still delivers in the common case.
	_ = d.execObserved(ctx, "notify frontend of upgrade change", `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)
	// STATBUS-110: clear the read-only upgrade window — health passed, no rollback
	// pending, box reopening. Placed HERE (right after the completed UPDATE landed)
	// rather than at the setMaintenance(false) above because queryConn is only
	// GUARANTEED live once the completed UPDATE's reconnect-on-stale loop has
	// succeeded (the NOTIFY just above proves it); clearing at the earlier
	// setMaintenance(false) could silently miss on a stale conn and leak read-only.
	// STATBUS-163: the terminal OFF flip rides the teardown-immune terminalExec
	// (a FRESH conn, not the completing pass's dying queryConn — the 'conn closed'
	// race that left the window stuck ON with state='completed', wedging every
	// fresh 25006 writer, caught by the STATBUS-110 AC#2 rider). The 'completed'
	// row already landed above (senior truth); a failed flip may NOT
	// complete-with-warning — a completed box that rejects every write is a broken
	// box masquerading as healthy — so it ESCALATES LOUDLY (STATBUS-154 exit-
	// invariant class), never the quiet Warning. The boot backstop clears the
	// residue on the next start; its firing indicts this flip.
	readOnlyStatement, readOnlyErr := d.liftReadOnlyWindow("upgrade completion")
	if readOnlyErr != nil {
		finishingClean = false
		finishingErr = errors.Join(finishingErr, fmt.Errorf("unblock SQL writes: %w", readOnlyErr))
		fmt.Fprintf(os.Stderr,
			"INVARIANT COMPLETION_READ_ONLY_WINDOW_LIFTED violated: the read-only window did not lift at completion after %d attempts (err=%v) — the database default is still read-only, so every fresh non-exempt session fails with 25006 (read_only_sql_transaction). Remedy: run `./sb install` to clear it (or the daemon's boot backstop clears it on the next start). (service.go:%d, pid=%d)\n",
			terminalWriteMaxAttempts, readOnlyErr, thisLine(), os.Getpid())
		d.markTerminal("COMPLETION_READ_ONLY_WINDOW_LIFTED",
			fmt.Sprintf("window OFF flip failed at completion after retries: %v; DB default still read-only; ./sb install clears it", readOnlyErr))
		progress.Write("  Unblocking SQL writes ... failed: %v", readOnlyErr)
	} else {
		writeProgressLines(progress, finishing.readOnlyLines(readOnlyStatement)...)
	}
	if err := d.removeUpgradeFlag(); err != nil {
		finishingClean = false
		finishingErr = errors.Join(finishingErr, fmt.Errorf("release upgrade lock: %w", err))
		progress.Write("  Releasing upgrade lock ... failed: %v", err)
	} else {
		writeProgressLines(progress, finishing.lockLines()...)
	}

	// The row is now truly `completed`; lock release was attempted immediately
	// afterward. Only the finishingClean branch below may claim the whole process
	// completed. Everything from here on (pruning, retention, fixup) is
	// post-database-completion cleanup: a kill in this window leaves a COMPLETED
	// row that the next start no-ops past.
	// Layer 3 of the rollback-on-SIGKILL hole plug: now that the upgrade
	// has reached terminal state='completed', the pre-upgrade backup is no
	// longer needed for rollback. pruneBackups (defined in exec.go) trims
	// finalised pre-upgrade-* directories to the `keep` most-recent. Until
	// this call site existed, pruneBackups was only exercised by tests —
	// orphan backups accumulated forever (rune still has one from April 21).
	// keep=3 retains the last few for forensic / disaster-recovery purposes.
	d.pruneBackups(ctx, 3)
	// Pre-upgrade branch is no longer needed — successful completion
	// means we're committed to the new version. Best-effort delete; if
	// the branch is missing (best-effort create at the start failed),
	// the -D returns non-zero and we just move on.
	_ = runCommand(d.projDir, "git", "branch", "-D", "pre-upgrade")
	d.supersedeOlderReleases(ctx, commitSHA)
	d.supersedeCompletedPrereleases(ctx, commitSHA)
	// Retention pass scoped to the just-installed row: rules A/B/C fire
	// (same-family prereleases, stale commits) so admins aren't stuck
	// with obsolete dogfood entries after a release lands. Must run AFTER
	// supersedeOlderReleases — rule D's ranking depends on the older
	// releases' new 'superseded' state.
	d.runRetentionPurge(ctx, "all", &id)

	// Now the row is truly `completed`; run the post-success fixup and emit the
	// canonical completion line only if every finishing boundary also succeeded.
	// install fixup. See the "Mark complete" comment above for the
	// ordering rationale. Fixup can restart docker services (including
	// db) — that's fine here because we're past the terminal UPDATE;
	// anything that breaks after this point is a fixup-side concern the
	// operator can re-run idempotently.
	// Run idempotent install to apply any new infrastructure (systemd service,
	// directories, config fixes). Install steps skip what's already done.
	// This exercises the install path on every upgrade, catching install bugs early.
	//
	// The flag file has already been removed above (the completed UPDATE +
	// removeUpgradeFlag ran first, by rune-stuck-fix A). The fixup child's
	// --post-upgrade-fixup + STATBUS_POST_UPGRADE_FIXUP=1 signals are
	// LOAD-BEARING, not just audit: besides bypassing the mutex (don't
	// re-acquire, don't expect a flag) they make the child skip state detection,
	// install-log creation, and row-authoring — without which it would probe the
	// DB mid-fixup and author a SECOND completed row for the running version
	// (pass-1's post-recovery continuation already records it). acquireOrBypass
	// recognizes the env signature and stays quiet: the absent flag is the
	// expected steady state here, not an A17 violation.
	fixupStart := time.Now()
	if err := runInstallFixup(projDir); err != nil {
		finishingClean = false
		finishingErr = errors.Join(finishingErr, fmt.Errorf("apply configuration and service updates: %w", err))
		progress.Write("  Applying configuration and service updates ... failed (the database upgrade succeeded, but process finishing did not): %v", err)
		// Non-fatal to the already-committed database upgrade. It is still a
		// process-finishing failure, so the canonical complete line, success callback,
		// and nil return remain reserved for a fully clean finishing block below.
	} else {
		progress.Write("%s", finishing.fixupLine(time.Since(fixupStart)))
	}
	if finishingClean {
		d.runUpgradeCallback(displayName)
		progress.Write("%s", finishing.completeLine())
		return nil
	}
	progress.Write("Upgrade to %s was recorded as successful, but finishing did not complete; see the failed step(s) above.", displayName)
	return fmt.Errorf("upgrade to %s was recorded as successful, but finishing did not complete: %w", displayName, finishingErr)
}

// resumeNewSb re-enters the upgrade pipeline in the new binary after a
// mid-flow exit-42 restart. Called from recoverFromFlag when the flag's
// Phase is PhaseNewSbSwapped.
//
// Recovers state from: flag (CommitSHA, CommitTags, BackupPath, Recreate,
// InvokedBy, Trigger, ID) and DB row (log_relative_file_path). The rollback
// restore target is the pinned `pre-upgrade` branch (STATBUS-077 single source;
// the from_commit_sha column was removed). Then re-acquires the flock (prior
// process died, kernel released it), reopens the progress log in append mode,
// and calls applyNewSbUpgrading.
//
// Control returns to Run() after applyNewSbUpgrading completes. If applyNewSbUpgrading
// fails, rollback() has already run inside it.
// upgradeParkedReason reports whether upgrade `id` is PARKED (STATBUS-046):
// recovery_parked_at IS NOT NULL. A parked row is SKIPPED by every automatic
// resume (the unit stays alive-idle) until a deliberate operator trigger
// un-parks it (RunSchedule / install re-claim resets the marker).
// INSTALL_CMD is the operator's one tool, named once so every message that
// tells them what to run says the same thing.
const INSTALL_CMD = "./sb install"

// preSwapRecoveryReason selects the cause written to the eventual terminal row.
// New flags carry the concrete failure. Legacy flags have no such field and keep
// the conservative unchanged-attempt fallback. The fallback is not used when an
// original error exists, which is the STATBUS-338 truthfulness boundary exposed
// by Norway rc.02.
func preSwapRecoveryReason(flag UpgradeFlag) string {
	if original := strings.TrimSpace(flag.OriginalError); original != "" {
		return original
	}
	return fmt.Sprintf(
		"%s: the upgrade was interrupted before it changed anything and was rolled back to the previous version; the database was not modified. (detail: before booting the new binary — the point of no return)",
		ErrInstallPreconditionFailed)
}

func retryableRollbackReason(reason string) bool {
	return strings.HasPrefix(strings.TrimSpace(reason), ErrGitFetchRetryable+":")
}

// The cleanup-only rollback state is the COLUMN public.upgrade.rollback_finish_pending_at
// (STATBUS-347, migration 20260903205636), never a prefix on `error`. The schema
// enforces its shape (chk_upgrade_rollback_finish_pending_requires_failed), the
// install ladder excludes it from restore replay by column, and every reader in
// this file selects on the column. `error` carries only the human cause.
//
// rollbackFinishPendingSQL is the ONE predicate for "restored but not finished",
// shared by the claim gate, the recovery interception, the finisher's candidate
// list, and the row lock, so no two readers can disagree about what pending is.
const rollbackFinishPendingSQL = "state = 'failed' AND rollback_finish_pending_at IS NOT NULL"

func rollbackFinalError(reason string) string {
	if reason == "" {
		reason = "Rollback completed (no reason captured — caller did not pass one)"
	}
	if retryableRollbackReason(reason) {
		return reason + " - rolled back to the previous version; the system is running normally on the old version. " +
			"The git failure is recorded (log retained) and is retryable. It is safe to schedule this same version again; no manual recovery is needed."
	}
	return reason + " — rolled back to the previous version; the system is running normally on the old version. " +
		"The failure is recorded (log retained); report it to support. This version will fail the same way — do NOT re-schedule it; run `./sb upgrade check` and try a LATER release when one is available. No manual intervention needed."
}

// isRollbackFinishPending reports whether the row for id is the cleanup-only
// ROLLBACK_FINISH_PENDING shape. It runs on the recovery classify path before
// phase routing, so the read is bounded by recoveryReadTimeout (STATBUS-190): a
// paused database must classify as an error quickly, never hang recovery.
func (d *Service) isRollbackFinishPending(ctx context.Context, id int) (bool, error) {
	if d.queryConn == nil {
		return false, fmt.Errorf("query connection is not available")
	}
	readCtx, cancel := context.WithTimeout(ctx, recoveryReadTimeout)
	defer cancel()
	var pending bool
	err := d.queryConn.QueryRow(readCtx,
		`SELECT EXISTS (SELECT 1 FROM public.upgrade WHERE id = $1 AND `+rollbackFinishPendingSQL+`)`, id).Scan(&pending)
	return pending, err
}

func readUpgradeFlagFromOpenFile(file *os.File) (UpgradeFlag, error) {
	if _, err := file.Seek(0, 0); err != nil {
		return UpgradeFlag{}, fmt.Errorf("seek upgrade flag: %w", err)
	}
	data, err := io.ReadAll(file)
	if err != nil {
		return UpgradeFlag{}, fmt.Errorf("read upgrade flag: %w", err)
	}
	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		return UpgradeFlag{}, fmt.Errorf("decode upgrade flag: %w", err)
	}
	return flag, nil
}

// clearRollbackFinishFlag removes only the marker belonging to this already-
// restored rollback. Identity is checked from the same open file descriptor
// while its flock is held, not by a read-before-lock path that could race a new
// upgrade replacing the marker. The row stays ROLLBACK_FINISH_PENDING until
// unlink succeeds, so neither the daemon nor ./sb install can mistake cleanup
// for another restore.
func (d *Service) clearRollbackFinishFlag(id int) error {
	path := d.flagPath()
	if d.flagLock != nil && d.flagLock.file != nil {
		flag, err := readUpgradeFlagFromOpenFile(d.flagLock.file)
		if err != nil {
			return err
		}
		if flag.ID != id {
			return fmt.Errorf("rollback finishing expected marker for upgrade %d, found upgrade %d; refusing to remove it", id, flag.ID)
		}
		holder := flag.Holder
		if holder == "" {
			holder = HolderService
		}
		if holder != HolderService {
			return fmt.Errorf("upgrade %d rollback finishing found a %q-held marker; refusing to remove it", id, holder)
		}
		return d.removeUpgradeFlag()
	}

	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer func() { _ = file.Close() }()
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return err
	}
	flag, err := readUpgradeFlagFromOpenFile(file)
	if err != nil {
		return err
	}
	if flag.ID != id {
		return nil
	}
	holder := flag.Holder
	if holder == "" {
		holder = HolderService
	}
	if holder != HolderService {
		return fmt.Errorf("upgrade %d rollback finishing found a %q-held marker; refusing to remove it", id, holder)
	}
	const consequence = "rollback finishing remains cleanup-only and will retry without restoring the database"
	removeErr := d.removePath(path)
	warnOnStaleFlagRemoveFailure(path, removeErr, consequence)
	if os.IsNotExist(removeErr) {
		return nil
	}
	return removeErr
}

// finalizePendingRollbacks repairs the only deliberate failed+backup_path
// exception to install's restore-reattemptable invariant. The restore already
// passed every health boundary; only stale-marker cleanup and/or the final DB
// transition remain after the live filesystem lock disappeared. Retrying those
// cleanup-only steps is safe at startup and on each heartbeat, and requires no
// restore or service action.
func (d *Service) finalizePendingRollbacks(ctx context.Context) {
	if d.queryConn == nil {
		return
	}
	rows, err := d.queryConn.Query(ctx,
		`SELECT id FROM public.upgrade WHERE `+rollbackFinishPendingSQL+` ORDER BY id`)
	if err != nil {
		log.Printf("finalizePendingRollbacks: query failed: %v", err)
		return
	}
	var pendingIDs []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			log.Printf("finalizePendingRollbacks: scan failed: %v", err)
			return
		}
		pendingIDs = append(pendingIDs, id)
	}
	rowsErr := rows.Err()
	rows.Close()
	if rowsErr != nil {
		log.Printf("finalizePendingRollbacks: rows failed: %v", rowsErr)
		return
	}

	for _, id := range pendingIDs {
		readOnlyStatement, readOnlyErr := d.liftReadOnlyWindow("rollback finishing recovery")
		if readOnlyErr != nil {
			log.Printf("finalizePendingRollbacks: upgrade %d SQL-write cleanup remains pending: %v", id, readOnlyErr)
			continue
		}
		log.Printf("finalizePendingRollbacks: upgrade %d SQL writes unblocked (%s)", id, readOnlyStatement)
		if maintenanceErr := d.setMaintenance(false, ""); maintenanceErr != nil {
			log.Printf("finalizePendingRollbacks: upgrade %d HTTP-maintenance cleanup remains pending: %v", id, maintenanceErr)
			continue
		}
		if _, finalizeErr := d.finalizePendingRollback(ctx, id, LabelRolledBackFinishRecovery); finalizeErr != nil {
			log.Printf("finalizePendingRollbacks: upgrade %d remains pending: %v", id, finalizeErr)
		}
	}
}

// finalizePendingRollback locks the still-pending database row before touching
// its marker, then removes the marker and changes the row to rolled_back in the
// same transaction. A second cleanup actor waits on the row lock and, after the
// first commits, observes no pending row and therefore cannot unlink a newer
// upgrade's marker through an old open descriptor.
func (d *Service) finalizePendingRollback(ctx context.Context, id int, label string) (bool, error) {
	tx, err := d.queryConn.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin rollback finishing transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var finishLockHeld bool
	if err := tx.QueryRow(ctx, "SELECT pg_try_advisory_xact_lock(hashtext('upgrade_daemon'))").Scan(&finishLockHeld); err != nil {
		return false, fmt.Errorf("acquire rollback finishing transaction lock: %w", err)
	}
	if !finishLockHeld {
		return false, fmt.Errorf("another upgrade actor owns the upgrade lock")
	}

	var errorText, commitSHA, commitVersion string
	err = tx.QueryRow(ctx,
		`SELECT COALESCE(error, ''), commit_sha, COALESCE(commit_version, '')
		   FROM public.upgrade
		  WHERE id = $1 AND `+rollbackFinishPendingSQL+`
		  FOR UPDATE`, id).Scan(&errorText, &commitSHA, &commitVersion)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("lock rollback finishing row: %w", err)
	}
	if cleanupErr := d.clearRollbackFinishFlag(id); cleanupErr != nil {
		return false, fmt.Errorf("remove stale rollback marker: %w", cleanupErr)
	}

	finalError := rollbackFinalError(errorText)
	// Clear the pending marker in the SAME statement that writes rolled_back:
	// the CHECK forbids pending on rolled_back, so a partial write is impossible,
	// and the RETURNING scan is the row-count check (ErrNoRows = the row moved
	// under the lock, which the FOR UPDATE above makes unreachable).
	var rowJSON string
	if err := tx.QueryRow(ctx,
		"UPDATE public.upgrade SET state = 'rolled_back', error = $2, rolled_back_at = now(), rollback_finish_pending_at = NULL WHERE id = $1 AND "+rollbackFinishPendingSQL+upgradeRowReturning,
		id, finalError).Scan(&rowJSON); err != nil {
		return false, fmt.Errorf("write final rolled_back row: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit final rolled_back row: %w", err)
	}

	logUpgradeRow(label, rowJSON)
	displayName := commitVersion
	if displayName == "" {
		displayName = renderDisplayName(CommitSHA(commitSHA), nil)
	}
	d.runCallback(displayName, map[string]string{"STATBUS_EVENT": "rolled_back", "STATBUS_ROLLED_BACK": "1"})
	log.Printf("Rollback to the previous version complete for upgrade %d (recovered interrupted final row transition).", id)
	return true, nil
}

// preSwapStoppedMessage renders STATBUS-240's operator-facing text, approved
// VERBATIM by the King. Do not reword any part of it without going back to him:
// the ordering is the design, not prose style.
//
// THE FIRST LINE IS THE REASSURANCE, NOT THE FAULT. An operator meeting this
// text is frightened before they are curious — something went wrong with an
// upgrade to their statistical register. The most valuable fact we hold is that
// their data is untouched, so it goes first, in the shortest sentence
// available.
//
// DELIBERATELY ABSENT: any guess at what went wrong. We do not know from this
// terminal alone, and a speculative cause would send the operator to
// investigate the wrong thing — the same defect as the old text, in a
// friendlier tone.
func preSwapStoppedMessage(attempts int) string {
	_ = attempts // the count is in the row; the operator-facing text stays plain
	return ErrUpgradeStoppedUnchanged + ": The upgrade stopped before it changed anything.\n\n" +
		"Your data was not modified and your installed version was not replaced. " +
		"This system is still running the version it was running before, and it is serving normally.\n\n" +
		"The upgrade was attempted twice and stopped at the same point both times, so it will not be tried again on its own.\n\n" +
		"To try again: run " + INSTALL_CMD + "\n\n" +
		"If it stops here again, the upgrade itself needs a fix. " +
		"Report this message together with the version you were upgrading to."
}

// parkStateUnknown answers the question every park-state consumer must ask
// before acting: does this error mean the row CANNOT be parked, or that we do
// not KNOW whether it is? (STATBUS-242 narrowing.)
//
// SQLSTATE 42703 (undefined_column) is not a fail-open at all — it is
// fail-INFORMED. A schema with no recovery_parked_at cannot hold a parked row,
// so proceeding is knowledge-based: we know the answer, and the answer is "not
// parked". EVERY OTHER ERROR is the ABSENCE of knowledge, and the code used to
// treat those opposites as the same fact.
//
// The asymmetry that settles what to do with the unknown case: refusing on a
// transient costs a human trigger on a box that is alive-idle and recoverable
// through the operator's normal remedy; PROCEEDING silently un-parks a row into
// the deterministic failure it stopped at — and, on the restore-bearing paths,
// restores over it.
func parkStateUnknown(err error) bool {
	if err == nil {
		return false
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "42703" {
		return false // the column does not exist => the row cannot be parked
	}
	return true
}

func (d *Service) upgradeParkedReason(ctx context.Context, id int) (parked bool, reason string, err error) {
	var parkedAt sql.NullTime
	var r sql.NullString
	if err = d.queryConn.QueryRow(ctx,
		"SELECT recovery_parked_at, recovery_parked_reason FROM public.upgrade WHERE id = $1", id).
		Scan(&parkedAt, &r); err != nil {
		return false, "", err
	}
	return parkedAt.Valid, r.String, nil
}

// UpgradeParkedReason is the exported counterpart of upgradeParkedReason, for
// callers outside this package (cmd/install_upgrade.go's runCrashRecovery,
// STATBUS-147: after a failed recovery, re-check whether the row re-parked so
// the daemon unit can be restarted anyway — a parked row is alive-idle-safe by
// construction, unlike a genuinely broken recovery).
func (d *Service) UpgradeParkedReason(ctx context.Context, id int) (parked bool, reason string, err error) {
	return d.upgradeParkedReason(ctx, id)
}

// incrementRecoveryAttempts bumps recovery_attempts by one at attempt START and
// returns the new value (STATBUS-046/D3: incremented before the forward pipeline
// re-runs so a dead process self-counts — no post-hoc bookkeeping). Counts
// PROCESS DEATHS only; class-A in-place waits never call this.
func (d *Service) incrementRecoveryAttempts(ctx context.Context, id int) (int, error) {
	var attempts int
	if err := d.queryConn.QueryRow(ctx,
		"UPDATE public.upgrade SET recovery_attempts = recovery_attempts + 1 WHERE id = $1 RETURNING recovery_attempts", id).
		Scan(&attempts); err != nil {
		return 0, err
	}
	return attempts, nil
}

// countRecoveryAttemptOnce increments recovery_attempts EXACTLY ONCE per process
// lifetime (STATBUS-044 comment #6 part 3). RecoveryBudgetGuard is the first
// counter — it runs at the start of the recovery pass, before the boot migrate —
// and whichever downstream regime runs afterwards (resumeNewSb /
// recoveryRollback) reuses that count via this helper instead of double-counting
// the same pass. When nothing counted yet this lifetime (e.g. a PreSwap→rollback
// pass, where the forward guard is a no-op), it increments and records the value
// so a later caller in the same pass still reuses it.
func (d *Service) countRecoveryAttemptOnce(ctx context.Context, id int) (int, error) {
	if d.recoveryPassCounted {
		return d.recoveryPassAttempts, nil
	}
	n, err := d.incrementRecoveryAttempts(ctx, id)
	if err != nil {
		return 0, err
	}
	d.recoveryPassCounted = true
	d.recoveryPassAttempts = n
	return n, nil
}

// RecoveryBudgetGuard is the crash-resume attempt budget's EARLY guard (STATBUS-044
// comment #6, King-approved). It runs at the START of a recovery pass on BOTH
// entrypoints (Service.Run and the ./sb install crash-recovery ladder), BEFORE the
// boot migrate — the window r12 proved is where resume-time migrations actually
// run and where a killer migration crash-looped UNCOUNTED (the rune class, in the
// one window heavy migrations execute). It:
//
//   - counts this pass at its start so a death IN the boot migrate self-counts,
//   - stamps StepBootMigrate on the flag so two consecutive boot-migrate deaths
//     trip same-step-twice → park early,
//   - PARKS (never rolls back) on a terminal verdict: park touches no data, and a
//     deliberate ./sb install un-parks into recoverFromFlag's careful observed-state
//     routing, which can still roll a genuinely-behind box back,
//   - SKIPS the boot migrate for a parked row so park delivers alive-idle for this
//     failure class (otherwise every restart re-runs the killer migration).
//
// Returns skipBootMigrate: true when the caller must NOT run the boot migrate (row
// parked, or just parked by this guard). The downstream recoverFromFlag →
// resumeNewSb parked-skip then keeps the unit alive-idle.
//
// FAIL-OPEN on any DB read/write error (the resumeNewSb :5792-5804 bootstrap
// pattern, verbatim): the 046-shipping upgrade's own recovery boot runs these
// queries against the pre-migrate schema (recovery_* columns absent → SQLSTATE
// 42703). Proceed so the boot migrate ships the columns and the feature bootstraps
// through its own deferral window; the downstream resumeNewSb increment/consult
// still bounds the pass. Fail-CLOSED here would loop uncounted on exactly that path.
func (d *Service) RecoveryBudgetGuard(ctx context.Context) (skipBootMigrate bool) {
	flag, ferr := ReadFlagFile(d.projDir)
	if ferr != nil || flag == nil || !flag.IsServiceNewSbRecovery() {
		// No service-held FORWARD recovery flag → not a resume pass (fresh boot,
		// install-held, or a PreSwap flag that rolls back). Guard is a no-op; the
		// PreSwap→rollback path keeps recoveryRollback's own increment.
		return false
	}

	// Own the flag: acquiring the flock is the authoritative "the prior holder is
	// dead and this process owns the recovery pass" signal — PID-reuse-immune, the
	// same gate Detect + recoveryRollback key on. A live holder means this is not
	// our pass to count; fall through and let the existing downstream recovery
	// bound it. Re-write the flag content verbatim (the flock ownership, not any
	// stored PID, is what matters — STATBUS-111); the step is stamped below, only
	// if we continue to the boot migrate.
	base := *flag
	lock, lerr := acquireFlock(d.projDir, base)
	if lerr != nil {
		log.Printf("RecoveryBudgetGuard: upgrade flock held by another actor (id=%d) — skipping early counting; downstream recovery still bounds this pass: %v", flag.ID, lerr)
		return false
	}
	d.flagLock = lock
	release := func() {
		d.flagLock = nil
		lock.Close()
	}

	// Parked rows skip the boot migrate → alive-idle for this failure class.
	parked, _, perr := d.upgradeParkedReason(ctx, flag.ID)
	if parkStateUnknown(perr) {
		// UNKNOWN => skip boot migrate, exactly as if parked. Boot-migrating a
		// row that may be parked defeats what the park is for: a park means
		// STOP and wait for a human, and this is the guard that honours it.
		//
		// WHY THIS SITE'S 42703 ARM IS LOAD-BEARING IN A WAY THE OTHERS' ARE
		// NOT, and why it must keep proceeding: boot migrate is what CREATES
		// recovery_parked_at on a schema that lacks it. Treating 42703 as
		// unknown-and-therefore-skip would skip the migration that creates the
		// column, leaving the column absent, the state unknowable, and the skip
		// permanent — a bootstrap deadlock. Fail-INFORMED is not a nicety here;
		// it is the only non-wedging answer.
		log.Printf("RecoveryBudgetGuard: park state UNKNOWN (id=%d): %v — skipping boot migrate and leaving the unit alive-idle rather than acting on an unverified row", flag.ID, perr)
		release()
		return true
	}
	if perr != nil {
		log.Printf("RecoveryBudgetGuard: park-state read failed (id=%d): %v — proceeding fail-open (boot migrate bootstraps the recovery_* columns if absent)", flag.ID, perr)
		release()
		return false
	}
	if parked {
		log.Printf("RecoveryBudgetGuard: upgrade %d is PARKED — skipping boot migrate (alive-idle); re-trigger the upgrade or run ./sb install to un-park", flag.ID)
		release()
		return true
	}

	// Count this pass at its START (before the boot migrate) so a death IN the boot
	// migrate self-counts (D3: process deaths only).
	attempts, aerr := d.incrementRecoveryAttempts(ctx, flag.ID)
	if aerr != nil {
		log.Printf("RecoveryBudgetGuard: could not increment recovery_attempts (id=%d): %v — proceeding fail-open with a single attempt", flag.ID, aerr)
		release()
		return false
	}
	d.recoveryPassCounted = true
	d.recoveryPassAttempts = attempts

	// STATBUS-134 — ROLLBACK-REGIME DEFER. When the just-crashed attempt died
	// mid-rollback (flag.Step == StepRollback), this pass belongs to the ROLLBACK
	// regime, whose terminal is rollbackResumeIsTerminal (TWO consecutive rollback
	// deaths → restore-broke), NOT the forward budget. We have counted the pass above
	// (the 1B shared, never-reset counter, reused downstream via
	// countRecoveryAttemptOnce); now DEFER the rest to recoveryRollback:
	//   - SKIP the resumeEscalation consult (1B pin: a budget exhaust must NEVER
	//     terminal a rollback — it would insta-restore-broke / mis-park it), and
	//   - SKIP the roll+stamp: leaving flag.Step == StepRollback (unstamped) is what
	//     lets recordRollbackCommit form the (rollback, rollback) pair across two
	//     consecutive mid-rollback deaths. Stamping StepBootMigrate here (the pre-134
	//     bug) overwrote that step every boot, so the pair could never form and the
	//     rollback crash-looped to the WRONG budget park instead of restore-broke.
	// Return false so the boot migrate still runs as before. ACCEPTED NUANCE
	// (documented, STATBUS-134): a death DURING the boot migrate on a rollback pass
	// reads as a rollback death (Step stays 'rollback', unstamped) — conservative,
	// fires restore-broke slightly early, honest for a pass whose purpose is rollback
	// recovery.
	if flag.Step == StepRollback {
		release()
		return false
	}

	// Consult the pure escalation core. canRollBack=FALSE unconditionally: a
	// terminal verdict at this early guard PARKS, never rolls back (comment #6).
	// deathStep/priorDeathStep are read from the flag AS IT WAS before this pass
	// (the just-crashed attempt's frozen step) — the in-memory `flag`, not the
	// PID-updated on-disk copy.
	if action, reason := resumeEscalation(attempts, flag.Step, flag.PriorDeathStep, false); action != recoveryContinue {
		freshlyParked, parkErr := d.parkUpgrade(ctx, flag.ID, reason,
			fmt.Sprintf("parked after %d crash-resume attempts: %s", attempts, reason))
		release()
		if parkErr != nil {
			log.Printf("RecoveryBudgetGuard: park write failed (id=%d): %v — skipping boot migrate anyway; the row stays in_progress and the next pass re-evaluates", flag.ID, parkErr)
			return true
		}
		log.Printf("RecoveryBudgetGuard: PARKED upgrade %d after %d attempt(s) — %s", flag.ID, attempts, reason)
		// Degraded siren — fires EXACTLY ONCE per park event (freshlyParked from the
		// parkUpgrade parked_at guard), matching resumeNewSb's contract.
		if freshlyParked {
			d.runCallback(flag.Label(), map[string]string{"STATBUS_EVENT": "parked", "STATBUS_PARKED": "1", "STATBUS_PARK_REASON": reason})
		}
		// STATBUS-204: route this budget park through the operable-box chokepoint. This guard
		// logs to the journal only (log.Printf), so open the upgrade's OWN progress log for the
		// park narrative (a park story belongs on the row's log, not the journal). The DB is up
		// here (EnsureDBUp ran pre-READY, before this guard), so loadLogRelPath resolves. The
		// flock was released above; parkServiceRecovery adopts-or-acquires its own (STATBUS-212).
		// The helper owns its watchdog cover, era-guards the state (post-delta budget parks
		// refuse naturally), and starts services only on permit.
		//
		// STATBUS-212 (closing 204's recorded nit): the restoration runs whether or not that log
		// opens. A nil *ProgressLog IS this codebase's discard writer — Write still narrates to
		// stdout/journal and skips the file, File() yields io.Discard, bump() is nil-safe — so a
		// missing or unopenable log now costs the NARRATIVE only. Gating the call on the log (the
		// pre-212 shape) left the box DARK for a bookkeeping failure, which inverts the North Star:
		// lose the story, never the box. Liveness does not depend on the log either — the helper's
		// own always-ping watchdog ticker covers the span (204), not progress.Write's heartbeat.
		plog := AppendProgressLog(d.projDir, d.loadLogRelPath(ctx, int64(flag.ID)))
		d.parkServiceRecovery(ctx, flag.ID, "", plog)
		plog.Close()
		return true
	}

	// Continue: stamp the boot-migrate step + roll the death history so two
	// consecutive deaths IN the boot migrate trip same-step-twice via
	// StepBootMigrate. Mirrors resumeNewSb's reacquire roll, hoisted to cover
	// the boot window. Best-effort (mutateHeldFlag needs the flock we still hold):
	// a failure only degrades same-step detection to the plain attempt budget.
	if err := d.mutateHeldFlag(func(f *UpgradeFlag) {
		f.PriorDeathStep = f.Step
		f.Step = StepBootMigrate
	}); err != nil {
		log.Printf("RecoveryBudgetGuard: could not stamp boot-migrate step (id=%d): %v — same-step-twice detection degraded; the attempt budget still bounds the loop", flag.ID, err)
	}
	// Release before the boot migrate: the downstream resumeNewSb /
	// recoveryRollback re-acquire the flock on their own fd (a second flock on the
	// held fd would EWOULDBLOCK). The stamped step is already persisted on disk.
	release()
	return false
}

// parkUpgrade writes the durable PARK marker (STATBUS-046): the row STAYS
// state='in_progress' (forward-only preserved; rollback stays reachable ONLY via
// a positively-Behind observed-state verdict, NEVER via exhaustion) and gains
// recovery_parked_at + the named reason. The `recovery_parked_at IS NULL` guard
// makes it idempotent — a racing writer can't double-park, so the degraded
// siren fires exactly once.
// parkUpgrade returns freshlyParked=true only when THIS call flipped the row
// into parked (RowsAffected>0 under the `recovery_parked_at IS NULL` guard), so
// the caller can fire the degraded siren EXACTLY ONCE per park event even when a
// read-blip re-enters an already-parked row (STATBUS-046).
// parkUpgrade parks the in_progress upgrade row via the teardown-immune
// terminalUpdate (STATBUS-154) — the park terminal is the pass's last word and
// must OUTLIVE the pass that decided to park (the "context already done: context
// canceled" race that left a parked process with a not-parked row, the health-
// park arc's re-park red). The guard parks only an in_progress, not-yet-parked
// row (idempotent).
//
// ctx is retained for signature parity but is NOT used for the write — the
// terminal write deliberately runs under context.Background (PIN i). Returns:
//   - (true,  nil)  FRESHLY parked by this call → caller fires the one-shot siren.
//   - (false, nil)  the row is ALREADY parked (a retry after our own committed
//     write, or a prior pass) — the park LANDED, no siren.
//   - (false, err)  NOT confirmed landed (connectivity exhausted, or the row is
//     not parkable) — caller MUST keep the row in_progress and let the next pass
//     re-evaluate (exit invariant AC#2); never exit as-parked on this.
func (d *Service) parkUpgrade(ctx context.Context, id int, reason, errNarrative string) (freshlyParked bool, err error) {
	// errNarrative rides the SAME immune terminalUpdate write as the park columns
	// (STATBUS-071 C-rollback finding): the old split write — park columns via this
	// teardown-immune terminalUpdate, but the error narrative via
	// recordInProgressFailure on the pass's OWN conn with a silent nil-conn no-op —
	// lost the story whenever a park landed on a dying recoverFromFlag pass (park
	// columns set, error empty). One write, one guarantee, atomic. EVERY caller MUST
	// pass a non-empty narrative — a park without a story is a design smell.
	_, uerr := d.terminalUpdate(
		"UPDATE public.upgrade SET recovery_parked_at = now(), recovery_parked_reason = $2, error = $3 WHERE id = $1 AND state = 'in_progress' AND recovery_parked_at IS NULL"+upgradeRowReturning,
		id, reason, errNarrative)
	if uerr == nil {
		return true, nil // guard matched + RETURNING scanned → freshly parked
	}
	if !errors.Is(uerr, pgx.ErrNoRows) {
		return false, uerr // connectivity exhausted or a real error — NOT landed
	}
	// Guard matched 0 rows: EITHER our own prior attempt committed then the conn
	// died (retry), OR a prior pass parked it, OR the row moved out of in_progress
	// and is not parkable. Verify on a fresh connection whether it IS parked.
	parked, state, verr := d.rowIsParked(id)
	if verr != nil {
		return false, fmt.Errorf("park write matched 0 rows and the parked-state verify failed for id=%d: %w", id, verr)
	}
	if parked {
		return false, nil // already parked → landed, but not freshly (no siren)
	}
	return false, fmt.Errorf("park write matched 0 rows and the row is not parked (id=%d, state=%s) — not parkable: a park marker requires state='in_progress', but the row is '%s'", id, state, state)
}

// rowIsParked reports whether the upgrade row's recovery_parked_at is set AND
// the row's current state, read on a FRESH short-lived connection (reuses
// terminalUpdate's teardown-immune primitive for the single-row read). Used by
// parkUpgrade to confirm the exit invariant when the guarded park UPDATE matched
// 0 rows — the state lets the not-parkable error name what it actually found
// (STATBUS-154). Encoded as "<state>|<parked>" so the single-column primitive
// carries both.
func (d *Service) rowIsParked(id int) (parked bool, state string, err error) {
	out, err := d.terminalUpdate(
		"SELECT state::text || '|' || (recovery_parked_at IS NOT NULL)::text FROM public.upgrade WHERE id = $1", id)
	if err != nil {
		return false, "", err
	}
	fields := strings.SplitN(strings.TrimSpace(out), "|", 2)
	if len(fields) != 2 {
		return false, "", fmt.Errorf("rowIsParked: malformed row read %q for id=%d", out, id)
	}
	return fields[1] == "true", fields[0], nil
}

// STATBUS-046 (architect pin 2): these are the standalone parked-only recovery
// reset used by ./sb install's UnparkByID. Schedule reset and un-park semantics
// now live atomically in public.upgrade_schedule (STATBUS-333), so Go must not
// duplicate them. For an in_progress row this guard reduces to
// `recovery_parked_at IS NOT NULL`: a live, non-parked upgrade keeps its count.
const (
	recoveryBudgetResetCols  = "recovery_attempts = 0, recovery_parked_at = NULL, recovery_parked_reason = NULL"
	recoveryBudgetResetGuard = "(state != 'in_progress' OR recovery_parked_at IS NOT NULL)"
)

// UnparkByID is the ./sb install un-park (trigger 2). Called ONLY on the
// deliberate install crash-recovery path (runCrashRecovery), NEVER on an
// automatic self-resume — which is why the marker persists across boots and
// resumeNewSb keeps skipping the parked row until a human acts. The
// FROM-subquery captures the PRE-reset reason so the caller can name it in the
// loud un-park line. Returns whether a parked row was un-parked + that reason.
func (d *Service) UnparkByID(ctx context.Context, id int) (unparked bool, oldReason string, err error) {
	q := fmt.Sprintf(`UPDATE public.upgrade AS u
	   SET %s
	  FROM (SELECT recovery_parked_reason AS old_reason FROM public.upgrade WHERE id = $1 LIMIT 1) prev
	 WHERE u.id = $1 AND %s
	 RETURNING prev.old_reason`, recoveryBudgetResetCols, recoveryBudgetResetGuard)
	var r sql.NullString
	if err = d.queryConn.QueryRow(ctx, q, id).Scan(&r); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, "", nil // guard didn't match → nothing reset (live / absent)
		}
		return false, "", err
	}
	return true, r.String, nil
}

func (d *Service) resumeNewSb(ctx context.Context, flag UpgradeFlag) error {
	var logRelPath sql.NullString
	err := d.queryConn.QueryRow(ctx,
		"SELECT log_relative_file_path FROM public.upgrade WHERE id = $1", flag.ID).
		Scan(&logRelPath)
	if err != nil {
		return fmt.Errorf("resumeNewSb: cannot load upgrade %d state (err=%v) — leaving flag for manual triage", flag.ID, err)
	}
	// STATBUS-077: restore target = the pinned pre-upgrade branch (single source).
	restoreTargetSHA := ""

	// Reopen the progress log. Append-mode so the narrative is continuous
	// across the restart. If the file is missing (manual tmp cleanup), fall
	// through to a fresh log so the resume path still reports progress.
	progress := AppendProgressLog(d.projDir, logRelPath.String)
	if progress == nil {
		progress = NewUpgradeLog(d.projDir, int64(flag.ID), flag.Label(), time.Now().UTC())
	}
	// Dedup: recoverFromFlag already emitted "Post-swap restart detected
	// for upgrade %d (%s) — resuming pipeline on new binary (pid=%d)"
	// before calling here. A second line in resumeNewSb was redundant.

	// Observed-state guard (task #49 Gap #6, rune-stuck fix). If the
	// running binary's compile-time commit SHA doesn't match the flag's
	// target commit SHA, the flag is stale: a subsequent install
	// advanced the server past this in_progress upgrade without
	// clearing the flag. Running applyNewSbUpgrading in this state would
	// "complete" the row against a different binary — a silent lie.
	// Treat it as a rollback instead: mark row rolled_back via
	// recoveryRollback (which also clears the flag), leave the running
	// binary's services alone (rollback's restore-from-previous-version
	// is a no-op when there's no destructive state to undo — the
	// binary/git are already at the NEWER version the operator
	// explicitly installed).
	//
	// Degraded mode: skip the check when binaryCommit is unset (local
	// go-run builds); matches the #49 pattern. The on-prem production
	// builds always have cmd.commit set via ldflags.
	//
	// Self-heal canary (Item E, plan-rc.66). Before the binary-skew
	// rollback fires, probe docker compose ps. If every production
	// container already runs at the flag's target — db/app/worker/proxy
	// tagged with CommitSHA[:8] OR DisplayName (rc.55-era scheme), rest
	// just running — the upgrade actually converged; only the bookkeeping
	// UPDATE didn't land (rune Apr 24 case: SDNOTIFY collision aborted
	// the parent before the row UPDATE). Mark the row completed and
	// return so the next state probe selects StateNothingScheduled
	// instead of triggering a rollback of a successful deploy.
	if ok, mismatched := d.containersAtFlagTarget(ctx, flag); ok {
		// STATBUS-067 (Q1): containers-healthy is necessary but NOT sufficient
		// for convergence. A post-swap kill mid-migrate (after-commit-before-
		// recorded) leaves containers up at target but a migration committed-
		// but-unrecorded → migrate.HasPending == true. Self-healing to
		// 'completed' here would short-circuit the snapshot-restore rollback
		// that boot-migrate-up's STATBUS-017 deferral (service.go:1675-1697)
		// routes here for, silently certifying a half-migrated DB. Only
		// self-heal when migrations are genuinely complete; otherwise fall
		// through to the continuation (re-acquire flock → applyNewSbUpgrading →
		// migrate up re-hits the unrecorded migration → newSbUpgradingFailure →
		// rollback).
		//
		// STATBUS-145: this HasPending gate is now MORE load-bearing — since boot
		// migrates only to the floor, the whole upgrade DELTA is pending here on a
		// resume, so HasPending==true correctly withholds self-heal until
		// applyNewSbUpgrading applies the delta (or rolls back). It never short-circuits a
		// delta-pending resume.
		// STATBUS-193 PRIMARY (loud): a PARKED row must NEVER self-heal here. Parked rows
		// are skipped by every automatic resume (the 135 parked-skip genre); this self-heal
		// was the lone exception — its UPDATE guarded state='in_progress' only, and a parked
		// row IS in_progress (recovery_parked_at set). Since STATBUS-192 the reach is real: a
		// 192 health-fail park leaves containers UP at target, so if the cause clears by this
		// boot all three gates below pass and the parked row would quietly complete — erasing
		// the siren an operator was paged to investigate (the no-standing-self-heal doctrine).
		// Read park state FIRST (same 42703 fail-open precedent as completeInProgressUpgrade;
		// recovery_parked_at's migration 20260703210000 ships ≤ DaemonSchemaFloor 20260712024457,
		// so by construction the column exists here — the fail-open is belt-and-suspenders). If
		// parked, skip self-heal and fall through to the continuation, whose STATBUS-046
		// budget-section parked-skip returns the unit to alive-idle with the flag kept. A parked
		// row resolves ONLY by a fix-release re-trigger (STATBUS-159 displacement) or ./sb install.
		// STATBUS-242 NARROWING — THIS SITE IS DELIBERATELY LEFT FAIL-OPEN, and
		// the reason is checked rather than assumed. Unlike the four other
		// park-state consumers, nothing downstream of here restores: the only
		// write this branch guards is the self-heal UPDATE below, which carries
		// its own SQL belt guard `AND recovery_parked_at IS NULL` — verified
		// present, not inferred from this comment. So a parked row cannot be
		// self-healed even when this read fails, and refusing here would cost a
		// legitimate self-heal for no safety gain. If that WHERE clause ever
		// loses its guard, this site joins the other four.
		parked, parkReason, pkErr := d.upgradeParkedReason(ctx, flag.ID)
		if pkErr != nil {
			log.Printf("resumeNewSb: park-state read failed for upgrade %d: %v — proceeding fail-open; the belt guard (AND recovery_parked_at IS NULL) on the self-heal UPDATE still protects a parked row", flag.ID, pkErr)
		}
		pending, perr := migrate.HasPending(d.projDir)
		if parked {
			log.Printf("resumeNewSb: containers healthy at target but row %d is PARKED (%s) — NOT self-healing; a parked row resolves only by a fix-release re-trigger or ./sb install un-park (STATBUS-193)", flag.ID, parkReason)
		} else if perr != nil || pending {
			log.Printf("resumeNewSb: containers healthy at %s but migrations pending/unknown (pending=%v err=%v) — NOT self-healing; deferring to rollback (STATBUS-067)",
				flag.Label(), pending, perr)
		} else if hcErr := d.healthCheck(progress, 5, 5*time.Second); hcErr != nil {
			// STATBUS-104: containers-already-at-new + no-pending is necessary but NOT
			// sufficient — run the SAME bounded probe the normal applyNewSbUpgrading path
			// uses (exec.go:4809) before certifying 'completed'. On FAIL, do NOT
			// self-heal: fall through to the continuation (re-acquire flock →
			// applyNewSbUpgrading → its own healthCheck → completed OR rollback), so a
			// self-heal can never certify an unhealthy box as completed.
			log.Printf("resumeNewSb: containers at target but healthCheck failed (%v) — NOT self-healing; deferring to applyNewSbUpgrading re-verify", hcErr)
		} else {
			log.Printf("resumeNewSb: containers healthy at %s (sha %s), no pending migrations — self-healing row %d to completed",
				flag.Label(), ShortForDisplay(flag.CommitSHA), flag.ID)
			var selfHealJSON string
			// error = NULL: clears any non-terminal error stamped by a prior
			// forward-retry pass (recordInProgressFailure, STATBUS-039) —
			// chk_upgrade_state_attributes forbids it on completed, and pre-039
			// this exact UPDATE could fail on rows carrying an error (the
			// "falling through to continuation" branch below).
			// STATBUS-067 (Q2): log_relative_file_path = COALESCE(...) — the
			// completed branch of chk_upgrade_state_attributes requires it
			// NOT NULL; a row that reached here with a NULL path
			// (fabricated/legacy) would otherwise raise 23514. progress.RelPath()
			// is the live log this function reopened/created above.
			// STATBUS-154: teardown-immune self-heal completed write (fresh
			// daemon-tagged conn + context.Background + retry). ErrNoRows here =
			// the guarded row is already terminal OR PARKED (STATBUS-193 belt:
			// `AND recovery_parked_at IS NULL`, the same guard bytes parkUpgrade
			// uses — covers the TOCTOU window and the primary read's fail-open) →
			// fall through to continuation (handled below), exactly as before.
			selfHealJSON, err := d.terminalUpdate(
				"UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready', error = NULL, log_relative_file_path = COALESCE(log_relative_file_path, $2) WHERE id = $1 AND state = 'in_progress' AND recovery_parked_at IS NULL"+upgradeRowReturning,
				flag.ID, progress.RelPath())
			if err == nil {
				logUpgradeRow(LabelCompletedSelfHeal, selfHealJSON)
				d.deleteRollbackBinaryOnCompletion() // STATBUS-197 C3: swap resolved → ./sb.old must not linger
				finishingClean := true
				var finishingErr error
				progress.Write("Finishing recovered upgrade:")
				progress.Write("  Recording the successful upgrade in the database ... ok")
				// Best-effort NOTIFY belt, same shape as the normal-completion
				// path above.
				_ = d.execObserved(ctx, "notify frontend of upgrade change", `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)
				// STATBUS-071 P5: lift the read-only window. This self-heal is the
				// THIRD completed writer (alongside the applyNewSbUpgrading completion
				// site and the flagless completeInProgressUpgrade belt), and the crash
				// it recovers fired at the CONVERGED-but-unlanded instant: the window
				// engaged at step 2 (:5305) is still ON, so a self-heal that writes
				// 'completed' without lifting it certifies a box that rejects every
				// fresh write with 25006 — "a broken box masquerading as healthy" — and
				// would routinely trip the STATBUS-163 boot backstop on the next start.
				// The completed row already landed above (senior truth); mirror the two
				// completion sites: the teardown-immune terminalExec (a FRESH conn, not
				// the completing pass's queryConn) flips it, and a failed flip ESCALATES
				// LOUDLY via the named invariant (never a Warning — a completed box that
				// rejects writes is not healthy). This runs ONLY on the self-heal-success
				// path; the err != nil fall-through below re-enters applyNewSbUpgrading,
				// whose own completion site lifts the window there. The boot backstop
				// clears the residue on the next start; its firing indicts this flip.
				readOnlyStatement, werr := d.liftReadOnlyWindow("post-swap resume completion")
				if werr != nil {
					finishingClean = false
					finishingErr = errors.Join(finishingErr, fmt.Errorf("unblock SQL writes: %w", werr))
					fmt.Fprintf(os.Stderr,
						"INVARIANT COMPLETION_READ_ONLY_WINDOW_LIFTED violated: the read-only window did not lift at post-swap self-heal completion after %d attempts (err=%v) — the database default is still read-only, so every fresh non-exempt session fails with 25006 (read_only_sql_transaction). Remedy: run `./sb install` to clear it (or the daemon's boot backstop clears it on the next start). (service.go:%d, pid=%d)\n",
						terminalWriteMaxAttempts, werr, thisLine(), os.Getpid())
					d.markTerminal("COMPLETION_READ_ONLY_WINDOW_LIFTED",
						fmt.Sprintf("window OFF flip failed at post-swap self-heal completion after retries: %v; DB default still read-only; ./sb install clears it", werr))
					progress.Write("  Unblocking SQL writes ... failed: %v", werr)
				} else {
					progress.Write("  Unblocking SQL writes ... ok")
					progress.Write("    ran: %s", readOnlyStatement)
				}
				// STATBUS-187 AC#3 (architect ruling, ticket comment #7): same
				// uniform stale-flag-class treatment as removeUpgradeFlag/
				// ReleaseInstallFlag above — see warnOnStaleFlagRemoveFailure.
				// This site's consequence: the row is now genuinely
				// 'completed', so a stale flag would make the next boot
				// misread a HEALTHY upgrade as crashed/in-progress.
				if removeErr := d.removeUpgradeFlag(); removeErr != nil {
					finishingClean = false
					finishingErr = errors.Join(finishingErr, fmt.Errorf("release upgrade lock: %w", removeErr))
					progress.Write("  Releasing upgrade lock ... failed: %v", removeErr)
				} else {
					progress.Write("  Releasing upgrade lock ... ok")
					progress.Write("    removed: %s", homeRelativePath(d.flagPath()))
				}
				d.supersedeOlderReleases(ctx, flag.CommitSHA)
				d.supersedeCompletedPrereleases(ctx, flag.CommitSHA)
				if finishingClean {
					progress.Write("Upgrade to %s complete.", flag.Label())
				} else {
					progress.Write("Upgrade to %s was recorded as successful, but recovered-upgrade finishing did not complete; see the failed step(s) above.", flag.Label())
				}
				progress.Close()
				if finishingErr != nil {
					return fmt.Errorf("post-swap self-heal recorded upgrade %s as successful but finishing failed: %w", flag.Label(), finishingErr)
				}
				return nil
			}
			// UPDATE didn't land (ErrNoRows: row already terminal; or
			// chk_upgrade_state_attributes violation: row carries an `error`
			// the constraint forbids on completed). Fall through to the
			// continuation path — re-acquire flock and resume applyNewSbUpgrading
			// from where the prior process died. The continuation handles
			// its own terminal-row idempotency.
			log.Printf("resumeNewSb: self-heal UPDATE skipped for row %d (err=%v) — falling through to continuation",
				flag.ID, err)
		}
	} else {
		// Containers don't match flag's target. The discriminator is
		// the running binary's commit relative to flag.CommitSHA:
		//
		// (a) Normal mid-pipeline state. Binary was just swapped on
		//     disk by replaceBinaryOnDisk; old containers were stopped
		//     before swap; new containers haven't been started yet
		//     (that's literally applyNewSbUpgrading's job below). The running
		//     process IS the freshly-restarted post-swap binary, so
		//     d.binaryCommit == flag.CommitSHA exactly. Continue.
		//
		// (b) Operator-driven recovery roll-forward. The operator
		//     deployed a binary newer than the stuck flag's target to
		//     fix this exact wedge. d.binaryCommit is a DESCENDANT of
		//     flag.CommitSHA — the new binary subsumes everything the
		//     flag's target could do (its column-name expectations,
		//     its compose template, its post-swap steps). Continuing
		//     is safe; the new binary's applyNewSbUpgrading brings the
		//     world to a state at LEAST as new as the flag implies.
		//
		// (c) Genuine category-3 divergence (rc.67 trifecta). The
		//     running binary is NOT at flag.CommitSHA AND NOT a
		//     descendant of it — i.e. the operator regressed the
		//     binary, OR a sibling branch was installed. Continuing
		//     would query the rolled-back/sibling schema with the
		//     new binary's column expectations. Fail loudly.
		//
		// (Auto-rollback was removed in rc.67: tmp/rc67-recovery-
		// rootcause.md Findings 4, 7-14 — it cascaded into a worse
		// state.)
		binaryAtFlag := d.binaryCommit == "" || d.binaryCommit == "unknown" || d.binaryCommit == flag.CommitSHA
		binaryDescendsFlag := false
		if !binaryAtFlag && d.binaryCommit != "" && d.binaryCommit != "unknown" {
			// `git merge-base --is-ancestor flag binary` exits 0 iff
			// flag is reachable from binary in git history (i.e.
			// binary is at flag or beyond). Errors (no such ref,
			// shallow clone) are conservative-false: fall through to
			// fail-loud rather than guess.
			if _, err := runCommandOutput(d.projDir, "git", "merge-base", "--is-ancestor", flag.CommitSHA, d.binaryCommit); err == nil {
				binaryDescendsFlag = true
			}
		}
		if !binaryAtFlag && !binaryDescendsFlag {
			progress.Write("Checking service state before proceeding ... failed: running binary %s cannot continue target %s; services: %v",
				ShortForDisplay(d.binaryCommit), flag.Label(), mismatched)
			progress.Close()
			return fmt.Errorf(
				"recovery after booting the new binary: containers do not match flag target %s and running binary %s is not at or descendant of flag target.\n"+
					"  Mismatched: %v\n"+
					"  This is a category-3 divergence per the recovery trifecta — the\n"+
					"  running binary is BEHIND the flag's target (or on a sibling branch).\n"+
					"  Continuing would query a schema newer than the binary speaks.\n"+
					"  Investigate `docker compose ps` and the upgrade-progress log;\n"+
					"  ./sb install will resume after the divergence is resolved",
				flag.Label(), ShortForDisplay(d.binaryCommit), mismatched)
		}
		// "mismatched" is the expected post-swap state — the prior process
		// stopped containers on purpose with old images so the new binary
		// can restart them with target tags. The list reads as a fault
		// only because of word choice and one-line formatting. Break into
		// a header + per-container lines so the operator can scan it.
		progress.Write("Checking service state before proceeding:")
		if binaryDescendsFlag {
			progress.Write("  Running binary %s includes the interrupted target %s; continuing forward", ShortForDisplay(d.binaryCommit), flag.Label())
		}
		for _, m := range operatorServiceStateLines(mismatched) {
			progress.Write("  %s", m)
		}
	}

	// STATBUS-046 (doc-021/D3) — the crash-resume ATTEMPT BUDGET, the bound that
	// replaces the rune loop-forever. We are past the self-heal early return, so
	// this resume IS a fresh forward attempt. resumeNewSb is only reached in
	// the already-at-new forward regime (recoverFromFlag routes a positively-Behind
	// observed state to rollback, never here), so a terminal verdict PARKS
	// (canRollBack=false); direction stays STATBUS-039's call — 046 only bounds
	// how-long/how-loud.
	//
	// (1) A PARKED row is skipped entirely — alive-idle, no attempt consumed, no
	//     siren re-fire. Un-park is only via a deliberate operator trigger.
	//
	// FAIL-OPEN on a read error (log loud, do NOT return early — do NOT "fix" this
	// into fail-closed). DECISIVE case: a crash mid-flight on the 046-SHIPPING
	// upgrade itself runs this SELECT against the still-UNMIGRATED schema —
	// recovery_parked_at doesn't exist until its own migrate-up at step 3.5, so
	// the read errors SQLSTATE 42703 persistently on every boot. Fail-open logs +
	// proceeds → the increment below fails the same way → attempts=1 fallback →
	// migrate-up ships the columns → the feature bootstraps itself through its own
	// deferral window. Fail-CLOSED would return BEFORE the increment and loop
	// UNCOUNTED forever on exactly that path — the rune class the budget exists to
	// kill. Fail-open is also provably harmless on a transient blip: the escalation
	// core re-derives TERMINAL from persisted state (attempts never decrease,
	// Step==PriorDeathStep survives on the flag), so a genuinely-parked row parks
	// again before the reacquire — no pipeline attempt ever runs on it.
	//
	// STATBUS-044 comment #6 — RecoveryBudgetGuard (Run + install ladder) may have
	// ALREADY counted + consulted this pass at boot, before the boot migrate. Capture
	// that at entry: the parked-skip below runs REGARDLESS (a row the guard just
	// parked must not run applyNewSbUpgrading — the parked-skip is what returns the unit
	// to alive-idle), but the increment + consult are SKIPPED when the guard ran.
	// Skipping the CONSULT is load-bearing: after a boot migrate that SUCCEEDS
	// following a boot-migrate death, flag.Step == flag.PriorDeathStep ==
	// StepBootMigrate, so re-consulting here would FALSE-PARK a pass whose migration
	// actually succeeded (comment #6's verified subtlety).
	guardCounted := d.recoveryPassCounted
	parked, parkReason, perr := d.upgradeParkedReason(ctx, flag.ID)
	if parkStateUnknown(perr) {
		// This guard is the ONLY thing standing between a parked row and
		// applyNewSbUpgrading (its sole caller, below), whose failure paths roll
		// back and restore. The escalation budget bounds how MANY attempts
		// happen; it does not stop the first one restoring over a park.
		parked = true
		parkReason = fmt.Sprintf("park state UNKNOWN — the read failed (%v); refusing the automatic resume on an unverified row", perr)
	} else if perr != nil {
		log.Printf("resumeNewSb: recovery_parked_at does not exist for upgrade %d (%v) — the row CANNOT be parked on this schema, so the resume proceeds on knowledge, not on a guess", flag.ID, perr)
	}
	if parked {
		log.Printf("resumeNewSb: upgrade %d is PARKED (%s) — skipping automatic resume; re-trigger the upgrade or run ./sb install to make a fresh attempt", flag.ID, parkReason)
		progress.Write("Checking whether upgrade %d should continue automatically ... paused: %s", flag.ID, parkReason)
		progress.Write("  A later release or a deliberate ./sb install run can make a fresh attempt.")
		progress.Close()
		return nil
	}
	if !guardCounted {
		// (2) Increment at attempt START so a death self-counts (D3: process deaths
		//     only). Non-fatal on write error — fall back to a single conservative
		//     attempt rather than block recovery on bookkeeping. countRecoveryAttemptOnce
		//     also records the count so a later recoveryRollback in the same pass reuses it.
		attempts, aerr := d.countRecoveryAttemptOnce(ctx, flag.ID)
		if aerr != nil {
			log.Printf("resumeNewSb: could not increment recovery_attempts for %d (%v) — proceeding with a single attempt", flag.ID, aerr)
			attempts = 1
		}
		// (3) Consult the pure escalation core. deathStep = where the PREVIOUS attempt
		//     died (flag.Step, frozen by that crash); priorDeathStep = the death two
		//     attempts ago (flag.PriorDeathStep). Terminal already-at-new → PARK.
		if action, reason := resumeEscalation(attempts, flag.Step, flag.PriorDeathStep, false); action != recoveryContinue {
			freshlyParked, parkErr := d.parkUpgrade(ctx, flag.ID, reason,
				fmt.Sprintf("parked after %d crash-resume attempts: %s", attempts, reason))
			if parkErr != nil {
				progress.Write("Pausing automatic upgrade recovery ... failed: %v", parkErr)
				progress.Close()
				return fmt.Errorf("resumeNewSb: park write failed for upgrade %d: %w", flag.ID, parkErr)
			}
			log.Printf("resumeNewSb: PARKED upgrade %d after %d attempt(s) — %s", flag.ID, attempts, reason)
			progress.Write("Pausing automatic upgrade recovery after %d failed continuation attempt(s) ... ok", attempts)
			progress.Write("  Cause: %s", reason)
			progress.Write("  The service remains available for a later release or a deliberate ./sb install retry.")
			// STATBUS-204: route this budget park through the operable-box chokepoint too — bring
			// the source version's services back (era-guarded, starts-only, narrative-only on
			// refuse/failure) so a same-step-twice park is alive-idle AND operable, not dark. The
			// helper owns its watchdog cover. restoreTargetSHA="" falls back to this attempt's
			// pre-upgrade pin (identity holds post-197).
			d.parkServiceRecovery(ctx, flag.ID, "", progress)
			progress.Close()
			// Degraded siren — fires EXACTLY ONCE per park EVENT: only when THIS call
			// is the one that flipped the row into parked (freshlyParked, from the
			// parkUpgrade parked_at guard). A re-park after a failed fresh attempt is a
			// new event and correctly sirens again; a blip that re-enters an already-
			// parked row does not (RowsAffected==0 → freshlyParked==false).
			if freshlyParked {
				d.runCallback(flag.Label(), map[string]string{"STATBUS_EVENT": "parked", "STATBUS_PARKED": "1", "STATBUS_PARK_REASON": reason})
			}
			return nil
		}
	}

	// Re-acquire the flock on the flag file AND advance the on-disk phase to
	// Resuming: from here this process commits to running applyNewSbUpgrading on the
	// new binary. If it dies before completing (watchdog SIGABRT on a hung step,
	// OOM, reboot, kill), the next recoverFromFlag sees Phase=Resuming and
	// consults observed state (STATBUS-039): at-or-past target → resume forward
	// again; confirmed behind → one-shot rollback to this upgrade's own
	// snapshot (flag.BackupPath, carried below) (upgrade-timeline.md
	// § Binary-swap restart + resume). We only reach here past the
	// self-heal-converged early return above, so a legitimately-converged upgrade
	// still self-heals to completed before the phase advances.
	//
	// STATBUS-046: roll flag.Step (where THIS attempt's predecessor died) into
	// PriorDeathStep so the NEXT resume can detect two consecutive deaths at the
	// same step (deterministic hang → park early). Step itself resets to "" and
	// recordFlagStep re-stamps it as applyNewSbUpgrading progresses.
	//
	// STATBUS-044 comment #6: when RecoveryBudgetGuard already ran this pass
	// (guardCounted), it ALREADY rolled the death history (PriorDeathStep ← the prior
	// Step) and stamped Step=StepBootMigrate for the boot window. PRESERVE its roll —
	// re-rolling flag.Step (now StepBootMigrate) into PriorDeathStep would corrupt the
	// same-step comparison for a death that occurs AFTER the boot migrate (it would
	// wrongly read boot-migrate as the prior death). Only the un-guarded fallback
	// path (guard was a no-op) rolls flag.Step here.
	priorDeathStep := flag.Step
	if guardCounted {
		priorDeathStep = flag.PriorDeathStep
	}
	reacquired := UpgradeFlag{
		ID:             flag.ID,
		CommitSHA:      flag.CommitSHA,
		CommitTags:     flag.CommitTags,
		StartedAt:      time.Now(),
		InvokedBy:      flag.InvokedBy,
		Trigger:        flag.Trigger,
		Holder:         HolderService,
		Phase:          PhaseNewSbUpgrading,
		Recreate:       flag.Recreate,
		BackupPath:     flag.BackupPath,
		PriorDeathStep: priorDeathStep,
	}
	lock, lerr := acquireFlock(d.projDir, reacquired)
	if lerr != nil {
		progress.Write("Reacquiring the upgrade lock before continuing ... failed: %v", lerr)
		progress.Close()
		return fmt.Errorf("resumeNewSb: re-acquire flock: %w", lerr)
	}
	d.flagLock = lock
	d.upgrading = true
	defer func() { d.upgrading = false }()

	if applyErr := d.applyNewSbUpgrading(ctx, flag.ID, flag.CommitSHA, flag.Label(), restoreTargetSHA, flag.BackupPath, flag.Recreate, progress); applyErr != nil {
		// rollback() already ran inside applyNewSbUpgrading and (post-rc.67)
		// exits the process unconditionally. If we somehow got here
		// without exiting, propagate the error to the caller.
		return applyErr
	}
	return nil
}

// runUpgradeCallback notifies external systems after a successful upgrade.
// Thin wrapper over runCallback with no extra env — preserved as a
// distinct name so success-path call sites read clearly.
func (d *Service) runUpgradeCallback(displayName string) {
	// STATBUS-137: name the success event so operator streams keyed on
	// STATBUS_EVENT can route it (was firing blank).
	d.runCallback(displayName, map[string]string{"STATBUS_EVENT": "completed"})
}

// runCallback executes the UPGRADE_CALLBACK shell command from .env, if
// set, with the given displayName context plus any extraEnv overlay.
// Used by both the success path (no extraEnv) and the rollback-failure
// path (passes STATBUS_ROLLBACK_FAILED=1 and recovery context so the
// callback script — typically ops/notify-slack.sh — can branch on
// outcome). Never fails the upgrade; logs errors but always returns.
// maybeRunBackup takes a scheduled logical backup (pg_dump) if one is due and no
// upgrade is in flight (STATBUS-113). Invoked from the BACKUP_INTERVAL ticker and
// once at boot for missed-window catch-up — ALWAYS in a goroutine. It NEVER
// crashes the service: a panic is recovered and logged, and the next tick retries.
//
// Coordination (AC#3): the backup defers to any upgrade — the service's own
// (d.upgrading) or an install-CLI-driven one (the upgrade-in-progress flock). The
// upgrade takes its own pre-swap snapshot, so a skipped run loses nothing; the
// next tick (or the boot catch-up) covers the gap. A backup that races the START
// of an upgrade is harmless anyway: dbdump.DumpDatabase is atomic, so a DB stop
// aborts it leaving only a discardable .tmp.
func (d *Service) maybeRunBackup(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			fmt.Printf("Scheduled backup: recovered from panic (service continues): %v\n", r)
		}
	}()
	if ctx.Err() != nil {
		return // service shutting down — don't start a dump
	}

	if run, skipReason := d.backupGate(); !run {
		if skipReason != "" {
			fmt.Printf("Scheduled backup skipped: %s\n", skipReason)
		}
		return
	}

	// Single-flight: a previous backup may still be running (a slow dump that
	// outlasted the tick interval). TryLock returns immediately if so.
	if !d.backupMu.TryLock() {
		return
	}
	defer d.backupMu.Unlock()

	// Re-check under the lock: an upgrade may have started — or another path may
	// have produced a dump — between the first gate read and acquiring the lock.
	if run, _ := d.backupGate(); !run {
		return
	}

	start := time.Now()
	fmt.Println("Scheduled backup: starting pg_dump ...")
	path, err := dbdump.DumpDatabase(d.projDir)
	if err != nil {
		fmt.Printf("Scheduled backup FAILED: %v\n", err)
		// Notify on failure only (reuse UPGRADE_CALLBACK); success is silent.
		d.runCallback("scheduled-backup", map[string]string{
			"STATBUS_EVENT": "backup_failed",
			"STATBUS_ERROR": err.Error(),
		})
		return
	}
	size := int64(0)
	if info, sErr := os.Stat(path); sErr == nil {
		size = info.Size()
	}
	fmt.Printf("Scheduled backup completed: %s (%d bytes) in %s\n",
		path, size, time.Since(start).Round(time.Second))

	if deleted, pErr := dbdump.PurgeDumps(d.projDir, d.backupRetention); pErr != nil {
		// Retention purge failure is non-fatal — the fresh dump is safe and the
		// next run catches up. Log, don't fail.
		fmt.Printf("Scheduled backup: dump kept, retention purge failed: %v\n", pErr)
	} else if len(deleted) > 0 {
		fmt.Printf("Scheduled backup: purged %d old dump(s), keeping newest %d per prefix\n",
			len(deleted), d.backupRetention)
	}
}

// backupGate decides whether a scheduled backup should run now. It returns a
// human-readable reason ONLY for a loud skip (an upgrade is in flight); disabled
// and not-due are silent skips (reason ""). Pure w.r.t. the dump itself (no
// docker, no lock) so the coordination rules are unit-testable.
func (d *Service) backupGate() (run bool, skipReason string) {
	if !d.backupEnabled {
		return false, "" // opted out — silent
	}
	if d.upgrading || IsFlockHeld(d.projDir) {
		return false, "upgrade in progress"
	}
	if !backupDue(d.projDir, d.backupInterval) {
		return false, "" // a recent dump already covers this window — silent
	}
	return true, ""
}

// backupDue reports whether a logical backup is due: true if no dump exists yet,
// or the newest dump is at least ~one interval old. The 0.9×interval threshold is
// a deliberate tolerance: the BACKUP_INTERVAL ticker fires one interval after the
// previous dump COMPLETED, so at tick time the newest dump is slightly younger
// than a full interval (by the dump's own runtime + scheduler jitter); a strict
// `>= interval` test would miss every other tick and halve the real cadence. The
// slack is operationally irrelevant at a daily cadence and still prevents a
// dump-on-every-restart at boot (a fresh dump is far younger than 0.9×interval).
func backupDue(projDir string, interval time.Duration) bool {
	newest, ok := dbdump.NewestDumpModTime(projDir)
	if !ok {
		return true // no dump yet → due
	}
	return time.Since(newest) >= interval-interval/10
}

func (d *Service) runCallback(displayName string, extraEnv map[string]string) {
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		fmt.Printf("Upgrade callback: cannot load .env: %v\n", err)
		return
	}

	callback, ok := f.Get("UPGRADE_CALLBACK")
	if !ok || callback == "" {
		return
	}

	hostname, _ := os.Hostname()

	statbusURL := ""
	if v, ok := f.Get("STATBUS_URL"); ok {
		statbusURL = v
	}

	fmt.Printf("Running upgrade callback...\n")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "sh", "-c", callback)
	cmd.Dir = d.projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	env := append(os.Environ(),
		"STATBUS_VERSION="+displayName,
		"STATBUS_FROM_VERSION="+d.version,
		"STATBUS_SERVER="+hostname,
		"STATBUS_URL="+statbusURL,
	)
	for k, v := range extraEnv {
		env = append(env, k+"="+v)
	}
	cmd.Env = env
	prepareCmd(cmd)

	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			fmt.Printf("Upgrade callback timed out after 30s\n")
		} else {
			fmt.Printf("Upgrade callback failed: %v\n", err)
		}
		return
	}
	fmt.Printf("Upgrade callback completed successfully\n")
}

// failUpgrade marks an upgrade row state='failed' WITHOUT invoking
// rollback(). This is correct ONLY for failures that happen BEFORE any
// destructive step (i.e. before backupDatabase at executeUpgrade step 5):
//
//   - downgrade refusal (no destructive work)
//   - missing release manifest / platform binary (no destructive work)
//   - disk-space precondition (no destructive work)
//   - signature verification (no destructive work)
//   - flag-file write (no destructive work)
//   - pullImagesForCommitShort (downloads images but doesn't touch live DB or services)
//
// AUDIT (task #49 / Gap #4): if a future executeUpgrade step adds
// destructive side effects (stops services, modifies the DB schema,
// swaps the binary, etc.) BEFORE backupDatabase, its handler MUST NOT
// use failUpgrade — it MUST call d.rollback() so the live system is
// actually restored to the previous version. The user's principle is
// "two outcomes only — completed, or failed-with-rollback. No silent
// in-between." failUpgrade as it stands is the "no destructive state to
// undo" exception; preserve that contract by reading this comment
// before extending it.
func (d *Service) failUpgrade(ctx context.Context, id int, errMsg string, progress *ProgressLog) {
	d.failUpgradeWithFlagDisposition(ctx, id, errMsg, progress, false)
}

// failUpgradeKeepingFlag records the same durable failed row as failUpgrade but
// preserves the recovery breadcrumb. Use it when a cleanup boundary failed and
// the next ./sb install must reconcile machine state before another attempt.
func (d *Service) failUpgradeKeepingFlag(ctx context.Context, id int, errMsg string, progress *ProgressLog) {
	d.failUpgradeWithFlagDisposition(ctx, id, errMsg, progress, true)
}

// abortFailedPreBackupStop unwinds a stop failure before any snapshot or live
// data mutation. The upgrade marker may disappear only when every machine-state
// boundary is confirmed clean: services restarted, HTTP maintenance removed,
// PostgreSQL reconnected, and the read-only default lifted. Any uncertainty
// leaves a free recovery marker for ./sb install or the daemon to reconcile.
func (d *Service) abortFailedPreBackupStop(ctx context.Context, id int, boundary, errMsg string, restartServices []string, progress *ProgressLog) string {
	needsRecovery := false
	restartArgs := append([]string{"compose", "up", "-d"}, restartServices...)
	if restartErr := runCommand(d.projDir, "docker", restartArgs...); restartErr != nil {
		needsRecovery = true
		progress.Write("  Restarting services after the %s failure ... failed: %v", boundary, restartErr)
		errMsg += fmt.Sprintf("; services also did not restart cleanly: %v", restartErr)
	} else {
		progress.Write("  Restarting services after the %s failure ... ok", boundary)
	}

	if maintenanceErr := d.setMaintenance(false, ""); maintenanceErr != nil {
		needsRecovery = true
		progress.Write("  Lifting maintenance mode after the %s failure ... failed: %v", boundary, maintenanceErr)
		errMsg += fmt.Sprintf("; maintenance mode also did not lift: %v", maintenanceErr)
	} else {
		progress.Write("  Lifting maintenance mode after the %s failure ... ok", boundary)
	}

	if reconnectErr := d.reconnect(ctx); reconnectErr != nil {
		needsRecovery = true
		progress.Write("  Reconnecting after the %s failure ... failed: %v", boundary, reconnectErr)
		errMsg += fmt.Sprintf("; database reconnection also failed: %v", reconnectErr)
	} else {
		progress.Write("  Reconnecting after the %s failure ... ok", boundary)
		offStatement, offErr := d.setDatabaseReadOnly(ctx, false)
		if offErr != nil {
			needsRecovery = true
			progress.Write("  Unblocking SQL writes after the %s failure ... failed: %v", boundary, offErr)
			errMsg += fmt.Sprintf("; SQL writes may remain blocked: %v", offErr)
		} else {
			progress.Write("  Unblocking SQL writes after the %s failure ... ok", boundary)
			progress.Write("    ran: %s", offStatement)
		}
	}

	if needsRecovery {
		d.failUpgradeKeepingFlag(ctx, id, errMsg, progress)
	} else {
		d.failUpgrade(ctx, id, errMsg, progress)
	}
	return errMsg
}

func (d *Service) failUpgradeWithFlagDisposition(ctx context.Context, id int, errMsg string, progress *ProgressLog, keepFlag bool) {
	// STATBUS-338, Norway rc.02: keep the original failure outside the DB volume
	// before any terminal write or unwind can fail. Callers before flag acquisition
	// remain a no-op; claimed preswap failures gain an honest restart breadcrumb.
	if err := d.recordOriginalError(errMsg); err != nil {
		log.Printf("failUpgrade: could not persist original error in the held flag: %v (continuing with the in-memory error)", err)
	}
	progress.Write("FAILED: %s", errMsg)
	// Bundle BEFORE the terminal UPDATE so inspecting a `failed` row on
	// disk is guaranteed to have a sibling .bundle.txt. Non-fatal.
	d.writeDiagnosticBundle(ctx, id, progress)
	if d.queryConn != nil {
		// The on-disk log (referenced by log_relative_file_path) holds the
		// full narrative; the admin UI fetches it via /upgrade-logs/<name>.
		// state='failed' requires started_at IS NOT NULL — executeScheduled
		// always sets started_at before executeUpgrade runs, so that holds.
		var failJSON string
		if scanErr := d.queryConn.QueryRow(ctx,
			"UPDATE public.upgrade SET state = 'failed', error = $1, scheduled_at = NULL WHERE id = $2"+upgradeRowReturning,
			errMsg, id).Scan(&failJSON); scanErr == nil {
			logUpgradeRow(LabelFailed, failJSON)
		}
	}
	// Normally release the mutex on failure paths, even those that don't run
	// rollback (e.g., pullImagesForCommitShort failure returns directly after failUpgrade).
	// removeUpgradeFlag is idempotent — safe when no flag was acquired (some
	// failUpgrade callers run before writeUpgradeFlag during pre-flight).
	if keepFlag {
		d.releaseUpgradeFlagLockKeepingFile()
		progress.Write("Preserving the recovery marker after releasing its live lock: %s", homeRelativePath(d.flagPath()))
		return
	}
	if err := d.removeUpgradeFlag(); err != nil {
		progress.Write("Releasing upgrade lock after failure ... failed: %v", err)
		d.markTerminal("FAILURE_UPGRADE_LOCK_RELEASED",
			fmt.Sprintf("id=%d; failed-row lock release error=%v; ./sb install reconciles it", id, err))
	}
}

// readAdministratorContact returns the ADMINISTRATOR_CONTACT value from
// <projDir>/.env (set by ./sb config generate), or "" if unset/unreadable.
// Callers MUST tolerate the empty-string case — development installs leave
// it empty and the UI renders sensibly without it.
// captureContainerLogs writes per-service docker logs into a sibling
// directory of the per-upgrade log so a failure-time snapshot survives
// the rollback's docker compose stop+recreate. The directory is named
// <log-basename>.containers/ and contains one file per service. Best
// effort: if the docker call hangs or fails, log via progress and move
// on — capture must NOT block rollback's recovery path. Each per-service
// command has its own 8s deadline.
func captureContainerLogs(projDir string, progress *ProgressLog, services []string) {
	if progress == nil || progress.RelPath() == "" {
		return
	}
	base := strings.TrimSuffix(progress.RelPath(), filepath.Ext(progress.RelPath()))
	dirRel := filepath.Join("tmp", "upgrade-logs", base+".containers")
	dirAbs := filepath.Join(projDir, dirRel)
	if err := os.MkdirAll(dirAbs, 0755); err != nil {
		progress.Write("Warning: could not create container log dir %s: %v", dirRel, err)
		return
	}

	for _, svc := range services {
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		cmd := exec.CommandContext(ctx, "docker", "compose", "logs",
			"--tail", "500", "--no-color", svc)
		cmd.Dir = projDir
		out, err := cmd.CombinedOutput()
		cancel()
		path := filepath.Join(dirAbs, svc+".log")
		if err != nil && len(out) == 0 {
			_ = os.WriteFile(path, []byte(fmt.Sprintf("# capture failed: %v\n", err)), 0644) // best-effort diagnostic placeholder
			continue
		}
		if writeErr := os.WriteFile(path, out, 0644); writeErr != nil {
			progress.Write("Warning: could not write %s: %v", filepath.Join(dirRel, svc+".log"), writeErr)
		}
	}
	progress.Write("Captured pre-rollback container logs to %s/", dirRel)
}

func readAdministratorContact(projDir string) string {
	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return ""
	}
	v, _ := f.Get("ADMINISTRATOR_CONTACT")
	return strings.TrimSpace(v)
}

// contactSuffix formats the trailing ": <contact>" fragment for the
// CATASTROPHIC FAILURE headline. Empty contact → empty suffix (so the
// headline still reads as a complete sentence without trailing ": .").
// The caller interpolates the result via a %s verb, which inserts the
// value verbatim — no %-escaping needed and none applied.
func contactSuffix(contact string) string {
	contact = strings.TrimSpace(contact)
	if contact == "" {
		return ""
	}
	return ": " + contact
}

// writeRollbackTerminal records rollback()'s terminal state (the `failed` or
// `rolled_back` UPDATE) durably, and reports whether the write landed.
//
// rollback() restarts the database (docker compose up) and then races its own
// reconnect — the post-rollback reconnect can transiently fail ("connection
// reset by peer", DB still starting). A single-shot UPDATE on a dead conn used
// to be silently swallowed, leaving the row stuck in_progress while the caller
// removed the flag and exited claiming success — the silent strand the collapse
// exists to kill. This mirrors the bounded-retry + markTerminal contract of the
// other terminal-write sites (completeInProgressUpgrade, recoverFromFlag).
//
// Each attempt ensures a live query connection via reconnect() — which also
// re-acquires the upgrade_daemon advisory lock. If that lock is held, reconnect
// fails: a live service legitimately owns the upgrade authority, so we exhaust
// and YIELD (the caller keeps the flag; the service's completeInProgressUpgrade
// / recoverFromFlag reconciles the row). We never bypass the lock.
//
// Returns true iff the UPDATE committed (RETURNING row scanned). On persistent
// failure it emits the INVARIANT transcript + markTerminal (the on-disk audit
// channel; the support bundle is already written once by rollback() before the
// terminal write) and returns false — never swallows. The caller then KEEPS the
// flag so the next boot reconciles.
// terminalWriteTimeout / terminalWriteMaxAttempts bound the teardown-immune
// terminal write (STATBUS-154). 30s comfortably covers a fresh connect + a
// single guarded UPDATE; 4 attempts × retryBackoff rides a brief connectivity
// blip without hanging the exiting pass.
const (
	terminalWriteTimeout     = 30 * time.Second
	terminalWriteMaxAttempts = 4
)

// terminalConnDo is the teardown-immune primitive under EVERY terminal write and
// window flip — the shared core of terminalUpdate (row writes: writeRollbackTerminal,
// the completed-state UPDATEs, parkUpgrade — STATBUS-154) and terminalExec (the
// read-only-window OFF flip — STATBUS-163). ONE definition so a future backoff /
// error-classification / exemption change lands in a single place; two hand-synced
// copies would be the seed of the next 163 (163's own lesson: a teardown-immune
// property applied non-uniformly across sites). Three properties, one per the
// failure class it kills:
//
//	(i)   context.Background() + its own short deadline — NEVER the caller's
//	      pass ctx. A terminal write is the pass's LAST WORD; sharing the pass
//	      ctx let teardown cancel it mid-flight ("context already done: context
//	      canceled"), so the process exited as-terminal while the row disagreed.
//	(ii)  a FRESH short-lived daemon-tagged connection per attempt (149's
//	      recoveryDSN), NEVER d.queryConn — always-fresh sidesteps the
//	      cached-statement-deallocation class ("failed to deallocate cached
//	      statement(s)") entirely, and structurally kills the 'conn closed' race.
//	(iii) bounded retry on connect/connection errors — generalizes the 047-H
//	      completion-write reconnect save (patched at ONE terminal; 154/163 prove
//	      every terminal write AND flip needed it).
//
// fn runs on the fresh, read-only-exempt session. Returns nil on success. A
// NON-connection error from fn (a CHECK violation, pgx.ErrNoRows on a 0-row guard,
// or a genuine 25006 on a bad statement) is returned IMMEDIATELY without retry — it
// will not self-heal; the caller interprets it. Writes NO markTerminal/bundle — the
// caller owns terminal escalation.
func (d *Service) terminalConnDo(fn func(ctx context.Context, conn *pgx.Conn) error) error {
	ctx, cancel := context.WithTimeout(context.Background(), terminalWriteTimeout)
	defer cancel()
	var lastErr error
	for attempt := 0; attempt < terminalWriteMaxAttempts; attempt++ {
		connStr, derr := d.recoveryDSN()
		if derr != nil {
			lastErr = derr
		} else if conn, cerr := pgx.Connect(ctx, connStr); cerr != nil {
			lastErr = cerr
		} else if _, roErr := conn.Exec(ctx, "SET default_transaction_read_only = off"); roErr != nil {
			// STATBUS-154 (wave-6 regression) + STATBUS-110/-021: this FRESH
			// session postdates the post-swap read-only flip (ALTER DATABASE ...
			// default_transaction_read_only = on), so it inherits read-only and
			// the terminal write/flip would hit 25006 (read_only_sql_transaction) —
			// a NON-conn error → no retry → it could never land. The read-only
			// window is an accident-guard against APPLICATION writes, NEVER a lock
			// on machinery bookkeeping; the pass conns self-exempt in connect() for
			// exactly this reason, so this fresh session must too. USERSET GUC, no
			// special privilege. (NOT via the DSN -c: that would demote every
			// recoveryDSN consumer incl. the reachability probe. NOT BEGIN READ
			// WRITE: needless tx choreography.) A SET failure is a live-connection
			// fault → close + retry within the bounded budget.
			_ = conn.Close(context.Background()) // best-effort; retrying with a fresh connection regardless
			lastErr = roErr
		} else {
			lastErr = fn(ctx, conn)
			_ = conn.Close(context.Background()) // best-effort; this attempt's connection is being discarded either way
			if lastErr == nil {
				return nil
			}
			// A non-connection error will not self-heal on retry — hand it back
			// for the caller to interpret.
			if !isConnError(lastErr) {
				return lastErr
			}
		}
		if attempt < terminalWriteMaxAttempts-1 {
			time.Sleep(retryBackoff(attempt + 1))
		}
	}
	return lastErr
}

// terminalUpdate is the row-returning thin wrapper over terminalConnDo (STATBUS-154):
// the terminal STATE writers persist an UPDATE ... RETURNING and scan the row JSON,
// teardown-immune. Returns (rowJSON, nil) on a landed write; a non-conn error
// (CHECK / ErrNoRows) is handed back for the caller to interpret (e.g. parkUpgrade
// reads ErrNoRows as "verify already parked"). Idempotent by construction (callers
// pass state-guarded UPDATEs); writes no markTerminal — the caller owns escalation.
func (d *Service) terminalUpdate(updateSQL string, args ...any) (string, error) {
	var rowJSON string
	err := d.terminalConnDo(func(ctx context.Context, conn *pgx.Conn) error {
		return conn.QueryRow(ctx, updateSQL, args...).Scan(&rowJSON)
	})
	return rowJSON, err
}

// terminalExec is the non-row-returning thin wrapper over terminalConnDo (STATBUS-163):
// the terminal read-only-WINDOW flips (the OFF at completion/rollback) use it so the
// flip outlives the completing pass's dying connection exactly as the terminal row
// write does — the 'conn closed' race STATBUS-154 killed for row writes, now killed
// for the flip (caught by the STATBUS-110 AC#2 rider's first live red).
func (d *Service) terminalExec(execSQL string, args ...any) error {
	return d.terminalConnDo(func(ctx context.Context, conn *pgx.Conn) error {
		_, e := conn.Exec(ctx, execSQL, args...)
		return e
	})
}

// liftReadOnlyWindow clears the read-only upgrade window on the CURRENT database
// through terminalConnDo's teardown-immune fresh connection. It resolves the
// database name and executes the direct ALTER on that same connection, returning
// the exact statement so the caller can put the hand-undoable artifact in its own
// progress stream.
//
// STATBUS-266. The window announced itself in ONE direction: setDatabaseReadOnly
// prints for both ON and OFF, but only the FAILURE paths call it — every success
// path clears the window through terminalExec(windowOffSQL), which says nothing
// when it works. So a healthy upgrade left `read-only window ON` in the journal
// with no matching OFF, and the only way to learn the window had lifted was to
// query the catalog.
//
// That asymmetry is not cosmetic: it actively misleads. Grepping the journal of a
// perfectly healthy box shows ON-and-never-OFF, which reads as a stuck window —
// and during STATBUS-262 it did exactly that, sending three ranked hypotheses
// after a window that had lifted a week earlier. The next responder meets the
// same trap at 2am.
//
// A state change announced in one direction and silent in the other is a defect
// in its own right. After this, ON always pairs with either an OFF or a loud
// failure, and window state is answerable by grep.
//
// `where` names the terminal that lifted it, because five sites clear this
// window and "which one ran" is the next question a responder asks.
func (d *Service) liftReadOnlyWindow(where string) (string, error) {
	var statement string
	err := d.terminalConnDo(func(ctx context.Context, conn *pgx.Conn) error {
		var dbName string
		if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&dbName); err != nil {
			return fmt.Errorf("%s: resolve current database: %w", where, err)
		}
		statement = fmt.Sprintf("ALTER DATABASE %s SET default_transaction_read_only = off", quoteIdent(dbName))
		if _, err := conn.Exec(ctx, statement); err != nil {
			return fmt.Errorf("%s: %w", where, err)
		}
		return nil
	})
	return statement, err
}

// flagSourcedBackupPath resolves THE FLAG's backup identity for the terminal
// write (STATBUS-241). It returns a *string carrying the three-state answer
// terminalBackupPathSQL consumes, plus a short source label for the log:
//
//	(&"<path>", "held flag")  — this attempt stamped an identity at the swap
//	(&"",       "held flag")  — PreSwap: nothing moved, so there is no identity
//	(nil,       "...")        — UNKNOWN: no flag we can read. NOT the same as
//	                            empty, and the caller must leave the column be.
//
// Reads the HELD descriptor first (authoritative while the flock is ours, and
// it sees writes this process made without re-opening), then falls back to the
// on-disk file. The descriptor's offset is restored so a later mutateHeldFlag
// rewrite is unaffected.
func (d *Service) flagSourcedBackupPath() (*string, string) {
	if d.flagLock != nil && d.flagLock.file != nil {
		f := d.flagLock.file
		if _, err := f.Seek(0, 0); err == nil {
			data, readErr := io.ReadAll(f)
			// Restore the offset regardless — mutateHeldFlag seeks before every
			// use, but leaving a shared descriptor at EOF is a trap for the next
			// reader that does not.
			_, _ = f.Seek(0, 0)
			if readErr == nil {
				var flag UpgradeFlag
				if json.Unmarshal(data, &flag) == nil {
					p := flag.BackupPath
					return &p, "held flag"
				}
			}
		}
	}
	if flag, err := ReadFlagFile(d.projDir); err == nil && flag != nil {
		p := flag.BackupPath
		return &p, "flag file on disk"
	}
	return nil, "no readable flag"
}

// terminalBackupPathSQL is the backup_path re-imposition every rollback/abort
// terminal UPDATE must carry (STATBUS-241). It reads $4 — a *string supplied by
// writeRollbackTerminal from the FLAG, never from a caller's variable — and
// distinguishes the three states the column can legitimately be in after a
// volume rewind:
//
//	$4 IS NULL   → the identity is UNKNOWN (no readable flag): keep whatever the
//	               row holds. Never guess NULL; the flagless STATBUS-111 replay
//	               path lands here with a live identity that must survive.
//	$4 = ''      → the flag says NOTHING MOVED (PreSwap): impose SQL NULL, so a
//	               rewind cannot resurrect a stale identity onto a route whose
//	               whole contract is that it has none.
//	$4 = '<path>' → impose that identity.
//
// Kept as one named constant so the four call sites cannot drift apart, and so
// the source pin has a single string to require.
const terminalBackupPathSQL = `, backup_path = CASE WHEN $4::text IS NULL THEN backup_path ELSE NULLIF($4::text, '') END`

// writeRollbackTerminal persists a rollback/abort terminal row via the
// teardown-immune terminalUpdate (STATBUS-154 — it no longer takes the pass
// ctx; the write must outlive the pass). Returns true iff the row landed; on
// exhaustion it fails LOUD (markTerminal) and returns false so the caller KEEPS
// the flag for the next reconcile.
// attempts (STATBUS-181) re-imposes recovery_attempts onto the terminal row.
// Callers pass the value they read BEFORE any destructive restore step — a
// volume-rewind restore (restoreDatabase) reverts the column to whatever the
// pre-upgrade snapshot had (typically 0), and this UPDATE is what runs AFTER
// that rewind, so every updateSQL string passed in here MUST include
// `recovery_attempts = $2` (with id shifted to $3) or the re-impose is a
// silent no-op. See callers for the exact SQL shape.
//
// STATBUS-241 — backup_path is re-imposed by the SAME mechanism, one column
// over, and it is SOURCED FROM THE FLAG rather than from a parameter. The
// rewind that erases recovery_attempts erases this column too: the ABORT branch
// restores the volume (:8609) BEFORE its terminal write, rewinding
// public.upgrade to a snapshot taken before the post-reconnect recorder ran,
// where backup_path is NULL. The consequence is not cosmetic — the abort-hold
// guard (:3841, `state='failed' AND backup_path IS NOT NULL`) then reads zero
// and FAILS OPEN, stripping the read-only hold protecting a broken volume on
// exactly the population it exists for.
//
// WHY THE FLAG AND NOT A PARAMETER: the flag is the authoritative carrier
// across this gap (STATBUS-228), and STATBUS-229 made its value correct on BOTH
// routes BY CONSTRUCTION — empty at PreSwap (nothing moved, so no identity may
// exist) and the identity once the swap stamps it. Reading it here therefore
// writes the right value on either arm, where a remembered variable could
// resurrect an identity onto a route that must not carry one.
//
// THREE STATES, DELIBERATELY DISTINCT — silence and empty are NOT the same
// thing (see flagSourcedBackupPath):
//   - flag readable, path set    → impose that identity
//   - flag readable, path empty  → impose SQL NULL explicitly (PreSwap: the
//     absence is a fact about the world, and imposing it defends the arcs'
//     "nothing moved ⇒ no identity" contract against a rewind resurrecting one)
//   - flag NOT readable          → LEAVE THE COLUMN ALONE. This is not
//     hypothetical: STATBUS-111's human-gated replay reaches restoreAndFinalize
//     with NO flag (the restore-broke terminal removed it), and imposing NULL
//     there would erase a live identity that reconcileBackupDir still needs.
//
// Every updateSQL passed here MUST therefore carry the backup_path CASE on $4
// exactly as the four call sites do, or the re-impose is a silent no-op in the
// same way a missing `recovery_attempts = $2` is.
func (d *Service) writeRollbackTerminal(id int, updateSQL, errMsg, label string, attempts int) bool {
	flagBackupPath, flagSource := d.flagSourcedBackupPath()
	if flagBackupPath == nil {
		// Loud, because it means the terminal row keeps whatever the rewind left
		// there — correct on the flagless replay path, worth seeing anywhere else.
		fmt.Fprintf(os.Stderr,
			"writeRollbackTerminal: no flag-sourced backup identity available (%s) for id=%d label=%s — leaving public.upgrade.backup_path AS-IS (STATBUS-241: imposing NULL here would erase a live identity on the flagless STATBUS-111 replay path)\n",
			flagSource, id, label)
	}
	rowJSON, err := d.terminalUpdate(updateSQL, errMsg, attempts, id, flagBackupPath)
	if err == nil {
		logUpgradeRow(label, rowJSON)
		return true
	}
	fmt.Fprintf(os.Stderr,
		"INVARIANT ROLLBACK_TERMINAL_WRITE_FAILED violated: rollback terminal write (%s) matched 0 rows or errored after retries (id=%d, err=%v) — KEEPING flag so the next recoverFromFlag/completeInProgressUpgrade reconciles (service.go:%d, pid=%d)\n",
		label, id, err, thisLine(), os.Getpid())
	d.markTerminal("ROLLBACK_TERMINAL_WRITE_FAILED",
		fmt.Sprintf("id=%d; label=%s; final err=%v", id, label, err))
	return false
}

// backupPath is the snapshot THIS upgrade recorded for itself (flag.BackupPath
// / row.backup_path / the in-process backupDatabase return) — the ONLY legal
// restore source (identity-keyed, STATBUS-039/-031). Empty means the upgrade
// never finalised a snapshot (PreSwap): restoreDatabase then refuses to touch
// the volume, which is exactly right — it was never mutated.
// restoreAndFinalize runs the restore-through-terminal-write tail shared by
// rollback() (the fail-fast upgrade rollback) and the install-driven restore
// re-attempt (STATBUS-111, dispatchInstallState). It restores the binary,
// regenerates config, rsync-restores the DB snapshot, brings services back,
// clears the maintenance + read-only windows, then writes the terminal row
// (rolled_back when healthy, failed when the restore/services degraded) and, on
// a landed write, removes the flag + fires the operator callback. Returns whether
// the outcome was degraded.
//
// PIN 1 (STATBUS-111): it makes NO process-lifecycle decision (no os.Exit) — the
// caller owns that (rollback() → exit 75; the re-attempt → exit 0 / actionable
// error). Callers must have stopped the db container and armed the watchdog
// cover before calling (rollback() does both in its head; the re-attempt does
// the same). Pure extraction of rollback()'s former tail — identical order.
//
// attemptsAtCall (STATBUS-181): recovery_attempts read by the CALLER before
// any destructive step (restoreDatabase below rewinds the volume to the
// pre-upgrade snapshot, where the column reads whatever it was BEFORE this
// upgrade's recovery passes ran — typically 0). Re-imposed onto the terminal
// row alongside state/error so the volume rewind doesn't silently erase the
// audit-trail value the row had at the moment this restore began.
func (d *Service) restoreAndFinalize(ctx context.Context, id int, version, reason, backupPath string, attemptsAtCall int, progress *ProgressLog) bool {
	projDir := d.projDir
	// Restore ./sb to match the restored git era BEFORE running config
	// generate (rc.67 trifecta). The current ./sb is the NEW binary; its
	// PersistentPreRun staleness guard (rc.65 freshness check) compares
	// the binary's compile-time COMMIT against git HEAD, which is now at
	// restoreTargetSHA. The guard fires exit-2 → "Warning: config generate
	// during rollback failed" (jo's 2026-04-28 deploy log line 105).
	// Restoring the binary first puts ./sb back at the same era as the
	// rolled-back git tree, so the staleness guard sees a match and
	// config generate runs cleanly. Best-effort; ErrRollbackBinaryCorrupt
	// is logged (non-fatal) if the rename fails.
	// STATBUS-197 C2: skip when this attempt committed no snapshot — nothing swapped (the swap
	// sits after backupDatabase), so ./sb.old (if any) belongs to a PRIOR attempt and restoring
	// it would install the wrong binary. The empty-path rollback skipped the git restore too;
	// the box is untouched at the source, so leave ./sb alone.
	if backupPath != "" {
		d.restoreBinary(progress)
	}

	if err := runCommandToLog(projDir, 2*time.Minute, progress.File(), "rollback-config-generate", nil, filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
		progress.Write("  Regenerating configuration for the previous version ... failed (continuing): %v", err)
	} else {
		progress.Write("  Regenerating configuration for the previous version ... ok")
	}

	// Restore database backup. Now safe — git state matches the DB era. A
	// non-nil error means the rsync restore was attempted and FAILED, leaving
	// the volume inconsistent → the terminal row must record `failed` (degraded),
	// not `rolled_back`.
	dbRestoreErr := d.restoreDatabase(progress, backupPath)

	// Harness-only kill site (C9): simulates the OS / orchestrator killing
	// the process MID-ROLLBACK — specifically, after the destructive
	// restore steps (restoreGitState, restoreBinary, restoreDatabase) have
	// run but BEFORE the docker compose up + reconnect + setMaintenance
	// + state='rolled_back' UPDATE land. At kill time the on-disk state
	// is consistent (OLD git tree, OLD binary, OLD DB volume) but the
	// services are still stopped, maintenance is still ON, and the
	// upgrade row is still 'in_progress'.
	//
	// Recovery via the next recovery pass (service restart or ./sb
	// install): the flag survives the kill (Phase PostSwap or Resuming).
	// Observed state (STATBUS-039) sees the restored OLD state — for a
	// Resuming flag the verdict is confirmed-behind (binary/migrations
	// rolled back below target) → the one-shot rollback path re-runs the
	// remaining reconcile: bring services up, set maintenance OFF, mark
	// the row 'rolled_back'. restoreDatabase is idempotent over an
	// already-restored volume.
	//
	// Reachability — TWO reach-paths to d.rollback() (hence to this site):
	//   • PreSwap flag (e.g. a binary-swap kill): recoverFromFlag PreSwap →
	//     recoveryRollback → d.rollback() UNCONDITIONALLY (no forward attempt),
	//     so this site fires DETERMINISTICALLY. (Arc: rollback-kill, proven.)
	//   • Resuming/PostSwap flag: d.rollback() is reached only on a POSITIVELY-
	//     behind verdict (STATBUS-039: already-at-new and unverifiable failures retry
	//     forward and never reach here). Via THIS path the site fires only when
	//     forward-recovery NATURALLY fails — non-deterministic across the HEAD
	//     migration set (legacy 4-rollback-kill documented it as that diagnostic).
	// No-op in production. Drives scenario 4-rollback-kill.
	inject.KillHere("killed-by-system-during-builtin-rollback")

	// Start with old config — git is verified at restoreTargetSHA. A failure
	// here means the old-version services would not come back up → degraded,
	// recorded as `failed` below.
	servicesStart := time.Now()
	servicesUpErr := runCommandToLog(projDir, 5*time.Minute, progress.File(), "rollback-docker-up", nil, "docker", "compose", "--profile", "all", "up", "-d", "--remove-orphans")
	if servicesUpErr != nil {
		progress.Write("  Starting services for the previous version ... failed: %v", servicesUpErr)
	} else {
		progress.Write("  Starting services for the previous version ... ok (%s)", formatProgressDuration(time.Since(servicesStart), false))
	}

	// Wait for the restored DB to accept connections BEFORE reconnecting: the
	// restart above brings Postgres back and an immediate reconnect would race
	// it coming ready (the scenario 2-preswap-backup-kill "connection reset by peer"). Mirrors
	// applyNewSbUpgrading's post-restart waitForDBHealth on the normal path. This is
	// the PRIMARY wait — writeRollbackTerminal's bounded retry below is the
	// durable fallback. Log-not-raise: if the DB genuinely never returns, the
	// wait elapses, the reconnect + terminal write fail, and the flag is KEPT
	// for next-boot reconciliation (a degraded outcome already recorded failed).
	dbHealthStart := time.Now()
	dbHealthErr := d.waitForDBHealth(30 * time.Second)
	if dbHealthErr != nil {
		progress.Write("  Waiting for the restored database to become healthy ... failed after 30s: %v", dbHealthErr)
	} else {
		progress.Write("  Waiting for the restored database to become healthy ... healthy (%s)", formatProgressDuration(time.Since(dbHealthStart), false))
	}

	// Reconnect (may fail if DB didn't come back)
	reconnectErr := d.reconnect(ctx)
	if reconnectErr != nil {
		progress.Write("  Reconnecting to the restored database ... failed: %v", reconnectErr)
	} else {
		progress.Write("  Reconnecting to the restored database ... ok")
	}

	// Persist the real failure reason in `error` (short, one-line). The
	// full narrative lives in the on-disk log (referenced by
	// log_relative_file_path) and is fetched by the admin UI's "Log"
	// collapsible via /upgrade-logs/<name>.
	errMsg := reason
	if reason == "" {
		errMsg = "Rollback completed (no reason captured — caller did not pass one)"
	}
	// Two-tier terminal (upgrade-timeline.md § Complete / rollback). The restore
	// steps above are best-effort and log-not-raise, so a degraded outcome must be
	// detected HERE: if any required restoration boundary failed, the box is NOT
	// "running normally on the old version" — record `failed` (degraded; manual
	// recovery), never `rolled_back`. Recording
	// rolled_back on a degraded box is the silent-operator-lie the codebase forbids
	// (rolled_back's contract is "running normally on old version, no manual
	// intervention"). (restoreBinary failure is excluded: ./sb being stale is
	// self-healed by the staleness guard on the next invocation; the site's
	// containers serve old code from the restored git tree, so it stays healthy.)
	restoreErrors := rollbackCompletionErrors{
		databaseRestore: dbRestoreErr,
		servicesStart:   servicesUpErr,
		databaseHealth:  dbHealthErr,
		reconnect:       reconnectErr,
	}
	// Bundle BEFORE the terminal UPDATE so a support ticket on the row has the
	// sibling .bundle.txt available.
	d.writeDiagnosticBundle(ctx, id, progress)

	if restoreErrors.degraded() {
		detail := ""
		for _, failure := range restoreErrors.details() {
			detail += "; " + failure
		}
		errMsg = errMsg + " — ROLLBACK INCOMPLETE" + detail + ". The system is in a degraded state; manual CLI recovery is required (./sb install); contact SSB support and involve your IT staff."
		// Durable terminal write with bounded retry + reconnect. removeUpgradeFlag
		// ONLY on success: if the write never landed, KEEP the flag so the next
		// boot's recoverFromFlag / completeInProgressUpgrade reconciles the row
		// (writeRollbackTerminal has already failed loud). The degraded siren below
		// fires regardless — the box IS degraded whether or not the row write landed.
		if d.writeRollbackTerminal(id,
			"UPDATE public.upgrade SET state = 'failed', error = $1, recovery_attempts = $2"+terminalBackupPathSQL+" WHERE id = $3"+upgradeRowReturning,
			errMsg, LabelFailedRollbackIncomplete, attemptsAtCall) {
			if removeErr := d.removeUpgradeFlag(); removeErr != nil {
				progress.Write("  Releasing upgrade lock after the incomplete rollback ... failed: %v", removeErr)
			}
		} else {
			d.releaseUpgradeFlagLockKeepingFile()
		}
		// Page on-call: the degraded/all-hands tier (siren), same signal as the
		// git-restore ABORT path.
		hostname, _ := os.Hostname()
		d.runCallback(version, map[string]string{
			"STATBUS_EVENT":           "rollback_failed", // STATBUS-137 (LabelFailedRollbackIncomplete)
			"STATBUS_ROLLBACK_FAILED": "1",
			"STATBUS_ROLLBACK_ERROR":  errMsg,
			"STATBUS_RECOVERY_CMD":    fmt.Sprintf(`ssh %s "cd statbus && ./sb install"`, hostname),
		})
		progress.Write("Recording rollback completion ... failed; the system remains degraded and requires manual recovery.")
		return true
	}

	// The snapshot restore and service health boundaries are now confirmed. Write
	// the cleanup-only discriminator BEFORE reopening SQL or HTTP. From this point
	// forward, every restart/install path is forbidden from restoring the snapshot
	// again, so writes accepted after the window lifts cannot be overwritten.
	if !d.writeRollbackTerminal(id,
		"UPDATE public.upgrade SET state = 'failed', error = $1, recovery_attempts = $2, rollback_finish_pending_at = now()"+terminalBackupPathSQL+" WHERE id = $3"+upgradeRowReturning,
		errMsg, LabelFailedRollbackPendingFinish, attemptsAtCall) {
		d.releaseUpgradeFlagLockKeepingFile()
		progress.Write("Recording rollback finishing state ... failed; maintenance and SQL read-only remain active, and the free recovery marker is kept for reconciliation.")
		return true
	}

	reportFinishingPending := func(detail string) {
		d.releaseUpgradeFlagLockKeepingFile()
		d.markTerminal("ROLLBACK_FINISHING_PENDING", fmt.Sprintf("id=%d; %s", id, detail))
		d.runCallback(version, map[string]string{
			"STATBUS_EVENT":           "rollback_failed",
			"STATBUS_ROLLBACK_FAILED": "1",
			"STATBUS_ROLLBACK_ERROR":  detail,
		})
		progress.Write("Rollback restored the previous version, but finishing did not complete; cleanup will retry without restoring the database again.")
	}

	// Lift SQL first while HTTP maintenance still shields browser/API traffic. The
	// pending row already makes direct-DB writes safe: no path may restore again.
	readOnlyStatement, readOnlyErr := d.liftReadOnlyWindow("rollback completion")
	if readOnlyErr != nil {
		fmt.Fprintf(os.Stderr,
			"INVARIANT ROLLBACK_READ_ONLY_WINDOW_LIFTED violated: the read-only window did not lift after rollback after %d attempts (err=%v) — maintenance remains active and cleanup will retry without restoring the database again. (service.go:%d, pid=%d)\n",
			terminalWriteMaxAttempts, readOnlyErr, thisLine(), os.Getpid())
		d.markTerminal("ROLLBACK_READ_ONLY_WINDOW_LIFTED",
			fmt.Sprintf("window OFF flip failed after rollback after retries: %v; maintenance remains active; cleanup-only retry required", readOnlyErr))
		progress.Write("  Unblocking SQL writes ... failed: %v", readOnlyErr)
		reportFinishingPending(fmt.Sprintf("rollback restored the previous version, but SQL writes remain blocked (%v)", readOnlyErr))
		return true
	}
	progress.Write("  Unblocking SQL writes ... ok")
	progress.Write("    ran: %s", readOnlyStatement)

	maintenanceErr := d.setMaintenance(false, "")
	if maintenanceErr != nil {
		progress.Write("  Lifting maintenance mode ... failed: %v", maintenanceErr)
		reportFinishingPending(fmt.Sprintf("rollback restored the previous version and SQL writes are enabled, but HTTP maintenance did not lift (%v)", maintenanceErr))
		return true
	}
	progress.Write("  Lifting maintenance mode ... ok")
	progress.Write("    removed: %s", homeRelativePath(maintenanceFlagHostPath()))

	finalized, finalErr := d.finalizePendingRollback(ctx, id, LabelRolledBackNormal)
	if finalErr != nil {
		progress.Write("  Releasing the upgrade marker and recording completed rollback guidance ... failed: %v", finalErr)
		reportFinishingPending(fmt.Sprintf("rollback restored the previous version, but marker/database finalization failed (%v)", finalErr))
		return true
	}
	if !finalized {
		reportFinishingPending("rollback finishing row changed before finalization; refusing to claim healthy completion")
		return true
	}
	progress.Write("Rollback to the previous version complete.")
	return false
}

// preRestoreStopServices is the service set both pre-restore stop sites
// (ReattemptRestore, rollback()'s normal path) shut down before touching
// the database volume — a single object feeds both the `docker compose
// stop` args and the compose.VerifyStopped call at each site, so the two
// sets cannot drift apart (STATBUS-187 fix unit #2).
var preRestoreStopServices = []string{"app", "worker", "rest", "db"}

// preRestoreStopVerifyBudget bounds compose.VerifyStopped's re-check
// polling: covers `docker compose stop`'s default 10s SIGTERM grace with
// margin, while still forcing a hung dockerd to reach the caller's ABORT
// / error path rather than block forever.
const preRestoreStopVerifyBudget = 30 * time.Second

// ReattemptRestore replays the DB-snapshot restore for a restore-broke row
// (state='failed' with a retained backup_path) — the STATBUS-111 human-gated
// re-attempt driven from `./sb install` (dispatchInstallState → here). On the
// restore-broke path the original rollback's restore broke mid-way (rsync
// failure or two crash-deaths), leaving state='failed' + backup_path set while
// git + binary are already at the old era. This re-runs the idempotent restore
// TAIL (restoreAndFinalize) under the SAME always-ping watchdog cover rollback()
// uses, and returns:
//   - nil   → the restore completed; the row is now rolled_back (healthy at the
//     old version). The caller prints the success + forecast line.
//   - error → the restore degraded again (row stays failed); actionable error.
//
// Human-gated (AC#2): this runs ONLY from the install ladder. The systemd
// service's RecoverFromFlag keys on the flag file, which the restore-broke path
// removed — so the service never auto-re-attempts (no StartLimit thrash).
// Caller must have a connected d.queryConn (LoadConfigAndConnect).
func (d *Service) ReattemptRestore(ctx context.Context, rowID int64, backupPath string) error {
	// Load the row's commit label for the callback + progress continuity, AND
	// its recovery_attempts (STATBUS-181). Runs before the db stop below — the
	// restore-broke box has the DB reachable. recovery_attempts must be
	// captured HERE, in memory, because restoreAndFinalize's restoreDatabase
	// rewinds the volume to the pre-upgrade snapshot (attempts=0 there); the
	// terminal UPDATE that follows only re-imposes state/error/timestamps, so
	// without this capture the audit-trail value is silently erased by the
	// volume rewind (found live, arc run 29325230294: 3 → 0).
	var commitSHA, commitVersion sql.NullString
	var attemptsAtCall int
	if err := d.queryConn.QueryRow(ctx,
		"SELECT commit_sha, commit_version, recovery_attempts FROM public.upgrade WHERE id = $1", rowID).
		Scan(&commitSHA, &commitVersion, &attemptsAtCall); err != nil {
		return fmt.Errorf("ReattemptRestore: cannot load upgrade %d: %w", rowID, err)
	}
	displayName := commitVersion.String
	if displayName == "" {
		displayName = renderDisplayName(CommitSHA(commitSHA.String), nil)
	}

	// Append to the row's log so the restore narrative stays continuous; fall
	// through to a fresh log if the original is gone.
	progress := AppendProgressLog(d.projDir, d.loadLogRelPath(ctx, rowID))
	if progress == nil {
		progress = NewUpgradeLog(d.projDir, rowID, displayName, time.Now().UTC())
	}
	defer progress.Close()
	progress.Write("Re-attempting the interrupted database restore for %s:", displayName)

	// Watchdog cover — the SAME always-ping ticker rollback() arms, because
	// restoreAndFinalize runs the two heartbeat-silent steps (the whole-volume
	// rsync + the docker-up). restoreAndFinalize arms none itself (PIN 1: the
	// cover is caller-owned), so without this a >120s restore trips WatchdogSec.
	tickerCtx, tickerCancel := context.WithCancel(ctx)
	tickerDone := make(chan struct{})
	go runGatedWatchdogTicker(tickerCtx, nil,
		applyNewSbUpgradingStallThreshold, applyNewSbUpgradingWatchdogCadence,
		func() { sdNotify("WATCHDOG=1") }, tickerDone)
	defer func() { tickerCancel(); <-tickerDone }()

	// Restore git state FIRST (architect review of STATBUS-111). The re-attempt
	// probe also matches the git-restore ABORT row (LabelFailedAbort — the tree
	// is corrupt), and restoreAndFinalize only touches binary + DB. Without this,
	// an abort-row re-attempt would restore binary + DB to the old era while the
	// git tree stayed at the abort's wreckage → config generate against corrupt
	// templates → the box comes up MIXED-ERA. Empty target = the STATBUS-077
	// pinned pre-upgrade branch (single source), same call shape as rollback()'s
	// head. On the common PAIR-TERMINAL row git is already at the old era →
	// idempotent no-op; on an ABORT row this either genuinely cures the original
	// failure (e.g. transient disk pressure since cleared) or hard-fails
	// ACTIONABLY here — BEFORE any destructive stop/restore, never mixed-era.
	if err := d.restoreGitState("", progress); err != nil {
		return fmt.Errorf("%s: cannot restore the working tree before the database re-attempt (%w) — the git tree is corrupt; do NOT proceed. Manual recovery required: contact SSB support and involve your IT staff%s",
			ErrRollbackGitCorrupt, err, contactSuffix(readAdministratorContact(d.projDir)))
	}

	// Stop clients + db before rsyncing the volume (restoreAndFinalize's
	// docker-up brings them back). Mirrors rollback()'s pre-restore stop.
	//
	// STATBUS-187 fix unit #2: capture the stop error AND positively verify
	// every service is actually down before the rsync — this is STATBUS-111's
	// own restore-broke re-attempt path, and a torn-restore under a still-live
	// postgres is a real data-corruption pathway, not a cosmetic gap.
	if err := runCommand(d.projDir, "docker", append([]string{"compose", "stop"}, preRestoreStopServices...)...); err != nil {
		return fmt.Errorf("%s: stop services before database re-attempt: %w", ErrRollbackServicesNotStopped, err)
	}
	if err := compose.VerifyStopped(d.projDir, preRestoreStopServices, preRestoreStopVerifyBudget); err != nil {
		return fmt.Errorf("%s: %w", ErrRollbackServicesNotStopped, err)
	}

	reason := fmt.Sprintf("operator re-attempt of the interrupted restore for %s", displayName)
	if degraded := d.restoreAndFinalize(ctx, int(rowID), displayName, reason, backupPath, attemptsAtCall, progress); degraded {
		return fmt.Errorf("%s: the database restore did not complete — the system remains degraded; contact SSB support and involve your IT staff", ErrRollbackDBRestore)
	}
	return nil
}

// rollbackRecoveryAttempts captures the audit counter before a volume restore.
// It is deliberately nil-safe: executeUpgrade closes queryConn before the DB
// stop, which is the exact Norway rc.02 state. The terminal path can continue
// with zero and later writes through its fresh teardown-immune connection.
func (d *Service) rollbackRecoveryAttempts(ctx context.Context, id int) int {
	var attempts int
	if d.queryConn == nil {
		log.Printf("rollback: query connection already closed for upgrade %d - skipping recovery_attempts read and re-imposing 0", id)
		return 0
	}
	if err := d.queryConn.QueryRow(ctx, "SELECT recovery_attempts FROM public.upgrade WHERE id = $1", id).Scan(&attempts); err != nil {
		log.Printf("rollback: could not read recovery_attempts for %d before the restore (%v) - re-imposing 0", id, err)
		return 0
	}
	return attempts
}

func (d *Service) rollback(ctx context.Context, id int, version, restoreTargetSHA, reason string, backupPath string, progress *ProgressLog) {
	// WATCHDOG COVER (STATBUS-031). rollback()'s body runs the two DB-size-scaled,
	// heartbeat-SILENT steps an upgrade has: restoreDatabase's whole-volume rsync
	// (exec.go, onAdvance=nil → output bypasses the heartbeat) and the rollback
	// docker-up (5m, onAdvance=nil). On the STARTUP recovery path (recoverFromFlag →
	// recoveryRollback → here) NO watchdog ticker is armed; on the execute path the
	// applyNewSbUpgrading gated ticker closes its gate after applyNewSbUpgradingStallThreshold of
	// rsync silence — so either way a >120s restore (Norway 32 GB ⇒ guaranteed) gets
	// the unit SIGABRT'd mid-restore. Because the flag is removed only AFTER the
	// restore completes, the next boot restores from scratch and is killed again — an
	// indefinite restore loop on the recovery path itself. Wrap the whole body in the
	// same always-ping bounded ticker the two migrate sites use (nil progress = ping
	// unconditionally; the stall arg is inert under nil, passed for signature parity).
	// The hang-bound is each inner command's own timeout (RestoreDBTimeout on the
	// rsync, 5m on docker-up), NOT WatchdogSec — identical tradeoff to the boot-migrate
	// cover: the 120s WatchdogSec was a FALSE kill of a slow-but-progressing restore.
	// Safe to land now: STATBUS-039's identity-keyed restore means a completing
	// (covered) restore is always THIS upgrade's own snapshot, never a silent-loss
	// amplifier. rollback() always terminates via os.Exit (ABORT=1, terminal=75),
	// which reaps this goroutine by process death — so the watchdog is fed right up to
	// exit; the deferred cancel+join is insurance for any future early-return path
	// (os.Exit bypasses defers; a `return` would not).
	rollbackTickerCtx, rollbackTickerCancel := context.WithCancel(ctx)
	rollbackTickerDone := make(chan struct{})
	go runGatedWatchdogTicker(rollbackTickerCtx, nil,
		applyNewSbUpgradingStallThreshold, applyNewSbUpgradingWatchdogCadence,
		func() { sdNotify("WATCHDOG=1") }, rollbackTickerDone)
	defer func() { rollbackTickerCancel(); <-rollbackTickerDone }()

	progress.Write("Rolling back to the previous version:")
	progress.Write("  Cause: %s", reason)
	// STATBUS-338, Norway rc.02: persist the cause before rollback touches any
	// connection or process state. If this rollback itself dies, PreSwap recovery
	// can report the returned git error instead of manufacturing a precondition
	// failure on the next boot.
	if err := d.recordOriginalError(reason); err != nil {
		log.Printf("rollback: could not persist original error in the held flag: %v (continuing with the in-memory error)", err)
	}

	projDir := d.projDir

	// STATBUS-181: capture recovery_attempts BEFORE any destructive step —
	// restoreDatabase below (via restoreAndFinalize, or directly in the ABORT
	// branch) rewinds the volume to the pre-upgrade snapshot, where the column
	// reads whatever it was before this upgrade ran (typically 0); the
	// terminal write that follows only re-imposes state/error/timestamps, so
	// without this capture the value is silently erased by the rewind (found
	// live, arc run 29325230294: 3 → 0). Best-effort: on read failure, 0 is
	// re-imposed — the same value a rollback with no prior recovery pass
	// would carry anyway (the common, non-recovery-triggered case).
	// Norway rc.02 reached this line after executeUpgrade had deliberately closed
	// and nilled queryConn for the consistent backup. The attempts read is audit
	// enrichment, not permission to roll back; when the DB connection is gone,
	// skip it cleanly. restoreAndFinalize later starts/reconnects the DB and the
	// teardown-immune terminal writer persists `reason` through a fresh connection.
	attemptsAtCall := d.rollbackRecoveryAttempts(ctx, id)

	// Capture failure-time container logs BEFORE the docker compose stop
	// destroys the running containers. The rollback later does
	// `docker compose up -d --remove-orphans` which recreates fresh
	// containers — without this snapshot, the REST 5xx body, db
	// startup output, and app connection-attempt logs that explain
	// the failure are gone forever.
	captureContainerLogs(projDir, progress, []string{"rest", "app", "worker", "db"})

	// Stop everything before we touch the git tree or restore the DB.
	//
	// STATBUS-187 fix unit #2: capture the stop error AND positively verify
	// every service is actually down before any restore below — a torn
	// restore under a still-live postgres is a real data-corruption
	// pathway, not a cosmetic gap. Both failure modes route to the SAME
	// ABORT shape the git-corrupt branch below uses (no restore attempted
	// yet, so nothing to unwind): bundle, callback, bring DB up so the
	// terminal write can land, terminal write, exit — never proceed to
	// restoreGitState/restoreDatabase on an unconfirmed stop.
	stopErr := runCommand(projDir, "docker", append([]string{"compose", "stop"}, preRestoreStopServices...)...)
	if stopErr == nil {
		stopErr = compose.VerifyStopped(projDir, preRestoreStopServices, preRestoreStopVerifyBudget)
	}
	if stopErr != nil {
		progress.Write("  Stopping services before restore ... failed: %v", stopErr)
		fmt.Fprintf(os.Stderr, "ABORT: rollback refused — %v\n", stopErr)

		rollbackFailedMsg := fmt.Sprintf("%s: %v (originally: %s) — ROLLBACK FAILED; the system is in a degraded state. Manual CLI recovery is required (./sb install); contact SSB support and involve your IT staff.", ErrRollbackServicesNotStopped, stopErr, reason)
		// Bundle BEFORE the ABORT UPDATE so a forensic inspection of a wedged
		// `failed` row has the sibling .bundle.txt (mirrors the git-corrupt
		// ABORT branch below).
		d.writeDiagnosticBundle(ctx, id, progress)
		hostname, _ := os.Hostname()
		d.runCallback(version, map[string]string{
			"STATBUS_EVENT":           "rollback_aborted",
			"STATBUS_ROLLBACK_FAILED": "1",
			"STATBUS_ROLLBACK_ERROR":  stopErr.Error(),
			"STATBUS_RECOVERY_CMD":    fmt.Sprintf(`ssh %s "cd statbus && ./sb install"`, hostname),
		})
		// STATBUS-136: bring the DB back up BEFORE the terminal write, same
		// reasoning as the git-corrupt ABORT branch below — some services in
		// preRestoreStopServices may genuinely be down (only the ones named
		// in stopErr are confirmed still running), so the terminal write can
		// still hit a stopped DB.
		if err := d.EnsureDBReachable(ctx); err != nil {
			if startErr := d.StartDBForRecovery(ctx); startErr != nil {
				progress.Write("  Starting the existing database to record the rollback outcome ... failed: %v", startErr)
			} else if reachErr := d.EnsureDBReachable(ctx); reachErr != nil {
				progress.Write("  Starting the existing database to record the rollback outcome ... failed health check: %v", reachErr)
			} else {
				progress.Write("  Starting the existing database to record the rollback outcome ... healthy")
			}
		}
		progress.Write("Manual recovery required:")
		progress.Write("    1. Investigate why `docker compose stop` did not stop every service: docker compose ps -a")
		progress.Write("    2. Stop the remaining service(s) manually, then decide whether to retry: ./sb install")
		progress.Write("CATASTROPHIC FAILURE [%s]. Services stopped. Contact your administrator%s.",
			ErrRollbackServicesNotStopped, contactSuffix(readAdministratorContact(d.projDir)))
		if d.writeRollbackTerminal(id,
			"UPDATE public.upgrade SET state = 'failed', error = $1, recovery_attempts = $2"+terminalBackupPathSQL+" WHERE id = $3"+upgradeRowReturning,
			rollbackFailedMsg, LabelFailedAbortServicesLive, attemptsAtCall) {
			_ = d.removeUpgradeFlag()
		}
		progress.Close()
		os.Exit(1)
	}

	// STATBUS-197 C2 — THE NO-TOUCH GUARD. backupPath == "" means this attempt died BEFORE its
	// snapshot committed (C1 records backup_path at the commit moment, and every destructive
	// step — the recovery-boot checkout, the binary swap, migrations — sits AFTER it), so
	// NOTHING moved on ANY axis. Restoring git/binary here would check out the standing
	// `pre-upgrade` pin and install ./sb.old — both belong to a PRIOR attempt (one version
	// back) — moving the box to a version no one asked for while the DB stays current: the
	// mixed-era class. So skip BOTH the git restore and the binary restore (the DB leg already
	// refuses on "" — restoreDatabase, exec.go). Keep the full tail (compose up, reconnect,
	// terminal write, maintenance off, window lift) so the box returns to service at the
	// untouched source and 'rolled_back' lands honestly. This one identity key covers W1
	// (claim→commit stale pin, flagless heal), W2 (commit-window PreSwap recovery), AND the
	// first-upgrade no-pin CATASTROPHIC abort (this guard precedes the git-restore error branch).
	//
	// When backupPath != "": restore git state as before. An empty/unresolvable restoreTargetSHA
	// falls back to the pinned `pre-upgrade` branch inside restoreGitStateFn — which is now
	// identity-correct because a committed snapshot proves THIS attempt owns that pin. If it
	// FAILS we MUST NOT bring services up (NEW code on the just-restored OLD DB = corruption);
	// restore the DB first to keep on-disk state consistent, then ABORT before docker compose up.
	if backupPath == "" {
		progress.Write("  Checking for a committed snapshot ... ok (none recorded; source code and ./sb remain unchanged)")
	} else if err := d.restoreGitState(restoreTargetSHA, progress); err != nil {
		progress.Write("  Restoring source code ... failed: %v", err)
		// STATBUS-187 fix unit #1 (second wave, architect-ruled: "fix =
		// capture + fold into the ABORT error string"): capture the ABORT
		// branch's OWN restoreDatabase outcome (confirmed present and
		// load-bearing this session, STATBUS-181) and fold it into
		// rollbackFailedMsg + the progress log below, so support sees the
		// WHOLE story — git restore failed AND whether the DB-side restore
		// also failed — not just the generic ROLLBACK_FAILED_GIT_CORRUPT the
		// message already names. Same tier/code/label/callback-event/exit as
		// before; only the message is enriched.
		dbRestoreErr := d.restoreDatabase(progress, backupPath)
		dbRestoreOutcome := "succeeded"
		if dbRestoreErr != nil {
			dbRestoreOutcome = fmt.Sprintf("ALSO FAILED: %v", dbRestoreErr)
			progress.Write("  Restoring the database after the source-code failure ... failed: %v", dbRestoreErr)
		} else {
			progress.Write("  Restoring the database after the source-code failure ... ok")
		}
		// Restore ./sb to match the attempted-but-failed git era so the
		// operator's `./sb` at least stops being the NEW (mismatched)
		// binary. Best-effort: if it fails, we log ErrRollbackBinaryCorrupt
		// and move on — the ABORT headline below already escalates.
		d.restoreBinary(progress)
		// restoreTargetSHA may be empty here (the abort means neither it nor the
		// pinned `pre-upgrade` branch resolved); point the operator at the
		// recorded version if set, else the `pre-upgrade` fallback ref.
		restoreTarget := restoreTargetSHA
		if restoreTarget == "" {
			restoreTarget = "pre-upgrade"
		}
		progress.Write("Manual recovery required:")
		progress.Write("    1. Manually checkout the previous version: git checkout %s", restoreTarget)
		progress.Write("    2. Regenerate config: ./sb config generate")
		progress.Write("    3. Bring services up: docker compose --profile all up -d")
		progress.Write("    4. Re-run ./sb install — it detects the stale flag and reconciles the upgrade row automatically.")
		// Headline for the operator reading maintenance.html — the four
		// lines above are the technical recovery trail for an admin
		// reviewing service logs; this one sentence is what a
		// non-technical operator sees as the last (and biggest) line on
		// the maintenance screen. Keep the error code + contact so the
		// operator can escalate with a concrete identifier.
		progress.Write("CATASTROPHIC FAILURE [%s]. Services stopped. Contact your administrator%s.",
			ErrRollbackGitCorrupt, contactSuffix(readAdministratorContact(d.projDir)))
		fmt.Fprintf(os.Stderr, "ABORT: rollback git restore to %s failed: %v\n", restoreTargetSHA, err)

		// state=failed, NOT rolled_back: the git restore itself failed, so
		// services are stopped and maintenance is ON — the box is DOWN, not
		// "healthy at the old version". rolled_back's contract (no manual
		// intervention needed) would be a silent operator lie to monitoring/UI.
		// failed is valid here (started_at is set, no rolled_back_at). See
		// upgrade-timeline.md § Complete / rollback.
		rollbackFailedMsg := fmt.Sprintf("%s: %v (originally: %s) — ROLLBACK FAILED; the system is in a degraded state. Manual CLI recovery is required (./sb install); contact SSB support and involve your IT staff. Database restore %s.", ErrRollbackGitCorrupt, err, reason, dbRestoreOutcome)
		// Bundle BEFORE the ABORT UPDATE so a forensic inspection of
		// a wedged `failed` row has the sibling .bundle.txt.
		d.writeDiagnosticBundle(ctx, id, progress)
		// Page on-call via the configured callback (Slack, etc.) — the box is
		// DOWN, so the siren fires regardless of whether the terminal write lands.
		// extraEnv tells the script to render a distinctive rollback-failure alert
		// with the recovery command body.
		hostname, _ := os.Hostname()
		d.runCallback(version, map[string]string{
			"STATBUS_EVENT":           "rollback_aborted", // STATBUS-137 (LabelFailedAbort — mirrors the label; 'restore-broke' is doctrine vocabulary for the pair-terminal, which lands under rollback_failed)
			"STATBUS_ROLLBACK_FAILED": "1",
			"STATBUS_ROLLBACK_ERROR":  err.Error(),
			"STATBUS_RECOVERY_CMD":    fmt.Sprintf(`ssh %s "cd statbus && ./sb install"`, hostname),
		})
		// STATBUS-136: bring the DB back up BEFORE the terminal write. The write
		// below records state='failed' into public.upgrade, but every service —
		// including db — was stopped for the restore (`docker compose stop … db`
		// above) and this abort branch is the one rollback path that never brings
		// them back up (unlike the normal rollback's `up -d`). So the write hit a
		// stopped DB: writeRollbackTerminal's reconnect had nothing to connect to,
		// exhausted its bounded retry, tripped INVARIANT ROLLBACK_TERMINAL_WRITE_FAILED,
		// KEPT the flag, and the process exited → systemd re-ran the whole abort →
		// a guaranteed death loop on a path that had already concluded (observed
		// live, r17 ×3). Start the EXISTING db container so the write can land.
		//
		// Asymmetric-safe: StartDBForRecovery runs `docker compose start db`, which
		// ONLY starts a stopped container — never `up -d`/recreate — so it cannot
		// swap the DB image (same primitive + argument as install crash recovery's
		// connect-first pattern, cli/cmd/install_upgrade.go). The volume already
		// holds the just-restored old snapshot; starting its own stopped container
		// touches no data. Best-effort: if the start or health-wait fails, we fall
		// through to writeRollbackTerminal's own bounded retry, which then fails
		// loud exactly as before — no regression, only the loop removed.
		if err := d.EnsureDBReachable(ctx); err != nil {
			if startErr := d.StartDBForRecovery(ctx); startErr != nil {
				progress.Write("  Starting the existing database to record the rollback outcome ... failed: %v", startErr)
			} else if reachErr := d.EnsureDBReachable(ctx); reachErr != nil {
				progress.Write("  Starting the existing database to record the rollback outcome ... failed health check: %v", reachErr)
			} else {
				progress.Write("  Starting the existing database to record the rollback outcome ... healthy")
			}
		}

		// Maintenance stays ON — operator must complete the manual rollback steps above.
		// Durable terminal write with bounded retry (same contract as the two tiers
		// below). On SUCCESS, release the flock + remove the file so the operator's
		// prescribed `./sb install` recovery proceeds (a held flock would wedge
		// install with StateLiveUpgrade). On a FAILED write, KEEP the flag: this
		// process exits below (the fd close releases the flock at the kernel level),
		// leaving a dead-PID breadcrumb so the operator's `./sb install` hits
		// StateCrashedUpgrade → RecoverFromFlag and reconciles the still in_progress
		// row instead of leaving it stuck. writeRollbackTerminal already failed loud
		// (INVARIANT ROLLBACK_TERMINAL_WRITE_FAILED + markTerminal).
		if d.writeRollbackTerminal(id,
			"UPDATE public.upgrade SET state = 'failed', error = $1, recovery_attempts = $2"+terminalBackupPathSQL+" WHERE id = $3"+upgradeRowReturning,
			rollbackFailedMsg, LabelFailedAbort, attemptsAtCall) {
			_ = d.removeUpgradeFlag()
		}

		// Exit unconditionally (rc.67 trifecta). Same reasoning as the
		// normal-rollback exit below: rollback is a process-state break,
		// the binary on disk is now different from the one in memory,
		// continuing execution would query the rolled-back schema with
		// the new binary's column expectations. Under systemd this is a
		// clean restart (Restart=always brings the restored ./sb back as
		// a fresh process); under one-shot ./sb install the operator's
		// shell exits and the next install invocation comes back fresh
		// against the restored binary. The CATASTROPHIC FAILURE banner
		// stays visible because maintenance.html's terminal marker
		// persists across restarts.
		progress.Close()
		os.Exit(1)
	}
	// STATBUS-111: the restore-through-terminal-write tail is now shared with the
	// install-driven restore re-attempt via restoreAndFinalize. Process-lifecycle
	// (os.Exit below) stays HERE per the extraction boundary — restoreAndFinalize
	// only restores and writes the terminal, then returns.
	d.restoreAndFinalize(ctx, id, version, reason, backupPath, attemptsAtCall, progress)

	// Exit 75 (sysexits EX_TEMPFAIL: "temporary failure, retry later")
	// per the rc.67 trifecta. Distinct from:
	//   - 0  : true success (no rollback ran)
	//   - 1  : catastrophic ABORT (rollback itself failed, system in
	//          undefined state — see the runtime branch above)
	//   - 42 : successful-upgrade handoff to systemd (selfUpdate)
	// install.sh branches on this code to render a "UPGRADE FAILED,
	// ROLLED BACK" banner instead of either silent success or the
	// SYSTEM UNUSABLE banner — operator instantly sees that the upgrade
	// attempt failed but the system is back at the prior known-good
	// version and the right next step is "fix the root cause, retry".
	//
	// Under systemd Restart=always cycles cleanly regardless of code; 75
	// counts toward StartLimitBurst (Item L: 10/600s), which is the
	// correct behaviour — repeated rollbacks indicate something
	// structurally wrong that warrants stopping the unit.
	progress.Close()
	os.Exit(75)
}

// restoreGitState is the *Service-bound wrapper around restoreGitStateFn,
// adapting progress.Write to the free function's plain logger.
func (d *Service) restoreGitState(previousVersion string, progress *ProgressLog) error {
	return restoreGitStateFn(d.projDir, previousVersion, func(format string, args ...interface{}) {
		progress.Write(format, args...)
	}, progress.File())
}

// restoreGitStateFn restores the git working tree at projDir to
// `previousVersion`, pre-validating that the ref resolves before touching
// the tree and post-verifying that HEAD matches the expected commit
// afterwards.
//
// Returns an error if any step fails. Callers MUST treat a non-nil
// return as "DO NOT start services on this code" — the working tree is
// in an undefined state somewhere between the new and old versions.
//
// previousVersion is a general git ref — a tag, branch, or full SHA (the
// pipeline passes a CommitSHA restore target, but the fallback below
// reassigns it to the `pre-upgrade` BRANCH, so it is not strictly a SHA).
// Whatever `git rev-parse --verify <ref>^{commit}` resolves to is the
// expected HEAD after checkout.
//
// If `previousVersion` doesn't resolve (e.g., the tag was pruned
// upstream and the local mirror dropped it), falls back to the
// `pre-upgrade` branch pinned by executeUpgrade before the destructive
// steps started — defense in depth against ref drift.
//
// Logger is invoked at narrative milestones; pass a no-op for tests.
// Free function (not a method) so the unit tests don't have to
// construct a *Service or its DB connections.
func restoreGitStateFn(projDir, previousVersion string, log func(format string, args ...interface{}), logWriter io.Writer) error {
	// STATBUS-137 rider: recoveryRollback passes previousVersion="" deliberately
	// (STATBUS-077 — the pinned pre-upgrade branch is the single source of truth).
	// Name that rather than interpolate an empty ref ("Restoring git state to ..."
	// / "Ref  does not resolve") on every rollback log. Log-only; the flow below is
	// unchanged (an empty ref fails rev-parse and falls back to pre-upgrade).
	log("  Restoring source code:")

	// Pre-validate: refuse to checkout a ref we can't resolve. If the
	// requested ref is gone, fall back to the persistent `pre-upgrade`
	// branch before erroring out.
	expectedOut, err := runCommandOutput(projDir, "git", "rev-parse", "--verify", previousVersion+"^{commit}")
	if err != nil {
		if previousVersion != "" {
			log("    Requested revision %s is unavailable; using the pinned pre-upgrade revision", previousVersion)
		}
		fallbackOut, fallbackErr := runCommandOutput(projDir, "git", "rev-parse", "--verify", "pre-upgrade^{commit}")
		if fallbackErr != nil {
			return fmt.Errorf("neither %s nor pre-upgrade resolves: %v / %v", previousVersion, err, fallbackErr)
		}
		expectedOut = fallbackOut
		previousVersion = "pre-upgrade"
	}
	expectedSHA := strings.TrimSpace(expectedOut)
	if expectedSHA == "" {
		return fmt.Errorf("ref %s resolved to empty SHA", previousVersion)
	}

	// Force checkout — discards any local changes. We're rolling back from
	// a partial upgrade, so any working-tree mutations are by definition
	// part of the failure we're undoing.
	if err := runCommandToLog(projDir, 5*time.Minute, logWriter, "rollback-git-checkout", nil, "git", "-c", "advice.detachedHead=false", "checkout", "-f", previousVersion); err != nil {
		return fmt.Errorf("git checkout -f %s: %w", previousVersion, err)
	}

	// Post-verify: HEAD must match what we resolved upfront. Belt-and-
	// suspenders against a checkout that "succeeded" but landed on the
	// wrong commit (e.g., refspec pointing somewhere unexpected).
	headOut, err := runCommandOutput(projDir, "git", "rev-parse", "HEAD")
	if err != nil {
		return fmt.Errorf("post-checkout git rev-parse HEAD: %w", err)
	}
	headSHA := strings.TrimSpace(headOut)
	if headSHA != expectedSHA {
		return fmt.Errorf("git checkout landed on %s, expected %s", ShortForDisplay(headSHA), ShortForDisplay(expectedSHA))
	}

	log("    Restoring the working tree to %s ... ok", previousVersion)
	log("      HEAD: %s", ShortForDisplay(headSHA))
	return nil
}

// replaceBinaryOnDisk swaps ./sb for the release binary matching `version`.
//
// Called mid-flow in executeUpgrade (between git checkout and the post-swap
// handoff). Tagged-release path: source is the GitHub release manifest.
// Edge-commit path uses buildBinaryOnDisk instead. Both produce a fresh
// ./sb on disk so the post-swap process (handed off via exit-42 or exec)
// runs the NEW compiled Go code — not just the new templates/SQL pulled
// in by the git checkout. This closes the rc.6→rc.7 class of bug where
// template-level fixes landed but the binary still ran old Go against them.
//
// Does NOT self-replace the running upgrade-service process; that happens
// via the explicit handoff in executeUpgrade (os.Exit(42) under systemd,
// syscall.Exec inline).
//
// Errors when no binary exists for the current platform — the pre-flight
// check should have caught this, but defense-in-depth catches late changes.
func (d *Service) replaceBinaryOnDisk(version string, progress *ProgressLog) error {
	manifest, err := FetchManifest(version)
	if err != nil {
		return fmt.Errorf("fetch manifest for %s: %w", version, err)
	}
	platform := selfupdate.Platform()
	binary, ok := manifest.Binaries[platform]
	if !ok {
		return fmt.Errorf("no binary for platform %s in release %s", platform, version)
	}
	sbPath := filepath.Join(d.projDir, "sb")
	// STATBUS-171: pass the target commit so the new binary's self-verify asserts
	// its own identity against the TARGET, not the STATBUS-060 deferred-source worktree.
	if err := selfupdate.ReplaceBinaryOnDisk(sbPath, binary.URL, binary.SHA256, manifest.CommitSHA); err != nil {
		return err
	}
	progress.Write("  Replacing ./sb with the %s binary (./sb.old kept for rollback) ... ok", version)
	return nil
}

// buildBinaryOnDisk FETCHES ./sb from the commit-tagged statbus-sb image
// (ghcr.io/statisticsnorway/statbus-sb:<commit_short>, built and pushed by CI
// in images.yaml on every master push) and swaps it in, mirroring
// replaceBinaryOnDisk for tagged releases. Called mid-flow in executeUpgrade
// for edge commits, where no GitHub release artifact exists — but the
// commit-tagged image always does (a release tag merely points at a master
// commit whose image already built).
//
// Image extraction (procureSbFromImage), NOT `make`: this removes the host
// Go/make toolchain requirement entirely — the point of the change. It
// mirrors `./sb db seed fetch` (cli/cmd/seed.go extractSeedFromImage):
// docker create (records the distroless ENTRYPOINT, runs nothing) + docker
// cp /sb. The commit_short is derived from commitSHA via `git rev-parse
// --short=8`, NOT from the working tree, so it is correct regardless of what
// HEAD is currently checked out.
//
// Atomicity: rename ./sb → ./sb.old, then procureSbFromImage writes the new
// ./sb. There is a brief window between the .old rename and the docker cp
// where ./sb does not exist — safe inside the upgrade pipeline because
// maintenance mode is on, all services are stopped, and the only ./sb
// consumer is this very process which is busy doing the fetch.
//
// On failure: rename .old back to ./sb so the deploy host isn't left
// without a usable binary. The caller (executeUpgrade) then invokes
// rollback() with ErrBinaryBuildFailed.
//
// Pre-staged-binary skip (task #8, scenarios 26 + 27): if ./sb on disk
// ALREADY reports the target commit (verified by parsing `./sb --version`
// and matching its 8-char hex `commit XXXXXXXX` field against
// targetCommitSHA), skip the image fetch entirely. This is the legitimate
// idempotency case for two real workflows:
//
//  1. Operator manually pre-stages ./sb (e.g. scp'd a tested binary)
//     and then schedules an upgrade for that commit. Today's fetch
//     would needlessly re-pull a binary that's already at the target.
//  2. The install-recovery harness's upload_sb_to_vm pre-stages ./sb
//     from HEAD to the VM (vm-bootstrap.sh:577) and then schedules an
//     upgrade for HEAD via the real ./sb upgrade register+schedule chain. Scenarios
//     26 + 27 (and any future post-swap scenario) reach buildBinary-
//     OnDisk; the skip lets them proceed without a published image —
//     an UNPUSHED harness HEAD has no statbus-sb:<short> image in the
//     registry, so the fetch would otherwise fail with "manifest unknown"
//     (the toolchain-free analog of the old `make: go: not found`).
//
// CORRECTNESS — the skip is exact/conservative (fail-safe = BUILD, not
// skip):
//   - Skip only when ./sb --version EXACTLY contains the literal
//     `commit <targetCommitSHA[:8]>`. Any mismatch — different commit,
//     unparseable output, "dev (UNSTAMPED)", `./sb` exec failure,
//     non-zero exit — falls through to the rebuild. A false-positive
//     skip would silently run a STALE binary as if it were the target;
//     fail-safe = build, never skip on ambiguity.
//   - The shortName fallback (when displayName is the 8-char shortSHA
//     and targetCommitSHA is unavailable) compares against displayName
//     directly — same 8-char invariant.
//
// A real edge upgrade has ./sb LAGGING the target (the daemon image and
// the disk binary are still at the PREVIOUS commit when executeUpgrade
// enters), so ./sb --version reports the OLD commit and we proceed with
// the image fetch. The skip ONLY kicks in for pre-staged or manual-swap
// workflows, exactly as intended.
//
// commitSHA may be empty in legacy call paths or test stubs — in that
// case we cannot verify the target identity, so we proceed with the
// image fetch (fail-safe).
func (d *Service) buildBinaryOnDisk(commitSHA, displayName string, progress *ProgressLog) error {
	sbPath := filepath.Join(d.projDir, "sb")
	sbOldPath := sbPath + ".old"

	if shortAt, ok := sbAlreadyAtCommit(d.projDir, sbPath, commitSHA, displayName); ok {
		progress.Write("  Verifying the pre-staged ./sb binary at commit %s ... ok", shortAt)
		return nil
	}

	if err := os.Rename(sbPath, sbOldPath); err != nil {
		return fmt.Errorf("preserve ./sb.old: %w", err)
	}
	if err := d.procureSbFromImage(commitSHA, displayName, sbPath, progress); err != nil {
		// Restore .old so the host still has a working ./sb after rollback.
		if rerr := os.Rename(sbOldPath, sbPath); rerr != nil {
			return fmt.Errorf("sb image fetch failed AND ./sb.old restore failed: fetch=%v restore=%v", err, rerr)
		}
		return fmt.Errorf("procure sb from image: %w", err)
	}
	progress.Write("  Replacing ./sb with the %s binary (./sb.old kept for rollback) ... ok", displayName)
	return nil
}

// procureSbFromImage replaces ./sb (at sbPath) with the statbus-sb binary for
// the target commit, extracted from the commit-tagged image
// ghcr.io/statisticsnorway/statbus-sb:<commit_short> that CI (images.yaml)
// builds and pushes on every master push. Config-free — no compose, no .env,
// no host Go/make toolchain.
//
// This function resolves commit_short locally — including the UntaggedTarget
// 8-char displayName fallback — and delegates the pull → (in-container build
// fallback) → docker create + docker cp + chmod to the shared sbimage primitive
// (cli/internal/sbimage), the same body the freshness self-heal uses. The
// in-container build fallback (gained from the shared primitive) only fires on
// a pull MISS and only when the working tree is at the target commit.
//
// commit_short is derived from commitSHA via `git rev-parse --short=8` — the
// same value CI tags with — NOT from the working tree, so it is correct
// regardless of what HEAD is checked out (a prerequisite for procuring the
// binary before the working-tree checkout). Falls back to an exactly-8-char
// displayName (the UntaggedTarget short-SHA shape) when commitSHA cannot be
// resolved.
func (d *Service) procureSbFromImage(commitSHA, displayName, sbPath string, progress *ProgressLog) error {
	short := ""
	if commitSHA != "" {
		if out, err := runCommandOutput(d.projDir, "git", "rev-parse", "--short=8", commitSHA); err == nil {
			short = strings.TrimSpace(out)
		}
	}
	if short == "" && len(displayName) == 8 {
		short = strings.ToLower(displayName)
	}
	if short == "" {
		return fmt.Errorf("cannot resolve commit_short for the statbus-sb image (commitSHA=%q, displayName=%q)",
			ShortForDisplay(commitSHA), displayName)
	}

	// Delegate the pull → (in-container build fallback) → create+cp+chmod to the
	// shared sbimage primitive (cli/internal/sbimage). Resolving commit_short
	// here — including the 8-char displayName fallback — stays local because the
	// upgrade pipeline can name the target by an UntaggedTarget short SHA when no
	// full commit_sha is available; sbimage.ProcureShort takes the resolved short
	// directly. The freshness self-heal uses sbimage.Procure (resolves short from
	// the worktree HEAD). Same body, no host Go/make toolchain.
	progress.Write("  Downloading the ./sb binary from %s:%s ...", sbimage.ImageRepo, short)
	return sbimage.ProcureShort(d.projDir, short, commitSHA, sbPath)
}

// sbAlreadyAtCommit reports whether the on-disk ./sb binary already
// carries the target commit SHA, as established by parsing its
// `--version` output. Returns (8-char-short-display, true) on a verified
// match; ("", false) on any ambiguity (parse failure, non-zero exit,
// "UNSTAMPED", mismatched commit, empty target). Fail-safe: ambiguity
// returns false so the caller proceeds with the rebuild.
//
// Strategy: invoke `./sb --version`, regex out `commit ([0-9a-fA-F]{8})`,
// compare to the lower-cased 8-char prefix of commitSHA (when non-empty)
// OR to displayName (when displayName is the 8-char short SHA used for
// UntaggedTarget — service.go:2940). Both targets are checked so the
// skip kicks in whichever the caller supplies cleanly.
//
// Why parse --version instead of adding a new `./sb commit` flag: the
// --version output is already the stable API (cli/cmd/root.go:266-274).
// Adding API surface for one internal call would expand the contract
// for a single use; parsing the existing stable shape keeps the change
// local to upgrade.
var sbVersionCommitRE = regexp.MustCompile(`commit ([0-9a-fA-F]{8})`)

func sbAlreadyAtCommit(projDir, sbPath, commitSHA, displayName string) (string, bool) {
	// Both targets unusable → cannot verify identity, fail-safe to build.
	if commitSHA == "" && displayName == "" {
		return "", false
	}
	out, err := runCommandOutput(projDir, sbPath, "--version")
	if err != nil {
		return "", false
	}
	return matchSbVersionCommit(out, commitSHA, displayName)
}

// matchSbVersionCommit is the pure parsing+comparison core extracted
// from sbAlreadyAtCommit so it can be unit-tested without a real ./sb
// subprocess. Returns (8-char-short-display, true) on a verified match
// of the version-output's `commit XXXXXXXX` field against commitSHA[:8]
// (preferred — strongest identity) or against an exactly-8-char
// displayName (fallback when only the short name is supplied). Returns
// ("", false) on every ambiguity: unparseable output, mismatched
// commit, empty targets, "UNSTAMPED". Fail-safe = false (caller builds).
//
// Invariant: a true return means the version-output literally contained
// `commit X` where X exactly equals (case-insensitive) the requested
// target prefix. Anything fuzzier returns false.
func matchSbVersionCommit(versionOut, commitSHA, displayName string) (string, bool) {
	m := sbVersionCommitRE.FindStringSubmatch(versionOut)
	if len(m) < 2 {
		return "", false
	}
	onDisk := strings.ToLower(m[1])
	// Try commitSHA[:8] first (the strongest identity; full 40-char SHA
	// is the authoritative target identity from public.upgrade).
	if commitSHA != "" && len(commitSHA) >= 8 {
		if onDisk == strings.ToLower(commitSHA[:8]) {
			return onDisk, true
		}
	}
	// displayName for UntaggedTarget is commitShort(commitSHA) = 8-char
	// short (service.go:2940). If commitSHA was empty we still match on
	// the 8-char shape exactly.
	if displayName != "" && len(displayName) == 8 {
		if onDisk == strings.ToLower(displayName) {
			return onDisk, true
		}
	}
	return "", false
}

// restoreBinary reverts ./sb from ./sb.old. Best-effort, non-fatal.
// Called from rollback() AFTER git-restore and DB-restore have run so that
// the operator's ./sb matches the restored source tree.
//
// If ./sb.old is absent, assumes the swap never happened (e.g. rollback
// fired before replaceBinaryOnDisk reached its rename step) and returns
// without touching anything.
//
// If the rename itself fails (disk full, permissions), logs with
// ErrRollbackBinaryCorrupt and returns — rollback does NOT re-raise. The
// operator's ./sb is now the new (mismatched) binary; their next
// command must be a manual `mv ./sb.old ./sb` before doing anything else.
// No separate CATASTROPHIC headline: the data-layer rollback succeeded,
// so maintenance already reflects the right state; the binary mismatch
// is a cosmetic-but-loud error in the log.
// deleteRollbackBinaryOnCompletion removes ./sb.old at a SERVE-PROVEN completion (STATBUS-197
// C3). Once EVERY completion path runs this, the invariant `./sb.old exists ⇔ an unresolved
// swap` holds — so a LATER attempt's rollback that reaches restoreBinary can only ever install
// THIS attempt's own swapped-out binary, never a predecessor's (F3's stale-binary class, which
// the first-upgrade preswap arcs never caught). Called at all three serve-proven completions
// (executeUpgrade normal, completeInProgressUpgrade flagless, resumeNewSb self-heal) — each
// resolves a real swap, so a stale .old at any of them would defeat the invariant. Best-effort:
// a leftover .old is only a latent wrong-restore risk that C2's backup-path identity guard
// already blocks, so a removal failure is logged, never fatal; os.IsNotExist is the normal case
// on a box's first-ever upgrade (no prior swap to resolve).
func (d *Service) deleteRollbackBinaryOnCompletion() {
	sbOldPath := filepath.Join(d.projDir, "sb") + ".old"
	if err := os.Remove(sbOldPath); err != nil && !os.IsNotExist(err) {
		fmt.Printf("STATBUS-197: could not delete ./sb.old at completion (%v) — a stale rollback binary may persist; C2's backup-path identity guard still prevents a wrong-version restore\n", err)
	}
}

func (d *Service) restoreBinary(progress *ProgressLog) {
	sbPath := filepath.Join(d.projDir, "sb")
	sbOldPath := sbPath + ".old"
	if _, err := os.Stat(sbOldPath); err != nil {
		// ENOENT is the legitimate "swap never happened" case — silent no-op.
		// Anything else (EPERM, EIO, ELOOP) means we can't even tell whether
		// there's a rollback candidate; log loudly so the operator can
		// investigate. Matches selfupdate.Rollback's own ENOENT handling.
		if !os.IsNotExist(err) {
			progress.Write("  Checking ./sb.old for rollback ... failed: %v", err)
		}
		return
	}
	if err := selfupdate.Rollback(sbPath); err != nil {
		progress.Write("  Restoring ./sb from ./sb.old ... failed: %v (the artifact remains at ./sb.old)", err)
		return
	}
	progress.Write("  Restoring ./sb from ./sb.old ... ok")
}

func (d *Service) selfUpdate(ctx context.Context, version string, progress *ProgressLog) {
	manifest, err := FetchManifest(version)
	if err != nil {
		progress.Write("Checking self-update assets for %s ... skipped: %v", version, err)
		return
	}

	// Skip if local code is ahead of the release (edge channel: HEAD has
	// commits beyond the tag). Prevents downgrading to an older release binary.
	if manifest.CommitSHA != "" {
		ahead, _ := runCommandOutput(d.projDir, "git", "log", "--oneline", "HEAD", "^"+manifest.CommitSHA)
		if strings.TrimSpace(ahead) != "" {
			progress.Write("Checking whether ./sb needs a self-update ... ok (local code is newer than %s)", version)
			return
		}
	}

	platform := selfupdate.Platform()
	binary, ok := manifest.Binaries[platform]
	if !ok {
		progress.Write("Checking self-update assets for %s ... skipped (no binary for %s)", version, platform)
		return
	}

	sbPath := filepath.Join(d.projDir, "sb")
	swapped, err := selfupdate.Update(sbPath, binary.URL, binary.SHA256, manifest.CommitSHA)
	if err != nil {
		msg := fmt.Sprintf("Updating ./sb to %s ... failed: %v", version, err)
		progress.Write("%s", msg)
		fmt.Fprintln(os.Stderr, msg)
		// Record in system_info so admins can see the failure. Best-effort;
		// the failure is already logged to stderr + progress above regardless.
		_ = d.execObserved(ctx, "selfUpdate: record self_update_error",
			`INSERT INTO public.system_info (key, value, updated_at) VALUES ('self_update_error', $1, now())
			 ON CONFLICT (key) DO UPDATE SET value = $1, updated_at = now()`, msg)
		return
	}

	if swapped {
		progress.Write("Updating ./sb ... ok; restarting the upgrade service ...")
	} else {
		// Mid-flow replaceBinaryOnDisk already placed the target binary;
		// end-of-flow self-update was a pure no-op. Log honestly so the
		// narrative on disk / in maintenance.html doesn't lie about what
		// just happened. Restart is still required — the running service
		// process is still holding the old binary image in memory.
		progress.Write("Checking ./sb ... already current; restarting the upgrade service ...")
	}
	progress.Close()
	// Exit 42 triggers systemd restart on the new binary. One-shot callers
	// (./sb install inline upgrade) must not exit 42 — the shell would read
	// it as failure; the install caller orchestrates unit restart itself.
	if d.runningAsService {
		os.Exit(42)
	}
}

// Runtime invariant registration for Phase 5 / Issue C — every fail-fast
// guard site in this file declares its triad so the support-bundle
// `invariants` section and the plan ↔ code ↔ bundle coupling stays
// authoritative. TestEveryInvariantHasTriadDocumented gates this on every
// build.
func init() {
	invariants.Register(invariants.Invariant{
		Name:             "CI_FAILURE_DETECTED_TRANSITIONS_ROW",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:markImagesFailed",
		ExpectedToHold:   "When CI image failure is detected (via gh-reported failure or manifest-timeout fallback on hosts without gh), the UPDATE transitioning docker_images_status to 'failed' succeeds.",
		WhyExpected:      "The upgrade row exists (we just SELECT'd it); the WHERE clause matches by id and current state 'building'; the DB was reachable milliseconds earlier when the SELECT ran.",
		ViolationShape:   "queryConn.Exec returns a non-nil error on the UPDATE despite an immediately-preceding successful SELECT — schema drift, DB crash mid-cycle, or transaction state issue.",
		TranscriptFormat: "INVARIANT CI_FAILURE_DETECTED_TRANSITIONS_ROW violated: UPDATE docker_images_status=failed failed for sha=<sha>: <err> (service.go:<line>, pid=<pid>)",
	})
	invariants.Register(invariants.Invariant{
		Name:             "SELF_HEAL_COMPLETED_TRANSITION_PERSISTED",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:recoverFromFlag",
		ExpectedToHold:   "When recoverFromFlag detects a stale in_progress row whose post-upgrade service is healthy, the UPDATE ... SET state='completed' RETURNING to_jsonb(upgrade.*) succeeds.",
		WhyExpected:      "The row is in_progress (we just SELECT'd it on that state); the CHECK constraint permits in_progress→completed with completed_at non-null and docker_images_status='ready'; the DB is reachable.",
		ViolationShape:   "QueryRow.Scan returns an error OR the RETURNING clause yields zero rows — CHECK violation, transient DB failure, or row disappeared between SELECT and UPDATE.",
		TranscriptFormat: "INVARIANT SELF_HEAL_COMPLETED_TRANSITION_PERSISTED violated: state transition to completed matched 0 rows or errored (id=<id>, err=<err>) — possible CHECK constraint violation (service.go:<line>, pid=<pid>)",
	})
	invariants.Register(invariants.Invariant{
		Name:             "CRASH_ROLLED_BACK_TRANSITION_PERSISTED",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:recoverFromFlag",
		ExpectedToHold:   "When recoverFromFlag detects a crashed upgrade (stale flag + dead holder PID), the UPDATE marking the row rolled_back succeeds.",
		WhyExpected:      "The row is in_progress (we just confirmed it); the CHECK constraint permits in_progress→rolled_back with rolled_back_at non-null; the DB is reachable.",
		ViolationShape:   "QueryRow.Scan returns an error OR the RETURNING clause yields zero rows — CHECK violation, transient DB failure, or row disappeared between SELECT and UPDATE.",
		TranscriptFormat: "INVARIANT CRASH_ROLLED_BACK_TRANSITION_PERSISTED violated: could not mark upgrade <id> as rolled_back: <err> (service.go:<line>, pid=<pid>)",
	})
	invariants.Register(invariants.Invariant{
		Name:             "POST_RESTART_FAILED_TRANSITION_PERSISTED",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:completeInProgressUpgrade",
		ExpectedToHold:   "After a restart that detects a failed in-progress upgrade, the UPDATE ... SET state='failed' RETURNING succeeds within the bounded retry budget (up to 4 attempts with exponential backoff on isConnError).",
		WhyExpected:      "The row is in_progress (SELECT confirmed it); CHECK permits in_progress→failed with failed_at non-null; transient isConnError errors are tolerated via reconnect-on-next-attempt.",
		ViolationShape:   "All retry attempts exhaust with Scan returning a non-conn error, or the RETURNING clause yields zero rows — persistent CHECK violation, schema drift, or sustained DB outage.",
		TranscriptFormat: "INVARIANT POST_RESTART_FAILED_TRANSITION_PERSISTED violated: state transition to failed matched 0 rows or errored (id=<id>, err=<err>) after <n> attempts (service.go:<line>, pid=<pid>)",
	})
	invariants.Register(invariants.Invariant{
		Name:             "POST_RESTART_COMPLETED_TRANSITION_PERSISTED",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:completeInProgressUpgrade",
		ExpectedToHold:   "After a successful restart on the new binary, the UPDATE ... SET state='completed', completed_at=now(), docker_images_status='ready' RETURNING succeeds within the bounded retry budget.",
		WhyExpected:      "The row is in_progress (SELECT confirmed it); CHECK permits in_progress→completed; the new binary has already established a live pool to the DB.",
		ViolationShape:   "All retry attempts exhaust with Scan returning a non-conn error, or the RETURNING clause yields zero rows — CHECK violation or sustained DB outage despite successful SELECT.",
		TranscriptFormat: "INVARIANT POST_RESTART_COMPLETED_TRANSITION_PERSISTED violated: state transition to completed matched 0 rows or errored (id=<id>, err=<err>) after <n> attempts (service.go:<line>, pid=<pid>)",
	})
	invariants.Register(invariants.Invariant{
		Name:             "LOG_POINTER_STAMPED",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:executeUpgrade",
		ExpectedToHold:   "After the upgrade INSERT completes, the UPDATE stamping log_relative_file_path on the just-inserted row succeeds within the bounded retry budget.",
		WhyExpected:      "The row was INSERTed a handful of milliseconds earlier on this same connection; isConnError retries are bounded so transient pool staleness is tolerated.",
		ViolationShape:   "Exec returns a non-conn error, or all retries exhaust with isConnError — DB failure sustained across 2+ seconds, or the row was deleted by an external actor.",
		TranscriptFormat: "INVARIANT LOG_POINTER_STAMPED violated: could not set log_relative_file_path for upgrade <id> after <n> attempts: <err>; elapsedMs=<ms> (service.go:<line>, pid=<pid>)",
	})
	invariants.Register(invariants.Invariant{
		Name:             "RECONNECT_ON_STALE_CONN_SUCCEEDS",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:executeUpgrade",
		ExpectedToHold:   "When executeUpgrade detects an isConnError on the terminal state=completed UPDATE, d.reconnect(ctx) refreshes the pool successfully so the retried UPDATE can land.",
		WhyExpected:      "The DB container is healthy (the upgraded binary just exchanged SQL with it); only the pooled connection went stale; reconnect uses the same DSN that worked at service startup.",
		ViolationShape:   "reconnect returns a non-nil error despite the DB being reachable — DSN / auth / TLS drift, or genuine DB failure concurrent with the state-transition window.",
		TranscriptFormat: "INVARIANT RECONNECT_ON_STALE_CONN_SUCCEEDS violated: reconnect after stale conn on id=<id> failed: <err> (service.go:<line>, pid=<pid>)",
	})
	invariants.Register(invariants.Invariant{
		Name:             "NORMAL_COMPLETED_TRANSITION_PERSISTED",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/internal/upgrade/service.go:executeUpgrade",
		ExpectedToHold:   "The terminal UPDATE on a successful upgrade (state=completed, completed_at=now(), docker_images_status='ready') matches exactly one row within the bounded retry budget.",
		WhyExpected:      "The row was in_progress (we inserted it and held the flag through the upgrade); CHECK permits the transition; RECONNECT_ON_STALE_CONN_SUCCEEDS guarantees a live connection on every retry.",
		ViolationShape:   "All retry attempts exhaust with Scan returning a non-conn error, or the RETURNING clause yields zero rows — CHECK violation, DB failure, or row disappeared mid-upgrade.",
		TranscriptFormat: "INVARIANT NORMAL_COMPLETED_TRANSITION_PERSISTED violated: terminal state transition to completed errored for id=<id>: <err> after <n> attempts (service.go:<line>, pid=<pid>)",
	})
}

// RowStateForCommit reads the upgrade row for a commit: its state, whether it is
// parked, and the park reason. Used by apply-latest's already-at-latest decision
// (STATBUS-226), which must distinguish a converged box from a box merely
// RUNNING the target's binary — a post-swap park whose era guard refused the
// source restoration has the target binary and a parked row at the same time.
//
// A missing row returns pgx.ErrNoRows; every error is the caller's cue that
// convergence is unproven. Read-only, single fresh query on the pass connection.
func (d *Service) RowStateForCommit(ctx context.Context, commitSHA string) (state string, parked bool, parkedReason string, err error) {
	// runOneShot is the house pattern for a one-shot verb: it connects, and it
	// CLOSES both connections on the way out. Doing this by hand would leave a
	// CLI invocation holding a listen connection open for the life of the
	// process, which is what the wrapper exists to prevent.
	err = d.runOneShot(ctx, func(ctx context.Context) error {
		var reason sql.NullString
		if qerr := d.queryConn.QueryRow(ctx,
			`SELECT state::text, recovery_parked_at IS NOT NULL, COALESCE(recovery_parked_reason, '')
			   FROM public.upgrade WHERE commit_sha = $1 ORDER BY id DESC LIMIT 1`,
			commitSHA).Scan(&state, &parked, &reason); qerr != nil {
			return qerr
		}
		parkedReason = reason.String
		return nil
	})
	if err != nil {
		return "", false, "", err
	}
	return state, parked, parkedReason, nil
}
