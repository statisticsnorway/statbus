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
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/invariants"
	"github.com/statisticsnorway/statbus/cli/internal/selfupdate"
)

// markTerminal pins invariants.MarkTerminal to this service's projDir.
// Every fail-fast guard site in this file calls markTerminal before
// returning/continuing so the support bundle's install-terminal.txt has
// a named-invariant anchor for SSB triage.
func (d *Service) markTerminal(name, observed string) {
	invariants.MarkTerminal(d.projDir, name, observed)
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

// Service is the long-running upgrade service.
type Service struct {
	projDir      string
	version      string           // compiled-in version from ldflags (e.g., v2026.03.0-rc.11)
	listenConn   *pgx.Conn         // dedicated to LISTEN/NOTIFY — never use for queries
	queryConn    *pgx.Conn         // for all SELECT/INSERT/UPDATE queries
	verbose      bool
	channel      string
	interval     time.Duration
	autoDL       bool
	// pinnedVer removed — use "skip" in the UI instead of a channel that hides all releases
	upgrading      bool             // true during executeUpgrade; prevents ticker/notify from using nil conn
	pendingRecreate bool           // if true, next upgrade deletes+recreates the database instead of migrating
	cachedURL      string           // cached health check URL (derived from .env at startup)
	listenCancel context.CancelFunc // cancels the listenLoop goroutine
	listenDone   chan struct{}      // closed when the active listenLoop goroutine exits
	// listenWg retired in favour of listenDone: we need to tolerate a leaked
	// goroutine after a force-close timeout (task #40 / #37 root cause), and
	// sync.WaitGroup's counter would go negative on the leaked goroutine's
	// eventual Done() if the field was reassigned during restart. A per-run
	// channel has no state to corrupt.
	allowedSignersPath string      // path to tmp/allowed-signers file (empty if no signers configured)
	flagLock           *FlagLock   // holds the flock on tmp/upgrade-in-progress.json during executeUpgrade
	runningAsService   bool        // true when Run() is the entry point; false for one-shot callers
	// binaryCommit is the compile-time commit SHA (ldflags -X cmd.commit=<sha>),
	// a ground-truth anchor the service uses to answer "what version is this
	// binary itself?" independent of git checkout state or row-recorded
	// targets. Used by completeInProgressUpgrade's ground-truth verification
	// (task #49): if an in_progress row's commit_sha differs from
	// binaryCommit at post-restart recovery time, the upgrade did not
	// actually complete — mark failed, don't silently lie.
	//
	// "unknown" when the build has no ldflags (local go-run paths); in that
	// case the ground-truth check degrades to a skip rather than a false
	// failure, since we can't know the binary's true identity.
	binaryCommit       string
	stuckLoopFired     bool            // set to true after SERVICE_STUCK_RETRY_LOOP is emitted, to avoid spam
}

// NewService creates a new upgrade service.
//
// binaryCommit is the compile-time commit SHA from cli/cmd/root.go's
// `commit` ldflag. Pass cmd.commit directly from the caller. Leave
// "unknown" in non-release builds (go run, local test); the ground-truth
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

// FlagPhase discriminates where executeUpgrade had reached when the holder's
// process last ran. The service swaps the ./sb binary on disk mid-flow then
// hands off to a fresh process via exit 42 / systemd restart so the remaining
// steps run against the NEW compiled Go. recoverFromFlag branches on Phase to
// distinguish a crashed pre-swap run (rollback) from an expected post-swap
// handoff (resume).
//
// Legacy flags pre-dating Option C lack the field and deserialize as empty;
// recoverFromFlag treats empty as FlagPhasePreSwap, preserving the prior
// "HEAD=target => self-heal to completed" semantics.
const (
	FlagPhasePreSwap  = ""          // default: written before replaceBinaryOnDisk, or legacy
	FlagPhasePostSwap = "post_swap" // stamped after binary swap, before exit-42 handoff
)

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
// PID + pidAlive() is diagnostic only: if the file exists, flock
// semantics already guarantee that either someone alive holds it or no
// one does. The PID in the JSON surfaces WHO (for error messages);
// liveness is known from whether the flock can be acquired.
//
// Legacy flag files written before Release 1 lack PID/StartedAt/InvokedBy
// and deserialize with zero values. `pidAlive` treats PID<=0 as not-alive,
// so a legacy flag produces the "crashed — recover required" path rather
// than a false "still running" diagnosis. Holder also defaults to empty
// (treated as "service").
type UpgradeFlag struct {
	ID         int       `json:"id"`                    // 0 when Holder=="install"
	CommitSHA  string    `json:"commit_sha"`            // "" when Holder=="install"
	CommitTags []string  `json:"commit_tags,omitempty"` // release tags at CommitSHA; empty for install-held and untagged commits
	PID        int       `json:"pid"`                   // os.Getpid() at write time
	StartedAt  time.Time `json:"started_at"`            // time.Now() at write time
	InvokedBy  string    `json:"invoked_by"`            // specific trigger (e.g. "notify:v2026.04.1", "operator:jhf")
	Trigger    string    `json:"trigger"`               // coarse bucket ("notify"|"scheduled"|"recovery"|"install")
	Holder     string    `json:"holder"`                // HolderService or HolderInstall
	Phase      string    `json:"phase,omitempty"`       // FlagPhasePreSwap (default) or FlagPhasePostSwap
	Recreate   bool      `json:"recreate,omitempty"`    // captures d.pendingRecreate so resumePostSwap can replay --recreate
	BackupPath string    `json:"backup_path,omitempty"` // finalized backup dir, populated at Phase=post_swap so resumePostSwap can roll back without DB
}

// Label returns a human-readable label for the flag. For service-held
// flags, the label is renderDisplayName(CommitSHA, CommitTags). For
// install-held flags, returns a synthetic "install (PID N)" string
// since there is no commit-centric label.
func (f *UpgradeFlag) Label() string {
	if f == nil {
		return ""
	}
	if f.Holder == HolderInstall {
		return fmt.Sprintf("install (PID %d)", f.PID)
	}
	return renderDisplayName(CommitSHA(f.CommitSHA), f.CommitTags)
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
		// Contention: another live holder has the lock. Read what's on
		// disk for diagnostics, without holding a lock.
		f.Close()
		existing, alive, readErr := ReadFlagFile(projDir)
		if readErr != nil {
			return nil, fmt.Errorf("flag file unreadable while locked: %w\n  Investigate %s manually.",
				readErr, path)
		}
		if existing == nil {
			// Pathological: flock failed but file was removed before we
			// could read it. Report generically.
			return nil, fmt.Errorf("flag file at %s is locked by another process (could not read metadata)", path)
		}
		return nil, formatContentionError(existing, alive)
	}
	// We hold the lock. Truncate existing content and write ours.
	if _, err := f.Seek(0, 0); err != nil {
		f.Close()
		return nil, fmt.Errorf("seek flag: %w", err)
	}
	if err := f.Truncate(0); err != nil {
		f.Close()
		return nil, fmt.Errorf("truncate flag: %w", err)
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		return nil, fmt.Errorf("write flag: %w", err)
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return nil, fmt.Errorf("sync flag: %w", err)
	}
	return &FlagLock{file: f}, nil
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
	l.file.Close()
	l.file = nil
}

// writeUpgradeFlag is the service's acquire. On success, the FlagLock
// held on d.flagLock keeps the flock alive for the duration of
// executeUpgrade. removeUpgradeFlag closes it to release.
//
// Phase is initialised to FlagPhasePreSwap; writeFlagPhase rewrites it to
// FlagPhasePostSwap after replaceBinaryOnDisk, right before the exit-42
// handoff. Recreate captures d.pendingRecreate so the resumed post-swap
// process can replay the --recreate branch identically.
func (d *Service) writeUpgradeFlag(id int, commitSHA string, commitTags []string, invokedBy, trigger string, recreate bool) error {
	flag := UpgradeFlag{
		ID:         id,
		CommitSHA:  commitSHA,
		CommitTags: commitTags,
		PID:        os.Getpid(),
		StartedAt:  time.Now(),
		InvokedBy:  invokedBy,
		Trigger:    trigger,
		Holder:     HolderService,
		Phase:      FlagPhasePreSwap,
		Recreate:   recreate,
	}
	lock, err := acquireFlock(d.projDir, flag)
	if err != nil {
		return err
	}
	d.flagLock = lock
	return nil
}

// updateFlagPostSwap rewrites the on-disk flag JSON without releasing the
// flock: sets Phase=FlagPhasePostSwap and stores backupPath so the new
// binary's recoverFromFlag → resumePostSwap can resume without a live DB
// connection (queryConn is closed mid-flow for the consistent backup).
//
// Preconditions: d.flagLock holds the flock (set by writeUpgradeFlag).
// Uses the already-open fd so the flock is preserved across the rewrite.
func (d *Service) updateFlagPostSwap(backupPath string) error {
	if d.flagLock == nil || d.flagLock.file == nil {
		return fmt.Errorf("updateFlagPostSwap: no flag file held")
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
	flag.Phase = FlagPhasePostSwap
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
func (d *Service) removeUpgradeFlag() {
	if d.flagLock != nil {
		d.flagLock.Close()
		d.flagLock = nil
	}
	os.Remove(d.flagPath())
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
		PID:       os.Getpid(),
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
func ReleaseInstallFlag(lock *FlagLock) {
	if lock != nil && lock.file != nil {
		path := lock.file.Name()
		lock.Close()
		os.Remove(path)
	} else {
		lock.Close()
	}
}

// formatContentionError builds the operator-facing message for a failed
// AcquireInstallFlag. Branches on Holder + alive to produce one of:
//   - live service: "upgrade in progress, wait"
//   - live install: "another install running, wait"
//   - dead any:    "previous {upgrade|install} crashed — re-run ./sb install"
//
// Empty Holder (legacy pre-Release-1.1 flags) is treated as service.
func formatContentionError(flag *UpgradeFlag, alive bool) error {
	holder := flag.Holder
	if holder == "" {
		holder = HolderService
	}
	if alive {
		switch holder {
		case HolderInstall:
			return fmt.Errorf(
				"another ./sb install is already running: PID %d (%s, invoked_by=%s).\n\n"+
					"  Wait for it to complete, then retry.",
				flag.PID, flag.Label(), flag.InvokedBy)
		default: // HolderService
			return fmt.Errorf(
				"an orchestrated upgrade is in progress: PID %d (%s, invoked_by=%s).\n\n"+
					"  Wait for it to complete:\n"+
					"    journalctl --user -u 'statbus-upgrade@*' -f\n\n"+
					"  Do NOT pass --inside-active-upgrade — that flag is the upgrade service's\n"+
					"  internal contract with its own post-upgrade install step. Using it from the\n"+
					"  command line would corrupt an upgrade that is currently running.",
				flag.PID, flag.Label(), flag.InvokedBy)
		}
	}
	verb := "upgrade"
	if holder == HolderInstall {
		verb = "install"
	}
	return fmt.Errorf(
		"a prior %s crashed or was stopped mid-run: flag file references PID %d (%s, invoked_by=%s)\n"+
			"but that process is no longer alive.\n\n"+
			"  Re-run ./sb install — it detects the stale flag and reconciles it automatically.",
		verb, flag.PID, flag.Label(), flag.InvokedBy)
}

// ReadFlagFile inspects the upgrade-in-progress flag at <projDir>/tmp/upgrade-in-progress.json.
// Returns (nil, false, nil) when the flag file is absent (upgrade-mutex is "Idle").
// Returns (flag, alive, nil) when the flag exists, where `alive` is true iff the PID that
// wrote the flag is still running. Callers use the liveness to pick between
// "wait for the running upgrade" vs "restart the service to recover from a crash" messaging.
//
// Callers outside this package should treat this as read-only: never remove or modify
// the flag file. Ownership belongs to the upgrade service (service.go:writeUpgradeFlag
// and removeUpgradeFlag).
func ReadFlagFile(projDir string) (*UpgradeFlag, bool, error) {
	path := filepath.Join(projDir, "tmp", "upgrade-in-progress.json")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, false, nil
		}
		return nil, false, err
	}
	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		return nil, false, fmt.Errorf("parse upgrade flag file: %w", err)
	}
	return &flag, pidAlive(flag.PID), nil
}

