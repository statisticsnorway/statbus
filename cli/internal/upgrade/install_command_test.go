package upgrade

import (
	"reflect"
	"testing"
)

// A parked upgrade tells the operator the whole resume flow: a recovery psql
// session to fix the database, then ./sb install, both runnable from any
// directory.
func TestParkedResumeGuidanceNamesTheResumeFlow(t *testing.T) {
	got := ParkedResumeGuidance("/home/statbus/statbus")
	want := []string{
		"To fix it in the database: cd /home/statbus/statbus && STATBUS_PSQL=recovery ./sb psql (a session that can write; everyone else stays read-only).",
		"Then resume with one fresh attempt: cd /home/statbus/statbus && ./sb install",
		"A newer release replaces this upgrade without a resume.",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ParkedResumeGuidance =\n%q\nwant\n%q", got, want)
	}
}
