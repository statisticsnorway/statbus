package upgrade

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
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
// is the kernel-enforced mutex that prevents two mutators from racing:
// O_CREATE|O_EXCL acquire makes "two writers see no flag" impossible.
//
// If the holder crashes, the flag file survives (it's on the filesystem,
// NOT in the DB volume which gets rolled back). On next service startup
// (or via `./sb upgrade recover`), the file is reconciled — Holder
// determines what cleanup is needed.
//
// PID + pidAlive() distinguishes a live mutator from a crashed one;
// InvokedBy records who triggered it so post-mortems can trace
// responsibility.
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

// writeFlagAtomic writes the flag JSON via O_CREATE|O_EXCL — the kernel
// guarantees that exactly one caller wins when two race. Returns
// fs.ErrExist (matchable with errors.Is(err, os.ErrExist)) when another
// holder already owns the file.
func writeFlagAtomic(projDir string, flag UpgradeFlag) error {
	data, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal flag: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
		return fmt.Errorf("mkdir tmp: %w", err)
	}
	f, err := os.OpenFile(flagFilePath(projDir), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	if _, werr := f.Write(data); werr != nil {
		f.Close()
		os.Remove(flagFilePath(projDir))
		return fmt.Errorf("write flag: %w", werr)
	}
	return f.Close()
}

// writeUpgradeFlag is the service's atomic acquire. Returns an error if
// another actor already holds the flag — by service-startup invariants
// (recoverFromFlag runs first; advisory lock prevents two services), this
// can only happen if an `./sb install` slipped in between recovery and
// now. Caller (executeUpgrade) treats that as a failure.
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
	return writeFlagAtomic(d.projDir, flag)
}

func (d *Service) removeUpgradeFlag() {
	os.Remove(d.flagPath())
}

// AcquireInstallFlag atomically claims the upgrade-mutex marker for an
// `./sb install` invocation. Returns nil on success — the caller MUST
// arrange release via ReleaseInstallFlag (typically defer).
//
// On contention (any holder — running upgrade, running install, or a
// stale flag from a crashed prior holder), returns an error formatted to
// guide the operator to the right recovery action. The error message
// distinguishes service-vs-install holders and live-vs-dead PIDs.
func AcquireInstallFlag(projDir, displayName, invokedBy string) error {
	flag := UpgradeFlag{
		DisplayName: displayName,
		PID:         os.Getpid(),
		StartedAt:   time.Now(),
		InvokedBy:   invokedBy,
		Trigger:     "install",
		Holder:      HolderInstall,
	}
	err := writeFlagAtomic(projDir, flag)
	if err == nil {
		return nil
	}
	if !errors.Is(err, os.ErrExist) {
		return fmt.Errorf("write upgrade flag: %w", err)
	}
	existing, alive, readErr := ReadFlagFile(projDir)
	if readErr != nil {
		return fmt.Errorf("upgrade flag file present but unreadable: %w\n\n  Investigate %s manually, then retry.",
			readErr, flagFilePath(projDir))
	}
	if existing == nil {
		// Race: file existed during write, gone by the time we read. Retry.
		return AcquireInstallFlag(projDir, displayName, invokedBy)
	}
	return formatContentionError(existing, alive)
}

