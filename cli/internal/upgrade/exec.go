package upgrade

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/inject"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// DiskFree returns the free bytes on the filesystem containing the given path.
func DiskFree(path string) (uint64, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0, err
	}
	return stat.Bavail * uint64(stat.Bsize), nil
}

// prepareCmd configures a command for robust subprocess execution:
// - Runs in its own process group (Setpgid) so we can kill all children
// - WaitDelay ensures cmd.Run() doesn't hang if orphaned children hold pipes open
// - Cancel kills the entire process group, not just the direct child
func prepareCmd(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.WaitDelay = 10 * time.Second
	cmd.Cancel = func() error {
		// Kill the entire process group — ensures docker's child processes die too.
		// Without this, orphaned grandchildren hold stdout/stderr pipes open
		// and cmd.Run() hangs forever (Go issue #59055).
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}
}

// RunCommandOutput executes a command and returns combined output (exported for cmd package).
func RunCommandOutput(dir string, name string, args ...string) (string, error) {
	return runCommandOutput(dir, name, args...)
}

// gitArgs prepends invocation-scoped config overrides when name == "git".
// Specifically disables log.showSignature for programmatic git invocations —
// if the operator set it globally (for their interactive `git log`), it would
// inject "Good 'git' signature..." lines into %H and other --format outputs,
// corrupting any parsing we do (e.g., preflight's "last migration" SHA lookup).
// The override is scoped to the single invocation; the operator's global
// config is untouched.
func gitArgs(name string, args []string) []string {
	if name != "git" {
		return args
	}
	return append([]string{"-c", "log.showSignature=false"}, args...)
}

// runCommand executes a command with inherited stdout/stderr and a default 5-minute timeout.
func runCommand(dir string, name string, args ...string) error {
	return runCommandWithTimeout(dir, 5*time.Minute, name, args...)
}

// runInstallFixup runs `./sb install` as a post-upgrade idempotency step.
//
// Concurrency safety: this function is the ONE legitimate caller that runs
// `./sb install` while the upgrade mutex (tmp/upgrade-in-progress.json) is
// held. It sets --inside-active-upgrade and STATBUS_INSIDE_ACTIVE_UPGRADE=1
// so the child install recognizes itself as part of the active upgrade and
// bypasses the mutex check. Without these signals, the child would abort
// with "upgrade in progress" because our own flag is still on disk at this
// point (it's removed later when executeUpgrade completes successfully).
//
// No other caller in the codebase should ever set these signals.
func runInstallFixup(projDir string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx,
		filepath.Join(projDir, "sb"),
		"install", "--non-interactive", "--inside-active-upgrade",
	)
	cmd.Dir = projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "STATBUS_INSIDE_ACTIVE_UPGRADE=1")
	prepareCmd(cmd)
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("install fixup timed out after 5m")
	}
	return err
}

// runCommandWithTimeout executes a command with a specific timeout.
// Uses process groups and WaitDelay to prevent hangs from orphaned subprocesses.
func runCommandWithTimeout(dir string, timeout time.Duration, name string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, gitArgs(name, args)...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	prepareCmd(cmd)
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("%s %v after %s: %w", name, args, timeout, ErrCommandTimeout)
	}
	return err
}

// runCommandToLog executes a command like runCommandWithTimeout but also
// tees child stdout/stderr into logWriter using PrefixWriter so the
// per-upgrade log captures subprocess output alongside service narration.
// Raw output still flows to os.Stdout/Stderr for daemon journal capture.
// runCommandToLog runs a child process, tee-ing its stdout/stderr to logWriter
// (prefixed) and os.Stdout. onAdvance (nil-able) is the #3 progress-gated
// watchdog hook: it fires once per subprocess output line (via the PrefixWriter
// onLine callback) so a live, emitting step (docker pull, rsync, tar
// --checkpoint) advances ProgressLog.lastAdvanceAt and survives the watchdog.
// Pass progress.bump for tracked active-phase steps; nil for untracked ones
// (git, rollback). NOTE: a SILENT step (a single CREATE INDEX migration) emits
// no lines, so onAdvance alone can't keep it alive — the migrate step uses a
// server-side progress poll instead (plan §3 migrate-path resolution); this
// ErrCommandTimeout wraps a runCommandToLog timeout (ctx DeadlineExceeded) so
// callers can errors.Is() it. The migrate site uses this to fire the #14
// orphan-terminate ONLY on a genuine timeout (a host-side process-group SIGKILL
// of the docker-exec client leaves an orphaned in-container psql backend) —
// NOT on a clean non-timeout migrate failure, where psql exited and there is no
// orphan to reap.
var ErrCommandTimeout = errors.New("command timed out")

// callback covers the output-emitting steps.
func runCommandToLog(dir string, timeout time.Duration, logWriter io.Writer, source string, onAdvance func(), name string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, gitArgs(name, args)...)
	cmd.Dir = dir
	outW := NewPrefixWriter("O", source, logWriter, onAdvance)
	errW := NewPrefixWriter("E", source, logWriter, onAdvance)
	cmd.Stdout = io.MultiWriter(os.Stdout, outW)
	cmd.Stderr = io.MultiWriter(os.Stderr, errW)
	prepareCmd(cmd)
	err := cmd.Run()
	outW.Flush()
	errW.Flush()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("%s %v after %s: %w", name, args, timeout, ErrCommandTimeout)
	}
	return err
}

// runCommandOutput executes a command and returns combined output.
func runCommandOutput(dir string, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, gitArgs(name, args)...)
	cmd.Dir = dir
	prepareCmd(cmd)
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return string(out), fmt.Errorf("command timed out after 2m: %s %v", name, args)
	}
	return string(out), err
}

func (d *Service) pullImages(version string) error {
	// docker compose reads VERSION from .env, not from process environment.
	// For pre-downloads before config regeneration, we pass it as an override.
	// 10-minute timeout: image pulls can be slow on shared servers.
	// --quiet suppresses progress bars that cause excessive pipe output under systemd.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", "compose", "pull", "--quiet")
	cmd.Dir = d.projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "VERSION="+version)
	prepareCmd(cmd)
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("docker compose pull timed out after 10 minutes")
	}
	return err
}

func (d *Service) setMaintenance(active bool) {
	// ~/maintenance is the path Caddy's try_files directive watches (see
	// cli/src/templates/private.caddyfile.ecr and standalone.caddyfile.ecr).
	// When this file exists, Caddy serves maintenance.html with 503 for all requests.
	file := filepath.Join(os.Getenv("HOME"), "maintenance")

	if active {
		_, statErr := os.Stat(file)
		if err := os.WriteFile(file, []byte("upgrade in progress\n"), 0644); err != nil {
			fmt.Printf("maintenance ON — failed to create %s: %v\n", file, err)
		} else if os.IsNotExist(statErr) {
			fmt.Printf("maintenance ON — added %s (created new)\n", file)
		} else {
			fmt.Printf("maintenance ON — added %s (already existed)\n", file)
		}
	} else {
		var age string
		if fi, err := os.Stat(file); err == nil {
			age = fmt.Sprintf(" (was on for %s)", time.Since(fi.ModTime()).Truncate(time.Second))
		}
		if err := os.Remove(file); err != nil && !os.IsNotExist(err) {
			fmt.Printf("maintenance OFF — failed to remove %s: %v\n", file, err)
		} else {
			fmt.Printf("maintenance OFF — removed %s%s\n", file, age)
		}
	}
}

// dbVolumeName returns the Docker named volume for PostgreSQL data.
// Derived from COMPOSE_INSTANCE_NAME in .env (e.g., "statbus-speed-db-data").
func (d *Service) dbVolumeName() string {
	envPath := filepath.Join(d.projDir, ".env")
	if f, err := dotenv.Load(envPath); err == nil {
		if name, ok := f.Get("COMPOSE_INSTANCE_NAME"); ok {
			return name + "-db-data"
		}
	}
	return "statbus-db-data" // fallback
}

