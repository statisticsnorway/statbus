package migrate

import (
	"fmt"
	"strconv"
	"strings"
)

// STATBUS-533 (owner-approved design): extension upgrades are their own
// lifecycle step, run by the migrate runner on the ACTUAL target database
// BEFORE the pending-migration set is computed. Normal migrations contain
// schema changes only — no migration ever creates or updates an extension,
// so no migration can run an old extension update script against a newer
// native library. Future extension bumps change the image pin
// (postgres/Dockerfile) and ride this step; they never add a migration file.
//
// Per tracked extension, decided from the live catalogs (pg_extension vs
// pg_available_extensions.default_version, i.e. the image pin):
//
//   - absent: CREATE EXTENSION at the image default. Covers fresh databases
//     and partial old-dump restores that lack the extension entirely.
//   - older:  one direct ALTER EXTENSION UPDATE TO the image default, using
//     upstream's direct update script (e.g. sql_saga--1.0--1.4.sql), with
//     the extension's integrity check in the same transaction. NEVER
//     intermediate hops: an old update script refuses against the newer
//     native library.
//   - equal:  nothing.
//   - newer:  REFUSE. Never downgrade; the operator needs a newer image.
//
// Every create/update is recorded as an audit receipt in
// db.extension_upgrade (extension, from_version, to_version, applied_at).
// The receipt names the EVENT only — it deliberately carries no list of
// retired migration IDs (there is no registry, no satisfied_migrations, no
// at-head exemption and no special redo path for extension updates).

// trackedExtension is one extension the application schema depends on. The
// runner guarantees it exists at the image default before any migration runs.
type trackedExtension struct {
	name string
	// integrityCheck, when non-empty, is a statement run in the same
	// transaction right after a direct update. sql_saga's update scripts end
	// in check_integrity() themselves; stating it here keeps the check
	// explicit at the call site that owns the "older" decision.
	integrityCheck string
}

// trackedExtensions lists every extension the schema requires, in reconcile
// order. sql_saga first: later migrations build on its API. jsonb_stats next
// (the derive pipeline's aggregates), then the contrib extensions the early
// migrations historically CREATEd inline (ltree for category paths, citext
// for auth emails, btree_gist for multirange GiST indexes).
var trackedExtensions = []trackedExtension{
	{name: "sql_saga", integrityCheck: "SELECT sql_saga.check_integrity()"},
	{name: "jsonb_stats"},
	{name: "ltree"},
	{name: "citext"},
	{name: "btree_gist"},
}

// ensureExtensionUpgradeTableSQL creates the audit receipt table. It lives in
// the runner (like db.migration in ensureMigrationTableSQL) because the
// extension lifecycle step runs BEFORE migrations — a database whose first
// contact with this code is an extension upgrade has no migration that could
// have created the table yet.
const ensureExtensionUpgradeTableSQL = `
CREATE SCHEMA IF NOT EXISTS db;
CREATE TABLE IF NOT EXISTS db.extension_upgrade (
  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  extension TEXT NOT NULL,
  from_version TEXT,
  to_version TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE db.extension_upgrade IS
  'Audit receipt for the migrate runner extension lifecycle step (STATBUS-533): one row per extension create/update event on this database, written before pending migrations are computed. Never lists retired migration IDs; db.migration records schema migrations only.';
COMMENT ON COLUMN db.extension_upgrade.extension IS 'Extension name (pg_extension.extname).';
COMMENT ON COLUMN db.extension_upgrade.from_version IS 'Installed version before the event; NULL when the event created the extension.';
COMMENT ON COLUMN db.extension_upgrade.to_version IS 'Version after the event: always the database image default (pg_available_extensions.default_version).';
COMMENT ON COLUMN db.extension_upgrade.applied_at IS 'When the runner applied the event.';
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_policies WHERE schemaname = 'db' AND tablename = 'extension_upgrade' AND policyname = 'extension_upgrade_authenticated_read') THEN
    ALTER TABLE db.extension_upgrade ENABLE ROW LEVEL SECURITY;
    CREATE POLICY extension_upgrade_authenticated_read ON db.extension_upgrade FOR SELECT TO authenticated USING (true);
  END IF;
END $$;`

