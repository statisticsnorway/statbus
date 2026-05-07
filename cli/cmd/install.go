package cmd

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/invariants"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// markTerminal is a thin wrapper over invariants.MarkTerminal that pins
// the projDir to the install dir. Every fail-fast guard site in this file
// calls markTerminal BEFORE returning the wrapped error, so install.sh
// can surface the invariant name in its SYSTEM UNUSABLE banner.
func markTerminal(installDir, name, observed string) {
	invariants.MarkTerminal(installDir, name, observed)
}

// thisLine returns the caller's source line number. Guard-site transcripts
// embed it so the stderr message always points at the real code location
// even as the file is edited — keeping the `install.go:NNN` anchor
// stable enough for support-bundle triage.
func thisLine() int {
	_, _, line, ok := runtime.Caller(1)
	if !ok {
		return 0
	}
	return line
}

// capturePanicInvariant is a deferred helper registered at the top of
// runInstall. It catches panics whose string form starts with
// "INVARIANT <name> violated:" (emitted by log.Panicf at bug-class
// assert sites — class=panic-regression) and writes the name to
// install-terminal.txt so install.sh's banner still has an anchor.
// The panic is re-raised so the Go runtime prints the stack trace
// and the process exits non-zero.
func capturePanicInvariant(installDir string) {
	r := recover()
	if r == nil {
		return
	}
	var msg string
	switch v := r.(type) {
	case string:
		msg = v
	case error:
		msg = v.Error()
	default:
		msg = fmt.Sprintf("%v", v)
	}
	const prefix = "INVARIANT "
	if strings.HasPrefix(msg, prefix) {
		rest := strings.TrimPrefix(msg, prefix)
		if sp := strings.IndexByte(rest, ' '); sp > 0 {
			name := rest[:sp]
			observed := strings.TrimSpace(rest[sp:])
			markTerminal(installDir, name, observed)
		}
	}
	panic(r)
}

var nonInteractive bool

// trustGitHubUser is set by --trust-github-user to auto-trust a GitHub user's
// signing key during install. This runs trust-key add non-interactively before
// the step table, so cloud.sh can pass it through for fleet-wide key repair.
var trustGitHubUser string

// insideActiveUpgrade signals that this install invocation is a post-upgrade
// fixup spawned by the upgrade service itself. It is NOT a user-facing flag —
// operators must never pass it. The service at service.go:executeUpgrade sets
// both this CLI flag and STATBUS_INSIDE_ACTIVE_UPGRADE=1 env var on its child
// exec; either triggers the mutex bypass in runInstall.
var insideActiveUpgrade bool

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install or resume StatBus installation",
	// install is part of the recovery surface — its job is to fix the
	// stale-binary state. stalenessGuard rebuilds + re-execs instead of
	// hard-failing when this annotation is present. See cli/cmd/root.go.
	Annotations: map[string]string{"selfheal": "true"},
	Long: `Unified entrypoint for first-install, repair, and dispatching a
pending upgrade. Probes the install state and routes:

  - Fresh directory         → runs the install step-table.
  - Existing install        → idempotent config-refresh (safe to re-run).
  - Scheduled upgrade row   → dispatches the upgrade inline through the
                              same pipeline the service uses (backup,
                              checkout, migrate, restart, health-check,
                              rollback on failure).
  - Crashed upgrade flag    → reconciles, re-probes, re-dispatches.
  - Live upgrade running    → refuses (points at journalctl).
  - Pre-1.0 database        → refuses (points at the manual upgrade path).

To upgrade an existing install, schedule the target version first:

  ./sb upgrade schedule v2026.03.1
  ./sb install                  # dispatches the scheduled upgrade

Or let the systemd upgrade service pick it up on its next tick.

Example first install (interactive):
  ./sb install

Example scripted install (non-interactive):
  # Pre-create .env.config, then:
  ./sb install --non-interactive

Example with statbus.nso.eu domain:
  ./sb install
  # Prompts for: mode=standalone, domain=statbus.nso.eu, name=StatBus, code=nso`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runInstall()
	},
}

func init() {
	installCmd.Flags().BoolVar(&nonInteractive, "non-interactive", false,
		"Run without prompts (requires .env.config to exist)")
	installCmd.Flags().StringVar(&trustGitHubUser, "trust-github-user", "",
		"Auto-trust this GitHub user's signing key (non-interactive, for scripted installs)")
	installCmd.Flags().BoolVar(&insideActiveUpgrade, "inside-active-upgrade", false,
		"Internal: set by the upgrade service when spawning install as a post-upgrade fixup. Operators must not pass this.")
	// Hide the internal flag from --help; it's a contract between service and child install, not a user-facing knob.
	_ = installCmd.Flags().MarkHidden("inside-active-upgrade")
	rootCmd.AddCommand(installCmd)
}

// step represents one installation step with an idempotency check.
type step struct {
	name  string
	check func(dir string) bool // returns true if step is already done
	run   func(dir string) error
}

// acquireOrBypass enforces the install ↔ upgrade-service mutual exclusion.
//
// Both the upgrade service and `./sb install` write the same marker file
// (tmp/upgrade-in-progress.json) via O_CREATE|O_EXCL — the kernel
// guarantees exactly one writer wins. The Holder field distinguishes
// service-vs-install ownership; recoverFromFlag uses Holder to decide
// what cleanup is needed when a writer crashed (DB reconciliation for
// service, file-removal-only for install).
//
// When `bypass` is true, the caller is the upgrade service's own
// post-upgrade fixup — the parent service already holds the flag, so the
// child install neither acquires nor releases. Otherwise:
//   - No flag → atomic acquire succeeds; returns a release function the
//     caller must defer.
//   - Flag exists, live PID → returns a formatted error guiding the
//     operator to wait.
//   - Flag exists, dead PID → unreachable: install.Detect returns
//     StateCrashedUpgrade before acquireOrBypass is called, so the
//     stale-flag path is handled by RecoverFromFlag, not here.
//
// Returns (releaseFunc, nil) on success; (nil-no-op, err) on contention.
func acquireOrBypass(installDir string, bypass bool) (release func(), err error) {
	if bypass {
		// Verify-only diagnostic. The parent's flag is on disk; we don't
		// touch it. Print holder info for the audit log.
		if flag, _, rerr := upgrade.ReadFlagFile(installDir); rerr == nil && flag != nil {
			fmt.Printf("Upgrade mutex bypass honored (--inside-active-upgrade). Flag owned by PID %d (holder=%s), invoked_by=%s.\n",
				flag.PID, flag.Holder, flag.InvokedBy)
		} else {
			// A17: OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED (unexpected-bypass)
			log.Printf(
				"INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A17 — unexpected-bypass): --inside-active-upgrade set but no upgrade flag found; proceeding (install.go:%d, pid=%d)",
				thisLine(), os.Getpid())
		}
		return func() {}, nil
	}

	invokedBy := "operator"
	if u := os.Getenv("USER"); u != "" {
		invokedBy = "operator:" + u
	}
	lock, err := upgrade.AcquireInstallFlag(installDir, invokedBy)
	if err != nil {
		return nil, err
	}
	// Keep the FlagLock alive until the install completes. The returned
	// closure is deferred by the caller (runInstall) so normal exit and
	// all error paths release the flock. Crash-exit releases it via
	// kernel fd teardown.
	return func() { upgrade.ReleaseInstallFlag(lock) }, nil
}

