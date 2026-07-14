package migrate

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// SeedMutationLockKey is the human-readable identifier hashed into the
// PG advisory lock ID that serialises mutations of the canonical seed
// (statbus_seed) and queries against artifacts downstream of it
// (statbus_test_template, transient gen-docs DBs).
//
// Why a string + hashtext: a stable name is easier to keep in sync
// across bash, Go, and SQL than a magic bigint constant. Postgres
// converts via `hashtext('statbus_seed_mutate')` at every acquisition;
// the hash is stable for the lifetime of the cluster.
//
// Holders:
//   - EXCLUSIVE: `./sb db with-seed-lock --exclusive` (dev.sh recreate-seed
//     wraps its body with this). Mutates statbus_seed: DROP + recreate +
//     migrate.Up + post_restore.sql. Held on a connection to the
//     `postgres` system database so the lock survives DROP DATABASE
//     statbus_seed (a connection directly to statbus_seed would be
//     forcibly closed mid-DROP).
//   - SHARED: migrate.AssertDBAtHead (when test-fast / gen-docs assert
//     against the seed). Multiple shared holders can coexist; blocks
//     iff an exclusive holder is mid-mutation.
//
// Defensive: the lock is for coordination, NOT correctness. If the
// postgres system DB is unreachable, the gate's downstream query
// would fail anyway — we surface the underlying error rather than
// swallowing it as a lock-specific message.
const SeedMutationLockKey = "statbus_seed_mutate"

// PostgresSystemConnStr returns a pgx connection string targeting the
// `postgres` system database (NOT POSTGRES_APP_DB / statbus_seed /
// statbus_test_template). Used by seed-mutation lock holders — the
// system DB connection survives DROP DATABASE statbus_seed
// mid-recreate, which is the entire point of holding the lock there.
//
// Connection params come from .env via the same shape advisoryLockConnStr
// uses for the migrate-up lock — CADDY_DB_BIND_ADDRESS + CADDY_DB_PORT
// (server-internal bind), POSTGRES_ADMIN_USER/PASSWORD, sslmode=disable.
func PostgresSystemConnStr(projDir string) (string, error) {
	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return "", fmt.Errorf("load .env: %w", err)
	}
	requireKey := func(key string) (string, error) {
		if v, ok := f.Get(key); ok && v != "" {
			return v, nil
		}
		return "", fmt.Errorf("%s not found in .env — regenerate with: ./sb config generate", key)
	}
	getOr := func(key, fallback string) string {
		if v := os.Getenv(key); v != "" {
			return v
		}
		if v, ok := f.Get(key); ok {
			return v
		}
		return fallback
	}
	dbHost, err := requireKey("CADDY_DB_BIND_ADDRESS")
	if err != nil {
		return "", err
	}
	dbPort, err := requireKey("CADDY_DB_PORT")
	if err != nil {
		return "", err
	}
	return fmt.Sprintf(
		"host=%s port=%s dbname=postgres user=%s password=%s sslmode=disable",
		dbHost,
		dbPort,
		getOr("POSTGRES_ADMIN_USER", "postgres"),
		getOr("POSTGRES_ADMIN_PASSWORD", ""),
	), nil
}

// AcquireSeedLock opens a connection to the postgres system DB and
// acquires either an exclusive or shared advisory lock keyed by
// hashtext(SeedMutationLockKey). The caller MUST call Close(ctx) on
// the returned conn to release the lock — PG advisory locks are
// session-scoped, so connection close releases automatically (no
// stale-lock cleanup needed).
//
// lockTimeout is applied via `SET lock_timeout` before the acquire
// attempt; pass 0 to block indefinitely (exclusive holders may want
// this — recreate-seed should wait for any in-flight assertion to
// finish, not error out on timeout). Pass 60s or similar for shared
// acquirers (assert-db-at-head) so an operator-pathological exclusive
// writer doesn't deadlock the entire test cycle.
//
// caller is a human-readable label folded into error messages for
// debuggability (e.g. "./sb db with-seed-lock", "assert-db-at-head:seed").
func AcquireSeedLock(ctx context.Context, projDir string, exclusive bool, lockTimeout time.Duration, caller string) (*pgx.Conn, error) {
	connStr, err := PostgresSystemConnStr(projDir)
	if err != nil {
		return nil, fmt.Errorf("%s: build postgres system conn string: %w", caller, err)
	}
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		return nil, fmt.Errorf("%s: postgres system DB unreachable: %w", caller, err)
	}

	// Tag the session so a leaked lock holder is identifiable via
	// pg_stat_activity. Mirrors acquireAdvisoryLock's pattern for the
	// migrate_up lock — keeps the diagnostic surface uniform.
	if _, tagErr := conn.Exec(ctx, fmt.Sprintf("SET application_name = 'statbus-seed-lock-%d'", os.Getpid())); tagErr != nil {
		_ = conn.Close(ctx) // best-effort; already erroring out
		return nil, fmt.Errorf("%s: tag seed-lock connection: %w", caller, tagErr)
	}

	// Optional lock_timeout. Postgres `SET lock_timeout` applies to
	// blocking acquisitions of advisory locks (alongside regular
	// table/row locks).
	if lockTimeout > 0 {
		if _, err := conn.Exec(ctx, fmt.Sprintf("SET lock_timeout = '%dms'", lockTimeout.Milliseconds())); err != nil {
			_ = conn.Close(ctx) // best-effort; already erroring out
			return nil, fmt.Errorf("%s: set lock_timeout: %w", caller, err)
		}
	}

	// Acquire. SQL string uses the constant to keep the key in lock-step
	// across Go + (future) bash callsites — change one, search the other.
	var lockSQL string
	if exclusive {
		lockSQL = fmt.Sprintf("SELECT pg_advisory_lock(hashtext('%s'))", SeedMutationLockKey)
	} else {
		lockSQL = fmt.Sprintf("SELECT pg_advisory_lock_shared(hashtext('%s'))", SeedMutationLockKey)
	}
	if _, err := conn.Exec(ctx, lockSQL); err != nil {
		_ = conn.Close(ctx) // best-effort; already erroring out
		mode := "shared"
		if exclusive {
			mode = "exclusive"
		}
		return nil, fmt.Errorf("%s: acquire %s seed lock: %w", caller, mode, err)
	}
	return conn, nil
}