// backupRoot is the directory holding the backup state. Since CHANGE 2 (task
// #12) the rsync snapshot is a SINGLE persistent dir committed by atomic rename
// (backupActiveName ↔ backupSyncingName); legacy per-stamp pre-upgrade-<stamp>
// dirs from before the migration may still be present and are reaped by the
// reconcile orphan pass. The per-version archive tars (<version>-pre.tar.gz)
// also live here and carry the per-upgrade history.
func (d *Service) backupRoot() string {
	return filepath.Join(os.Getenv("HOME"), "statbus-backups")
}

// Managed backup dir names (CHANGE 2 / task #12). The persistent rsync snapshot
// is committed by atomic directory rename, where the dir NAME is the
// clean/dirty state:
//   - backupActiveName  — a COMPLETE, restorable snapshot (the incremental base
//     for the next backup, and the rollback source). pickLatestBackup /
//     restoreDatabase read ONLY this.
//   - backupSyncingName — an IN-FLIGHT or killed-mid-rsync PARTIAL. Never
//     restorable; a killed run RESUMES by rsyncing into it (never deleted), and
//     only rename(syncing→active) publishes it. Structurally invisible to
//     pickLatestBackup.
//
// active and syncing never coexist from our sequence (the aside-rename consumes
// active before syncing exists; the commit-rename consumes syncing while active
// is absent), so there is no cleanup branch — an unexpected coexistence makes a
// rename fail loudly (fail-fast), never a silent rm.
const (
	backupActiveName  = "pre-upgrade-active"
	backupSyncingName = "pre-upgrade-syncing"
)

// isManagedBackupDir reports whether name is one of the two CHANGE-2 managed
// dirs (active/syncing). Both reconcileBackupDir's orphan pass and pruneBackups
// EXCLUDE these: they are governed by the backup rename state machine, not
// reference-counted against public.upgrade rows. Without the exclusion a
// stale-mtime syncing (a killed run's incremental base, or a live partial)
// would be misclassified as a 90-day orphan and PURGED, destroying the base.
// Legacy per-stamp pre-upgrade-<stamp>(.tmp) dirs are NOT managed → they remain
// subject to the orphan/prune logic for graceful post-migration cleanup.
func isManagedBackupDir(name string) bool {
	return name == backupActiveName || name == backupSyncingName
}

// humanBytes formats a byte count as a human-readable string.
// Local duplicate of cmd/db.go humanSize — different package, and we
// don't want to promote this to a shared util just for two callers.
func humanBytes(bytes int64) string {
	const (
		kb = 1024
		mb = 1024 * kb
		gb = 1024 * mb
	)
	switch {
	case bytes >= gb:
		return fmt.Sprintf("%.1f GB", float64(bytes)/float64(gb))
	case bytes >= mb:
		return fmt.Sprintf("%.1f MB", float64(bytes)/float64(mb))
	case bytes >= kb:
		return fmt.Sprintf("%.1f KB", float64(bytes)/float64(kb))
	default:
		return fmt.Sprintf("%d B", bytes)
	}
}

// dirExists reports whether path exists and is a directory.
func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// syncTree fsyncs every regular file and directory under root so the data — not
// just the directory entries — is durable on disk before a commit rename. Used
// by backupDatabase before rename(syncing→active): rsync does not fsync, and an
// os.Rename persists only the name, so without this a crash right after the
// rename could publish an active snapshot whose file contents were still only in
// the page cache. Best-effort per-node (a single fsync failure is collected and
// returned, not aborted mid-walk) — the caller logs and proceeds, trading a
// narrow durability window against refusing to commit a backup that is almost
// certainly on disk. The whole walk also skips files it cannot open (the rsync
// chown left them deploy-user-owned, so this is rare).
func syncTree(root string) error {
	var firstErr error
	note := func(err error) {
		if err != nil && firstErr == nil {
			firstErr = err
		}
	}
	walkErr := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			note(err)
			return nil // keep walking other nodes
		}
		// fsync regular files and directories; skip symlinks/devices/etc.
		if !info.Mode().IsRegular() && !info.IsDir() {
			return nil
		}
		f, openErr := os.Open(path)
		if openErr != nil {
			note(openErr)
			return nil
		}
		if syncErr := f.Sync(); syncErr != nil {
			note(syncErr)
		}
		f.Close()
		return nil
	})
	note(walkErr)
	return firstErr
}

// prepareBackupSnapshotDir readies the syncing base for backupDatabase's rsync
// (CHANGE 2 / task #12, step 1) and returns its path. DB-free + no docker, so
// the rename state machine is unit-testable in isolation:
//   - active exists, syncing absent → rename(active→syncing): the persistent
//     base moves aside with content PRESERVED (the incremental base).
//   - active absent, syncing present → a killed run's leftover IS the base:
//     RESUME into it (no rename, no rm).
//   - neither → first-ever backup: create an empty syncing.
//   - BOTH → corrupt state that this sequence never produces: fail LOUD (no
//     silent rm, no guess).
//
// The caller rsyncs into the returned dir, fsyncs it, then commits via
// rename(syncing→active).
func (d *Service) prepareBackupSnapshotDir(progress *ProgressLog) (string, error) {
	root := d.backupRoot()
	activeDir := filepath.Join(root, backupActiveName)
	syncingDir := filepath.Join(root, backupSyncingName)

	activeExists := dirExists(activeDir)
	syncingExists := dirExists(syncingDir)
	switch {
	case activeExists && syncingExists:
		return "", fmt.Errorf(
			"backup state corrupt: both %s and %s exist (they must never coexist); "+
				"inspect %s manually — refusing to guess or delete",
			backupActiveName, backupSyncingName, root)
	case activeExists:
		if err := os.Rename(activeDir, syncingDir); err != nil {
			return "", fmt.Errorf("move backup base aside (%s -> %s): %w", backupActiveName, backupSyncingName, err)
		}
	case syncingExists:
		// Resume into the leftover syncing base — no rename, no rm.
		progress.Write("Resuming into existing %s base from a prior interrupted backup...", backupSyncingName)
	default:
		// First-ever backup (or after a legacy migration): create an empty
		// syncing for rsync to populate.
		if err := os.MkdirAll(syncingDir, 0755); err != nil {
			return "", fmt.Errorf("create backup syncing dir: %w", err)
		}
	}
	return syncingDir, nil
}

