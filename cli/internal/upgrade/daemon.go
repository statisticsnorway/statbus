package upgrade

import (
	"context"
	"fmt"
	"os"
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

// Daemon is the long-running upgrade daemon.
type Daemon struct {
	projDir      string
	version      string           // compiled-in version from ldflags (e.g., v2026.03.0-rc.11)
	listenConn   *pgx.Conn         // dedicated to LISTEN/NOTIFY — never use for queries
	queryConn    *pgx.Conn         // for all SELECT/INSERT/UPDATE queries
	verbose      bool
	channel      string
	interval     time.Duration
	autoDL       bool
	pinnedVer    string
	upgrading    bool             // true during executeUpgrade; prevents ticker/notify from using nil conn
	cachedURL    string           // cached health check URL (derived from .env at startup)
	listenCancel context.CancelFunc // cancels the listenLoop goroutine
	listenWg     sync.WaitGroup     // tracks listenLoop goroutine lifetime
}

// NewDaemon creates a new upgrade daemon.
func NewDaemon(projDir string, verbose bool, version string) *Daemon {
	return &Daemon{
		projDir: projDir,
		version: version,
		verbose: verbose,
	}
}

// Run starts the daemon main loop.
func (d *Daemon) Run(ctx context.Context) error {
	ctx, cancel := signal.NotifyContext(ctx, syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	if err := d.loadConfig(); err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	if err := d.connect(ctx); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer d.listenConn.Close(context.Background())
	defer d.queryConn.Close(context.Background())

	// Acquire advisory lock to prevent multiple daemons
	if err := d.acquireAdvisoryLock(ctx); err != nil {
		return err
	}

	// Complete any in-progress upgrade from a previous daemon instance
	// (e.g., after self-update restart via exit code 42)
	d.completeInProgressUpgrade(ctx)

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

	fmt.Printf("Upgrade daemon started (channel=%s, interval=%s)\n", d.channel, d.interval)

	// Main loop: use a goroutine for LISTEN/NOTIFY, select on channels
	notifyCh := make(chan *pgconn.Notification, 1)
	errCh := make(chan error, 1)
	d.startListenLoop(ctx, notifyCh, errCh)

	ticker := time.NewTicker(d.interval)
	defer ticker.Stop()

	// Initial discovery on startup
	d.discover(ctx)

	for {
		select {
		case <-ctx.Done():
			fmt.Println("Upgrade daemon shutting down")
			d.stopListenLoop()
			return nil
		case <-ticker.C:
			if !d.upgrading {
				d.discover(ctx)
				d.executeScheduled(ctx)
			}
		case n := <-notifyCh:
			if !d.upgrading {
				d.handleNotification(ctx, n)
				d.executeScheduled(ctx)
			}
		case err := <-errCh:
			d.listenWg.Wait() // ensure old goroutine fully exited
			if ctx.Err() != nil {
				return nil // shutdown
			}
			fmt.Printf("LISTEN error: %v, reconnecting...\n", err)
			if reconnErr := d.reconnect(ctx); reconnErr != nil {
				return fmt.Errorf("reconnect failed: %w", reconnErr)
			}
			// Restart listen goroutine
			d.startListenLoop(ctx, notifyCh, errCh)
		}
	}
}

// startListenLoop launches a new listenLoop goroutine with a cancellable context.
func (d *Daemon) startListenLoop(ctx context.Context, notifyCh chan<- *pgconn.Notification, errCh chan<- error) {
	listenCtx, cancel := context.WithCancel(ctx)
	d.listenCancel = cancel
	d.listenWg.Add(1)
	go func() {
		defer d.listenWg.Done()
		d.listenLoop(listenCtx, notifyCh, errCh)
	}()
}

// stopListenLoop cancels the listenLoop goroutine and waits for it to exit.
func (d *Daemon) stopListenLoop() {
	if d.listenCancel != nil {
		d.listenCancel()
		d.listenWg.Wait()
		d.listenCancel = nil
	}
}

// listenLoop runs WaitForNotification in a goroutine, sending results on channels.
func (d *Daemon) listenLoop(ctx context.Context, notifyCh chan<- *pgconn.Notification, errCh chan<- error) {
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

func (d *Daemon) handleNotification(ctx context.Context, n *pgconn.Notification) {
	switch n.Channel {
	case "upgrade_check":
		if d.verbose {
			fmt.Println("Received NOTIFY upgrade_check")
		}
		d.discover(ctx)
	case "upgrade_apply":
		payload := strings.TrimSpace(n.Payload)
		if payload == "" {
			// Empty payload = run whatever is scheduled
			return
		}
		if d.verbose {
			fmt.Printf("Received NOTIFY upgrade_apply: %s\n", payload)
		}
		if ValidateVersion(payload) {
			d.scheduleImmediate(ctx, payload)
		} else {
			fmt.Printf("Invalid version in NOTIFY payload: %q\n", payload)
		}
	}
}

func (d *Daemon) acquireAdvisoryLock(ctx context.Context) error {
	var locked bool
	err := d.queryConn.QueryRow(ctx, "SELECT pg_try_advisory_lock(hashtext('upgrade_daemon'))").Scan(&locked)
	if err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}
	if !locked {
		return fmt.Errorf("another upgrade daemon is already running (advisory lock held)")
	}
	return nil
}

// completeInProgressUpgrade checks for an upgrade that was started but not
// completed (e.g., daemon restarted after self-update). If found, verifies
// health and marks completed_at. This ensures "completed" truly means
// the new version is running and verified.
func (d *Daemon) completeInProgressUpgrade(ctx context.Context) {
	var id int
	var version string
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, version FROM public.upgrade
		 WHERE started_at IS NOT NULL
		   AND completed_at IS NULL
		   AND error IS NULL
		   AND rollback_completed_at IS NULL
		 LIMIT 1`).Scan(&id, &version)
	if err != nil {
		return // no in-progress upgrade
	}

	fmt.Printf("Found in-progress upgrade to %s, verifying...\n", version)

	// Verify services are healthy
	if err := d.waitForDBHealth(30 * time.Second); err != nil {
		fmt.Printf("Warning: in-progress upgrade %s health check failed: %v\n", version, err)
		d.queryConn.Exec(ctx,
			"UPDATE public.upgrade SET error = $1 WHERE id = $2",
			fmt.Sprintf("post-restart health check failed: %v", err), id)
		return
	}

	// Mark complete
	d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET completed_at = now() WHERE id = $1", id)

	// Skip older releases that are still "available" — no point upgrading to an older version
	d.skipOlderReleases(ctx, version)

	fmt.Printf("Upgrade to %s completed (verified after daemon restart)\n", version)
}

// syncConfigToSystemInfo writes UPGRADE_* values from .env to system_info.
// This keeps the admin UI in sync with the config file.
func (d *Daemon) syncConfigToSystemInfo(ctx context.Context) {
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

// skipOlderReleases marks older available releases as skipped after a newer version completes.
func (d *Daemon) skipOlderReleases(ctx context.Context, completedVersion string) {
	result, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade
		 SET skipped_at = now()
		 WHERE completed_at IS NULL
		   AND skipped_at IS NULL
		   AND error IS NULL
		   AND discovered_at < (SELECT discovered_at FROM public.upgrade WHERE version = $1)`,
		completedVersion)
	if err != nil {
		return
	}
	if result.RowsAffected() > 0 {
		fmt.Printf("Skipped %d older release(s)\n", result.RowsAffected())
	}
}

func (d *Daemon) loadConfig() error {
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

	if v, ok := f.Get("UPGRADE_PINNED_VERSION"); ok {
		d.pinnedVer = v
	}

	return nil
}

func (d *Daemon) connect(ctx context.Context) error {
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

	connStr := fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
		getOr("SITE_DOMAIN", "localhost"),
		getOr("CADDY_DB_PORT", "5432"),
		getOr("POSTGRES_APP_DB", "statbus_local"),
		getOr("POSTGRES_ADMIN_USER", "postgres"),
		getOr("POSTGRES_ADMIN_PASSWORD", ""),
	)

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

func (d *Daemon) reconnect(ctx context.Context) error {
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

func (d *Daemon) cleanStaleMaintenance(ctx context.Context) {
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
		if d.verbose {
			fmt.Printf("Cannot check upgrade status (DB error: %v), leaving maintenance file\n", err)
		}
		return
	}
	if count == 0 {
		os.Remove(maintenanceFile)
		if d.verbose {
			fmt.Println("Cleaned stale maintenance file")
		}
	}
}

func (d *Daemon) checkMissedUpgrades(ctx context.Context) {
	var count int
	err := d.queryConn.QueryRow(ctx,
		"SELECT COUNT(*) FROM public.upgrade WHERE scheduled_at IS NOT NULL AND started_at IS NULL").Scan(&count)
	if err == nil && count > 0 {
		fmt.Printf("Found %d missed scheduled upgrade(s)\n", count)
	}
}

func (d *Daemon) discover(ctx context.Context) {
	if d.channel == "pinned" {
		return
	}

	releases, err := FetchReleases()
	if err != nil {
		fmt.Printf("Discovery error: %v\n", err)
		return
	}

	filtered := FilterByChannel(releases, d.channel)
	fmt.Printf("Discovery: %d release(s) from GitHub, %d match channel %q\n", len(releases), len(filtered), d.channel)

	for _, r := range filtered {
		var exists bool
		err := d.queryConn.QueryRow(ctx,
			"SELECT EXISTS(SELECT 1 FROM public.upgrade WHERE version = $1)",
			r.TagName).Scan(&exists)
		if err != nil {
			fmt.Printf("  Check exists for %s: %v\n", r.TagName, err)
			continue
		}
		if exists {
			continue
		}

		hasMigrations := HasMigrationsFromChanges(r.Body)

		// Try to get commit SHA and has_migrations from manifest
		commitSHA := r.TargetSHA // Fallback: may be branch name, not SHA
		if manifest, err := FetchManifest(r.TagName); err == nil {
			hasMigrations = manifest.HasMigrations
			if manifest.CommitSHA != "" {
				commitSHA = manifest.CommitSHA
			}
		}

		summary := r.Name
		if summary == "" {
			summary = r.TagName
		}

		_, err = d.queryConn.Exec(ctx,
			`INSERT INTO public.upgrade (version, commit_sha, is_prerelease, summary, changes, release_url, has_migrations)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)
			 ON CONFLICT (version) DO NOTHING`,
			r.TagName, commitSHA, r.Prerelease, summary, r.Body, r.HTMLURL, hasMigrations)
		if err != nil {
			fmt.Printf("Failed to record release %s: %v\n", r.TagName, err)
			continue
		}

		fmt.Printf("Discovered: %s\n", ReleaseSummary(r))
	}

	// Auto-download images if enabled
	if d.autoDL {
		d.preDownloadImages(ctx)
	}
}

func (d *Daemon) preDownloadImages(ctx context.Context) {
	rows, err := d.queryConn.Query(ctx,
		`SELECT version FROM public.upgrade
		 WHERE images_downloaded = false AND skipped_at IS NULL AND error IS NULL
		 ORDER BY discovered_at LIMIT 3`)
	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() {
		var version string
		if err := rows.Scan(&version); err != nil {
			continue
		}

		if d.verbose {
			fmt.Printf("Pre-downloading images for %s...\n", version)
		}

		if err := d.pullImages(version); err != nil {
			fmt.Printf("Pre-download failed for %s: %v\n", version, err)
			continue
		}

		d.queryConn.Exec(ctx,
			"UPDATE public.upgrade SET images_downloaded = true WHERE version = $1",
			version)
	}
}

func (d *Daemon) scheduleImmediate(ctx context.Context, version string) {
	_, err := d.queryConn.Exec(ctx,
		`INSERT INTO public.upgrade (version, commit_sha, is_prerelease, summary, scheduled_at)
		 VALUES ($1, $1, false, $1, now())
		 ON CONFLICT (version) DO UPDATE SET scheduled_at = now()`,
		version)
	if err != nil {
		fmt.Printf("Failed to schedule %s: %v\n", version, err)
	} else {
		fmt.Printf("Scheduled immediate upgrade to %s\n", version)
	}
}

func (d *Daemon) executeScheduled(ctx context.Context) {
	var id int
	var version string
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, version FROM public.upgrade
		 WHERE scheduled_at <= now() AND started_at IS NULL AND skipped_at IS NULL
		 ORDER BY scheduled_at LIMIT 1`).Scan(&id, &version)
	if err != nil {
		return // no pending upgrades
	}

	fmt.Printf("Executing upgrade to %s...\n", version)
	if err := d.executeUpgrade(ctx, id, version); err != nil {
		fmt.Printf("Upgrade to %s failed: %v\n", version, err)
	}
}

func (d *Daemon) executeUpgrade(ctx context.Context, id int, version string) error {
	d.upgrading = true
	defer func() { d.upgrading = false }()

	projDir := d.projDir
	progress := NewProgressLog(projDir)
	defer progress.Close()

	// Mark started — use compiled-in version, not .env (which may be stale/updated)
	d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET started_at = now(), from_version = $1 WHERE id = $2",
		d.version, id)

	progress.Write("Upgrading to %s (from %s)...", version, d.version)

	// Step 1: Prepare images
	progress.Write("Preparing images...")
	if err := d.pullImages(version); err != nil {
		d.failUpgrade(ctx, id, fmt.Sprintf("Failed to pull images for %s: %v", version, err), progress)
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

	// Restart proxy first — picks up new Caddy config, verified working
	// before we take anything else down. Sub-second restart.
	runCommand(projDir, "docker", "compose", "up", "-d", "--force-recreate", "proxy")

	// Step 3: Stop application services (proxy stays running for maintenance page)
	progress.Write("Stopping services...")
	if err := runCommand(projDir, "docker", "compose", "stop", "app", "worker", "rest"); err != nil {
		progress.Write("Warning: could not stop some services: %v", err)
	}

	// Step 4: Stop database for consistent backup
	if err := runCommand(projDir, "docker", "compose", "stop", "db"); err != nil {
		progress.Write("Warning: could not stop database: %v", err)
	}

	// Step 5: Backup database
	progress.Write("Backing up database...")
	previousVersion := d.version
	backupPath, err := d.backupDatabase(progress)
	if err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Step 6: Install new version
	progress.Write("Installing %s...", version)
	if err := runCommand(projDir, "git", "fetch", "--tags", "--depth", "1", "origin", "tag", version); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}
	if err := runCommand(projDir, "git", "-c", "advice.detachedHead=false", "checkout", version); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Verify checked-out SHA matches manifest (detect tag spoofing)
	if manifest, mErr := FetchManifest(version); mErr == nil && manifest.CommitSHA != "" {
		if checkedOut, gErr := runCommandOutput(projDir, "git", "rev-parse", "HEAD"); gErr == nil {
			checkedOut = strings.TrimSpace(checkedOut)
			if !strings.HasPrefix(checkedOut, manifest.CommitSHA) && !strings.HasPrefix(manifest.CommitSHA, checkedOut) {
				errMsg := fmt.Sprintf("Version verification failed: expected commit %s but got %s. Possible tag tampering.", manifest.CommitSHA[:12], checkedOut[:12])
				progress.Write("%s", errMsg)
				d.rollback(ctx, id, version, previousVersion, progress)
				return fmt.Errorf("%s", errMsg)
			}
		}
	}

	// Regenerate config — VERSION is derived from git describe --tags --always,
	// which returns the tag name (e.g., v2026.03.0-rc.3) since we just checked it out.
	if err := runCommand(projDir, filepath.Join(projDir, "sb"), "config", "generate"); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Step 8: Pull updated images
	progress.Write("Pulling updated images...")
	if err := runCommand(projDir, "docker", "compose", "pull"); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Step 9: Start database
	progress.Write("Starting database...")
	if err := runCommand(projDir, "docker", "compose", "up", "-d", "db"); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Wait for DB health
	if err := d.waitForDBHealth(30 * time.Second); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Reconnect daemon DB connection
	if err := d.reconnect(ctx); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Update backup_path now that we have a connection
	d.queryConn.Exec(ctx, "UPDATE public.upgrade SET backup_path = $1 WHERE id = $2", backupPath, id)

	// Step 10: Run migrations
	progress.Write("Applying database migrations...")
	if err := runCommand(projDir, filepath.Join(projDir, "sb"), "migrate", "up", "--verbose"); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Step 11: Start application services (proxy already running from step 2)
	progress.Write("Starting services...")
	if err := runCommand(projDir, "docker", "compose", "up", "-d", "app", "worker", "rest"); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Step 12: Verify health
	progress.Write("Verifying health...")
	if err := d.healthCheck(5, 5*time.Second); err != nil {
		d.rollback(ctx, id, version, previousVersion, progress)
		return err
	}

	// Check for simulated failure sentinel (for testing the rollback path).
	// Create with: touch tmp/simulate-upgrade-failure
	// The file is consumed (deleted) so it only triggers once.
	sentinelPath := filepath.Join(projDir, "tmp", "simulate-upgrade-failure")
	if _, err := os.Stat(sentinelPath); err == nil {
		os.Remove(sentinelPath)
		progress.Write("Simulated failure triggered (sentinel file found) — rolling back")
		d.rollback(ctx, id, version, previousVersion, progress)
		return fmt.Errorf("simulated upgrade failure for rollback testing")
	}

	// Done — deactivate maintenance, archive, finalize
	d.setMaintenance(false)
	d.archiveBackup(backupPath, version)

	fmt.Printf("Upgrade to %s completed successfully\n", version)

	// Self-update binary (may restart daemon via exit code 42).
	// If self-update restarts, the NEW daemon marks completed_at on startup
	// (completeInProgressUpgrade) — so "completed" means the new version is verified.
	d.selfUpdate(ctx, version, progress)

	// If we get here, self-update didn't restart (no binary for platform, or same version).
	// Mark complete now since there won't be a new daemon to do it.
	d.queryConn.Exec(ctx, "UPDATE public.upgrade SET completed_at = now() WHERE id = $1", id)
	d.skipOlderReleases(ctx, version)
	progress.Write("Upgrade to %s complete!", version)

	return nil
}

func (d *Daemon) failUpgrade(ctx context.Context, id int, errMsg string, progress *ProgressLog) {
	if d.queryConn != nil {
		d.queryConn.Exec(ctx, "UPDATE public.upgrade SET error = $1 WHERE id = $2", errMsg, id)
	}
	progress.Write("FAILED: %s", errMsg)
}

func (d *Daemon) rollback(ctx context.Context, id int, version, previousVersion string, progress *ProgressLog) {
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

	progress.Write("Rollback complete. The previous version has been restored.")
}

func (d *Daemon) selfUpdate(ctx context.Context, version string, progress *ProgressLog) {
	manifest, err := FetchManifest(version)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Self-update: cannot fetch manifest for %s: %v\n", version, err)
		return
	}

	platform := selfupdate.Platform()
	binary, ok := manifest.Binaries[platform]
	if !ok {
		if d.verbose {
			fmt.Fprintf(os.Stderr, "Self-update: no binary for platform %s\n", platform)
		}
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

	progress.Write("Binary updated. Restarting daemon...")
	progress.Close()
	// Exit with code 42 to signal systemd to restart
	os.Exit(42)
}

