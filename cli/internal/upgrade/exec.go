package upgrade

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// runCommand executes a command with inherited stdout/stderr and a default 5-minute timeout.
func runCommand(dir string, name string, args ...string) error {
	return runCommandWithTimeout(dir, 5*time.Minute, name, args...)
}

// runCommandWithTimeout executes a command with a specific timeout.
// If the timeout expires, the process is killed and an error is returned.
func runCommandWithTimeout(dir string, timeout time.Duration, name string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
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
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return string(out), fmt.Errorf("command timed out after 2m: %s %v", name, args)
	}
	return string(out), err
}

func (d *Daemon) pullImages(version string) error {
	// docker compose reads VERSION from .env, not from process environment.
	// For pre-downloads before config regeneration, we pass it as an override.
	// 10-minute timeout: image pulls can be slow on shared servers.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", "compose", "pull")
	cmd.Dir = d.projDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "VERSION="+version)
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("docker compose pull timed out after 10 minutes")
	}
	return err
}

func (d *Daemon) setMaintenance(active bool) {
	dir := filepath.Join(os.Getenv("HOME"), "statbus-maintenance")
	file := filepath.Join(dir, "active")

	if active {
		os.MkdirAll(dir, 0755)
		os.WriteFile(file, []byte("upgrade in progress\n"), 0644)
	} else {
		os.Remove(file)
	}
}

func (d *Daemon) backupDatabase(progress *ProgressLog) (string, error) {
	backupDir := filepath.Join(os.Getenv("HOME"), "statbus-backups", "pre-upgrade")
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return "", fmt.Errorf("create backup dir: %w", err)
	}

	// Find the db data directory
	dbDataDir := filepath.Join(d.projDir, "postgres", "volumes", "db", "data")
	if _, err := os.Stat(dbDataDir); os.IsNotExist(err) {
		return "", fmt.Errorf("db data dir not found: %s", dbDataDir)
	}

	// rsync with sudo (postgres uid owns the files)
	// DB must be stopped before this point for a consistent backup
	if err := runCommandWithTimeout(d.projDir, 10*time.Minute, "sudo", "rsync", "-a", "--delete",
		dbDataDir+"/", backupDir+"/"); err != nil {
		return "", fmt.Errorf("rsync backup: %w", err)
	}

	return backupDir, nil
}

func (d *Daemon) restoreDatabase(progress *ProgressLog) {
	backupDir := filepath.Join(os.Getenv("HOME"), "statbus-backups", "pre-upgrade")
	dbDataDir := filepath.Join(d.projDir, "postgres", "volumes", "db", "data")

	progress.Write("Restoring database from backup...")
	if err := runCommand(d.projDir, "sudo", "rsync", "-a", "--delete",
		backupDir+"/", dbDataDir+"/"); err != nil {
		progress.Write("WARNING: Database restore failed: %v", err)
	}
}

func (d *Daemon) archiveBackup(backupPath, version string) {
	archiveDir := filepath.Join(os.Getenv("HOME"), "statbus-backups")
	archivePath := filepath.Join(archiveDir, fmt.Sprintf("%s-pre.tar.gz", version))

	if err := runCommand(d.projDir, "sudo", "tar", "-czf", archivePath, "-C", filepath.Dir(backupPath), filepath.Base(backupPath)); err != nil {
		fmt.Printf("Warning: archive backup failed: %v\n", err)
		return
	}

	// Prune old archives (keep last 3)
	d.pruneArchives(archiveDir, 3)
}

func (d *Daemon) pruneArchives(dir string, keep int) {
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

func (d *Daemon) waitForDBHealth(timeout time.Duration) error {
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
func (d *Daemon) healthURL() string {
	if d.cachedURL != "" {
		return d.cachedURL
	}
	d.cachedURL = "http://localhost:3000/"
	envPath := filepath.Join(d.projDir, ".env")
	if f, err := dotenv.Load(envPath); err == nil {
		if port, ok := f.Get("CADDY_HTTP_PORT"); ok {
			d.cachedURL = fmt.Sprintf("http://localhost:%s/", port)
		}
	}
	return d.cachedURL
}

func (d *Daemon) healthCheck(retries int, interval time.Duration) error {
	healthURL := d.healthURL()
	client := &http.Client{Timeout: 10 * time.Second}

	for i := 0; i < retries; i++ {
		resp, err := client.Get(healthURL)
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
