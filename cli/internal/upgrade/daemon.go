package upgrade

import (
	"context"
	"database/sql"
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
	// pinnedVer removed — use "skip" in the UI instead of a channel that hides all releases
	upgrading      bool             // true during executeUpgrade; prevents ticker/notify from using nil conn
	pendingRecreate bool           // if true, next upgrade deletes+recreates the database instead of migrating
	cachedURL      string           // cached health check URL (derived from .env at startup)
	listenCancel context.CancelFunc // cancels the listenLoop goroutine
	listenWg     sync.WaitGroup     // tracks listenLoop goroutine lifetime
	requireSigning bool            // if true, reject unsigned commits (UPGRADE_REQUIRE_SIGNING)
	allowedSignersPath string      // path to tmp/allowed-signers file (empty if no signers configured)
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

	// Load trusted commit signers for signature verification
	if err := d.loadTrustedSigners(); err != nil {
		return err
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
	sdNotify("READY=1") // Tell systemd we're initialized

	// Main loop: use a goroutine for LISTEN/NOTIFY, select on channels
	notifyCh := make(chan *pgconn.Notification, 1)
	errCh := make(chan error, 1)
	d.startListenLoop(ctx, notifyCh, errCh)

	ticker := time.NewTicker(d.interval)
	defer ticker.Stop()

	// Systemd watchdog: proves the daemon is alive and responsive.
	// If WatchdogSec is set in the unit file, systemd kills+restarts
	// the daemon if it stops pinging within the timeout.
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
			fmt.Println("Upgrade daemon shutting down")
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

	// Mark complete
	d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET completed_at = now() WHERE id = $1", id)

	// Skip older releases that are still "available" — no point upgrading to an older version
	d.skipOlderReleases(ctx, commitSHA)
	d.runUpgradeCallback(displayName)

	fmt.Printf("Upgrade to %s completed (verified after daemon restart)\n", displayName)
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

// reportDiskSpace writes the current free disk space to system_info.
func (d *Daemon) reportDiskSpace(ctx context.Context) {
	if freeBytes, err := DiskFree(d.projDir); err == nil {
		freeGB := freeBytes / (1024 * 1024 * 1024)
		d.queryConn.Exec(ctx,
			`INSERT INTO public.system_info (key, value, updated_at)
			 VALUES ('disk_free_gb', $1::text, clock_timestamp())
			 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp()`,
			fmt.Sprintf("%d", freeGB))
	}
}

// skipOlderReleases marks available releases older than the selected commit as skipped.
// Ordering is by position (topological order) then committed_at as fallback.
func (d *Daemon) skipOlderReleases(ctx context.Context, selectedCommitSHA string) {
	// Get the position/committed_at of the selected commit
	var selectedPos sql.NullInt32
	var selectedCommittedAt time.Time
	err := d.queryConn.QueryRow(ctx,
		"SELECT position, committed_at FROM public.upgrade WHERE commit_sha = $1",
		selectedCommitSHA).Scan(&selectedPos, &selectedCommittedAt)
	if err != nil {
		return
	}

	// Skip all available entries that are older
	result, err := d.queryConn.Exec(ctx,
		`UPDATE public.upgrade SET skipped_at = now(), error = NULL
		 WHERE completed_at IS NULL AND started_at IS NULL AND skipped_at IS NULL
		   AND commit_sha != $1
		   AND (
		     (position IS NOT NULL AND $2::int IS NOT NULL AND position < $2)
		     OR committed_at < $3
		   )`,
		selectedCommitSHA, selectedPos, selectedCommittedAt)
	if err != nil {
		fmt.Printf("Failed to skip older releases: %v\n", err)
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

	return nil
}

// loadTrustedSigners reads UPGRADE_TRUSTED_SIGNER_* keys from .env and
// writes an allowed-signers file for git verify-commit. Also reads
// UPGRADE_REQUIRE_SIGNING to control enforcement.
func (d *Daemon) loadTrustedSigners() error {
	envPath := filepath.Join(d.projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return fmt.Errorf("load .env for signers: %w", err)
	}

	// Check enforcement setting
	d.requireSigning = false
	if v, ok := f.Get("UPGRADE_REQUIRE_SIGNING"); ok {
		d.requireSigning = v == "true"
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
		if d.requireSigning {
			return fmt.Errorf("no trusted signers configured (UPGRADE_TRUSTED_SIGNER_*), daemon refuses to start")
		}
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

	fmt.Printf("Commit signature verification enabled (%d trusted signer(s), require=%v)\n", len(signerLines), d.requireSigning)
	return nil
}

// verifyCommitSignature verifies an SSH signature on a git commit.
// Returns nil if the signature is valid and trusted.
// If no signers are configured and requireSigning is false, returns nil (permissive).
// If the commit is unsigned and requireSigning is false, logs a warning and returns nil.
func (d *Daemon) verifyCommitSignature(sha string) error {
	if d.allowedSignersPath == "" {
		// No signers configured — skip verification
		if d.requireSigning {
			return fmt.Errorf("no trusted signers configured but signing is required")
		}
		return nil
	}

	out, err := runCommandOutput(d.projDir, "git", "-c",
		fmt.Sprintf("gpg.ssh.allowedSignersFile=%s", d.allowedSignersPath),
		"verify-commit", sha)
	if err != nil {
		if d.requireSigning {
			return fmt.Errorf("commit %s signature verification failed: %s", sha[:12], strings.TrimSpace(out))
		}
		// Transition period: warn but don't block
		fmt.Printf("Warning: commit %s signature verification failed (not enforced): %s\n", sha[:12], strings.TrimSpace(out))
		return nil
	}

	if d.verbose {
		fmt.Printf("Commit %s signature verified: %s\n", sha[:12], strings.TrimSpace(out))
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

	// The daemon's compiled-in version — used to skip older releases.
	currentVersion := d.version

	for _, t := range filtered {
		// Skip releases older than or equal to what we're currently running.
		if CompareVersions(t.TagName, currentVersion) <= 0 {
			if d.verbose {
				fmt.Printf("  Skipping %s (not newer than %s)\n", t.TagName, currentVersion)
			}
			continue
		}

		// Determine release_status based on tag format and manifest availability.
		// Tags with "-" are prereleases, without "-" are full releases.
		// If the release manifest isn't available yet (CI still building), downgrade to "commit".
		targetStatus := "prerelease"
		if !t.Prerelease {
			targetStatus = "release"
		}
		// Check if release artifacts exist
		if _, err := FetchManifest(t.TagName); err != nil {
			targetStatus = "commit" // manifest not available yet
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
func (d *Daemon) pruneDeletedTags(ctx context.Context, currentTags []GitTag) {
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
func (d *Daemon) discoverEdge(ctx context.Context) {
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
			`INSERT INTO public.upgrade (commit_sha, committed_at, summary, has_migrations)
			 VALUES ($1, $2, $3, false)
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

func (d *Daemon) preDownloadImages(ctx context.Context) {
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

		if d.verbose {
			fmt.Printf("Pre-downloading images for %s...\n", displayName)
		}

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

func (d *Daemon) scheduleImmediate(ctx context.Context, versionOrSHA string) {
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
	// → sends NOTIFY upgrade_apply → daemon calls scheduleImmediate again → infinite loop.
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
		d.skipOlderReleases(ctx, commitSHA)
	} else {
		fmt.Printf("Version %s already scheduled, no action needed\n", displayName)
	}
}

func (d *Daemon) executeScheduled(ctx context.Context) {
	var id int
	var commitSHA, displayName string
	err := d.queryConn.QueryRow(ctx,
		`SELECT id, commit_sha,
		        COALESCE(tags[array_upper(tags, 1)], 'sha-' || left(commit_sha, 12)) as display_name
		 FROM public.upgrade
		 WHERE scheduled_at <= now() AND started_at IS NULL AND skipped_at IS NULL
		 ORDER BY scheduled_at LIMIT 1`).Scan(&id, &commitSHA, &displayName)
	if err != nil {
		return // no pending upgrades
	}

	fmt.Printf("Executing upgrade to %s...\n", displayName)
	if err := d.executeUpgrade(ctx, id, commitSHA, displayName); err != nil {
		fmt.Printf("Upgrade to %s failed: %v\n", displayName, err)
	}
}

func (d *Daemon) executeUpgrade(ctx context.Context, id int, commitSHA string, displayName string) error {
	d.upgrading = true
	defer func() { d.upgrading = false }()

	projDir := d.projDir
	progress := NewProgressLog(projDir)
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
	// If CI hasn't finished building the release assets yet, refuse to start.
	// Only check for tagged releases, not raw SHA commits.
	if !strings.HasPrefix(displayName, "sha-") {
		progress.Write("Verifying release assets available...")
		manifest, err := FetchManifest(displayName)
		if err != nil {
			d.failUpgrade(ctx, id, fmt.Sprintf("Release manifest not available for %s: %v. CI may still be building. Will retry on next check.", displayName, err), progress)
			return err
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
	// From this point on, the maintenance guard will activate.
	d.queryConn.Exec(ctx,
		"UPDATE public.upgrade SET started_at = now(), from_version = $1 WHERE id = $2",
		d.version, id)

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
	progress.Write("Installing %s...", displayName)
	if err := runCommand(projDir, "git", "fetch", "--depth", "1", "origin", commitSHA); err != nil {
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

	// Reconnect daemon DB connection
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

	// Done — deactivate maintenance, archive, finalize
	d.setMaintenance(false)
	d.archiveBackup(backupPath, displayName)

	fmt.Printf("Upgrade to %s completed successfully\n", displayName)

	// Self-update binary (may restart daemon via exit code 42).
	// If self-update restarts, the NEW daemon marks completed_at on startup
	// (completeInProgressUpgrade) — so "completed" means the new version is verified.
	// Only for tagged releases — SHA commits don't have release binaries.
	if !strings.HasPrefix(displayName, "sha-") {
		d.selfUpdate(ctx, displayName, progress)
	}

	// If we get here, self-update didn't restart (no binary for platform, or same version).
	// Mark complete now since there won't be a new daemon to do it.
	d.queryConn.Exec(ctx, "UPDATE public.upgrade SET completed_at = now() WHERE id = $1", id)
	d.skipOlderReleases(ctx, commitSHA)
	d.runUpgradeCallback(displayName)
	progress.Write("Upgrade to %s complete!", displayName)

	return nil
}

// runUpgradeCallback executes the UPGRADE_CALLBACK shell command from .env, if set.
// Called after a successful upgrade to notify external systems (e.g., Slack).
// Never fails the upgrade — logs errors but always returns.
func (d *Daemon) runUpgradeCallback(displayName string) {
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
		progress.Write("Self-update skipped: cannot fetch manifest for %s: %v", version, err)
		return
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

	progress.Write("Binary updated. Restarting daemon...")
	progress.Close()
	// Exit with code 42 to signal systemd to restart
	os.Exit(42)
}

