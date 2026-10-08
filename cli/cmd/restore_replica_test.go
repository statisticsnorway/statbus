package cmd

import "testing"

// The replica-role conninfo is what lets a dump restore through a transient
// ACL state (STATBUS-481); the behavioural proof is the seed build's round
// trip (verifySeedRoundTrip). This test pins only the libpq conninfo grammar:
// the option must reach the server, and a database name must stay one value.
func TestRestoreTargetConninfo(t *testing.T) {
	cases := map[string]string{
		"statbus_seed": `dbname='statbus_seed' options='-c session_replication_role=replica'`,
		`o'brien\x`:    `dbname='o\'brien\\x' options='-c session_replication_role=replica'`,
	}
	for in, want := range cases {
		if got := restoreTargetConninfo(in); got != want {
			t.Errorf("restoreTargetConninfo(%q) = %q, want %q", in, got, want)
		}
	}
}
