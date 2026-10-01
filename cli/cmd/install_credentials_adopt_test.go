package cmd

import (
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
	oldRead, oldWrite, oldRegenerated := readStoredJWTSecret, writeJWTSecret, missingCredentialKeysBeforeInstall
	t.Cleanup(func() {
		readStoredJWTSecret, writeJWTSecret, missingCredentialKeysBeforeInstall = oldRead, oldWrite, oldRegenerated
	})
	stored := "surviving-database-secret"
	readStoredJWTSecret = func(string) (string, error) { return stored, nil }
	writeJWTSecret = func(string) error {
		stored = "regenerated-secret"
		return nil
	}
	missingCredentialKeysBeforeInstall = map[string]bool{"JWT_SECRET": true}

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

func TestPasswordReconciliationAdoptionTrigger_STATBUS426(t *testing.T) {
	changed := []dbroles.Mismatch{{Role: "authenticator", Reason: "differs"}}
	if !passwordReconciliationWasCredentialAdoption(changed, map[string]bool{"POSTGRES_AUTHENTICATOR_PASSWORD": true}) {
		t.Fatal("regenerated password plus a changed surviving role must trigger adoption reporting")
	}
	if passwordReconciliationWasCredentialAdoption(nil, map[string]bool{"POSTGRES_AUTHENTICATOR_PASSWORD": true}) {
		t.Fatal("fresh-install generation with no surviving role change is not adoption")
	}
	if passwordReconciliationWasCredentialAdoption(changed, nil) {
		t.Fatal("an ordinary manually changed password is reconciliation, not damaged-file adoption")
	}
}