// backupDatabase rsyncs the live Postgres data volume into a PERSISTENT
// snapshot dir, committed by an atomic directory rename (CHANGE 2 / task #12,
// replacing the prior per-stamp .tmp→final scheme). Returns the path of the
// committed snapshot (…/pre-upgrade-active).
//
// Mechanism — the dir NAME is the clean/dirty state:
//  1. If pre-upgrade-active/ exists → rename(active → syncing). Atomic; CONTENT
//     PRESERVED, so syncing is the incremental base the rsync reconciles against
//     (fast on the 2nd+ backup — only the delta transfers). If active is absent,
//     a syncing left by a previously-killed run IS the base — go straight to
//     rsync into it; NEVER delete it (rsync --delete reconciles the partial to
//     the source incrementally — that partial is exactly what we resume from).
//  2. rsync -a --delete /source(volume) → /backup(syncing).
//  3. fsync the FILE DATA in syncing (not just the dir entries) so the snapshot
//     is durable before it's published.
//  4. rename(syncing → active). active is absent at this point (consumed in step
//     1), so this is a clean atomic commit. The snapshot is COMPLETE iff named
//     pre-upgrade-active.
//
// Why rename over a .complete marker: a single atomic rename mirrors the shipped
// ATOMIC archive tar (one mental model), the state IS the name (no sentinel to
// get out of sync), and it's fail-safe by construction — a crash anywhere leaves
// either active (complete) or syncing (partial, ignored by pickLatestBackup).
// active and syncing never coexist from this sequence, so there is NO cleanup
// branch and NO rm; an unexpected coexistence makes a rename fail loudly.
//
// rsync --delete is not itself crash-safe (it removes before copying), but that
// is fine here: it operates on syncing, never on active — a killed rsync leaves
// a half-reconciled syncing (resumed next run), while active stays untouched and
// restorable throughout.
//
// stamp (UTC timestamp) is no longer used for the rsync dir name; it is retained
// for the per-upgrade archive tar + the upgrade-logs-<stamp> sibling correlation
// (cascadeUpgradeLogsIntoBackup), which remain per-upgrade.
func (d *Service) backupDatabase(progress *ProgressLog, stamp string) (string, error) {
	root := d.backupRoot()
	if err := os.MkdirAll(root, 0755); err != nil {
		return "", fmt.Errorf("create backup root: %w", err)
	}

	activeDir := filepath.Join(root, backupActiveName)

	// Step 1: get the syncing base ready (rename active aside / resume leftover /
	// create fresh). Extracted + DB-free so the rename state machine is
	// unit-testable without the docker rsync below.
	syncingDir, err := d.prepareBackupSnapshotDir(progress)
	if err != nil {
		return "", err
	}

	// rsync from named Docker volume into the syncing dir via a lightweight
	// container. DB must be stopped before this point for a consistent
	// backup. No sudo needed — the container runs as root and can read
	// postgres-owned files.
	volumeName := d.dbVolumeName()

	// Heartbeat wrapper. Raw rsync stdout is streamed via progress.File()
	// (bypasses progress.Write, which is where the unified emitHeartbeat
	// lives). A large DB can keep rsync running for minutes, which would
	// silence the main goroutine for the duration and tickle
	// WatchdogSec=120. Emit a progress.Write every 30s so each tick fires
	// emitHeartbeat via the unified path.
	//
	// "%s copied": delta in free-disk-space since backup start, computed
	// via statfs. Prior implementation walked tmpDir with filepath.Walk
	// and summed file sizes — but rsync runs as root inside the alpine
	// container and preserves the source's postgres-UID ownership when
	// writing through the bind mount. The host-side process is the
	// statbus user, which can't traverse postgres-owned subdirs (e.g.
	// /backup/base/). filepath.Walk silently swallows the EACCES errors
	// → total stayed at 0, hence the famous "0 B copied" log lines for
	// the entire 3-minute backup. statfs sees real on-disk bytes
	// regardless of file ownership.
	//
	// Caveat: other writers to the same filesystem would skew the
	// reading. During an upgrade the database is stopped and the worker
	// is idle, so rsync is effectively the only writer; the metric is
	// accurate to within filesystem-overhead noise.
	rsyncStart := time.Now()
	rsyncDone := make(chan struct{})
	rsyncTicker := time.NewTicker(30 * time.Second)
	freeAtStart, _ := DiskFree(root)
	go func() {
		defer rsyncTicker.Stop()
		for {
			select {
			case <-rsyncDone:
				return
			case <-rsyncTicker.C:
				freeNow, _ := DiskFree(root)
				var copied int64
				if freeAtStart > freeNow {
					copied = int64(freeAtStart - freeNow)
				}
				progress.Write("Still backing up database (%s elapsed, %s copied)...",
					time.Since(rsyncStart).Truncate(time.Second),
					humanBytes(copied))
			}
		}
	}()
	// chown + chmod inside the container after rsync so the finalised
	// dir is owned by the host's deploy user (not the in-container
	// postgres user, which lands as messagebus/uid 101 on Debian/Ubuntu
	// hosts via UID coincidence). Without this:
	//   - statbus_<slot> can't traverse the 0700 messagebus-owned dir →
	//     pruneBackups can't remove old backups → ~/statbus-backups/
	//     accumulates indefinitely (observed on jo: 9 backup dirs going
	//     back to March 2026).
	//   - The post-install archive step (tar | gzip) fails with
	//     "Permission denied" on EVERY file inside the backup, leaving
	//     no shippable artifact for support-bundle attachment.
	//
	// The chown is harmless to restoreDatabase: that path also runs
	// inside an alpine container as root and reads /source via rsync,
	// which doesn't care about host-side ownership.
	deployUID := os.Getuid()
	deployGID := os.Getgid()
	rsyncShell := fmt.Sprintf(
		"apk add --no-cache rsync >/dev/null 2>&1 && "+
			"rsync -a --delete /source/ /backup/ && "+
			"chown -R %d:%d /backup && "+
			"chmod -R u=rwX,go=rX /backup",
		deployUID, deployGID,
	)
	rsyncErr := runCommandToLog(d.projDir, 10*time.Minute, progress.File(), "rsync", nil,
		"docker", "run", "--rm",
		"-v", volumeName+":/source:ro",
		"-v", syncingDir+":/backup",
		"alpine", "sh", "-c", rsyncShell,
	)
	if rsyncErr != nil {
		close(rsyncDone) // stop the heartbeat ticker
		// Leave the syncing dir in place — it is the incremental base the next
		// run resumes into (NEVER deleted). It is structurally invisible to
		// pickLatestBackup (not named active), so a partial cannot be restored.
		return "", fmt.Errorf("rsync backup: %w", rsyncErr)
	}

	// fsync the syncing dir's FILE DATA before the commit rename. rsync does not
	// fsync by default, and an os.Rename of the dir entry persists only the
	// NAME, not the file contents — a crash after the rename but before the
	// kernel flushed the data would publish an active dir whose files are
	// partially in the page cache only. syncTree walks the subtree and fsyncs
	// each regular file + the dirs (best-effort: a fsync failure is logged, not
	// fatal — the data is very likely on disk and refusing to commit would be a
	// worse outcome than a small durability-window risk).
	//
	// Runs BEFORE close(rsyncDone) so the 30 s heartbeat ticker keeps pinging
	// WATCHDOG=1 through the fsync walk too — on a large DB (many files) the
	// walk can take several seconds, and executeUpgrade runs active-phase under
	// WatchdogSec (plan #2), so an unheartbeated gap here could trip it.
	if err := syncTree(syncingDir); err != nil {
		progress.Write("warning: fsync of backup contents in %s failed (proceeding): %v", backupSyncingName, err)
	}
	close(rsyncDone) // stop the heartbeat ticker (rsync + fsync both done)

	// Harness-only kill site (C3): simulates the OS / orchestrator killing the
	// process AFTER rsync finishes but BEFORE the atomic commit rename. The
	// wedge state: the syncing dir has a complete copy of the DB volume but the
	// syncing→active rename never happened, so on-disk the backup looks "in
	// flight" (partial). The pre-upgrade git branch was already pinned upstream
	// (executeUpgrade step before this call) so restoreGitState has its anchor.
	// The next install's recoverFromFlag sees flag PreSwap (kill fired upstream
	// of updateFlagPostSwap) and routes through the PreSwap recovery branch; the
	// OLD DB volume is intact (backup was a COPY, source unmodified). A retry
	// resumes by rsyncing into the leftover syncing, then commits. No active dir
	// is produced by the killed run, so pickLatestBackup won't read the partial.
	//
	// Placement rationale: in this exact spot the rsync has completed (so the
	// test exercises real I/O), but the rename is the next thing the parent
	// would do. No-op in production. Drives scenario 21.
	inject.KillHere("killed-by-system-during-preswap-backup")

	// Atomic commit: rename syncing → active. active is absent here (consumed at
	// the top), so this is a clean atomic publish. The snapshot is COMPLETE iff
	// it is named active. No sentinel files, no symlinks.
	if err := os.Rename(syncingDir, activeDir); err != nil {
		return "", fmt.Errorf("commit backup (rename %s -> %s): %w", backupSyncingName, backupActiveName, err)
	}

	// Cascade tmp/upgrade-logs/ into <root>/upgrade-logs-<stamp>/ (sibling
	// of the backup dir) so the historical log+bundle pairs are accessible
	// to the deploying user without touching the rsync-root-owned backup dir.
	// Best-effort — a log-snapshot miss must not abort the upgrade; the DB
	// dump is the critical artifact.
	if err := cascadeUpgradeLogsIntoBackup(d.projDir, root, stamp); err != nil {
		progress.Write("warning: cascade upgrade-logs into %s/upgrade-logs-%s: %v", root, stamp, err)
	}

	// Pruning is deferred to the service tick (reconcileBackupDir + pruneBackups)
	// where d.queryConn is live and can NULL backup_path before deletion.
	// No pruning here — the DB connection is closed for the duration of executeUpgrade.

	return activeDir, nil
}

