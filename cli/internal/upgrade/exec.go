package upgrade

import (
	"context"
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
		return fmt.Errorf("command timed out after %s: %s %v", timeout, name, args)
	}
	return err
}

// runCommandToLog executes a command like runCommandWithTimeout but also
// tees child stdout/stderr into logWriter using PrefixWriter so the
// per-upgrade log captures subprocess output alongside service narration.
// Raw output still flows to os.Stdout/Stderr for daemon journal capture.
func runCommandToLog(dir string, timeout time.Duration, logWriter io.Writer, source string, name string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, gitArgs(name, args)...)
	cmd.Dir = dir
	outW := NewPrefixWriter("O", source, logWriter)
	errW := NewPrefixWriter("E", source, logWriter)
	cmd.Stdout = io.MultiWriter(os.Stdout, outW)
	cmd.Stderr = io.MultiWriter(os.Stderr, errW)
	prepareCmd(cmd)
	err := cmd.Run()
	outW.Flush()
	errW.Flush()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("command timed out after %s: %s %v", timeout, name, args)
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

// backupRoot is the directory holding all pre-upgrade-* backup
// directories. Each backup is a separate timestamped directory inside.
func (d *Service) backupRoot() string {
	return filepath.Join(os.Getenv("HOME"), "statbus-backups")
}