// runInstall is the entry point for `./sb install`. It is safe to run while
// an upgrade service is active on the same host because of the mutex check
// below: if the upgrade service has written tmp/upgrade-in-progress.json
// (which it does before any destructive step in executeUpgrade), this function
// refuses to proceed. The only exception is the service's own post-upgrade
// fixup, which passes --inside-active-upgrade / STATBUS_INSIDE_ACTIVE_UPGRADE=1
// to signal "I am the active upgrade, not a conflicting actor."
func runInstall() (installErr error) {
	// Warn if running as root — the upgrade service is a user-level systemd unit now,
	// running as root would create files owned by root in the project dir.
	if os.Geteuid() == 0 {
		fmt.Println("Warning: running as root. The upgrade service is a user-level systemd unit.")
		fmt.Println("Run as the application user instead: ./sb install")
		fmt.Println()
	}

	fmt.Println("StatBus Installation")
	fmt.Println("====================")
	fmt.Println()

	// Detect non-interactive from stdin if not explicitly set
	if !nonInteractive {
		if fi, err := os.Stdin.Stat(); err == nil {
			if fi.Mode()&os.ModeCharDevice == 0 {
				nonInteractive = true
			}
		}
	}

	// Resolve project dir early — the upgrade-in-progress flag lives under it.
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot determine home directory (HOME unset?): %w", err)
	}
	installDir := filepath.Join(home, "statbus")

	// Register the panic-capturing defer FIRST so it runs LAST during unwind
	// and catches panics from every later defer, including the post-completion
	// block. Any `INVARIANT X violated: ...` panic (class=panic-regression,
	// e.g., A6) gets its name written to install-terminal.txt before the Go
	// runtime prints the stack trace.
	defer capturePanicInvariant(installDir)

	// === Upgrade mutex acquire ===
	// Atomically claim tmp/upgrade-in-progress.json (Holder="install") so
	// any other actor — running upgrade service, another install — sees us
	// and aborts. ReleaseInstallFlag in defer cleans up on every exit path.
	// The ONLY caller allowed to bypass is the upgrade service itself
	// (service.go:executeUpgrade spawns install as a post-upgrade fixup
	// with --inside-active-upgrade + env var set; the service already holds
	// the flag for that exec, so the child must not try to acquire it).
	bypass := insideActiveUpgrade || os.Getenv("STATBUS_INSIDE_ACTIVE_UPGRADE") == "1"

	// === State detection + dispatch ===
	// Detect reads the install directory + DB to classify the install state.
	// In the bypass path the parent upgrade service already knows; skip
	// detection to avoid probing the DB mid-upgrade.
	//
	// Dispatch policy:
	//   StateLiveUpgrade      → refuse BEFORE acquireOrBypass so the message
	//                           is an authoritative refusal, not a flock error.
	//   StateScheduledUpgrade → hand off to executeUpgrade (the upgrade
	//                           service's pipeline) WITHOUT acquiring the
	//                           install flag — executeUpgrade writes its own
	//                           HolderService flag internally before any
	//                           destructive step. This is Option A of the
	//                           flag-lock ownership design: ownership transfer
	//                           matches the flock primitive.
	//   StateCrashedUpgrade   → run RecoverFromFlag (clears stale flag,
	//                           reconciles the DB row), re-detect, re-dispatch.
	//                           The re-detect may land us in any other state.
	//   StateLegacyNoUpgradeTable → refuse with a pointer to #65.6 (the
	//                           pre-1.0 cascade lands there).
	//   all other states      → fall through to acquireOrBypass + step-table.
	var detectedState install.State
	if !bypass {
		state, detail, derr := install.Detect(installDir, version)
		if derr != nil {
			log.Printf("State detection failed (continuing with step-table fallback): %v", derr)
		} else {
			detectedState = state
			logInstallState(state, detail)
			if state == install.StateCrashedUpgrade {
				if err := runCrashRecovery(installDir); err != nil {
					return fmt.Errorf("crash recovery: %w", err)
				}
				state, detail, derr = install.Detect(installDir, version)
				if derr != nil {
					return fmt.Errorf("re-detect after recovery: %w", derr)
				}
				detectedState = state
				fmt.Printf("  State after recovery: %s (target=%s)\n", state, detail.TargetVersion)
			}
			if handled, err := dispatchInstallState(installDir, state, detail); handled {
				return err
			}
		}
	}

	// Pre-flight: if --trust-github-user is set, trust that user's signing
	// key before any validation. Skips the GitHub fetch if a valid key is
	// already configured (idempotent — no API call on re-run).
	if !bypass && trustGitHubUser != "" {
		cfgPath := filepath.Join(installDir, ".env.config")
		if _, statErr := os.Stat(cfgPath); statErr == nil {
			if checkSignersDone(installDir) {
				fmt.Printf("Trusted signer already configured and verified — skipping GitHub fetch\n")
			} else {
				f, loadErr := dotenv.Load(cfgPath)
				if loadErr == nil {
					fmt.Printf("Trusting GitHub user %s (--trust-github-user)...\n", trustGitHubUser)
					if err := trustSignerNonInteractive(trustGitHubUser, f); err != nil {
						log.Printf("Could not trust %s (continuing, operator may add manually): %v", trustGitHubUser, err)
					} else {
						if err := f.Save(); err != nil {
							log.Printf("Could not save .env.config after adding trusted signer: %v", err)
						}
					}
				}
			}
		}
	}

	// Pre-flight: on existing installs (.env.config exists), require at
	// least one trusted signer BEFORE doing any work. Fresh installs skip
	// this — .env.config doesn't exist yet (step 5 creates it, step 13
	// prompts for signers). Re-installs that removed their signer get a
	// fast, actionable failure instead of wasting 2 minutes on steps 1-12.
	if !bypass {
		cfgPath := filepath.Join(installDir, ".env.config")
		if _, statErr := os.Stat(cfgPath); statErr == nil && !checkSignersDone(installDir) {
			if nonInteractive {
				return fmt.Errorf("no valid trusted signers configured.\n" +
					"  The upgrade service requires at least one trusted signer that can verify commit signatures.\n" +
					"  Pre-configure before running install:\n" +
					"    ./sb upgrade trust-key add <github-username>\n" +
					"  Or pass --trust-github-user <username> to install.\n" +
					"  Then re-run the install.")
			}
			fmt.Println("No valid trusted signers configured. You must approve at least one signer before the install can proceed.")
			if err := runTrustSigners(installDir); err != nil {
				return err
			}
		}
	}

	releaseFlag, err := acquireOrBypass(installDir, bypass)
	if err != nil {
		return err
	}
	defer releaseFlag()

	// Pre-flight: check disk space (default 100 GB, override with STATBUS_MIN_DISK_GB)
	minDiskGB := uint64(100)
	if v := os.Getenv("STATBUS_MIN_DISK_GB"); v != "" {
		if n, err := strconv.ParseUint(v, 10, 64); err == nil {
			minDiskGB = n
		}
	}
	if freeBytes, err := upgrade.DiskFree("."); err == nil {
		freeGB := freeBytes / (1024 * 1024 * 1024)
		if freeGB < minDiskGB {
			return fmt.Errorf("insufficient disk space: %d GB free (need at least %d GB for database, images, and backups).\n"+
				"  For smaller installations, override with: STATBUS_MIN_DISK_GB=%d ./sb install", freeGB, minDiskGB, freeGB)
		}
		fmt.Printf("Disk space: %d GB free\n", freeGB)
	}

	// --- Install-invocation / upgrade row lifecycle ---
	// Capability separation: install runs the step-table; the upgrade daemon
	// owns public.upgrade (discovery + ledger).
	//
	// Log layout by detected state:
	//   StateNothingScheduled        → tmp/install-logs/<ver>-<ts>.log
	//                                  (no row authored; system_info stamps
	//                                  install_last_log_relative_file_path +
	//                                  install_last_at on success; daemon
	//                                  materializes the public.upgrade row on
	//                                  its next tick via NOTIFY upgrade_check)
	//   StateFresh/HalfConfigured/
	//   StateDBUnreachable           → tmp/upgrade-logs/0-<ver>-<ts>.log
	//                                  (fresh row authored via rowID=0 INSERT
	//                                  path in completeInstallUpgradeRow,
	//                                  stamping log_relative_file_path on the
	//                                  new row)
	//
	// The daemon / scheduled-upgrade path uses executeUpgrade's own NewUpgradeLog
	// with a real row id — those calls happen elsewhere in the upgrade service.
	// Install itself never authors an in_progress row under A20 capability
	// separation, so upgradeRowID stays 0 for the completion-defer path.
	var upgradeRowID int64

	// Create the run log so the admin UI can show what happened. Always create
	// for real installs (not bypass, not dev) — even for fresh installs where
	// the DB doesn't exist yet. Must be registered BEFORE the post-completion
	// defer so the pipe stays active during completion/supersede/retention
	// prints (defers are LIFO — this one drains last).
	var installLog *upgrade.ProgressLog
	var origStdout *os.File
	var pipeW *os.File
	var teeDone chan struct{}
	if !bypass && version != "dev" {
		if detectedState == install.StateNothingScheduled {
			installLog = upgrade.NewInstallLog(installDir, version, time.Now().UTC())
		} else {
			installLog = upgrade.NewUpgradeLog(installDir, upgradeRowID, version, time.Now().UTC())
		}
		// Tee stdout to the log file for the entire install duration.
		origStdout = os.Stdout
		pr, pw, pipeErr := os.Pipe()
		if pipeErr == nil {
			pipeW = pw
			os.Stdout = pw
			teeDone = make(chan struct{})
			go func() {
				defer close(teeDone)
				buf := make([]byte, 4096)
				for {
					n, readErr := pr.Read(buf)
					if n > 0 {
						origStdout.Write(buf[:n])
						installLog.File().Write(buf[:n])
					}
					if readErr != nil {
						break
					}
				}
			}()
		}
	}
	defer func() {
		if pipeW != nil {
			pipeW.Close()
			<-teeDone
			os.Stdout = origStdout
		}
		if installLog != nil {
			installLog.Close()
		}
	}()

	if !bypass && version != "dev" {
		defer func() {
			// Post-completion DB ops use pgx (parameter binding, no shell
			// escaping). The connection goes through Caddy's L4 proxy on
			// the loopback address — Caddy is guaranteed running because
			// the step-table's "Services" step completed before we get here.
			conn, connErr := connectInstallDB(installDir)
			if conn != nil {
				defer conn.Close(context.Background())
			}

			// A3: POST_COMPLETION_DB_REACHABLE_AFTER_STEP_TABLE —
			// only fires when the primary install succeeded. If installErr is
			// already set we fall through to the cleanup branch; A10/A11 emit
			// log-only breadcrumbs if conn/UPDATE fail.
			if installErr == nil && connErr != nil {
				fmt.Fprintf(os.Stderr,
					"INVARIANT POST_COMPLETION_DB_REACHABLE_AFTER_STEP_TABLE violated: pgx.Connect failed after healthy step-table: %v (install.go:%d, pid=%d)\n",
					connErr, thisLine(), os.Getpid())
				markTerminal(installDir, "POST_COMPLETION_DB_REACHABLE_AFTER_STEP_TABLE",
					fmt.Sprintf("pgx.Connect failed after healthy step-table: %v", connErr))
				installErr = fmt.Errorf("POST_COMPLETION_DB_REACHABLE_AFTER_STEP_TABLE: %w", connErr)
				return
			}

			if installErr == nil {
				logRelPath := ""
				if installLog != nil {
					logRelPath = installLog.RelPath()
				}
				if err := completeInstallUpgradeRow(installDir, conn, logRelPath); err != nil {
					installErr = err
					return
				}
				// Notify the daemon so it picks up any newly available releases.
				// Best-effort: periodic discovery tick recovers on drop.
				if _, err := conn.Exec(context.Background(), "NOTIFY upgrade_check"); err != nil {
					log.Printf(
						"INVARIANT NOTIFY_UPGRADE_CHECK_BEST_EFFORT_LOGGED violated (audit-only): NOTIFY upgrade_check failed post-install: %v (install.go:%d, pid=%d) — next daemon tick will recover",
						err, thisLine(), os.Getpid())
				}
				// Stamp install-invocation tracking in public.system_info.
				// Mirrors the support.go install_last_error* upsert pattern.
				// Best-effort: a failure here is a log-only breadcrumb — the
				// admin UI simply shows stale values until the next install.
				stampInstallInvocationTracking(conn, logRelPath)
				runInstallSupersede(conn, installDir)
				runInstallRetention(conn, upgradeRowID)
				runInstallCallback(installDir)
			}

			// A21: FAILED_INSTALL_HAS_AUDIT_TRAIL — secondary audit breadcrumb
			// for failures where no upgrade row was ever created (fresh install
			// that died before DB reachable; upgradeRowID stays 0 for every
			// current caller under capability separation). The primary
			// `installErr` return already drives the shell fail-fast; this
			// log-only line guarantees the bundle has a greppable invariant
			// anchor even when the DB has no row for SSB triage to grep against.
			if installErr != nil && upgradeRowID == 0 {
				log.Printf(
					"INVARIANT FAILED_INSTALL_HAS_AUDIT_TRAIL violated (audit-only): install failed with no upgrade row (detectedState=%s): %v — support bundle's install.log has full context (install.go:%d, pid=%d)",
					detectedState, installErr, thisLine(), os.Getpid())
			}
		}()
	}

	steps := []step{
		{"Prerequisites", checkPrereqDone, runPrereq},
		{"Repository", checkRepoDone, runCloneRepo},
		{"Binary", checkBinaryDone, runInstallBinary},
		{"Configuration", checkConfigDone, runCreateConfig},
		{"Credentials", checkCredsDone, runCreateCreds},
		{"Generated env", checkEnvDone, runGenerateEnv},
		{"Images", checkImagesDone, runPullImages},
		{"Services", checkServicesDone, runStartServices},
		// "Database sessions" gates Seed + Migrations. Recovers from
		// Stage B of the rune.statbus.org wedge: prior systemd-killed
		// migrate-up loops leak postgres backends until max_connections
		// is exhausted, blocking subsequent migrate-up attempts. On a
		// healthy install this is a no-op: WHERE clause matches zero
		// rows, recheck passes immediately.
		{"Database sessions", checkSessionsClean, cleanOrphanSessions},
		{"Seed", checkSeedRestored, runSeedRestore},
		{"Migrations", checkMigrationsDone, runMigrations},
		{"JWT secret", checkJWTDone, runLoadJWT},
		{"Users", checkUsersDone, runCreateUsers},
		{"Trusted signers", checkSignersDone, runTrustSigners},
		{"Upgrade service", checkServiceDone, runInstallService},
	}

	total := len(steps)
	allDone := true

	for i, s := range steps {
		prefix := fmt.Sprintf("[%d/%d] %-20s", i+1, total, s.name)

		if s.check(installDir) {
			fmt.Printf("%s OK\n", prefix)
			continue
		}

		allDone = false
		fmt.Printf("%s RUNNING\n", prefix)

		if err := s.run(installDir); err != nil {
			fmt.Printf("%s FAILED: %v\n", prefix, err)
			if i < total-1 {
				fmt.Printf("\nFix the issue and re-run: ./sb install\n")
				fmt.Printf("(Steps 1-%d will be skipped automatically)\n", i)
			}
			return err
		}

		fmt.Printf("%s DONE\n", prefix)
	}

	fmt.Println()
	if allDone {
		fmt.Println("All steps complete. Nothing to do.")
	} else {
		fmt.Println("Installation complete!")
		fmt.Println("=====================")
		if f, err := dotenv.Load(filepath.Join(installDir, ".env.config")); err == nil {
			if domain, ok := f.Get("SITE_DOMAIN"); ok {
				fmt.Printf("Visit: https://%s\n", domain)
			}
		}
		fmt.Printf("Management: cd %s && ./sb --help\n", installDir)
	}

	return nil
}

