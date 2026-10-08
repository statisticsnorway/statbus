package cmd

import (
	"fmt"
	"strings"
)

// restoreTargetConninfo returns the pg_restore `-d` argument for restoring INTO
// dbName with DDL event triggers suppressed for that one restore session
// (session_replication_role=replica). Every pg_restore that recreates a StatBus
// database from a dump MUST use it (STATBUS-481).
//
// WHY. A dump is a replay of the database's final state in pg_dump's
// dependency order, not in the order the state was built. Between two of its
// statements the database can be in a TRANSIENT state no live session ever
// produced. sql_saga's ddl_command_end event trigger (sql_saga.health_checks)
// validates privileges on every GRANT/REVOKE, so it can reject such a transient
// state: with STATBUS-460 (functions taking legal_unit/establishment as their
// argument type) pg_dump emits those tables' GRANTs before an unrelated
// `REVOKE ... ON FUNCTION upgrade_schedule`, while their for_portion_of_valid
// views' GRANTs still come later, and the REVOKE raised "cannot revoke INSERT
// directly from establishment__for_portion_of_valid". The dump was then
// unrestorable, the published seed broke, and CI fell back to a full replay.
//
// THIS IS NOT A WEAKENED CHECK. session_replication_role=replica is set only
// for the restore's own connection (libpq `options`); it suppresses event
// triggers (and ordinary triggers, which --disable-triggers already suppresses)
// while the dump replays state that sql_saga validated when it was first
// built. The event triggers stay ENABLED in the catalog, and every live
// session afterwards is fully guarded. The round trip (dump -> restore ->
// dump -> restore) and an "all event triggers still enabled" assertion run in
// the seed build (verifySeedRoundTrip) so this stays proven.
//
// The value goes through libpq conninfo, so dbName is quoted for that grammar
// (validateIdentifier upstream already restricts it).
func restoreTargetConninfo(dbName string) string {
	quoted := strings.ReplaceAll(strings.ReplaceAll(dbName, `\`, `\\`), `'`, `\'`)
	return fmt.Sprintf("dbname='%s' options='-c session_replication_role=replica'", quoted)
}
