package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// STATBUS-481 — the seed must be RESTORABLE, and restorable AGAIN.
//
// The published seed is a pg_dump that every install, every CI run and the
// next incremental seed build restores. A dump that cannot be restored is
// therefore a broken release artifact, and until STATBUS-481 that failure
// surfaced only downstream: the next seed build's incremental restore failed
// and CI silently fell back to a FULL_REPLAY, so the breakage looked like an
// unrelated Images failure.
//
// verifySeedRoundTrip makes the seed build itself fail LOUDLY instead. After
// DumpSeed it:
//   1. restores the just-written seed.pg_dump into an empty database prepared
//      exactly like a box's (CreateSeedDb's template_statbus + auth grants),
//      through restoreSeedDump, the production restore code path;
//   2. dumps that database and restores the second dump into another empty
//      database (dump -> restore -> dump -> restore: the invariant that broke);
//   3. requires the ACL digest (every relation and function ACL) of the seed,
//      of round trip 1 and of round trip 2 to be identical, so a restore that
//      "succeeds" by losing or mangling grants is also caught;
//   4. requires every DDL event trigger to still be ENABLED after the restores,
//      so the replica-role restore accommodation can never be mistaken for, or
//      silently turn into, a disabled sql_saga health check.
//
// It reuses the restore the build already performs for incremental seeds, at
// the cost of two schema-sized restores (a few seconds for a seed), and is
// bolted onto the build rather than added as a separate CI job.

// seedACLDigestSQL is one md5 over every relation ACL and every function ACL
// outside the system schemas, keyed by object identity, so it is stable across
// OIDs and detects any grant difference. It digests the EFFECTIVE ACL
// (COALESCE(acl, acldefault(...))): pg_dump omits an ACL that equals the
// owner's default, so a migrated database that stores the default explicitly
// (e.g. auth.secrets after REVOKE ALL ... FROM PUBLIC, {postgres=arwdDxtm/postgres})
// restores it as NULL, which grants exactly the same privileges. Comparing the
// stored form would report that as a lost grant (it did, on the first FULL
// seed build after the check landed).
const seedACLDigestSQL = `SELECT md5(
  (SELECT string_agg(c.oid::regclass::text || '=' || COALESCE(c.relacl, acldefault(CASE WHEN c.relkind = 'S' THEN 's'::"char" ELSE 'r'::"char" END, c.relowner))::text, '|' ORDER BY c.oid::regclass::text)
     FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
      AND n.nspname NOT LIKE 'pg_temp%' AND n.nspname NOT LIKE 'pg_toast_temp%')
  || '#' ||
  (SELECT string_agg(p.oid::regprocedure::text || '=' || COALESCE(p.proacl, acldefault('f', p.proowner))::text, '|' ORDER BY p.oid::regprocedure::text)
     FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')))`

// seedEventTriggerStateSQL reports enabled/total DDL event triggers.
const seedEventTriggerStateSQL = `SELECT count(*) FILTER (WHERE evtenabled <> 'D') || '/' || count(*) FROM pg_event_trigger`

func seedRoundTripDbNames(seedDbName string) (string, string) {
	return seedDbName + "_roundtrip1", seedDbName + "_roundtrip2"
}

// prepareEmptyRestoreTarget creates dbName exactly like CreateSeedDb prepares
// the seed: from template_statbus, plus the per-database auth schema grants.
func prepareEmptyRestoreTarget(projDir, dbName string) error {
	if err := migrate.ExecOnDB(projDir, "postgres",
		fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE);", pgQuoteIdent(dbName))); err != nil {
		return fmt.Errorf("drop %s: %w", dbName, err)
	}
	if err := migrate.ExecOnDB(projDir, "postgres",
		fmt.Sprintf("CREATE DATABASE %s WITH TEMPLATE template_statbus OWNER postgres;", pgQuoteIdent(dbName))); err != nil {
		return fmt.Errorf("create %s from template_statbus: %w", dbName, err)
	}
	return migrate.ExecOnDB(projDir, dbName,
		"CREATE SCHEMA IF NOT EXISTS auth;\n"+
			"GRANT USAGE ON SCHEMA auth TO authenticated;\n"+
			"GRANT USAGE ON SCHEMA auth TO anon;\n"+
			"GRANT USAGE ON SCHEMA public TO notify_reader;\n")
}