// ── Step checks (return true if step is already done) ──

func checkPrereqDone(_ string) bool {
	_, dockerErr := exec.LookPath("docker")
	_, gitErr := exec.LookPath("git")
	composeErr := exec.Command("docker", "compose", "version").Run()
	return dockerErr == nil && gitErr == nil && composeErr == nil
}

func checkRepoDone(dir string) bool {
	gitDir := filepath.Join(dir, ".git")
	_, err := os.Stat(gitDir)
	return err == nil
}

func checkBinaryDone(dir string) bool {
	sb := filepath.Join(dir, "sb")
	info, err := os.Stat(sb)
	return err == nil && info.Mode().Perm()&0111 != 0
}

func checkConfigDone(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, ".env.config"))
	return err == nil
}

func checkCredsDone(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, ".env.credentials"))
	return err == nil
}

func checkEnvDone(dir string) bool {
	// Always regenerate .env — code checkout may change variable names
	// (e.g., NEXT_PUBLIC_* → PUBLIC_*) and .env must match docker-compose.
	return false
}

func checkImagesDone(dir string) bool {
	cmd := exec.Command("docker", "compose", "--profile", "all", "images", "-q")
	cmd.Dir = dir
	out, err := cmd.Output()
	// If we get at least 4 image IDs, images are available
	return err == nil && len(strings.Split(strings.TrimSpace(string(out)), "\n")) >= 4
}

func checkServicesDone(dir string) bool {
	cmd := exec.Command("docker", "compose", "ps", "--format", "{{.Health}}", "--filter", "name=db")
	cmd.Dir = dir
	out, err := cmd.Output()
	return err == nil && strings.Contains(string(out), "healthy")
}

func checkMigrationsDone(dir string) bool {
	// Done iff there are no pending migration files vs db.migration.
	// migrate.HasPending compares disk (migrations/*.up.sql) against the
	// applied versions table; single source of truth shared with `migrate up`.
	//
	// Historical note: this used to return true whenever MAX(version)>0 — i.e.
	// "any migration applied = all done" — which silently skipped newer
	// migrations on upgrade. That bug wedged five cloud servers on v2026.03.1.
	pending, err := migrate.HasPending(dir)
	if err != nil {
		// On error, fall through to runMigrations (it will surface the error
		// cleanly). "Done" would hide a real problem.
		return false
	}
	return !pending
}

func checkJWTDone(dir string) bool {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	args := append(prefix, "-t", "-A", "-c",
		"SELECT COUNT(*) FROM auth.secrets WHERE key = 'jwt_secret' AND value != '';")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	return err == nil && strings.TrimSpace(string(out)) == "1"
}

func checkUsersDone(dir string) bool {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	args := append(prefix, "-t", "-A", "-c",
		"SELECT COUNT(*) FROM auth.\"user\";")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	count := strings.TrimSpace(string(out))
	return count != "0" && count != ""
}

func checkServiceDone(dir string) bool {
	if runtime.GOOS != "linux" {
		return true // Skip on non-Linux
	}
	instance := serviceInstance(dir)
	if instance == "" {
		return false
	}
	// User-level systemd service — no root needed to manage.
	// Check is-active (running), not just is-enabled (starts on boot).
	cmd := exec.Command("systemctl", "--user", "is-active", instance)
	return cmd.Run() == nil
}

// serviceInstance returns the systemd instance name, e.g. "statbus-upgrade@statbus_dev.service"
// (cloud, user is statbus_<slot>) or "statbus-upgrade@statbus.service" (standalone, user is statbus).
// The instance suffix after `@` is the deployment user — matches the convention already used
// by upgrade.go's channel-set restart, and works on both deployment shapes.
func serviceInstance(_ string) string {
	u := os.Getenv("USER")
	if u == "" {
		return ""
	}
	return fmt.Sprintf("statbus-upgrade@%s.service", u)
}

// ── Step runners ──

func runPrereq(_ string) error {
	return checkPrerequisites()
}

func runCloneRepo(dir string) error {
	if err := runCmd("git", "clone", "--depth", "1",
		"https://github.com/statisticsnorway/statbus.git", dir); err != nil {
		return err
	}
	// Configure deploy branch fetch refspec if slot code is known
	configureDeployFetch(dir)
	return nil
}

