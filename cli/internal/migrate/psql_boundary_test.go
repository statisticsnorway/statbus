package migrate

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// repoRootForPsql: runPsql resolves connection settings from <projDir>/.env
// before it execs psql, so the fixture needs a real project root. The psql
// that actually runs is the fake on PATH; nothing connects anywhere.
func repoRootForPsql(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	root := filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
	if _, err := os.Stat(filepath.Join(root, ".env")); err != nil {
		t.Skip("no .env at repo root; runPsql cannot resolve settings here")
	}
	return root
}

// fakePsql puts a shell script named psql first on PATH so runPsql exercises
// the REAL subprocess boundary (exit status, stderr) rather than a
// hand-built *exec.ExitError. Env is pinned so the psql-resolution code
// takes the host-binary path and never reaches for docker.
func fakePsql(t *testing.T, body string) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "psql")
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+":"+os.Getenv("PATH"))
	t.Setenv("DOCKER_PSQL", "0")
	for _, kv := range [][2]string{{"PGHOST", "x"}, {"PGPORT", "1"}, {"PGDATABASE", "x"}, {"PGUSER", "x"}, {"PGPASSWORD", "x"}} {
		t.Setenv(kv[0], kv[1])
	}
}

// TestPsqlBoundary_ClassifiesFromDocumentedSignalsOnly_STATBUS349 is the
// D4 contract through the real interface (STATBUS-349 review, HIGH). psql's
// documented exit statuses are the only signal besides the SQLSTATE:
//
//	3 = a statement failed under ON_ERROR_STOP     -> deterministic (20)
//	2 = connection lost / not opened                -> UNCLASSIFIED (1)
//	1 = psql's own fatal error                      -> UNCLASSIFIED (1)
//	any + SQLSTATE class 53 on stderr               -> resource (22)
//
// Before the fix every non-53 failure was wrapped as deterministic, so a
// lost connection parked recovery on the first blip.
func TestPsqlBoundary_ClassifiesFromDocumentedSignalsOnly_STATBUS349(t *testing.T) {
	cases := []struct {
		name string
		body string
		want int
	}{
		{"exit3 statement failure", "echo 'ERROR:  42P01: relation does not exist' >&2; exit 3", ExitDeterministic},
		{"exit2 connection lost", "echo 'psql: error: connection to server was lost' >&2; exit 2", ExitUnclassified},
		{"exit1 psql fatal", "echo 'psql: error: could not open file' >&2; exit 1", ExitUnclassified},
		{"class53 on exit3", "echo 'ERROR:  53100: could not extend file: No space left on device' >&2; exit 3", ExitResource},
		{"class53 on exit2 still resource", "echo 'FATAL:  53300: too many connections' >&2; exit 2", ExitResource},
		{"exit3 with non-53 sqlstate", "echo 'ERROR:  23505: duplicate key' >&2; exit 3", ExitDeterministic},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			fakePsql(t, tc.body)
			_, err := runPsql(repoRootForPsql(t), "select 1")
			if err == nil {
				t.Fatal("fake psql exited non-zero; runPsql must return an error")
			}
			if got := ClassifyUpErr(err); got != tc.want {
				t.Fatalf("exit code %d, want %d (err=%v)", got, tc.want, err)
			}
		})
	}
}
