package upgrade

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
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
	if err := runCommandWithTimeout(d.projDir, 10*time.Minute,
		"docker", "run", "--rm",
		"-v", volumeName+":/source:ro",
		"-v", tmpDir+":/backup",
		"alpine", "sh", "-c", "apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /source/ /backup/",
	); err != nil {
		// Leave the .tmp dir for inspection; pruneStaleTmpBackups will
		// clean it after 10 minutes if it's confirmed dead.
		return "", fmt.Errorf("rsync backup: %w", err)
	}

	// Atomic completion marker: directory's final name appearing IS the
	// completion signal. No sentinel files, no symlinks.
	if err := os.Rename(tmpDir, finalDir); err != nil {
		return "", fmt.Errorf("finalise backup (rename %s -> %s): %w", tmpDir, finalDir, err)
	}

	// Pruning is deferred to the service tick (reconcileBackupDir + pruneBackups)
	// where d.queryConn is live and can NULL backup_path before deletion.
	// No pruning here — the DB connection is closed for the duration of executeUpgrade.

	return finalDir, nil
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
	if err := runCommandWithTimeout(d.projDir, 10*time.Minute,
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
		for _, p := range finalised[:len(finalised)-keep] {
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
		}
	}
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
	for _, p := range sorted[:len(sorted)-keep] {
		os.Remove(filepath.Join(dir, p.stem+".log"))        // no-op if absent
		os.Remove(filepath.Join(dir, p.stem+".bundle.txt")) // no-op if absent
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

// healthURL returns the cached health check URL, loading from .env on first call.
//
// Probes /rest/rpc/auth_status — the same PostgREST RPC the frontend
// invokes on every page load (app/src/atoms/auth-machine.ts:66). Hitting
// it through Caddy exercises the full request path: caddy → next.js
// proxy → postgrest → postgres. Any failure here is a failure a real
// user would see on first load. Older versions of this code probed `/`
// and accepted any < 500, but the Next.js root renders even when
// PostgREST or the DB is broken — false-positive healthy upgrade.
//
// auth_status is anonymous-safe (returns 200 with is_authenticated=false
// without a JWT) and reads auth.user, so it touches both PostgREST and
// the DB.
func (d *Service) healthURL() string {
	if d.cachedURL != "" {
		return d.cachedURL
	}
	port := "3000"
	envPath := filepath.Join(d.projDir, ".env")
	if f, err := dotenv.Load(envPath); err == nil {
		if v, ok := f.Get("CADDY_HTTP_PORT"); ok {
			port = v
		}
	}
	d.cachedURL = fmt.Sprintf("http://localhost:%s/rest/rpc/auth_status", port)
	return d.cachedURL
}

func (d *Service) healthCheck(retries int, interval time.Duration) error {
	healthURL := d.healthURL()
	client := &http.Client{Timeout: 10 * time.Second}

	for i := 0; i < retries; i++ {
		// POST {} matches what the frontend sends — PostgREST RPCs are
		// invoked via POST with a JSON body.
		resp, err := client.Post(healthURL, "application/json", strings.NewReader("{}"))
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode < 500 {
				return nil
			}
		}

		if d.verbose {
			fmt.Printf("Health check attempt %d/%d failed (url=%s)\n", i+1, retries, healthURL)
		}
		time.Sleep(interval)
	}
	return fmt.Errorf("health check failed after %d attempts", retries)
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
