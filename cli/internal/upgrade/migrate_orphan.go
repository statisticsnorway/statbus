package upgrade

import (
	"context"
	"fmt"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// migrateOrphanTerminateSQL terminates the orphaned in-container psql backend
// left by a killed migrate (task #14). migrate runs psql IN the db container
// via `docker compose exec` (migrate.go), and docker-exec does NOT forward
// SIGKILL — so the host-side process-group SIGKILL of `./sb migrate` at the
// runCommandToLog timeout reaps the host docker-exec client but leaves the
// in-container backend ALIVE: its transaction open, locks held, and (the real
// hazard) a statement that COMPLETES will COMMIT-after-host-rollback.
//
// Matched by application_name PREFIX (migrate tags the subprocess
// 'statbus-migrate-sql-<pid>' via PGAPPNAME): the terminate runs in the SERVICE
// process, which cannot know the migrate child's pid, and the upgrade-mutex
// serializes so at most one such backend exists. Excludes pg_backend_pid() so
// the service's own connection is never terminated. Scoped to current_database()
// for safety. Returns the terminated pids for logging.
var migrateOrphanTerminateSQL = fmt.Sprintf(`
	SELECT pid, pg_terminate_backend(pid)
	  FROM pg_stat_activity
	 WHERE datname = current_database()
	   AND pid <> pg_backend_pid()
	   AND application_name LIKE '%s%%'`, migrate.SubprocessAppNamePrefix)

// terminateMigrateOrphan deterministically aborts the orphaned in-container psql
// backend after a migrate TIMEOUT, BEFORE the rollback — so the orphan's open
// transaction is rolled back (no commit-after-rollback) and its locks released,
// rather than relying on restoreDatabase's container-stop to eventually kill it
// (which is timing-dependent and skippable). Best-effort: a failure here is
// logged, not fatal — restoreDatabase's container stop remains the backstop.
//
// Call ONLY when the migrate step returned an ErrCommandTimeout — a clean
// (non-timeout) migrate failure means psql exited and there is no orphan.
//
// Orphan-class split (the two are COMPLEMENTARY — neither is the sole defense):
//   1. migrate TIMED OUT while the owning ./sb migrate process is alive → the
//      runCommandToLog ctx-deadline fires Cancel=SIGKILL on the process group,
//      reaping the host docker-exec client but NOT the in-container psql backend
//      (docker-exec doesn't forward the signal). THIS function handles that
//      class, in-line, immediately, on the live service conn.
//   2. the owning Go process itself died mid-migrate (service OOM / host SIGKILL
//      / reboot) → no runCommandToLog timeout fires, so this function never runs;
//      the migrate AND its psql are both orphaned. That class is cleanOrphanSessions'
//      job (install.go) — it exists precisely for "owning process died" and runs
//      at install / crash-recovery, matching the same statbus-migrate-sql% prefix.
// Together: terminate-on-timeout (here) + cleanOrphanSessions-at-recovery cover
// both ways a migrate psql backend can be orphaned.
func (d *Service) terminateMigrateOrphan(ctx context.Context, progress *ProgressLog) {
	if d.queryConn == nil {
		progress.Write("migrate-orphan: no DB connection to terminate the orphaned psql backend (rollback's container-stop is the backstop)")
		return
	}
	qctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	rows, err := d.queryConn.Query(qctx, migrateOrphanTerminateSQL)
	if err != nil {
		progress.Write("migrate-orphan: pg_terminate_backend query failed: %v (rollback's container-stop is the backstop)", err)
		return
	}
	defer rows.Close()
	var terminated []int32
	for rows.Next() {
		var pid int32
		var ok bool
		if scanErr := rows.Scan(&pid, &ok); scanErr == nil {
			terminated = append(terminated, pid)
		}
	}
	if len(terminated) > 0 {
		progress.Write("migrate-orphan: terminated %d orphaned in-container psql backend(s) %v after migrate timeout (aborts open txn before rollback)", len(terminated), terminated)
	} else {
		progress.Write("migrate-orphan: no orphaned migrate psql backend found to terminate (already gone, or none left a session)")
	}
}
