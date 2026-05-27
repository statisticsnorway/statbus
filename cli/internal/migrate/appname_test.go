package migrate

import (
	"slices"
	"strings"
	"testing"
)

// #14 (migrate-orphan clean kill): the migration psql SUBPROCESS must carry a
// distinct application_name so that, on a migrate TIMEOUT, the upgrade service
// can pg_terminate_backend the orphaned in-container backend (docker compose
// exec does NOT forward SIGKILL, so a host-side process-group kill leaves the
// in-container psql alive with its txn open). injectPsqlAppName tags it in BOTH
// modes — host (PGAPPNAME env) and docker (`-e PGAPPNAME=` passed INTO the
// container, since the host `docker` process's env does NOT reach the
// in-container psql). These guards pin the tagging for both PsqlCommand shapes.

func TestInjectPsqlAppName_HostMode(t *testing.T) {
	// Host mode: psqlPath="psql", empty prefix, env carries PG* vars.
	args := []string{"-v", "ON_ERROR_STOP=on"}
	env := []string{"PGHOST=127.0.0.1", "PGPORT=5432"}
	gotArgs, gotEnv := injectPsqlAppName("psql", args, env, "statbus-migrate-sql-123")

	// Host mode must NOT touch args (no -e; that's a docker-exec flag).
	if !slices.Equal(gotArgs, args) {
		t.Errorf("host mode must not modify args; got %v", gotArgs)
	}
	// PGAPPNAME must be appended to env.
	found := false
	for _, e := range gotEnv {
		if e == "PGAPPNAME=statbus-migrate-sql-123" {
			found = true
		}
	}
	if !found {
		t.Errorf("host mode must append PGAPPNAME to env; got %v", gotEnv)
	}
}

func TestInjectPsqlAppName_DockerMode(t *testing.T) {
	// Docker mode: psqlPath="docker", prefix is the compose-exec invocation.
	args := []string{"compose", "exec", "-T", "-w", "/statbus", "db", "psql", "-U", "postgres", "-d", "statbus", "-v", "ON_ERROR_STOP=on"}
	gotArgs, gotEnv := injectPsqlAppName("docker", args, nil, "statbus-migrate-sql-123")

	// Docker mode passes PGAPPNAME INTO the container via `-e KEY=VAL` — a
	// `docker compose exec` OPTION, which must appear BEFORE the service name
	// ("db") and the command ("psql").
	joined := strings.Join(gotArgs, " ")
	if !strings.Contains(joined, "-e PGAPPNAME=statbus-migrate-sql-123") {
		t.Errorf("docker mode must inject `-e PGAPPNAME=...` into the exec args; got %v", gotArgs)
	}
	// The -e flag must precede the service name "db" (it's an exec option).
	eIdx := slices.Index(gotArgs, "-e")
	dbIdx := slices.Index(gotArgs, "db")
	if eIdx < 0 || dbIdx < 0 || eIdx > dbIdx {
		t.Errorf("`-e` must come before the service name `db` (it's an exec option); -e@%d db@%d args=%v", eIdx, dbIdx, gotArgs)
	}
	// psql + its flags must still be intact (we didn't clobber the command).
	if !strings.Contains(joined, "psql -U postgres -d statbus -v ON_ERROR_STOP=on") {
		t.Errorf("docker mode must preserve the psql command + flags; got %v", gotArgs)
	}
	// env unchanged in docker mode (the host docker process env is irrelevant).
	if gotEnv != nil {
		t.Errorf("docker mode must not set host env (use -e instead); got %v", gotEnv)
	}
}

// TestMigrateSubprocessAppName: the tag has the agreed prefix so the
// terminate-side LIKE match (statbus-migrate-sql%) finds it, and embeds the pid
// for forensics/uniqueness.
func TestMigrateSubprocessAppName(t *testing.T) {
	name := migrateSubprocessAppName()
	if !strings.HasPrefix(name, migrateSubprocessAppNamePrefix) {
		t.Errorf("migrateSubprocessAppName()=%q must start with the match prefix %q (the terminate side matches by LIKE %q)",
			name, migrateSubprocessAppNamePrefix, migrateSubprocessAppNamePrefix+"%")
	}
	if name == migrateSubprocessAppNamePrefix {
		t.Error("migrateSubprocessAppName must append a pid suffix (forensics), not equal the bare prefix")
	}
}