// EnsureTrackedExtensions reconciles every tracked extension on the target
// database with the image default version. runUp calls it before computing
// pending migrations, so fresh installs, old-template replays, partial
// old-dump restores and production upgrades all take the same path.
func EnsureTrackedExtensions(projDir string) error {
	if _, err := runPsql(projDir, ensureExtensionUpgradeTableSQL); err != nil {
		return fmt.Errorf("ensure db.extension_upgrade: %w", err)
	}
	defaults, err := imageExtensionDefaults(projDir)
	if err != nil {
		return err
	}
	installed, err := installedExtensionVersions(projDir)
	if err != nil {
		return err
	}
	for _, ext := range trackedExtensions {
		imageDefault, ok := defaults[ext.name]
		if !ok {
			return fmt.Errorf("tracked extension %s is not provided by this database image "+
				"(no pg_available_extensions row); the image must install it (postgres/Dockerfile)", ext.name)
		}
		current, present := installed[ext.name]
		switch {
		case !present:
			if _, err := runPsql(projDir, fmt.Sprintf(
				"BEGIN;\nCREATE EXTENSION %s;\nINSERT INTO db.extension_upgrade (extension, from_version, to_version) VALUES (%s, NULL, %s);\nCOMMIT;",
				quoteIdent(ext.name), sqlLiteralStr(ext.name), sqlLiteralStr(imageDefault))); err != nil {
				return fmt.Errorf("create extension %s at image default %s: %w", ext.name, imageDefault, err)
			}
			fmt.Printf("[migrate] Extension %s: absent -> created at image default %s\n", ext.name, imageDefault)
		default:
			cmp, cmpErr := compareExtensionVersions(current, imageDefault)
			if cmpErr != nil {
				return fmt.Errorf("extension %s: %w", ext.name, cmpErr)
			}
			switch {
			case cmp == 0:
				// At the image default; nothing to do.
			case cmp < 0:
				if err := updateExtensionDirect(projDir, ext, current, imageDefault); err != nil {
					return err
				}
			default:
				return fmt.Errorf("extension %s is at version %s, NEWER than the database image's default %s. "+
					"Refusing to downgrade: run a database image that provides %s %s or newer",
					ext.name, current, imageDefault, ext.name, current)
			}
		}
	}
	return nil
}

// updateExtensionDirect performs the "older" arm: one direct ALTER EXTENSION
// UPDATE TO the image default plus the extension's integrity check and the
// audit receipt, all in a single transaction so a refusal leaves the previous
// version intact.
func updateExtensionDirect(projDir string, ext trackedExtension, fromVersion, toVersion string) error {
	var b strings.Builder
	b.WriteString("BEGIN;\nSET LOCAL lock_timeout = '30s';\n")
	fmt.Fprintf(&b, "ALTER EXTENSION %s UPDATE TO %s;\n", quoteIdent(ext.name), sqlLiteralStr(toVersion))
	if ext.integrityCheck != "" {
		b.WriteString(ext.integrityCheck + ";\n")
	}
	fmt.Fprintf(&b, "INSERT INTO db.extension_upgrade (extension, from_version, to_version) VALUES (%s, %s, %s);\n",
		sqlLiteralStr(ext.name), sqlLiteralStr(fromVersion), sqlLiteralStr(toVersion))
	b.WriteString("COMMIT;")
	if _, err := runPsql(projDir, b.String()); err != nil {
		return fmt.Errorf("update extension %s directly from %s to image default %s: %w",
			ext.name, fromVersion, toVersion, err)
	}
	fmt.Printf("[migrate] Extension %s: %s -> %s (direct update to image default)\n", ext.name, fromVersion, toVersion)
	return nil
}

// imageExtensionDefaults reads the image's pin for every tracked extension:
// the version CREATE EXTENSION would install on this image.
func imageExtensionDefaults(projDir string) (map[string]string, error) {
	return extensionVersionMap(projDir,
		"SELECT name || '=' || default_version FROM pg_available_extensions WHERE name IN ("+
			trackedExtensionsInList()+")")
}

