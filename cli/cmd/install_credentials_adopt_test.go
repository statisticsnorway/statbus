package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dbroles"
)

func TestCheckJWTDoneComparesCredentialFileSecret_STATBUS426(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("JWT_SECRET=credential-secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	oldRead := readStoredJWTSecret
	t.Cleanup(func() { readStoredJWTSecret = oldRead })

	for _, tc := range []struct {
		name   string
		stored string
		want   bool
	}{
		{name: "match", stored: "credential-secret", want: true},
		{name: "split detected", stored: "surviving-database-secret", want: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			readStoredJWTSecret = func(string) (string, error) { return tc.stored, nil }
			if got := checkJWTDone(dir); got != tc.want {
				t.Fatalf("checkJWTDone = %t, want %t", got, tc.want)
			}
		})
	}
}

// STATBUS-439: the JWT step compares the database's secret with
// .env.credentials. Different: it updates it and says so, because every
// signed-in user is logged out. Same: it does nothing. Unreadable: install
// stops, since a database it cannot read is not one it can install.
func runLoadJWTWith(t *testing.T, stored string, readErr error) (string, string, error) {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("JWT_SECRET=credential-secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	oldRead, oldWrite := readStoredJWTSecret, writeJWTSecret
	t.Cleanup(func() { readStoredJWTSecret, writeJWTSecret = oldRead, oldWrite })
	readStoredJWTSecret = func(string) (string, error) {
		if readErr != nil {
			return "", readErr
		}
		return stored, nil
	}
	writeJWTSecret = func(string) error { stored = "credential-secret"; return nil }
	var runErr error
	out := captureStdout(t, func() { runErr = runLoadJWT(dir) })
	return stored, out, runErr
}

func TestRunLoadJWTUpdatesADifferentSecretAndSaysSo_STATBUS439(t *testing.T) {
	// The orphaned-volume shape: the surviving database holds the old secret,
	// the regenerated .env.credentials a new one. No state flag is consulted.
	stored, out, err := runLoadJWTWith(t, "surviving-database-secret", nil)
	if err != nil {
		t.Fatalf("runLoadJWT: %v", err)
	}
	if stored != "credential-secret" {
		t.Fatalf("stored JWT = %q, want credential-secret", stored)
	}
	if want := "  The JWT signing secret in the database differed from .env.credentials and was updated; users who were signed in must sign in again.\n"; out != want {
		t.Fatalf("output = %q, want %q", out, want)
	}
}

func TestRunLoadJWTWritesAFirstSecretQuietly_STATBUS439(t *testing.T) {
	stored, out, err := runLoadJWTWith(t, "", nil)
	if err != nil || stored != "credential-secret" || out != "" {
		t.Fatalf("first write: stored=%q out=%q err=%v, want credential-secret, no output, no error", stored, out, err)
	}
}

func TestRunLoadJWTStopsWhenTheDatabaseCannotBeRead_STATBUS439(t *testing.T) {
	_, _, err := runLoadJWTWith(t, "", errors.New("connection refused"))
	if err == nil || !strings.Contains(err.Error(), "connection refused") {
		t.Fatalf("unreadable database: err = %v, want the read error", err)
	}
}

func TestPasswordReconciliationAttributionIsRoleSpecific_STATBUS426(t *testing.T) {
	changed := []dbroles.Mismatch{
		{Role: "admin", PasswordKey: "POSTGRES_ADMIN_PASSWORD", Reason: "differs"},
		{Role: "app", PasswordKey: "POSTGRES_APP_PASSWORD", Reason: "differs"},
	}
	adopted, drifted := partitionPasswordReconciliation(changed, map[string]bool{"POSTGRES_APP_PASSWORD": true})
	if got := dbroles.RoleNames(adopted); got != "app" {
		t.Fatalf("adopted roles = %q, want app", got)
	}
	if got := dbroles.RoleNames(drifted); got != "admin" {
		t.Fatalf("ordinary drift roles = %q, want admin", got)
	}
}
