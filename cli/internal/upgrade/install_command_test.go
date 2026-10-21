package upgrade

import (
	"reflect"
	"testing"
)

// A parked upgrade tells the operator the whole resume flow: open their own
// psql session for writing, fix, then resume with ./sb install, both runnable
// from any directory.
func TestParkedResumeGuidanceNamesTheResumeFlow(t *testing.T) {
	got := ParkedResumeGuidance("/home/statbus/statbus")
	want := []string{
		"To fix it in the database: run cd /home/statbus/statbus && ./sb psql, then SET default_transaction_read_only = off; in that session before writing.",
		"Then resume with one fresh attempt: cd /home/statbus/statbus && ./sb install",
		"A newer release replaces this upgrade without a resume.",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ParkedResumeGuidance =\n%q\nwant\n%q", got, want)
	}
}