func seedACLState(projDir, dbName string) (digest string, eventTriggers string, err error) {
	digest, err = migrate.QueryDB(projDir, dbName, seedACLDigestSQL, "-t", "-A")
	if err != nil {
		return "", "", fmt.Errorf("ACL digest of %s: %w", dbName, err)
	}
	eventTriggers, err = migrate.QueryDB(projDir, dbName, seedEventTriggerStateSQL, "-t", "-A")
	if err != nil {
		return "", "", fmt.Errorf("event trigger state of %s: %w", dbName, err)
	}
	return strings.TrimSpace(digest), strings.TrimSpace(eventTriggers), nil
}

// verifySeedRoundTrip proves the published seed restores, and that its
// restore restores again with identical grants and enabled event triggers.
func verifySeedRoundTrip(projDir, seedDbName string) (result error) {
	seedDump := filepath.Join(projDir, ".db-seed", "seed.pg_dump")
	rt1, rt2 := seedRoundTripDbNames(seedDbName)
	rt1Dump := filepath.Join(projDir, ".db-seed", "roundtrip1.pg_dump")
	defer func() {
		_ = os.Remove(rt1Dump)
		for _, db := range []string{rt1, rt2} {
			if err := migrate.ExecOnDB(projDir, "postgres",
				fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE);", pgQuoteIdent(db))); err != nil && result == nil {
				result = fmt.Errorf("seed round trip: drop %s: %w", db, err)
			}
		}
	}()

	wantDigest, wantTriggers, err := seedACLState(projDir, seedDbName)
	if err != nil {
		return err
	}

	fmt.Printf("seed round trip (STATBUS-481): restore seed.pg_dump -> %s\n", rt1)
	if err := prepareEmptyRestoreTarget(projDir, rt1); err != nil {
		return fmt.Errorf("seed round trip: %w", err)
	}
	if err := restoreSeedDump(projDir, rt1, seedDump); err != nil {
		return fmt.Errorf("seed round trip FAILED: the seed dump cannot be restored into an empty database: %w", err)
	}
	fmt.Printf("seed round trip (STATBUS-481): dump %s -> restore -> %s\n", rt1, rt2)
	if err := dumpVerifyDB(projDir, rt1, rt1Dump); err != nil {
		return fmt.Errorf("seed round trip: %w", err)
	}
	if err := prepareEmptyRestoreTarget(projDir, rt2); err != nil {
		return fmt.Errorf("seed round trip: %w", err)
	}
	if err := restoreSeedDump(projDir, rt2, rt1Dump); err != nil {
		return fmt.Errorf("seed round trip FAILED: a database restored from the seed dumps to an unrestorable archive: %w", err)
	}

	for _, db := range []string{rt1, rt2} {
		digest, triggers, err := seedACLState(projDir, db)
		if err != nil {
			return err
		}
		if digest != wantDigest {
			return fmt.Errorf("seed round trip FAILED: ACL digest of %s (%s) differs from the seed's (%s): the restore lost or changed grants", db, digest, wantDigest)
		}
		if triggers != wantTriggers {
			return fmt.Errorf("seed round trip FAILED: event triggers enabled/total in %s is %s, seed has %s: a restore must never leave the sql_saga health checks disabled", db, triggers, wantTriggers)
		}
	}
	fmt.Printf("seed round trip (STATBUS-481): OK — seed -> restore -> dump -> restore; ACL digest %s identical; event triggers enabled %s\n",
		wantDigest, wantTriggers)
	return seedRestoredTypesCheck(projDir, rt1)
}