// cascadeUpgradeLogsIntoBackup mirrors the current tmp/upgrade-logs/
// snapshot into <root>/upgrade-logs-<stamp>/ — a sibling of the
// pre-upgrade-<stamp> backup directory rather than a subdirectory of it.
//
// Rationale: the backup dir is rsync-populated from inside an Alpine
// container running as root, which chowns the mount point to uid 70
// (postgres inside Alpine = messagebus on the host) with mode 0700.
// After the atomic rename the backup dir is inaccessible to the
// deploying user (statbus_dev). Writing logs into a sibling that is
// always MkdirAll'd by the Go process keeps ownership at the deploying
// user (0755) while leaving the DB restoration artifact pristine.
//
// Called from backupDatabase after the atomic rename finalises the
// backup directory. Regular files only (.log and .bundle.txt pairs);
// symlinks and subdirectories are skipped. Idempotent: os.Create
// overwrites existing destinations.
func cascadeUpgradeLogsIntoBackup(projDir, root, stamp string) error {
	srcDir := upgradeLogsDir(projDir)
	entries, err := os.ReadDir(srcDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("read %s: %w", srcDir, err)
	}
	destDir := filepath.Join(root, "upgrade-logs-"+stamp)
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return fmt.Errorf("create %s: %w", destDir, err)
	}
	for _, e := range entries {
		if !e.Type().IsRegular() {
			continue
		}
		if err := copyRegularFile(filepath.Join(srcDir, e.Name()), filepath.Join(destDir, e.Name())); err != nil {
			return fmt.Errorf("copy %s: %w", e.Name(), err)
		}
	}
	return nil
}

func copyRegularFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// pickLatestBackup returns the path of the COMPLETE restorable snapshot, or ""
// if none exists. Since CHANGE 2 (task #12) that is the persistent
// backupActiveName dir. For backward compatibility — an upgrade that backed up
// under the OLD per-stamp scheme and then recovers under the new binary, with no
// active dir yet — it falls back to the newest legacy finalised
// pre-upgrade-<stamp> dir (timestamp prefix sorts lexicographically, so
// sort.Strings + take-max gives the newest). A partial backupSyncingName and
// any legacy .tmp are ALWAYS excluded: restore must never read an incomplete
// snapshot. "" makes restoreDatabase abort rather than touch the live volume.
func (d *Service) pickLatestBackup() string {
	root := d.backupRoot()

	// Primary: the persistent active snapshot.
	active := filepath.Join(root, backupActiveName)
	if info, err := os.Stat(active); err == nil && info.IsDir() {
		return active
	}

	// Legacy fallback: newest finalised pre-upgrade-<stamp> (excluding the
	// managed syncing dir and any .tmp). Covers the cross-deploy-boundary
	// in-flight upgrade until the next backup produces an active dir.
	entries, err := os.ReadDir(root)
	if err != nil {
		return ""
	}
	var finalised []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasPrefix(name, "pre-upgrade-") {
			continue
		}
		if strings.HasSuffix(name, ".tmp") || isManagedBackupDir(name) {
			continue
		}
		finalised = append(finalised, name)
	}
	if len(finalised) == 0 {
		return ""
	}
	sort.Strings(finalised)
	return filepath.Join(root, finalised[len(finalised)-1])
}

// restoreDatabase rsync-restores the DB volume from the finalised snapshot.
// Returns nil on success OR on the no-backup no-op (the PreSwap case, where the
// DB volume was never mutated so there is nothing to restore — the box stays
// healthy). Returns a non-nil error ONLY when an rsync restore was attempted and
// FAILED: the volume is then left inconsistent, so the caller must record the
// row terminal as `failed` (degraded), not `rolled_back`.
func (d *Service) restoreDatabase(progress *ProgressLog) error {
	backupDir := d.pickLatestBackup()
	if backupDir == "" {
		progress.Write("ABORT: no finalised backup directory found in %s; refusing to touch the live volume", d.backupRoot())
		return nil
	}
	volumeName := d.dbVolumeName()

	progress.Write("Restoring database from backup at %s...", backupDir)
	if err := runCommandToLog(d.projDir, 10*time.Minute, progress.File(), "rsync", nil,
		"docker", "run", "--rm",
		"-v", backupDir+":/source:ro",
		"-v", volumeName+":/dest",
		"alpine", "sh", "-c", "apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /source/ /dest/",
	); err != nil {
		progress.Write("%s: database restore failed: %v", ErrRollbackDBRestore, err)
		return fmt.Errorf("%s: %w", ErrRollbackDBRestore, err)
	}
	return nil
}

// pruneBackups trims LEGACY finalised pre-upgrade-<stamp> backups to the `keep`
// most recent. Before removing each dir it NULLs backup_path on the matching
// upgrade row so reconcileBackupDir does not emit BACKUP_MISSING noise for
// intentionally-pruned dirs on subsequent ticks. .tmp dirs are excluded
// (reconcileBackupDir owns them), and since CHANGE 2 (task #12) the two MANAGED
// dirs (active/syncing) are excluded too — there is only ever one persistent
// active snapshot (no collection to trim), and it must never be pruned. This
// function now only reaps leftover per-stamp dirs during the migration window;
// per-upgrade history lives in the archive tars (pruneArchives keeps N).
//
// Must be called with an active d.queryConn (i.e. from the service tick, not from
// within executeUpgrade where the DB is closed).
func (d *Service) pruneBackups(ctx context.Context, keep int) {
	entries, err := os.ReadDir(d.backupRoot())
	if err != nil {
		return
	}
	var finalised []string
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasPrefix(name, "pre-upgrade-") {
			continue
		}
		if strings.HasSuffix(name, ".tmp") || isManagedBackupDir(name) {
			continue // .tmp: reconcileBackupDir owns; active/syncing: managed, never pruned
		}
		finalised = append(finalised, filepath.Join(d.backupRoot(), name))
	}
	if len(finalised) > keep {
		sort.Strings(finalised)
		toPrune := finalised[:len(finalised)-keep]
		pruned := 0
		for _, p := range toPrune {
			// NULL the DB reference before deletion.  If the Exec fails, skip
			// os.RemoveAll for this cycle: deleting without nulling would cause
			// permanent BACKUP_MISSING noise — one extra cycle is the lesser cost.
			if d.queryConn != nil {
				if _, err := d.queryConn.Exec(ctx,
					"UPDATE public.upgrade SET backup_path = NULL WHERE backup_path = $1", p); err != nil {
					continue // retry next tick
				}
			}
			os.RemoveAll(p)
			log.Printf("Pruned backup: %s", filepath.Base(p))
			pruned++
			// Prune the matching upgrade-logs-<stamp> sibling (created by
			// cascadeUpgradeLogsIntoBackup). It has no DB row reference so
			// reconcileBackupDir would not touch it — we must co-prune here.
			base := filepath.Base(p) // "pre-upgrade-<stamp>"
			stamp := strings.TrimPrefix(base, "pre-upgrade-")
			if stamp != base { // only if the prefix was present
				logsDir := filepath.Join(d.backupRoot(), "upgrade-logs-"+stamp)
				os.RemoveAll(logsDir)
			}
		}
		if pruned > 0 {
			log.Printf("Pruned %d backup(s), keeping %d newest", pruned, keep)
		}
	}
}

