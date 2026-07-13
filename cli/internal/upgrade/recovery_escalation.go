package upgrade

import (
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// STATBUS-046 (doc-021, King ruling D3) — the crash-resume escalation core: the
// bound that replaces the rune loop-forever (10,229 restarts). systemd
// StartLimit cannot bound a ~160s/cycle crash loop; the real bound is an
// UPGRADE-ATTEMPT budget owned by recovery. This file holds the PURE decision
// (no I/O) + the stable step names; service.go wires the persisted state (the
// recovery_attempts row column + the flag's dying-step field) around it.

// RecoveryDeathBudget bounds how many PROCESS DEATHS a single flag-owned upgrade
// may accrue before recovery stops trying forward (D3's unit is DEATHS, not
// attempts — named that way so nobody later "fixes" the off-by-one that isn't
// one). recovery_attempts is incremented at attempt START, so a dead process
// self-counts with no post-hoc bookkeeping; the number of deaths observed at any
// resume is `attempts - 1` (the first attempt had no preceding death). Budget 3
// deaths ⇒ the 4th resume (attempts==4, deaths==3) is terminal, so exactly three
// forward attempts run and die before park. Class-A in-place waits never consume
// it. Tunable at build/arc (doc-021 §Ratification ask 2).
const RecoveryDeathBudget = 3

// Phase-3 (post-swap forward) step identifiers, recorded on the flag as each
// step BEGINS so a crash freezes the dying step. Two consecutive deaths at the
// SAME step = deterministic-hang evidence → terminal immediately, independent of
// remaining budget (doc-021 D3). These are STABLE machine identifiers (never
// English prose) so the same-step comparison is exact — the doc-022 lesson that
// classification must not ride error text. Mapped to the applyNewSbUpgrading steps
// (doc-021 §Step-list 3.1–3.7 + the Phase-4 completion writes).
const (
	// StepBootMigrate is the RESUME-time schema catch-up (`sb migrate up` at
	// service.go Run + the install ladder — the rc.65 schema-skew guard). It runs
	// BEFORE recoverFromFlag/resumeNewSb on every recovery boot, and because
	// executeUpgrade Step 6b always hands off post-swap, THIS site — not the
	// applyNewSbUpgrading StepMigrateUp below — consumes every upgrade's migration delta
	// on a resume (STATBUS-044 comment #6 / r12). RecoveryBudgetGuard stamps it on
	// the flag around the boot migrate so two consecutive deaths there trip
	// same-step-twice, exactly like the Phase-3 steps. It is NOT a Phase-3
	// applyNewSbUpgrading step (it runs earlier, in Run itself) — kept beside them so the
	// same-step comparison is over one stable identifier set.
	StepBootMigrate = "boot-migrate" // resume-time schema catch-up (Run + install ladder)

	StepConfigGenerate = "config-generate" // 3.1
	StepImagePull      = "image-pull"      // 3.2
	StepDBUp           = "db-up"           // 3.3
	StepReconnect      = "reconnect"       // 3.4
	StepMigrateUp      = "migrate-up"      // 3.5
	StepStartServices  = "start-services"  // 3.6
	StepHealthCheck    = "health-check"    // 3.7
	StepMaintenanceOff = "maintenance-off" // 4.1
	StepComplete       = "complete"        // 4.2–4.3 terminal write + flag removal
	// StepRollback (slice 1B) is the single rollback-pipeline step marker. Passed
	// as the CURRENT step on a rollback resume so that same-step-twice fires iff
	// the PREVIOUS death was also a rollback (flag.Step==StepRollback) — scoping
	// same-step-twice to the rollback pipeline, never inheriting a forward step.
	StepRollback = "rollback"
)

// recoveryAction is what a crash-resume must do BEFORE re-running the forward
// pipeline.
type recoveryAction int

const (
	recoveryContinue recoveryAction = iota // proceed with this forward attempt
	recoveryPark                           // already-at-new: stop + park (siren once, alive-idle)
	recoveryRollback                       // data-safe: roll back to this upgrade's snapshot
)

func (a recoveryAction) String() string {
	switch a {
	case recoveryContinue:
		return "continue"
	case recoveryPark:
		return "park"
	case recoveryRollback:
		return "rollback"
	default:
		return fmt.Sprintf("recoveryAction(%d)", int(a))
	}
}

// resumeEscalation is the PURE escalation decision (no I/O), evaluated on a
// crash-resume BEFORE the forward pipeline re-runs. Inputs:
//   - attempts: recovery_attempts AFTER the attempt-START increment, so it
//     already includes this resume (each just-crashed attempt self-counted).
//   - deathStep: the step the just-crashed attempt was executing (frozen on the
//     flag); "" when unknown (the very first attempt, or a crash before any
//     step was recorded).
//   - priorDeathStep: the deathStep recorded at the PREVIOUS resume.
//   - canRollBack: observed state (STATBUS-039) says a rollback is data-safe
//     (pre-swap, or positively-Behind). Direction is NEVER decided here — this
//     only routes a TERMINAL outcome to its safe terminal. Forward-vs-back is
//     039's call; 046 governs only how-long / how-loud forward is tried.
//
// Rules (doc-021 / D3):
//   - same-step-twice (deathStep non-empty AND == priorDeathStep) → terminal
//     now (deterministic-hang evidence), even with budget remaining.
//   - deaths (== attempts-1) >= RecoveryDeathBudget → terminal (budget exhausted).
//   - otherwise → continue.
//
// A terminal outcome routes by canRollBack: true → rollback (data-safe), false
// → park (already-at-new — can't roll back; the loop-forever regime this ticket
// kills). The park/rollback split is the ONLY place phase matters, and it is a
// safety routing, never a direction decision.
func resumeEscalation(attempts int, deathStep, priorDeathStep string, canRollBack bool) (action recoveryAction, reason string) {
	// deaths observed at this resume: the counter increments at attempt START, so
	// the current attempt hasn't itself died yet — the first attempt (attempts==1)
	// follows zero deaths. 3 deaths (attempts==4) exhausts the budget.
	deaths := attempts - 1
	sameStepTwice := deathStep != "" && deathStep == priorDeathStep
	exhausted := deaths >= RecoveryDeathBudget
	if !sameStepTwice && !exhausted {
		return recoveryContinue, ""
	}
	if sameStepTwice {
		reason = fmt.Sprintf("two consecutive crash-deaths at step %q — deterministic hang (same-step-twice)", deathStep)
	} else {
		reason = fmt.Sprintf("crash-resume budget exhausted: %d process deaths >= budget %d (attempt %d, last death at step %q)",
			deaths, RecoveryDeathBudget, attempts, stepOrUnknown(deathStep))
	}
	if canRollBack {
		return recoveryRollback, reason
	}
	return recoveryPark, reason
}

func stepOrUnknown(s string) string {
	if s == "" {
		return "unknown"
	}
	return s
}

// rollbackResumeIsTerminal is the ROLLBACK-regime sibling of resumeEscalation
// (STATBUS-046 slice 1B, architect-pinned). It deliberately does NOT reuse
// resumeEscalation: that function's EXHAUST term must NOT fire for a rollback.
// A Phase-1 (pre-swap) budget-EXHAUST *routes* to the rollback, so terminating a
// rollback on the shared death count would insta-restore-broke its very FIRST
// resume without one re-attempt (the same false-positive shape the StepRollback
// marker fixes in the step dimension). So the ONLY budget-side terminal for a
// rollback is SAME-STEP-TWICE: it takes TWO consecutive mid-rollback deaths.
//
// On a rollback resume, `step` is where the JUST-crashed attempt died (the frozen
// flag.Step) and `priorStep` is where the death BEFORE that died (flag.PriorDeathStep,
// rolled forward by recordRollbackCommit on each commit). Terminal IFF BOTH are
// StepRollback — i.e. the last TWO deaths were both mid-rollback. On the
// forward→rollback handoff priorStep is the FORWARD step (never StepRollback), so
// the first rollback resume is free BY CONSTRUCTION (architect (a), no special
// case) and the rollback gets its designed idempotent re-run. A single transient
// reboot/OOM mid-restore therefore re-runs, never insta-fails.
//
// Two consecutive rollback deaths ⇒ the rollback itself can't complete ⇒ the
// caller maps it to the restore-broke HUMAN stop (state='failed'). The genuinely-
// terminal git-restore-fail is handled inside rollback() itself; this bounds the
// CRASH loop (net hard bound: 3 forward + 2 rollback deaths).
func rollbackResumeIsTerminal(step, priorStep string) bool {
	return step == StepRollback && priorStep == StepRollback
}

// ─────────────────────────────────────────────────────────────────────────────
// STATBUS-046 slice 2 — B/C failure classification (park-on-first).
//
// A step failure already-at-new already funnels into the death budget (newSbUpgradingFailure
// records the failure and returns → the process exits → the next crash-resume
// increments recovery_attempts; after 3 deaths it parks). Slice 2 SHORT-CIRCUITS
// that for a PROVABLY-deterministic (B) or resource (C) failure: park on the
// FIRST occurrence instead of burning three deaths, with a named actionable
// reason. Class A (transient/readiness) is unchanged — the existing in-place
// handling + the death budget bound it.
//
// CLASSIFIER DISCIPLINE (doc-022): STRUCTURED signals only — exec exit codes,
// SQLSTATE, docker error classes — NEVER an English-substring list. classUnknown
// is the SAFE default (architect Q1 lean): the death budget + same-step-twice
// still bound an unrecognised failure, so it never false-parks on a transient
// blip; whereas defaulting unknown→B would park a genuinely-transient unknown on
// its first occurrence.
// ─────────────────────────────────────────────────────────────────────────────

type failureClass int

const (
	// classUnknown — no structured signal recognised → fall through to the
	// existing forward-retry, which the death budget + same-step-twice bound.
	classUnknown failureClass = iota
	// classTransient — A: readiness/transient, handled in place (never parks here).
	classTransient
	// classDeterministic — B: retrying cannot change the outcome → park on first.
	classDeterministic
	// classResource — C: retrying amplifies it → park on first.
	classResource
)

func (c failureClass) String() string {
	switch c {
	case classTransient:
		return "A/transient"
	case classDeterministic:
		return "B/deterministic"
	case classResource:
		return "C/resource"
	default:
		return "unknown"
	}
}

// parksOnFirst reports whether a class parks immediately (B/C) rather than
// deferring to the death budget (A/unknown).
func (c failureClass) parksOnFirst() bool {
	return c == classDeterministic || c == classResource
}

// classifyStepFailure maps a Phase-3 step failure to its handling class using
// STRUCTURED signals only. SLICE 2 (current scope): config-generate is the one
// cleanly exit-code-classifiable site — `sb config generate` renders templates
// from .env.config with no network/DB, so any NON-TIMEOUT failure is a
// deterministic template/config error (B) that re-running cannot fix.
//
// A hung step (ErrCommandTimeout) is NOT deterministic — it returns classUnknown
// so the death budget + same-step-twice bound a repeated hang instead of parking
// a possibly-slow step on its first timeout.
//
// UNKNOWN → A is safe (architect Q1) precisely because an error-exit COUNTS AS A
// DEATH: the failing step returns → applyNewSbUpgrading stops → the process exits →
// systemd restarts → the next resume increments recovery_attempts. So an
// unknown-but-deterministic error parks on its SECOND occurrence via
// same-step-twice (faster than the budget), while a transient unknown survives
// its one blip. That is why the budget bounds unknown errors at all.
//
// The docker sites (3.2/3.3/3.6) still need a structured docker signal (exit code
// is 1 for 404/disk/transient alike; architect Q2) → classUnknown until wired.
func classifyStepFailure(step string, err error) failureClass {
	if err == nil {
		return classUnknown
	}
	if errors.Is(err, ErrCommandTimeout) {
		return classUnknown
	}
	switch step {
	case StepConfigGenerate:
		// config generate renders templates from .env.config (no network/DB) → any
		// non-timeout failure is a deterministic template/config error.
		return classDeterministic
	case StepMigrateUp:
		// The migrate SQLSTATE lives INSIDE the `sb migrate up` subprocess; it
		// reaches us ONLY as the process EXIT CODE (the Q5 contract in
		// migrate/exit_codes.go), read structurally — never the stderr text.
		// 20 = deterministic SQL (B); 22 = resource / SQLSTATE class 53 (C);
		// anything else → unknown → A (budget + same-step-twice bounded).
		if code, ok := exitCodeOf(err); ok {
			switch code {
			case migrate.ExitDeterministic:
				return classDeterministic
			case migrate.ExitResource:
				return classResource
			}
		}
		return classUnknown
	}
	return classUnknown
}

// exitCodeOf extracts a subprocess exit code from an error (via exec.ExitError),
// if one is present. The second return is false when err is not a process-exit
// error (e.g. a timeout or an in-process error) — the caller treats that as
// "no structured exit signal" → classUnknown.
func exitCodeOf(err error) (int, bool) {
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode(), true
	}
	return 0, false
}