// dirSize returns the aggregate byte count of a directory tree. Walk
// errors (e.g. a file removed mid-walk) are silently skipped — the
// returned size is informational, not authoritative. Only used for
// heartbeat log messages during rsync.
func dirSize(root string) int64 {
	var total int64
	_ = filepath.Walk(root, func(_ string, info os.FileInfo, err error) error {
		if err != nil || info == nil {
			return nil
		}
		if !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	return total
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

// backupDatabase rsyncs the live Postgres data volume into a fresh
// timestamped directory and atomically renames it on success.
//
// Atomicity matters because rsync --delete is not crash-safe: it
// removes destination files before copying replacements. A SIGKILL
// mid-rsync into a fixed path leaves the directory half-deleted /
// half-copied — silent corruption that the next rollback would happily
// rsync straight back into the live volume.
//
// Mechanism: write to pre-upgrade-<UTC>.tmp/. After rsync exits 0,
// rename to pre-upgrade-<UTC>/. rename(2) is atomic on POSIX for dirs
// on the same filesystem. Crash mid-rsync leaves only a .tmp
// directory; restoreDatabase / pickLatestBackup ignore those.
//
// stamp is the UTC timestamp string already written to public.upgrade.backup_path
// (as the .tmp path) by executeUpgrade before the DB connection was closed.
// Passing it here ensures the on-disk directory name matches the DB record.
func (d *Service) backupDatabase(progress *ProgressLog, stamp string) (string, error) {
	root := d.backupRoot()
	if err := os.MkdirAll(root, 0755); err != nil {
		return "", fmt.Errorf("create backup root: %w", err)
	}

	tmpDir := filepath.Join(root, "pre-upgrade-"+stamp+".tmp")
	finalDir := filepath.Join(root, "pre-upgrade-"+stamp)

	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return "", fmt.Errorf("create backup tmpdir: %w", err)
	}

	// rsync from named Docker volume into the .tmp dir via a lightweight
	// container. DB must be stopped before this point for a consistent
	// backup. No sudo needed — the container runs as root and can read
	// postgres-owned files.
	volumeName := d.dbVolumeName()

	// Heartbeat wrapper. Raw rsync stdout is streamed via progress.File()
	// (bypasses progress.Write, which is where the unified emitHeartbeat
	// lives — task #42). A large DB can keep rsync running for minutes,
	// which would silence the main goroutine for the duration and
	// tickle WatchdogSec=120. Emit a progress.Write every 30s so each
	// tick fires emitHeartbeat via the unified path.
	//
	// %s copied: walk the growing tmpDir and sum file sizes. Cheap on a
	// backup-shaped directory (dozens to thousands of files, all small
	// or PG data files); racy against concurrent rsync writes which is
	// fine — the number in the log line is informational.
	//
	// Same blind-spot trade-off as pullImages (task #42): the ticker
	// runs in a background goroutine, so a stuck main goroutine inside
	// runCommandToLog would still emit heartbeats. Bounded by the
	// 10-minute context timeout inside runCommandToLog.
	rsyncStart := time.Now()
	rsyncDone := make(chan struct{})
	rsyncTicker := time.NewTicker(30 * time.Second)
	go func() {
		defer rsyncTicker.Stop()
		for {
			select {
			case <-rsyncDone:
				return
			case <-rsyncTicker.C:
				copied := dirSize(tmpDir)
				progress.Write("Still backing up database (%s elapsed, %s copied)...",
					time.Since(rsyncStart).Truncate(time.Second),
					humanBytes(copied))
			}
		}
	}()
	rsyncErr := runCommandToLog(d.projDir, 10*time.Minute, progress.File(), "rsync",
		"docker", "run", "--rm",
		"-v", volumeName+":/source:ro",
		"-v", tmpDir+":/backup",
		"alpine", "sh", "-c", "apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /source/ /backup/",
	)
	close(rsyncDone)
	if rsyncErr != nil {
		// Leave the .tmp dir for inspection; pruneStaleTmpBackups will
		// clean it after 10 minutes if it's confirmed dead.
		return "", fmt.Errorf("rsync backup: %w", rsyncErr)
	}

	// Atomic completion marker: directory's final name appearing IS the
	// completion signal. No sentinel files, no symlinks.
	if err := os.Rename(tmpDir, finalDir); err != nil {
		return "", fmt.Errorf("finalise backup (rename %s -> %s): %w", tmpDir, finalDir, err)
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

	return finalDir, nil
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

// pickLatestBackup returns the path of the newest finalised
// pre-upgrade-* directory (no .tmp suffix), or "" if none exists.
// Timestamp prefix sorts lexicographically so sort.Strings + take-max
// works.
func (d *Service) pickLatestBackup() string {
	entries, err := os.ReadDir(d.backupRoot())
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
		if strings.HasSuffix(name, ".tmp") {
			continue
		}
		finalised = append(finalised, name)
	}
	if len(finalised) == 0 {
		return ""
	}
	sort.Strings(finalised)
	return filepath.Join(d.backupRoot(), finalised[len(finalised)-1])
}

func (d *Service) restoreDatabase(progress *ProgressLog) {
	backupDir := d.pickLatestBackup()
	if backupDir == "" {
		progress.Write("ABORT: no finalised backup directory found in %s; refusing to touch the live volume", d.backupRoot())
		return
	}
	volumeName := d.dbVolumeName()

	progress.Write("Restoring database from backup at %s...", backupDir)
	if err := runCommandToLog(d.projDir, 10*time.Minute, progress.File(), "rsync",
		"docker", "run", "--rm",
		"-v", backupDir+":/source:ro",
		"-v", volumeName+":/dest",
		"alpine", "sh", "-c", "apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /source/ /dest/",
	); err != nil {
		progress.Write("%s: database restore failed: %v", ErrRollbackDBRestore, err)
	}
}

// pruneBackups trims finalised pre-upgrade-* backups to the `keep` most recent.
// Before removing each dir it NULLs backup_path on the matching upgrade row so
// reconcileBackupDir does not emit BACKUP_MISSING noise for intentionally-pruned
// dirs on subsequent ticks.  .tmp dirs are excluded — reconcileBackupDir owns them.
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
		if strings.HasSuffix(name, ".tmp") {
			continue // reconcileBackupDir handles orphan .tmp dirs
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

func (d *Service) archiveBackup(backupPath, version string) {
	archiveDir := filepath.Join(os.Getenv("HOME"), "statbus-backups")
	archivePath := filepath.Join(archiveDir, fmt.Sprintf("%s-pre.tar.gz", version))

	if err := runCommand(d.projDir, "tar", "-czf", archivePath, "-C", filepath.Dir(backupPath), filepath.Base(backupPath)); err != nil {
		fmt.Printf("Warning: archive backup failed: %v\n", err)
		return
	}

	// Prune old archives (keep last 3)
	d.pruneArchives(archiveDir, 3)
}

func (d *Service) pruneArchives(dir string, keep int) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}

	var archives []string
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".gz" {
			archives = append(archives, filepath.Join(dir, e.Name()))
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

	root := d.backupRoot()

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

	// --- 2. Build on-disk map (all pre-upgrade-* including .tmp) ---
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

	// --- 3. Check each referenced path; consume from onDisk map ---
	for path, id := range referenced {
		if _, ok := onDisk[path]; ok {
			delete(onDisk, path) // matched — not an orphan
			continue
		}
		fmt.Printf("BACKUP_MISSING: upgrade id=%d backup_path=%s not found on disk\n", id, path)
	}

	// --- 4. Remaining entries are orphans (no DB row references them) ---
	// Differential grace:
	//   .tmp  — 10 minutes (crash artifact; rsync never completed, low recovery value)
	//   final — 90 days   (may hold genuine recovery value; allow manual rescue)
	const tmpGrace      = 10 * time.Minute
	const finalisedGrace = 90 * 24 * time.Hour
	now := time.Now()
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
