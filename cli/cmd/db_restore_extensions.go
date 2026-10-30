package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// legacySqlSagaUpdateMigrations maps the retired pure extension-update
// migrations (removed by STATBUS-533, migration 20261027221500) to the
// sql_saga version each left the database at. A dump made before
// db.extension_upgrade existed carries its sql_saga version only as these
// db.migration rows. Ordered oldest first.
var legacySqlSagaUpdateMigrations = []struct {
	version string
	sqlSaga string
}{
	{"20261015163419", "1.1"},
	{"20261021130641", "1.3"},
	{"20261027135139", "1.4"},
}

// dumpSqlSagaVersion returns the sql_saga version a dump was made with, read
// from the dump's own data (pg_dump does not record extension versions):
// the newest sql_saga receipt in db.extension_upgrade (written by the
// extension lifecycle step since STATBUS-533), else the newest retired
// sql_saga update migration in db.migration, else 1.0, the version every
// database had before those migrations. auditCopy and migrationCopy are the
// COPY text pg_restore --data-only emits for those two tables, empty when
// the dump lacks the table.
func dumpSqlSagaVersion(auditCopy, migrationCopy string) string {
	newestReceipt := ""
	for _, row := range copyRows(auditCopy) {
		// id, extension, from_version, to_version, applied_at; rows are in id order.
		if len(row) >= 4 && row[1] == "sql_saga" {
			newestReceipt = row[3]
		}
	}
	if newestReceipt != "" {
		return newestReceipt
	}
	applied := map[string]bool{}
	for _, row := range copyRows(migrationCopy) {
		// id, version, ...
		if len(row) >= 2 {
			applied[row[1]] = true
		}
	}
	version := "1.0"
	for _, m := range legacySqlSagaUpdateMigrations {
		if applied[m.version] {
			version = m.sqlSaga
		}
	}
	return version
}

// copyRows splits the data rows of pg_restore COPY output into fields.
func copyRows(copyText string) [][]string {
	var rows [][]string
	inCopy := false
	sc := bufio.NewScanner(strings.NewReader(copyText))
	sc.Buffer(make([]byte, 1024*1024), 16*1024*1024)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "COPY "):
			inCopy = true
		case line == `\.`:
			inCopy = false
		case inCopy:
			rows = append(rows, strings.Split(line, "\t"))
		}
	}
	return rows
}

// restoreDumpTableData returns the COPY text of one table in the dump already
// copied to /tmp/restore.pg_dump in the db container ("" when absent).
func restoreDumpTableData(projDir, schema, table string) (string, error) {
	c, err := composeCommand(projDir, "exec", "-T", "db",
		"pg_restore", "--data-only", "-f", "-", "-n", schema, "-t", table, "/tmp/restore.pg_dump")
	if err != nil {
		return "", err
	}
	c.Stderr = os.Stderr
	out, err := c.Output()
	if err != nil {
		return "", fmt.Errorf("read %s.%s from dump: %w", schema, table, err)
	}
	return string(out), nil
}

// preinstallDumpSqlSaga creates sql_saga in the empty target database at the
// version the dump was made with, before the dump's schema loads. The dump's
// CREATE EXTENSION IF NOT EXISTS then keeps that version, so its catalog rows
// load into the layout they were written for. sql_saga's own restore
// procedure (doc/upgrade.md "Restore at the dump's own extension version")
// requires this; the image default would reject an older dump's rows.
func preinstallDumpSqlSaga(projDir, dbName string) (string, error) {
	audit, err := restoreDumpTableData(projDir, "db", "extension_upgrade")
	if err != nil {
		return "", err
	}
	ledger, err := restoreDumpTableData(projDir, "db", "migration")
	if err != nil {
		return "", err
	}
	version := dumpSqlSagaVersion(audit, ledger)
	sql := fmt.Sprintf("BEGIN;\nCREATE EXTENSION IF NOT EXISTS btree_gist;\nCREATE EXTENSION sql_saga VERSION '%s';\nCOMMIT;",
		strings.ReplaceAll(version, "'", "''"))
	c, err := composeCommand(projDir, "exec", "-T", "db",
		"psql", "-U", "postgres", "-d", dbName, "-v", "ON_ERROR_STOP=1", "-c", sql)
	if err != nil {
		return "", err
	}
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	if err := c.Run(); err != nil {
		return "", fmt.Errorf("create sql_saga %s for the dump: %w", version, err)
	}
	return version, nil
}

// reconcileRestoredExtensions runs the extension lifecycle step
// (migrate.EnsureTrackedExtensions) on the restored database, after its data
// and ACLs are in: an extension older than the image default updates to it
// with its integrity check, exactly as on upgrade.
func reconcileRestoredExtensions(projDir string) error {
	if err := migrate.EnsureTrackedExtensions(projDir); err != nil {
		return fmt.Errorf("extension lifecycle step after restore: %w", err)
	}
	return nil
}
