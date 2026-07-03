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
// Called at the TAIL of applyPostSwap — AFTER the terminal state='completed'
// UPDATE and removeUpgradeFlag (rune-stuck-fix A; service.go). By the time this
// child runs, the upgrade flag is already GONE and the upgrade is COMPLETE, not
// active. It sets --post-upgrade-fixup and STATBUS_POST_UPGRADE_FIXUP=1 to tell
// the child install: (1) bypass the install↔upgrade mutex — do not acquire it,
// and do not expect a flag on disk; (2) skip state detection, row-authoring, and
// install-log creation (this is a nested fixup, not a fresh install). The env
// var is also the signature acquireOrBypass uses to recognize the expected
// flag-absent state and stay quiet — see install.go:acquireOrBypass. (A bare
// hand-passed --post-upgrade-fixup, lacking this env var, is audited as A17.)
//
// This function is the ONE legitimate caller that sets these signals; no other
// caller in the codebase should ever set them.
func runInstallFixup(projDir string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx,
		filepath.Join(projDir, "sb"),
		"install", "--non-interactive", "--post-upgrade-fixup",
	)
	cmd.Dir = projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "STATBUS_POST_UPGRADE_FIXUP=1")
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
	err := runCommandToLogCtx(ctx, dir, logWriter, source, onAdvance, name, args...)
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("%s %v after %s: %w", name, args, timeout, ErrCommandTimeout)
	}
	return err
}

// tailBuffer keeps only the last `max` bytes written — a BOUNDED stderr capture
// for structured error-marker classification (STATBUS-046 slice 2, docker ENOSPC
// backstop). Small cap: the markers we classify on (kernel strerror lines) are
// short and appear at the END of a failing step's stderr. Never grows unbounded.
type tailBuffer struct {
	max int
	buf []byte
}

func (t *tailBuffer) Write(p []byte) (int, error) {
	t.buf = append(t.buf, p...)
	if len(t.buf) > t.max {
		t.buf = t.buf[len(t.buf)-t.max:]
	}
	return len(p), nil
}

func (t *tailBuffer) String() string { return string(t.buf) }

// runCommandToLogCapture is runCommandToLog PLUS a bounded stderr TAIL capture,
// returned alongside the error for structured marker classification (the docker
// ENOSPC backstop — runCommandToLog itself discards stderr text, returning only
// the exec.ExitError whose .Stderr is empty under cmd.Run). Identical streaming /
// stall-heartbeat behaviour: the tail buffer is just teed into the existing
// stderr MultiWriter, so the log + os.Stderr + onAdvance feed are unchanged.
func runCommandToLogCapture(dir string, timeout time.Duration, logWriter io.Writer, source string, onAdvance func(), name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	tail := &tailBuffer{max: 4096}
	cmd := exec.CommandContext(ctx, name, gitArgs(name, args)...)
	cmd.Dir = dir
	outW := NewPrefixWriter("O", source, logWriter, onAdvance)
	errW := NewPrefixWriter("E", source, logWriter, onAdvance)
	cmd.Stdout = io.MultiWriter(os.Stdout, outW)
	cmd.Stderr = io.MultiWriter(os.Stderr, errW, tail)
	prepareCmd(cmd)
	err := cmd.Run()
	outW.Flush()
	errW.Flush()
	if ctx.Err() == context.DeadlineExceeded {
		return tail.String(), fmt.Errorf("%s %v after %s: %w", name, args, timeout, ErrCommandTimeout)
	}
	return tail.String(), err
}

