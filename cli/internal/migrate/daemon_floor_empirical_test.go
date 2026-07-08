package migrate

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// daemonFloorQueries is the ENUMERATION ARTIFACT (STATBUS-145 slice 1 step 3):
// the shapes the daemon's own boot + recovery + pre-delta main-loop queries take,
// each referencing the daemon columns/types/procs a floor-insufficiency would
// break. The empirical floor test PREPAREs each against a schema migrated to
// exactly DaemonSchemaFloor — Prepare resolves every column, enum type, and
// function WITHOUT executing (no side effects, no valid params needed), so a
// missing one fails the prepare (42703 undefined_column, 42704 undefined_object,
// 42883 undefined_function). A clean prepare of all of them ⇒ the floor is
// sufficient for the daemon to operate.
//
// The architect reviews this list against service.go's ~23 query sites. Sources
// cited per entry (service.go line refs at authoring time).
var daemonFloorQueries = []struct {
	name string
	sql  string
}{
	{"observed-state: db.migration max", // service.go:2463
		`SELECT COALESCE(MAX(version), 0) FROM db.migration`},
	{"upgrade ledger + recovery-park columns + release_status enum", // service.go park columns + :3677
		`SELECT id, state, recovery_attempts, recovery_parked_at, recovery_parked_reason,
		        commit_tags, release_status
		   FROM public.upgrade WHERE false`},
	{"upgrade claim shape (scheduled → in_progress)", // service.go executeScheduled claim
		`SELECT id, state, started_at FROM public.upgrade WHERE state = 'scheduled' ORDER BY id LIMIT 1`},
	{"upgrade release_status enum write cast", // service.go:3677
		`UPDATE public.upgrade SET commit_tags = $1, release_status = $2::public.release_status_type WHERE id = $3`},
	{"release_builds_status_type enum resolves", // service.go release-build status
		`SELECT $1::public.release_builds_status_type`},
	{"system_info config sync", // service.go:2987/3005/3617
		`INSERT INTO public.system_info (key, value, updated_at) VALUES ($1, $2, now())
		   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at`},
	{"supersede-older proc exists", // service.go:3019
		`CALL public.upgrade_supersede_older($1, 0)`},
	{"supersede-completed-prereleases proc exists", // service.go:3036
		`CALL public.upgrade_supersede_completed_prereleases($1, 0)`},
	{"retention plan set-returning fn", // exec.go:980
		`SELECT id, log_relative_file_path FROM public.upgrade_retention_plan($1, $2)`},
	{"retention apply proc exists", // exec.go:1020
		`CALL public.upgrade_retention_apply($1, $2, 0)`},
}

// (The three CALL entries prepare clean via pgx's protocol-level Parse — verified
// by the tester's for-the-record run — so no ::regprocedure fallback is needed.)
//
// SELF-PROVISIONING ATTEMPTED + REFUTED (STATBUS-096 slice 3, engineer run
// 2026-07-08): comment #4's in-process recipe (CREATE DATABASE → migrate.Up
// migrateTo=DaemonSchemaFloor → Prepare → drop) does NOT work — a from-scratch
// migrate.Up on an empty DB fails at migration 20240102100000
// (create_admin_credentials_table): "schema \"auth\" does not exist". The STATBUS
// migrations are not cleanly from-scratch-runnable on a bare database; the working
// provisioning path (`./dev.sh create-db`, seed clone) supplies a base baseline
// migrate.Up alone does not. So the split provisioning stays: the tester/CI
// provisions a floor DB and points STATBUS_FLOOR_TEST_DSN at it. (Awaiting the
// architect's re-ruling on comment #4 given this empirical refutation.)

// TestDaemonFloorSchemaSufficient is the EMPIRICAL floor oracle: against a DB
// migrated to EXACTLY DaemonSchemaFloor, every daemon query above must PREPARE
// clean. Backstop for the bump guard's one blind spot (a daemon relation
// referenced only unqualified in a migration).
//
// PROVISIONING (tester/CI supplies the floor DB — `./dev.sh create-db` on a
// scratch DB then `./sb migrate up --to 20260703210000`, then point the DSN):
//
//	STATBUS_FLOOR_TEST_DSN='postgres://…/statbus_floor_test' go test ./cli/internal/migrate/ -run TestDaemonFloorSchemaSufficient
//
// Skips when unset/unreachable → `go test` stays green without a cluster. DO NOT
// point it at a HEAD DB — HEAD ⊇ floor would pass vacuously; the DSN must be a DB
// migrated to exactly the floor.
func TestDaemonFloorSchemaSufficient(t *testing.T) {
	dsn := os.Getenv("STATBUS_FLOOR_TEST_DSN")
	if dsn == "" {
		// The silent skip is safe ONLY while the floor is the newest migration (the
		// oracle is vacuous then — HEAD == floor). The moment the floor LAGS the
		// tree, this is the guard that finally matters, and a silent skip would hide
		// a floor insufficiency. So FAIL with the provisioning recipe the instant the
		// floor first lags — the recipe gets built exactly when first needed.
		migs, err := listMigrationFiles(repoRoot(t))
		if err != nil || len(migs) == 0 {
			t.Fatalf("list migrations: %v (n=%d)", err, len(migs))
		}
		treeMax := migs[len(migs)-1].Version // listMigrationFiles sorts ascending
		if DaemonSchemaFloor < treeMax {
			t.Fatalf("DaemonSchemaFloor (%d) now LAGS the newest migration (%d) — the empirical floor oracle MUST run, but STATBUS_FLOOR_TEST_DSN is unset.\n"+
				"Provision a floor DB and set it:\n"+
				"  ./dev.sh create-db                 # scratch DB WITH the create-db baseline (roles + auth schema)\n"+
				"  ./sb migrate up --to %d            # bring it to exactly the floor (NOT HEAD — HEAD would pass vacuously)\n"+
				"  STATBUS_FLOOR_TEST_DSN='postgres://…/<db>' go test ./cli/internal/migrate/ -run TestDaemonFloorSchemaSufficient",
				DaemonSchemaFloor, treeMax, DaemonSchemaFloor)
		}
		t.Skip("STATBUS_FLOOR_TEST_DSN unset and the floor is still the newest migration (oracle vacuous) — skipping")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Skipf("STATBUS_FLOOR_TEST_DSN unreachable (%v) — skipping empirical floor oracle", err)
	}
	defer conn.Close(context.Background())

	for _, q := range daemonFloorQueries {
		t.Run(q.name, func(t *testing.T) {
			if _, err := conn.Prepare(ctx, "", q.sql); err != nil {
				t.Errorf("daemon query %q failed to prepare at the floor schema — the floor is insufficient for the daemon to operate: %v", q.name, err)
			}
		})
	}
}