// configureDeployFetch adds the slot-specific deploy branch to the git fetch refspec.
// e.g., for slot "dev": +refs/heads/ops/cloud/deploy/dev:refs/remotes/origin/ops/cloud/deploy/dev
// Idempotent — safe to call on existing repos.
func configureDeployFetch(dir string) {
	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return // no config yet, will be called again after config is created
	}
	code, ok := f.Get("DEPLOYMENT_SLOT_CODE")
	if !ok || code == "" {
		return
	}

	branch := fmt.Sprintf("ops/cloud/deploy/%s", code)
	refspec := fmt.Sprintf("+refs/heads/%s:refs/remotes/origin/%s", branch, branch)

	// Remove any stale devops/* refspecs — they refer to branches renamed
	// during R1.1 and every subsequent `git fetch` errors on them. Shared
	// helper so `./sb upgrade apply-latest` can self-heal before its own
	// fetch without duplicating the cleanup logic.
	upgrade.CleanStaleRefspecs(dir)

	cmd := exec.Command("git", "config", "--get-all", "remote.origin.fetch")
	cmd.Dir = dir
	out, _ := cmd.Output()

	if strings.Contains(string(out), refspec) {
		return // already configured
	}

	// Check if the branch exists on the remote before adding
	check := exec.Command("git", "ls-remote", "--exit-code", "--heads", "origin", branch)
	check.Dir = dir
	if check.Run() != nil {
		return // branch doesn't exist on remote, skip
	}

	add := exec.Command("git", "config", "--add", "remote.origin.fetch", refspec)
	add.Dir = dir
	add.Run()
}

func runInstallBinary(dir string) error {
	sbDst := filepath.Join(dir, "sb")
	sbSrc, err := os.Executable()
	if err != nil {
		return fmt.Errorf("find current binary: %w", err)
	}
	// Don't copy if we're already running from the install dir
	if sbSrc == sbDst {
		return nil
	}
	if err := copyFile(sbSrc, sbDst); err != nil {
		return fmt.Errorf("copy binary: %w", err)
	}
	return os.Chmod(sbDst, 0755)
}

func runCreateConfig(dir string) error {
	cfgPath := filepath.Join(dir, ".env.config")

	if nonInteractive {
		return fmt.Errorf(".env.config not found\n\n" +
			"  Create .env.config with at minimum:\n" +
			"    DEPLOYMENT_SLOT_CODE=xx\n" +
			"    CADDY_DEPLOYMENT_MODE=standalone\n" +
			"    SITE_DOMAIN=statbus.nso.eu\n" +
			"\n  Then re-run: ./sb install --non-interactive")
	}

	fmt.Println()
	mode := prompt("  Deployment mode (development/standalone/private)", "standalone")
	domain := prompt("  Domain name", "statbus.nso.eu")
	name := prompt("  Display name", "StatBus")
	code := prompt("  Deployment code (short, lowercase)", "local")

	cfgContent := fmt.Sprintf(`DEPLOYMENT_SLOT_NAME=%s
DEPLOYMENT_SLOT_CODE=%s
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=%s
SITE_DOMAIN=%s
`, name, code, mode, domain)

	return os.WriteFile(cfgPath, []byte(cfgContent), 0644)
}

func runCreateCreds(dir string) error {
	// sb config generate creates .env.credentials if missing
	sb := filepath.Join(dir, "sb")
	return runCmdDir(dir, sb, "config", "generate")
}

func runGenerateEnv(dir string) error {
	// Align with latest code — but only if we're on master (not a tag/detached HEAD).
	// The upgrade service checks out a specific commit; install should respect that.
	// Servers on ops branches (e.g. ops/cloud/deploy/no) also need to align with master.
	branchOut, err := upgrade.RunCommandOutput(dir, "git", "symbolic-ref", "--short", "HEAD")
	branch := strings.TrimSpace(branchOut)
	if err == nil && (branch == "master" || strings.HasPrefix(branch, "ops/")) {
		if err := runCmdDir(dir, "git", "fetch", "origin", "master"); err != nil {
			log.Printf("git fetch origin master failed (continuing with existing checkout): %v", err)
		}
		if err := runCmdDir(dir, "git", "checkout", "master"); err != nil {
			log.Printf("git checkout master failed (continuing with existing checkout): %v", err)
		}
		if err := runCmdDir(dir, "git", "merge", "--ff-only", "origin/master"); err != nil {
			log.Printf("git merge origin/master failed (continuing with existing checkout): %v", err)
		}
	}

	// Migrate .env.config paths from devops/ → ops/ (one-time, idempotent)
	migrateConfigPaths(dir)

	sb := filepath.Join(dir, "sb")
	if err := runCmdDir(dir, sb, "config", "generate"); err != nil {
		return err
	}
	// Now that config exists, ensure deploy branch fetch is configured
	configureDeployFetch(dir)
	// Create backup directory for upgrade service (systemd unit expects it)
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot determine home directory (HOME unset?): %w", err)
	}
	backupDir := filepath.Join(home, "statbus-backups")
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		log.Printf("Could not create backup dir %s: %v", backupDir, err)
	}
	// Create maintenance directory for Caddy volume mount
	maintDir := filepath.Join(home, "statbus-maintenance")
	if err := os.MkdirAll(maintDir, 0755); err != nil {
		log.Printf("Could not create maintenance dir %s: %v", maintDir, err)
	}
	return nil
}

func runPullImages(dir string) error {
	// Try pull first (pre-built from ghcr.io)
	if err := runCmdDir(dir, "docker", "compose", "--profile", "all", "pull"); err != nil {
		// Fall back to build for services without pre-built images
		fmt.Println("  Pull incomplete, building remaining images locally...")
		return runCmdDir(dir, "docker", "compose", "--profile", "all", "build")
	}
	return nil
}

func runStartServices(dir string) error {
	return runCmdDir(dir, "docker", "compose", "--profile", "all", "up", "-d")
}

// checkSessionsClean returns true iff the database is reachable AND its
// session pool is in a healthy state. Returns false if any of:
//   - DB is unreachable (caller's runStartServices should have started
//     it, but the connection pool may still be exhausted)
//   - active backend count is ≥ 80% of max_connections (saturation
//     headroom — leaves room for migrate-up + reserved superuser slots)
//   - any backend > 5 minutes old is wedged on a TRUNCATE/INSERT/CALL
//     against a `statistical_*` table (heuristic for "leaked from a
//     prior crashed upgrade")
//
// Recovery sequence: Stage A (systemd timeout kills migrate-up) leaves
// postgres backends running their TRUNCATE/INSERT/CALL until the
// backends notice their dead client. After enough cycles
// max_connections is exhausted, blocking the next migrate-up. This
// check is the gate that triggers cleanOrphanSessions when needed.
func checkSessionsClean(dir string) bool {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	args := append(prefix, "-t", "-A", "-c", `
		WITH s AS (
			SELECT
				(SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn,
				(SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()) AS active,
				(SELECT count(*) FROM pg_stat_activity
				  WHERE datname = current_database()
				    AND state IN ('active', 'idle in transaction')
				    AND query_start < now() - interval '5 minutes'
				    AND (query ILIKE '%TRUNCATE %statistical_%'
				         OR query ILIKE '%INSERT INTO %statistical_%'
				         OR query ILIKE '%CALL %statistical_%')
				) AS leaked
		)
		SELECT
			active::text || '/' || max_conn::text AS pool,
			(active::numeric < (max_conn::numeric * 0.8) AND leaked = 0)::text AS healthy
		FROM s;`)
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		return false
	}
	// Format: "<active>/<max>|<healthy>"
	line := strings.TrimSpace(string(out))
	parts := strings.Split(line, "|")
	if len(parts) != 2 {
		return false
	}
	return parts[1] == "t"
}

// cleanOrphanSessions terminates leaked backends from prior crashed
// upgrade attempts so the next migrate-up has free connection slots.
//
// Connects via the standard psql path (which uses
// `superuser_reserved_connections` if ordinary slots are full —
// postgres reserves 3 slots for superuser by default, enough to acquire
// a connection even when normal slots are exhausted).
//
// Targets two backend classes:
//   1. Any backend > 2 minutes old in the current database (other than
//      this connection) — likely orphaned by a SIGKILLed migrate-up
//      subprocess.
//   2. Any backend running a query touching statistical_history* —
//      these are the heavy migrations that get caught in the timeout
//      loop on at-scale data.
//
// 2-second sleep + recheck after termination. If the pool is still
// saturated afterwards, returns an error pointing at the upgrade
// service journal — we do NOT silently retry, because that would hide
// a real problem (e.g. genuine load, or a crashed cleanup).
//
// Idempotent: on a healthy system the WHERE clause matches zero rows
// and the recheck passes cleanly. Self-targeting is excluded via
// `pid <> pg_backend_pid()`.
func cleanOrphanSessions(dir string) error {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return fmt.Errorf("psql command: %w", err)
	}

	args := append(prefix, "-c", `
		SELECT pg_terminate_backend(pid), pid, query_start, left(query, 80) AS query
		  FROM pg_stat_activity
		 WHERE datname = current_database()
		   AND pid <> pg_backend_pid()
		   AND (
			   -- Orphans from killed migrate-up subprocesses
			   (state IN ('active', 'idle in transaction')
			    AND query_start < now() - interval '2 minutes')
			   OR
			   -- Backends still wedged on the upgrade's heavy migration
			   query ILIKE '%statistical_history%'
		   );`)
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("pg_terminate_backend: %w", err)
	}

	// Give postgres a moment to actually free the slots after
	// pg_terminate_backend. Slot release is async wrt the SQL return.
	time.Sleep(2 * time.Second)

	if !checkSessionsClean(dir) {
		return fmt.Errorf(
			"connection pool still saturated after cleanOrphanSessions; " +
				"check `journalctl --user -u 'statbus-upgrade@*'` for the underlying cause")
	}
	return nil
}