// runRetentionPurge executes the v2 retention policy for public.upgrade.
//
//   - context: "all" for the periodic time-safety sweep, or one of
//     {"commit","prerelease","release"} to scope the sweep (rarely used).
//   - installedID: when the caller just transitioned a row to 'completed',
//     pass its id so rules A/B/C (install-triggered purges) fire. NULL for
//     the time-safety tick.
//
// File-first cascade: fetch the plan, delete each row's log + .bundle.txt
// sibling on disk, THEN call upgrade_retention_apply to DELETE the DB rows.
// If the process dies between file-delete and row-delete, the DB row
// survives but references a missing log — the admin UI shows empty content
// for that log; retention will pick the row up again on the next tick.
// All errors are logged and swallowed: retention is opportunistic, not a
// hard upgrade dependency.
func (d *Service) runRetentionPurge(ctx context.Context, scope string, installedID *int) {
	if d.queryConn == nil {
		return
	}
	rows, err := d.queryConn.Query(ctx,
		"SELECT id, log_relative_file_path FROM public.upgrade_retention_plan($1, $2)",
		scope, installedID)
	if err != nil {
		fmt.Printf("retention: plan query failed (scope=%s, installed=%v): %v\n", scope, installedID, err)
		return
	}
	var plannedLogs []string
	var plannedCount int
	for rows.Next() {
		var id int
		var logPath *string
		if err := rows.Scan(&id, &logPath); err != nil {
			fmt.Printf("retention: plan scan failed: %v\n", err)
			rows.Close()
			return
		}
		plannedCount++
		if logPath != nil && *logPath != "" {
			plannedLogs = append(plannedLogs, *logPath)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fmt.Printf("retention: plan iterate failed: %v\n", err)
		return
	}
	if plannedCount == 0 {
		return
	}

	logsDir := upgradeLogsDir(d.projDir)
	for _, rel := range plannedLogs {
		stem := strings.TrimSuffix(rel, ".log")
		os.Remove(filepath.Join(logsDir, rel))
		os.Remove(filepath.Join(logsDir, stem+".bundle.txt"))
	}

	// Third arg is the INOUT p_deleted; the procedure overwrites it. We pass 0
	// and discard the result — plannedCount above already serves as our log.
	if _, err := d.queryConn.Exec(ctx,
		"CALL public.upgrade_retention_apply($1, $2, 0)", scope, installedID); err != nil {
		fmt.Printf("retention: apply failed (scope=%s, installed=%v): %v\n", scope, installedID, err)
		return
	}
	fmt.Printf("retention: purged %d upgrade row(s) (scope=%s, installed=%v)\n", plannedCount, scope, installedID)
}

// pruneUpgradeLogs trims tmp/upgrade-logs/ to the `keep` newest log+bundle
// pairs. Sibling of pruneBackups. Safe to call on every service tick —
// O(entries) readdir, cheap. Any upgrade row that still references a
// just-deleted log file will see empty content when the admin UI
// fetches /upgrade-logs/<name>; retention v2's row DELETE is expected
// to run first, so dangling references are transient.
//
// Pairs share a stem — the `.log` basename without suffix is also the
// prefix of the `.bundle.txt`. We scan both suffixes so an orphan
// bundle (written when the log was already pruned, or vice versa)
// still counts against the keep window and gets its own chance at
// eviction. Age is taken as the newest mtime across the pair so a
// late-written bundle doesn't get evicted ahead of its own log.
//
// Sort is by mtime, NOT filename. Filenames start with the numeric
// upgrade id — lexicographic ordering picks the wrong oldest once ids
// span varying widths ("10-…" sorts before "2-…").
func (d *Service) pruneUpgradeLogs(keep int) {
	dir := upgradeLogsDir(d.projDir)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	type pair struct {
		stem  string
		mtime time.Time
	}
	pairs := make(map[string]*pair)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		var stem string
		switch {
		case strings.HasSuffix(e.Name(), ".log"):
			stem = strings.TrimSuffix(e.Name(), ".log")
		case strings.HasSuffix(e.Name(), ".bundle.txt"):
			stem = strings.TrimSuffix(e.Name(), ".bundle.txt")
		default:
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if existing, ok := pairs[stem]; ok {
			if info.ModTime().After(existing.mtime) {
				existing.mtime = info.ModTime()
			}
		} else {
			pairs[stem] = &pair{stem: stem, mtime: info.ModTime()}
		}
	}
	if len(pairs) <= keep {
		return
	}
	sorted := make([]*pair, 0, len(pairs))
	for _, p := range pairs {
		sorted = append(sorted, p)
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].mtime.Before(sorted[j].mtime) })
	toPrune := sorted[:len(sorted)-keep]
	for _, p := range toPrune {
		os.Remove(filepath.Join(dir, p.stem+".log"))        // no-op if absent
		os.Remove(filepath.Join(dir, p.stem+".bundle.txt")) // no-op if absent
	}
	if len(toPrune) > 0 {
		log.Printf("Pruned %d upgrade log(s), keeping %d newest", len(toPrune), keep)
	}
}

// tarSupportsCheckpoint reports whether the given `tar --version` output is GNU
// tar, which supports --checkpoint / --checkpoint-action (used by archiveBackup
// to feed the #3 progress-gated watchdog). BSD/libarchive tar (the macOS dev
// default) does NOT — passing --checkpoint to it errors on an unknown flag. We
// capability-gate on this rather than on GOOS or NOTIFY_SOCKET: the same tar
// command shape runs everywhere; only the checkpoint flags are appended when
// the host tar is GNU. On a bsdtar host the tar runs without checkpoints, which
// is harmless (those hosts — macOS dev — have no systemd WatchdogSec to feed).
func tarSupportsCheckpoint(versionOutput string) bool {
	// GNU tar's first line is `tar (GNU tar) <version>`; bsdtar prints
	// `bsdtar <v> - libarchive <v>`. Match the unambiguous GNU marker.
	return strings.Contains(versionOutput, "GNU tar")
}

// hostTarCheckpointOnce caches the one-time `tar --version` probe so archiveBackup
// (called once per upgrade, but the probe shouldn't re-run on retries) pays the
// fork cost at most once per process.
var (
	hostTarCheckpointOnce sync.Once
	hostTarCheckpointOK   bool
)

// hostTarSupportsCheckpoint probes the host tar ONCE and reports whether it is
// GNU tar (supports --checkpoint). A probe failure (tar missing, error) is
// treated as "no checkpoint support" — fail safe: archiveBackup then runs a
// plain tar (the pre-#11 behaviour), never passing a flag that would error.
func hostTarSupportsCheckpoint(dir string) bool {
	hostTarCheckpointOnce.Do(func() {
		out, err := runCommandOutput(dir, "tar", "--version")
		if err != nil {
			hostTarCheckpointOK = false
			return
		}
		hostTarCheckpointOK = tarSupportsCheckpoint(out)
	})
	return hostTarCheckpointOK
}

