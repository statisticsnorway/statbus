package cmd

import (
	"fmt"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
)

// TestPgxIdentifier_Sanitize pins the identifier-quoting integration we
// rely on at db.go:543-544 (drop/create database in restore) and
// db.go:747-748 (same SQL inside the remote heredoc). The handlers use
// pgx.Identifier{name}.Sanitize() expecting:
//   - the value to be wrapped in double quotes,
//   - any embedded `"` to be doubled,
//   - the result to be a single-token, ready-to-paste-into-SQL string.
//
// This is testing pgx upstream as much as it's testing us, but it pins
// the contract so a future SDK swap can't silently regress it.
func TestPgxIdentifier_Sanitize(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain ascii", "statbus_local", `"statbus_local"`},
		{"hyphenated", "weird-db", `"weird-db"`},
		{"embedded quote", `weird"db`, `"weird""db"`},
		{"unicode", "статбус", `"статбус"`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := pgx.Identifier{c.in}.Sanitize()
			if got != c.want {
				t.Errorf("pgx.Identifier{%q}.Sanitize() = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

// TestDropCreateSQLShape reproduces the SQL string-formation we do at
// db.go:543-544: pre-sanitize the identifier with pgx, then format
// `DROP DATABASE IF EXISTS %s;` / `CREATE DATABASE %s;`. Confirms the
// sanitized value substitutes in cleanly without re-quoting.
func TestDropCreateSQLShape(t *testing.T) {
	for _, in := range []string{"statbus_local", `weird"db`} {
		q := pgx.Identifier{in}.Sanitize()
		drop := fmt.Sprintf(`DROP DATABASE IF EXISTS %s;`, q)
		create := fmt.Sprintf(`CREATE DATABASE %s;`, q)

		if !strings.HasPrefix(drop, `DROP DATABASE IF EXISTS "`) || !strings.HasSuffix(drop, `";`) {
			t.Errorf("DROP for %q: %q lacks expected wrapping", in, drop)
		}
		if !strings.HasPrefix(create, `CREATE DATABASE "`) || !strings.HasSuffix(create, `";`) {
			t.Errorf("CREATE for %q: %q lacks expected wrapping", in, create)
		}
		// Embedded quote case must produce doubled quotes inside the SQL.
		if in == `weird"db` && !strings.Contains(drop, `"weird""db"`) {
			t.Errorf("DROP for %q does not contain doubled-quote form: %q", in, drop)
		}
	}
}
