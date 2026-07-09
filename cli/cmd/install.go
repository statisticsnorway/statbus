package cmd

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/compose"
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

// postUpgradeFixup signals that this install invocation is a post-upgrade
// fixup spawned by the upgrade service itself. It is NOT a user-facing flag —
// operators must never pass it. The service at service.go:executeUpgrade sets
// both this CLI flag and STATBUS_POST_UPGRADE_FIXUP=1 env var on its child
// exec; either triggers the mutex bypass in runInstall.
var postUpgradeFixup bool

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
	installCmd.Flags().BoolVar(&postUpgradeFixup, "post-upgrade-fixup", false,
		"Internal: set by the upgrade service when spawning install as a post-upgrade fixup. Operators must not pass this.")
	// Hide the internal flag from --help; it's a contract between service and child install, not a user-facing knob.
	_ = installCmd.Flags().MarkHidden("post-upgrade-fixup")
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
// Both the upgrade service and `./sb install` acquire the same marker file
// (tmp/upgrade-in-progress.json) via acquireFlock — O_CREATE|O_RDWR +
// flock(LOCK_EX|LOCK_NB); the kernel advisory lock guarantees one holder and
// auto-releases on fd close, so a crash never leaves a stale lock. The Holder field distinguishes
// service-vs-install ownership; recoverFromFlag uses Holder to decide
// what cleanup is needed when a writer crashed (DB reconciliation for
// service, file-removal-only for install).
//
// When `bypass` is true, the caller is the upgrade service's own
// post-upgrade fixup — the parent service already holds the flag, so the
// child install neither acquires nor releases. Otherwise:
//   - No flag → atomic acquire succeeds; returns a release function the
//     caller must defer.
//   - Flag exists, flock held (live) → returns a formatted error guiding the
//     operator to wait (with the `lsof` hint).
//   - Flag exists, flock free (crashed) → unreachable: install.Detect returns
//     StateCrashedUpgrade before acquireOrBypass is called, so the
//     stale-flag path is handled by RecoverFromFlag, not here.
//
// Returns (releaseFunc, nil) on success; (nil-no-op, err) on contention.
func acquireOrBypass(installDir string, bypass bool) (release func(), err error) {
	if bypass {
		// Verify-only diagnostic — the bypass child neither acquires nor
		// releases the mutex. Three cases:
		//   1. Flag present → an upgrade is mid-flight and holds it; print the
		//      holder for the audit log (e.g. a fixup racing an unrelated install).
		//   2. Flag absent + STATBUS_POST_UPGRADE_FIXUP=1 → the EXPECTED steady
		//      state: the upgrade service spawned us as its post-completion fixup,
		//      and applyPostSwap removes the upgrade flag BEFORE running this fixup
		//      (rune-stuck-fix A, service.go). The absent flag is by design — not
		//      an anomaly — so proceed quietly, no invariant.
		//   3. Flag absent + no env signature → GENUINE misuse: the bare internal
		//      flag was hand-passed. Audit it (A17) and proceed (harmless; the
		//      step-table is idempotent).
		if flag, rerr := upgrade.ReadFlagFile(installDir); rerr == nil && flag != nil {
			fmt.Printf("Upgrade mutex bypass honored (--post-upgrade-fixup). Flag holder=%s, invoked_by=%s (see: lsof tmp/upgrade-in-progress.json).\n",
				flag.Holder, flag.InvokedBy)
		} else if os.Getenv("STATBUS_POST_UPGRADE_FIXUP") == "1" {
			fmt.Println("Post-upgrade fixup: upgrade already completed and cleared its flag — proceeding (expected).")
		} else {
			// A17: OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED (unexpected-bypass).
			// Genuine misuse ONLY — the legitimate post-completion fixup carries
			// the STATBUS_POST_UPGRADE_FIXUP env signature handled just above. Here
			// the bare --post-upgrade-fixup flag was passed by hand with no upgrade
			// in flight; this flag is the upgrade service's contract with its own
			// child and operators must never pass it.
			log.Printf(
				"INVARIANT OPPORTUNISTIC_CLEANUP_BEST_EFFORT_LOGGED violated (A17 — unexpected-bypass): --post-upgrade-fixup passed by hand (no STATBUS_POST_UPGRADE_FIXUP env signature) and no upgrade flag found; this flag is internal — do not pass it. Proceeding (install.go:%d, pid=%d)",
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
// fixup, which passes --post-upgrade-fixup / STATBUS_POST_UPGRADE_FIXUP=1
// to signal "I am the upgrade service's own post-completion fixup, not a
// conflicting actor."
func runInstall() (installErr error) {
	// The upgrade service spawns `./sb install` as its post-completion fixup
	// with --post-upgrade-fixup + STATBUS_POST_UPGRADE_FIXUP=1. Either signal
	// marks this a fixup child: it bypasses the install↔upgrade mutex (the
	// service owns it / has already cleared it) and skips state detection,
	// row-authoring, and log creation below. Computed once here so the banner
	// and the mutex section agree.
	bypass := postUpgradeFixup || os.Getenv("STATBUS_POST_UPGRADE_FIXUP") == "1"

	// Warn if running as root — the upgrade service is a user-level systemd unit now,
	// running as root would create files owned by root in the project dir.
	if os.Geteuid() == 0 {
		fmt.Println("Warning: running as root. The upgrade service is a user-level systemd unit.")
		fmt.Println("Run as the application user instead: ./sb install")
		fmt.Println()
	}

	// Self-identifying banner: the post-completion fixup is a legitimately
	// separate `./sb install` process (distinct pid) nested at the tail of an
	// upgrade — label it so the log does not read as a second independent install.
	if bypass {
		fmt.Println("StatBus Post-Upgrade Install Fixup")
		fmt.Println("==================================")
	} else {
		fmt.Println("StatBus Installation")
		fmt.Println("====================")
	}
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
	// Atomically claim tmp/upgrade-in-progress.json (Holder="install") via
	// acquireOrBypass below so any other actor — running upgrade service,
	// another install — sees us and aborts. ReleaseInstallFlag in defer cleans
	// up on every exit path. The ONLY caller allowed to bypass is the upgrade
	// service's own post-completion fixup (service.go:applyPostSwap →
	// runInstallFixup, with --post-upgrade-fixup + STATBUS_POST_UPGRADE_FIXUP=1);
	// `bypass` was computed at the top of runInstall. By the time that fixup
	// runs, applyPostSwap has already removed the flag — acquireOrBypass treats
	// that (absent flag + env signature) as the expected steady state.

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
	// Pre-Detect orphan-backend cleanup. Critical for recovery from a
	// crashed upgrade that exhausted max_connections (rune wedge Stage B).
	// install.Detect runs DB queries; if pool is exhausted, Detect fails
	// and we'd skip the recovery path entirely. cleanOrphanSessions uses
	// docker exec → peer auth → superuser inside the container, which
	// works even when external connections all fail with "too many
	// clients". Idempotent: the check is a single SELECT count(*); if the
	// pool has headroom this is a no-op. Gated on services-up so fresh
	// installs (no DB container yet) skip cleanly.
	if !bypass && checkServicesDone(installDir) && !checkSessionsClean(installDir) {
		fmt.Println("  Pre-detect: connection pool not clean, running cleanOrphanSessions")
		if err := cleanOrphanSessions(installDir); err != nil {
			// Best-effort here — log and proceed. install.Detect's own
			// error path (and the step-table's later "Database sessions"
			// step) will surface a real DB-down state with a clean error.
			log.Printf("Pre-detect cleanOrphanSessions: %v", err)
		}
	}

	// Pre-flight: if --trust-github-user is set, trust that user's signing key
	// BEFORE state detection + dispatch. Positioned ahead of dispatchInstallState
	// (below) on purpose: the scheduled-upgrade and crashed-upgrade paths return
	// early from dispatch (handing off to executeUpgrade), so a trust pre-flight
	// placed after dispatch never runs on a box with a pending/wedged upgrade —
	// making `./sb install --trust-github-user X` a silent no-op exactly when the
	// upgrade pipeline needs that signer to verify the target commit. Skips the
	// GitHub fetch if a valid key is already configured (idempotent — no API call
	// on re-run); a truly fresh box (no .env.config yet) is a no-op, same as
	// before — the require-a-signer pre-flight further down still gates existing
	// installs.
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

	var detectedState install.State
	if !bypass {
		state, detail, derr := install.Detect(installDir, version)
		if derr != nil {
			log.Printf("State detection failed (continuing with step-table fallback): %v", derr)
		} else {
			detectedState = state
			logInstallState(installDir, state, detail)
			// Safe takeover (STATBUS-039): a live flock + a crash-looping
			// unit is not a progressing upgrade — it is a wedge cycling
			// through watchdog kills (rune: NRestarts=10229 over 18 days),
			// and the operator's `./sb install` must FIX it, not lose a
			// timing lottery against the ~30s RestartSec dead windows.
			// Reclassify to crashed-upgrade and proceed: runCrashRecovery's
			// SIGKILL-class quiesce (stopRestartUpgradeUnit) kills the loop
			// holder — never SIGTERM, which would fire the in-flight
			// upgrade's rollback handler — and recovery then owns the flag.
			// A genuinely progressing upgrade (low restart count) keeps the
			// refusal below; any probe failure also falls through to it.
			if state == install.StateLiveUpgrade {
				if _, looping := upgradeUnitCrashLooping(installDir); looping {
					state = install.StateCrashedUpgrade
					detectedState = state
				}
			}
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
		// "Backup ownership" heals pre-upgrade-* dirs created by the
		// rsync alpine container before the chown-after-rsync fix
		// landed. Without this, ~/statbus-backups/ accumulates
		// indefinitely (statbus_<slot> can't traverse the 0700
		// messagebus-owned dirs → pruneBackups silently fails →
		// support-bundle archive step fails with "Permission denied").
		// Idempotent: no-op when all dirs are already deploy-user-owned.
		// Discovered during jo's v2026.05.4 recovery: 9 backup dirs
		// going back to March 2026 because none could be removed.
		{"Backup ownership", checkBackupOwnershipDone, healBackupOwnership},
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

	// R1 quiesce window: worker / app / rest must NOT be running across
	// the DDL phases (Seed + Migrations). The worker holds AccessShareLock
	// on statistical-history tables for the duration of each task; the
	// seed's DROP POLICY and migrations' CREATE/DROP INDEX need
	// AccessExclusiveLock on those same tables, and Postgres lock
	// manager parks the DDL indefinitely behind the worker's lock —
	// the wedge tcc had to manually break. compose.QuiesceClients stops
	// the running clients before we enter the DDL window; compose.
	// ResumeClients restarts exactly the ones we stopped after the
	// window closes. db / proxy / caddy stay up throughout (db is the
	// DDL target; proxy + caddy serve maintenance views).
	//
	// We track quiesced state across the loop via a slice + bool pair
	// so the Resume call can fire exactly once even if Migrations was
	// already done (check passed) on the second invocation of install.
	var quiescedServices []string
	var quiesced bool
	resumeIfQuiesced := func() {
		if !quiesced {
			return
		}
		quiesced = false
		if err := compose.ResumeClients(installDir, quiescedServices); err != nil {
			// Don't fail the install — DB is correct, the DDL window has
			// closed, and the operator can restart services manually if
			// the Resume itself errored. Surface as a clear warning so
			// it's not silent.
			fmt.Printf("  ⚠ resume clients failed: %v — restart manually: ./sb start all_except_db\n", err)
		}
		quiescedServices = nil
	}

	for i, s := range steps {
		prefix := fmt.Sprintf("[%d/%d] %-20s", i+1, total, s.name)

		// Quiesce gate: enter the DDL window before Seed (only if we
		// actually need to run Seed; if check passes, skip quiesce and
		// stay outside the window). If a later step inside the window
		// (Migrations) succeeds, we exit on the way out. Names are
		// matched verbatim against the step slice above so renaming a
		// step here forces a deliberate revisit of this hook.
		if (s.name == "Seed" || s.name == "Migrations") && !quiesced && !s.check(installDir) {
			fmt.Printf("  [DDL] quiescing worker / app / rest before %s ...\n", s.name)
			stopped, err := compose.QuiesceClients(installDir)
			if err != nil {
				return fmt.Errorf("quiesce clients before %s: %w (must not proceed with DDL on live services)", s.name, err)
			}
			if len(stopped) == 0 {
				fmt.Printf("  [DDL] no clients were running; entering DDL window without stopping anything\n")
			} else {
				fmt.Printf("  [DDL] stopped %v; resume after Migrations succeeds\n", stopped)
			}
			quiescedServices = stopped
			quiesced = true
		}

		if s.check(installDir) {
			if s.name == "Seed" {
				// STATBUS-018: a Seed skip here means checkSeedRestored found
				// the schema already migrated / populated (its dbHasUserData /
				// dbHasAppliedMigrations / migrations-done branches; the
				// services-not-running defensive branch can't reach here — the
				// Services step precedes Seed). Report it honestly rather than a
				// bare "OK" so the operator sees the fast-path was deliberately
				// bypassed, not silently skipped.
				fmt.Printf("%s SKIPPED — schema already migrated\n", prefix)
			} else {
				fmt.Printf("%s OK\n", prefix)
			}
			// If we entered the quiesce window and Migrations was already
			// done (check passed on re-run after a prior partial install),
			// exit the window now — the DDL is fait accompli, services
			// can resume.
			if s.name == "Migrations" {
				resumeIfQuiesced()
			}
			continue
		}

		allDone = false
		fmt.Printf("%s RUNNING\n", prefix)

		if err := s.run(installDir); err != nil {
			line, fatal := stepRunOutcome(err)
			if !fatal {
				// Non-fatal degrade (the Seed fast-path was lost or no seed
				// image existed): report honestly — NEVER "DONE" over a
				// swallowed restore error (STATBUS-018) — and proceed to the
				// next step (Migrations, still inside the quiesce window),
				// which does the real work.
				fmt.Printf("%s %s\n", prefix, line)
				continue
			}
			fmt.Printf("%s FAILED: %v\n", prefix, err)
			if i < total-1 {
				fmt.Printf("\nFix the issue and re-run: ./sb install\n")
				fmt.Printf("(Steps 1-%d will be skipped automatically)\n", i)
			}
			// DO NOT auto-resume on failure: clients restarted on top of
			// a half-done DDL state could compound damage. The operator
			// re-runs ./sb install, which re-evaluates the quiesce window
			// from scratch (Migrations check fails → quiesce → run →
			// resume on success).
			return err
		}

		fmt.Printf("%s DONE\n", prefix)

		// Resume gate: leave the DDL window after Migrations succeeds.
		// We don't resume after Seed (Migrations comes next inside the
		// window) but we ALSO don't resume early if Seed was the last
		// thing we ran and Migrations was already done — the check-
		// passes branch above handles that case.
		if s.name == "Migrations" {
			resumeIfQuiesced()
		}
	}

	// Belt-and-suspenders: if the loop somehow exits with the quiesce
	// flag still set (shouldn't happen — Migrations is always before
	// the loop tail), resume so the system isn't left with clients down.
	resumeIfQuiesced()

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
	// Use positional service name `db` rather than `--filter name=db`. The
	// `--filter` flag's `name=` key is rejected by docker-compose v2.x as
	// "unknown filter name" — observed on rune.statbus.org (statbus-no-db
	// container, docker-compose Plugin 2025+). Positional service-name is
	// the supported invocation; the legacy filter-style only worked on
	// older lenient builds that silently accepted unknown filters.
	cmd := exec.Command("docker", "compose", "ps", "db", "--format", "{{.Health}}")
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

// userUnitPath returns the install destination for the user-level upgrade
// unit. The unit is copied here VERBATIM by runInstallService (copyFile is a
// byte copy; the %h/%i/%u specifiers resolve at systemd runtime, not at copy
// time), so the on-disk file should be byte-identical to the repo template.
func userUnitPath() string {
	return filepath.Join(os.Getenv("HOME"), ".config", "systemd", "user", "statbus-upgrade@.service")
}

// unitFileMatchesRepo reports whether the on-disk user unit is byte-identical
// to the repo template (<dir>/ops/statbus-upgrade.service). Because the unit
// is installed verbatim, a byte-compare is the exact drift check: a drifted
// unit (e.g. rune's stale WatchdogUSec=infinity / TimeoutStartSec=90 vs the
// repo's 120/120) mismatches and must be reconciled. A missing on-disk unit
// (fresh box) also reports false so install writes it. No systemd needed —
// this is the pure, unit-testable half of checkServiceDone.
func unitFileMatchesRepo(dir string) bool {
	repo, err := os.ReadFile(filepath.Join(dir, "ops", "statbus-upgrade.service"))
	if err != nil {
		// No repo template to compare against — can't assert drift; treat as
		// "matches" so a missing source doesn't wedge the install ladder.
		return true
	}
	onDisk, err := os.ReadFile(userUnitPath())
	if err != nil {
		return false // missing / unreadable on-disk unit ⇒ reconcile (write it)
	}
	return bytes.Equal(repo, onDisk)
}

func checkServiceDone(dir string) bool {
	if runtime.GOOS != "linux" {
		return true // Skip on non-Linux
	}
	instance := serviceInstance(dir)
	if instance == "" {
		return false
	}
	// #4 unit-reconcile: a healthy (active) unit is NOT "done" if its on-disk
	// file has drifted from the repo template — otherwise a box that booted an
	// old unit keeps stale WatchdogSec/TimeoutStartSec forever (the rune
	// 90/infinity drift). Drift ⇒ not-done ⇒ runInstallService rewrites +
	// daemon-reload + restarts so the new timers actually arm.
	if !unitFileMatchesRepo(dir) {
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

// checkSessionsClean returns true iff there are no detectable ZOMBIES
// requiring cleanup. Two zombie classes:
//   - Empty-application_name advisory-lock holders (pre-rc.07 zombies
//     from a killed migrate.Up before Fix 6a tagged its sessions, OR
//     unknown external clients holding session-level locks)
//   - Backends > 5 minutes old running TRUNCATE/INSERT/CALL on
//     statistical_* tables (subprocess zombies from a killed migrate.Up's
//     psql children)
//
// Pool saturation alone is NOT a zombie signal. PostgREST + worker + app
// generate legitimate connection bursts that exceed any reasonable
// "% of max_connections" threshold during normal operation —
// worker.process_tasks alone can spike connections during queue draining.
// Earlier versions of this function flagged saturation as unhealthy, which
// caused cleanOrphanSessions's recheck-after-cleanup to falsely fail on
// healthy busy systems (observed on rune post-recovery; the rc.07/08/09
// install-fixups all failed at step 9 not because cleanup didn't work
// but because the worker was momentarily busy when the recheck SQL ran).
//
// If you genuinely have max_clients exhausted with no zombies visible,
// the system is just overloaded — that's a different problem with a
// different remedy (raise max_connections, reduce client count). Not
// something cleanOrphanSessions can fix.
//
// The GATE itself is now PID-liveness-aware (STATBUS-055): it shares the
// zombieAdvisoryHolders detection with cleanOrphanSessions Phase 2, so a dead-PID
// statbus-migrate-<PID> advisory holder TRIGGERS cleanup. Previously the gate's
// SQL counted only EMPTY-application_name advisory holders and missed the tagged
// dead-PID holder; because Phase 2 runs ONLY when this gate returns false, that
// blindness meant the cleanup never ran and the next migrate stalled on the held
// lock (a bounded multi-minute recovery delay). The gate and the action now use
// one detection, so they can never diverge again.
// checkBackupOwnershipDone returns true iff every pre-upgrade-* dir
// in ~/statbus-backups/ is owned by the deploy user. False (need to
// heal) iff at least one is owned by someone else — typically the
// in-container postgres user (uid 70 on alpine-postgres, uid 101
// on debian-postgres) leaking through the rsync container's bind
// mount as messagebus / arbitrary system user on the host.
//
// No backups present → trivially "done" (nothing to heal).
// HOME unreadable → trivially "done" (caller can't recover further).
func checkBackupOwnershipDone(_ string) bool {
	home, err := os.UserHomeDir()
	if err != nil {
		return true
	}
	root := filepath.Join(home, "statbus-backups")
	entries, err := os.ReadDir(root)
	if err != nil {
		// Backup root doesn't exist yet → nothing to heal.
		return true
	}
	deployUID := uint32(os.Getuid())
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasPrefix(name, "pre-upgrade-") {
			continue
		}
		info, err := os.Stat(filepath.Join(root, name))
		if err != nil {
			continue // skip unreadable entries; subsequent runs catch them
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok {
			continue // non-POSIX platform; can't probe ownership
		}
		if stat.Uid != deployUID {
			return false // at least one dir needs healing
		}
	}
	return true
}

// healBackupOwnership chowns every pre-upgrade-* dir under
// ~/statbus-backups/ to the deploy user via a single alpine container.
// The container runs as root and can change ownership; the host-side
// process (statbus_<slot>) cannot, because the dirs are currently
// owned by the in-container postgres user that leaked through the
// rsync bind mount during backup creation.
//
// chmod -R u=rwX,go=rX yields 0755 on dirs / 0644 on files — making
// them traversable (pruneBackups can remove them) and readable
// (support-bundle archive step can tar them) while keeping write
// restricted to the deploy user.
//
// Idempotent: re-running on already-deploy-user-owned dirs is a no-op
// (chown to the same uid is a metadata-only operation; chmod to the
// same mode is also a no-op).
func healBackupOwnership(_ string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot determine home directory (HOME unset?): %w", err)
	}
	root := filepath.Join(home, "statbus-backups")
	if _, err := os.Stat(root); err != nil {
		// Nothing to heal — backup root missing or unreadable.
		return nil
	}
	deployUID := os.Getuid()
	deployGID := os.Getgid()
	// One alpine container, one find invocation, all pre-upgrade-* dirs
	// at once. The `-mindepth 1 -maxdepth 1` keeps the chown contained
	// to top-level entries (we recurse via -R below, separately, to keep
	// the find expression tractable).
	shellCmd := fmt.Sprintf(
		"find /backup -mindepth 1 -maxdepth 1 -name 'pre-upgrade-*' -type d "+
			"-exec chown -R %d:%d {} + -exec chmod -R u=rwX,go=rX {} +",
		deployUID, deployGID,
	)
	cmd := exec.Command("docker", "run", "--rm",
		"-v", root+":/backup",
		"alpine", "sh", "-c", shellCmd,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("docker chown of %s failed: %w\n%s", root, err, out)
	}
	return nil
}

// ── STATBUS-055: shared zombie-advisory-holder detection ─────────────────────
//
// The migrate advisory lock (pg_advisory_lock(hashtext('migrate_up'))) is held
// by a Go connection tagged `statbus-migrate-<pid>` (migrate.acquireAdvisoryLock,
// migrate.go). When that migrate process dies (OOM / SIGKILL / reboot) but its
// connection lingers (a proxy absorbs the socket close until TCP keepalive reaps
// it), the server still shows a GRANTED advisory lock held by a dead-PID-tagged
// backend. Pure SQL cannot tell dead from live — only a host-side
// syscall.Kill(pid, 0) can. This detection is SHARED by the gate
// (checkSessionsClean — decide whether to clean) and the action
// (cleanOrphanSessions Phase 2 — the kill), so the gate can never again be blind
// to what the action can reclaim (the STATBUS-055 gap).
//
// syscall.Kill is meaningful ONLY on the host where migrate's PID lived; every
// caller runs inside `./sb install` on that host (all checkSessionsClean callers
// + cleanOrphanSessions).

// zombieHolder is an advisory-lock holder whose lock should be reclaimed.
type zombieHolder struct {
	BackendPID int
	AppName    string
	Reason     string
}

// procAlive reports whether pid is a live process. Any syscall.Kill error (ESRCH
// = dead; also EPERM) is treated as not-live — matching the prior inline Phase-2
// behaviour; safe because migrate runs as the same user as install, so EPERM does
// not arise for our own migrate PIDs.
func procAlive(pid int) bool { return syscall.Kill(pid, 0) == nil }

// classifyAdvisoryHolder decides whether an advisory-lock holder with the given
// application_name is a zombie whose lock should be reclaimed. Pure (the PID
// liveness probe is injected), so it is Docker-free unit-tested:
//   - ""                                     → zombie (unidentified — see below).
//   - "statbus-migrate-<pid>" dead           → zombie.
//   - "statbus-migrate-<pid>" alive          → legitimate (a healthy migration
//     idling between statements); leave alone.
//   - "statbus-upgrade-daemon-<pid>" dead    → zombie (STATBUS-149).
//   - "statbus-upgrade-daemon-<pid>" alive   → legitimate (the running upgrade
//     daemon's own lock connection); leave alone.
//   - malformed tag (Atoi fails, e.g. the "statbus-migrate-sql-<pid>" SUBPROCESS
//     tag) or any other app_name (worker / psql / PostgREST pool) → leave alone.
//
// KNOWN STATBUS advisory-lock tags on the app DB (all our clients now tag
// themselves): 'statbus-migrate-<pid>' (migrate.go:833) and
// 'statbus-upgrade-daemon-<pid>' (service.go recoveryDSN). (migrate SUBPROCESS
// psql tags 'statbus-migrate-sql-<pid>' but does not hold this lock;
// 'statbus-seed-*' from AcquireSeedLock connects to dbname=postgres and is
// filtered out by zombieAdvisoryHolders' a.datname = current_database().) With
// every client tagged, an EMPTY application_name on our DB is genuinely
// unidentified → kill it; a future untagged client is diagnosable by diffing an
// observed tag against this list.
func classifyAdvisoryHolder(appName string, pidAlive func(int) bool) (zombie bool, reason string) {
	switch {
	case appName == "":
		return true, "empty application_name → unidentified zombie"
	case strings.HasPrefix(appName, "statbus-migrate-"):
		ownerStr := strings.TrimPrefix(appName, "statbus-migrate-")
		ownerPID, err := strconv.Atoi(ownerStr)
		if err != nil {
			return false, fmt.Sprintf("malformed migrate tag %q → leaving alone", appName)
		}
		if !pidAlive(ownerPID) {
			return true, fmt.Sprintf("owner PID %d is dead → zombie", ownerPID)
		}
		return false, fmt.Sprintf("owner PID %d is alive → legitimate", ownerPID)
	case strings.HasPrefix(appName, "statbus-upgrade-daemon-"):
		ownerStr := strings.TrimPrefix(appName, "statbus-upgrade-daemon-")
		ownerPID, err := strconv.Atoi(ownerStr)
		if err != nil {
			return false, fmt.Sprintf("malformed upgrade-daemon tag %q → leaving alone", appName)
		}
		if !pidAlive(ownerPID) {
			return true, fmt.Sprintf("upgrade-daemon owner PID %d is dead → zombie", ownerPID)
		}
		return false, fmt.Sprintf("upgrade-daemon owner PID %d is alive → legitimate", ownerPID)
	default:
		return false, fmt.Sprintf("non-statbus-managed application_name %q → legitimate", appName)
	}
}

// zombieAdvisoryHolders queries every advisory-lock holder in the app DB and
// returns those classified as zombies (empty-app or dead-PID-tagged). Uses the
// pool-bypassing `docker compose exec -T db psql` path (peer-auth superuser) so
// it works even when the connection pool is saturated. Shared by the gate and
// cleanOrphanSessions Phase 2.
func zombieAdvisoryHolders(dir string) ([]zombieHolder, error) {
	envFile, err := dotenv.Load(filepath.Join(dir, ".env"))
	if err != nil {
		return nil, fmt.Errorf("load .env for docker psql: %w", err)
	}
	dbName := "statbus_local"
	if v, ok := envFile.Get("POSTGRES_APP_DB"); ok && v != "" {
		dbName = v
	}
	adminUser := "postgres"
	if v, ok := envFile.Get("POSTGRES_ADMIN_USER"); ok && v != "" {
		adminUser = v
	}
	q := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", adminUser, "-d", dbName, "-t", "-A", "-F", "|", "-c", `
		SELECT a.pid, COALESCE(a.application_name, '')
		  FROM pg_stat_activity a
		  JOIN pg_locks l ON l.pid = a.pid
		 WHERE l.locktype = 'advisory'
		   AND l.granted
		   AND a.datname = current_database()
		   AND a.pid <> pg_backend_pid()
		 ORDER BY a.pid;`)
	q.Dir = dir
	out, err := q.Output()
	if err != nil {
		return nil, fmt.Errorf("query advisory-lock holders: %w", err)
	}
	var zombies []zombieHolder
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "|", 2)
		if len(parts) != 2 {
			continue
		}
		backendPID, perr := strconv.Atoi(strings.TrimSpace(parts[0]))
		if perr != nil {
			continue
		}
		appName := strings.TrimSpace(parts[1])
		if z, reason := classifyAdvisoryHolder(appName, procAlive); z {
			zombies = append(zombies, zombieHolder{BackendPID: backendPID, AppName: appName, Reason: reason})
		}
	}
	return zombies, nil
}

// sessionsVerdictKind is the tri-state outcome of a sessions probe (STATBUS-139).
// The pre-139 code collapsed all three onto a single bool, so "cannot verify" and
// "verified dirty" were indistinguishable — correct for the GATE (can't verify →
// run cleanup) but WRONG for the VERDICT after cleanup, where a probe that merely
// couldn't get a connection slot became a hard "still saturated" false alarm.
type sessionsVerdictKind int

const (
	sessionsClean        sessionsVerdictKind = iota // no leaked backends, no zombie holders — verified
	sessionsDirty                                   // leaked backends and/or zombie holders — verified
	sessionsUnverifiable                            // the probe itself failed (e.g. DB unreachable)
)

// sessionsVerdict carries the tri-state plus the EVIDENCE (STATBUS-139 (d)): the
// leaked count, the zombie pids, or the probe error — so a failure names WHAT was
// observed and 'draining' is distinguishable from 'wedged'.
type sessionsVerdict struct {
	kind     sessionsVerdictKind
	leaked   int
	zombies  []zombieHolder
	probeErr error
}

// classifySessions is the PURE tri-state mapping (STATBUS-139 (b)) — no I/O, so it
// is unit-tested directly. A probe error is UNVERIFIABLE (retry), never dirty; a
// clean read requires BOTH zero leaked and zero zombies; anything else is verified
// DIRTY with its counts.
func classifySessions(leaked int, zombies []zombieHolder, probeErr error) sessionsVerdict {
	if probeErr != nil {
		return sessionsVerdict{kind: sessionsUnverifiable, probeErr: probeErr}
	}
	if leaked == 0 && len(zombies) == 0 {
		return sessionsVerdict{kind: sessionsClean}
	}
	return sessionsVerdict{kind: sessionsDirty, leaked: leaked, zombies: zombies}
}

// describe renders the observed evidence for the operator-facing message.
func (v sessionsVerdict) describe() string {
	switch v.kind {
	case sessionsClean:
		return "sessions clean (no leaked migrate backends, no zombie advisory holders)"
	case sessionsDirty:
		pids := make([]string, len(v.zombies))
		for i, z := range v.zombies {
			pids[i] = strconv.Itoa(z.BackendPID)
		}
		return fmt.Sprintf("%d leaked migrate backend(s); %d zombie advisory holder(s) on pid(s) [%s]",
			v.leaked, len(v.zombies), strings.Join(pids, ", "))
	case sessionsUnverifiable:
		return fmt.Sprintf("sessions state could not be verified (probe error: %v)", v.probeErr)
	default:
		return "unknown sessions verdict"
	}
}

// countLeakedOrphans counts aged psql-subprocess zombies (a killed migrate.Up's
// psql children still running TRUNCATE/INSERT/CALL on statistical_* tables >5min).
// Match BOTH the libpq default 'psql' and the task-#14 'statbus-migrate-sql%' tag;
// the worker (application_name='worker') legitimately runs CALL
// worker.statistical_*_reduce for minutes on Norway-sized data, so filtering by
// app_name avoids false-positive cleanup-failures during healthy operation.
//
// STATBUS-139 (a): runs on the pool-BYPASSING `docker compose exec -T db psql`
// peer-auth path (same transport as zombieAdvisoryHolders + cleanOrphanSessions),
// NOT the pool-limited migrate.PsqlCommand external path the pre-139 probe used. The
// observer must not ride the observed resource: during a post-restart reconnection
// burst on a small max_connections box, the external path can't get a slot → the old
// probe returned a false 'saturated' during the exact condition it existed to judge.
func countLeakedOrphans(dir string) (int, error) {
	envFile, err := dotenv.Load(filepath.Join(dir, ".env"))
	if err != nil {
		return 0, fmt.Errorf("load .env for docker psql: %w", err)
	}
	dbName := "statbus_local"
	if v, ok := envFile.Get("POSTGRES_APP_DB"); ok && v != "" {
		dbName = v
	}
	adminUser := "postgres"
	if v, ok := envFile.Get("POSTGRES_ADMIN_USER"); ok && v != "" {
		adminUser = v
	}
	q := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", adminUser, "-d", dbName, "-t", "-A", "-c", `
		SELECT count(*) FROM pg_stat_activity
		  WHERE datname = current_database()
		    AND state IN ('active', 'idle in transaction')
		    AND query_start < now() - interval '5 minutes'
		    AND (application_name = 'psql' OR application_name LIKE 'statbus-migrate-sql%')
		    AND (query ILIKE '%TRUNCATE %statistical_%'
		         OR query ILIKE '%INSERT INTO %statistical_%'
		         OR query ILIKE '%CALL %statistical_%');`)
	q.Dir = dir
	out, err := q.Output()
	if err != nil {
		return 0, fmt.Errorf("query leaked migrate backends (docker-exec): %w", err)
	}
	leaked, err := strconv.Atoi(strings.TrimSpace(string(out)))
	if err != nil {
		return 0, fmt.Errorf("parse leaked-backend count %q: %w", strings.TrimSpace(string(out)), err)
	}
	return leaked, nil
}

// probeSessionsVerdict produces the tri-state verdict from the two pool-INDEPENDENT
// docker-exec probes (leaked-orphan count + zombie advisory holders). Either probe
// erroring → UNVERIFIABLE (never a false dirty). STATBUS-139.
func probeSessionsVerdict(dir string) sessionsVerdict {
	leaked, err := countLeakedOrphans(dir)
	if err != nil {
		return classifySessions(0, nil, err)
	}
	// Zombie advisory-lock holders — empty-app OR dead-PID-tagged statbus-migrate-<pid>
	// (STATBUS-055). PID-liveness needs Go, not SQL; SHARED with cleanOrphanSessions
	// Phase 2 so the verdict detects EXACTLY what Phase 2 reclaims.
	zombies, err := zombieAdvisoryHolders(dir)
	if err != nil {
		return classifySessions(0, nil, err)
	}
	return classifySessions(leaked, zombies, nil)
}

// checkSessionsClean is the GATE predicate (step-table + the recovery pre-check at
// :328). Conservative-false on anything but a verified-clean read: unverifiable OR
// dirty → run cleanup. This bool is CORRECT for the gate ("can't verify → clean up")
// but must NOT be used as the post-cleanup VERDICT — that path uses the tri-state
// (probeSessionsVerdict) so an unverifiable probe retries instead of hard-failing
// (STATBUS-139 defect 1: verdict-role conflation).
func checkSessionsClean(dir string) bool {
	return probeSessionsVerdict(dir).kind == sessionsClean
}

// Bounded settle window for the post-cleanup sessions verdict (STATBUS-139 (c)).
// Slot release after pg_terminate_backend AND a post-restart reconnection burst are
// ASYNC wrt the SQL return, so a single probe races the drain; re-probe on a bounded
// loop and succeed on the first clean read. Cap sized for a reconnection burst on a
// small (max_connections=30) box — longer than the pre-139 fixed 2s.
//
// sessionsSettleMaxKillAttempts is STATBUS-149's REQUIRED bound on the settle
// loop's kill authority (below): a zombie advisory holder that reappears after
// being killed (the 173→312→442 escalation this ticket investigated — a genuine
// regenerating source, mechanism not yet pinned) must FAIL LOUDLY once it has
// happened this many times, never be silently re-killed forever. Without the
// bound, kill-in-loop would convert a regenerating leak into a quiet success —
// exactly the finding this ticket exists to keep visible, not paper over.
const (
	sessionsSettleInterval        = 4 * time.Second
	sessionsSettleCap             = 48 * time.Second
	sessionsSettleMaxKillAttempts = 5
)

// cleanOrphanSessions terminates leaked backends from prior crashed
// upgrade attempts so the next migrate-up has free connection slots.
//
// Connects via `docker compose exec -T db psql -U postgres`, NOT
// migrate.PsqlCommand. Critical: when max_connections is exhausted,
// EVERY external connection fails — including ones nominally targeting
// `superuser_reserved_connections` — because the reserved slots are
// gated on the AUTH ROLE (must be superuser), not the connection
// target. The statbus role is not superuser; reserved slots are
// unreachable from the host.
//
// Connecting *inside* the container as the postgres OS user via peer
// authentication gives full superuser privileges and bypasses the
// connection pool entirely. This is the only path that works when the
// pool is wedged.
//
// TWO-PHASE design:
//
//	Phase 1 — heuristic kill via SQL alone:
//	  1a. Backend > 2 minutes old in active or idle-in-transaction state
//	      (orphaned subprocess connections from killed migrate-up runs).
//	  1b. Backend running a query touching statistical_history (the
//	      heavy migration that gets caught in the timeout loop on
//	      at-scale data — usually subprocess-level).
//
//	Phase 2 — advisory-lock holder triage with PID liveness:
//	  Pure SQL can't probe host-side process liveness. Phase 1's
//	  heuristic misses the most damaging zombie type: an IDLE backend
//	  holding the migrate_up advisory lock (post-acquire, between SQL
//	  statements) whose owning Go process died. The session is in
//	  state='idle' which Phase 1 explicitly avoids — killing healthy
//	  idle sessions would be unsafe.
//
//	  Phase 2 queries advisory-lock holders, parses the
//	  application_name marker (set by migrate.acquireAdvisoryLock as
//	  'statbus-migrate-<PID>'), and runs syscall.Kill(PID, 0) per
//	  candidate. ESRCH → owner is dead → zombie → terminate. Empty
//	  application_name → pre-rc.07 binary or unknown client → also
//	  terminate. Live PID → legitimate work, skip.
//
//	  This is what protects a healthy 30-minute migration whose
//	  parent connection is idle for most of the wall-clock time:
//	  the marker resolves to a live PID, cleanup skips it.
//
// Bounded settle loop + tri-state recheck after both phases (STATBUS-139).
// Slot release is async, so we re-probe (pool-independent docker-exec) up to
// sessionsSettleCap and succeed on the first verified-clean read. A hard fail only
// on a VERIFIED verdict that names what was observed (leaked count / zombie pids /
// probe error) — never a bare 'saturated' from a probe that itself couldn't get a
// slot. This is NOT silent retry: the terminal failure still surfaces the evidence.
//
// Idempotent: on a healthy system Phase 1's WHERE clause matches zero
// rows, Phase 2's advisory-lock query matches zero, and the recheck
// passes cleanly. Self-targeting is excluded via
// `pid <> pg_backend_pid()`.
//
// Orphan-class split (task #14): this is the RECOVERY-TIME half. It cleans a
// migrate psql backend orphaned because the OWNING Go process itself died
// mid-migrate (service OOM / host SIGKILL / reboot) — no runCommandToLog timeout
// fired, so the in-line terminate-on-timeout (upgrade.terminateMigrateOrphan)
// never ran. The two are complementary; Phase 1 now matches BOTH the libpq
// default 'psql' and the #14 tag 'statbus-migrate-sql%' so it catches the
// orphan whichever binary started the migrate.

// terminateZombieAdvisoryHolders issues pg_terminate_backend for every zombie
// in the given list (logging each one loudly: pid + classification reason —
// STATBUS-149, so an instrumented run documents the kill cadence for free),
// via the same docker-exec superuser path the rest of this file uses. Returns
// the count killed. No-op (0, nil) on an empty list. Shared by
// cleanOrphanSessions's initial Phase 2 pass AND its settle-loop re-kill
// (STATBUS-149) — ONE kill code path, so they can never drift into different
// kill logic ("no new classification arms").
func terminateZombieAdvisoryHolders(dir, adminUser, dbName string, zombies []zombieHolder) (int, error) {
	if len(zombies) == 0 {
		return 0, nil
	}
	pidsToKill := make([]int, 0, len(zombies))
	for _, h := range zombies {
		fmt.Printf("  Advisory-lock holder PID %d (%s): %s → terminating\n", h.BackendPID, h.AppName, h.Reason)
		pidsToKill = append(pidsToKill, h.BackendPID)
	}
	sqlPids := make([]string, len(pidsToKill))
	for i, p := range pidsToKill {
		sqlPids[i] = strconv.Itoa(p)
	}
	killSQL := fmt.Sprintf(`SELECT pg_terminate_backend(pid), pid FROM pg_stat_activity WHERE pid IN (%s);`,
		strings.Join(sqlPids, ","))
	killCmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", adminUser, "-d", dbName, "-c", killSQL)
	killCmd.Dir = dir
	killCmd.Stdout = os.Stdout
	killCmd.Stderr = os.Stderr
	if err := killCmd.Run(); err != nil {
		return 0, fmt.Errorf("pg_terminate_backend: %w", err)
	}
	return len(pidsToKill), nil
}

// settleLoopMayKillAgain is STATBUS-149's pure bound check: the settle loop
// below may issue another zombie-kill attempt only while under
// sessionsSettleMaxKillAttempts. Extracted so the bound itself is
// Docker-free unit-tested (the "bound trips at N+1" case), independent of
// the loop's own docker-exec plumbing.
func settleLoopMayKillAgain(killAttempts, maxKillAttempts int) bool {
	return killAttempts < maxKillAttempts
}

// regeneratingZombieError is STATBUS-149's bounded-exhaustion message: a
// zombie advisory holder that keeps reappearing after being killed is a
// regenerating source, not a one-off leak — kill-in-loop must fail loudly
// once the bound is hit rather than silently mask it as eventual success.
// Pure (no I/O) so the exact wording is unit-tested directly.
func regeneratingZombieError(totalKilled, killAttempts int, last sessionsVerdict) error {
	return fmt.Errorf(
		"zombie advisory-lock source is REGENERATING (%d killed across %d attempt(s), still appearing) — "+
			"not a one-off leak; the underlying source needs investigation (STATBUS-149), not another kill. "+
			"Last observed: %s. Check `journalctl --user -u 'statbus-upgrade@*'` for the underlying cause and re-run ./sb install",
		totalKilled, killAttempts, last.describe())
}

func cleanOrphanSessions(dir string) error {
	envFile, err := dotenv.Load(filepath.Join(dir, ".env"))
	if err != nil {
		return fmt.Errorf("load .env for docker psql: %w", err)
	}
	dbName := "statbus_local"
	if v, ok := envFile.Get("POSTGRES_APP_DB"); ok && v != "" {
		dbName = v
	}
	adminUser := "postgres"
	if v, ok := envFile.Get("POSTGRES_ADMIN_USER"); ok && v != "" {
		adminUser = v
	}

	// Phase 1: heuristic kill of obvious zombies.
	// CRITICAL: filter by application_name to avoid terminating legitimate
	// worker connections. The worker (application_name='worker') runs CALL
	// worker.statistical_*_reduce as part of normal task processing — those
	// reduces match the statistical_history pattern AND can run for >2 minutes
	// on Norway-sized data, so without this filter Phase 1 would aggressively
	// terminate healthy worker connections. Migrate.Up's psql subprocesses are
	// tagged statbus-migrate-sql-<pid> (task #14, via PGAPPNAME); pre-#14
	// binaries left the libpq default 'psql'. Match BOTH so we still clean a
	// SIGKILL'd migrate zombie regardless of which binary started it.
	phase1 := exec.Command("docker", "compose", "exec", "-T", "db",
		"psql", "-U", adminUser, "-d", dbName, "-c", `
		SELECT pg_terminate_backend(pid), pid, query_start, left(query, 80) AS query
		  FROM pg_stat_activity
		 WHERE datname = current_database()
		   AND pid <> pg_backend_pid()
		   AND (application_name = 'psql' OR application_name LIKE 'statbus-migrate-sql%')
		   AND (
			   (state IN ('active', 'idle in transaction')
			    AND query_start < now() - interval '2 minutes')
			   OR
			   query ILIKE '%statistical_history%'
		   );`)
	phase1.Dir = dir
	phase1.Stdout = os.Stdout
	phase1.Stderr = os.Stderr
	if err := phase1.Run(); err != nil {
		return fmt.Errorf("phase 1 pg_terminate_backend (docker exec): %w", err)
	}

	// Phase 2: reclaim zombie advisory-lock holders (empty-app or dead-PID-tagged
	// statbus-migrate-<pid>) via the SHARED detection (STATBUS-055) — the same
	// zombieAdvisoryHolders helper the gate (checkSessionsClean) uses to decide
	// whether to run this cleanup, so the gate can never be blind to what this
	// kills. The kill authority stays HERE, in terminateZombieAdvisoryHolders —
	// STATBUS-149 reuses this SAME kill code path from the settle loop below, so
	// the two can never drift into different kill logic.
	zombies, err := zombieAdvisoryHolders(dir)
	if err != nil {
		return fmt.Errorf("phase 2 detect zombie advisory holders: %w", err)
	}
	if _, err := terminateZombieAdvisoryHolders(dir, adminUser, dbName, zombies); err != nil {
		return fmt.Errorf("phase 2 pg_terminate_backend: %w", err)
	}

	// Bounded settle loop (STATBUS-139), now WITH KILL AUTHORITY (STATBUS-149):
	// re-probe the tri-state verdict on the pool-INDEPENDENT docker-exec transport
	// and SUCCEED on the first verified-clean read. Slot release + a post-restart
	// reconnection burst are async wrt the pg_terminate_backend return, so a single
	// probe races the drain — the pre-139 bug that turned a self-resolving
	// transient into a hard 'still saturated' exit-1. We probe immediately (fast
	// path: already clean → no wait), then poll every sessionsSettleInterval up to
	// sessionsSettleCap. On timeout we FAIL naming what was actually observed
	// (last.describe(): leaked count / zombie pids / probe error) — distinguishing
	// 'draining' (retried, then genuinely wedged) from a probe that couldn't verify.
	//
	// STATBUS-149: pre-149, this loop only re-PROBED — probeSessionsVerdict shares
	// zombieAdvisoryHolders with Phase 2 above, so it correctly RE-CLASSIFIED any
	// zombie appearing after Phase 2's one-shot kill, but had no way to reclaim it
	// (the settle-loop-only zombie was the exact 149 finding: pid 442 was never
	// killed because nothing in this loop ever called terminateZombieAdvisoryHolders
	// on it). Now: any zombie the probe sees gets the SAME kill Phase 2 already
	// performs — no new classification arms, same code path
	// (terminateZombieAdvisoryHolders) — bounded at sessionsSettleMaxKillAttempts.
	// The bound is REQUIRED, not incidental: a regenerating source (the
	// 173→312→442 escalation this ticket investigated) killed in an unbounded loop
	// would eventually "succeed" by outlasting the settle window while never
	// actually fixing anything — converting a real, still-unexplained leak into
	// silent green. Exceeding the bound fails loudly instead, naming exactly how
	// many were killed and how many attempts it took, so the regenerating source
	// stays visible rather than getting laundered into a passing step.
	deadline := time.Now().Add(sessionsSettleCap)
	var last sessionsVerdict
	killAttempts := 0
	totalKilled := 0
	for {
		last = probeSessionsVerdict(dir)
		if last.kind == sessionsClean {
			return nil
		}
		if last.kind == sessionsDirty && len(last.zombies) > 0 {
			if !settleLoopMayKillAgain(killAttempts, sessionsSettleMaxKillAttempts) {
				return regeneratingZombieError(totalKilled, killAttempts, last)
			}
			n, err := terminateZombieAdvisoryHolders(dir, adminUser, dbName, last.zombies)
			if err != nil {
				return fmt.Errorf("settle-loop zombie re-kill (attempt %d): %w", killAttempts+1, err)
			}
			killAttempts++
			totalKilled += n
		}
		if !time.Now().Before(deadline) {
			break
		}
		time.Sleep(sessionsSettleInterval)
	}
	return fmt.Errorf(
		"database sessions did not settle within %s after cleanOrphanSessions — %s. "+
			"Check `journalctl --user -u 'statbus-upgrade@*'` for the underlying cause and re-run ./sb install",
		sessionsSettleCap, last.describe())
}

// checkSeedRestored returns true if the database already has migrations
// OR holds user data (either way, seed restore would be destructive).
// Returns false only for truly fresh installs where the DB is empty.
//
// Intent: the seed is a FAST PATH for fresh installs only. Restoring
// over an existing database drops objects while migration records survive,
// leaving the DB in an inconsistent state.
//
// R5 classifier (added 2026-05-23 from tcc-near-miss forensics): the
// migration-tail check alone is insufficient. When an operator pulls a
// newer tree against a populated DB, the on-disk migration set is
// ahead of db.migration, so HasPending returns true → migrations-done
// returns false → and the seed step ran destructively against user
// data. The dbHasUserData probe below short-circuits BEFORE the
// migration check: if any user-facing table holds rows, route to
// migrate-forward regardless of the migration delta.
func checkSeedRestored(dir string) bool {
	// If services aren't running yet, we can't check the DB.
	// Return true to skip — the Services step must run first.
	if !checkServicesDone(dir) {
		return true
	}

	// Services are running. Wait for DB to be healthy, then check
	// content + migrations. If we can't reach the DB after 30 seconds,
	// FAIL HARD — don't silently fall through and restore a seed over
	// an existing database. The dbHasUserData check fires BEFORE the
	// migration check so populated DBs short-circuit even when their
	// migration tail is behind.
	for attempt := 0; attempt < 15; attempt++ {
		// R5 short-circuit: populated DBs NEVER run seed.
		if dbHasUserData(dir) {
			return true
		}
		// STATBUS-018: a schema ANY migration has touched already holds the
		// sql_saga era objects (updatable views + their protected triggers)
		// that the seed's pg_restore --clean would try to DROP — and the
		// sql_saga_drop_protection sql_drop event trigger refuses that DROP,
		// rolling the whole atomic restore back. dbHasUserData catches only
		// the rows-present half of "populated"; this catches the
		// schema-present-but-rowless half (the operator pulled a newer tree
		// against a migrated-but-empty DB). Seed runs ONLY on a schema no
		// migration has touched.
		if dbHasAppliedMigrations(dir) {
			return true
		}
		if checkMigrationsDone(dir) {
			return true // DB has migrations — do NOT restore seed
		}
		if attempt < 14 {
			time.Sleep(2 * time.Second)
		}
	}

	// DB is reachable (services running), holds no user data, AND no
	// migrations are applied. This is a genuinely fresh database — seed
	// restore is appropriate.
	return false
}

// dbHasUserData returns true if the application database holds rows in
// any user-facing table (statistical_unit, legal_unit, establishment,
// import_job). The probe is conservative: any failure (DB unreachable,
// table missing on a brand-new DB, psql binary absent) is treated as
// "no user data" so the fresh-install path still runs the seed step.
// The R5 classifier in checkSeedRestored guards a destructive action,
// so the principled posture on probe error is "don't ASSUME populated"
// — we ASSUME empty when we can't tell, because that lets fresh
// installs proceed. The downstream migrate-forward path catches the
// false-negative case: if the DB is populated but the probe failed,
// the seed restore would still need the tables to exist, and
// pg_restore --single-transaction --clean --if-exists would either
// succeed (genuinely empty) or roll back loudly (populated, the
// runPgRestoreAtomic wrapper from 1f077e545 fails the install).
//
// Tables checked: the same four the harness's
// assert_demo_data_present uses. Adding tables to the demo dataset
// requires updating both — the cross-reference is documented in
// data-helpers.sh's populate_with_demo_data and in this comment.
func dbHasUserData(dir string) bool {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	const probe = `
SELECT EXISTS (
  SELECT 1 FROM public.statistical_unit LIMIT 1
  UNION ALL SELECT 1 FROM public.legal_unit LIMIT 1
  UNION ALL SELECT 1 FROM public.establishment LIMIT 1
  UNION ALL SELECT 1 FROM public.import_job LIMIT 1
);`
	args := append([]string{}, prefix...)
	args = append(args, "-t", "-A", "-v", "ON_ERROR_STOP=on", "-c", probe)
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		// Table missing (very early install before migrations ran),
		// connection refused, etc. Treat as "no user data" so the
		// fresh-install path still triggers the seed step.
		return false
	}
	return strings.TrimSpace(string(out)) == "t"
}

// dbHasAppliedMigrations reports whether db.migration holds at least one
// APPLIED row — i.e. whether any migration has touched this schema. It is the
// STATBUS-018 companion to dbHasUserData: dbHasUserData gates on rows in the
// user tables, this gates on schema having been migrated at all. The two
// together mean the seed fast-path (pg_restore --clean) is attempted ONLY on a
// schema no migration has touched.
//
// The probe is conservative in the same direction dbHasUserData is: any failure
// (DB unreachable, psql absent, and crucially the db.migration table not
// existing yet on a brand-new cluster) is treated as "not migrated" → false, so
// the genuinely-fresh install path still runs the seed step. See
// interpretAppliedMigrationsProbe for the (output, error) → verdict matrix.
func dbHasAppliedMigrations(dir string) bool {
	psqlPath, prefix, env, err := migrate.PsqlCommand(dir)
	if err != nil {
		return false
	}
	// EXISTS(... LIMIT 1) is O(1). When db.migration does not exist yet
	// (fresh cluster, before ensureMigrationTable), psql errors with
	// `relation "db.migration" does not exist` and cmd.Output returns a
	// non-nil error — interpretAppliedMigrationsProbe maps that to false.
	const probe = `SELECT EXISTS (SELECT 1 FROM db.migration LIMIT 1);`
	args := append([]string{}, prefix...)
	args = append(args, "-t", "-A", "-v", "ON_ERROR_STOP=on", "-c", probe)
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = dir
	cmd.Env = env
	out, err := cmd.Output()
	return interpretAppliedMigrationsProbe(string(out), err)
}

// interpretAppliedMigrationsProbe is the PURE verdict behind
// dbHasAppliedMigrations, factored out so the STATBUS-018 probe matrix is unit-
// testable without a live database (the classifyAdvisoryHolder / classifySessions
// pattern in this package). The matrix:
//   - missing db.migration table (fresh cluster, pre-ensureMigrationTable):
//     the probe ERRORS → probeErr != nil → false (schema untouched, seed winnable).
//   - table present but EMPTY (ensureMigrationTable created it, no migration has
//     applied yet): probe returns "f" → false (still winnable — no eras exist).
//   - table present with >= 1 applied row: probe returns "t" → true (a migration
//     has touched the schema; the seed's --clean would collide with sql_saga).
//
// Any unexpected output is treated conservatively as "not migrated" (false), the
// same fresh-install-favouring default dbHasUserData uses; the downstream
// migrate-forward path is the safety net if that guess is wrong.
func interpretAppliedMigrationsProbe(out string, probeErr error) bool {
	if probeErr != nil {
		return false
	}
	return strings.TrimSpace(out) == "t"
}

// errSeedUnavailable / errSeedFallback are the two NON-FATAL outcomes of the
// Seed step (runSeedRestore). Both degrade to full migrations, but NEITHER may
// be reported as DONE: a swallowed seed failure that reads as success is the
// exact STATBUS-018 silent ~10x-slowdown class. errSeedUnavailable is
// calm-and-expected (no seed image published for this commit — fresh repos /
// private forks); errSeedFallback is LOUD (a seed image exists but pg_restore
// errored, which is unexpected once the gate only lets seed run on a fresh
// schema). stepRunOutcome maps them to the install loop's reported status.
var (
	errSeedUnavailable = errors.New("no seed image available; running full migrations")
	errSeedFallback    = errors.New("seed restore failed; falling back to full migrations")
)

// stepRunOutcome maps a step's run() error to the line the install loop prints
// and whether the failure halts the install. It is the pure guard for the
// STATBUS-018 invariant: a non-nil restore error is NEVER reported as DONE.
// Only the two Seed sentinels are non-fatal; every other error is fatal (the
// loop prints "FAILED: <err>" and stops — also never DONE). Kept pure + here so
// the invariant is unit-pinned rather than buried in the loop.
func stepRunOutcome(runErr error) (line string, fatal bool) {
	switch {
	case runErr == nil:
		return "DONE", false
	case errors.Is(runErr, errSeedFallback):
		return "FAILED — falling back to full migrations", false
	case errors.Is(runErr, errSeedUnavailable):
		return "no seed image — full migrations will run", false
	default:
		return "", true // fatal: caller prints "FAILED: <err>" and halts
	}
}

// runSeedRestore fetches the seed from the published statbus-seed image
// and restores it into the database. This makes `migrate up` fast — only
// migrations newer than the seed need to run. Non-fatal throughout: a missing
// image (errSeedUnavailable) or a failed restore (errSeedFallback) both degrade
// to runMigrations, which replays all migrations from scratch. Per STATBUS-018
// the two are distinguished — the missing-image path is calm/expected, the
// failed-restore path is loud — and neither is ever reported as DONE.
func runSeedRestore(dir string) error {
	sb := filepath.Join(dir, "sb")

	// Fetch seed from the published image.
	fmt.Println("  Fetching seed from the seed image (statbus-seed:<commit_short>)...")
	if err := runCmdDir(dir, sb, "db", "seed", "fetch"); err != nil {
		// LEG 1 — no seed image for this commit (fresh repos / private forks).
		// Calm + expected: full migrations run next and do the real work.
		fmt.Println("  No seed image available — full migrations will run.")
		return errSeedUnavailable
	}

	// Restore into the default database (configured in .env).
	fmt.Println("  Restoring seed...")
	if err := runCmdDir(dir, sb, "db", "seed", "restore"); err != nil {
		// LEG 2 — seed image present but pg_restore ERRORED. The fast path is
		// lost; full migrations (~10x slower) run instead. This is UNEXPECTED
		// on a genuinely fresh schema (checkSeedRestored now gates seed OFF
		// once any migration has touched the DB — STATBUS-018), so announce it
		// loudly. Non-fatal, but NEVER reported as DONE.
		fmt.Println("  ============================================================")
		fmt.Println("  ⚠ SEED FAST-PATH LOST — seed image present but pg_restore failed.")
		fmt.Printf("     Cause: %v\n", err)
		fmt.Println("     Falling back to FULL MIGRATIONS (~10x slower).")
		fmt.Println("     Unexpected on a fresh database — worth investigating.")
		fmt.Println("  ============================================================")
		return errSeedFallback
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

	// #4 unit-reconcile re-arm (plan de-risk #2): capture whether the on-disk
	// unit is about to CHANGE while the unit is already running. A rewritten
	// unit file is INERT — systemd keeps running with the old WatchdogSec/
	// TimeoutStartSec until daemon-reload + a RESTART. `enable --now` below
	// does NOT restart an already-active unit, so without an explicit restart
	// a drifted-but-running box (rune's 90/infinity) would keep its stale
	// timers even after we rewrite the file to 120/120. Detect drift-on-active
	// here so we can restart only when needed (never churn a healthy,
	// already-matching unit).
	unitWasDrifted := !unitFileMatchesRepo(dir)
	unitWasActive := exec.Command("systemctl", "--user", "is-active", instance).Run() == nil

	fmt.Printf("  Copying %s → %s\n", filepath.Base(serviceFile), destFile)
	if err := copyFile(serviceFile, destFile); err != nil {
		return fmt.Errorf("copy service file: %w", err)
	}

	fmt.Println("  Running systemctl --user daemon-reload")
	if err := runCmd("systemctl", "--user", "daemon-reload"); err != nil {
		return fmt.Errorf("systemctl --user daemon-reload: %w", err)
	}

	// Re-arm the timers: if we just rewrote a DRIFTED unit that was actively
	// running, restart it so the new WatchdogSec/TimeoutStartSec take effect
	// (daemon-reload alone only reloads systemd's view, not the running unit's
	// armed deadlines). Skip when postUpgradeFixup — that path is the
	// active upgrade's own main PID and relies on the exit-42 → systemd
	// auto-restart handoff (Item H below); restarting it here would kill the
	// in-flight upgrade. The enable --now path below covers the not-running
	// and fresh-install cases.
	if unitWasDrifted && unitWasActive && !postUpgradeFixup {
		fmt.Printf("  Unit %s drifted from the repo template and was running — restarting to arm the reconciled timers\n", instance)
		if err := runCmd("systemctl", "--user", "restart", instance); err != nil {
			return fmt.Errorf("restart %s after unit reconcile: %w", instance, err)
		}
	}

	// Enable linger so the user service runs even when not logged in.
	// This requires loginctl which is available on systemd systems.
	fmt.Println("  Enabling linger for user services")
	runCmd("loginctl", "enable-linger", os.Getenv("USER"))

	// Recovery: if the unit is in `failed` state from a prior crashed
	// upgrade (e.g. the rune wedge — systemd hit StartLimitBurst after
	// repeated SIGKILL → restart cycles trying to satisfy
	// TimeoutStartSec for an at-scale migrate-up), `enable --now`
	// won't restart it. Probe ActiveState/Result and run reset-failed
	// first if needed. Idempotent: on a healthy unit the probe finds
	// active/inactive and reset is skipped.
	if probeOut, probeErr := exec.Command("systemctl", "--user", "show",
		"--property=ActiveState", "--property=Result", instance).Output(); probeErr == nil {
		probe := string(probeOut)
		if strings.Contains(probe, "ActiveState=failed") ||
			strings.Contains(probe, "Result=start-limit-hit") {
			fmt.Printf("  Unit %s is in failed state — running reset-failed\n", instance)
			if err := runCmd("systemctl", "--user", "reset-failed", instance); err != nil {
				return fmt.Errorf("reset-failed for %s: %w", instance, err)
			}
		}
	}

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
	if postUpgradeFixup {
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

	var rowJSON string
	err := conn.QueryRow(ctx,
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
		 WHERE upgrade.state != 'completed'
		 RETURNING to_jsonb(upgrade.*)`,
		sha,
		commitDate,
		fmt.Sprintf("Installed via ./sb install (%s)", version),
		version,
		upgrade.ClassifyReleaseShape(version).ReleaseStatus(),
		logRelPath).Scan(&rowJSON)
	if errors.Is(err, pgx.ErrNoRows) {
		// ON CONFLICT no-op: a completed row for this SHA already exists
		// (idempotent re-install). The upsert's WHERE (state != 'completed') was
		// false, so RETURNING yielded no row — not an error, nothing changed.
		fmt.Printf("  Installed version %s already recorded in upgrade table (no change)\n", version)
		return nil
	}
	if err != nil {
		// A9: POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS
		fmt.Fprintf(os.Stderr,
			"INVARIANT POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS violated: could not record completed upgrade row for sha=%s: %v (install.go:%d, pid=%d)\n",
			sha, err, thisLine(), os.Getpid())
		markTerminal(installDir, "POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS",
			fmt.Sprintf("sha=%s; INSERT err=%v", sha, err))
		return fmt.Errorf("POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS: %w", err)
	}
	// Symmetric with the recovery / executeUpgrade completion paths: emit the
	// full row snapshot under a greppable label (the recovery path logs
	// logUpgradeRow[completed-normal]; this is its install-side sibling). Same
	// "upgrade row [<label>] <json>" format as upgrade.logUpgradeRow so the
	// journald grep contract (grep 'upgrade row \[<label>\]') holds.
	fmt.Printf("upgrade row [%s] %s\n", upgrade.LabelCompletedInstall, rowJSON)
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
		"STATBUS_EVENT=install_completed", // STATBUS-137: name the event (was firing blank)
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

// runCmdDirTimeout is runCmdDir with a hard deadline. For steps that are
// DB-size-scaled and must not hang an unattended recovery forever — e.g.
// the crash-recovery boot-migrate (STATBUS-012), bounded by the shared
// upgrade.MigrateUpTimeout so it cannot drift from the service-path sites.
func runCmdDirTimeout(dir string, timeout time.Duration, name string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("%s %s timed out after %s", name, strings.Join(args, " "), timeout)
	}
	return err
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
//
// projDir is passed in so the StateNothingScheduled branch can probe
// for DB-vs-disk migration drift (best-effort; failure stays quiet so
// a DB blip never breaks the install output).
func logInstallState(projDir string, state install.State, detail *install.Detail) {
	fmt.Printf("Detected install state: %s (current=%s, target=%s)\n",
		state, detail.CurrentVersion, detail.TargetVersion)
	switch state {
	case install.StateFresh:
		fmt.Printf("  Fresh install; target version = %s (binary).\n", detail.TargetVersion)
	case install.StateLiveUpgrade:
		if detail.Flag != nil {
			fmt.Printf("  Upgrade in progress (%s). Install will refuse. See which process holds it: lsof tmp/upgrade-in-progress.json\n",
				detail.Flag.Label())
		}
	case install.StateCrashedUpgrade:
		if detail.Flag != nil {
			fmt.Printf("  Prior upgrade crashed (%s). Its flock is free (the holder is gone); recovering.\n",
				detail.Flag.Label())
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
	case install.StateRestoreReattemptable:
		fmt.Printf("  A prior rollback's database restore did not finish (row id=%d, snapshot retained). Re-attempting the restore.\n",
			detail.ReattemptRowID)
	case install.StateNothingScheduled:
		fmt.Println("  Existing install, no upgrade scheduled; running idempotent step-table to refresh.")
		// Surface DB-vs-disk migration drift so the operator knows
		// whether the step-table will actually apply migrations.
		// Pre-fix the diagnostic said "no upgrade scheduled" while
		// the step-table silently applied N pending migrations —
		// functionally correct but misleading. Best-effort probe:
		// both helpers return "" on error, so a DB blip just
		// elides this line rather than failing the install.
		live := install.LiveMaxMigrationVersion(projDir)
		onDisk := install.OnDiskMaxMigrationVersion(projDir)
		switch {
		case live == "" || onDisk == "":
			// Couldn't probe one side; stay quiet rather than
			// surface a confusing partial diagnostic.
		case live == onDisk:
			fmt.Printf("  DB migration_version %s matches on-disk max — step-table is a no-op for migrations.\n", live)
		case live < onDisk:
			fmt.Printf("  DB migration_version %s < on-disk max %s — step-table will apply pending migrations.\n", live, onDisk)
		default: // live > onDisk
			fmt.Printf("  DB migration_version %s > on-disk max %s — DB is ahead of this checkout; step-table may down-then-up to converge.\n", live, onDisk)
		}
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
		ViolationShape:   "conn==nil, or CALL upgrade_retention_apply / upgrade_supersede_older / upgrade_supersede_completed_prereleases returns err, or --post-upgrade-fixup hand-passed with no STATBUS_POST_UPGRADE_FIXUP env signature and no on-disk flag (A17 — genuine misuse only; the legitimate post-completion fixup carries the env signature and is expected, not audited). Each sub-site prints a named log line with sub-index (A12/A13/A14/A16/A17).",
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