// archiveBackupTimeout is the generous outer ceiling on the archive tar (task
// #11). The real liveness bound on a HUNG tar is the #3 progress-gated watchdog
// (fed by --checkpoint output); this timeout only guarantees the call can't hang
// a goroutine forever. The archive is post-FIX-A forensics (row already
// completed, flag removed), so a timeout-kill is harmless — sized to fit a real
// 35 GB tar, unlike the 5-min runCommand default it replaced.
const archiveBackupTimeout = 60 * time.Minute

func (d *Service) archiveBackup(backupPath, version string, progress *ProgressLog) {
	archiveDir := filepath.Join(os.Getenv("HOME"), "statbus-backups")
	archivePath := filepath.Join(archiveDir, fmt.Sprintf("%s-pre.tar.gz", version))
	// ATOMIC (task #8): tar to a `.tmp` and atomically rename to the final
	// name only on tar success. A tar that is interrupted (the systemd
	// start-phase SIGTERM that wedged NO/rune, a SIGKILL, disk-full mid-tar)
	// or that exits non-zero must NEVER leave a partial at the final
	// `<version>-pre.tar.gz` — a partial there is indistinguishable from a
	// complete archive to pruneArchives (which keeps the 3 newest `.gz` by
	// name) and to an operator inspecting the backups dir. Writing to `.tmp`
	// first confines any partial to the `.tmp` name (ignored by pruneArchives,
	// ext != .gz) and the rename publishes the final name only when the tar
	// completed cleanly. Idempotent: backupPath persists, so a later run
	// re-tars and overwrites the `.tmp`. Best-effort throughout (warn + return
	// on any failure) — the archive is forensics, not the rollback artifact.
	tmpPath := archivePath + ".tmp"

	// Harness-only stall site for Bug 1 — `d416a50a0` introduced a
	// ticker scoped only to the migrate-up subprocess. `extendCancel()`
	// fires before archiveBackup; the tar of a multi-GB backup (rune:
	// 35 GB) keeps the main goroutine parked with no WATCHDOG=1
	// emitter. Active-phase systemd's WatchdogSec=120 s fires; SIGABRT;
	// restart loop. Activated by
	// STATBUS_INJECT_AT=archive-backup-stall-active-phase-watchdog
	// and held by STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE. No-op in
	// production. The stall runs BEFORE tar so the harness sees the
	// main goroutine parked at the canonical "tar in flight" point.
	inject.StallHere("archive-backup-stall-active-phase-watchdog")

	// CHANGE 1 (task #11): feed the #3 progress-gated watchdog from the tar's
	// own progress so a LIVE long archive (rune: 35 GB, minutes) keeps the gate
	// open and a write-HUNG tar trips it. GNU tar's --checkpoint=N fires every N
	// records PROCESSED (record = 512 B × blocking-factor 20 = 10 KiB; N=1000 ⇒
	// ~every 10 MiB), and --checkpoint-action=echo writes a line to stderr.
	// runCommandToLog tees that through the PrefixWriter whose onLine callback is
	// progress.bump → lastAdvanceAt advances per checkpoint. A write-hang stops
	// the records → stops the checkpoints → stops the bumps → the gate closes →
	// WatchdogSec fires. Checkpoint-REAL (records processed), NOT a blind
	// wall-clock ticker — it cannot recreate the task-#37 blind-watchdog hang.
	//
	// Capability-gated: --checkpoint is GNU-only. On a bsd/libarchive host
	// (macOS dev) we omit it and run a plain tar — harmless there (no systemd
	// WatchdogSec to feed). Same tar command shape everywhere; only the flags
	// differ, gated on tar capability (NOT on GOOS or NOTIFY_SOCKET). See
	// hostTarSupportsCheckpoint / tarSupportsCheckpoint.
	//
	// Timeout: archiveBackup's prior runCommand used the 5-min runCommand
	// default — too tight for a 35 GB tar (it would time out → no archive). The
	// archive is post-FIX-A forensics (row already completed, flag removed), so a
	// timeout-kill is harmless; archiveBackupTimeout=60 min is a generous outer
	// ceiling so a goroutine can't live forever, while the gated watchdog
	// (checkpoint-fed) is the real bound on a HUNG tar.
	tarArgs := []string{"-czf", tmpPath, "-C", filepath.Dir(backupPath), filepath.Base(backupPath)}
	if hostTarSupportsCheckpoint(d.projDir) {
		tarArgs = append(tarArgs,
			"--checkpoint=1000",
			"--checkpoint-action=echo=archive: %u records")
	}
	if err := runCommandToLog(d.projDir, archiveBackupTimeout, progress.File(), "archive-tar", progress.bump, "tar", tarArgs...); err != nil {
		fmt.Printf("Warning: archive backup failed: %v\n", err)
		// Drop the partial `.tmp` so it can't accumulate across failed runs
		// (a later run overwrites it anyway; this keeps the dir tidy now).
		os.Remove(tmpPath)
		return
	}

	// fsync the completed tar before the rename so the data is durable on
	// disk before the final name becomes visible. tar wrote via a subprocess,
	// so open the finished file read-only purely to flush it. Best-effort: a
	// fsync failure is logged but does not abort the rename (the tar succeeded;
	// the rename is still atomic on the same filesystem).
	if f, err := os.Open(tmpPath); err == nil {
		if syncErr := f.Sync(); syncErr != nil {
			fmt.Printf("Warning: fsync of archive %s failed (proceeding): %v\n", tmpPath, syncErr)
		}
		f.Close()
	}

	// Atomic publish: rename .tmp → final. Same-directory rename is atomic on
	// a single filesystem, so a reader sees either the old final (if any) or
	// the complete new one — never a partial.
	if err := os.Rename(tmpPath, archivePath); err != nil {
		fmt.Printf("Warning: could not finalize archive %s → %s: %v\n", tmpPath, archivePath, err)
		os.Remove(tmpPath)
		return
	}

	// fsync the directory so the rename itself is durable (cheap — one dir
	// entry). Best-effort; a crash before this only risks the rename being
	// lost, leaving the prior state — still consistent, never a partial.
	if dir, err := os.Open(archiveDir); err == nil {
		dir.Sync() //nolint:errcheck
		dir.Close()
	}

	// Prune old archives (keep last 3). pruneArchives filters ext == .gz, so
	// any leftover `.tmp` from a concurrent/failed run is ignored here.
	d.pruneArchives(archiveDir, 3)
}

func (d *Service) pruneArchives(dir string, keep int) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}

	var archives []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		// Sweep stale ATOMIC `.tmp` archives: a tar that was KILLED mid-write
		// (SIGTERM/SIGKILL) couldn't run archiveBackup's own os.Remove(tmpPath)
		// cleanup, so a `<version>-pre.tar.gz.tmp` can survive. A same-version
		// retry overwrites it, but a different-version killed run leaves a
		// distinct orphan that pruneArchives would otherwise never touch (it
		// filters ext == .gz). Reap them here so they can't accumulate across
		// killed upgrades. Match our exact suffix to avoid touching anything
		// else a user might have parked in the dir.
		if strings.HasSuffix(name, "-pre.tar.gz.tmp") {
			os.Remove(filepath.Join(dir, name))
			continue
		}
		if filepath.Ext(name) == ".gz" {
			archives = append(archives, filepath.Join(dir, name))
		}
	}

	if len(archives) <= keep {
		return
	}

	// Sort so oldest (lexicographically first) are at front
	sort.Strings(archives)
	// Remove oldest
	for _, f := range archives[:len(archives)-keep] {
		os.Remove(f)
	}
}

