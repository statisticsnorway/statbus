package upgrade

import (
	"fmt"
	"os"
	"strings"
	"testing"
)

// This guard is local to the same-process 452 fixture, not a subprocess API.
func is452KissAttemptDatabase(db string) bool {
	managedDB := fmt.Sprintf("statbus_livedb_%d", os.Getpid())
	return db == managedDB || strings.HasPrefix(db, "statbus_452kiss_ab_")
}

func Test452KissAttemptDatabase(t *testing.T) {
	managedDB := fmt.Sprintf("statbus_livedb_%d", os.Getpid())
	for _, tc := range []struct {
		name string
		db   string
		want bool
	}{
		{"own-pid", managedDB, true},
		{"reviewer", "statbus_452kiss_ab_review_1006", true},
		{"reviewer-prefix", "statbus_452kiss_ab_", true},
		{"foreign-pid", fmt.Sprintf("statbus_livedb_%d", os.Getpid()+1), false},
		{"managed-suffix", managedDB + "_other", false},
		{"app", "statbus_local", false},
		{"seed", "statbus_seed", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := is452KissAttemptDatabase(tc.db); got != tc.want {
				t.Fatalf("is452KissAttemptDatabase(%q) = %t, want %t", tc.db, got, tc.want)
			}
		})
	}
}
