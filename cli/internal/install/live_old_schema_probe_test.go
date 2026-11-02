//go:build livedb

package install

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// STATBUS-559: install state detection runs BEFORE migrations, so every probe
// it uses must resolve on any schema the installer accepts — including the
// oldest released one (v2026.03.0), whose public.upgrade predates the state
// machine, the version column, and rollback_finish_pending_at. A probe that
// names a newer column stops the install on an older box even though the
// condition the column guards cannot hold there.
//
// These tests run the REAL probes (defaultProbe: psql against the fixture
// project's database) against scratch databases shaped like those old
// schemas. Before the fix, QueryScheduledUpgrade and QueryReattemptableRestore
// both fail with `column "..." does not exist`; after it they classify the
// rows by the old shape's own semantics.
//
// go test -tags livedb -count=1 ./internal/install
func TestPreMigrationProbesWorkOnOlderAcceptedSchemas(t *testing.T) {
	projDir := liveProjDir(t)

	t.Run("v2026.03.0 shape: no state, version, or rollback_finish_pending_at", func(t *testing.T) {
		// The commit-centric table as first released in v2026.03.0: scheduled_at
		// is the accept signal, failure is error-without-rollback, and neither
		// the state enum nor any later column exists.
		newScratchUpgradeDB(t, projDir, `
			CREATE TABLE public.upgrade (
				id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
				commit_sha text NOT NULL UNIQUE,
				scheduled_at timestamptz,
				started_at timestamptz,
				completed_at timestamptz,
				error text,
				rollback_completed_at timestamptz,
				backup_path text
			);
			INSERT INTO public.upgrade (commit_sha, scheduled_at)
			VALUES ('1111111111111111111111111111111111111111', now());
			INSERT INTO public.upgrade (commit_sha, scheduled_at, started_at, error, backup_path)
			VALUES ('2222222222222222222222222222222222222222', now(), now(), 'restore failed', '/backups/restore-broke');
			INSERT INTO public.upgrade (commit_sha, scheduled_at, started_at, error, rollback_completed_at, backup_path)
			VALUES ('3333333333333333333333333333333333333333', now(), now(), 'rolled back', now(), '/backups/rolled-back');
		`)

		row, err := (defaultProbe{}).QueryScheduledUpgrade(projDir)
		if err != nil {
			t.Fatalf("QueryScheduledUpgrade on a v2026.03.0 schema: %v", err)
		}
		if row == nil {
			t.Fatal("QueryScheduledUpgrade found no scheduled row on a v2026.03.0 schema")
		}
		if row.ID != 1 || row.CommitSHA != "1111111111111111111111111111111111111111" {
			t.Fatalf("scheduled row = %+v, want id 1 and the scheduled commit", row)
		}

		id, backupPath, found, err := (defaultProbe{}).QueryReattemptableRestore(projDir)
		if err != nil {
			t.Fatalf("QueryReattemptableRestore on a v2026.03.0 schema: %v", err)
		}
		if !found || id != 2 || backupPath != "/backups/restore-broke" {
			t.Fatalf("restore probe = id %d path %q found %t; want the failed row with a retained backup (id 2)", id, backupPath, found)
		}
	})

	t.Run("v2026.09.0 shape: state present, rollback_finish_pending_at absent", func(t *testing.T) {
		// The incident's schema: the state machine and version column exist (and
		// QueryScheduledUpgrade's version fallback is exercised), but STATBUS-347's
		// pending marker does not — so no rollback can be pending on any row.
		newScratchUpgradeDB(t, projDir, `
			CREATE TYPE public.upgrade_state AS ENUM ('available', 'scheduled', 'in_progress', 'completed', 'failed', 'rolled_back', 'dismissed', 'skipped', 'superseded');
			CREATE TABLE public.upgrade (
				id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
				commit_sha text NOT NULL UNIQUE,
				version text,
				state public.upgrade_state NOT NULL DEFAULT 'available',
				scheduled_at timestamptz,
				started_at timestamptz,
				completed_at timestamptz,
				error text,
				rolled_back_at timestamptz,
				backup_path text
			);
			INSERT INTO public.upgrade (commit_sha, version, state, scheduled_at, started_at, error, backup_path)
			VALUES ('4444444444444444444444444444444444444444', 'v2026.10.0', 'failed', now(), now(), 'restore failed', '/backups/restore-broke');
		`)

		row, err := (defaultProbe{}).QueryScheduledUpgrade(projDir)
		if err != nil {
			t.Fatalf("QueryScheduledUpgrade on a v2026.09.0 schema: %v", err)
		}
		if row != nil {
			t.Fatalf("QueryScheduledUpgrade reported %+v, want no scheduled row", row)
		}

		id, backupPath, found, err := (defaultProbe{}).QueryReattemptableRestore(projDir)
		if err != nil {
			t.Fatalf("QueryReattemptableRestore on a v2026.09.0 schema: %v", err)
		}
		if !found || id != 1 || backupPath != "/backups/restore-broke" {
			t.Fatalf("restore probe = id %d path %q found %t; want the failed row with a retained backup (id 1)", id, backupPath, found)
		}
	})
}

// newScratchUpgradeDB creates an empty scratch database, applies ddl, points
// the fixture project's psql probes at it (PGDATABASE wins over .env, in both
// host and docker psql modes), and drops it after the test.
func newScratchUpgradeDB(t *testing.T, projDir, ddl string) {
	t.Helper()
	name := fmt.Sprintf("statbus_probe_old_schema_%d_%d", os.Getpid(), time.Now().UnixNano())
	admin := liveAdminConn(t, projDir)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+name+" TEMPLATE template0"); err != nil {
		t.Fatalf("create scratch database: %v", err)
	}
	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer ccancel()
		if _, err := admin.Exec(cctx, "DROP DATABASE "+name+" WITH (FORCE)"); err != nil {
			t.Errorf("drop scratch database %s: %v", name, err)
		}
		_ = admin.Close(cctx)
	})

	conn := liveConnToDB(t, projDir, name)
	t.Cleanup(func() { _ = conn.Close(context.Background()) })
	if _, err := conn.Exec(ctx, ddl); err != nil {
		t.Fatalf("shape scratch schema: %v", err)
	}
	t.Setenv("PGDATABASE", name)
}

func liveConnToDB(t *testing.T, projDir, dbName string) *pgx.Conn {
	t.Helper()
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		t.Fatal(err)
	}
	get := func(k string) string { v, _ := f.Get(k); return v }
	dsn := "host=" + get("CADDY_DB_BIND_ADDRESS") + " port=" + get("CADDY_DB_PORT") +
		" dbname=" + dbName + " user=" + get("POSTGRES_ADMIN_USER") +
		" password=" + get("POSTGRES_ADMIN_PASSWORD") + " sslmode=disable application_name=probe-old-schema"
	conn, err := pgx.Connect(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect to scratch database %s: %v", dbName, err)
	}
	return conn
}