// pidAlive checks whether a process with the given PID currently exists and
// is owned by a user whose signals we can deliver. Returns false for PID<=0
// (which includes the zero value produced by deserializing legacy flag files).
//
// On Unix, os.FindProcess never fails; the real liveness check is
// `kill -0 pid` (signal 0 = permission check without actually signaling).
// ESRCH means "no such process" (dead); EPERM means "process exists but
// we don't own it" which we treat as alive.
func pidAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	if err := proc.Signal(syscall.Signal(0)); err != nil {
		return os.IsPermission(err)
	}
	return true
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
	defer f.Close()
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
	var relPath sql.NullString
	if err := d.queryConn.QueryRow(ctx,
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
		os.Remove(d.flagPath())
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

	logRecover("Service restarted. Found interrupted %s flag for %s (id=%d, pid=%d, invoked_by=%s)",
		holder, flag.Label(), flag.ID, flag.PID, flag.InvokedBy)

	// Guard removed: DetectState's flock-try is now authoritative for
	// distinguishing ghost flags from live upgrades. If we reach here, the
	// caller (DetectState → StateCrashedUpgrade, or service startup) has
	// already confirmed the flock is NOT held. pidAlive was unreliable:
	// the service survives SHA upgrades, so PID stays alive after the
	// upgrade completes — creating a ghost flag that pidAlive can't detect.

	// Install-held flag from a crashed install. The flock was released by
	// the kernel when the install's fd closed; the on-disk JSON is pure
	// audit now. Install never writes public.upgrade, so there's no DB
	// state to reconcile — delete the stale file so tmp/ stays tidy and
	// inspecting the directory doesn't suggest something is in flight.
	// (If install ever grows DB-write semantics, add reconciliation here.)
	if holder == HolderInstall {
		logRecover("Clearing stale install flag (PID %d crashed or exited without releasing)", flag.PID)
		os.Remove(d.flagPath())
		return nil
	}

	// Post-swap restart (exit 42 after replaceBinaryOnDisk): this is NOT a
	// crash. The prior process image intentionally handed off to the new
	// binary so that migrate + health-check + post-swap steps run against
	// the freshly-compiled Go. Resume the pipeline from config-generate
	// onward rather than marking the row completed — the upgrade isn't
	// actually done yet.
	if flag.Phase == FlagPhasePostSwap {
		logRecover("Post-swap restart detected for upgrade %d (%s) — resuming pipeline on new binary (pid=%d)",
			flag.ID, flag.Label(), os.Getpid())
		if appendLog != nil {
			appendLog.Close()
			appendLog = nil
		}
		return d.resumePostSwap(ctx, flag)
	}

	// Service-held flag: reconcile against public.upgrade.
	// Check if the upgrade actually succeeded (self-update restart via exit code 42).
	// If git HEAD matches the upgrade target, the code is at the right version.
	headSHA, _ := runCommandOutput(d.projDir, "git", "rev-parse", "HEAD")
	headSHA = strings.TrimSpace(headSHA)
	targetIsAncestor := false
	if headSHA != flag.CommitSHA {
		if _, err := runCommandOutput(d.projDir, "git", "merge-base", "--is-ancestor", flag.CommitSHA, headSHA); err == nil {
			targetIsAncestor = true
		}
	}
	if headSHA == flag.CommitSHA || targetIsAncestor {
		if targetIsAncestor {
			logRecover("Upgrade %s succeeded (target %s is ancestor of HEAD %s — code advanced past target)",
				flag.Label(), ShortForDisplay(flag.CommitSHA), ShortForDisplay(headSHA))
		} else {
			logRecover("Upgrade %s succeeded (HEAD matches target commit — self-update restart detected)", flag.Label())
		}

		// Ground-truth verification (task #49 / Gap #1). HEAD-matches-target
		// is necessary but not sufficient — git checkout (executeUpgrade
		// step 6) succeeds BEFORE replaceBinaryOnDisk (step 6b). A crash in
		// that window leaves HEAD at the target but the running binary at
		// the prior version. Without this check, recoverFromFlag would
		// silently mark the row completed despite a stale binary.
		// On failure, fall through to the rollback path (Branch D below)
		// rather than the success-mark UPDATE.
		if ok, reason := d.verifyUpgradeGroundTruth(ctx, flag.CommitSHA); !ok {
			logRecover("Ground-truth verification FAILED for %s: %s — falling through to rollback", flag.Label(), reason)
			if appendLog != nil {
				appendLog.Close()
				appendLog = nil
			}
			d.recoveryRollback(ctx, int(flag.ID), flag.Label(), logRelPath, fmt.Sprintf(
				"%s: post-restart ground-truth check failed: %s",
				ErrInstallPreconditionFailed, reason))
			return nil
		}

		// Close the appender BEFORE reading the tail so the flush lands
		// on disk and the UPDATE below captures the recovery lines.
		if appendLog != nil {
			appendLog.Close()
			appendLog = nil
		}
		// Guard: only self-heal an in_progress row. A row already in a
		// terminal state (completed/failed/rolled_back) means the prior
		// service instance reconciled before exiting (clean rollback or
		// success path) and left the file as a ghost — this recovery
		// pass should silently remove the file, not overwrite the
		// audit trail. ErrNoRows here means "ghost flag, terminal row";
		// any other error is the real C1 invariant violation.
		var selfHealJSON string
		if err := d.queryConn.QueryRow(ctx,
			"UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready' WHERE id = $1 AND state = 'in_progress'"+upgradeRowReturning,
			flag.ID).Scan(&selfHealJSON); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				logRecover("Ghost flag detected for upgrade %d (%s): row is already terminal, removing stale flag file without overwriting audit trail",
					flag.ID, flag.Label())
				os.Remove(d.flagPath())
				return nil
			}
			// C1: SELF_HEAL_COMPLETED_TRANSITION_PERSISTED — bug-class. The
			// flag's SHA matches a completed-on-disk state, the row is still
			// in_progress (per the WHERE guard), and we hold the mutex. A
			// CHECK violation here means the state machine has drifted;
			// retrying next tick won't reconcile it. Fail-fast + bundle.
			fmt.Fprintf(os.Stderr,
				"INVARIANT SELF_HEAL_COMPLETED_TRANSITION_PERSISTED violated: state transition to completed errored for in_progress row (id=%d, err=%v) — possible CHECK constraint violation (service.go:%d, pid=%d)\n",
				flag.ID, err, thisLine(), os.Getpid())
			d.markTerminal("SELF_HEAL_COMPLETED_TRANSITION_PERSISTED",
				fmt.Sprintf("id=%d; Scan err=%v", flag.ID, err))
			d.writeDiagnosticBundle(ctx, int(flag.ID), appendLog)
			return nil
		}
		logUpgradeRow(LabelCompletedSelfHeal, selfHealJSON)
		// Explicit NOTIFY — the DB trigger also fires, but the app's LISTEN is
		// definitely established by now (new service starts after app is healthy).
		d.queryConn.Exec(ctx, `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)
		// The stale flag has now been reconciled — remove the on-disk
		// file so the next executeUpgrade's acquireFlock starts from a
		// clean state. (The kernel flock was already released when the
		// prior service process died.)
		os.Remove(d.flagPath())
		d.supersedeOlderReleases(ctx, flag.CommitSHA)
		d.supersedeCompletedPrereleases(ctx, flag.CommitSHA)
		return nil
	}

	// Real failure. HEAD doesn't match the upgrade target — the binary
	// swap (and likely earlier steps) didn't complete. Task #49 / Gap #2
	// rewrite: previously this branch only marked the row rolled_back
	// without touching the running system, leaving services possibly
	// stopped, maintenance possibly on, DB possibly half-migrated, etc.
	// That made the row a lie about the on-disk reality.
	//
	// Now: invoke recoveryRollback → d.rollback(), which runs the full
	// restoration pipeline (capture container logs, stop services, restore
	// git/DB/binary, restart services, deactivate maintenance, mark
	// state='rolled_back'). For the pre-destructive-step crash case (no
	// services were stopped, no maintenance was activated) the restore
	// steps are mostly no-ops — that's fine; the UPDATE still happens
	// coherently and the operator-facing row matches reality.
	logRecover("HEAD (%s) does not match upgrade target (%s). Invoking rollback to %s.",
		ShortForDisplay(headSHA), ShortForDisplay(flag.CommitSHA), d.version)

	// Build a short error summary from the log tail. The full narrative
	// lives in the on-disk log (served via /upgrade-logs/); we only need
	// the last handful of lines here for the row's `error` column.
	logTail := readProgressLogTail(UpgradeLogAbsPath(d.projDir, logRelPath), 50)
	errMsg := "Upgrade interrupted (service crashed or was killed)"
	if logTail != "" {
		lines := strings.Split(strings.TrimSpace(logTail), "\n")
		if len(lines) > 5 {
			lines = lines[len(lines)-5:]
		}
		errMsg = strings.Join(lines, "\n")
	}

	// Guard: if the row is no longer in_progress (terminal state already
	// recorded by a prior service instance before exit), this is a ghost
	// flag — just remove the file and don't overwrite the audit trail.
	// Check with a probe SELECT before invoking the heavyweight rollback
	// machinery so we don't run a full restore on a row we shouldn't touch.
	var probeState string
	if probeErr := d.queryConn.QueryRow(ctx,
		"SELECT state FROM public.upgrade WHERE id = $1", flag.ID).Scan(&probeState); probeErr != nil {
		if errors.Is(probeErr, pgx.ErrNoRows) {
			logRecover("Ghost flag detected for upgrade %d (%s): row missing, removing stale flag file",
				flag.ID, flag.Label())
			os.Remove(d.flagPath())
			return nil
		}
		// Real DB error — preserve flag + bundle so an operator can investigate.
		fmt.Fprintf(os.Stderr,
			"recoverFromFlag: probe SELECT failed for upgrade %d: %v\n", flag.ID, probeErr)
		d.writeDiagnosticBundle(ctx, int(flag.ID), nil)
		return fmt.Errorf("recoverFromFlag: probe SELECT failed for upgrade %d: %w", flag.ID, probeErr)
	}
	if probeState != "in_progress" {
		logRecover("Ghost flag detected for upgrade %d (%s): row is already %s, removing stale flag file without overwriting audit trail",
			flag.ID, flag.Label(), probeState)
		os.Remove(d.flagPath())
		return nil
	}

	// Close appender before rollback acquires its own log handle.
	if appendLog != nil {
		appendLog.Close()
		appendLog = nil
	}

	d.recoveryRollback(ctx, int(flag.ID), flag.Label(), logRelPath, errMsg)
	// rollback() removes the flag and emits LabelRolledBackNormal logs;
	// nothing more to do here.
	return nil
}

// (shortSHA helper deleted in rc.63; use commit.go's commitShort for
// typed CommitSHA values and ShortForDisplay for untyped log strings.)

// markCIImagesFailed transitions a discovery row to
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
func (d *Service) markCIImagesFailed(ctx context.Context, id int, sha, reason string) {
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
			decision := fmt.Sprintf("markCIImagesFailed/%s", sha[:12])
			tracker.Clear(decision)
			return
		}
		// Real DB error (connection dead, unexpected constraint
		// violation). Escalate — but first check if we're in a retry loop
		// (item #5 rc.64: attempt tracker for SERVICE_STUCK_RETRY_LOOP).
		tracker := NewAttemptTracker(d.projDir, 3)
		decision := fmt.Sprintf("markCIImagesFailed/%s", sha[:12])
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
		decision := fmt.Sprintf("markCIImagesFailed/%s", sha[:12])
		tracker.Clear(decision)
		return
	}
	// Clear attempt counter on success
	tracker := NewAttemptTracker(d.projDir, 3)
	decision := fmt.Sprintf("markCIImagesFailed/%s", sha[:12])
	tracker.Clear(decision)
	log.Printf("CI images marked failed for commit %s: %s", ShortForDisplay(sha), reason)
}

// verifyArtifacts runs the declarative artifact readiness check for every
// public.upgrade row that hasn't already been completed, rolled back, or
// skipped. Two independent levels are tracked by separate columns so the
// admin UI can tell an operator exactly what it is waiting for:
//
//   docker_images_status           — the four Docker images (db/app/worker/proxy)
//                             exist at the runtime VERSION tag
//                             (git-describe output). Verified via
//                             `docker manifest inspect` — a registry-only
//                             query that doesn't pull. Three states:
//                             building (CI in progress), ready (verified),
//                             failed (CI workflow failed).
//   release_builds_status          — for tagged releases only: the GitHub Release
//                             + `sb` binary + manifest.json exist. Set
//                             by the discovery loop above via FetchManifest.
//                             For commits this defaults to ready (edge
//                             channel doesn't use release artifacts).
//                             Three states: building, ready, failed.
//
// Scoped to the 30 most recent pending rows to bound per-cycle cost.
func (d *Service) verifyArtifacts(ctx context.Context) {
	const registryPrefix = "ghcr.io/statisticsnorway/statbus-"
	// manifestTimeout is the fallback grace window used when `gh` is absent or
	// errors: once a discovery row has been in docker_images_status='building'
	// longer than this AND the registry manifests are still missing, we mark
	// the row 'failed' so the admin UI stops spinning. Production hosts
	// typically have no `gh`; this ensures CI_FAILURE_DETECTED_TRANSITIONS_ROW
	// still holds without it.
	const manifestTimeout = 20 * time.Minute
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
		id                   int
		sha                  string
		releaseStatus        string
		dockerImagesStatus   string
		releaseBuildsStatus  string
		version              *string // NULL for rows predating the version column
		discoveredAt         time.Time
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
				d.queryConn.Exec(ctx,
					"UPDATE public.upgrade SET docker_images_status = 'ready' WHERE id = $1 AND docker_images_status != 'ready'",
					r.id)
				fmt.Printf("Images verified for commit %s (tag=%s)\n", ShortForDisplay(r.sha), tag)
				dockerImagesReady = true

				// Auto-supersede intermediate commit rows that are ancestors of
				// this commit but will never have CI images of their own.
				// ci-images.yaml triggers once per push and only tags images for
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
				// Images not in registry — try gh first, fall back to a time-
				// bounded manifest check so CI_FAILURE_DETECTED_TRANSITIONS_ROW
				// holds on hosts where `gh` is absent (production norm).
				ciOutput, ciErr := runCommandOutput(d.projDir, "gh", "api",
					fmt.Sprintf("repos/statisticsnorway/statbus/actions/workflows/ci-images.yaml/runs?head_sha=%s&status=completed&per_page=5", r.sha),
					"--jq", ".workflow_runs[] | .conclusion")
				if ciErr == nil && ciOutput != "" {
					conclusions := strings.Fields(strings.TrimSpace(ciOutput))
					hasSuccess := false
					hasFailure := false
					for _, c := range conclusions {
						if c == "success" {
							hasSuccess = true
						} else if c == "failure" {
							hasFailure = true
						}
					}
					if hasFailure && !hasSuccess {
						d.markCIImagesFailed(ctx, r.id, r.sha, fmt.Sprintf(
							"CI images workflow reported failure for commit %s", ShortForDisplay(r.sha)))
					}
				} else if ciErr != nil {
					// gh unavailable / errored. Fall back to manifest-timeout:
					// if the row has been waiting in 'building' longer than
					// manifestTimeout and the registry still has no manifests,
					// CI must have failed (or been skipped) — mark failed.
					age := time.Since(r.discoveredAt)
					log.Printf(
						"verifyArtifacts: gh unavailable (%v); falling back to manifest-timeout check (sha=%s, age=%s, timeout=%s)",
						ciErr, ShortForDisplay(r.sha), age.Truncate(time.Second), manifestTimeout)
					if age > manifestTimeout {
						d.markCIImagesFailed(ctx, r.id, r.sha, fmt.Sprintf(
							"CI images absent after %s timeout; gh probe err=%v", manifestTimeout, ciErr))
					}
				}
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
		d.queryConn.Close(context.Background())
	}
	if d.listenConn != nil {
		d.listenConn.Close(context.Background())
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
func (d *Service) ExecuteUpgradeInline(ctx context.Context, id int, commitSHA, displayName string) error {
	tag, err := d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET state = 'in_progress', started_at = now(), from_commit_version = $1 WHERE id = $2 AND state = 'scheduled' AND started_at IS NULL",
		d.version, id)
	if err != nil {
		d.markPgInvariantTerminal(err, "service.go:ExecuteUpgradeInline:claim")
		return fmt.Errorf("claim scheduled upgrade row %d: %w", id, err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("upgrade row %d no longer in 'scheduled' state (another actor claimed it first); re-run ./sb install after it finishes", id)
	}
	// Load the row's tags so the flag file captures the full commit identity.
	var commitTags []string
	_ = d.queryConn.QueryRow(ctx,
		"SELECT commit_tags FROM public.upgrade WHERE id = $1", id).Scan(&commitTags)
	return d.executeUpgrade(ctx, id, commitSHA, displayName, commitTags, "operator:install", "install-cli")
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
//	LabelRolledBackNormal        — rollback normal path: upgrade failed, git restore succeeded,
//	                               prior version restarted cleanly
//	LabelRolledBackAbort         — rollback ABORT: git restore itself failed; row is rolled_back
//	                               but the on-disk binary may be in an inconsistent state
//	LabelRolledBackCrashRecovery — recoverFromFlag: prior binary crashed mid-upgrade; new binary
//	                               could not self-heal and triggered a rollback to recover
//	LabelFailed                  — two sites: (1) completeInProgressUpgrade health check failed,
//	                               (2) failUpgrade explicit failure during executeUpgrade
const (
	LabelCompletedNormal         = "completed-normal"
	LabelCompletedSelfHeal       = "completed-self-heal"
	LabelCompletedFromInProgress = "completed-from-in-progress"
	LabelRolledBackNormal        = "rolled-back-normal"
	LabelRolledBackAbort         = "rolled-back-abort"
	LabelRolledBackCrashRecovery = "rolled-back-crash-recovery"
	LabelFailed                  = "failed"
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
//	ErrRollbackBinaryCorrupt — rollback could not restore ./sb from ./sb.old (operator must mv manually)
//	ErrBinaryReplaceFailed   — mid-flow binary replacement (download/verify/swap) failed before migrations
//	ErrBinaryBuildFailed     — mid-flow `make -C cli build` from source failed (edge channel; no release artifact)
//	ErrInstallFixupFailed    — post-upgrade ./sb install fixup step failed (non-fatal)
const (
	ErrMigrationFailed       = "MIGRATION_FAILED"
	ErrBackupFailed          = "BACKUP_FAILED"
	ErrDockerUpFailed        = "DOCKER_UP_FAILED"
	ErrHealthcheckRESTDown   = "HEALTHCHECK_REST_DOWN"
	ErrHealthcheckAppDown    = "HEALTHCHECK_APP_DOWN"
	ErrHealthcheckDBDown     = "HEALTHCHECK_DB_DOWN"
	ErrRollbackGitCorrupt    = "ROLLBACK_FAILED_GIT_CORRUPT"
	ErrRollbackDBRestore     = "ROLLBACK_FAILED_DB_RESTORE"
	ErrRollbackServicesUp    = "ROLLBACK_FAILED_SERVICES_UP"
	ErrRollbackBinaryCorrupt = "ROLLBACK_FAILED_BINARY_CORRUPT"
	ErrBinaryReplaceFailed   = "BINARY_REPLACE_FAILED"
	ErrBinaryBuildFailed     = "BINARY_BUILD_FAILED"
	ErrInstallFixupFailed    = "INSTALL_FIXUP_FAILED"
	// ErrInstallPreconditionFailed — an installable precondition was not
	// met at recovery time (binary SHA mismatch, migration gap, etc.).
	// Used by completeInProgressUpgrade's ground-truth check (task #49)
	// to mark rows FAILED rather than silently completing them.
	ErrInstallPreconditionFailed = "INSTALL_PRECONDITION_FAILED"
)

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

	// Load trusted commit signers for signature verification
	if err := d.loadTrustedSigners(); err != nil {
		return err
	}

	// Pre-flight: ensure DB is up. Idempotent (no-op when already up).
	// Always run — covers both the normal-boot path and the post-swap
	// recovery path where the prior process image exited 42 after stamping
	// Phase=post_swap and intentionally stopped the DB (applyPostSwap step 2
	// for the consistent backup). Without this pre-start, connect() would
	// fail against the stopped DB and systemd would loop-restart us before
	// recoverFromFlag → resumePostSwap → applyPostSwap ever runs.
	if flag, _, ferr := ReadFlagFile(d.projDir); ferr == nil && flag != nil &&
		flag.Holder == HolderService && flag.Phase == FlagPhasePostSwap {
		fmt.Printf("Post-swap flag detected at startup — ensuring DB is up before connecting (upgrade id=%d, target=%s)\n",
			flag.ID, flag.Label())
	}
	if err := d.EnsureDBUp(ctx); err != nil {
		return fmt.Errorf("ensure DB up: %w", err)
	}

	// Schema-skew guard (rc.65 structural fix). The binary's column-name
	// expectations must match the running schema before any service-level
	// query touches public.upgrade. Run `./sb migrate up` to bring the
	// schema to HEAD; idempotent — a no-op when already current.
	//
	// Background: rc.63 renamed three columns (version → commit_version,
	// from_version → from_commit_version, tags → commit_tags). When a new
	// binary boots against an unmigrated schema, ~23 SELECT/INSERT/UPDATE
	// sites in this file fail with SQLSTATE 42703. Rather than scatter
	// per-site compat shims, we migrate forward at boot. If migrate up
	// itself fails, refuse to enter the loop — operator must fix the
	// migration or restore the DB from backup.
	if err := runCommandToLog(d.projDir, 5*time.Minute, io.Discard, "boot-migrate-up",
		filepath.Join(d.projDir, "sb"), "migrate", "up", "--verbose"); err != nil {
		d.markTerminal("BOOT_MIGRATE_UP_FAILED",
			fmt.Sprintf("./sb migrate up at boot failed: %v; service refuses to enter the loop on a stale schema", err))
		return fmt.Errorf("boot migrate up: %w", err)
	}

	if err := d.connect(ctx); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer d.listenConn.Close(context.Background())
	defer d.queryConn.Close(context.Background())

	// Acquire advisory lock to prevent multiple instances
	if err := d.acquireAdvisoryLock(ctx); err != nil {
		return err
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

	// Complete any in-progress upgrade from a previous service instance
	// (e.g., after self-update restart via exit code 42)
	d.completeInProgressUpgrade(ctx)

	// Mark the currently running version as completed. Handles versions
	// installed via install.sh which bypasses the upgrade service flow.
	d.markCurrentVersionCompleted(ctx)

	// Sync UPGRADE_* config from .env to system_info table
	d.syncConfigToSystemInfo(ctx)

	// Clean stale maintenance file
	d.cleanStaleMaintenance(ctx)

	// Check for missed scheduled upgrades
	d.checkMissedUpgrades(ctx)

	// LISTEN on channels (must use listenConn — queryConn is for queries)
	if _, err := d.listenConn.Exec(ctx, "LISTEN upgrade_check"); err != nil {
		return fmt.Errorf("LISTEN upgrade_check: %w", err)
	}
	if _, err := d.listenConn.Exec(ctx, "LISTEN upgrade_apply"); err != nil {
		return fmt.Errorf("LISTEN upgrade_apply: %w", err)
	}

	fmt.Printf("Upgrade service started (channel=%s, interval=%s)\n", d.channel, d.interval)
	sdNotify("READY=1") // Tell systemd we're initialized

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

	// Initial discovery on startup
	d.discover(ctx)

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
		case <-ticker.C:
			fmt.Printf("Poll tick (next in %s)\n", d.interval)
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
				d.reconcileBackupDir(ctx)  // reconcile before prune: avoids BACKUP_MISSING for just-pruned rows
				d.pruneBackups(ctx, 3)
				d.pruneUpgradeLogs(20) // keep the 20 newest upgrade-log + bundle pairs
				d.runRetentionPurge(ctx, "all", nil) // time-safety sweep over public.upgrade
			}
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
func (d *Service) startListenLoop(ctx context.Context, notifyCh chan<- *pgconn.Notification, errCh chan<- error) {
	if d.listenCancel != nil {
		return // already running
	}
	listenCtx, cancel := context.WithCancel(ctx)
	d.listenCancel = cancel
	done := make(chan struct{})
	d.listenDone = done
	fmt.Println("listenLoop started (channels: upgrade_check, upgrade_apply)")
	go func() {
		defer close(done)
		d.listenLoop(listenCtx, notifyCh, errCh)
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
func (d *Service) listenLoop(ctx context.Context, notifyCh chan<- *pgconn.Notification, errCh chan<- error) {
	defer fmt.Printf("listenLoop exiting (ctx.Err=%v)\n", ctx.Err())
	for {
		notification, err := d.listenConn.WaitForNotification(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return // context canceled, clean exit
			}
			errCh <- err
			return
		}
		notifyCh <- notification
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
		// Parse optional :recreate suffix (e.g., "v2026.03.0:recreate")
		version := payload
		recreate := false
		if strings.HasSuffix(payload, ":recreate") {
			version = strings.TrimSuffix(payload, ":recreate")
			recreate = true
			fmt.Printf("Recreate mode requested for %s\n", version)
		}
		// No pre-validation: scheduleImmediate calls resolveUpgradeTarget,
		// which is the sole parser for operator/NOTIFY payloads. It accepts
		// CalVer tags, commit_sha, commit_short, and the legacy `sha-<hex>`
		// form the pre-Commit-B trigger emits (transitional). Bad payloads
		// surface as clear error messages from there.
		d.scheduleImmediate(ctx, version)
		if recreate {
			d.pendingRecreate = true
		}
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

// verifyUpgradeGroundTruth is the ground-truth verification step for
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
//   - DB query or on-disk read fails transiently: skip with a log line.
//     The next recovery cycle will retry.
func (d *Service) verifyUpgradeGroundTruth(ctx context.Context, rowCommitSHA string) (ok bool, reason string) {
	// Check 1: binary SHA at-or-descendant-of target.
	//
	//   binary == "" / "unknown"  → tier-1/tier-2 ambiguous; skip check
	//                                (degraded path per the docstring).
	//   binary == rowCommitSHA    → trivially success.
	//   `git merge-base --is-ancestor rowCommitSHA binary` exit 0
	//                              → binary descends from target; success.
	//                              The upgrade reached at-or-past the goal,
	//                              even if a later commit landed on top.
	//   error / non-ancestor       → conservative-false: the upgrade did
	//                              not advance to (or past) the target.
	//
	// Mirrors the pattern in resumePostSwap (search for
	// "binaryDescendsFlag") so the at-or-descendant predicate is uniform
	// across post-restart recovery paths.
	if d.binaryCommit == "" || d.binaryCommit == "unknown" {
		fmt.Printf("Ground-truth: binary SHA unknown (local build?); skipping binary check.\n")
	} else if d.binaryCommit != rowCommitSHA {
		binaryDescendsTarget := false
		if _, err := runCommandOutput(d.projDir, "git", "merge-base", "--is-ancestor", rowCommitSHA, d.binaryCommit); err == nil {
			binaryDescendsTarget = true
		}
		if !binaryDescendsTarget {
			return false, fmt.Sprintf(
				"binary commit %s != row target %s and is not its descendant (upgrade crashed before binary swap)",
				ShortForDisplay(d.binaryCommit), ShortForDisplay(rowCommitSHA))
		}
	}

	// Check 2: migration max version — DB vs on-disk
	var dbMaxVersion int64
	queryErr := d.queryConn.QueryRow(ctx,
		`SELECT COALESCE(MAX(version), 0) FROM db.migration`).Scan(&dbMaxVersion)
	if queryErr != nil {
		fmt.Printf("Ground-truth: DB migration-version query failed (%v); skipping migration check.\n", queryErr)
		return true, ""
	}

	diskMaxVersion := latestDiskMigrationVersion(d.projDir)
	if diskMaxVersion == 0 {
		// No on-disk migrations found (odd but non-fatal); skip check.
		fmt.Printf("Ground-truth: no on-disk migrations found; skipping migration check.\n")
		return true, ""
	}

	if dbMaxVersion < diskMaxVersion {
		return false, fmt.Sprintf(
			"db.migration max version %d < on-disk max %d (migrations did not run)",
			dbMaxVersion, diskMaxVersion)
	}

	return true, ""
}

// latestDiskMigrationVersion returns the max YYYYMMDDHHMMSS version number
// parsed from migrations/*.up.sql file basenames in projDir. Returns 0 when
// the directory is unreadable or empty. Used by verifyUpgradeGroundTruth to
// compare against db.migration's recorded max.
func latestDiskMigrationVersion(projDir string) int64 {
	entries, err := os.ReadDir(filepath.Join(projDir, "migrations"))
	if err != nil {
		return 0
	}
	var latest int64
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".up.sql") {
			continue
		}
		parts := strings.SplitN(name, "_", 2)
		if len(parts) == 0 {
			continue
		}
		v, convErr := strconv.ParseInt(parts[0], 10, 64)
		if convErr != nil {
			continue
		}
		if v > latest {
			latest = v
		}
	}
	return latest
}

// recoveryRollback is the recovery-path wrapper around d.rollback() used by
// completeInProgressUpgrade and recoverFromFlag (task #49). It bridges the
// recovery context — where we have an upgrade row id + log relative path
// but the in-process rollback() machinery expects a live ProgressLog and
// previousVersion string — to a real rollback invocation.
//
// User principle (task #49): every code path that today marks
// `failed`/`rolled_back` WITHOUT calling rollback() must now call it.
// "Status without reality-restore is a lie."
//
// Steps:
//  1. Read previousVersion from public.upgrade.from_version. If unreadable
//     or empty, fall back to d.version (the binary's running version).
//     A working previousVersion is what restoreGitState needs to know
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
func (d *Service) recoveryRollback(ctx context.Context, id int, displayName, logRelPath, reason string) {
	var fromVersion sql.NullString
	if err := d.queryConn.QueryRow(ctx,
		"SELECT from_commit_version FROM public.upgrade WHERE id = $1", id).Scan(&fromVersion); err != nil {
		fmt.Fprintf(os.Stderr, "recoveryRollback: could not read from_version for id=%d: %v\n", id, err)
	}
	prev := d.version
	if fromVersion.Valid && fromVersion.String != "" {
		prev = fromVersion.String
	}

	// Reopen the per-upgrade log in append mode so the rollback narrative
	// continues the existing file. AppendProgressLog returns nil when the
	// file is gone; in that case open a fresh log so rollback() has a
	// writable channel for its progress.Write calls.
	rollbackLog := AppendProgressLog(d.projDir, logRelPath)
	if rollbackLog == nil {
		rollbackLog = NewUpgradeLog(d.projDir, int64(id), displayName, time.Now().UTC())
	}
	defer rollbackLog.Close()

	d.rollback(ctx, id, displayName, prev, reason, rollbackLog)
}

// completeInProgressUpgrade checks for an upgrade that was started but not
// completed (e.g., service restarted after self-update). If found, verifies
// health and marks completed_at. This ensures "completed" truly means
// the new version is running and verified.
func (d *Service) completeInProgressUpgrade(ctx context.Context) {
	var id int
	var commitSHA string
	var displayName string
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, commit_sha,
		        COALESCE(commit_tags[array_upper(commit_tags, 1)], left(commit_sha, 8)) as display_name
		 FROM public.upgrade
		 WHERE state = 'in_progress'
		 LIMIT 1`).Scan(&id, &commitSHA, &displayName)
	if err != nil {
		return // no in-progress upgrade
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
	defer d.removeUpgradeFlag()

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

	// Ground-truth verification (task #49). The row is about to be marked
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
	// On failure, invoke d.rollback() — restores git/DB/binary/services
	// to the previous version and marks state='rolled_back'. The
	// alternative — just marking state='failed' — would leave the system
	// in a half-broken state that contradicts the row's claim.
	if ok, reason := d.verifyUpgradeGroundTruth(ctx, commitSHA); !ok {
		logRecover("Ground-truth verification FAILED for %s: %s", displayName, reason)
		if appendLog != nil {
			appendLog.Close()
			appendLog = nil
		}
		d.recoveryRollback(ctx, id, displayName, logRelPath, fmt.Sprintf(
			"%s: post-restart ground-truth check failed: %s",
			ErrInstallPreconditionFailed, reason))
		return
	}

	logRecover("Upgrade to %s completed (verified after service restart)", displayName)

	// Close the appender so the post-restart lines are flushed to disk
	// before we mark the row completed.
	if appendLog != nil {
		appendLog.Close()
		appendLog = nil
	}
	completedSQL := "UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready' WHERE id = $1" + upgradeRowReturning
	var fromInProgressJSON string
	var scanErr error
	for attempt := 0; attempt < 4; attempt++ {
		scanErr = d.queryConn.QueryRow(ctx, completedSQL, id).Scan(&fromInProgressJSON)
		if scanErr == nil {
			logUpgradeRow(LabelCompletedFromInProgress, fromInProgressJSON)
			break
		}
		if attempt < 3 && isConnError(scanErr) {
			time.Sleep(retryBackoff(attempt + 1))
			continue
		}
		// C4: POST_RESTART_COMPLETED_TRANSITION_PERSISTED — bounded retry
		// exhausted. Symmetric to C3; row was in_progress, we hold the flag,
		// CHECK permits in_progress → completed. Fail-fast + bundle.
		if dbName := d.markPgInvariantTerminal(scanErr, "service.go:completeInProgressUpgrade:completed"); dbName != "" {
			d.writeDiagnosticBundle(ctx, int(id), nil)
			break
		}
		fmt.Fprintf(os.Stderr,
			"INVARIANT POST_RESTART_COMPLETED_TRANSITION_PERSISTED violated: state transition to completed matched 0 rows or errored (id=%d, err=%v) after %d attempts (service.go:%d, pid=%d)\n",
			id, scanErr, attempt+1, thisLine(), os.Getpid())
		d.markTerminal("POST_RESTART_COMPLETED_TRANSITION_PERSISTED",
			fmt.Sprintf("id=%d; final Scan err=%v; attempts=%d", id, scanErr, attempt+1))
		d.writeDiagnosticBundle(ctx, int(id), nil)
		break
	}
	d.removeUpgradeFlag()

	// Skip older releases that are still "available" — no point upgrading to an older version
	d.supersedeOlderReleases(ctx, commitSHA)
	d.supersedeCompletedPrereleases(ctx, commitSHA)
	d.runUpgradeCallback(displayName)
}

