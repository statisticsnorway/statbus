// install_cert_folder_choice_test.go: what the folder chooser asks once it has
// content-checked a folder. One usable certificate is a confirmation, not a
// numbered list (STATBUS-422).
package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// folderChoiceFixture writes one PEM certificate+key bundle into a fresh
// folder and returns the folder and bundle paths.
func folderChoiceFixture(t *testing.T, cn string, notAfter time.Time) (folder, bundle string) {
	t.Helper()
	folder = t.TempDir()
	cert, key := testCertificate(t, cn, []string{cn}, time.Now().Add(-time.Hour), notAfter)
	bundle = filepath.Join(folder, cn+".pem")
	if err := os.WriteFile(bundle, append(certPEM(t, cert), keyPEM(t, key)...), 0o600); err != nil {
		t.Fatal(err)
	}
	return folder, bundle
}

func stubCertificateDefaultYes(t *testing.T, answer bool) *string {
	t.Helper()
	saved := askCertificateDefaultYes
	var asked string
	askCertificateDefaultYes = func(label string) bool {
		asked = label
		return answer
	}
	t.Cleanup(func() { askCertificateDefaultYes = saved })
	return &asked
}

func TestCertificateFolderSingleChoiceAsksConfirmation(t *testing.T) {
	folder, bundle := folderChoiceFixture(t, "statbus.example.org", time.Now().Add(365*24*time.Hour))
	asked := stubCertificateDefaultYes(t, true)

	var args []string
	out := pickerCapture(t, func() { args, _ = chooseCertificateFromFolder(folder, t.TempDir()) })

	if len(args) != 1 || args[0] != bundle {
		t.Fatalf("confirmation produced %q, want [%q]", args, bundle)
	}
	if *asked != "  Install this certificate?" {
		t.Fatalf("question = %q, want the single-certificate confirmation", *asked)
	}
	for _, want := range []string{bundle, "CN=statbus.example.org", "SANs: statbus.example.org", "expires ", "SITE_DOMAIN not set"} {
		if !strings.Contains(out, want) {
			t.Fatalf("certificate line is missing %q:\n%s", want, out)
		}
	}
	for _, unwanted := range []string{"1) ", "Install which certificate number"} {
		if strings.Contains(out, unwanted) {
			t.Fatalf("a single certificate must not be a numbered choice (%q):\n%s", unwanted, out)
		}
	}
}

func TestCertificateFolderSingleChoiceDeclinedContinuesWithoutCertificate(t *testing.T) {
	folder, _ := folderChoiceFixture(t, "statbus.example.org", time.Now().Add(365*24*time.Hour))
	stubCertificateDefaultYes(t, false)

	var args []string
	out := pickerCapture(t, func() { args, _ = chooseCertificateFromFolder(folder, t.TempDir()) })

	if args != nil {
		t.Fatalf("declining produced %q, want no certificate", args)
	}
	if !strings.Contains(out, "Continuing with automatic certificates. Install your own later with: ./sb cert install") {
		t.Fatalf("declining did not say what happens next:\n%s", out)
	}
}

func TestCertificateFolderTwoChoicesKeepNumberedList(t *testing.T) {
	first, firstBundle := folderChoiceFixture(t, "first.example.org", time.Now().Add(30*24*time.Hour))
	if err := os.Rename(firstBundle, filepath.Join(first, "1.pem")); err != nil {
		t.Fatal(err)
	}
	secondCert, secondKey := testCertificate(t, "second.example.org", []string{"second.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(365*24*time.Hour))
	if err := os.WriteFile(filepath.Join(first, "2.pem"), append(certPEM(t, secondCert), keyPEM(t, secondKey)...), 0o600); err != nil {
		t.Fatal(err)
	}
	stubCertificateDefaultYes(t, true)

	var asked string
	savedPrompt := questionnairePrompt
	questionnairePrompt = func(label, fallback string) string {
		if !strings.Contains(label, "Install which certificate number") {
			t.Fatalf("unexpected prompt %q", label)
		}
		asked = label
		return "1"
	}
	t.Cleanup(func() { questionnairePrompt = savedPrompt })

	var args []string
	out := pickerCapture(t, func() { args, _ = chooseCertificateFromFolder(first, t.TempDir()) })

	for _, want := range []string{"1) ", "2) "} {
		if !strings.Contains(out, want) {
			t.Fatalf("numbered list is missing %q:\n%s", want, out)
		}
	}
	if asked != "  Install which certificate number" {
		t.Fatalf("question = %q, want the numbered choice", asked)
	}
	if strings.Contains(out, "Install this certificate?") {
		t.Fatalf("two candidates must not use the single-certificate confirmation:\n%s", out)
	}
	// The later expiry ranks first, so choice 1 is 2.pem.
	if len(args) != 1 || args[0] != filepath.Join(first, "2.pem") {
		t.Fatalf("choosing 1 produced %q, want [%q]", args, filepath.Join(first, "2.pem"))
	}
}