// ── docker step classification (architect Q2) ────────────────────────────────
//
// docker/compose exits 1 for 404 / disk-full / transient alike, so the exit code
// alone can't sub-classify. We match ONE canonical KERNEL constant CONJUNCTIVELY
// with a non-zero process exit (pin 2) and park ONLY on a positive exact match
// (pin 3): a missed marker degrades to classUnknown → A, budget-bounded.
// Under-match is bounded leniency, never a wrong park — the asymmetry that keeps
// this on the right side of the doc-022 line.
//
// WHY ONLY ONE MARKER (the manifest-404 arm ships as unknown→A): a LIVE sample
// (docker pull of a nonexistent tag) proved the OCI MANIFEST_UNKNOWN string never
// reaches the caller — the daemon REWRAPS the registry error as generic
// `failed to resolve reference "...": ... not found`. "not found" is too generic
// to promote to a park signal. THE PRINCIPLED DISTINCTION (do not add "just one
// more marker"): ENOSPC's strerror text is KERNEL-authored and survives any
// daemon's rewrapping verbatim; the registry error is DAEMON-authored prose —
// kernel constants survive rewrapping, daemon prose IS the rewrapping.
//
// Manifest-404 therefore stays unknown→A here. Q1 gives that real teeth as-is: a
// persistent 404 dies at the SAME step twice → parks in 2 deaths with the step
// named. The marker lights up ONLY after a real-surface sample confirms a stable
// verbatim string (docker-ce + compose pull on Linux, via the next arc run or a
// tiny CI capture). PRE-DECIDED NEGATIVE: if that sample is ALSO generic
// "not found"-class prose, this arm stays unknown→A PERMANENTLY — no weaker
// marker. The only future alternative worth evaluating then is a POST-failure
// `docker manifest inspect` disambiguation probe (after-failure only, degrades to
// A on ambiguity) — NOT to be built speculatively.
const (
	// kernelMarkerENOSPC — strerror(ENOSPC), the kernel's canonical disk-full
	// message. Source: POSIX/Linux errno ENOSPC. Genuinely verbatim in docker
	// error chains (kernel-authored — see the block comment). In-flight BACKSTOP
	// only; the PRIMARY disk (C) signal is the local statfs pre-check at the call
	// site (fully structured, mirrors the Phase-0 ≥5GB gate).
	kernelMarkerENOSPC = "no space left on device"
)

// classifyDockerFailure classifies a docker/compose step failure from its error
// + a captured stderr tail. Only the kernel-stable ENOSPC marker promotes (to C);
// non-exit failures, an unmatched failure, and the manifest-404 case all →
// classUnknown (→ A, budget-bounded). See the block comment.
func classifyDockerFailure(err error, stderrTail string) failureClass {
	if _, ok := exitCodeOf(err); !ok {
		return classUnknown // not a process-exit failure → no structured signal
	}
	if strings.Contains(stderrTail, kernelMarkerENOSPC) {
		return classResource // disk full (kernel-verbatim backstop) — C
	}
	return classUnknown
}