func (d *Service) waitForDBHealth(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		out, err := runCommandOutput(d.projDir, "docker", "compose", "exec", "db",
			"pg_isready", "-U", "postgres")
		if err == nil {
			return nil
		}
		if d.verbose {
			fmt.Printf("DB not ready: %s\n", out)
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("database did not become healthy within %s", timeout)
}

// EnsureDBUp guarantees the db container is running and healthy. Idempotent
// when the DB is already up (`docker compose up -d db` is a no-op in that
// case). Used by Service.Run() at daemon startup, where the DB may be
// intentionally stopped (post-swap intermediate state set up by
// applyPostSwap step 2 for the consistent backup, cleared by step 9 on
// the new binary). The post-swap restart of the daemon comes back as the
// IN-FLIGHT TARGET binary (exit-42 handoff), so this docker compose up uses
// the in-flight target's compose template — pulling the in-flight target's
// image, which is consistent with the flag's recovery target.
//
// NOT used by install.runCrashRecovery (operator-driven recovery): the
// operator's `./sb install` invokes a binary whose compose template may
// have a different image-tag scheme than what's actually running. A
// docker compose up there would silently swap the DB container to the
// operator's binary's image, destroying resumePostSwap's
// containersAtFlagTarget self-heal precondition. That caller uses
// EnsureDBReachable below.
func (d *Service) EnsureDBUp(ctx context.Context) error {
	if out, err := runCommandOutput(d.projDir, "docker", "compose", "up", "-d", "db"); err != nil {
		return fmt.Errorf("docker compose up -d db: %w (%s)", err, strings.TrimSpace(out))
	}
	if err := d.waitForDBHealth(60 * time.Second); err != nil {
		return fmt.Errorf("db did not become healthy after compose up: %w", err)
	}
	return nil
}

// StartDBForRecovery tries to start the EXISTING db container (without
// recreating it) and waits for it to become healthy. Used by
// install.runCrashRecovery before falling back to EnsureDBReachable's
// refusal — when the prior in-flight upgrade legitimately stopped the DB
// container (preswap backup window: rsync from the named volume requires
// pg to be stopped; post-swap intermediate state before the new binary
// brings it back), the crash leaves a stopped-but-present container that
// recovery must restart to continue.
//
// `docker compose start db` ONLY starts an existing stopped container; it
// NEVER recreates the container with the current binary's compose-template
// image tag. That's the critical asymmetry with `docker compose up -d db`
// (which IS forbidden here per the rc.66 → rc.67 lesson): up -d would
// silently recreate the container against the operator's binary's image,
// destroying resumePostSwap's containersAtFlagTarget self-heal precondition.
// `start` preserves the in-flight upgrade's container exactly as it was —
// we're just resuming a paused execution, not redeploying.
//
// If the container has been REMOVED (not just stopped), `docker compose
// start db` errors with "no such service" — fall through to the caller's
// refusal-with-diagnostic path. That's a category-3 divergence the
// operator must investigate manually.
//
// Returns nil on success (container started + DB healthy) or a wrapped
// error describing the failure mode (gone, start failed, health timeout).
func (d *Service) StartDBForRecovery(ctx context.Context) error {
	if out, err := runCommandOutput(d.projDir, "docker", "compose", "start", "db"); err != nil {
		return fmt.Errorf("docker compose start db: %w (%s)", err, strings.TrimSpace(out))
	}
	if err := d.waitForDBHealth(60 * time.Second); err != nil {
		return fmt.Errorf("db did not become healthy after compose start: %w", err)
	}
	return nil
}

// EnsureDBReachable verifies the DB is reachable via the .env-configured
// connection. Connect-only — no docker compose up, no image pull. Used by
// operator-driven crash recovery where touching the container set with the
// operator's binary's compose template would partially-swap the in-flight
// upgrade's containers and break resumePostSwap's containersAtFlagTarget
// self-heal (the rc.66 → rc.67 lesson learned from jo's failed deploy).
//
// Returns a category-3 error per the recovery trifecta when the DB isn't
// reachable: the prior in-flight upgrade's containers must still be
// running for recovery to proceed safely. If they aren't, fail loudly so
// the operator can investigate, not silently bring up containers using a
// possibly-mismatched compose template.
func (d *Service) EnsureDBReachable(ctx context.Context) error {
	psqlPath, prefix, env, err := migrate.PsqlCommand(d.projDir)
	if err != nil {
		return fmt.Errorf("EnsureDBReachable: resolve psql command: %w", err)
	}
	args := append(append([]string{}, prefix...),
		"-v", "ON_ERROR_STOP=on",
		"-X", "-A", "-t",
		"-c", "SELECT 1")

	timedCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(timedCtx, psqlPath, args...)
	cmd.Dir = d.projDir
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf(
			"DB not reachable for crash recovery: %w\n"+
				"  output: %s\n"+
				"  Containers from the prior in-flight upgrade must be running for recovery to proceed safely.\n"+
				"  Investigate `docker compose ps` and the upgrade-progress log; do not blindly `docker compose up -d` (the\n"+
				"  current binary's compose template may have a different image-tag scheme than what's actually running).",
			err, strings.TrimSpace(string(out)))
	}
	if strings.TrimSpace(string(out)) != "1" {
		return fmt.Errorf("DB not reachable for crash recovery: SELECT 1 returned %q", strings.TrimSpace(string(out)))
	}
	return nil
}

// healthURL returns the cached health check URL, loading REST_BIND_ADDRESS
// from .env on first call and probing PostgREST directly on its host-side
// loopback bind (typically 127.0.0.1:<port>). Bypasses Caddy entirely.
//
// Why direct probe, not through Caddy:
//
//	An earlier version of this code built the URL as
//	http://localhost:<CADDY_HTTP_PORT>/rest/rpc/auth_status — relying on
//	Caddy to strip /rest and forward to the rest container. That failed
//	on standalone deploys with a confusing TLS error: Caddy's :80 listener
//	has no site block matching Host=localhost, so the default-match
//	fallback was `http://<domain> { redir https://{host}{uri} permanent }`.
//	Caddy returned 301 → https://localhost{uri} → Go's client followed the
//	redirect → TLS handshake to localhost:443 → "remote error: tls:
//	internal error" because Caddy has no cert for SNI=localhost. Private
//	mode passed this check by accident: its fallback block was a full
//	site handler, not a redirect.
//
// Coverage trade-off: direct probe exercises postgrest → postgres. It
// does NOT exercise Caddy's reverse-proxy, header rewrites, or container
// networking. That's acceptable because (a) Caddy misconfiguration fails
// loudly on real user traffic, (b) what the health check uniquely catches
// is migration / PostgREST / DB damage — exactly what can force a
// rollback.
//
// auth_status is anonymous-safe (returns 200 with is_authenticated=false
// without a JWT) and reads auth.user, so it touches both PostgREST and
// the DB — the two things an upgrade's migrate step can break.
//
// Fails fast with an actionable error if REST_BIND_ADDRESS is missing or
// empty — silent fallback to a guess would re-hide the class of config
// drift this function is supposed to surface.
func (d *Service) healthURL() (string, error) {
	if d.cachedURL != "" {
		return d.cachedURL, nil
	}
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return "", fmt.Errorf(
			"health check: cannot read %s to resolve REST_BIND_ADDRESS: %w\n"+
				"Fix: run `./sb config generate` to regenerate .env from .env.config, "+
				"or verify the file exists and is readable.",
			envPath, err)
	}
	bind, ok := f.Get("REST_BIND_ADDRESS")
	bind = strings.TrimSpace(bind)
	if !ok || bind == "" {
		return "", fmt.Errorf(
			"health check: REST_BIND_ADDRESS is not set in %s.\n"+
				"Fix: run `./sb config generate` to regenerate .env from .env.config, "+
				"or check that REST_BIND_ADDRESS=<host>:<port> is populated in your .env file.",
			envPath)
	}
	d.cachedURL = fmt.Sprintf("http://%s/rpc/auth_status", bind)
	return d.cachedURL, nil
}

