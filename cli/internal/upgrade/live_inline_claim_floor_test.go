//go:build livedb

package upgrade

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

const claimTokenMigration int64 = 20260923202403

// TestInlineScheduledClaimPre382UndefinedColumnClosedByDaemonFloor is the
// STATBUS-441 AC#1 fixture. It full-replays a throwaway database only through
// the largest migration before claim_token, proves the production claim SQL
// fails with SQLSTATE 42703, raises that same database only to the declared
// daemon floor, then proves the identical claim succeeds and owns the row.
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

	fixtureProjDir := writeFixtureProjectEnv(t, envValues, dbName)
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

	claimToken := "44100000-0000-4000-8000-000000000001"
	err = executePredecessorSchemaProductionClaim(ctx, svc.queryConn, id, claimToken)
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "42703" {
		t.Fatalf("pre-382 production claim error = %v, want SQLSTATE 42703 undefined_column", err)
	}

	if err := migrate.Up(projDir, migrate.DaemonSchemaFloor, true, true); err != nil {
		t.Fatalf("raise throwaway database to daemon floor %d: %v", migrate.DaemonSchemaFloor, err)
	}
	if err := executePredecessorSchemaProductionClaim(ctx, svc.queryConn, id, claimToken); err != nil {
		t.Fatalf("production claim after daemon-floor bump: %v", err)
	}

	var state string
	var storedToken string
	if err := svc.queryConn.QueryRow(ctx, "SELECT state::text, claim_token::text FROM public.upgrade WHERE id = $1", id).Scan(&state, &storedToken); err != nil {
		t.Fatalf("read claimed row: %v", err)
	}
	if state != "in_progress" || storedToken != claimToken {
		t.Fatalf("claimed row state/token = %s/%s, want in_progress/%s", state, storedToken, claimToken)
	}
}

// This is the exact no-tree-convergence-column claim statement shape from
// claimScheduledUpgrade in service.go. Keeping the production shape here makes
// the fixture fail on the actual claim_token resolution boundary, not a proxy.
func executePredecessorSchemaProductionClaim(ctx context.Context, conn *pgx.Conn, id int, claimToken string) error {
	var commitTags []string
	var recreate bool
	var returnedID int
	var commitVersion pgtype.Text
	var commitSHA, fromCommitVersion string
	var startedAt time.Time
	var immutableJSON string
	return conn.QueryRow(ctx, `WITH claimed AS (
		UPDATE public.upgrade
		   SET state = 'in_progress',
		       started_at = now(),
		       from_commit_version = $1,
		       claim_token = $3::uuid
		 WHERE id = $2 AND state = 'scheduled' AND started_at IS NULL
		 RETURNING commit_tags, recreate, id, commit_version, commit_sha, from_commit_version, started_at
	),
	labelled AS (
		SELECT c.commit_tags, c.recreate, c.id, c.commit_version, c.commit_sha,
		       COALESCE(c.from_commit_version, '') AS from_commit_version, c.started_at
		  FROM claimed AS c
	)
	SELECT l.commit_tags, l.recreate, l.id, l.commit_version, l.commit_sha,
	       l.from_commit_version, l.started_at,
	       (SELECT to_json(t)::text FROM (SELECT l.id AS id, l.commit_version AS commit_version,
	        l.commit_sha AS commit_sha, l.from_commit_version AS from_commit_version,
	        l.started_at AS started_at) AS t)
	  FROM labelled AS l`, "v2026.09.2", id, claimToken).Scan(
		&commitTags, &recreate, &returnedID, &commitVersion, &commitSHA,
		&fromCommitVersion, &startedAt, &immutableJSON)
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

func writeFixtureProjectEnv(t *testing.T, values map[string]string, dbName string) string {
	t.Helper()
	dir := t.TempDir()
	contents := fmt.Sprintf("CADDY_DB_BIND_ADDRESS=%s\nCADDY_DB_PORT=%s\nPOSTGRES_ADMIN_DB=%s\nPOSTGRES_ADMIN_USER=%s\nPOSTGRES_ADMIN_PASSWORD=%s\nPOSTGRES_APP_DB=%s\n",
		values["CADDY_DB_BIND_ADDRESS"], values["CADDY_DB_PORT"], values["POSTGRES_ADMIN_DB"],
		values["POSTGRES_ADMIN_USER"], values["POSTGRES_ADMIN_PASSWORD"], dbName)
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}
