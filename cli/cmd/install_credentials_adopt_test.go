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

func TestRunLoadJWTRepairsSplitAndReportsAdoption_STATBUS426(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("JWT_SECRET=regenerated-secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	oldRead, oldWrite, oldRegenerated, oldFresh := readStoredJWTSecret, writeJWTSecret, missingCredentialKeysBeforeInstall, freshDatabaseBeforeInstall
	t.Cleanup(func() {
		readStoredJWTSecret, writeJWTSecret, missingCredentialKeysBeforeInstall, freshDatabaseBeforeInstall = oldRead, oldWrite, oldRegenerated, oldFresh
	})
	stored := "surviving-database-secret"
	readStoredJWTSecret = func(string) (string, error) { return stored, nil }
	writeJWTSecret = func(string) error {
		stored = "regenerated-secret"
		return nil
	}
	missingCredentialKeysBeforeInstall = map[string]bool{"JWT_SECRET": true}
	freshDatabaseBeforeInstall = false

	out := captureStdout(t, func() {
		if err := runLoadJWT(dir); err != nil {
			t.Fatalf("runLoadJWT: %v", err)
		}
	})
	if stored != "regenerated-secret" {
		t.Fatalf("stored JWT = %q", stored)
	}
	for _, want := range []string{"JWT signing secret was rotated", ".env.credentials was damaged or incomplete"} {
		if !strings.Contains(out, want) {
			t.Fatalf("output lacks %q:\n%s", want, out)
		}
	}
}

func TestRunLoadJWTReportsAbsentEmptyAndUnreadableRepair_STATBUS426(t *testing.T) {
	for _, tc := range []struct {
		name       string
		initial    string
		initialErr error
		want       string
	}{
		{name: "missing row", want: "missing or empty"},
		{name: "empty value", initial: "", want: "missing or empty"},
		{name: "pre-read failure", initialErr: errors.New("temporary read failure"), want: "could not be read before repair"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("JWT_SECRET=credential-secret\n"), 0600); err != nil {
				t.Fatal(err)
			}
			oldRead, oldWrite, oldRegenerated, oldFresh := readStoredJWTSecret, writeJWTSecret, missingCredentialKeysBeforeInstall, freshDatabaseBeforeInstall
			t.Cleanup(func() {
				readStoredJWTSecret, writeJWTSecret, missingCredentialKeysBeforeInstall, freshDatabaseBeforeInstall = oldRead, oldWrite, oldRegenerated, oldFresh
			})
			stored, reads := tc.initial, 0
			readStoredJWTSecret = func(string) (string, error) {
				reads++
				if reads == 1 && tc.initialErr != nil {
					return "", tc.initialErr
				}
				return stored, nil
			}
			writeJWTSecret = func(string) error { stored = "credential-secret"; return nil }
			missingCredentialKeysBeforeInstall = nil
			freshDatabaseBeforeInstall = false

			out := captureStdout(t, func() {
				if err := runLoadJWT(dir); err != nil {
					t.Fatalf("runLoadJWT: %v", err)
				}
			})
			if !strings.Contains(out, tc.want) {
				t.Fatalf("output lacks %q:\n%s", tc.want, out)
			}
		})
	}
}

func TestRunLoadJWTFreshDatabaseWriteIsNotReportedAsRepair_STATBUS426(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("JWT_SECRET=credential-secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	oldRead, oldWrite, oldFresh := readStoredJWTSecret, writeJWTSecret, freshDatabaseBeforeInstall
	t.Cleanup(func() { readStoredJWTSecret, writeJWTSecret, freshDatabaseBeforeInstall = oldRead, oldWrite, oldFresh })
	stored := ""
	readStoredJWTSecret = func(string) (string, error) { return stored, nil }
	writeJWTSecret = func(string) error { stored = "credential-secret"; return nil }
	freshDatabaseBeforeInstall = true

	out := captureStdout(t, func() {
		if err := runLoadJWT(dir); err != nil {
			t.Fatalf("runLoadJWT: %v", err)
		}
	})
	if out != "" {
		t.Fatalf("fresh database JWT write was reported as a repair:\n%s", out)
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