// runCommandToLogCtx is runCommandToLog with the cancellation context supplied
// by the CALLER instead of a self-built WithTimeout — so a caller can drive
// cancellation from a stall watchdog (no progress for N seconds) rather than a
// wall-clock deadline that would cancel a healthy slow transfer (STATBUS-109,
// doc-022 §3: "a deadline cancels a healthy slow transfer" is forbidden). The
// timeout wrapper above preserves the existing deadline behaviour + the
// ErrCommandTimeout mapping for every other caller. onAdvance still fires per
// output line (via NewPrefixWriter) — the stall detector uses it as its
// progress feed AND its systemd-heartbeat pump.
func runCommandToLogCtx(ctx context.Context, dir string, logWriter io.Writer, source string, onAdvance func(), name string, args ...string) error {
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

// pullImagesForCommitShort pre-pulls the full image set for a SPECIFIC version,
// selected by its commit-short Docker tag. The compose image tag is
// ${COMMIT_SHORT} (config.go) — NOT ${VERSION} — so the version to fetch is
// chosen by overriding COMMIT_SHORT (the same 8-char tag verifyArtifacts probes,
// = ShortForDisplay(commit_sha)). The previous form set only VERSION, which
// feeds build-args / display env and never the image tag, so it silently
// re-pulled whatever COMMIT_SHORT was already in .env — the currently-installed
// images — regardless of the intended target (STATBUS-047 item A / A3).
//
// --profile all is MANDATORY: every service here is profile-gated and
// COMPOSE_PROFILES is never set, so a bare `docker compose pull` selects zero
// services and pulls nothing. --quiet suppresses progress bars that cause
// excessive pipe output under systemd. 10-minute timeout: registry pulls can be
// slow on shared servers. VERSION is left to .env (display/build-arg only; it
// does not affect which image tag is pulled).
func (d *Service) pullImagesForCommitShort(commitShort string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", "compose", "--profile", "all", "pull", "--quiet")
	cmd.Dir = d.projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "COMMIT_SHORT="+commitShort)
	prepareCmd(cmd)
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("docker compose pull timed out after 10 minutes")
	}
	return err
}

// Maintenance flag-file path convention (STATBUS-089). The upgrade service
// writes a flag file on the HOST; the proxy container reads it through a bind
// mount; Caddy's @maintenance matcher checks it. ALL THREE MUST AGREE:
//
//	host write:     $HOME/statbus-maintenance/active
//	bind mount:     $HOME/statbus-maintenance → /statbus-maintenance  (caddy/docker-compose.yml)
//	Caddy matcher:  file /statbus-maintenance/active                  (caddy/templates/*.caddyfile.tmpl)
//
// TestMaintenancePathAlignment pins this agreement so a future edit cannot
// silently re-split it (the 2026-04-14 regression this fixes: the writer wrote
// ~/maintenance — OUTSIDE the mounted dir — so the matcher never fired and
// maintenance mode was dead on every standalone+private box since then).
const (
	maintenanceFlagDir     = "statbus-maintenance"  // host dir under $HOME, bind-mounted to maintenanceMountTarget
	maintenanceFlagName    = "active"               // flag file inside it
	maintenanceMountTarget = "/statbus-maintenance" // in-container mount point
)

// maintenanceFlagHostPath is the host path the upgrade service writes/removes
// ($HOME/statbus-maintenance/active).
func maintenanceFlagHostPath() string {
	return filepath.Join(os.Getenv("HOME"), maintenanceFlagDir, maintenanceFlagName)
}

// maintenanceFlagContainerPath is the absolute in-container path Caddy's
// @maintenance matcher checks (/statbus-maintenance/active).
func maintenanceFlagContainerPath() string {
	return maintenanceMountTarget + "/" + maintenanceFlagName
}