// ReleaseInstallFlag removes the flag file iff our PID owns it as
// HolderInstall. Safe to call when no flag exists, when another holder
// owns the file, or when the file has already been removed.
func ReleaseInstallFlag(projDir string) {
	flag, _, err := ReadFlagFile(projDir)
	if err != nil || flag == nil {
		return
	}
	if flag.PID != os.Getpid() || flag.Holder != HolderInstall {
		return
	}
	os.Remove(flagFilePath(projDir))
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

// recoverFromFlag checks for a flag file from a previous interrupted upgrade.
// Distinguishes between a real crash (mark failed) and a self-update restart
// (mark completed) by checking if git HEAD matches the upgrade target.
func (d *Service) recoverFromFlag(ctx context.Context) {
	data, err := os.ReadFile(d.flagPath())
	if err != nil {
		return // no flag file — normal startup
	}

	var flag UpgradeFlag
	if err := json.Unmarshal(data, &flag); err != nil {
		fmt.Printf("Warning: corrupt upgrade flag file, removing: %v\n", err)
		d.removeUpgradeFlag()
		return
	}

	holder := flag.Holder
	if holder == "" {
		holder = HolderService // legacy flags pre-Release 1.1
	}

	fmt.Printf("Found interrupted %s flag for %s (id=%d, pid=%d, invoked_by=%s)\n",
		holder, flag.DisplayName, flag.ID, flag.PID, flag.InvokedBy)

	// Sanity check: if the PID that wrote the flag is still alive AND it isn't us
	// (os.Getpid() of a freshly-started process can never match a flag written by
	// a prior process), someone else claims ownership. This is pathological for
	// service holders (advisory lock should prevent two services from coexisting)
	// and surprising for install holders (operator is running install while
	// service starts). Either way, do NOT clean up another live process's state.
	if flag.PID > 0 && flag.PID != os.Getpid() && pidAlive(flag.PID) {
		fmt.Fprintf(os.Stderr,
			"REFUSING to recover: %s flag owned by live PID %d. Leaving flag in place. Investigate manually.\n",
			holder, flag.PID)
		return
	}

	// Install-held flags have no public.upgrade row to reconcile — install
	// crashes leave only the on-disk marker. Just remove it.
	if holder == HolderInstall {
		fmt.Printf("Removing stale install flag (PID %d crashed or exited without releasing)\n", flag.PID)
		d.removeUpgradeFlag()
		return
	}

	// Service-held flag: reconcile against public.upgrade.
	// Check if the upgrade actually succeeded (self-update restart via exit code 42).
	// If git HEAD matches the upgrade target, the code is at the right version.
	headSHA, _ := runCommandOutput(d.projDir, "git", "rev-parse", "HEAD")
	headSHA = strings.TrimSpace(headSHA)
	if headSHA == flag.CommitSHA {
		fmt.Printf("Upgrade %s succeeded (self-update restart detected)\n", flag.DisplayName)
		d.queryConn.Exec(ctx,
			"UPDATE public.upgrade SET completed_at = now() WHERE id = $1 AND completed_at IS NULL",
			flag.ID)
		// Explicit NOTIFY — the DB trigger also fires, but the app's LISTEN is
		// definitely established by now (new service starts after app is healthy).
		d.queryConn.Exec(ctx, `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)
		d.removeUpgradeFlag()
		d.supersedeOlderReleases(ctx, flag.CommitSHA)
		return
	}

	// Real failure — read the per-version progress log for the error message.
	// Use ProgressLogPath (matches NewProgressLog naming) instead of the
	// upgrade-progress.log symlink, which always points to the most recent
	// run and could attribute a stale tail to the wrong (older) crash.
	errMsg := "Upgrade interrupted (service crashed or was killed)"
	progressPath := ProgressLogPath(d.projDir, flag.DisplayName)
	if logData, err := os.ReadFile(progressPath); err == nil {
		lines := strings.Split(strings.TrimSpace(string(logData)), "\n")
		if len(lines) > 5 {
			lines = lines[len(lines)-5:]
		}
		errMsg = strings.Join(lines, "\n")
	}

	// Mark the upgrade as failed in the DB.
	_, err = d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET error = $1, rollback_completed_at = now() WHERE id = $2 AND completed_at IS NULL",
		errMsg, flag.ID)
	if err != nil {
		fmt.Printf("Warning: could not mark upgrade %d as failed: %v\n", flag.ID, err)
	} else {
		fmt.Printf("Marked upgrade %d (%s) as failed\n", flag.ID, flag.DisplayName)
	}

	d.removeUpgradeFlag()
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
			if !d.upgrading {
				d.discover(ctx)
				d.executeScheduled(ctx)
				// Catch up on work missed during any upgrade that just completed
				// (LISTEN connection was closed, NOTIFYs were lost)
				d.discover(ctx)
				d.executeScheduled(ctx)
				d.reportDiskSpace(ctx)
			}
		case n := <-notifyCh:
			if !d.upgrading {
				d.handleNotification(ctx, n)
				d.executeScheduled(ctx)
				// Catch up on work missed during any upgrade that just completed
				// (LISTEN connection was closed, NOTIFYs were lost)
				d.discover(ctx)
				d.executeScheduled(ctx)
			}
		case err := <-errCh:
			d.listenWg.Wait() // ensure old goroutine fully exited
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
func (d *Service) startListenLoop(ctx context.Context, notifyCh chan<- *pgconn.Notification, errCh chan<- error) {
	listenCtx, cancel := context.WithCancel(ctx)
	d.listenCancel = cancel
	d.listenWg.Add(1)
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
		   AND rollback_completed_at IS NULL
		 LIMIT 1`).Scan(&id, &commitSHA, &displayName)
	if err != nil {
		return // no in-progress upgrade
	}

	fmt.Printf("Found in-progress upgrade to %s, verifying...\n", displayName)

	// Verify services are healthy
	if err := d.waitForDBHealth(30 * time.Second); err != nil {
		fmt.Printf("Warning: in-progress upgrade %s health check failed: %v\n", displayName, err)
		d.queryConn.Exec(ctx,
			"UPDATE public.upgrade SET error = $1 WHERE id = $2",
			fmt.Sprintf("post-restart health check failed: %v", err), id)
		return
	}

	// Mark complete and remove flag file
	d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET completed_at = now() WHERE id = $1", id)
	d.removeUpgradeFlag()

	// Skip older releases that are still "available" — no point upgrading to an older version
	d.supersedeOlderReleases(ctx, commitSHA)
	d.runUpgradeCallback(displayName)

	fmt.Printf("Upgrade to %s completed (verified after service restart)\n", displayName)
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
		 SET completed_at = COALESCE(completed_at, now()),
		     scheduled_at = NULL,
		     error = NULL,
		     rollback_completed_at = NULL
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
// Ordering is by position (topological order) then committed_at as fallback.
func (d *Service) supersedeOlderReleases(ctx context.Context, selectedCommitSHA string) {
	// Get the position/committed_at of the selected commit
	var selectedPos sql.NullInt32
	var selectedCommittedAt time.Time
	err := d.queryConn.QueryRow(ctx,
		"SELECT position, committed_at FROM public.upgrade WHERE commit_sha = $1",
		selectedCommitSHA).Scan(&selectedPos, &selectedCommittedAt)
	if err != nil {
		return
	}

	// Supersede all available entries that are older
	result, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade SET superseded_at = now(), error = NULL
		 WHERE completed_at IS NULL AND started_at IS NULL
		   AND skipped_at IS NULL AND superseded_at IS NULL
		   AND commit_sha != $1
		   AND (
		     (position IS NOT NULL AND $2::int IS NOT NULL AND position < $2)
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
	maintenanceFile := filepath.Join(os.Getenv("HOME"), "statbus-maintenance", "active")
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
		result, err := d.queryConn.Exec(ctx,
			`INSERT INTO public.upgrade (commit_sha, committed_at, tags, release_status, summary, has_migrations)
			 VALUES ($1, $2, ARRAY[$3]::text[], $4::public.release_status_type, $5, false)
			 ON CONFLICT (commit_sha) DO UPDATE SET
			   tags = CASE WHEN $3 = ANY(upgrade.tags) THEN upgrade.tags
			               ELSE array_append(upgrade.tags, $3) END,
			   release_status = GREATEST(upgrade.release_status, EXCLUDED.release_status)
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

	// Check manifest availability for tagged releases and update artifacts_ready.
	// On each discovery cycle, tags with artifacts_ready=false get re-checked.
	for _, t := range filtered {
		if _, err := FetchManifest(t.TagName); err == nil {
			d.queryConn.Exec(ctx,
				"UPDATE public.upgrade SET artifacts_ready = true WHERE commit_sha = $1 AND NOT artifacts_ready",
				t.CommitSHA)
		}
	}

	// Prune tags deleted upstream: remove from the tags array in the DB
	// any tags that no longer exist in git. If all tags are removed,
	// demote release_status back to 'commit'.
	d.pruneDeletedTags(ctx, filtered)

	if d.autoDL {
		d.preDownloadImages(ctx)
	}
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

		_, err := d.queryConn.Exec(ctx,
			`INSERT INTO public.upgrade (commit_sha, committed_at, summary, has_migrations, artifacts_ready)
			 VALUES ($1, $2, $3, false, true)
			 ON CONFLICT (commit_sha) DO NOTHING`,
			c.SHA, c.PublishedAt, summary)
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
		 WHERE images_downloaded = false AND skipped_at IS NULL AND error IS NULL
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
			"UPDATE public.upgrade SET images_downloaded = true WHERE commit_sha = $1",
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
		`INSERT INTO public.upgrade (commit_sha, committed_at, tags, summary, scheduled_at)
		 VALUES ($1, now(), CASE WHEN $2 != '' AND NOT starts_with($2, 'sha-') THEN ARRAY[$2]::text[] ELSE '{}'::text[] END, $2, now())
		 ON CONFLICT (commit_sha) DO UPDATE SET
		   scheduled_at = now(),
		   started_at = NULL,
		   completed_at = NULL,
		   error = NULL,
		   rollback_completed_at = NULL,
		   skipped_at = NULL
		 WHERE public.upgrade.scheduled_at IS NULL
		    OR public.upgrade.started_at IS NOT NULL
		    OR public.upgrade.completed_at IS NOT NULL
		    OR public.upgrade.error IS NOT NULL`,
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
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, commit_sha,
		        COALESCE(tags[array_upper(tags, 1)], 'sha-' || left(commit_sha, 12)) as display_name
		 FROM public.upgrade
		 WHERE scheduled_at <= now()
		   AND started_at IS NULL
		   AND completed_at IS NULL
		   AND error IS NULL
		   AND rollback_completed_at IS NULL
		   AND skipped_at IS NULL
		 ORDER BY scheduled_at LIMIT 1`).Scan(&id, &commitSHA, &displayName)
	if err != nil {
		return // no pending upgrades
	}

	// Claim immediately: mark started_at so the UI shows "In Progress"
	// and the user can no longer unschedule. Declared before any work begins.
	d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET started_at = now(), from_version = $1 WHERE id = $2",
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
	progress := NewProgressLog(projDir, displayName)
	defer progress.Close()

	progress.Write("Upgrading to %s (from %s)...", displayName, d.version)

	// === Pre-flight checks (BEFORE marking started_at) ===
	// These checks reject the upgrade without setting started_at, so the
	// maintenance guard never activates and the upgrade page stays clean.

	// Downgrade protection: refuse to apply an older version than currently running.
	// Downgrades require restoring from backup instead.
	// Only applies when displayName is a CalVer tag (not a SHA reference).
	if !strings.HasPrefix(displayName, "sha-") && !strings.HasPrefix(d.version, "sha-") && d.version != "dev" {
		if CompareVersions(displayName, d.version) < 0 {
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
			// CI not ready — unschedule without setting error. The service will
			// set artifacts_ready=true on the next discovery cycle when CI finishes,
			// and the UI will re-enable "Upgrade Now".
			d.queryConn.Exec(ctx,
				"UPDATE public.upgrade SET scheduled_at = NULL WHERE id = $1", id)
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
		msg := fmt.Sprintf("Commit %s signature verification failed: %v", commitSHA[:12], err)
		d.failUpgrade(ctx, id, msg, progress)
		return fmt.Errorf("%s", msg)
	}

	// === All pre-flight checks passed — mark the upgrade as started ===
	// Atomically acquire the flag file BEFORE any destructive steps. The
	// O_EXCL acquire prevents racing an `./sb install` that slipped between
	// recoverFromFlag (service startup) and now. If the service crashes
	// after this point, the file survives (it's on the filesystem, not in
	// the DB volume which gets rolled back), and recoverFromFlag at the
	// next service startup reconciles it.
	if err := d.writeUpgradeFlag(id, commitSHA, displayName, invokedBy, trigger); err != nil {
		msg := fmt.Sprintf("Could not acquire upgrade-mutex flag file: %v", err)
		d.failUpgrade(ctx, id, msg, progress)
		return fmt.Errorf("%s", msg)
	}

	// started_at and from_version were already set by executeScheduled() when
	// it claimed this task. From this point on, the maintenance guard will activate.

	// Step 1: Prepare images
	progress.Write("Preparing images...")
	if err := d.pullImages(displayName); err != nil {
		d.failUpgrade(ctx, id, fmt.Sprintf("Failed to pull images for %s: %v", displayName, err), progress)
		return err
	}

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

	// Step 5: Backup database
	progress.Write("Backing up database...")
	previousVersion := d.version
	backupPath, err := d.backupDatabase(progress)
	if err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Step 6: Install new version — always fetch/checkout by commit SHA directly.
	// No --depth 1: the discovery phase already fetched origin/master, so objects are local.
	// Keeping full history ensures git-describe can find tags for config generate (VERSION).
	progress.Write("Installing %s...", displayName)
	if err := runCommand(projDir, "git", "fetch", "origin", commitSHA); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}
	if err := runCommand(projDir, "git", "-c", "advice.detachedHead=false", "checkout", commitSHA); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Verify checked-out SHA matches manifest (detect tag spoofing) — only for tagged releases
	if !strings.HasPrefix(displayName, "sha-") {
		if manifest, mErr := FetchManifest(displayName); mErr == nil && manifest.CommitSHA != "" {
			if checkedOut, gErr := runCommandOutput(projDir, "git", "rev-parse", "HEAD"); gErr == nil {
				checkedOut = strings.TrimSpace(checkedOut)
				if !strings.HasPrefix(checkedOut, manifest.CommitSHA) && !strings.HasPrefix(manifest.CommitSHA, checkedOut) {
					errMsg := fmt.Sprintf("Version verification failed: expected commit %s but got %s. Possible tag tampering.", manifest.CommitSHA[:12], checkedOut[:12])
					progress.Write("%s", errMsg)
					d.rollback(ctx, id, displayName, previousVersion, progress)
					return fmt.Errorf("%s", errMsg)
				}
			}
		}
	}

	// Regenerate config — VERSION is derived from git describe --tags --always,
	// which returns the tag name (e.g., v2026.03.0-rc.3) since we just checked it out.
	progress.Write("Regenerating configuration...")
	if err := runCommand(projDir, filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Step 8: Pull updated images
	progress.Write("Pulling updated images...")
	if err := runCommand(projDir, "docker", "compose", "pull"); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Step 9: Start database
	progress.Write("Starting database...")
	if err := runCommand(projDir, "docker", "compose", "up", "-d", "db"); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Wait for DB health
	progress.Write("Waiting for database to be healthy...")
	if err := d.waitForDBHealth(30 * time.Second); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Reconnect service DB connection
	progress.Write("Reconnecting to database...")
	if err := d.reconnect(ctx); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Update backup_path now that we have a connection
	d.queryConn.Exec(ctx, "UPDATE public.upgrade SET backup_path = $1 WHERE id = $2", backupPath, id)

	// Step 10: Run migrations (or recreate database if requested)
	if d.pendingRecreate {
		d.pendingRecreate = false
		progress.Write("Recreating database from scratch (--recreate)...")
		if err := runCommandWithTimeout(projDir, 30*time.Minute, filepath.Join(projDir, "dev.sh"), "recreate-database"); err != nil {
			d.rollback(ctx, id, displayName, previousVersion, progress)
			return err
		}
	} else {
		progress.Write("Applying database migrations...")
		if err := runCommand(projDir, filepath.Join(projDir, "sb"), "migrate", "up", "--verbose"); err != nil {
			d.rollback(ctx, id, displayName, previousVersion, progress)
			return err
		}
	}

	// Step 11: Start application services (proxy already running from step 2)
	progress.Write("Starting services...")
	if err := runCommand(projDir, "docker", "compose", "up", "-d", "app", "worker", "rest"); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Step 12: Verify health
	progress.Write("Verifying health...")
	if err := d.healthCheck(5, 5*time.Second); err != nil {
		d.rollback(ctx, id, displayName, previousVersion, progress)
		return err
	}

	// Notify frontend that the upgrade state changed. The DB trigger also fires
	// NOTIFY on completed_at UPDATE, but there's a race: the app's LISTEN may not
	// be established when completed_at is set. This explicit NOTIFY after the health
	// check guarantees the app is listening.
	d.queryConn.Exec(ctx, `NOTIFY worker_status, '{"type":"upgrade_changed"}'`)

	// Done — deactivate maintenance, archive, finalize
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
		progress.Write("Warning: post-upgrade install fixups failed: %v", err)
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
	// Mark complete now since there won't be a new service to do it.
	d.queryConn.Exec(ctx, "UPDATE public.upgrade SET completed_at = now() WHERE id = $1", id)
	d.removeUpgradeFlag()
	d.supersedeOlderReleases(ctx, commitSHA)
	d.runUpgradeCallback(displayName)
	progress.Write("Upgrade to %s complete!", displayName)

	return nil
}

// runUpgradeCallback executes the UPGRADE_CALLBACK shell command from .env, if set.
// Called after a successful upgrade to notify external systems (e.g., Slack).
// Never fails the upgrade — logs errors but always returns.
func (d *Service) runUpgradeCallback(displayName string) {
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
	cmd.Env = append(os.Environ(),
		"STATBUS_VERSION="+displayName,
		"STATBUS_FROM_VERSION="+d.version,
		"STATBUS_SERVER="+hostname,
		"STATBUS_URL="+statbusURL,
	)
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
	if d.queryConn != nil {
		d.queryConn.Exec(ctx, "UPDATE public.upgrade SET error = $1, scheduled_at = NULL WHERE id = $2", errMsg, id)
	}
	progress.Write("FAILED: %s", errMsg)
}

func (d *Service) rollback(ctx context.Context, id int, version, previousVersion string, progress *ProgressLog) {
	progress.Write("Upgrade failed — rolling back to previous version...")

	projDir := d.projDir

	// Stop everything
	runCommand(projDir, "docker", "compose", "stop", "app", "worker", "rest", "db")

	// Restore git state
	if previousVersion != "" {
		if err := runCommand(projDir, "git", "-c", "advice.detachedHead=false", "checkout", "-f", previousVersion); err != nil {
			progress.Write("CRITICAL: git checkout to %s failed: %v — rollback continuing with current code", previousVersion, err)
			fmt.Fprintf(os.Stderr, "CRITICAL: rollback git checkout failed: %v\n", err)
		}
		if err := runCommand(projDir, filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
			progress.Write("Warning: config generate during rollback failed: %v", err)
		}
	}

	// Restore database backup
	d.restoreDatabase(progress)

	// Start with old config
	runCommand(projDir, "docker", "compose", "--profile", "all", "up", "-d", "--remove-orphans")

	// Reconnect (may fail if DB didn't come back)
	if err := d.reconnect(ctx); err != nil {
		progress.Write("Warning: could not reconnect after rollback: %v", err)
	}

	// Deactivate maintenance
	d.setMaintenance(false)

	if d.queryConn != nil {
		d.queryConn.Exec(ctx,
			"UPDATE public.upgrade SET error = 'Rollback completed', rollback_completed_at = now() WHERE id = $1", id)
	}

	// Clear the in-progress flag: the rollback has restored a consistent state,
	// so the mutex that blocks `./sb install` must be released. Without this,
	// the flag lingers until the next service restart, wedging all future installs.
	d.removeUpgradeFlag()

	progress.Write("Rollback complete. The previous version has been restored.")
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

	progress.Write("Self-updating binary...")

	sbPath := filepath.Join(d.projDir, "sb")
	if err := selfupdate.Update(sbPath, binary.URL, binary.SHA256); err != nil {
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

	progress.Write("Binary updated. Restarting service...")
	progress.Close()
	// Exit with code 42 to signal systemd to restart
	os.Exit(42)
}

