package upgrade

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/selfupdate"
)

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
	listenWg     sync.WaitGroup     // tracks listenLoop goroutine lifetime
	allowedSignersPath string      // path to tmp/allowed-signers file (empty if no signers configured)
	flagLock           *FlagLock   // holds the flock on tmp/upgrade-in-progress.json during executeUpgrade
}

// NewService creates a new upgrade service.
func NewService(projDir string, verbose bool, version string) *Service {
	return &Service{
		projDir: projDir,
		version: version,
		verbose: verbose,
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
	ID          int       `json:"id"`           // 0 when Holder=="install"
	CommitSHA   string    `json:"commit_sha"`   // "" when Holder=="install"
	DisplayName string    `json:"display_name"` // version OR install description
	PID         int       `json:"pid"`          // os.Getpid() at write time
	StartedAt   time.Time `json:"started_at"`   // time.Now() at write time
	InvokedBy   string    `json:"invoked_by"`   // specific trigger (e.g. "notify:v2026.04.1", "operator:jhf")
	Trigger     string    `json:"trigger"`      // coarse bucket ("notify"|"scheduled"|"recovery"|"install")
	Holder      string    `json:"holder"`       // HolderService or HolderInstall
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
func (d *Service) writeUpgradeFlag(id int, commitSHA, displayName, invokedBy, trigger string) error {
	flag := UpgradeFlag{
		ID:          id,
		CommitSHA:   commitSHA,
		DisplayName: displayName,
		PID:         os.Getpid(),
		StartedAt:   time.Now(),
		InvokedBy:   invokedBy,
		Trigger:     trigger,
		Holder:      HolderService,
	}
	lock, err := acquireFlock(d.projDir, flag)
	if err != nil {
		return err
	}
	d.flagLock = lock
	return nil
}

// removeUpgradeFlag releases the service's flock. On crash the kernel
// does this automatically; this is the graceful-completion path.
func (d *Service) removeUpgradeFlag() {
	if d.flagLock != nil {
		d.flagLock.Close()
		d.flagLock = nil
	}
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
func AcquireInstallFlag(projDir, displayName, invokedBy string) (*FlagLock, error) {
	flag := UpgradeFlag{
		DisplayName: displayName,
		PID:         os.Getpid(),
		StartedAt:   time.Now(),
		InvokedBy:   invokedBy,
		Trigger:     "install",
		Holder:      HolderInstall,
	}
	return acquireFlock(projDir, flag)
}

// ReleaseInstallFlag releases the install flock by closing the fd.
// Accepts the *FlagLock returned by AcquireInstallFlag. Safe to call
// multiple times; safe to call with a nil lock.
func ReleaseInstallFlag(lock *FlagLock) {
	lock.Close()
}

// formatContentionError builds the operator-facing message for a failed
// AcquireInstallFlag. Branches on Holder + alive to produce one of:
//   - live service: "upgrade in progress, wait"
//   - live install: "another install running, wait"
//   - dead any:    "previous {upgrade|install} crashed — run upgrade recover"
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
				flag.PID, flag.DisplayName, flag.InvokedBy)
		default: // HolderService
			return fmt.Errorf(
				"an orchestrated upgrade is in progress: PID %d (%s, invoked_by=%s).\n\n"+
					"  Wait for it to complete:\n"+
					"    journalctl --user -u 'statbus-upgrade@*' -f\n\n"+
					"  Do NOT pass --inside-active-upgrade — that flag is the upgrade service's\n"+
					"  internal contract with its own post-upgrade install step. Using it from the\n"+
					"  command line would corrupt an upgrade that is currently running.",
				flag.PID, flag.DisplayName, flag.InvokedBy)
		}
	}
	verb := "upgrade"
	if holder == HolderInstall {
		verb = "install"
	}
	return fmt.Errorf(
		"a prior %s crashed or was stopped mid-run: flag file references PID %d (%s, invoked_by=%s)\n"+
			"but that process is no longer alive.\n\n"+
			"  Reconcile the stale flag, then retry:\n"+
			"    ./sb upgrade recover\n\n"+
			"  (Equivalent: systemctl --user start 'statbus-upgrade@*' — the service's startup\n"+
			"  handler runs the same reconciliation.)",
		verb, flag.PID, flag.DisplayName, flag.InvokedBy)
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
func (d *Service) recoverFromFlag(ctx context.Context) {
	data, err := os.ReadFile(d.flagPath())
	if err != nil {
		return // no flag file — normal startup
	}

	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		fmt.Printf("Warning: corrupt upgrade flag file, removing: %v\n", err)
		os.Remove(d.flagPath())
		return
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
		holder, flag.DisplayName, flag.ID, flag.PID, flag.InvokedBy)

	// Refuse to clean up another live process's state. The `flag.PID != os.Getpid()`
	// check is defensive — in practice it can't match (this function runs at
	// service startup or via the freshly-spawned `./sb upgrade recover`, both
	// of which have PIDs distinct from any prior holder). The load-bearing
	// check is `pidAlive(flag.PID)`: a live PID means an actor still owns
	// the flag and we must not touch it (service-holder collision indicates
	// advisory-lock violation; install-holder collision means an operator is
	// actively installing — neither is ours to reconcile).
	if flag.PID > 0 && flag.PID != os.Getpid() && pidAlive(flag.PID) {
		logRecover("REFUSING to recover: %s flag owned by live PID %d. Leaving flag in place. Investigate manually.",
			holder, flag.PID)
		return
	}

	// Install-held flag from a crashed install. The flock was released by
	// the kernel when the install's fd closed; the on-disk JSON is pure
	// audit now. Install never writes public.upgrade, so there's no DB
	// state to reconcile — delete the stale file so tmp/ stays tidy and
	// inspecting the directory doesn't suggest something is in flight.
	// (If install ever grows DB-write semantics, add reconciliation here.)
	if holder == HolderInstall {
		logRecover("Clearing stale install flag (PID %d crashed or exited without releasing)", flag.PID)
		os.Remove(d.flagPath())
		return
	}

	// Service-held flag: reconcile against public.upgrade.
	// Check if the upgrade actually succeeded (self-update restart via exit code 42).
	// If git HEAD matches the upgrade target, the code is at the right version.
	headSHA, _ := runCommandOutput(d.projDir, "git", "rev-parse", "HEAD")
	headSHA = strings.TrimSpace(headSHA)
	if headSHA == flag.CommitSHA {
		logRecover("Upgrade %s succeeded (HEAD matches target commit — self-update restart detected)", flag.DisplayName)
		// Close the appender BEFORE reading the tail so the flush lands
		// on disk and the UPDATE below captures the recovery lines.
		if appendLog != nil {
			appendLog.Close()
			appendLog = nil
		}
		var selfHealJSON string
		if err := d.queryConn.QueryRow(ctx,
			"UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_ready = true WHERE id = $1 AND completed_at IS NULL"+upgradeRowReturning,
			flag.ID).Scan(&selfHealJSON); err != nil {
			fmt.Printf("WARN: state transition to completed matched 0 rows or errored (id=%d, err=%v) — possible CHECK constraint violation\n", flag.ID, err)
		} else {
			logUpgradeRow(LabelCompletedSelfHeal, selfHealJSON)
		}
		// Explicit NOTIFY — the DB trigger also fires, but the app's LISTEN is
		// definitely established by now (new service starts after app is healthy).
		d.queryConn.Exec(ctx, `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)
		// The stale flag has now been reconciled — remove the on-disk
		// file so the next executeUpgrade's acquireFlock starts from a
		// clean state. (The kernel flock was already released when the
		// prior service process died.)
		os.Remove(d.flagPath())
		d.supersedeOlderReleases(ctx, flag.CommitSHA)
		return
	}

	// Real failure. The file we've been appending to already contains the
	// pre-crash narrative PLUS our "Service restarted" line above; add
	// the failure summary and use the tail to derive a short `error`.
	logRecover("HEAD (%s) does not match upgrade target (%s). Treating as failed upgrade.",
		shortSHA(headSHA), shortSHA(flag.CommitSHA))
	logRecover("Marking upgrade %d (%s) as rolled_back", flag.ID, flag.DisplayName)

	// Close the appender before reading so pending writes are flushed.
	if appendLog != nil {
		appendLog.Close()
		appendLog = nil
	}

	// Grab the tail of the full log to build a short error summary. The
	// full narrative lives in the on-disk log (served via /upgrade-logs/)
	// so we only need the last handful of lines here.
	logTail := readProgressLogTail(UpgradeLogAbsPath(d.projDir, logRelPath), 50)
	// TODO: pick code — crash-recovery errMsg is derived from log tail; need to
	// inspect the last line for an existing Err* prefix before adding one here.
	errMsg := "Upgrade interrupted (service crashed or was killed)"
	if logTail != "" {
		lines := strings.Split(strings.TrimSpace(logTail), "\n")
		if len(lines) > 5 {
			lines = lines[len(lines)-5:]
		}
		errMsg = strings.Join(lines, "\n")
	}

	// Mark the upgrade as rolled_back in the DB. rolled_back_at +
	// error + state='rolled_back' — the CHECK requires all three together.
	var crashJSON string
	if scanErr := d.queryConn.QueryRow(ctx,
		"UPDATE public.upgrade SET state = 'rolled_back', error = $1, rolled_back_at = now() WHERE id = $2 AND completed_at IS NULL"+upgradeRowReturning,
		errMsg, flag.ID).Scan(&crashJSON); scanErr != nil {
		fmt.Printf("Warning: could not mark upgrade %d as rolled_back: %v\n", flag.ID, scanErr)
	} else {
		logUpgradeRow(LabelRolledBackCrashRecovery, crashJSON)
	}

	// Reconciled — remove the on-disk file. The kernel flock was already
	// released when the prior service process died.
	os.Remove(d.flagPath())
}

// shortSHA trims a 40-char git SHA down to 12 for display. Returns the
// input unchanged if it's already shorter.
func shortSHA(sha string) string {
	if len(sha) > 12 {
		return sha[:12]
	}
	return sha
}

// verifyArtifacts runs the declarative artifact readiness check for every
// public.upgrade row that hasn't already been completed, rolled back, or
// skipped. Two independent levels are tracked by separate columns so the
// admin UI can tell an operator exactly what it is waiting for:
//
//   docker_images_ready            — the four Docker images (db/app/worker/proxy)
//                             exist at the runtime VERSION tag
//                             (git-describe output). Verified via
//                             `docker manifest inspect` — a registry-only
//                             query that doesn't pull.
//   release_builds_ready — for tagged releases only: the GitHub Release
//                             + `sb` binary + manifest.json exist. Set
//                             by the discovery loop above via FetchManifest.
//                             For commits this defaults to true (edge
//                             channel doesn't use release artifacts).
//
// Scoped to the 30 most recent pending rows to bound per-cycle cost.
func (d *Service) verifyArtifacts(ctx context.Context) {
	const registryPrefix = "ghcr.io/statisticsnorway/statbus-"
	services := []string{"db", "app", "worker", "proxy"}

	rows, err := d.queryConn.Query(ctx, `
		SELECT id, commit_sha, release_status::text, docker_images_ready, release_builds_ready, version
		  FROM public.upgrade
		 WHERE NOT docker_images_ready
		   AND completed_at IS NULL
		   AND rolled_back_at IS NULL
		   AND skipped_at IS NULL
		   AND superseded_at IS NULL
		 ORDER BY committed_at DESC
		 LIMIT 30`)
	if err != nil {
		return
	}

	type pendingRow struct {
		id                 int
		sha                string
		releaseStatus      string
		dockerImagesReady  bool
		releaseBuildsReady bool
		version *string // NULL for rows predating the version column
	}
	var pending []pendingRow
	for rows.Next() {
		var r pendingRow
		if err := rows.Scan(&r.id, &r.sha, &r.releaseStatus, &r.dockerImagesReady, &r.releaseBuildsReady, &r.version); err == nil {
			pending = append(pending, r)
		}
	}
	rows.Close()

	for _, r := range pending {
		dockerImagesReady := r.dockerImagesReady
		if !dockerImagesReady {
			// Use the tag captured at discovery time (stable) to avoid drift
			// from new tags being pushed past this commit. Fall back to a
			// dynamic git describe for rows predating the column (NULL).
			var tag string
			if r.version != nil && *r.version != "" {
				tag = *r.version
			} else {
				out, err := runCommandOutput(d.projDir, "git", "describe", "--tags", "--always", r.sha)
				if err != nil {
					continue
				}
				tag = strings.TrimSpace(out)
				if tag == "" {
					continue
				}
			}
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
					"UPDATE public.upgrade SET docker_images_ready = true WHERE id = $1 AND NOT docker_images_ready",
					r.id)
				fmt.Printf("Images verified for commit %s (tag=%s)\n", r.sha[:12], tag)
				dockerImagesReady = true
			}
		}

		_ = dockerImagesReady // value recorded via the UPDATE above when applicable
	}
}

// RecoverFromFlag is the exported form of recoverFromFlag — the
// reconciliation step that runs at service startup but can also be invoked
// as a one-shot by `./sb upgrade recover` when the service is stopped
// (e.g., after `./cloud.sh install` killed the unit mid-upgrade and the
// flag file persists on disk).
//
// The caller MUST call LoadConfigAndConnect first so queryConn is live,
// and Close after to release connections.
func (d *Service) RecoverFromFlag(ctx context.Context) {
	d.recoverFromFlag(ctx)
}

// LoadConfigAndConnect performs the startup steps needed before
// RecoverFromFlag (or any other one-shot that reads/writes public.upgrade)
// can run: load .env config, acquire the queryConn / listenConn.
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
const upgradeRowReturning = ` RETURNING to_jsonb(public.upgrade)`

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
	ErrInstallFixupFailed    = "INSTALL_FIXUP_FAILED"
)

// Run starts the upgrade service main loop.
func (d *Service) Run(ctx context.Context) error {
	ctx, cancel := signal.NotifyContext(ctx, syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	if err := d.loadConfig(); err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	// Load trusted commit signers for signature verification
	if err := d.loadTrustedSigners(); err != nil {
		return err
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
	d.recoverFromFlag(ctx)

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

	// Systemd watchdog: proves the service is alive and responsive.
	// If WatchdogSec is set in the unit file, systemd kills+restarts
	// the service if it stops pinging within the timeout.
	watchdog := newWatchdog()
	if watchdog != nil {
		defer watchdog.Stop()
		fmt.Printf("Systemd watchdog enabled (interval=%s)\n", watchdog.interval)
	}

	// Initial discovery on startup
	d.discover(ctx)

	for {
		select {
		case <-ctx.Done():
			fmt.Println("Upgrade service shutting down")
			d.stopListenLoop()
			return nil
		case <-ticker.C:
			fmt.Printf("Poll tick (next in %s)\n", d.interval)
			if !d.upgrading {
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
	d.listenWg.Add(1)
	fmt.Println("listenLoop started (channels: upgrade_check, upgrade_apply)")
	go func() {
		defer d.listenWg.Done()
		d.listenLoop(listenCtx, notifyCh, errCh)
	}()
}

// stopListenLoop cancels the listenLoop goroutine and waits for it to exit.
func (d *Service) stopListenLoop() {
	if d.listenCancel != nil {
		d.listenCancel()
		d.listenWg.Wait()
		d.listenCancel = nil
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
		if ValidateVersion(version) {
			d.scheduleImmediate(ctx, version)
			if recreate {
				d.pendingRecreate = true
			}
		} else {
			fmt.Printf("Invalid version in NOTIFY payload: %q\n", payload)
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
		        COALESCE(tags[array_upper(tags, 1)], 'sha-' || left(commit_sha, 12)) as display_name
		 FROM public.upgrade
		 WHERE started_at IS NOT NULL
		   AND completed_at IS NULL
		   AND error IS NULL
		   AND rolled_back_at IS NULL
		 LIMIT 1`).Scan(&id, &commitSHA, &displayName)
	if err != nil {
		return // no in-progress upgrade
	}

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
		var failedJSON string
		if scanErr := d.queryConn.QueryRow(ctx,
			"UPDATE public.upgrade SET state = 'failed', error = $1 WHERE id = $2"+upgradeRowReturning,
			fmt.Sprintf("%s: post-restart health check failed: %v", ErrHealthcheckDBDown, err), id).Scan(&failedJSON); scanErr != nil {
			fmt.Printf("WARN: state transition to failed matched 0 rows or errored (id=%d, err=%v) — possible CHECK constraint violation\n", id, scanErr)
		} else {
			logUpgradeRow(LabelFailed, failedJSON)
		}
		return
	}

	logRecover("Upgrade to %s completed (verified after service restart)", displayName)

	// Close the appender so the post-restart lines are flushed to disk
	// before we mark the row completed.
	if appendLog != nil {
		appendLog.Close()
		appendLog = nil
	}
	var fromInProgressJSON string
	if scanErr := d.queryConn.QueryRow(ctx,
		"UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_ready = true WHERE id = $1"+upgradeRowReturning,
		id).Scan(&fromInProgressJSON); scanErr != nil {
		fmt.Printf("WARN: state transition to completed matched 0 rows or errored (id=%d, err=%v) — possible CHECK constraint violation\n", id, scanErr)
	} else {
		logUpgradeRow(LabelCompletedFromInProgress, fromInProgressJSON)
	}
	d.removeUpgradeFlag()

	// Skip older releases that are still "available" — no point upgrading to an older version
	d.supersedeOlderReleases(ctx, commitSHA)
	d.runUpgradeCallback(displayName)
}