// checkSeedRestored returns true if the database already has migrations
// (re-install scenario — seed restore would be destructive).
// Returns false only for truly fresh installs where the DB is empty.
//
// Intent: the seed is a FAST PATH for fresh installs only. Restoring
// over an existing database drops objects while migration records survive,
// leaving the DB in an inconsistent state.
func checkSeedRestored(dir string) bool {
	// If services aren't running yet, we can't check the DB.
	// Return true to skip — the Services step must run first.
	if !checkServicesDone(dir) {
		return true
	}

	// Services are running. Wait for DB to be healthy, then check migrations.
	// If we can't reach the DB after 30 seconds, FAIL HARD — don't silently
	// fall through and restore a seed over an existing database.
	for attempt := 0; attempt < 15; attempt++ {
		if checkMigrationsDone(dir) {
			return true // DB has migrations — do NOT restore seed
		}
		if attempt < 14 {
			time.Sleep(2 * time.Second)
		}
	}

	// DB is reachable (services running) but has no migrations.
	// This is a genuinely fresh database — seed restore is appropriate.
	return false
}

// runSeedRestore fetches the seed from origin/db-seed and restores
// it into the database. This makes `migrate up` fast — only migrations newer
// than the seed need to run.
func runSeedRestore(dir string) error {
	sb := filepath.Join(dir, "sb")

	// Fetch seed from remote.
	fmt.Println("  Fetching seed from origin/db-seed...")
	if err := runCmdDir(dir, sb, "db", "seed", "fetch"); err != nil {
		// Not fatal — fresh repos or private forks may not have the branch.
		fmt.Println("  No seed available — will run all migrations")
		return nil
	}

	// Restore into the default database (configured in .env).
	fmt.Println("  Restoring seed...")
	if err := runCmdDir(dir, sb, "db", "seed", "restore"); err != nil {
		// Not fatal — migrate up will run all migrations from scratch.
		fmt.Println("  Seed restore failed — will run all migrations")
		return nil
	}

	return nil
}

func runMigrations(dir string) error {
	sb := filepath.Join(dir, "sb")
	return runCmdDir(dir, sb, "migrate", "up", "--verbose")
}

func runLoadJWT(dir string) error {
	// Reuse the ensureJWTSecret function from users.go
	return ensureJWTSecret(dir)
}

func runCreateUsers(dir string) error {
	sb := filepath.Join(dir, "sb")
	return runCmdDir(dir, sb, "users", "create")
}

func checkSignersDone(dir string) bool {
	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return false
	}

	// Collect signer lines — we need both existence and content for verification.
	var signerLines []string
	for _, key := range f.Keys() {
		if !strings.HasPrefix(key, trustedSignerPrefix) {
			continue
		}
		val, _ := f.Get(key)
		if val == "" {
			continue
		}
		name := strings.TrimPrefix(key, trustedSignerPrefix)
		// allowed_signers format: <principal> <key>
		signerLines = append(signerLines, fmt.Sprintf("%s %s", name, val))
	}
	if len(signerLines) == 0 {
		return false
	}

	// Key(s) exist — verify they actually work against HEAD's signature.
	// Write a temporary allowed-signers file and run git verify-commit.
	// If HEAD is unsigned (development), accept key existence alone.
	tmpDir := filepath.Join(dir, "tmp")
	os.MkdirAll(tmpDir, 0755)
	allowedSignersPath := filepath.Join(tmpDir, "allowed-signers")
	if err := os.WriteFile(allowedSignersPath, []byte(strings.Join(signerLines, "\n")+"\n"), 0644); err != nil {
		return true // can't write temp file — don't block install
	}

	verifyCmd := exec.Command("git", "-C", dir, "-c",
		fmt.Sprintf("gpg.ssh.allowedSignersFile=%s", allowedSignersPath),
		"verify-commit", "HEAD")
	out, verifyErr := verifyCmd.CombinedOutput()
	if verifyErr != nil {
		if strings.Contains(string(out), "no signature found") {
			// HEAD is unsigned (development) — can't verify key, accept existence
			return true
		}
		// Signed commit but verification failed — wrong key configured.
		// Remove the invalid key(s) so step 13 starts clean.
		fmt.Printf("  Configured signing key does not verify HEAD commit — removing invalid key(s)\n")
		for _, key := range f.Keys() {
			if strings.HasPrefix(key, trustedSignerPrefix) {
				f.Delete(key)
			}
		}
		if err := f.Save(); err != nil {
			log.Printf("Could not save .env.config after removing invalid keys: %v", err)
		}
		return false
	}
	return true
}

func runTrustSigners(dir string) error {
	if nonInteractive {
		return fmt.Errorf("no trusted signers configured (non-interactive mode cannot prompt).\n" +
			"  The upgrade service requires at least one trusted signer to verify release signatures.\n" +
			"  Pre-configure before running install:\n" +
			"    ./sb upgrade trust-key add <github-username>\n" +
			"  Then re-run: ./sb install --non-interactive")
	}

	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return fmt.Errorf("load .env.config: %w", err)
	}

	reader := bufio.NewReader(os.Stdin)
	defaultSigner := "jhf"

	fmt.Println()
	fmt.Println("  StatBus recommends trusting the following release signer:")
	fmt.Printf("    %s (Jorgen H. Fjeld) -- https://github.com/%s\n", defaultSigner, defaultSigner)

	trusted, err := trustSignerInteractive(defaultSigner, f, reader)
	if err != nil {
		log.Printf("Could not fetch keys for %s: %v", defaultSigner, err)
		fmt.Println("  You can add trusted signers later with: ./sb upgrade trust-key add <github-username>")
		return nil // Non-fatal: don't block installation
	}
	if !trusted {
		fmt.Println("  Skipped. You can add trusted signers later with: ./sb upgrade trust-key add <github-username>")
		return nil
	}

	// Offer to add additional signers
	for {
		fmt.Print("\n  Add additional trusted signer? (GitHub username, or Enter to skip): ")
		username, _ := reader.ReadString('\n')
		username = strings.TrimSpace(username)
		if username == "" {
			break
		}

		// Reload the file in case trustSignerInteractive saved changes
		f, err = dotenv.Load(cfgPath)
		if err != nil {
			return fmt.Errorf("reload .env.config: %w", err)
		}

		trusted, err := trustSignerInteractive(username, f, reader)
		if err != nil {
			log.Printf("Could not fetch keys for %s: %v", username, err)
			continue
		}
		if !trusted {
			fmt.Println("  Skipped.")
		}
	}

	return nil
}

func runInstallService(dir string) error {
	if runtime.GOOS != "linux" {
		fmt.Println("  Skipping systemd on non-Linux")
		return nil
	}

	instance := serviceInstance(dir)
	if instance == "" {
		return fmt.Errorf("could not determine service instance name (check DEPLOYMENT_SLOT_CODE in .env.config)")
	}

	// Install as a user-level systemd service — no root needed.
	// The service file is copied to ~/.config/systemd/user/ and managed
	// with systemctl --user. This works on standalone deployments where
	// the user has no root access.
	userServiceDir := filepath.Join(os.Getenv("HOME"), ".config", "systemd", "user")
	if err := os.MkdirAll(userServiceDir, 0755); err != nil {
		return fmt.Errorf("create systemd user dir: %w", err)
	}

	serviceFile := filepath.Join(dir, "ops", "statbus-upgrade.service")
	destFile := filepath.Join(userServiceDir, "statbus-upgrade@.service")

	fmt.Printf("  Copying %s → %s\n", filepath.Base(serviceFile), destFile)
	if err := copyFile(serviceFile, destFile); err != nil {
		return fmt.Errorf("copy service file: %w", err)
	}

	fmt.Println("  Running systemctl --user daemon-reload")
	if err := runCmd("systemctl", "--user", "daemon-reload"); err != nil {
		return fmt.Errorf("systemctl daemon-reload: %w", err)
	}

	// Enable linger so the user service runs even when not logged in.
	// This requires loginctl which is available on systemd systems.
	fmt.Println("  Enabling linger for user services")
	runCmd("loginctl", "enable-linger", os.Getenv("USER"))

	// Item H (plan-rc.66): step 14/14 SDNOTIFY collision. When this
	// install runs as a child of the active upgrade service (Type=notify
	// unit, parent PID is the main daemon), `enable --now` joins the
	// existing start job and waits for READY=1 from a new main PID.
	// systemctl's helper PIDs send READY=1; systemd rejects them as
	// not-main-PID; start times out at ~47s and terminates the parent.
	// Skip --now in that case — the unit declares
	// SuccessExitStatus=42/RestartForceExitStatus=42/Restart=always so
	// the parent's exit-42 → systemd auto-restart picks up the new
	// binary. The is-enabled verification below still fires.
	if insideActiveUpgrade {
		fmt.Printf("  Enabling %s (start deferred — service is the active main PID, will exit-42 → systemd auto-restart)\n", instance)
		if err := runCmd("systemctl", "--user", "enable", instance); err != nil {
			return fmt.Errorf("enable service: %w", err)
		}
	} else {
		fmt.Printf("  Enabling and starting %s\n", instance)
		if err := runCmd("systemctl", "--user", "enable", "--now", instance); err != nil {
			return fmt.Errorf("enable service: %w", err)
		}
	}

	// Verify the boot-enable symlink was actually created. Bug observed on
	// rune 2026-04-22: `systemctl --user enable --now` exited 0 but the
	// default.target.wants/ symlink was missing — service ran but wouldn't
	// start after a reboot. Reproducer: enable invoked when the service was
	// already started externally (standalone.sh's ensure_service_started
	// failure-path ran `start` earlier). Fail loudly so the installer
	// doesn't silently deliver a host that regresses on its next reboot.
	out, isEnabledErr := exec.Command("systemctl", "--user", "is-enabled", instance).Output()
	state := strings.TrimSpace(string(out))
	if state != "enabled" {
		return fmt.Errorf("enable reported success but is-enabled=%q (err=%v); service will not start on boot — investigate systemctl user-bus / loginctl linger", state, isEnabledErr)
	}

	fmt.Printf("  Upgrade service installed and started: %s (is-enabled=%s)\n", instance, state)
	return nil
}

