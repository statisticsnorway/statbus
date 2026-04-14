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
	dir := filepath.Join(os.Getenv("HOME"), "statbus-maintenance")
	file := filepath.Join(dir, "active")

	if active {
		os.MkdirAll(dir, 0755)
		os.WriteFile(file, []byte("upgrade in progress\n"), 0644)
	} else {
		os.Remove(file)
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
func (d *Service) backupDatabase(progress *ProgressLog) (string, error) {
	root := d.backupRoot()
	if err := os.MkdirAll(root, 0755); err != nil {
		return "", fmt.Errorf("create backup root: %w", err)
	}

	stamp := time.Now().UTC().Format("20060102T150405Z")
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

	// Opportunistic cleanup: keep the 3 newest finalised backups, drop
	// stale .tmp dirs from prior crashes.
	d.pruneBackups(3)

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
		progress.Write("WARNING: Database restore failed: %v", err)
	}
}

// pruneBackups deletes .tmp leftovers older than 10 minutes (long
// enough to guarantee the originating process is dead, generous for
// genuinely-slow rsyncs) and trims finalised backups to the `keep`
// most recent.
func (d *Service) pruneBackups(keep int) {
	entries, err := os.ReadDir(d.backupRoot())
	if err != nil {
		return
	}
	var finalised, tmps []string
	tmpCutoff := time.Now().Add(-10 * time.Minute)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasPrefix(name, "pre-upgrade-") {
			continue
		}
		full := filepath.Join(d.backupRoot(), name)
		if strings.HasSuffix(name, ".tmp") {
			info, ierr := e.Info()
			if ierr == nil && info.ModTime().Before(tmpCutoff) {
				tmps = append(tmps, full)
			}
			continue
		}
		finalised = append(finalised, full)
	}
	for _, p := range tmps {
		os.RemoveAll(p)
	}
	if len(finalised) > keep {
		sort.Strings(finalised)
		for _, p := range finalised[:len(finalised)-keep] {
			os.RemoveAll(p)
		}
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
