package upgrade

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// runCommand executes a command with inherited stdout/stderr.
func runCommand(dir string, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// runCommandOutput executes a command and returns combined output.
func runCommandOutput(dir string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func (d *Daemon) pullImages(version string) error {
	// Set STATBUS_VERSION env var for docker compose
	os.Setenv("STATBUS_VERSION", version)
	defer os.Unsetenv("STATBUS_VERSION")

	return runCommand(d.projDir, "docker", "compose", "pull")
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
	progress.Write("rsync %s → %s", dbDataDir, backupDir)
	if err := runCommand(d.projDir, "sudo", "rsync", "-a", "--delete",
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

	if err := runCommand(d.projDir, "tar", "-czf", archivePath, "-C", filepath.Dir(backupPath), filepath.Base(backupPath)); err != nil {
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

	// Remove oldest (sorted by name = version = chronological)
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

func (d *Daemon) healthCheck(retries int, interval time.Duration) error {
	for i := 0; i < retries; i++ {
		// Check PostgREST
		resp, err := http.Get("http://localhost:3000/rest/")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode < 500 {
				return nil
			}
		}

		if d.verbose {
			fmt.Printf("Health check attempt %d/%d failed\n", i+1, retries)
		}
		time.Sleep(interval)
	}
	return fmt.Errorf("health check failed after %d attempts", retries)
}