// gitHeadInfo returns the HEAD commit SHA and ISO-8601 commit date, or empty
// strings if git is unavailable (e.g., non-git install from tarball).
func gitHeadInfo(dir string) (sha, commitDate string) {
	out, err := upgrade.RunCommandOutput(dir, "git", "rev-parse", "HEAD")
	if err != nil {
		return "", ""
	}
	sha = strings.TrimSpace(out)
	if len(sha) != 40 {
		return "", ""
	}
	out, err = upgrade.RunCommandOutput(dir, "git", "log", "-1", "--format=%cI", "HEAD")
	if err != nil {
		return sha, ""
	}
	return sha, strings.TrimSpace(out)
}

var gitDescribeRe = regexp.MustCompile(`-g[0-9a-f]+$`)

func classifyReleaseStatus(ver string) string {
	v := strings.TrimPrefix(ver, "v")
	if v == "" || v == "dev" {
		return "commit"
	}
	// Git-describe with distance: "2026.04.0-rc.15-1-gf483d1d2e" has "-g<hex>"
	// suffix indicating commits past the tag. These are "commit" not "prerelease".
	if gitDescribeRe.MatchString(v) {
		return "commit"
	}
	// Clean tag with -rc.N → prerelease
	if strings.Contains(v, "-rc.") {
		return "prerelease"
	}
	// Clean tag without -rc → release (e.g., "2026.04.0")
	parts := strings.SplitN(v, ".", 3)
	if len(parts) >= 3 {
		return "release"
	}
	return "commit"
}

// sqlLiteral escapes a string for use as a SQL single-quoted literal.
func sqlLiteral(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

// runInstallSQL pipes a SQL statement to psql via stdin and returns the output.
// No psql-specific interpolation (no -v / :'name') — callers build the SQL
// with fmt.Sprintf + sqlLiteral. Wraps psql output into the error for debugging.
func runInstallSQL(dir, sql string) (string, error) {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return "", err
	}
	args := append(append([]string{}, prefix...), "-v", "ON_ERROR_STOP=on", "-X", "-A", "-t")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	cmd.Stdin = strings.NewReader(sql)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%w: %s", err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

// connectInstallDB opens a pgx connection for post-completion operations.
// Uses migrate.AdminConnStr which reads CADDY_DB_BIND_ADDRESS from .env.
func connectInstallDB(dir string) (*pgx.Conn, error) {
	connStr, err := migrate.AdminConnStr(dir)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return pgx.Connect(ctx, connStr)
}

// completeInstallUpgradeRow creates a fresh `completed` upgrade row for the
// current SHA (idempotent INSERT ... ON CONFLICT upsert). Used on
// StateFresh/StateHalfConfigured/StateDBUnreachable where install is the
// first actor to touch public.upgrade; the daemon has not yet authored a row.
// logRelPath is stamped on the new row (the on-disk log was created before
// the step-table but couldn't be stamped until the row exists).
//
// Under A20 capability separation, install itself NEVER authors an in_progress
// row — so the UPDATE branch that used to exist here was removed in rc.38.
// StateNothingScheduled takes a separate code path that emits NOTIFY
// upgrade_check instead of calling this function.
//
// Guards three named invariants:
//   - A6 COMPLETION_CONN_NON_NIL — nil conn is a bug-class assert (A3's
//     post-completion defer fail-fasts first on connect failure). log.Panicf
//     so the runtime prints the stack trace; the panic handler in runInstall
//     writes install-terminal.txt.
//   - A8 GIT_HEAD_RESOLVABLE — gitHeadInfo yields a non-empty SHA inside a
//     checked-out repo.
//   - A9 POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS — the fresh-install INSERT
//     creating the `completed` row succeeds when conn is live and schema is
//     migrated.
func completeInstallUpgradeRow(installDir string, conn *pgx.Conn, logRelPath string) error {
	// A6: COMPLETION_CONN_NON_NIL — bug-class panic. A3's post-completion defer
	// returns early on connect failure so this function is reached only when
	// conn is non-nil. If a future refactor drops that guard, fail loudly.
	if conn == nil {
		log.Panicf(
			"INVARIANT COMPLETION_CONN_NON_NIL violated: completeInstallUpgradeRow called with nil conn; A3 guarantee broken in runInstall defer chain (install.go:%d, pid=%d)",
			thisLine(), os.Getpid())
	}
	ctx := context.Background()

	sha, commitDate := gitHeadInfo(installDir)
	if sha == "" || commitDate == "" {
		// A8: GIT_HEAD_RESOLVABLE
		cwd, _ := os.Getwd()
		fmt.Fprintf(os.Stderr,
			"INVARIANT GIT_HEAD_RESOLVABLE violated: gitHeadInfo returned sha=%q commitDate=%q at post-completion; cannot record version (install.go:%d, pid=%d, cwd=%s)\n",
			sha, commitDate, thisLine(), os.Getpid(), cwd)
		markTerminal(installDir, "GIT_HEAD_RESOLVABLE",
			fmt.Sprintf("sha=%q; commitDate=%q; cwd=%s", sha, commitDate, cwd))
		return fmt.Errorf("GIT_HEAD_RESOLVABLE: gitHeadInfo returned empty (sha=%q commitDate=%q)", sha, commitDate)
	}

	_, err := conn.Exec(ctx,
		`INSERT INTO public.upgrade (
		   commit_sha, committed_at, summary, state, completed_at,
		   commit_version, release_status, scheduled_at, started_at, from_commit_version,
		   commit_tags, has_migrations,
		   docker_images_status, release_builds_status,
		   log_relative_file_path
		 ) VALUES (
		   $1, $2::timestamptz,
		   $3, 'completed', clock_timestamp(),
		   $4, $5::release_status_type,
		   clock_timestamp(), clock_timestamp(),
		   (SELECT commit_version FROM public.upgrade WHERE state = 'completed' ORDER BY completed_at DESC NULLS LAST LIMIT 1),
		   ARRAY[$4]::text[], false,
		   'ready', 'ready',
		   NULLIF($6, '')
		 )
		 ON CONFLICT (commit_sha) DO UPDATE SET
		   state = 'completed',
		   completed_at = COALESCE(upgrade.completed_at, clock_timestamp()),
		   started_at = COALESCE(upgrade.started_at, clock_timestamp()),
		   -- DO NOT touch scheduled_at on this path. The
		   -- upgrade_notify_daemon_trigger fires AFTER UPDATE when
		   -- scheduled_at goes NULL → value, sending NOTIFY upgrade_apply
		   -- which the daemon picks up and treats as a fresh upgrade
		   -- request. For the install-record path we are bookkeeping
		   -- "we are already at this version" — there is no upgrade
		   -- to apply. Leaving scheduled_at unchanged means: if it was
		   -- NULL (state='available' from discovery), it stays NULL
		   -- and the trigger does NOT fire. Pre-fix: dev's deploy
		   -- triggered a no-op rc.67→rc.67 self-upgrade that wedged
		   -- the post-swap pipeline (rootcause for #55).
		   error = NULL,
		   rolled_back_at = NULL,
		   dismissed_at = NULL,
		   docker_images_status = 'ready',
		   release_builds_status = 'ready',
		   commit_version = COALESCE(EXCLUDED.commit_version, upgrade.commit_version),
		   log_relative_file_path = COALESCE(EXCLUDED.log_relative_file_path, upgrade.log_relative_file_path)
		 WHERE upgrade.state != 'completed'`,
		sha,
		commitDate,
		fmt.Sprintf("Installed via ./sb install (%s)", version),
		version,
		classifyReleaseStatus(version),
		logRelPath)
	if err != nil {
		// A9: POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS
		fmt.Fprintf(os.Stderr,
			"INVARIANT POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS violated: could not record completed upgrade row for sha=%s: %v (install.go:%d, pid=%d)\n",
			sha, err, thisLine(), os.Getpid())
		markTerminal(installDir, "POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS",
			fmt.Sprintf("sha=%s; INSERT err=%v", sha, err))
		return fmt.Errorf("POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS: %w", err)
	}
	fmt.Printf("  Recorded installed version %s in upgrade table\n", version)
	return nil
}

// stampInstallInvocationTracking records the latest install invocation in
// public.system_info. Mirrors the support.go install_last_error* upsert pattern.
// Called on successful install completion (all states). Best-effort: failures
// here only affect the admin UI banner freshness — the install itself succeeded.
// Also clears install_last_error / install_last_error_at / install_last_bundle_path
// so a previously-failed install stops showing a stale error banner after a
// successful re-run.
func stampInstallInvocationTracking(conn *pgx.Conn, logRelPath string) {
	if conn == nil {
		return
	}
	_, err := conn.Exec(context.Background(),
		`INSERT INTO public.system_info (key, value) VALUES
		     ('install_last_log_relative_file_path', $1),
		     ('install_last_at', clock_timestamp()::text),
		     ('install_last_error', ''),
		     ('install_last_error_at', ''),
		     ('install_last_bundle_path', '')
		 ON CONFLICT (key) DO UPDATE SET
		     value = EXCLUDED.value,
		     updated_at = clock_timestamp()`,
		logRelPath)
	if err != nil {
		log.Printf(
			"stampInstallInvocationTracking: upsert failed (non-fatal): %v (install.go:%d, pid=%d)",
			err, thisLine(), os.Getpid())
	}
}

// runInstallRetention runs the upgrade retention policy after a successful
// install. This ensures the step-table path (used by cloud.sh) triggers the
// same retention as the service's executeUpgrade path. Errors are logged and
// swallowed — retention is opportunistic, not a hard install dependency.
// Log lines are named under the class invariant OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED
// so the support bundle has a greppable anchor for SSB triage.
func runInstallRetention(conn *pgx.Conn, rowID int64) {
	if conn == nil {
		// A12: OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED (retention-no-conn)
		log.Printf(
			"INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A12 — retention-no-conn): conn==nil; skip (install.go:%d, pid=%d)",
			thisLine(), os.Getpid())
		return
	}
	// upgrade_retention_apply(scope, installed_id, INOUT p_deleted)
	// Pass NULL for installed_id when rowID is 0 (fresh install with no row).
	var installedID *int64
	if rowID > 0 {
		installedID = &rowID
	}
	var deleted int
	err := conn.QueryRow(context.Background(),
		"CALL public.upgrade_retention_apply($1, $2, 0)",
		"all", installedID).Scan(&deleted)
	if err != nil {
		// A13: OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED (retention-sql)
		log.Printf(
			"INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A13 — retention-sql): CALL upgrade_retention_apply err=%v (install.go:%d, pid=%d)",
			err, thisLine(), os.Getpid())
		return
	}
	if deleted > 0 {
		fmt.Printf("  Retention: purged %d old upgrade rows\n", deleted)
	}
}

// runInstallSupersede marks older upgrade rows as superseded after a
// successful install. Calls the shared SQL procedure so both install
// and service paths use the same logic. Best-effort — errors are named
// breadcrumbs under OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED so the
// support bundle retains a greppable anchor.
func runInstallSupersede(conn *pgx.Conn, dir string) {
	if conn == nil {
		// Sub-index reuses A12 class (no dedicated sub-idx; same no-conn shape).
		log.Printf(
			"INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A12 — supersede-no-conn): conn==nil; skip (install.go:%d, pid=%d)",
			thisLine(), os.Getpid())
		return
	}
	sha, _ := gitHeadInfo(dir)
	if sha == "" {
		return
	}
	var superseded int
	err := conn.QueryRow(context.Background(),
		"CALL public.upgrade_supersede_older($1, 0)",
		sha).Scan(&superseded)
	if err != nil {
		// A14: OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED (supersede-sql)
		log.Printf(
			"INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A14 — supersede-sql): CALL upgrade_supersede_older err=%v; rowsAffected=%d (install.go:%d, pid=%d)",
			err, superseded, thisLine(), os.Getpid())
		return
	}
	if superseded > 0 {
		fmt.Printf("  Superseded %d older release(s)\n", superseded)
	}

	// Also supersede older completed prereleases in the same version family.
	// Safe no-op for non-prereleases.
	var supersededPrereleases int
	err = conn.QueryRow(context.Background(),
		"CALL public.upgrade_supersede_completed_prereleases($1, 0)",
		sha).Scan(&supersededPrereleases)
	if err != nil {
		// A16: OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED (prerelease-sql)
		log.Printf(
			"INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A16 — prerelease-sql): CALL upgrade_supersede_completed_prereleases err=%v (install.go:%d, pid=%d)",
			err, thisLine(), os.Getpid())
		return
	}
	if supersededPrereleases > 0 {
		fmt.Printf("  Superseded %d completed prerelease(s) in same family\n", supersededPrereleases)
	}
}

// runInstallCallback executes the UPGRADE_CALLBACK shell command from .env
// after a successful install. Mirrors the service's runUpgradeCallback.
// Best-effort — errors are logged and swallowed.
func runInstallCallback(dir string) {
	envPath := filepath.Join(dir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		// No .env → no callback configured; not an error on fresh installs.
		return
	}

	callback, ok := f.Get("UPGRADE_CALLBACK")
	if !ok || callback == "" {
		return
	}

	hostname, _ := os.Hostname()
	statbusURL, _ := f.Get("STATBUS_URL")

	fmt.Printf("  Running upgrade callback...\n")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "sh", "-c", callback)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(),
		"STATBUS_VERSION="+version,
		"STATBUS_SERVER="+hostname,
		"STATBUS_URL="+statbusURL,
	)

	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			fmt.Printf("  Upgrade callback timed out after 30s\n")
		} else {
			fmt.Printf("  Upgrade callback failed: %v\n", err)
		}
		return
	}
	fmt.Printf("  Upgrade callback completed successfully\n")
}