// healthCheck POSTs {} to the auth_status RPC and retries on 5xx /
// transport errors. Each failed attempt is logged via progress with
// the actionable detail (status + body excerpt for 5xx, transport
// error class otherwise) so a triage reader of the per-upgrade log
// can identify the failure mode without grepping container logs.
//
// progress may be nil — falls back to stderr so the older verbose
// path keeps working for ad-hoc invocations.
func (d *Service) healthCheck(progress *ProgressLog, retries int, interval time.Duration) error {
	healthURL, err := d.healthURL()
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 10 * time.Second}

	logf := func(format string, args ...interface{}) {
		if progress != nil {
			progress.Write(format, args...)
		} else {
			fmt.Printf(format+"\n", args...)
		}
	}

	var lastDetail string
	for i := 0; i < retries; i++ {
		// POST {} matches what the frontend sends — PostgREST RPCs are
		// invoked via POST with a JSON body.
		resp, err := client.Post(healthURL, "application/json", strings.NewReader("{}"))
		switch {
		case err != nil:
			lastDetail = fmt.Sprintf("transport error: %v", err)
		case resp.StatusCode < 500:
			resp.Body.Close()
			if i > 0 {
				logf("Health check OK on attempt %d/%d (status=%d)", i+1, retries, resp.StatusCode)
			}
			return nil
		default:
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
			resp.Body.Close()
			lastDetail = fmt.Sprintf("status=%d body=%q", resp.StatusCode, strings.TrimSpace(string(body)))
		}
		logf("Health check attempt %d/%d failed: %s (url=%s)", i+1, retries, lastDetail, healthURL)
		time.Sleep(interval)
	}
	return fmt.Errorf("health check failed after %d attempts; last: %s", retries, lastDetail)
}

// reconcileBackupDir audits the backup directory against public.upgrade rows.
// Called on every ticker tick while not upgrading.
//
// Algorithm (matches partner design):
//  1. Load all non-NULL backup_path values from public.upgrade.
//  2. Build an on-disk map of all pre-upgrade-* dirs (including .tmp —
//     a referenced .tmp is a live mid-rsync backup and must survive).
//  3. For each DB-referenced path: consume from the on-disk map (silent),
//     or log BACKUP_MISSING if absent.
//  4. Remaining on-disk entries have no DB row → orphans.
//     Grace < 90 days: BACKUP_ORPHAN (loud, no action).
//     Grace ≥ 90 days: BACKUP_ORPHAN_PURGED (purge) or BACKUP_ORPHAN_PURGE_FAILED.
//
// BACKUP_MISSING is advisory only — the column value is forensic evidence;
// do NOT auto-NULL it.
//
// Greppable stable log tokens (parallel to the Err* taxonomy):
//
//	BACKUP_MISSING           — DB row references missing path (loud)
//	BACKUP_ORPHAN            — unreferenced dir, within 90-day grace (loud)
//	BACKUP_ORPHAN_PURGED     — unreferenced dir, past grace, deleted (loud)
//	BACKUP_ORPHAN_PURGE_FAILED — deletion failed; retried next tick (loud)
//	BACKUP_RECONCILE_SKIP    — tick aborted (query or readdir failed)
//	BACKUP_RECONCILE_DEBUG   — per-entry noise demoted to verbose
func (d *Service) reconcileBackupDir(ctx context.Context) {
	if err := d.ensureConnected(ctx); err != nil {
		fmt.Printf("BACKUP_RECONCILE_SKIP: cannot connect to DB: %v\n", err)
		return
	}

	// --- 1. Load DB-referenced paths ---
	rows, err := d.queryConn.Query(ctx,
		"SELECT id, backup_path FROM public.upgrade WHERE backup_path IS NOT NULL")
	if err != nil {
		fmt.Printf("BACKUP_RECONCILE_SKIP: query failed: %v\n", err)
		return
	}
	defer rows.Close()

	referenced := make(map[string]int) // abs path → upgrade id
	for rows.Next() {
		var id int
		var path string
		if err := rows.Scan(&id, &path); err != nil {
			continue
		}
		referenced[path] = id
	}
	if err := rows.Err(); err != nil {
		fmt.Printf("BACKUP_RECONCILE_SKIP: row scan error: %v\n", err)
		return
	}

	// --- 2-4. Classify + purge orphans (DB-free core, unit-testable). ---
	d.purgeOrphanBackups(referenced, time.Now())
}

// purgeOrphanBackups is the DB-free orphan pass of reconcileBackupDir, split out
// so it is unit-testable without a live connection. It enumerates legacy
// pre-upgrade-<stamp>(.tmp) dirs, consumes the DB-referenced ones, and for the
// rest applies the differential-grace orphan policy. `referenced` maps abs
// backup_path → upgrade id; `now` is injected for deterministic tests.
//
// The two CHANGE-2 MANAGED dirs (backupActiveName / backupSyncingName) are
// EXCLUDED entirely — they are governed by the backup rename state machine, not
// reference-counted, so they must never be classified as orphans or purged
// (purging a stale-mtime syncing would destroy a killed run's incremental base
// or a live partial). Only legacy per-stamp dirs flow through here, for graceful
// post-migration cleanup.
func (d *Service) purgeOrphanBackups(referenced map[string]int, now time.Time) {
	root := d.backupRoot()
	entries, err := os.ReadDir(root)
	if err != nil {
		if !os.IsNotExist(err) {
			fmt.Printf("BACKUP_RECONCILE_SKIP: readdir %s: %v\n", root, err)
		}
		return
	}

	type diskInfo struct{ mtime time.Time }
	onDisk := make(map[string]diskInfo)
	for _, e := range entries {
		if !e.IsDir() || !strings.HasPrefix(e.Name(), "pre-upgrade-") {
			continue
		}
		if isManagedBackupDir(e.Name()) {
			continue // managed by the rename state machine — never an orphan
		}
		info, infoErr := e.Info()
		if infoErr != nil {
			// Race: dir disappeared between ReadDir and Info().
			if d.verbose {
				fmt.Printf("BACKUP_RECONCILE_DEBUG: stat %s: %v\n", e.Name(), infoErr)
			}
			continue
		}
		onDisk[filepath.Join(root, e.Name())] = diskInfo{mtime: info.ModTime()}
	}

	// Check each referenced path; consume from onDisk map.
	for path, id := range referenced {
		if _, ok := onDisk[path]; ok {
			delete(onDisk, path) // matched — not an orphan
			continue
		}
		fmt.Printf("BACKUP_MISSING: upgrade id=%d backup_path=%s not found on disk\n", id, path)
	}

	// Remaining entries are orphans (no DB row references them).
	// Differential grace:
	//   .tmp  — 10 minutes (crash artifact; rsync never completed, low recovery value)
	//   final — 90 days   (may hold genuine recovery value; allow manual rescue)
	const tmpGrace = 10 * time.Minute
	const finalisedGrace = 90 * 24 * time.Hour
	for path, di := range onDisk {
		isTmp := strings.HasSuffix(path, ".tmp")
		grace := finalisedGrace
		if isTmp {
			grace = tmpGrace
		}
		age := now.Sub(di.mtime)
		if di.mtime.Before(now.Add(-grace)) {
			if err := os.RemoveAll(path); err != nil {
				fmt.Printf("BACKUP_ORPHAN_PURGE_FAILED: %s age=%s: %v\n",
					path, age.Truncate(time.Minute), err)
			} else {
				fmt.Printf("BACKUP_ORPHAN_PURGED: %s age=%s exceeded grace (%s)\n",
					path, age.Truncate(time.Minute), grace)
			}
		} else {
			graceUntil := di.mtime.Add(grace).Format(time.RFC3339)
			fmt.Printf("BACKUP_ORPHAN: %s unreferenced, age=%s (grace until %s)\n",
				path, age.Truncate(time.Minute), graceUntil)
		}
	}
}