// markCurrentVersionCompleted marks the service's own version as completed in
// the upgrade table. This handles versions deployed via install.sh (which
// bypasses the upgrade service flow) and ensures the UI doesn't show
// "Upgrade Now" for the already-running version. Idempotent.
func (d *Service) markCurrentVersionCompleted(ctx context.Context) {
	if d.version == "dev" {
		return
	}

	// Match by tag name or commit SHA
	headSHA, _ := runCommandOutput(d.projDir, "git", "rev-parse", "HEAD")
	headSHA = strings.TrimSpace(headSHA)

	result, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade
		 SET state = 'completed',
		     completed_at = COALESCE(completed_at, now()),
		     docker_images_ready = true,
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
	// Get the topological_order/committed_at of the selected commit
	var selectedPos sql.NullInt32
	var selectedCommittedAt time.Time
	err := d.queryConn.QueryRow(ctx,
		"SELECT topological_order, committed_at FROM public.upgrade WHERE commit_sha = $1",
		selectedCommitSHA).Scan(&selectedPos, &selectedCommittedAt)
	if err != nil {
		return
	}

	// Supersede all available entries that are older. error=NULL matters
	// when a previously-failed row gets auto-superseded — CHECK on
	// state='superseded' only requires superseded_at IS NOT NULL.
	result, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade SET state = 'superseded', superseded_at = now(), error = NULL
		 WHERE completed_at IS NULL AND started_at IS NULL
		   AND skipped_at IS NULL AND superseded_at IS NULL
		   AND commit_sha != $1
		   AND (
		     (topological_order IS NOT NULL AND $2::int IS NOT NULL AND topological_order < $2)
		     OR committed_at < $3
		   )`,
		selectedCommitSHA, selectedPos, selectedCommittedAt)
	if err != nil {
		fmt.Printf("Failed to supersede older releases: %v\n", err)
		return
	}

	if result.RowsAffected() > 0 {
		fmt.Printf("Superseded %d older release(s)\n", result.RowsAffected())
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
// Signing enforcement is determined by key presence: if keys are configured,
// verification is enforced. If no keys, verification is skipped with a warning.
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
		fmt.Println("Warning: no trusted signers configured (UPGRADE_TRUSTED_SIGNER_*), commit signature verification disabled")
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

	// Configure git to use the allowed-signers file
	if err := runCommand(d.projDir, "git", "config", "gpg.ssh.allowedSignersFile", allowedSignersPath); err != nil {
		fmt.Printf("Warning: could not set git gpg.ssh.allowedSignersFile: %v\n", err)
	}

	fmt.Printf("Commit signature verification enabled (%d trusted signer(s))\n", len(signerLines))
	return nil
}

// verifyCommitSignature verifies an SSH signature on a git commit.
// Returns nil if the signature is valid and trusted.
// If no signers are configured (allowedSignersPath is empty), skips verification.
// If signers ARE configured, enforces — unsigned/untrusted commits are rejected.
func (d *Service) verifyCommitSignature(sha string) error {
	if d.allowedSignersPath == "" {
		// No signers configured — skip verification
		return nil
	}

	out, err := runCommandOutput(d.projDir, "git", "-c",
		fmt.Sprintf("gpg.ssh.allowedSignersFile=%s", d.allowedSignersPath),
		"verify-commit", sha)
	if err != nil {
		return fmt.Errorf("commit %s signature verification failed: %s", sha[:12], strings.TrimSpace(out))
	}

	fmt.Printf("Commit %s signature verified: %s\n", sha[:12], strings.TrimSpace(out))
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

	d.listenConn, err = pgx.Connect(ctx, connStr)
	if err != nil {
		return fmt.Errorf("listen connection: %w", err)
	}
	d.queryConn, err = pgx.Connect(ctx, connStr)
	if err != nil {
		d.listenConn.Close(context.Background())
		return fmt.Errorf("query connection: %w", err)
	}
	return nil
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
		"SELECT COUNT(*) FROM public.upgrade WHERE started_at IS NOT NULL AND completed_at IS NULL AND error IS NULL").Scan(&count)
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
		"SELECT COUNT(*) FROM public.upgrade WHERE scheduled_at IS NOT NULL AND started_at IS NULL").Scan(&count)
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
			`INSERT INTO public.upgrade (commit_sha, committed_at, tags, release_status, summary, has_migrations, version)
			 VALUES ($1, $2, ARRAY[$3]::text[], $4::public.release_status_type, $5, false, $3)
			 ON CONFLICT (commit_sha) DO UPDATE SET
			   tags = CASE WHEN $3 = ANY(upgrade.tags) THEN upgrade.tags
			               ELSE array_append(upgrade.tags, $3) END,
			   release_status = GREATEST(upgrade.release_status, EXCLUDED.release_status),
			   release_builds_ready = CASE
			       WHEN EXCLUDED.release_status > upgrade.release_status THEN false
			       ELSE upgrade.release_builds_ready
			   END
			 WHERE NOT ($3 = ANY(upgrade.tags))
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
			   tags = CASE WHEN $2 = ANY(upgrade.tags) THEN upgrade.tags
			               ELSE array_append(upgrade.tags, $2) END,
			   release_status = GREATEST(upgrade.release_status, $3::public.release_status_type)
			 WHERE commit_sha = $1
			   AND (NOT ($2 = ANY(upgrade.tags)) OR upgrade.release_status < $3::public.release_status_type)`,
			t.CommitSHA, t.TagName, targetStatus)
	}

	// Check GitHub Release manifest availability for tagged releases and
	// update release_builds_ready. The manifest lives alongside the `sb`
	// binary and changelog in the GitHub Release — if FetchManifest
	// succeeds, all three are published. Commits never have this.
	for _, t := range filtered {
		if _, err := FetchManifest(t.TagName); err == nil {
			d.queryConn.Exec(ctx,
				"UPDATE public.upgrade SET release_builds_ready = true WHERE commit_sha = $1 AND NOT release_builds_ready",
				t.CommitSHA)
		}
	}

	// Two-level declarative verification covering every pending row:
	//   1. docker_images_ready — queries ghcr.io for each of the four images at
	//      the runtime VERSION tag.
	//   2. release_builds_ready — for tagged releases: GitHub Release + sb binary
	//      + manifest.json exist. Set by discoverTaggedReleases via FetchManifest.
	//      Commits skip this level (default true).
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
		`SELECT id, tags FROM public.upgrade WHERE array_length(tags, 1) > 0`)
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
			`UPDATE public.upgrade SET tags = $1, release_status = $2::public.release_status_type WHERE id = $3`,
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
			fmt.Printf("Skipping edge commit %s: %v\n", c.SHA[:12], err)
			continue
		}

		summary := c.Summary
		if len(summary) > 120 {
			summary = summary[:120]
		}

		// release_builds_ready=true for commits because edge channel
		// never needs release.yaml output (no self-update, no manifest).
		// docker_images_ready defaults to false and is flipped by verifyArtifacts()
		// once docker manifest inspect confirms the four images for this commit's
		// git-describe tag have landed in the registry.

		// Capture git describe output now so verifyArtifacts can look up
		// Docker images by a stable tag — the describe output changes as
		// new tags are pushed past this commit after discovery.
		versionTag, _ := runCommandOutput(d.projDir, "git", "describe", "--tags", "--always", c.SHA)
		versionTag = strings.TrimSpace(versionTag)

		_, err := d.queryConn.Exec(ctx,
			`INSERT INTO public.upgrade (commit_sha, committed_at, summary, has_migrations, release_builds_ready, version)
			 VALUES ($1, $2, $3, false, true, NULLIF($4, ''))
			 ON CONFLICT (commit_sha) DO NOTHING`,
			c.SHA, c.PublishedAt, summary, versionTag)
		if err != nil {
			fmt.Printf("  Failed to record commit %s: %v\n", c.SHA[:12], err)
		}
	}

	if d.autoDL {
		d.preDownloadImages(ctx)
	}
}

func (d *Service) preDownloadImages(ctx context.Context) {
	rows, err := d.queryConn.Query(ctx,
		`SELECT commit_sha,
		        COALESCE(tags[array_upper(tags, 1)], 'sha-' || left(commit_sha, 12)) as display_name
		 FROM public.upgrade
		 WHERE docker_images_downloaded = false AND skipped_at IS NULL AND error IS NULL
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

func (d *Service) scheduleImmediate(ctx context.Context, versionOrSHA string) {
	// Resolve to commit_sha
	commitSHA := versionOrSHA
	displayName := versionOrSHA
	if strings.HasPrefix(versionOrSHA, "sha-") {
		// It's a SHA reference — strip the prefix to get the raw SHA
		commitSHA = strings.TrimPrefix(versionOrSHA, "sha-")
	} else {
		// It's a tag — look up the commit SHA from the database
		err := d.queryConn.QueryRow(ctx,
			"SELECT commit_sha FROM public.upgrade WHERE $1 = ANY(tags) LIMIT 1",
			versionOrSHA).Scan(&commitSHA)
		if err != nil {
			// Not found in DB — try to resolve via git
			sha, gitErr := runCommandOutput(d.projDir, "git", "rev-parse", versionOrSHA)
			if gitErr != nil {
				fmt.Printf("Cannot resolve %s to commit SHA: %v\n", versionOrSHA, gitErr)
				return
			}
			commitSHA = strings.TrimSpace(sha)
		}
	}

	// Reset lifecycle fields so a completed/failed upgrade can be re-applied.
	// The WHERE clause prevents updating a row that's already scheduled and waiting
	// to execute (scheduled_at IS NOT NULL AND started_at IS NULL). Without this guard,
	// the UPDATE changes scheduled_at to now() → the upgrade_notify_daemon_trigger fires
	// → sends NOTIFY upgrade_apply → service calls scheduleImmediate again → infinite loop.
	result, err := d.queryConn.Exec(ctx,
		`INSERT INTO public.upgrade (commit_sha, committed_at, tags, summary, scheduled_at, state)
		 VALUES ($1, now(), CASE WHEN $2 != '' AND NOT starts_with($2, 'sha-') THEN ARRAY[$2]::text[] ELSE '{}'::text[] END, $2, now(), 'scheduled')
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
		 WHERE public.upgrade.scheduled_at IS NULL
		    OR public.upgrade.started_at IS NOT NULL
		    OR public.upgrade.completed_at IS NOT NULL
		    OR public.upgrade.error IS NOT NULL
		    OR public.upgrade.superseded_at IS NOT NULL`,
		commitSHA, displayName)
	if err != nil {
		fmt.Printf("Failed to schedule %s: %v\n", displayName, err)
	} else if result.RowsAffected() > 0 {
		fmt.Printf("Scheduled immediate upgrade to %s\n", displayName)
		// Once a commit is selected, all older ones are obsolete.
		d.supersedeOlderReleases(ctx, commitSHA)
	} else {
		fmt.Printf("Version %s already scheduled, no action needed\n", displayName)
	}
}

func (d *Service) executeScheduled(ctx context.Context) {
	if err := d.ensureConnected(ctx); err != nil {
		return
	}
	var id int
	var commitSHA, displayName string
	var scheduledAt time.Time
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, commit_sha,
		        COALESCE(tags[array_upper(tags, 1)], 'sha-' || left(commit_sha, 12)) as display_name,
		        scheduled_at
		 FROM public.upgrade
		 WHERE scheduled_at <= now()
		   AND started_at IS NULL
		   AND completed_at IS NULL
		   AND error IS NULL
		   AND rolled_back_at IS NULL
		   AND skipped_at IS NULL
		 ORDER BY scheduled_at LIMIT 1`).Scan(&id, &commitSHA, &displayName, &scheduledAt)
	if err != nil {
		return // no pending upgrades
	}
	fmt.Printf("Claiming id=%d, lag=%s\n", id, time.Since(scheduledAt).Truncate(time.Second))

	// Claim immediately: mark started_at + state='in_progress' so the UI
	// shows "In Progress" and the user can no longer unschedule.
	// Declared before any work begins.
	d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET state = 'in_progress', started_at = now(), from_version = $1 WHERE id = $2",
		d.version, id)

	fmt.Printf("Executing upgrade to %s...\n", displayName)
	// Invoker context for the flag file: the row was picked up from the scheduled queue.
	// This covers admin-UI "Apply now", NOTIFY upgrade_apply from ./sb upgrade apply-latest,
	// and the discovery loop's auto-schedule — we don't currently distinguish among them
	// at this layer. Later improvement: record originator in public.upgrade when scheduling.
	if err := d.executeUpgrade(ctx, id, commitSHA, displayName, "scheduled", "scheduled"); err != nil {
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
func (d *Service) executeUpgrade(ctx context.Context, id int, commitSHA, displayName, invokedBy, trigger string) error {
	d.upgrading = true
	defer func() { d.upgrading = false }()

	projDir := d.projDir
	progress := NewProgressLog(projDir, int64(id), displayName, time.Now().UTC())
	defer progress.Close()

	// Stamp log_relative_file_path on the row as early as possible so crash
	// recovery, the admin UI, and the support-bundle collector can all find
	// the on-disk log. Best-effort; failure doesn't abort the upgrade.
	if _, err := d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET log_relative_file_path = $1 WHERE id = $2",
		progress.RelPath(), id); err != nil {
		fmt.Printf("Warning: could not set log_relative_file_path for upgrade %d: %v\n", id, err)
	}

	progress.Write("Upgrading to %s (from %s)...", displayName, d.version)
	// For sha-prefixed targets (edge channel), displayName tells you the SHA
	// but nothing about how far it is from the nearest tag. `git describe`
	// fills that gap ("v2026.03.1-9-gea46d5818" → nearest tag + N commits
	// ahead + shortened SHA). Also emit the commit subject so an operator
	// watching the maintenance page sees what the upgrade actually brings
	// without tailing git log. Suppress describe when it equals displayName
	// (tagged-channel case) to avoid redundancy.
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
	// Only applies when displayName is a CalVer tag (not a SHA reference).
	if !strings.HasPrefix(displayName, "sha-") && !strings.HasPrefix(d.version, "sha-") && d.version != "dev" {
		if CompareVersions(displayName, d.version) < 0 {
			// TODO: pick code — downgrade precondition; consider adding ErrInstallPreconditionFailed
			msg := fmt.Sprintf("Version %s is older than current version %s. Downgrades are not supported. To restore a previous state, use: ./sb db backup restore <name>", displayName, d.version)
			d.failUpgrade(ctx, id, msg, progress)
			return fmt.Errorf("%s", msg)
		}
	}

	// Verify release manifest and binary exist before starting.
	// If CI hasn't finished building, unschedule and return — not an error.
	// Only check for tagged releases, not raw SHA commits.
	if !strings.HasPrefix(displayName, "sha-") {
		progress.Write("Verifying release assets available...")
		manifest, err := FetchManifest(displayName)
		if err != nil {
			// CI not ready — unschedule without setting error. Reset to
			// 'available' + clear started_at so the CHECK constraint holds
			// (state='available' requires all lifecycle timestamps NULL).
			// The service will flip docker_images_ready and release_builds_ready
			// on the next discovery cycle when CI finishes, re-enabling "Upgrade Now".
			d.queryConn.Exec(ctx,
				"UPDATE public.upgrade SET state = 'available', scheduled_at = NULL, started_at = NULL, from_version = NULL WHERE id = $1", id)
			progress.Write("Release assets not ready for %s — unscheduled. Will be available when CI finishes.", displayName)
			return nil
		}
		platform := selfupdate.Platform()
		if _, ok := manifest.Binaries[platform]; !ok {
			progress.Write("Warning: no binary for platform %s in release %s — self-update will be skipped", platform, displayName)
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
		msg := fmt.Sprintf("Commit %s signature verification failed: %v", commitSHA[:12], err)
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
	if err := d.writeUpgradeFlag(id, commitSHA, displayName, invokedBy, trigger); err != nil {
		// TODO: pick code — mutex flag acquisition failure; consider adding ErrInstallPreconditionFailed
		msg := fmt.Sprintf("Could not acquire upgrade-mutex flag file: %v", err)
		d.failUpgrade(ctx, id, msg, progress)
		return fmt.Errorf("%s", msg)
	}

	// started_at and from_version were already set by executeScheduled() when
	// it claimed this task. From this point on, the maintenance guard will activate.

	// Step 1: Prepare images
	progress.Write("Preparing images...")
	if err := d.pullImages(displayName); err != nil {
		d.failUpgrade(ctx, id, fmt.Sprintf("%s: Failed to pull images for %s: %v", ErrDockerUpFailed, displayName, err), progress)
		return err
	}

	// Pre-compute backup stamp and record the .tmp path in the DB before the
	// DB connection is closed.  The stamp ties the on-disk directory name to
	// the DB row so reconcileBackupDir can detect crashed or missing backups.
	backupStamp := time.Now().UTC().Format("20060102T150405Z")
	backupTmpPath := filepath.Join(d.backupRoot(), "pre-upgrade-"+backupStamp+".tmp")
	d.queryConn.Exec(ctx, "UPDATE public.upgrade SET backup_path = $1 WHERE id = $2", backupTmpPath, id)

	// Step 2: Enter maintenance mode and restart proxy first
	d.stopListenLoop()
	d.listenConn.Close(context.Background())
	d.listenConn = nil
	d.queryConn.Close(context.Background())
	d.queryConn = nil
	progress.Write("Entering maintenance mode...")
	d.setMaintenance(true)

	// Step 3: Stop application services (proxy stays running for maintenance page)
	progress.Write("Stopping application services...")
	if err := runCommand(projDir, "docker", "compose", "stop", "app", "worker", "rest"); err != nil {
		progress.Write("Warning: could not stop some services: %v", err)
	}

	// Step 4: Stop database for consistent backup
	progress.Write("Stopping database...")
	if err := runCommand(projDir, "docker", "compose", "stop", "db"); err != nil {
		progress.Write("Warning: could not stop database: %v", err)
	}

	// Pin the pre-upgrade commit as a persistent branch BEFORE we touch
	// anything destructive. The branch survives process crashes and tag
	// pruning — restoreGitState falls back to it if `previousVersion`
	// (a tag or describe-string) won't resolve later. Best-effort: log
	// failure, don't abort the upgrade.
	if out, err := runCommandOutput(projDir, "git", "branch", "-f", "statbus/pre-upgrade", "HEAD"); err != nil {
		progress.Write("Warning: could not pin statbus/pre-upgrade branch: %v\n%s", err, out)
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
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("git fetch %s: %v", commitSHA[:12], err), progress)
		return err
	}
	if err := runCommandToLog(projDir, 5*time.Minute, progress.File(), "git", "git", "-c", "advice.detachedHead=false", "checkout", commitSHA); err != nil {
		// TODO: pick code — forward git checkout failure; no Err* code covers install-time git errors yet
		d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("git checkout %s: %v", commitSHA[:12], err), progress)
		return err
	}

	// Verify checked-out SHA matches manifest (detect tag spoofing) — only for tagged releases
	if !strings.HasPrefix(displayName, "sha-") {
		if manifest, mErr := FetchManifest(displayName); mErr == nil && manifest.CommitSHA != "" {
			if checkedOut, gErr := runCommandOutput(projDir, "git", "rev-parse", "HEAD"); gErr == nil {
				checkedOut = strings.TrimSpace(checkedOut)
				if !strings.HasPrefix(checkedOut, manifest.CommitSHA) && !strings.HasPrefix(manifest.CommitSHA, checkedOut) {
					// TODO: pick code — tag-tampering detection; consider adding ErrInstallPreconditionFailed
					errMsg := fmt.Sprintf("Version verification failed: expected commit %s but got %s. Possible tag tampering.", manifest.CommitSHA[:12], checkedOut[:12])
					progress.Write("%s", errMsg)
					d.rollback(ctx, id, displayName, previousVersion, errMsg, progress)
					return fmt.Errorf("%s", errMsg)
				}
			}
		}
	}

	// Step 6b: Swap ./sb for the release binary BEFORE any subprocess runs.
	// Without this, `./sb config generate` and `./sb migrate up` below would
	// execute the OLD compiled Go against NEW templates/migrations — the
	// rc.6→rc.7 SITE_DOMAIN/PGHOST class of bug (#9). Tagged releases only
	// (sha-* edge commits have no release binary in the manifest).
	if !strings.HasPrefix(displayName, "sha-") {
		if err := d.replaceBinaryOnDisk(displayName, progress); err != nil {
			d.rollback(ctx, id, displayName, previousVersion, fmt.Sprintf("%s: %v", ErrBinaryReplaceFailed, err), progress)
			return err
		}
	}

	// Regenerate config — VERSION is derived from git describe --tags --always,
	// which returns the tag name (e.g., v2026.03.0-rc.3) since we just checked it out.
	progress.Write("Regenerating configuration...")
	if err := runCommand(projDir, filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
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

	// Step 10: Run migrations (or recreate database if requested)
	if d.pendingRecreate {
		d.pendingRecreate = false
		progress.Write("Recreating database from scratch (--recreate)...")
		if err := runCommandWithTimeout(projDir, 30*time.Minute, filepath.Join(projDir, "dev.sh"), "recreate-database"); err != nil {
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
	if err := d.healthCheck(5, 5*time.Second); err != nil {
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

	// Run idempotent install to apply any new infrastructure (systemd service,
	// directories, config fixes). Install steps skip what's already done.
	// This exercises the install path on every upgrade, catching install bugs early.
	//
	// The flag file we wrote at writeUpgradeFlag is still on disk at this point
	// (it's removed later on success, line ~1454). Install's upgrade-mutex check
	// would normally abort because it sees our flag — so we pass the bypass signal
	// both via the --inside-active-upgrade flag (visible in ps/logs for audit) and
	// via STATBUS_INSIDE_ACTIVE_UPGRADE=1 env var (propagates through exec chains).
	// Either is sufficient; we set both for defense in depth.
	progress.Write("Running install fixups...")
	if err := runInstallFixup(projDir); err != nil {
		progress.Write("%s: post-upgrade install fixups failed: %v", ErrInstallFixupFailed, err)
		// Non-fatal — the upgrade itself succeeded
	}

	// Self-update binary (may restart service via exit code 42).
	// If self-update restarts, the NEW service marks completed_at on startup
	// (completeInProgressUpgrade) — so "completed" means the new version is verified.
	// Only for tagged releases — SHA commits don't have release binaries.
	if !strings.HasPrefix(displayName, "sha-") {
		d.selfUpdate(ctx, displayName, progress)
	}

	// If we get here, self-update didn't restart (no binary for platform, or same version).
	// Mark complete now since there won't be a new service to do it. The full
	// narrative lives in the on-disk log (served via /upgrade-logs/<name>); the
	// admin UI fetches it by name when the operator expands the "Log" panel.
	progress.Write("Upgrade to %s complete!", displayName)
	var normalJSON string
	if scanErr := d.queryConn.QueryRow(ctx,
		"UPDATE public.upgrade SET state = 'completed', completed_at = now(), docker_images_ready = true WHERE id = $1"+upgradeRowReturning,
		id).Scan(&normalJSON); scanErr != nil {
		fmt.Printf("WARN: state transition to completed matched 0 rows or errored (id=%d, err=%v) — possible CHECK constraint violation\n", id, scanErr)
	} else {
		fmt.Println("state=completed")
		logUpgradeRow(LabelCompletedNormal, normalJSON)
	}
	d.removeUpgradeFlag()
	// Pre-upgrade branch is no longer needed — successful completion
	// means we're committed to the new version. Best-effort delete; if
	// the branch is missing (best-effort create at the start failed),
	// the -D returns non-zero and we just move on.
	runCommand(d.projDir, "git", "branch", "-D", "statbus/pre-upgrade")
	d.supersedeOlderReleases(ctx, commitSHA)
	d.runUpgradeCallback(displayName)

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
			progress.Write("    4. Reconcile DB row via: ./sb upgrade recover")
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
				"STATBUS_RECOVERY_CMD":    fmt.Sprintf(`ssh %s "cd statbus && ./sb upgrade recover"`, hostname),
			})
			// Maintenance stays ON — operator must finish the rollback.
			// Mutex stays HELD — `./sb install` would compound the mess.
			// `./sb upgrade recover` is documented above as the unstick path.
			return
		}
		if err := runCommand(projDir, filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
			progress.Write("Warning: config generate during rollback failed: %v", err)
		}
	}

	// Restore database backup. Now safe — git state matches the DB era.
	d.restoreDatabase(progress)

	// Restore ./sb to match the restored git era BEFORE `docker compose up`.
	// `docker compose` uses whatever `sb` happens to be on disk for any later
	// operator invocation; keeping the new binary around after a DB rollback
	// is the worst-of-both state. Best-effort; ErrRollbackBinaryCorrupt is
	// logged (non-fatal) if the rename fails.
	d.restoreBinary(progress)

	// Start with old config — git is verified at previousVersion.
	if err := runCommand(projDir, "docker", "compose", "--profile", "all", "up", "-d", "--remove-orphans"); err != nil {
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
}

// restoreGitState is the *Service-bound wrapper around restoreGitStateFn,
// adapting progress.Write to the free function's plain logger.
func (d *Service) restoreGitState(previousVersion string, progress *ProgressLog) error {
	return restoreGitStateFn(d.projDir, previousVersion, func(format string, args ...interface{}) {
		progress.Write(format, args...)
	})
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
// `statbus/pre-upgrade` branch pinned by executeUpgrade before the
// destructive steps started — defense in depth against ref drift.
//
// Logger is invoked at narrative milestones; pass a no-op for tests.
// Free function (not a method) so the unit tests don't have to
// construct a *Service or its DB connections.
func restoreGitStateFn(projDir, previousVersion string, log func(format string, args ...interface{})) error {
	log("Restoring git state to %s...", previousVersion)

	// Pre-validate: refuse to checkout a ref we can't resolve. If the
	// requested ref is gone, fall back to the persistent
	// statbus/pre-upgrade branch before erroring out.
	expectedOut, err := runCommandOutput(projDir, "git", "rev-parse", "--verify", previousVersion+"^{commit}")
	if err != nil {
		log("Ref %s does not resolve, falling back to statbus/pre-upgrade...", previousVersion)
		fallbackOut, fallbackErr := runCommandOutput(projDir, "git", "rev-parse", "--verify", "statbus/pre-upgrade^{commit}")
		if fallbackErr != nil {
			return fmt.Errorf("neither %s nor statbus/pre-upgrade resolves: %v / %v", previousVersion, err, fallbackErr)
		}
		expectedOut = fallbackOut
		previousVersion = "statbus/pre-upgrade"
	}
	expectedSHA := strings.TrimSpace(expectedOut)
	if expectedSHA == "" {
		return fmt.Errorf("ref %s resolved to empty SHA", previousVersion)
	}

	// Force checkout — discards any local changes. We're rolling back from
	// a partial upgrade, so any working-tree mutations are by definition
	// part of the failure we're undoing.
	if err := runCommand(projDir, "git", "-c", "advice.detachedHead=false", "checkout", "-f", previousVersion); err != nil {
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
		return fmt.Errorf("git checkout landed on %s, expected %s", shortSHA(headSHA), shortSHA(expectedSHA))
	}

	log("Git state restored to %s (HEAD %s)", previousVersion, shortSHA(headSHA))
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
// Called mid-flow in executeUpgrade (between git checkout and ./sb config
// generate), so subsequent `./sb …` subprocesses (config generate, migrate
// up, install fixup) run the NEW compiled Go code — not just the new
// templates/SQL pulled in by the git checkout. This closes the rc.6→rc.7
// class of bug where template-level fixes landed but the binary still ran
// old Go against them.
//
// Does NOT self-replace the running upgrade-service process; that still
// happens end-of-flow via selfUpdate() + exit-42. By then the file on
// disk already matches the target, so selfUpdate()'s same-hash shortcut
// in selfupdate.Update() makes it a no-op download and a pure exit-42 handoff.
//
// Skips silently (non-fatal) when:
//   - no binary in manifest for the current platform (e.g. dev-only build)
//   - version is an edge sha-* commit with no release binary
func (d *Service) replaceBinaryOnDisk(version string, progress *ProgressLog) error {
	manifest, err := FetchManifest(version)
	if err != nil {
		return fmt.Errorf("fetch manifest for %s: %w", version, err)
	}
	platform := selfupdate.Platform()
	binary, ok := manifest.Binaries[platform]
	if !ok {
		progress.Write("Binary replace skipped: no binary for platform %s in release %s", platform, version)
		return nil
	}
	sbPath := filepath.Join(d.projDir, "sb")
	progress.Write("Replacing ./sb with %s binary (subsequent subprocesses will run the new code)...", version)
	if err := selfupdate.ReplaceBinaryOnDisk(sbPath, binary.URL, binary.SHA256); err != nil {
		return err
	}
	progress.Write("./sb replaced; ./sb.old kept as rollback.")
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
	// Exit with code 42 to signal systemd to restart
	os.Exit(42)
}