// runRootInstall handles `sudo sb install` — ONLY installs the systemd service.
// Does not touch any project files to avoid creating root-owned files.
func runRootInstall() error {
	fmt.Println("StatBus — Installing systemd service (running as root)")
	fmt.Println()

	if runtime.GOOS != "linux" {
		return fmt.Errorf("systemd service installation is only supported on Linux")
	}

	// Find the project directory from the binary location
	sbPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("find executable: %w", err)
	}
	dir := filepath.Dir(sbPath)

	instance := serviceInstance(dir)
	if instance == "" {
		return fmt.Errorf("could not determine service instance name (check DEPLOYMENT_SLOT_CODE in .env.config)")
	}

	serviceFile := filepath.Join(dir, "ops", "statbus-upgrade.service")
	destFile := "/etc/systemd/system/statbus-upgrade@.service"

	fmt.Printf("  Copying %s → %s\n", filepath.Base(serviceFile), destFile)
	if err := copyFile(serviceFile, destFile); err != nil {
		return fmt.Errorf("copy service file: %w", err)
	}

	fmt.Println("  Running systemctl daemon-reload")
	if err := runCmd("systemctl", "daemon-reload"); err != nil {
		return fmt.Errorf("systemctl daemon-reload: %w", err)
	}

	// No sudoers needed — backup/restore runs rsync inside a Docker container,
	// which can read/write the named volume without host-level sudo.

	fmt.Printf("  Enabling and starting %s\n", instance)
	if err := runCmd("systemctl", "enable", "--now", instance); err != nil {
		return fmt.Errorf("enable service: %w", err)
	}

	// Mirror the user-service verification above: confirm the boot-enable
	// symlink exists. See runInstallService for the bug-history comment.
	out, isEnabledErr := exec.Command("systemctl", "is-enabled", instance).Output()
	state := strings.TrimSpace(string(out))
	if state != "enabled" {
		return fmt.Errorf("enable reported success but is-enabled=%q (err=%v); service will not start on boot", state, isEnabledErr)
	}

	fmt.Println()
	fmt.Printf("  Upgrade service installed and started: %s (is-enabled=%s)\n", instance, state)
	fmt.Println("  Re-run without sudo to verify: ./sb install")
	return nil
}

// ── Helpers ──

func checkPrerequisites() error {
	if _, err := exec.LookPath("docker"); err != nil {
		return fmt.Errorf("Docker is required but not found. Install from https://docs.docker.com/engine/install/")
	}
	if err := runCmd("docker", "compose", "version"); err != nil {
		return fmt.Errorf("Docker Compose is required. Install the compose plugin: https://docs.docker.com/compose/install/")
	}
	if _, err := exec.LookPath("git"); err != nil {
		return fmt.Errorf("git is required but not found. Install with: sudo apt install git")
	}
	return nil
}