// installedExtensionVersions reads the versions actually installed in the
// TARGET database (pg_extension is per-database).
func installedExtensionVersions(projDir string) (map[string]string, error) {
	return extensionVersionMap(projDir,
		"SELECT extname || '=' || extversion FROM pg_extension WHERE extname IN ("+
			trackedExtensionsInList()+")")
}

// extensionVersionMap runs a "name=version"-per-line query and splits it.
func extensionVersionMap(projDir, sql string) (map[string]string, error) {
	out, err := runPsql(projDir, sql, "-t", "-A")
	if err != nil {
		return nil, fmt.Errorf("query extension versions: %w", err)
	}
	versions := make(map[string]string)
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		name, version, found := strings.Cut(line, "=")
		if !found {
			return nil, fmt.Errorf("unexpected extension version row %q", line)
		}
		versions[name] = version
	}
	return versions, nil
}

// HasExtensionDrift reports whether any tracked extension on the target
// database is absent or at a version other than the image default. Install's
// checkMigrationsDone ORs this with HasPending so that a release which bumps
// an extension pin WITHOUT new migration files still routes the box through
// migrate up — the extension lifecycle step lives there (STATBUS-533).
// A newer-than-image version is drift too; runUp then refuses (never
// downgrade), which is exactly the loud failure the operator needs.
func HasExtensionDrift(projDir string) (bool, error) {
	defaults, err := imageExtensionDefaults(projDir)
	if err != nil {
		return false, err
	}
	installed, err := installedExtensionVersions(projDir)
	if err != nil {
		return false, err
	}
	for _, ext := range trackedExtensions {
		imageDefault, ok := defaults[ext.name]
		if !ok {
			return false, fmt.Errorf("tracked extension %s is not provided by this database image "+
				"(no pg_available_extensions row); the image must install it (postgres/Dockerfile)", ext.name)
		}
		current, present := installed[ext.name]
		if !present {
			return true, nil
		}
		cmp, cmpErr := compareExtensionVersions(current, imageDefault)
		if cmpErr != nil {
			return false, fmt.Errorf("extension %s: %w", ext.name, cmpErr)
		}
		if cmp != 0 {
			return true, nil
		}
	}
	return false, nil
}

// compareExtensionVersions orders dotted-numeric version strings ("1.10" >
// "1.9"). Missing trailing segments read as zero ("1.4" == "1.4.0").
// A non-numeric segment is an error: the caller refuses rather than guesses
// an ordering that could downgrade.
func compareExtensionVersions(a, b string) (int, error) {
	as, bs := strings.Split(a, "."), strings.Split(b, ".")
	n := len(as)
	if len(bs) > n {
		n = len(bs)
	}
	for i := 0; i < n; i++ {
		ai, bi := 0, 0
		var err error
		if i < len(as) {
			if ai, err = strconv.Atoi(as[i]); err != nil {
				return 0, fmt.Errorf("cannot order versions %q and %q: segment %q is not numeric; refusing to guess", a, b, as[i])
			}
		}
		if i < len(bs) {
			if bi, err = strconv.Atoi(bs[i]); err != nil {
				return 0, fmt.Errorf("cannot order versions %q and %q: segment %q is not numeric; refusing to guess", a, b, bs[i])
			}
		}
		if ai != bi {
			if ai < bi {
				return -1, nil
			}
			return 1, nil
		}
	}
	return 0, nil
}

func quoteIdent(s string) string {
	return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
}

func sqlLiteralStr(s string) string {
	return `'` + strings.ReplaceAll(s, `'`, `''`) + `'`
}

// trackedExtensionsInList renders the tracked names as a SQL IN-list tuple.
func trackedExtensionsInList() string {
	quoted := make([]string, len(trackedExtensions))
	for i, e := range trackedExtensions {
		quoted[i] = sqlLiteralStr(e.name)
	}
	return strings.Join(quoted, ",")
}
