package migrate

import (
	"slices"
	"strings"
	"testing"
)

// STATBUS-110 read-only upgrade window: migrate is the upgrade's OWN writer, so
// its psql sessions must self-exempt from the app DB's
// default_transaction_read_only=on window while EXTERNAL sessions stay blocked.
// injectReadOnlyExempt applies the exemption in BOTH PsqlCommand modes — host
// (PGOPTIONS env) and docker (`-e PGOPTIONS=` INTO the container, since the host
// process's env does NOT reach the in-container psql). These guards pin that the
// exemption is actually delivered in each shape (a silent miss = every migration
// write fails under the window) AND that it never clobbers an operator PGOPTIONS.

func TestInjectReadOnlyExempt_HostMode(t *testing.T) {
	t.Setenv("PGOPTIONS", "") // no operator PGOPTIONS
	args := []string{"-v", "ON_ERROR_STOP=on"}
	env := []string{"PGHOST=127.0.0.1", "PGPORT=5432"}
	gotArgs, gotEnv := injectReadOnlyExempt("psql", args, env)

	// Host mode must NOT touch args (no -e; that's a docker-exec flag).
	if !slices.Equal(gotArgs, args) {
		t.Errorf("host mode must not modify args; got %v", gotArgs)
	}
	if !slices.Contains(gotEnv, "PGOPTIONS="+migrateReadOnlyExemptOptions) {
		t.Errorf("host mode must append PGOPTIONS=%q to env; got %v", migrateReadOnlyExemptOptions, gotEnv)
	}
}

// The one dangerous failure is a SILENT clobber of an operator's PGOPTIONS — the
// exemption must MERGE, not replace.
func TestInjectReadOnlyExempt_HostMode_MergesExistingPGOPTIONS(t *testing.T) {
	t.Setenv("PGOPTIONS", "-c statement_timeout=5000")
	gotArgs, gotEnv := injectReadOnlyExempt("psql", []string{"-v", "ON_ERROR_STOP=on"}, []string{"PGHOST=127.0.0.1"})
	if len(gotArgs) != 2 {
		t.Errorf("host mode must not modify args; got %v", gotArgs)
	}
	want := "PGOPTIONS=-c statement_timeout=5000 " + migrateReadOnlyExemptOptions
	if !slices.Contains(gotEnv, want) {
		t.Errorf("host mode must MERGE with the operator PGOPTIONS (not clobber it); want %q in %v", want, gotEnv)
	}
}

func TestInjectReadOnlyExempt_DockerMode(t *testing.T) {
	t.Setenv("PGOPTIONS", "") // docker container has no inherited PGOPTIONS
	args := []string{"compose", "exec", "-T", "-w", "/statbus", "db", "psql", "-U", "postgres", "-d", "statbus", "-v", "ON_ERROR_STOP=on"}
	gotArgs, gotEnv := injectReadOnlyExempt("docker", args, nil)

	joined := strings.Join(gotArgs, " ")
	if !strings.Contains(joined, "-e PGOPTIONS="+migrateReadOnlyExemptOptions) {
		t.Errorf("docker mode must inject `-e PGOPTIONS=...` into the exec args; got %v", gotArgs)
	}
	// The -e flag must precede the service name "db" (it's an exec option).
	eIdx := slices.Index(gotArgs, "-e")
	dbIdx := slices.Index(gotArgs, "db")
	if eIdx < 0 || dbIdx < 0 || eIdx > dbIdx {
		t.Errorf("`-e` must come before the service name `db`; -e@%d db@%d args=%v", eIdx, dbIdx, gotArgs)
	}
	// psql command + flags intact.
	if !strings.Contains(joined, "psql -U postgres -d statbus -v ON_ERROR_STOP=on") {
		t.Errorf("docker mode must preserve the psql command + flags; got %v", gotArgs)
	}
	// env unchanged in docker mode.
	if gotEnv != nil {
		t.Errorf("docker mode must not set host env (use -e instead); got %v", gotEnv)
	}
}

// The exemption value must actually be the read-only-off GUC — a guard against a
// future typo silently disarming the exemption (every migration write would fail
// under the window).
func TestMigrateReadOnlyExemptOptions_TargetsTheGUC(t *testing.T) {
	if !strings.Contains(migrateReadOnlyExemptOptions, "default_transaction_read_only=off") {
		t.Errorf("exemption must set default_transaction_read_only=off; got %q", migrateReadOnlyExemptOptions)
	}
	if !strings.HasPrefix(migrateReadOnlyExemptOptions, "-c ") {
		t.Errorf("exemption must be a libpq `-c` startup option; got %q", migrateReadOnlyExemptOptions)
	}
}