func prompt(label, defaultVal string) string {
	fmt.Printf("%s [%s]: ", label, defaultVal)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	line = strings.TrimSpace(line)
	if line == "" {
		return defaultVal
	}
	return line
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func runCmdDir(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func copyFile(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, 0755)
}

// migrateConfigPaths rewrites devops/ → ops/ paths in .env.config.
// Idempotent — only changes values that still use the old prefix.
func migrateConfigPaths(dir string) {
	cfgPath := filepath.Join(dir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return
	}
	changed := false
	for _, key := range f.Keys() {
		val, _ := f.Get(key)
		if strings.Contains(val, "./devops/") {
			f.Set(key, strings.ReplaceAll(val, "./devops/", "./ops/"))
			changed = true
		}
	}
	if changed {
		if err := f.Save(); err != nil {
			log.Printf("Could not migrate .env.config paths: %v", err)
		} else {
			fmt.Println("  Migrated .env.config: devops/ → ops/")
		}
	}
}

// logInstallState prints the state classification produced by install.Detect.
// Dispatch policy lives in runInstall; this function is print-only.
func logInstallState(state install.State, detail *install.Detail) {
	fmt.Printf("Detected install state: %s (current=%s, target=%s)\n",
		state, detail.CurrentVersion, detail.TargetVersion)
	switch state {
	case install.StateFresh:
		fmt.Printf("  Fresh install; target version = %s (binary).\n", detail.TargetVersion)
	case install.StateLiveUpgrade:
		if detail.Flag != nil {
			fmt.Printf("  Upgrade in progress (PID %d, %s). Install will refuse.\n",
				detail.Flag.PID, detail.Flag.Label())
		}
	case install.StateCrashedUpgrade:
		if detail.Flag != nil {
			fmt.Printf("  Prior upgrade crashed (PID %d, %s). The stale lock was released when the PID died; recovering.\n",
				detail.Flag.PID, detail.Flag.Label())
		}
	case install.StateHalfConfigured:
		fmt.Println("  .env.credentials missing; step-table will generate it.")
	case install.StateDBUnreachable:
		fmt.Println("  Database not reachable; step-table will start services.")
	case install.StateLegacyNoUpgradeTable:
		fmt.Println("  Pre-1.0 install detected (public.upgrade absent). Install will refuse; automatic upgrade from pre-1.0 tracked as #65.6.")
	case install.StateScheduledUpgrade:
		fmt.Printf("  Upgrade scheduled (id=%d, version=%s). Dispatching inline upgrade.\n",
			detail.ScheduledRowID, detail.TargetVersion)
	case install.StateNothingScheduled:
		fmt.Println("  Existing install, no upgrade scheduled; running idempotent step-table to refresh.")
	}
	fmt.Println()
}

// Runtime invariant registration — every guard site in this file declares
// its triad (ExpectedToHold / WhyExpected / ViolationShape / TranscriptFormat)
// so the support-bundle `invariants` section and the plan ↔ code ↔ bundle
// coupling stays authoritative. TestEveryInvariantHasTriadDocumented gates
// this on every build.
func init() {
	invariants.Register(invariants.Invariant{
		Name:             "POST_COMPLETION_DB_REACHABLE_AFTER_STEP_TABLE",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/cmd/install.go:runInstall (post-completion defer)",
		ExpectedToHold:   "pgx.Connect to the admin DSN succeeds in the post-completion defer when the step-table (including the Services step) completed without error.",
		WhyExpected:      "Successful step-table completion requires a healthy DB — the Services and Migrations steps both exercise it moments earlier. A fresh pgx.Connect failing here means the DB went away in the narrow window after step-table success.",
		ViolationShape:   "pgx.Connect returns a non-nil error in the runInstall post-completion defer, on a path where installErr == nil (primary install succeeded).",
		TranscriptFormat: "INVARIANT POST_COMPLETION_DB_REACHABLE_AFTER_STEP_TABLE violated: pgx.Connect failed after healthy step-table: <err>",
	})
	invariants.Register(invariants.Invariant{
		Name:             "COMPLETION_CONN_NON_NIL",
		Class:            invariants.PanicRegression,
		SourceLocation:   "cli/cmd/install.go:completeInstallUpgradeRow",
		ExpectedToHold:   "completeInstallUpgradeRow is never called with a nil *pgx.Conn — A3 fail-fast in the runInstall defer guarantees the connect succeeded on the success path.",
		WhyExpected:      "The runInstall defer only calls completeInstallUpgradeRow when installErr == nil and (implicitly) after the A3 guard has returned early on connect failure. If this branch fires, the defer chain has drifted and quiet corruption is likely.",
		ViolationShape:   "conn == nil on entry to completeInstallUpgradeRow — a refactor of runInstall's defer chain has broken the A3 guarantee.",
		TranscriptFormat: "INVARIANT COMPLETION_CONN_NON_NIL violated: completeInstallUpgradeRow called with nil conn; A3 guarantee broken in runInstall defer chain",
	})
	invariants.Register(invariants.Invariant{
		Name:             "GIT_HEAD_RESOLVABLE",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/cmd/install.go:completeInstallUpgradeRow",
		ExpectedToHold:   "gitHeadInfo(installDir) returns non-empty sha and commitDate during the post-completion path.",
		WhyExpected:      "./sb install operates from inside a git clone (the Repository step ran earlier); HEAD is the commit just installed. Empty fields mean .git was removed mid-install or we're in the wrong directory — neither is recoverable.",
		ViolationShape:   "gitHeadInfo returns sha=\"\" or commitDate=\"\" inside completeInstallUpgradeRow.",
		TranscriptFormat: "INVARIANT GIT_HEAD_RESOLVABLE violated: gitHeadInfo returned sha=<sha> commitDate=<date>; cwd=<cwd>",
	})
	invariants.Register(invariants.Invariant{
		Name:             "POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS",
		Class:            invariants.FailFast,
		SourceLocation:   "cli/cmd/install.go:completeInstallUpgradeRow",
		ExpectedToHold:   "The INSERT/upsert recording the completed upgrade row for this SHA succeeds when no prior row existed (fresh-install path, rowID == 0).",
		WhyExpected:      "A3 just guaranteed the DB is reachable, gitHeadInfo (A8) yielded real values, and this is an idempotent INSERT ... ON CONFLICT upsert. Failure means the DB dropped between A3 and this call or a schema drift broke the INSERT.",
		ViolationShape:   "pgx.Exec returns a non-nil error for the fresh-install INSERT INTO public.upgrade (...) VALUES (...) ON CONFLICT (commit_sha) DO UPDATE SET ...",
		TranscriptFormat: "INVARIANT POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS violated: could not record completed upgrade row for sha=<sha>: <err>",
	})
	invariants.Register(invariants.Invariant{
		Name:             "OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED",
		Class:            invariants.LogOnly,
		SourceLocation:   "cli/cmd/install.go:runInstallRetention/runInstallSupersede/acquireOrBypass",
		ExpectedToHold:   "Post-success cleanup calls (retention purge, supersede older rows, prerelease supersede, unexpected-bypass audit) succeed, but their failure never aborts the install.",
		WhyExpected:      "These are housekeeping operations whose failure is tolerable — the primary install already succeeded; stale rows accumulate but do not break future installs. A4's A1 auto-heal is the backstop.",
		ViolationShape:   "conn==nil, or CALL upgrade_retention_apply / upgrade_supersede_older / upgrade_supersede_completed_prereleases returns err, or --inside-active-upgrade observed without an on-disk flag. Each sub-site prints a named log line with sub-index (A12/A13/A14/A16/A17).",
		TranscriptFormat: "INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A<sub> — <subsite>): <observed>; proceeding",
	})
	invariants.Register(invariants.Invariant{
		Name:             "FAILED_INSTALL_HAS_AUDIT_TRAIL",
		Class:            invariants.LogOnly,
		SourceLocation:   "cli/cmd/install.go:runInstall (post-completion defer, audit branch)",
		ExpectedToHold:   "Every failed install leaves a greppable audit breadcrumb in stderr/log, even when no upgrade row was created (fresh install that died before DB reachable).",
		WhyExpected:      "Primary installErr return already drives install.sh's shell-level banner; the DB-side row is missing by construction on this branch. An explicit named log line keeps the support bundle's invariants grep aligned with SSB triage expectations.",
		ViolationShape:   "runInstall returns a non-nil installErr while upgradeRowID == 0 — the audit line prints but neither markTerminal nor installErr wrapping is applied (log-only class).",
		TranscriptFormat: "INVARIANT FAILED_INSTALL_HAS_AUDIT_TRAIL violated (audit-only): install failed with no upgrade row (detectedState=<state>): <err>",
	})
	invariants.Register(invariants.Invariant{
		Name:             "NOTIFY_UPGRADE_CHECK_BEST_EFFORT_LOGGED",
		Class:            invariants.LogOnly,
		SourceLocation:   "cli/cmd/install.go:runInstall (post-completion defer, NothingScheduled arm)",
		ExpectedToHold:   "After a successful install on StateNothingScheduled, NOTIFY upgrade_check reaches the discovery daemon on the open pgx connection so the daemon materializes the current commit_sha row on its next tick without waiting for the periodic interval.",
		WhyExpected:      "The pgx connection was just used successfully for post-completion ops (A3 guards that connect succeeded); no hang-up is expected in the few microseconds between ops. NOTIFY is a single async send. The periodic discovery tick guarantees eventual recovery if the send fails transiently.",
		ViolationShape:   "conn.Exec(ctx, \"NOTIFY upgrade_check\") returns a non-nil error after the step-table completed healthily.",
		TranscriptFormat: "INVARIANT NOTIFY_UPGRADE_CHECK_BEST_EFFORT_LOGGED violated (audit-only): NOTIFY upgrade_check failed post-install: <err> — next daemon tick will recover",
	})
}