// markCurrentVersionCompleted marks the service's own version as completed in
// the upgrade table. This handles versions deployed via install.sh (which
// bypasses the upgrade service flow) and ensures the UI doesn't show
// "Upgrade Now" for the already-running version. Idempotent.
//
// Task #49 / Gap #5: ground-truth check before the mark. Same blind spot
// as recoverFromFlag's success branch — git HEAD might match a row's
// commit_sha while the actual binary on disk is a prior version (crash
// between git checkout and replaceBinaryOnDisk). On startup, that would
// have us silently mark a "completed" upgrade we never actually ran.
//
// Resolution: if d.binaryCommit != git HEAD, the binary doesn't match
// the checked-out tree — skip the auto-mark and log. The operator's
// next install or the upgrade service's recovery path will reconcile.
func (d *Service) markCurrentVersionCompleted(ctx context.Context) {
	if d.version == "dev" {
		return
	}

	// Match by tag name or commit SHA
	headSHA, _ := runCommandOutput(d.projDir, "git", "rev-parse", "HEAD")
	headSHA = strings.TrimSpace(headSHA)

	// Ground-truth verification (task #49 Gap #5): verify the running binary
	// matches git HEAD AND that all required migrations have been applied.
	// verifyUpgradeGroundTruth checks both conditions; it returns false if
	// either condition fails. Demo bug (rc.63): binary=rc.63 ✓ but schema=rc.62
	// (migration not applied) — without this check, markCurrentVersionCompleted
	// would silently mark the row completed despite missing migrations.
	if ok, reason := d.verifyUpgradeGroundTruth(ctx, headSHA); !ok {
		fmt.Printf("markCurrentVersionCompleted: blocked — %s; "+
			"leaving row in_progress for proper applyPostSwap\n", reason)
		return
	}

	result, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade
		 SET state = 'completed',
		     completed_at = COALESCE(completed_at, now()),
		     docker_images_status = 'ready',
		     scheduled_at = NULL,
		     error = NULL,
		     rolled_back_at = NULL
		 WHERE commit_sha = $1
		   AND completed_at IS NULL`,
		headSHA)
	if err != nil {
		return
	}
	if result.RowsAffected() > 0 {
		fmt.Printf("Marked current version (%s) as completed\n", d.version)
		d.supersedeOlderReleases(ctx, headSHA)
		d.supersedeCompletedPrereleases(ctx, headSHA)
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
		d.queryConn.Exec(ctx,
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
		d.channel = "stable"
	}

	intervalStr := "6h"
	if v, ok := f.Get("UPGRADE_CHECK_INTERVAL"); ok {
		intervalStr = v
	}
	d.interval, err = time.ParseDuration(intervalStr)
	if err != nil {
		d.interval = 6 * time.Hour
	}

	d.autoDL = true
	if v, ok := f.Get("UPGRADE_AUTO_DOWNLOAD"); ok {
		d.autoDL = v == "true"
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
	os.MkdirAll(tmpDir, 0755)
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

func (d *Service) connect(ctx context.Context) error {
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return err
	}

	getOr := func(key, fallback string) string {
		if v, ok := f.Get(key); ok {
			return v
		}
		return fallback
	}

	// Connect to the Caddy DB proxy on the host's loopback address.
	// The service runs on the host (not inside Docker), so it reaches PostgreSQL
	// through Caddy's Layer4 proxy. CADDY_DB_BIND_ADDRESS is where Caddy listens
	// (typically 127.0.0.1). Using SITE_DOMAIN would resolve to the public IP,
	// which Caddy doesn't listen on in private deployment mode.
	//
	// No fallback defaults — if these are missing, the .env is broken and we
	// must fail loud rather than silently connect to the wrong place.
	requireKey := func(key string) (string, error) {
		if v, ok := f.Get(key); ok && v != "" {
			return v, nil
		}
		return "", fmt.Errorf("%s not found in .env — regenerate with: ./sb config generate", key)
	}

	dbHost, err := requireKey("CADDY_DB_BIND_ADDRESS")
	if err != nil {
		return err
	}
	dbPort, err := requireKey("CADDY_DB_PORT")
	if err != nil {
		return err
	}
	dbName, err := requireKey("POSTGRES_APP_DB")
	if err != nil {
		return err
	}
	dbUser, err := requireKey("POSTGRES_ADMIN_USER")
	if err != nil {
		return err
	}
	dbPass := getOr("POSTGRES_ADMIN_PASSWORD", "") // password CAN be empty (trust auth)

	connStr := fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
		dbHost, dbPort, dbName, dbUser, dbPass)

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

	d.listenConn, err = pgx.ConnectConfig(ctx, config)
	if err != nil {
		return fmt.Errorf("listen connection: %w", err)
	}
	d.queryConn, err = pgx.ConnectConfig(ctx, config)
	if err != nil {
		d.listenConn.Close(context.Background())
		return fmt.Errorf("query connection: %w", err)
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
		d.listenConn.Close(context.Background())
	}
	if d.queryConn != nil {
		d.queryConn.Close(context.Background())
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
	maintenanceFile := filepath.Join(os.Getenv("HOME"), "maintenance")
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
		os.Remove(maintenanceFile)
		fmt.Println("Cleaned stale maintenance file")
	}
}

func (d *Service) checkMissedUpgrades(ctx context.Context) {
	var count int
	err := d.queryConn.QueryRow(ctx,
		"SELECT COUNT(*) FROM public.upgrade WHERE state = 'scheduled'").Scan(&count)
	if err == nil && count > 0 {
		fmt.Printf("Found %d missed scheduled upgrade(s)\n", count)
	}
}

func (d *Service) discover(ctx context.Context) {
	if err := d.ensureConnected(ctx); err != nil {
		fmt.Printf("Reconnect failed in discover: %v\n", err)
		return
	}

	// Edge channel: discover commits AND release tags.
	// Commits for Docker container updates, tags for binary self-updates.
	if d.channel == "edge" {
		d.discoverEdge(ctx)
		// Fall through to also discover release tags below.
	}

	// Use git fetch for discovery — no API rate limit, no GITHUB_TOKEN needed.
	tags, err := DiscoverTagsViaGit(d.projDir)
	if err != nil {
		fmt.Printf("Discovery error: %v\n", err)
		return
	}

	filtered := FilterTagsByChannel(tags, d.channel)
	fmt.Printf("Discovery: %d tag(s) via git, %d match channel %q\n", len(tags), len(filtered), d.channel)

	// The service's compiled-in version — used to skip older releases.
	currentVersion := d.version

	for _, t := range filtered {
		// Skip releases older than or equal to what we're currently running.
		if CompareVersions(t.TagName, currentVersion) <= 0 {
			if d.verbose {
				fmt.Printf("  Skipping %s (not newer than %s)\n", t.TagName, currentVersion)
			}
			continue
		}

		// Determine release_status based on tag format.
		// Tags with "-" are prereleases, without "-" are full releases.
		// Manifest availability is checked at upgrade execution time, not discovery.
		targetStatus := "prerelease"
		if !t.Prerelease {
			targetStatus = "release"
		}

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
		result, err := d.queryConn.Exec(ctx,
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
			t.CommitSHA, t.PublishedAt, t.TagName, targetStatus, t.TagName)
		if err != nil {
			fmt.Printf("Failed to record release %s: %v\n", t.TagName, err)
			continue
		}

		if result.RowsAffected() > 0 {
			fmt.Printf("Discovered: %s (%s)\n", t.TagName, t.PublishedAt.Format("2006-01-02"))
		}
	}

	// Enrich existing rows with tag data. Separate from the discovery loop above
	// which only INSERTs rows for versions NEWER than current. This UPDATE pass
	// associates tags with commits already in the DB (e.g., from edge discovery),
	// regardless of whether the tag is newer, equal, or older than the service.
	for _, t := range filtered {
		targetStatus := "prerelease"
		if !t.Prerelease {
			targetStatus = "release"
		}
		d.queryConn.Exec(ctx,
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
	for _, t := range filtered {
		if _, err := FetchManifest(t.TagName); err == nil {
			d.queryConn.Exec(ctx,
				"UPDATE public.upgrade SET release_builds_status = 'ready' WHERE commit_sha = $1 AND release_builds_status != 'ready'",
				t.CommitSHA)
		} else {
			// Manifest not available — check if the release workflow failed.
			ciOutput, ciErr := runCommandOutput(d.projDir, "gh", "api",
				fmt.Sprintf("repos/statisticsnorway/statbus/actions/workflows/release.yaml/runs?head_sha=%s&status=completed&per_page=5", t.CommitSHA),
				"--jq", ".workflow_runs[] | .conclusion")
			if ciErr == nil && ciOutput != "" {
				conclusions := strings.Fields(strings.TrimSpace(ciOutput))
				hasSuccess := false
				hasFailure := false
				for _, c := range conclusions {
					if c == "success" {
						hasSuccess = true
					} else if c == "failure" {
						hasFailure = true
					}
				}
				if hasFailure && !hasSuccess {
					d.queryConn.Exec(ctx,
						"UPDATE public.upgrade SET release_builds_status = 'failed' WHERE commit_sha = $1 AND release_builds_status = 'building'",
						t.CommitSHA)
					fmt.Printf("Release build failed for %s\n", t.TagName)
				}
			}
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

	// Prune tags deleted upstream: remove from the tags array in the DB
	// any tags that no longer exist in git. If all tags are removed,
	// demote release_status back to 'commit'.
	d.pruneDeletedTags(ctx, filtered)

	if d.autoDL {
		d.preDownloadImages(ctx)
	}

	// Record last-discover timestamp for the admin UI "Last checked" display.
	// Best-effort — ignore error so observability noise never blocks the main path.
	_, _ = d.queryConn.Exec(ctx,
		`INSERT INTO public.system_info (key, value, updated_at)
		 VALUES ('upgrade_last_discover_at', now()::text, now())
		 ON CONFLICT (key) DO UPDATE
		   SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`)
}

// pruneDeletedTags removes tags from the upgrade table that no longer exist in git.
// When a tag is deleted upstream, git fetch --prune-tags removes it locally.
// This function syncs the database to match.
func (d *Service) pruneDeletedTags(ctx context.Context, currentTags []GitTag) {
	// Build set of tags that exist in git
	gitTags := make(map[string]bool, len(currentTags))
	for _, t := range currentTags {
		gitTags[t.TagName] = true
	}

	// Find rows with tags that no longer exist
	rows, err := d.queryConn.Query(ctx,
		`SELECT id, commit_tags FROM public.upgrade WHERE array_length(commit_tags, 1) > 0`)
	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() {
		var id int
		var tags []string
		if err := rows.Scan(&id, &tags); err != nil {
			continue
		}

		// Filter to only tags that still exist in git
		var kept []string
		for _, tag := range tags {
			if gitTags[tag] {
				kept = append(kept, tag)
			}
		}

		if len(kept) == len(tags) {
			continue // nothing pruned
		}

		// Update the row: remove deleted tags, demote status if all tags gone
		newStatus := "commit"
		for _, tag := range kept {
			if !strings.Contains(tag, "-") {
				newStatus = "release"
				break
			}
			newStatus = "prerelease"
		}

		d.queryConn.Exec(ctx,
			`UPDATE public.upgrade SET commit_tags = $1, release_status = $2::public.release_status_type WHERE id = $3`,
			kept, newStatus, id)
		fmt.Printf("Pruned deleted tags from upgrade %d: %v → %v (status: %s)\n", id, tags, kept, newStatus)
	}
}

// discoverEdge fetches recent master commits and makes them available.
// Uses git fetch — no API rate limit.
func (d *Service) discoverEdge(ctx context.Context) {
	commits, err := DiscoverCommitsViaGit(d.projDir, 5)
	if err != nil {
		fmt.Printf("Edge discovery error: %v\n", err)
		return
	}
	if len(commits) == 0 {
		return
	}

	fmt.Printf("Edge discovery: %d recent commit(s) from master\n", len(commits))

	for _, c := range commits {
		// Verify commit signature before recording
		if err := d.verifyCommitSignature(c.SHA); err != nil {
			fmt.Printf("Skipping edge commit %s: %v\n", ShortForDisplay(c.SHA), err)
			continue
		}

		summary := c.Summary
		if len(summary) > 120 {
			summary = summary[:120]
		}

		// release_builds_status='ready' for commits because edge channel
		// never needs release.yaml output (no self-update, no manifest).
		// docker_images_status defaults to 'building' and is set to 'ready'
		// by verifyArtifacts() once docker manifest inspect confirms the four
		// images, or to 'failed' if CI workflow failed.

		// Capture git describe output now so verifyArtifacts can look up
		// Docker images by a stable tag — the describe output changes as
		// new tags are pushed past this commit after discovery.
		versionTag, _ := runCommandOutput(d.projDir, "git", "describe", "--tags", "--always", c.SHA)
		versionTag = strings.TrimSpace(versionTag)

		_, err := d.queryConn.Exec(ctx,
			`INSERT INTO public.upgrade (commit_sha, committed_at, summary, has_migrations, release_builds_status, commit_version)
			 VALUES ($1, $2, $3, false, 'ready'::public.release_builds_status_type, NULLIF($4, ''))
			 ON CONFLICT (commit_sha) DO UPDATE SET commit_version = EXCLUDED.commit_version WHERE upgrade.commit_version IS NULL`,
			c.SHA, c.PublishedAt, summary, versionTag)
		if err != nil {
			fmt.Printf("  Failed to record commit %s: %v\n", ShortForDisplay(c.SHA), err)
		}
	}

	if d.autoDL {
		d.preDownloadImages(ctx)
	}
}

func (d *Service) preDownloadImages(ctx context.Context) {
	rows, err := d.queryConn.Query(ctx,
		`SELECT commit_sha,
		        COALESCE(commit_tags[array_upper(commit_tags, 1)], left(commit_sha, 8)) as display_name
		 FROM public.upgrade
		 WHERE docker_images_downloaded = false AND state IN ('available', 'scheduled')
		 ORDER BY discovered_at LIMIT 3`)
	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() {
		var commitSHA, displayName string
		if err := rows.Scan(&commitSHA, &displayName); err != nil {
			continue
		}

		fmt.Printf("Pre-downloading images for %s...\n", displayName)

		// pullImages needs a version for the VERSION env var — use display name (tag or sha-prefix)
		if err := d.pullImages(displayName); err != nil {
			fmt.Printf("Pre-download failed for %s: %v\n", displayName, err)
			continue
		}

		d.queryConn.Exec(ctx,
			"UPDATE public.upgrade SET docker_images_downloaded = true WHERE commit_sha = $1",
			commitSHA)
	}
}

// scheduleImmediate routes an operator-supplied upgrade target through
// the parser, then upserts a scheduled row. The input may be a full
// 40-char commit_sha, an 8-char commit_short, or a CalVer release tag
// (see resolveUpgradeTarget for the parse contract).
func (d *Service) scheduleImmediate(ctx context.Context, input string) {
	target, err := resolveUpgradeTarget(ctx, d, input)
	if err != nil {
		fmt.Printf("Cannot resolve %q: %v\n", input, err)
		return
	}

	var commitSHA CommitSHA
	var tagsToStore []string
	var displayName string
	switch t := target.(type) {
	case TaggedTarget:
		commitSHA = t.SHA
		tagsToStore = []string{string(t.Tag)}
		displayName = string(t.Tag)
	case UntaggedTarget:
		commitSHA = t.SHA
		tagsToStore = nil // stored as NULL → COALESCE to '{}' in SQL
		displayName = string(commitShort(t.SHA))
	default:
		fmt.Printf("unhandled UpgradeTarget type %T\n", target)
		return
	}

	// Reset lifecycle fields so a completed/failed upgrade can be re-applied.
	// The WHERE clause prevents updating a row that's already in 'scheduled' state.
	// Without this guard, the UPDATE changes scheduled_at to now() →
	// upgrade_notify_daemon_trigger fires → sends NOTIFY upgrade_apply →
	// service calls scheduleImmediate again → infinite loop.
	result, err := d.queryConn.Exec(ctx,
		`INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, summary, scheduled_at, state)
		 VALUES ($1, now(), COALESCE($3::text[], '{}'::text[]), $2, now(), 'scheduled')
		 ON CONFLICT (commit_sha) DO UPDATE SET
		   state = 'scheduled',
		   scheduled_at = now(),
		   started_at = NULL,
		   completed_at = NULL,
		   error = NULL,
		   rolled_back_at = NULL,
		   skipped_at = NULL,
		   dismissed_at = NULL,
		   superseded_at = NULL,
		   log_relative_file_path = NULL
		 WHERE public.upgrade.state != 'scheduled'`,
		string(commitSHA), displayName, tagsToStore)
	if err != nil {
		d.markPgInvariantTerminal(err, "service.go:scheduleImmediate:upsert")
		fmt.Printf("Failed to schedule %s: %v\n", displayName, err)
	} else if result.RowsAffected() > 0 {
		fmt.Printf("Scheduled immediate upgrade to %s\n", displayName)
		// Once a commit is selected, all older ones are obsolete.
		d.supersedeOlderReleases(ctx, string(commitSHA))
	} else {
		fmt.Printf("Version %s already scheduled, no action needed\n", displayName)
	}
}

// --- CommitLookup implementation -------------------------------------
//
// Service satisfies the CommitLookup interface used by
// resolveUpgradeTarget (see commit.go). These methods are the
// DB/git-accessing primitives; all shape detection lives in commit.go.

// LookupSHAByTag satisfies CommitLookup.
func (d *Service) LookupSHAByTag(ctx context.Context, tag ReleaseTag) (CommitSHA, bool, error) {
	var sha string
	err := d.queryConn.QueryRow(ctx,
		"SELECT commit_sha FROM public.upgrade WHERE $1 = ANY(commit_tags) LIMIT 1",
		string(tag)).Scan(&sha)
	if err != nil {
		// pgx returns ErrNoRows or similar on empty result; treat as not-found.
		return "", false, nil
	}
	return CommitSHA(sha), true, nil
}

// RevParse satisfies CommitLookup.
func (d *Service) RevParse(_ context.Context, ref string) (CommitSHA, error) {
	out, err := runCommandOutput(d.projDir, "git", "rev-parse", ref)
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

func (d *Service) executeScheduled(ctx context.Context) {
	if err := d.ensureConnected(ctx); err != nil {
		return
	}
	var id int
	var commitSHA string
	var commitTags []string
	var scheduledAt time.Time
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, commit_sha, commit_tags, scheduled_at
		 FROM public.upgrade
		 WHERE state = 'scheduled'
		   AND scheduled_at <= now()
		 ORDER BY scheduled_at LIMIT 1`).Scan(&id, &commitSHA, &commitTags, &scheduledAt)
	if err != nil {
		return // no pending upgrades
	}
	displayName := renderDisplayName(CommitSHA(commitSHA), commitTags)
	fmt.Printf("Claiming id=%d, lag=%s\n", id, time.Since(scheduledAt).Truncate(time.Second))

	// Claim immediately: mark started_at + state='in_progress' so the UI
	// shows "In Progress" and the user can no longer unschedule.
	// State guard makes the claim safe against a racing inline install
	// (./sb install dispatching StateScheduledUpgrade): whichever UPDATE
	// commits first wins, the other gets 0 rows affected and bails.
	tag, err := d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET state = 'in_progress', started_at = now(), from_commit_version = $1 WHERE id = $2 AND state = 'scheduled' AND started_at IS NULL",
		d.version, id)
	if err != nil {
		d.markPgInvariantTerminal(err, "service.go:executeScheduled:claim")
		fmt.Printf("UPGRADE_CLAIM_FAILED: could not claim scheduled upgrade id=%d: %v\n", id, err)
		return
	}
	if tag.RowsAffected() == 0 {
		fmt.Printf("Scheduled upgrade id=%d already claimed by another actor; skipping.\n", id)
		return
	}

	fmt.Printf("Executing upgrade to %s...\n", displayName)
	// Invoker context for the flag file: the row was picked up from the scheduled queue.
	// This covers admin-UI "Apply now", NOTIFY upgrade_apply from ./sb upgrade apply-latest,
	// and the discovery loop's auto-schedule — we don't currently distinguish among them
	// at this layer. Later improvement: record originator in public.upgrade when scheduling.
	if err := d.executeUpgrade(ctx, id, commitSHA, displayName, commitTags, "scheduled", "scheduled"); err != nil {
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
// --inside-active-upgrade flag and STATBUS_INSIDE_ACTIVE_UPGRADE=1 env var.
func (d *Service) executeUpgrade(ctx context.Context, id int, commitSHA, displayName string, commitTags []string, invokedBy, trigger string) error {
	d.upgrading = true
	defer func() { d.upgrading = false }()

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

	progress.Write("Upgrading to %s (from %s)...", displayName, d.version)
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
	if out, err := runCommandOutput(projDir, "git", "log", "-1", "--pretty=%s", commitSHA); err == nil {
		if subj := strings.TrimSpace(out); subj != "" {
			progress.Write("  Target commit: %s", subj)
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
		if CompareVersions(displayName, d.version) < 0 {
			// TODO: pick code — downgrade precondition; consider adding ErrInstallPreconditionFailed
			msg := fmt.Sprintf("Version %s is older than current version %s. Downgrades are not supported. To restore a previous state, use: ./sb db backup restore <name>", displayName, d.version)
			d.failUpgrade(ctx, id, msg, progress)
			return fmt.Errorf("%s", msg)
		}
	}

	// Verify release manifest and binary exist before starting.
	// If CI hasn't finished building, unschedule and return — not an error.
	// Only tagged releases have a manifest; untagged commits skip this check.
	if ValidateVersion(displayName) {
		progress.Write("Verifying release assets available...")
		manifest, err := FetchManifest(displayName)
		if err != nil {
			// CI not ready — unschedule without setting error. Reset to
			// 'available' + clear started_at so the CHECK constraint holds
			// (state='available' requires all lifecycle timestamps NULL).
			// The service will flip docker_images_status and release_builds_status
			// on the next discovery cycle when CI finishes, re-enabling "Upgrade Now".
			d.queryConn.Exec(ctx,
				"UPDATE public.upgrade SET state = 'available', scheduled_at = NULL, started_at = NULL, from_commit_version = NULL WHERE id = $1", id)
			progress.Write("Release assets not ready for %s — unscheduled. Will be available when CI finishes.", displayName)
			return nil
		}
		platform := selfupdate.Platform()
		if _, ok := manifest.Binaries[platform]; !ok {
			msg := fmt.Sprintf("release %s has no binary for platform %s — upgrade cannot proceed without a matching binary", displayName, platform)
			d.failUpgrade(ctx, id, msg, progress)
			return fmt.Errorf("%s", msg)
		}
	}

	// Check disk space. Need room for backup (~= DB size) + new images (~2GB).
	// Refuse to start if less than 5GB free to avoid mid-upgrade disk-full failures.
	if freeBytes, err := DiskFree(d.projDir); err == nil {
		freeGB := freeBytes / (1024 * 1024 * 1024)
		if freeGB < 5 {
			// TODO: pick code — disk-space preflight; consider ErrRollbackGitDiskFull or a new ErrInstallPreconditionFailed
			msg := fmt.Sprintf("Insufficient disk space: %d GB free (need at least 5 GB for backup + images)", freeGB)
			d.failUpgrade(ctx, id, msg, progress)
			return fmt.Errorf("%s", msg)
		}
		progress.Write("Disk space: %d GB free", freeGB)
	}

	// Re-verify commit signature before proceeding.
	// This defends against DB tampering between discovery and execution.
	progress.Write("Verifying commit signature...")
	if err := d.verifyCommitSignature(commitSHA); err != nil {
		// TODO: pick code — signature verification; consider adding ErrInstallPreconditionFailed
		msg := fmt.Sprintf("Commit %s signature verification failed: %v", ShortForDisplay(commitSHA), err)
		d.failUpgrade(ctx, id, msg, progress)
		return fmt.Errorf("%s", msg)
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
	if err := d.writeUpgradeFlag(id, commitSHA, commitTags, invokedBy, trigger, d.pendingRecreate); err != nil {
		// TODO: pick code — mutex flag acquisition failure; consider adding ErrInstallPreconditionFailed
		msg := fmt.Sprintf("Could not acquire upgrade-mutex flag file: %v", err)
		d.failUpgrade(ctx, id, msg, progress)
		return fmt.Errorf("%s", msg)
	}
	progress.Write("Upgrade-flag file written; taking ownership of the upgrade pipeline.")

	// started_at and from_version were already set by executeScheduled() when
	// it claimed this task. From this point on, the maintenance guard will activate.

	// Step 1: Prepare images
	// Fine-grained progress lines bracket each state transition here so that
	// if the service hangs (as seen on statbus_dev Apr 23 2026 — task #37),
	// the LAST journalctl line identifies the exact step that failed to
	// return. Zero behaviour change; pure observability.
	progress.Write("Preparing images...")
	pullStart := time.Now()

	// pullImages is the one step in executeUpgrade that can legitimately
	// exceed the 120s watchdog window (large registry pulls over slow
	// links). Emit a periodic "still pulling" progress line so each tick
	// fires emitHeartbeat and systemd sees liveness. 30s cadence matches
	// the main-loop heartbeatTicker's; net effect is at most ~30s of
	// silence between watchdog pings regardless of where the main
	// goroutine is executing.
	//
	// Known blind spot: this ticker fires from a background goroutine.
	// If pullImages hangs and the main goroutine is stuck inside
	// cmd.Run, the ticker keeps pinging and systemd doesn't restart.
	// Bounded by pullImages' own 10-minute ctx timeout (see exec.go:160)
	// — cmd.Run returns at the 10-min mark even on subprocess hang, so
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
				progress.Write("Still preparing images (%s elapsed)...",
					time.Since(pullStart).Truncate(time.Second))
			}
		}
	}()
	pullErr := d.pullImages(displayName)
	close(pullDone)
	if pullErr != nil {
		d.failUpgrade(ctx, id, fmt.Sprintf("%s: Failed to pull images for %s: %v", ErrDockerUpFailed, displayName, pullErr), progress)
		return pullErr
	}
	progress.Write("Images prepared (elapsed %s).", time.Since(pullStart).Truncate(time.Millisecond))

	// Pre-compute backup stamp and record the .tmp path in the DB before the
	// DB connection is closed.  The stamp ties the on-disk directory name to
	// the DB row so reconcileBackupDir can detect crashed or missing backups.
	backupStamp := time.Now().UTC().Format("20060102T150405Z")
	backupTmpPath := filepath.Join(d.backupRoot(), "pre-upgrade-"+backupStamp+".tmp")

	// L2 — stale-connection detection before the first DB write after the
	// multi-second pullImages step. pullImages leaves queryConn idle for the
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
		progress.Write("Stale queryConn detected before backup_path UPDATE (Ping: %v) — reconnecting...", pingErr)
		if reErr := d.reconnect(ctx); reErr != nil {
			progress.Write("Reconnect failed: %v — proceeding; reconcileBackupDir can still correlate via on-disk stamp if the Exec also fails.", reErr)
		} else {
			progress.Write("queryConn reconnected successfully.")
		}
	}

	progress.Write("Recording backup path on upgrade row (id=%d, path=%s)...", id, backupTmpPath)
	if _, err := d.queryConn.Exec(ctx, "UPDATE public.upgrade SET backup_path = $1 WHERE id = $2", backupTmpPath, id); err != nil {
		// Not fatal: the recovery path can still locate the backup via the
		// on-disk stamp if the DB write didn't land. Log and proceed.
		progress.Write("Warning: backup_path UPDATE failed: %v (proceeding — reconcileBackupDir can still correlate via stamp)", err)
	} else {
		progress.Write("Backup path recorded.")
	}

	// Step 2: Enter maintenance mode and restart proxy first
	// Guards let one-shot callers (./sb install inline upgrade) reach
	// executeUpgrade without a listenConn.
	progress.Write("Stopping listen-loop goroutine (canceling listener context)...")
	d.stopListenLoop()
	progress.Write("Listen-loop goroutine stopped.")
	if d.listenConn != nil {
		progress.Write("Closing listen connection to the database...")
		d.listenConn.Close(context.Background())
		d.listenConn = nil
		progress.Write("Listen connection closed.")
	}
	if d.queryConn != nil {
		progress.Write("Closing query connection to the database...")
		d.queryConn.Close(context.Background())
		d.queryConn = nil
		progress.Write("Query connection closed.")
	}
	progress.Write("Entering maintenance mode...")
	d.setMaintenance(true)
	progress.Write("Maintenance mode active (~/maintenance file written; Caddy now returns 503).")

	// Step 3: Stop application services (proxy stays running for maintenance page).
	// Hard error: running services during backup risk inconsistent state.
	progress.Write("Stopping application services...")
	if err := runCommand(projDir, "docker", "compose", "stop", "app", "worker", "rest"); err != nil {
		errMsg := fmt.Sprintf("could not stop application services before backup: %v", err)
		progress.Write("FAILED: %s", errMsg)
		runCommand(projDir, "docker", "compose", "up", "-d", "app", "worker", "rest")
		d.setMaintenance(false)
		if reconErr := d.reconnect(ctx); reconErr == nil {
			d.failUpgrade(ctx, id, errMsg, progress)
		} else {
			d.removeUpgradeFlag()
		}
		return fmt.Errorf("%s", errMsg)
	}

	// Step 4: Stop database for consistent backup.
	// Hard error: rsync of a running Postgres data dir is NOT crash-consistent.
	progress.Write("Stopping database...")
	if err := runCommand(projDir, "docker", "compose", "stop", "db"); err != nil {
		errMsg := fmt.Sprintf("could not stop database for consistent backup: %v", err)
		progress.Write("FAILED: %s", errMsg)
		runCommand(projDir, "docker", "compose", "up", "-d", "app", "worker", "rest", "db")
		d.setMaintenance(false)
		if reconErr := d.reconnect(ctx); reconErr == nil {
			d.failUpgrade(ctx, id, errMsg, progress)
		} else {
			d.removeUpgradeFlag()
		}
		return fmt.Errorf("%s", errMsg)
	}

	// Pin the pre-upgrade commit as a persistent branch BEFORE we touch
	// anything destructive. The branch survives process crashes and tag
	// pruning — restoreGitState falls back to it if `previousVersion`
	// (a tag or describe-string) won't resolve later. Best-effort: log
	// failure, don't abort the upgrade.
	if out, err := runCommandOutput(projDir, "git", "branch", "-f", "pre-upgrade", "HEAD"); err != nil {
		progress.Write("Warning: could not pin pre-upgrade branch: %v\n%s", err, out)
	}

	// Step 5: Backup database
	progress.Write("Backing up database...")
	previousVersion := d.version
	backupPath, err := d.backupDatabase(progress, backupStamp)
	if err != nil {
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: %v", ErrBackupFailed, err), progress)
		return err
	}

	// Step 6: Install new version — always fetch/checkout by commit SHA directly.
	// No --depth 1: the discovery phase already fetched origin/master, so objects are local.
	// Keeping full history ensures git-describe can find tags for config generate (VERSION).
	progress.Write("Installing %s...", displayName)
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "git", "git", "fetch", "origin", commitSHA); err != nil {
		// TODO: pick code — forward git fetch failure; no Err* code covers install-time git errors yet
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("git fetch %s: %v", ShortForDisplay(commitSHA), err), progress)
		return err
	}
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "git", "git", "-c", "advice.detachedHead=false", "checkout", commitSHA); err != nil {
		// TODO: pick code — forward git checkout failure; no Err* code covers install-time git errors yet
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("git checkout %s: %v", ShortForDisplay(commitSHA), err), progress)
		return err
	}

	// Verify checked-out SHA matches manifest (detect tag spoofing).
	// Only tagged releases carry a manifest; untagged commits skip.
	if ValidateVersion(displayName) {
		if manifest, mErr := FetchManifest(displayName); mErr == nil && manifest.CommitSHA != "" {
			if checkedOut, gErr := runCommandOutput(projDir, "git", "rev-parse", "HEAD"); gErr == nil {
				checkedOut = strings.TrimSpace(checkedOut)
				if !strings.HasPrefix(checkedOut, manifest.CommitSHA) && !strings.HasPrefix(manifest.CommitSHA, checkedOut) {
					// TODO: pick code — tag-tampering detection; consider adding ErrInstallPreconditionFailed
					errMsg := fmt.Sprintf("Version verification failed: expected commit %s but got %s. Possible tag tampering.",
						ShortForDisplay(manifest.CommitSHA), ShortForDisplay(checkedOut))
					progress.Write("%s", errMsg)
					d.rollback(ctx, id, displayName, previousVersion, errMsg, progress)
					return fmt.Errorf("%s", errMsg)
				}
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
	//   - edge commit:    buildBinaryOnDisk runs `make -C cli build`
	//
	// Both produce ./sb at the target commit and preserve ./sb.old for
	// rollback. Both upgrades go through the same swap+handoff plumbing,
	// so every upgrade exercises the path — no rarely-run "skip handoff"
	// branch can rot silently (the failure mode that bit edge in rc.70).
	var (
		procureErr  error
		procureCode string
	)
	if ValidateVersion(displayName) {
		procureErr = d.replaceBinaryOnDisk(displayName, progress)
		procureCode = ErrBinaryReplaceFailed
	} else {
		procureErr = d.buildBinaryOnDisk(displayName, progress)
		procureCode = ErrBinaryBuildFailed
	}
	if procureErr != nil {
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: %v", procureCode, procureErr), progress)
		return procureErr
	}

	// Stamp the flag as post-swap and store the finalised backup path so
	// the next process (after exit-42 restart or syscall.Exec) can roll
	// back without a live DB connection. queryConn was closed back at
	// Step 2 for the consistent-backup stop, so we can't persist to
	// public.upgrade here — the flag file is the handoff channel.
	if err := d.updateFlagPostSwap(backupPath); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("stamp post_swap flag: %v", err), progress)
		return err
	}
	progress.Write("Binary swapped on disk. Handing off to fresh process on the new code...")
	progress.Close()

	// Hand off to fresh process. Mechanism differs by mode; the semantic
	// (next process sees post_swap flag → dispatches resumePostSwap →
	// re-enters the pipeline at applyPostSwap) is the same.
	if d.runningAsService {
		// systemd-managed daemon: exit-42 → unit restarts on the new binary.
		os.Exit(42)
	}
	// Install-inline (one-shot foreground): replace this process image
	// with the new ./sb in-place. argv/env preserved; the new binary
	// hits recoverFromFlag at startup and resumes at applyPostSwap.
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

// applyPostSwap runs the upgrade steps that require the target binary's
// compiled code: config generate → docker pull → db up → waitForDBHealth →
// reconnect → persist final backup_path → migrate → app/worker/rest up →
// health check → maintenance off → archive → install-fixup → state=completed.
//
// Single entry point: resumePostSwap, dispatched by recoverFromFlag when
// a fresh process (post exit-42 systemd restart for service mode, post
// syscall.Exec for inline mode) sees Phase=FlagPhasePostSwap. Every
// upgrade — tagged or edge, service or inline — handsoff in executeUpgrade
// before reaching here, so applyPostSwap always runs against the NEW
// compiled Go code.
//
// Preconditions on entry: db container stopped; maintenance mode on; backup
// on disk at backupPath; git HEAD at target commit; ./sb binary at target
// version; d.queryConn is nil (reopened via reconnect() below). Flag file
// and its flock are held by d.flagLock.
func (d *Service) applyPostSwap(ctx context.Context, id int, commitSHA, displayName, previousVersion, backupPath string, recreate bool, progress *ProgressLog) error {
	projDir := d.projDir

	// Regenerate config via the NEW binary. VERSION comes from git describe
	// --tags --always against the just-checked-out HEAD.
	progress.Write("Regenerating configuration...")
	if err := runCommandToLog(projDir, 2*time.Minute, progress.File(), "config-generate", filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
		// TODO: pick code — config generate failure; no Err* code defined yet
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("./sb config generate: %v", err), progress)
		return err
	}

	// Step 8: Pull updated images
	progress.Write("Pulling updated images...")
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "docker-compose", "docker", "compose", "pull"); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: docker compose pull: %v", ErrDockerUpFailed, err), progress)
		return err
	}

	// Step 9: Start database. --no-build forces compose to USE THE PULLED IMAGE
	// and fail if it's absent, rather than silently falling back to a local
	// build from source (which for the db service means compiling pgrx
	// extensions — pg_graphql, sql_saga_native, jsonb_stats — from Rust/cargo,
	// a 10+ minute operation that blows past the 5m command timeout and gives
	// no useful error). If the image isn't in the registry yet, CI hasn't
	// built it. Tell the operator to wait for ci-images.yaml and retry.
	progress.Write("Starting database...")
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "docker-compose", "docker", "compose", "up", "-d", "--no-build", "db"); err != nil {
		reason := fmt.Sprintf(
			"%s: docker compose up -d db: %v\n\n"+
				"The db image for %s is not available locally or in the registry. "+
				"CI builds images on every master push (ci-images.yaml); commit-tagged "+
				"images take a few minutes to land. Wait for that workflow to finish, "+
				"then retry the upgrade. Check status: "+
				"gh run list --workflow=ci-images.yaml",
			ErrDockerUpFailed, err, displayName)
		d.rollback(ctx, id, displayName, previousVersion, reason, progress)
		return err
	}

	// Wait for DB health
	progress.Write("Waiting for database to be healthy...")
	if err := d.waitForDBHealth(30 * time.Second); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: DB health check: %v", ErrHealthcheckDBDown, err), progress)
		return err
	}

	// Reconnect service DB connection
	progress.Write("Reconnecting to database...")
	if err := d.reconnect(ctx); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: reconnect to DB: %v", ErrHealthcheckDBDown, err), progress)
		return err
	}

	// Update backup_path to the final (renamed) path now that we have a connection.
	// Log on failure: the DB still holds the .tmp path; reconcileBackupDir will
	// emit BACKUP_MISSING on the next tick for the missing .tmp, surfacing the issue.
	if _, err := d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET backup_path = $1 WHERE id = $2", backupPath, id); err != nil {
		progress.Write("Warning: could not update backup_path to final path for upgrade id=%d: %v", id, err)
	}

	// Step 10: Run migrations (or recreate database if requested).
	// `recreate` arrives via parameter (from d.pendingRecreate at pre-swap time,
	// or from flag.Recreate after a post-swap restart). d.pendingRecreate is
	// reset to false so a subsequent upgrade doesn't accidentally recreate.
	if recreate {
		d.pendingRecreate = false
		progress.Write("Recreating database from scratch (--recreate)...")
		if err := runCommandToLog(projDir, 30*time.Minute, progress.File(), "recreate-database", filepath.Join(projDir, "dev.sh"), "recreate-database"); err != nil {
			d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: ./dev.sh recreate-database: %v", ErrMigrationFailed, err), progress)
			return err
		}
	} else {
		progress.Write("Applying database migrations...")
		if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "migrate", filepath.Join(projDir, "sb"), "migrate", "up", "--verbose"); err != nil {
			d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: ./sb migrate up: %v", ErrMigrationFailed, err), progress)
			return err
		}
	}

	// Step 11: Start application services (proxy already running from step 2).
	// --no-build for the same reason as step 9: the app/worker/rest images
	// must come from the registry, not a local build that may time out.
	progress.Write("Starting services...")
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "docker-compose", "docker", "compose", "up", "-d", "--no-build", "app", "worker", "rest"); err != nil {
		reason := fmt.Sprintf(
			"%s: docker compose up -d app worker rest: %v\n\n"+
				"One or more application images for %s are not available locally or in the registry. "+
				"CI builds images on every master push (ci-images.yaml). "+
				"Wait for that workflow to finish, then retry the upgrade. Check status: "+
				"gh run list --workflow=ci-images.yaml",
			ErrDockerUpFailed, err, displayName)
		d.rollback(ctx, id, displayName, previousVersion, reason, progress)
		return err
	}

	// Step 12: Verify health
	progress.Write("Verifying health...")
	if err := d.healthCheck(progress, 5, 5*time.Second); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: application health check: %v", ErrHealthcheckRESTDown, err), progress)
		return err
	}

	// Notify frontend that the upgrade state changed. The DB trigger also fires
	// NOTIFY on completed_at UPDATE, but there's a race: the app's LISTEN may not
	// be established when completed_at is set. This explicit NOTIFY after the health
	// check guarantees the app is listening.
	d.queryConn.Exec(ctx, `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)

	// Done — deactivate maintenance, archive, finalize
	fmt.Println("Deactivating maintenance (app healthcheck passed)")
	d.setMaintenance(false)
	d.archiveBackup(backupPath, displayName)

	fmt.Printf("Upgrade to %s completed successfully\n", displayName)

	// selfUpdate is intentionally NOT invoked here: Option C moved the
	// binary-swap handoff earlier (right after replaceBinaryOnDisk in
	// executeUpgrade) so the current process is already running the target
	// binary. A second exit-42 here would be a no-op systemd restart
	// costing ~30s of extra downtime for nothing.

	// Mark complete. Task rune-stuck fix A (Apr 24): the terminal UPDATE
	// MUST happen BEFORE runInstallFixup, not after. Install-fixup runs
	// `./sb install --inside-active-upgrade` which triggers docker
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
	completedSQL := "UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready' WHERE id = $1" + upgradeRowReturning
	var lastScanErr error
	for attempt := 0; attempt < 4; attempt++ {
		// C6: on retry following a stale-connection error, refresh the pool
		// before issuing the UPDATE. If reconnect itself errors the pool is
		// unrecoverable in this process — fail fast.
		if attempt > 0 && isConnError(lastScanErr) {
			log.Printf("Connection stale on state=completed UPDATE (id=%d, err=%v), reconnecting...", id, lastScanErr)
			if reconErr := d.reconnect(ctx); reconErr != nil {
				fmt.Fprintf(os.Stderr,
					"INVARIANT RECONNECT_ON_STALE_CONN_SUCCEEDS violated: reconnect after stale conn on id=%d failed: %v (service.go:%d, pid=%d)\n",
					id, reconErr, thisLine(), os.Getpid())
				d.markTerminal("RECONNECT_ON_STALE_CONN_SUCCEEDS",
					fmt.Sprintf("id=%d; reconnect err=%v", id, reconErr))
				d.writeDiagnosticBundle(ctx, id, progress)
				return fmt.Errorf("RECONNECT_ON_STALE_CONN_SUCCEEDS: %w", reconErr)
			}
		}
		lastScanErr = d.queryConn.QueryRow(ctx, completedSQL, id).Scan(&normalJSON)
		if lastScanErr == nil {
			break
		}
		if attempt < 3 && isConnError(lastScanErr) {
			time.Sleep(retryBackoff(attempt + 1))
			continue
		}
		// C7: terminal UPDATE errored (non-conn error, or retry budget exhausted).
		// If the error is a DB-enforced invariant (e.g. chk_upgrade_state_attributes
		// log-pointer arm), prefer the specific name so the support bundle surfaces
		// the precise cause rather than the generic transition-persisted name.
		if dbName := d.markPgInvariantTerminal(lastScanErr, "service.go:applyPostSwap:completed-terminal"); dbName != "" {
			d.writeDiagnosticBundle(ctx, id, progress)
			return fmt.Errorf("%s: %w", dbName, lastScanErr)
		}
		fmt.Fprintf(os.Stderr,
			"INVARIANT NORMAL_COMPLETED_TRANSITION_PERSISTED violated: terminal state transition to completed errored for id=%d: %v after %d attempts (service.go:%d, pid=%d)\n",
			id, lastScanErr, attempt+1, thisLine(), os.Getpid())
		d.markTerminal("NORMAL_COMPLETED_TRANSITION_PERSISTED",
			fmt.Sprintf("id=%d; final Scan err=%v; attempts=%d", id, lastScanErr, attempt+1))
		d.writeDiagnosticBundle(ctx, id, progress)
		return fmt.Errorf("NORMAL_COMPLETED_TRANSITION_PERSISTED: %w", lastScanErr)
	}
	log.Println("state=completed")
	logUpgradeRow(LabelCompletedNormal, normalJSON)
	d.removeUpgradeFlag()
	// Pre-upgrade branch is no longer needed — successful completion
	// means we're committed to the new version. Best-effort delete; if
	// the branch is missing (best-effort create at the start failed),
	// the -D returns non-zero and we just move on.
	runCommand(d.projDir, "git", "branch", "-D", "pre-upgrade")
	d.supersedeOlderReleases(ctx, commitSHA)
	d.supersedeCompletedPrereleases(ctx, commitSHA)
	// Retention pass scoped to the just-installed row: rules A/B/C fire
	// (same-family prereleases, stale commits) so admins aren't stuck
	// with obsolete dogfood entries after a release lands. Must run AFTER
	// supersedeOlderReleases — rule D's ranking depends on the older
	// releases' new 'superseded' state.
	d.runRetentionPurge(ctx, "all", &id)
	d.runUpgradeCallback(displayName)

	// Now the row is truly `completed` (UPDATE + removeUpgradeFlag done),
	// emit the operator-facing "complete!" line and run the post-success
	// install fixup. See the "Mark complete" comment above for the
	// ordering rationale. Fixup can restart docker services (including
	// db) — that's fine here because we're past the terminal UPDATE;
	// anything that breaks after this point is a fixup-side concern the
	// operator can re-run idempotently.
	progress.Write("Upgrade to %s complete!", displayName)

	// Run idempotent install to apply any new infrastructure (systemd service,
	// directories, config fixes). Install steps skip what's already done.
	// This exercises the install path on every upgrade, catching install bugs early.
	//
	// The flag file has already been removed above. Install's upgrade-mutex
	// check sees no flag and proceeds normally, but we keep the
	// --inside-active-upgrade flag + STATBUS_INSIDE_ACTIVE_UPGRADE=1 env var
	// for audit-trail + belt-and-suspenders in case a future install path
	// adds additional mutex checks.
	progress.Write("Running install fixups...")
	if err := runInstallFixup(projDir); err != nil {
		progress.Write("%s: post-upgrade install fixups failed: %v", ErrInstallFixupFailed, err)
		// Non-fatal — the upgrade itself succeeded and the row reflects it.
	}

	return nil
}

// resumePostSwap re-enters the upgrade pipeline in the new binary after a
// mid-flow exit-42 restart. Called from recoverFromFlag when the flag's
// Phase is FlagPhasePostSwap.
//
// Recovers state from: flag (CommitSHA, CommitTags, BackupPath, Recreate,
// InvokedBy, Trigger, ID) and DB row (from_commit_version,
// log_relative_file_path). Then re-acquires the flock (prior process died,
// kernel released it), reopens the progress log in append mode, and calls
// applyPostSwap.
//
// Schema-skew note: the SELECT below uses the rc.63 column name
// `from_commit_version`. The boot-time `./sb migrate up` in Service.Run()
// guarantees the schema is at HEAD before resumePostSwap is reached, so no
// per-site compat shim is needed for renamed columns.
//
// Control returns to Run() after applyPostSwap completes. If applyPostSwap
// fails, rollback() has already run inside it.
func (d *Service) resumePostSwap(ctx context.Context, flag UpgradeFlag) error {
	var fromVersion sql.NullString
	var logRelPath sql.NullString
	err := d.queryConn.QueryRow(ctx,
		"SELECT from_commit_version, log_relative_file_path FROM public.upgrade WHERE id = $1", flag.ID).
		Scan(&fromVersion, &logRelPath)
	if err != nil {
		return fmt.Errorf(
			"resumePostSwap: cannot load upgrade %d state (err=%v) — leaving flag for manual triage",
			flag.ID, err)
	}

	// Reopen the progress log. Append-mode so the narrative is continuous
	// across the restart. If the file is missing (manual tmp cleanup), fall
	// through to a fresh log so the resume path still reports progress.
	progress := AppendProgressLog(d.projDir, logRelPath.String)
	if progress == nil {
		progress = NewUpgradeLog(d.projDir, int64(flag.ID), flag.Label(), time.Now().UTC())
	}
	progress.Write("Post-swap restart detected — resuming upgrade on new binary (pid=%d)", os.Getpid())

	// Ground-truth guard (task #49 Gap #6, rune-stuck fix). If the
	// running binary's compile-time commit SHA doesn't match the flag's
	// target commit SHA, the flag is stale: a subsequent install
	// advanced the server past this in_progress upgrade without
	// clearing the flag. Running applyPostSwap in this state would
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
		log.Printf("resumePostSwap: containers healthy at %s (sha %s) — self-healing row %d to completed",
			flag.Label(), ShortForDisplay(flag.CommitSHA), flag.ID)
		var selfHealJSON string
		err := d.queryConn.QueryRow(ctx,
			"UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_status = 'ready' WHERE id = $1 AND state = 'in_progress'"+upgradeRowReturning,
			flag.ID).Scan(&selfHealJSON)
		if err == nil {
			logUpgradeRow(LabelCompletedSelfHeal, selfHealJSON)
			d.queryConn.Exec(ctx, `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)
			os.Remove(d.flagPath())
			d.supersedeOlderReleases(ctx, flag.CommitSHA)
			d.supersedeCompletedPrereleases(ctx, flag.CommitSHA)
			progress.Write("Post-swap self-heal: containers already at %s; row %d marked completed without re-running applyPostSwap.",
				flag.Label(), flag.ID)
			progress.Close()
			return nil
		}
		// UPDATE didn't land (ErrNoRows: row already terminal; or
		// chk_upgrade_state_attributes violation: row carries an `error`
		// the constraint forbids on completed). Fall through to the
		// continuation path — re-acquire flock and resume applyPostSwap
		// from where the prior process died. The continuation handles
		// its own terminal-row idempotency.
		log.Printf("resumePostSwap: self-heal UPDATE skipped for row %d (err=%v) — falling through to continuation",
			flag.ID, err)
	} else {
		// Containers don't match flag's target. The discriminator is
		// the running binary's commit relative to flag.CommitSHA:
		//
		// (a) Normal mid-pipeline state. Binary was just swapped on
		//     disk by replaceBinaryOnDisk; old containers were stopped
		//     before swap; new containers haven't been started yet
		//     (that's literally applyPostSwap's job below). The running
		//     process IS the freshly-restarted post-swap binary, so
		//     d.binaryCommit == flag.CommitSHA exactly. Continue.
		//
		// (b) Operator-driven recovery roll-forward. The operator
		//     deployed a binary newer than the stuck flag's target to
		//     fix this exact wedge. d.binaryCommit is a DESCENDANT of
		//     flag.CommitSHA — the new binary subsumes everything the
		//     flag's target could do (its column-name expectations,
		//     its compose template, its post-swap steps). Continuing
		//     is safe; the new binary's applyPostSwap brings the
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
			progress.Write("Post-swap recovery: containers do not match flag target %s, AND running binary %s is not at or descendant of flag target. Mismatched: %v",
				flag.Label(), ShortForDisplay(d.binaryCommit), mismatched)
			progress.Close()
			return fmt.Errorf(
				"post-swap recovery: containers do not match flag target %s and running binary %s is not at or descendant of flag target.\n"+
					"  Mismatched: %v\n"+
					"  This is a category-3 divergence per the recovery trifecta — the\n"+
					"  running binary is BEHIND the flag's target (or on a sibling branch).\n"+
					"  Continuing would query a schema newer than the binary speaks.\n"+
					"  Investigate `docker compose ps` and the upgrade-progress log;\n"+
					"  ./sb install will resume after the divergence is resolved.",
				flag.Label(), ShortForDisplay(d.binaryCommit), mismatched)
		}
		if binaryDescendsFlag {
			progress.Write("Post-swap continuation: binary %s is descendant of flag target %s — operator-driven roll-forward, continuing via applyPostSwap (mismatched: %v).",
				ShortForDisplay(d.binaryCommit), flag.Label(), mismatched)
		} else {
			progress.Write("Post-swap continuation: binary at target %s; containers stopped mid-pipeline (mismatched: %v). Resuming via applyPostSwap.",
				flag.Label(), mismatched)
		}
	}

	// Re-acquire the flock on the flag file. The prior holder's fd was
	// released by the kernel at exit; the file on disk still has our
	// Phase=post_swap stamp.
	reacquired := UpgradeFlag{
		ID:         flag.ID,
		CommitSHA:  flag.CommitSHA,
		CommitTags: flag.CommitTags,
		PID:        os.Getpid(),
		StartedAt:  time.Now(),
		InvokedBy:  flag.InvokedBy,
		Trigger:    flag.Trigger,
		Holder:     HolderService,
		Phase:      FlagPhasePostSwap,
		Recreate:   flag.Recreate,
		BackupPath: flag.BackupPath,
	}
	lock, lerr := acquireFlock(d.projDir, reacquired)
	if lerr != nil {
		progress.Write("resumePostSwap: re-acquire flock failed: %v", lerr)
		progress.Close()
		return fmt.Errorf("resumePostSwap: re-acquire flock: %w", lerr)
	}
	d.flagLock = lock
	d.upgrading = true
	defer func() { d.upgrading = false }()

	if applyErr := d.applyPostSwap(ctx, flag.ID, flag.CommitSHA, flag.Label(), fromVersion.String, flag.BackupPath, flag.Recreate, progress); applyErr != nil {
		// rollback() already ran inside applyPostSwap and (post-rc.67)
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
	d.runCallback(displayName, nil)
}

