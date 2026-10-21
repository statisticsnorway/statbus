package cmd

import (
	"reflect"
	"testing"
)

// A recovery session is the operator's own psql session opened for writing
// while an upgrade holds the database read-only: the read-only default is
// turned off for that session only, and it names itself in pg_stat_activity.
// The mode comes from STATBUS_PSQL; every psql argument reaches psql as given.
func TestPsqlRecoverySessionWritesThroughTheReadOnlyWindow(t *testing.T) {
	given := []string{"-v", "x=recovery", "-c", "SELECT 1", "--recovery"}
	t.Run("host psql gets the session option in its environment", func(t *testing.T) {
		t.Setenv("PGOPTIONS", "")
		args, env, err := psqlSessionArgs("recovery", "psql", nil, given, []string{"PGHOST=db"})
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(args, given) {
			t.Fatalf("args = %q, want %q", args, given)
		}
		if want := []string{"PGHOST=db", "PGAPPNAME=sb psql recovery", "PGOPTIONS=-c default_transaction_read_only=off"}; !reflect.DeepEqual(env, want) {
			t.Fatalf("env = %q, want %q", env, want)
		}
	})
	t.Run("docker psql gets the session option inside the container", func(t *testing.T) {
		args, env, err := psqlSessionArgs("recovery", "docker", []string{"compose", "exec", "db", "psql"}, given, nil)
		if err != nil {
			t.Fatal(err)
		}
		want := append([]string{"compose", "exec", "-e", "PGOPTIONS=-c default_transaction_read_only=off", "-e", "PGAPPNAME=sb psql recovery", "db", "psql"}, given...)
		if !reflect.DeepEqual(args, want) {
			t.Fatalf("args = %q, want %q", args, want)
		}
		if env != nil {
			t.Fatalf("env = %q, want nil", env)
		}
	})
	t.Run("an ordinary session forwards every argument as given", func(t *testing.T) {
		args, env, err := psqlSessionArgs("", "psql", []string{"-X"}, given, []string{"PGHOST=db"})
		if err != nil {
			t.Fatal(err)
		}
		if want := append([]string{"-X"}, given...); !reflect.DeepEqual(args, want) {
			t.Fatalf("args = %q, want %q", args, want)
		}
		if want := []string{"PGHOST=db"}; !reflect.DeepEqual(env, want) {
			t.Fatalf("env = %q, want %q", env, want)
		}
	})
}
