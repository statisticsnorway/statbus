//go:build livedb

package upgrade

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

const claimTokenMigration int64 = 20260923202403

// TestInlineScheduledClaimPre382UndefinedColumnClosedByDaemonFloor is the
// STATBUS-441 AC#1 fixture. It full-replays a throwaway database only through
// the largest migration before claim_token, proves the real production claim
// fails with SQLSTATE 42703, raises that same database only to the declared
// daemon floor, then drives the DB-side remainder of the production pipeline:
// real claim, real full-delta migrate entry point, and real terminal completion.
func TestInlineScheduledClaimPre382UndefinedColumnClosedByDaemonFloor(t *testing.T) {
	if os.Getenv("STATBUS_LIVEDB_TEST_TIER") != "1" {
		t.Skip("requires ./dev.sh test-livedb")
	}
	projDir := findProjDir(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	adminDSN, appDSN, envValues := liveDatabaseDSNs(t, projDir)
	adminConn, err := pgx.Connect(ctx, adminDSN)
	if err != nil {
		t.Fatalf("connect to maintenance database: %v", err)
	}
	defer adminConn.Close(context.Background())

	dbName := fmt.Sprintf("statbus_test_template_441_%d", time.Now().UnixNano())
	quotedDB := pgx.Identifier{dbName}.Sanitize()
	if _, err := adminConn.Exec(ctx, "CREATE DATABASE "+quotedDB); err != nil {
		t.Fatalf("create throwaway database %s: %v", dbName, err)
	}
	t.Cleanup(func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cleanupCancel()
		cleanupConn, connectErr := pgx.Connect(cleanupCtx, adminDSN)
		if connectErr != nil {
			t.Errorf("connect for throwaway database cleanup: %v", connectErr)
			return
		}
		defer cleanupConn.Close(context.Background())
		_, _ = cleanupConn.Exec(cleanupCtx, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()", dbName)
		if _, dropErr := cleanupConn.Exec(cleanupCtx, "DROP DATABASE IF EXISTS "+quotedDB); dropErr != nil {
			t.Errorf("drop throwaway database %s: %v", dbName, dropErr)
		}
	})

	fixtureDSN := strings.Replace(appDSN, "dbname="+envValues["POSTGRES_APP_DB"], "dbname="+dbName, 1)
	fixtureConn, err := pgx.Connect(ctx, fixtureDSN)
	if err != nil {
		t.Fatalf("connect to throwaway database: %v", err)
	}
	// The local cluster owns roles globally. sql_saga is installed by the
	// database image rather than by a migration, while the migration corpus
	// creates the other extensions itself.
	if _, err := fixtureConn.Exec(ctx, "CREATE EXTENSION btree_gist"); err != nil {
		t.Fatalf("create btree_gist baseline extension: %v", err)
	}
	if _, err := fixtureConn.Exec(ctx, "CREATE EXTENSION sql_saga"); err != nil {
		t.Fatalf("create sql_saga baseline extension: %v", err)
	}
	if _, err := fixtureConn.Exec(ctx, "CREATE SCHEMA IF NOT EXISTS auth"); err != nil {
		t.Fatalf("create auth baseline schema: %v", err)
	}
	if err := fixtureConn.Close(ctx); err != nil {
		t.Fatalf("close baseline connection: %v", err)
	}

	preClaimVersion := largestMigrationBelow(t, projDir, claimTokenMigration)
	t.Setenv("DOCKER_PSQL", "0")
	t.Setenv("PGDATABASE", dbName)
	if err := migrate.Up(projDir, preClaimVersion, true, true); err != nil {
		t.Fatalf("full replay throwaway database to pre-claim_token version %d: %v", preClaimVersion, err)
	}

	fixtureProjDir := writeFixtureProjectEnv(t, projDir, envValues, dbName)
	svc := NewService(fixtureProjDir, false, "v2026.10.0-rc.11", "bcb1d568efa201eb76bfe2f9d124f8a29c7dacf5")
	if err := svc.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect throwaway database: %v", err)
	}
	defer svc.Close()

	const commitSHA = "4410000000000000000000000000000000000001"
	var id int
	if err := svc.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade
		       (commit_sha, committed_at, commit_tags, release_status, summary, state, scheduled_at)
		VALUES ($1, now(), '{}', 'commit', 'STATBUS-441 pre-382 claim fixture', 'scheduled', now())
		RETURNING id`, commitSHA).Scan(&id); err != nil {
		t.Fatalf("insert scheduled upgrade row: %v", err)
	}

	var preFloorSawTreeConvergence bool
	svc.claimSchemaProbeForTest = func(hasTreeConvergenceColumn bool) {
		preFloorSawTreeConvergence = hasTreeConvergenceColumn
	}
	_, err = svc.claimScheduledUpgrade(ctx, id)
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "42703" {
		t.Fatalf("pre-382 production claim error = %v, want SQLSTATE 42703 undefined_column", err)
	}
	if !preFloorSawTreeConvergence {
		t.Fatal("pre-floor production claim did not select the tree_convergence_required branch")
	}

	if err := migrate.Up(projDir, migrate.DaemonSchemaFloor, true, true); err != nil {
		t.Fatalf("raise throwaway database to daemon floor %d: %v", migrate.DaemonSchemaFloor, err)
	}
	var postFloorSawTreeConvergence bool
	svc.claimSchemaProbeForTest = func(hasTreeConvergenceColumn bool) {
		postFloorSawTreeConvergence = hasTreeConvergenceColumn
	}
	claim, err := svc.claimScheduledUpgrade(ctx, id)
	if err != nil {
		t.Fatalf("production claim after daemon-floor bump: %v", err)
	}
	if !postFloorSawTreeConvergence {
		t.Fatal("post-floor production claim did not select the tree_convergence_required branch")
	}
	floorVersions := appliedMigrationVersionsBetween(t, ctx, svc.queryConn, preClaimVersion, migrate.DaemonSchemaFloor)
	wantFloorVersions := []int64{claimTokenMigration, migrate.DaemonSchemaFloor}
	if fmt.Sprint(floorVersions) != fmt.Sprint(wantFloorVersions) {
		t.Fatalf("daemon-floor migrations = %v, want exactly %v", floorVersions, wantFloorVersions)
	}

	var state string
	var storedToken string
	if err := svc.queryConn.QueryRow(ctx, "SELECT state::text, claim_token::text FROM public.upgrade WHERE id = $1", id).Scan(&state, &storedToken); err != nil {
		t.Fatalf("read claimed row: %v", err)
	}
	if state != "in_progress" || storedToken != claim.Snapshot.ClaimToken {
		t.Fatalf("claimed row state/token = %s/%s, want in_progress/%s", state, storedToken, claim.Snapshot.ClaimToken)
	}

	diskVersions, err := migrate.DiskVersions(projDir)
	if err != nil {
		t.Fatalf("list on-disk migrations: %v", err)
	}
	wantRemaining := 0
	for _, version := range diskVersions {
		if version > migrate.DaemonSchemaFloor {
			wantRemaining++
		}
	}
	pendingMigrations, err := runMigrateUpToLog(fixtureProjDir, MigrateUpTimeout, io.Discard, nil, "migrate", "up", "--verbose")
	if err != nil {
		t.Fatalf("production full-delta migration entry point: %v", err)
	}
	if pendingMigrations != wantRemaining {
		t.Fatalf("full-delta pending migration count = %d, want %d", pendingMigrations, wantRemaining)
	}

	if _, err := svc.terminalUpdate(completedUpgradeSQL, id, "statbus-441-livedb.log"); err != nil {
		t.Fatalf("production terminal completion path: %v", err)
	}
	var completedAt *time.Time
	if err := svc.queryConn.QueryRow(ctx, "SELECT state::text, completed_at FROM public.upgrade WHERE id = $1", id).Scan(&state, &completedAt); err != nil {
		t.Fatalf("read completed row: %v", err)
	}
	if state != "completed" || completedAt == nil {
		t.Fatalf("completed row state/completed_at = %s/%v, want completed/non-NULL", state, completedAt)
	}
}

func appliedMigrationVersionsBetween(t *testing.T, ctx context.Context, conn *pgx.Conn, after, through int64) []int64 {
	t.Helper()
	rows, err := conn.Query(ctx, "SELECT version FROM db.migration WHERE version > $1 AND version <= $2 ORDER BY version", after, through)
	if err != nil {
		t.Fatalf("query daemon-floor migration versions: %v", err)
	}
	defer rows.Close()
	var versions []int64
	for rows.Next() {
		var version int64
		if err := rows.Scan(&version); err != nil {
			t.Fatalf("scan daemon-floor migration version: %v", err)
		}
		versions = append(versions, version)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("read daemon-floor migration versions: %v", err)
	}
	return versions
}

func largestMigrationBelow(t *testing.T, projDir string, ceiling int64) int64 {
	t.Helper()
	entries, err := os.ReadDir(filepath.Join(projDir, "migrations"))
	if err != nil {
		t.Fatal(err)
	}
	var versions []int64
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".up.sql") && !strings.HasSuffix(name, ".up.psql") {
			continue
		}
		version, parseErr := strconv.ParseInt(strings.SplitN(name, "_", 2)[0], 10, 64)
		if parseErr == nil && version < ceiling {
			versions = append(versions, version)
		}
	}
	if len(versions) == 0 {
		t.Fatalf("no migration below %d", ceiling)
	}
	sort.Slice(versions, func(i, j int) bool { return versions[i] < versions[j] })
	return versions[len(versions)-1]
}

func liveDatabaseDSNs(t *testing.T, projDir string) (adminDSN, appDSN string, values map[string]string) {
	t.Helper()
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		t.Fatal(err)
	}
	get := func(key string) string { value, _ := f.Get(key); return value }
	values = map[string]string{
		"CADDY_DB_BIND_ADDRESS":   get("CADDY_DB_BIND_ADDRESS"),
		"CADDY_DB_PORT":           get("CADDY_DB_PORT"),
		"POSTGRES_ADMIN_DB":       get("POSTGRES_ADMIN_DB"),
		"POSTGRES_ADMIN_USER":     get("POSTGRES_ADMIN_USER"),
		"POSTGRES_ADMIN_PASSWORD": get("POSTGRES_ADMIN_PASSWORD"),
		"POSTGRES_APP_DB":         get("POSTGRES_APP_DB"),
	}
	base := "host=" + values["CADDY_DB_BIND_ADDRESS"] + " port=" + values["CADDY_DB_PORT"] +
		" user=" + values["POSTGRES_ADMIN_USER"] + " password=" + values["POSTGRES_ADMIN_PASSWORD"] +
		" sslmode=disable application_name=statbus-441-livedb"
	return base + " dbname=" + values["POSTGRES_ADMIN_DB"], base + " dbname=" + values["POSTGRES_APP_DB"], values
}

func writeFixtureProjectEnv(t *testing.T, sourceProjDir string, values map[string]string, dbName string) string {
	t.Helper()
	dir := t.TempDir()
	contents := fmt.Sprintf("CADDY_DB_BIND_ADDRESS=%s\nCADDY_DB_PORT=%s\nPOSTGRES_ADMIN_DB=%s\nPOSTGRES_ADMIN_USER=%s\nPOSTGRES_ADMIN_PASSWORD=%s\nPOSTGRES_APP_DB=%s\n",
		values["CADDY_DB_BIND_ADDRESS"], values["CADDY_DB_PORT"], values["POSTGRES_ADMIN_DB"],
		values["POSTGRES_ADMIN_USER"], values["POSTGRES_ADMIN_PASSWORD"], dbName)
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"sb", "migrations", "dbseed"} {
		if err := os.Symlink(filepath.Join(sourceProjDir, name), filepath.Join(dir, name)); err != nil {
			t.Fatalf("link %s into fixture project: %v", name, err)
		}
	}
	return dir
}