// runCallback executes the UPGRADE_CALLBACK shell command from .env, if
// set, with the given displayName context plus any extraEnv overlay.
// Used by both the success path (no extraEnv) and the rollback-failure
// path (passes STATBUS_ROLLBACK_FAILED=1 and recovery context so the
// callback script — typically ops/notify-slack.sh — can branch on
// outcome). Never fails the upgrade; logs errors but always returns.
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
//   - pullImages (downloads images but doesn't touch live DB or services)
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
	// Always release the mutex on failure paths, even those that don't run
	// rollback (e.g., pullImages failure returns directly after failUpgrade).
	// removeUpgradeFlag is idempotent — safe when no flag was acquired (some
	// failUpgrade callers run before writeUpgradeFlag during pre-flight).
	d.removeUpgradeFlag()
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
			os.WriteFile(path, []byte(fmt.Sprintf("# capture failed: %v\n", err)), 0644)
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

func (d *Service) rollback(ctx context.Context, id int, version, previousVersion, reason string, progress *ProgressLog) {
	progress.Write("Upgrade failed — rolling back to previous version...")
	progress.Write("Reason: %s", reason)

	projDir := d.projDir

	// Capture failure-time container logs BEFORE the docker compose stop
	// destroys the running containers. The rollback later does
	// `docker compose up -d --remove-orphans` which recreates fresh
	// containers — without this snapshot, the REST 5xx body, db
	// startup output, and app connection-attempt logs that explain
	// the failure are gone forever.
	captureContainerLogs(projDir, progress, []string{"rest", "app", "worker", "db"})

	// Stop everything before we touch the git tree or restore the DB.
	runCommand(projDir, "docker", "compose", "stop", "app", "worker", "rest", "db")

	// Restore git state. If this FAILS we MUST NOT bring the application
	// services back up — they would run NEW code against the just-restored
	// OLD database, the exact silent-data-corruption scenario rollback
	// exists to prevent. Restore the database first so the on-disk state
	// is consistent (old DB + old code is recoverable; new code + old DB
	// is not), then ABORT before docker compose up.
	if previousVersion != "" {
		if err := d.restoreGitState(previousVersion, progress); err != nil {
			progress.Write("ABORT: rollback could not restore git state to %s: %v", previousVersion, err)
			progress.Write("Restoring database to keep on-disk state consistent...")
			d.restoreDatabase(progress)
			// Restore ./sb to match the attempted-but-failed git era so the
			// operator's `./sb` at least stops being the NEW (mismatched)
			// binary. Best-effort: if it fails, we log ErrRollbackBinaryCorrupt
			// and move on — the ABORT headline below already escalates.
			d.restoreBinary(progress)
			progress.Write("Services will NOT be started — manual intervention required.")
			progress.Write("    1. Manually checkout the intended previous version: git checkout %s", previousVersion)
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
			fmt.Fprintf(os.Stderr, "ABORT: rollback git restore to %s failed: %v\n", previousVersion, err)

			rollbackFailedMsg := fmt.Sprintf("%s: %v (originally: %s)", ErrRollbackGitCorrupt, err, reason)
			// Bundle BEFORE the ABORT UPDATE so a forensic inspection of
			// a wedged `rolled_back` row has the sibling .bundle.txt.
			d.writeDiagnosticBundle(ctx, id, progress)
			if d.queryConn != nil {
				var abortJSON string
				if scanErr := d.queryConn.QueryRow(ctx,
					"UPDATE public.upgrade SET state = 'rolled_back', error = $1, rolled_back_at = now() WHERE id = $2"+upgradeRowReturning,
					rollbackFailedMsg, id).Scan(&abortJSON); scanErr == nil {
					logUpgradeRow(LabelRolledBackAbort, abortJSON)
				}
			}
			// Page on-call via the configured callback (Slack, etc.).
			// extraEnv tells the script to render a distinctive
			// rollback-failure alert with the recovery command body.
			hostname, _ := os.Hostname()
			d.runCallback(version, map[string]string{
				"STATBUS_ROLLBACK_FAILED": "1",
				"STATBUS_ROLLBACK_ERROR":  err.Error(),
				"STATBUS_RECOVERY_CMD":    fmt.Sprintf(`ssh %s "cd statbus && ./sb install"`, hostname),
			})
			// Maintenance stays ON — operator must complete the manual rollback steps above.
			// Release the flock so the operator's prescribed step 4
			// (`./sb install`) can proceed: leaving the flock held would
			// wedge install with StateLiveUpgrade.
			// The on-disk JSON persists as the audit cue; the next install's
			// RecoverFromFlag pass is a no-op against the rolled_back row
			// (guarded by `state = 'in_progress'` since 2026-04-22) and
			// just removes the file.
			d.removeUpgradeFlag()

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
		// Restore ./sb to match the restored git era BEFORE running config
		// generate (rc.67 trifecta). The current ./sb is the NEW binary; its
		// PersistentPreRun staleness guard (rc.65 freshness check) compares
		// the binary's compile-time COMMIT against git HEAD, which is now at
		// previousVersion. The guard fires exit-2 → "Warning: config generate
		// during rollback failed" (jo's 2026-04-28 deploy log line 105).
		// Restoring the binary first puts ./sb back at the same era as the
		// rolled-back git tree, so the staleness guard sees a match and
		// config generate runs cleanly. Best-effort; ErrRollbackBinaryCorrupt
		// is logged (non-fatal) if the rename fails.
		d.restoreBinary(progress)

		if err := runCommandToLog(projDir, 2*time.Minute, progress.File(), "rollback-config-generate", filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
			progress.Write("Warning: config generate during rollback failed: %v", err)
		}
	}

	// Restore database backup. Now safe — git state matches the DB era.
	d.restoreDatabase(progress)

	// Start with old config — git is verified at previousVersion.
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "rollback-docker-up", "docker", "compose", "--profile", "all", "up", "-d", "--remove-orphans"); err != nil {
		progress.Write("%s: docker compose up failed after rollback: %v", ErrRollbackServicesUp, err)
	}

	// Reconnect (may fail if DB didn't come back)
	if err := d.reconnect(ctx); err != nil {
		progress.Write("Warning: could not reconnect after rollback: %v", err)
	}

	// Deactivate maintenance
	d.setMaintenance(false)

	// Persist the real failure reason in `error` (short, one-line). The
	// full narrative lives in the on-disk log (referenced by
	// log_relative_file_path) and is fetched by the admin UI's "Log"
	// collapsible via /upgrade-logs/<name>.
	errMsg := reason
	if reason == "" {
		errMsg = "Rollback completed (no reason captured — caller did not pass one)"
	}
	// Bundle BEFORE the terminal UPDATE so a support ticket on any
	// `rolled_back` row has the sibling .bundle.txt available.
	d.writeDiagnosticBundle(ctx, id, progress)
	if d.queryConn != nil {
		var rollbackJSON string
		if scanErr := d.queryConn.QueryRow(ctx,
			"UPDATE public.upgrade SET state = 'rolled_back', error = $1, rolled_back_at = now() WHERE id = $2"+upgradeRowReturning,
			errMsg, id).Scan(&rollbackJSON); scanErr == nil {
			logUpgradeRow(LabelRolledBackNormal, rollbackJSON)
		}
	}

	// Clear the in-progress flag: the rollback has restored a consistent state,
	// so the mutex that blocks `./sb install` must be released. Without this,
	// the flag lingers until the next service restart, wedging all future installs.
	d.removeUpgradeFlag()

	progress.Write("Rollback complete. The previous version has been restored.")

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
// The previousVersion may be a tag, branch, or full SHA. Whatever
// `git rev-parse --verify <ref>^{commit}` resolves to is the expected
// HEAD after checkout.
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
	log("Restoring git state to %s...", previousVersion)

	// Pre-validate: refuse to checkout a ref we can't resolve. If the
	// requested ref is gone, fall back to the persistent `pre-upgrade`
	// branch before erroring out.
	expectedOut, err := runCommandOutput(projDir, "git", "rev-parse", "--verify", previousVersion+"^{commit}")
	if err != nil {
		log("Ref %s does not resolve, falling back to pre-upgrade...", previousVersion)
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
	if err := runCommandToLog(projDir, 5*time.Minute, logWriter, "rollback-git-checkout", "git", "-c", "advice.detachedHead=false", "checkout", "-f", previousVersion); err != nil {
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

	log("Git state restored to %s (HEAD %s)", previousVersion, ShortForDisplay(headSHA))
	return nil
}

// readProgressLogTail returns the last `n` lines of the version-specific
// upgrade progress log, or "" if the file is absent or unreadable. Used by
// rollback() to embed the real failure narrative into public.upgrade.error.
func readProgressLogTail(path string, n int) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
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
	progress.Write("Replacing ./sb with %s binary (subsequent subprocesses will run the new code)...", version)
	if err := selfupdate.ReplaceBinaryOnDisk(sbPath, binary.URL, binary.SHA256); err != nil {
		return err
	}
	progress.Write("./sb replaced; ./sb.old kept as rollback.")
	return nil
}

// buildBinaryOnDisk compiles ./sb from the just-checked-out cli/ tree and
// swaps it in, mirroring replaceBinaryOnDisk for tagged releases. Called
// mid-flow in executeUpgrade for edge commits, where no release artifact
// exists in any GitHub manifest.
//
// Build inputs come from cli/Makefile: VERSION=$(git describe --tags),
// COMMIT=$(git rev-parse HEAD). Since git checkout already moved HEAD to
// the target, the resulting binary's compile-time commit matches HEAD
// and the freshness check in subsequent ./sb subprocesses passes.
//
// Atomicity: rename ./sb → ./sb.old, then `make -C cli build` writes
// directly to ../sb (i.e. ./sb) using Go's tempfile-then-rename. There
// is a brief window between the .old rename and Go's rename where ./sb
// does not exist — safe inside the upgrade pipeline because maintenance
// mode is on, all services are stopped, and the only ./sb consumer is
// this very process which is busy running `make`.
//
// On failure: rename .old back to ./sb so the deploy host isn't left
// without a usable binary. The caller (executeUpgrade) then invokes
// rollback() with ErrBinaryBuildFailed.
func (d *Service) buildBinaryOnDisk(displayName string, progress *ProgressLog) error {
	sbPath := filepath.Join(d.projDir, "sb")
	sbOldPath := sbPath + ".old"

	if err := os.Rename(sbPath, sbOldPath); err != nil {
		return fmt.Errorf("preserve ./sb.old: %w", err)
	}
	progress.Write("Building ./sb from source for edge commit %s...", displayName)
	if err := runCommandToLog(d.projDir, 5*time.Minute, progress.File(),
		"make-build-sb", "make", "-C", "cli", "build"); err != nil {
		// Restore .old so the host still has a working ./sb after rollback.
		if rerr := os.Rename(sbOldPath, sbPath); rerr != nil {
			return fmt.Errorf("make -C cli build failed AND ./sb.old restore failed: build=%v restore=%v", err, rerr)
		}
		return fmt.Errorf("make -C cli build: %w", err)
	}
	progress.Write("./sb rebuilt; ./sb.old kept as rollback.")
	return nil
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
func (d *Service) restoreBinary(progress *ProgressLog) {
	sbPath := filepath.Join(d.projDir, "sb")
	sbOldPath := sbPath + ".old"
	if _, err := os.Stat(sbOldPath); err != nil {
		// ENOENT is the legitimate "swap never happened" case — silent no-op.
		// Anything else (EPERM, EIO, ELOOP) means we can't even tell whether
		// there's a rollback candidate; log loudly so the operator can
		// investigate. Matches selfupdate.Rollback's own ENOENT handling.
		if !os.IsNotExist(err) {
			progress.Write("%s: could not stat ./sb.old: %v — manual recovery may be required", ErrRollbackBinaryCorrupt, err)
		}
		return
	}
	if err := selfupdate.Rollback(sbPath); err != nil {
		progress.Write("%s: could not restore ./sb from ./sb.old: %v — manual recovery: mv ./sb.old ./sb", ErrRollbackBinaryCorrupt, err)
		return
	}
	progress.Write("Restored ./sb from ./sb.old.")
}

func (d *Service) selfUpdate(ctx context.Context, version string, progress *ProgressLog) {
	manifest, err := FetchManifest(version)
	if err != nil {
		progress.Write("Self-update skipped: cannot fetch manifest for %s: %v", version, err)
		return
	}

	// Skip if local code is ahead of the release (edge channel: HEAD has
	// commits beyond the tag). Prevents downgrading to an older release binary.
	if manifest.CommitSHA != "" {
		ahead, _ := runCommandOutput(d.projDir, "git", "log", "--oneline", "HEAD", "^"+manifest.CommitSHA)
		if strings.TrimSpace(ahead) != "" {
			progress.Write("Self-update skipped: local code is ahead of release %s", version)
			return
		}
	}

	platform := selfupdate.Platform()
	binary, ok := manifest.Binaries[platform]
	if !ok {
		progress.Write("Self-update skipped: no binary for platform %s in release %s", platform, version)
		return
	}

	sbPath := filepath.Join(d.projDir, "sb")
	progress.Write("Self-updating binary...")
	swapped, err := selfupdate.Update(sbPath, binary.URL, binary.SHA256)
	if err != nil {
		msg := fmt.Sprintf("Self-update failed for %s: %v", version, err)
		progress.Write("%s", msg)
		fmt.Fprintln(os.Stderr, msg)
		// Record in system_info so admins can see the failure
		if d.queryConn != nil {
			d.queryConn.Exec(ctx,
				`INSERT INTO public.system_info (key, value, updated_at) VALUES ('self_update_error', $1, now())
				 ON CONFLICT (key) DO UPDATE SET value = $1, updated_at = now()`, msg)
		}
		return
	}

	if swapped {
		progress.Write("Binary updated. Restarting service...")
	} else {
		// Mid-flow replaceBinaryOnDisk already placed the target binary;
		// end-of-flow self-update was a pure no-op. Log honestly so the
		// narrative on disk / in maintenance.html doesn't lie about what
		// just happened. Restart is still required — the running service
		// process is still holding the old binary image in memory.
		progress.Write("Binary already at target (swapped mid-flow). Restarting service...")
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
		SourceLocation:   "cli/internal/upgrade/service.go:markCIImagesFailed",
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