func (d *Service) setMaintenance(active bool) {
	// The flag file lives under $HOME/statbus-maintenance/ — the host directory
	// bind-mounted into the proxy container at /statbus-maintenance. Caddy's
	// @maintenance matcher checks `file /statbus-maintenance/active`; when this
	// file exists the proxy serves maintenance.html with 503 for all requests.
	// Writer ↔ template ↔ mount must agree — see the convention above.
	file := maintenanceFlagHostPath()

	if active {
		_, statErr := os.Stat(file)
		// Ensure the bind-mounted dir exists before writing the flag into it
		// (install.go creates it; defensive for older boxes / a fresh mount).
		if mkErr := os.MkdirAll(filepath.Dir(file), 0o755); mkErr != nil {
			fmt.Printf("maintenance ON — failed to create dir %s: %v\n", filepath.Dir(file), mkErr)
		}
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

// quoteIdent double-quotes a SQL identifier (doubling any embedded quote) so it
// can be interpolated into DDL that cannot be parameterized (ALTER DATABASE).
func quoteIdent(id string) string {
	return `"` + strings.ReplaceAll(id, `"`, `""`) + `"`
}

// setDatabaseReadOnly toggles the app database's default_transaction_read_only
// via ALTER DATABASE — the STATBUS-110 read-only upgrade window, the accident-
// guard that makes phase-3 external writes fail so a rollback can lose nothing
// (see doc/read-only-upgrade-window.md). It is the SQL sibling of setMaintenance;
// unlike that filesystem-flag toggle it runs a catalog statement, so it needs a
// live query connection.
//
//   - ON is set in executeUpgrade BEFORE the DB stop, while queryConn is live, so
//     the ALTER persists in the catalog and survives the stop → every phase-3
//     reconnecting session inherits read-only (and a crash mid-window leaves the
//     DB frozen read-only = crash-freeze).
//   - OFF (idempotent) is co-located with each maintenance-OFF terminal.
//
// The upgrade's OWN writers are exempt by a SEPARATE, ADDITIVE mechanism and are
// NOT blocked: the Service's pgx sessions self-exempt in connect() (`SET
// default_transaction_read_only = off`, covering the state='completed' UPDATE and
// flag/recovery writes), and the `./sb migrate up` SUBPROCESS self-exempts via
// migrate.psqlEnv's PGOPTIONS (covering post-swap, boot-migrate, forward-recovery).
// This guard blocks only EXTERNAL sessions.
//
// Best-effort accident-guard (not a hard lock): it logs and returns any error so
// callers log-not-raise without aborting the upgrade. A nil queryConn (a one-shot
// path that never connected) is a no-op. Because this session is itself exempted
// in connect(), the ALTER runs even while the DB default is already on — which is
// exactly what the OFF direction needs.
func (d *Service) setDatabaseReadOnly(ctx context.Context, readOnly bool) error {
	if d.queryConn == nil {
		fmt.Printf("read-only window: no query connection — skipping ALTER DATABASE (readOnly=%v)\n", readOnly)
		return nil
	}
	var dbName string
	if err := d.queryConn.QueryRow(ctx, "SELECT current_database()").Scan(&dbName); err != nil {
		fmt.Printf("read-only window: could not resolve current_database(): %v\n", err)
		return err
	}
	val := "off"
	if readOnly {
		val = "on"
	}
	stmt := fmt.Sprintf("ALTER DATABASE %s SET default_transaction_read_only = %s", quoteIdent(dbName), val)
	if _, err := d.queryConn.Exec(ctx, stmt); err != nil {
		fmt.Printf("read-only window %s — ALTER DATABASE failed: %v\n", strings.ToUpper(val), err)
		return err
	}
	fmt.Printf("read-only window %s — %s\n", strings.ToUpper(val), stmt)
	return nil
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
// reconcile orphan pass.
func (d *Service) backupRoot() string {
	return filepath.Join(os.Getenv("HOME"), "statbus-backups")
}

// Managed backup dir names (CHANGE 2 / task #12). The persistent rsync snapshot
// is committed by atomic directory rename, where the dir NAME is the
// clean/dirty state:
//   - backupActiveName  — a COMPLETE, restorable snapshot (the incremental base
//     for the next backup, and the rollback source). Only a COMMITTED path is
//     ever recorded on the flag/row (updateFlagPostSwap runs after the
//     commit-rename), and restoreDatabase consumes ONLY that recorded path
//     (identity-keyed, STATBUS-039/-031).
//   - backupSyncingName — an IN-FLIGHT or killed-mid-rsync PARTIAL. Never
//     restorable; a killed run RESUMES by rsyncing into it (never deleted), and
//     only rename(syncing→active) publishes it. Never recorded as a backup
//     path, so it can never be a restore source.
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
		// INVARIANT (STATBUS-114): active→syncing MUST stay a RENAME — never
		// rm+mkdir, and never copy-then-delete. The rename moves the SAME
		// on-disk dir aside with its files' content AND mtimes intact, so the
		// next `rsync -a --delete` (step 2) reuses syncing as the incremental
		// base. That rsync is a LOCAL transfer → rsync defaults to --whole-file
		// (block-level delta OFF), so its ONLY speedup is the quick-check that
		// skips files whose size+mtime already match the source. Replace this
		// rename with delete+recreate (or any recopy that resets inode/mtime)
		// and the base is effectively empty every run → EVERY big-DB backup
		// full-copies the whole Postgres volume (minutes → hours on large
		// installs). The unit guard is TestPrepareSnapshot_ReusesBaseInodeNotRecopy.
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
// either active (complete) or syncing (partial, never recorded → never restorable).
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
		// run resumes into (NEVER deleted). Its path is never recorded on the
		// flag/row (only the post-commit active path is), so a partial cannot
		// be restored.
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
	// resumes by rsyncing into the leftover syncing, then commits. No backup
	// path was recorded by the killed run (updateFlagPostSwap never ran), so
	// the identity-keyed restore refuses to touch the volume — the partial
	// can never be a restore source.
	//
	// Placement rationale: in this exact spot the rsync has completed (so the
	// test exercises real I/O), but the rename is the next thing the parent
	// would do. No-op in production. Drives scenario 2-preswap-backup-kill.
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

// RestoreDBTimeout bounds the rollback DB-volume rsync restore. Raised from a
// site-local 10m to a shared 30m generous constant (the MigrateUpTimeout=30m
// philosophy): a Norway-scale (32 GB) restore can legitimately exceed 10m, and a
// false timeout would abort a HEALTHY rollback. rollback()'s always-ping watchdog
// cover (STATBUS-031) deliberately suppresses the 120s WatchdogSec false-kill of a
// slow-but-progressing restore, so THIS ceiling is the real bound on a HUNG rsync.
const RestoreDBTimeout = 30 * time.Minute

// restoreDatabase rsync-restores the DB volume from THIS upgrade's own
// snapshot — identity-keyed, never selected by recency (STATBUS-039 / -031,
// the transactional model: "a stale backup is another upgrade's backup —
// identity, not age"). Runs inside rollback()'s always-ping watchdog cover
// (STATBUS-031): the whole-volume rsync below is heartbeat-SILENT (onAdvance=nil,
// output to progress.File()), so without that cover a >120s restore trips
// WatchdogSec mid-restore.
//
// backupPath is the snapshot path the upgrade being recovered RECORDED for
// itself: flag.BackupPath (stamped by updateFlagPostSwap after the snapshot
// commit-rename) or the row's backup_path column. Selection by recency
// (the former pickLatestBackup) is forbidden here: during the aside-rename
// window of every backup the active dir is absent, and a recency scan would
// fall back to a LEGACY pre-upgrade-<stamp> dir from an OLDER upgrade —
// rsync --delete'ing a months-old state over the live volume. That path
// completed silently under ./sb install (no watchdog) before this change.
//
// Dispositions:
//   - backupPath == "": this upgrade never finalised a snapshot (PreSwap
//     kill — the volume was never mutated, the partial lives in the syncing
//     dir). NOTHING to restore; refuse to touch the volume; return nil so
//     the caller records `rolled_back` (box healthy, DB untouched).
//   - backupPath missing on disk: the upgrade DID record a snapshot and it
//     is gone (pruned mid-flight, manual deletion). Restoring any OTHER
//     backup would be another upgrade's state — fail LOUD with a non-nil
//     error so the caller records `failed` (degraded), never a silent
//     wrong-restore.
//   - backupPath present: rsync-restore it. A non-nil error means the rsync
//     was attempted and FAILED: the volume is left inconsistent, so the
//     caller must record `failed` (degraded), not `rolled_back`.
func (d *Service) restoreDatabase(progress *ProgressLog, backupPath string) error {
	if backupPath == "" {
		progress.Write("No snapshot was recorded by this upgrade — refusing to touch the live volume (nothing to restore; the DB was never mutated).")
		return nil
	}
	if info, statErr := os.Stat(backupPath); statErr != nil || !info.IsDir() {
		progress.Write("%s: this upgrade's recorded snapshot %s is missing on disk (stat: %v) — REFUSING to restore any other backup (identity-keyed restore).",
			ErrRollbackDBRestore, backupPath, statErr)
		return fmt.Errorf("%s: recorded snapshot %s missing on disk: %v",
			ErrRollbackDBRestore, backupPath, statErr)
	}
	backupDir := backupPath
	volumeName := d.dbVolumeName()

	progress.Write("Restoring database from backup at %s...", backupDir)

	// Harness-only stall site (STATBUS-031 RED proof): parks the restore here,
	// SILENT (no progress.Write, no WATCHDOG=1 from this goroutine), simulating a
	// slow Norway-scale rsync. On UNFIXED code (no ticker wrapping rollback()) the
	// silence exceeds WatchdogSec → SIGABRT mid-restore (the RED). With the
	// STATBUS-031 always-ping ticker, the cover keeps WATCHDOG=1 firing through the
	// stall (the GREEN). Released by removing STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE.
	// No-op in production. Drives scenario 4-rollback-restore-watchdog.
	inject.StallHere("restore-db-stall-watchdog")

	if err := runCommandToLog(d.projDir, RestoreDBTimeout, progress.File(), "rsync", nil,
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
// function now only reaps leftover per-stamp dirs during the migration window.
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

// PostSwapDBHealthTimeout is the class-A readiness allowance for the post-swap
// db-up step (STATBUS-046 slice 3, doc-021 3.3). SIZE-SCALED-INTENT: after an
// unclean stop, PostgreSQL replays the WAL before it accepts connections, and on
// a Norway-sized volume that can legitimately take minutes — a 30s wait would
// mis-classify a healthy-but-replaying DB as a failure and burn a death. Mirrors
// the generous-fixed-budget doctrine of MigrateUpTimeout (30m) rather than a
// per-volume formula (there is no such formula today). This is an IN-PLACE class-A
// wait; it never consumes a death. Honest default, arc-reconcilable/tunable.
const PostSwapDBHealthTimeout = 5 * time.Minute

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

// readyURL resolves the PostgREST admin server's /ready endpoint from
// REST_ADMIN_BIND_ADDRESS in .env. The admin server binds loopback-only
// (127.0.0.1:<slot offset+6>) and is never publicly routed; /ready returns
// 200 only once BOTH the connection pool AND the schema cache are loaded —
// the exact signal the post-swap warmup waits for before the functional RPC
// probe runs.
//
// Fails fast with an actionable error if REST_ADMIN_BIND_ADDRESS is missing
// or empty. There is deliberately no fallback to a guessed address or to
// skipping the warmup: a silent fallback would re-hide the config-drift class
// (a dropped admin mapping) that the readiness signal exists to surface.
func (d *Service) readyURL() (string, error) {
	if d.cachedReadyURL != "" {
		return d.cachedReadyURL, nil
	}
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return "", fmt.Errorf(
			"readiness check: cannot read %s to resolve REST_ADMIN_BIND_ADDRESS: %w\n"+
				"Fix: run `./sb config generate` to regenerate .env from .env.config, "+
				"or verify the file exists and is readable.",
			envPath, err)
	}
	bind, ok := f.Get("REST_ADMIN_BIND_ADDRESS")
	bind = strings.TrimSpace(bind)
	if !ok || bind == "" {
		return "", fmt.Errorf(
			"readiness check: REST_ADMIN_BIND_ADDRESS is not set in %s.\n"+
				"Fix: run `./sb config generate` to regenerate .env from .env.config so the "+
				"PostgREST admin server bind address (127.0.0.1:<port>) is populated.",
			envPath)
	}
	d.cachedReadyURL = fmt.Sprintf("http://%s/ready", bind)
	return d.cachedReadyURL, nil
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
	// WARMUP: wait for PostgREST's admin /ready=200 BEFORE the functional RPC
	// probe. The probe fires immediately after the post-swap container restart,
	// while PostgREST is still loading its schema cache → attempt 1 would always
	// fail 503 PGRST002, and on a large schema (Norway-scale) the cold-cache
	// window can outlast the whole fixed RPC retry budget → a false health-fail
	// → rollback. Gating on the real readiness signal removes that race entirely;
	// see waitForRestReady. No PGRST002 fallback follows: after /ready=200 the
	// cold-cache race cannot occur.
	if err := d.waitForRestReady(progress, RestReadyPollInterval, restReadyProgressInterval, RestReadyTimeout); err != nil {
		return err
	}

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

// RestReadyTimeout caps how long the post-swap warmup waits for PostgREST to
// report /ready=200 (connection pool + schema cache loaded). Generous-budget
// doctrine: schema-cache load scales with schema size, so a fixed retry budget
// would false-fail on a large schema (Norway). The wait can't itself trip the
// unit's watchdog because the loop narrates progress on restReadyProgressInterval
// (well under applyPostSwapStallThreshold = 3m), and every progress line pings
// sd_notify WATCHDOG=1 + bumps the progress gate (progress.Write).
const RestReadyTimeout = 5 * time.Minute

// RestReadyPollInterval is how often the warmup polls the admin /ready endpoint.
const RestReadyPollInterval = 2 * time.Second

// restReadyProgressInterval is how often the warmup emits a progress line while
// still waiting. MUST stay comfortably below applyPostSwapStallThreshold (3m)
// so a long-but-live cache load keeps feeding the progress-gated watchdog.
const restReadyProgressInterval = 15 * time.Second

// waitForRestReady polls the PostgREST admin /ready endpoint until it returns
// 200 — the signal that BOTH the connection pool and the schema cache are
// loaded. It is the first thing healthCheck does after a post-swap restart.
//
// Both 503 (process up, cache not loaded yet) and connection-refused / transport
// errors (process not accepting yet) take the SAME path: keep waiting until 200
// or until timeout. The loop emits a progress line every progressInterval — this
// is load-bearing, not cosmetic: each progress.Write pings sd_notify WATCHDOG=1
// and bumps applyPostSwap's progress gate, so a multi-minute cache load cannot
// close the gate and get the unit SIGABRTed.
//
// On timeout the returned error distinguishes the two failure modes by whether
// the admin server was ever reachable:
//   - never connected (always refused) → config drift: the admin mapping is
//     missing — run ./sb config generate.
//   - connected but always 503 → the schema cache never finished loading —
//     inspect docker compose logs rest.
//
// There is deliberately NO fallback that proceeds anyway on timeout: after
// /ready=200 the cold-cache race cannot occur, and a silent fallback would mask
// a future loss of the readiness signal (e.g. a compose refactor that drops the
// admin mapping) — exactly the vacuous-green class we must fail loudly on.
func (d *Service) waitForRestReady(progress *ProgressLog, pollInterval, progressInterval, timeout time.Duration) error {
	readyURL, err := d.readyURL()
	if err != nil {
		return err
	}

	logf := func(format string, args ...interface{}) {
		if progress != nil {
			progress.Write(format, args...)
		} else {
			fmt.Printf(format+"\n", args...)
		}
	}

	// Per-poll client timeout is independent of pollInterval: a single GET
	// against a loopback admin server returns in milliseconds when up, and a
	// hung GET must not consume the whole budget in one attempt.
	client := &http.Client{Timeout: 10 * time.Second}

	start := time.Now()
	deadline := start.Add(timeout)
	lastProgressAt := start

	var (
		sawConnection bool
		lastDetail    string
		polls         int
	)

	logf("Waiting for PostgREST schema cache to load (admin /ready, up to %s)...", timeout)

	for {
		polls++
		resp, getErr := client.Get(readyURL)
		switch {
		case getErr == nil && resp.StatusCode == http.StatusOK:
			resp.Body.Close()
			logf("PostgREST is ready (admin /ready=200 after %s, %d poll(s))",
				time.Since(start).Round(time.Millisecond), polls)
			return nil
		case getErr != nil:
			lastDetail = fmt.Sprintf("connection error: %v", getErr)
		default:
			io.Copy(io.Discard, io.LimitReader(resp.Body, 1024))
			resp.Body.Close()
			sawConnection = true
			lastDetail = fmt.Sprintf("status=%d (schema cache still loading)", resp.StatusCode)
		}

		if now := time.Now(); now.After(deadline) {
			if sawConnection {
				return fmt.Errorf(
					"PostgREST schema cache never loaded — admin /ready did not return 200 within %s "+
						"(last: %s). Check `docker compose logs rest`; the cache load may be failing, or the "+
						"schema may be too large for the %s budget.",
					timeout, lastDetail, timeout)
			}
			return fmt.Errorf(
				"PostgREST admin server unreachable — /ready at %s never accepted a connection within %s "+
					"(last: %s). The admin mapping is likely missing from your config — run "+
					"`./sb config generate` to regenerate .env and recreate the rest container.",
				readyURL, timeout, lastDetail)
		} else if now.Sub(lastProgressAt) >= progressInterval {
			logf("Still waiting for PostgREST /ready (elapsed %s, last: %s)",
				time.Since(start).Round(time.Second), lastDetail)
			lastProgressAt = now
		}

		time.Sleep(pollInterval)
	}
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
