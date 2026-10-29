package cmd

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"io"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	pkcs12 "software.sslmate.com/src/go-pkcs12"
)

func testCertificate(t *testing.T, cn string, dns []string, notBefore, notAfter time.Time) (*x509.Certificate, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber:          big.NewInt(notBefore.UnixNano()),
		Subject:               pkix.Name{CommonName: cn},
		DNSNames:              dns,
		NotBefore:             notBefore,
		NotAfter:              notAfter,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	return cert, key
}

func certPEM(t *testing.T, cert *x509.Certificate) []byte {
	t.Helper()
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
}

func keyPEM(t *testing.T, key *ecdsa.PrivateKey) []byte {
	t.Helper()
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
}

func writePFX(t *testing.T, path string, cert *x509.Certificate, key *ecdsa.PrivateKey, password string) {
	t.Helper()
	data, err := pkcs12.Modern.Encode(key, cert, nil, password)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestScanCertificateFolderListsAndRanksCandidates(t *testing.T) {
	dir := t.TempDir()
	validFrom := time.Now().Add(-24 * time.Hour)
	validTo := time.Now().Add(365 * 24 * time.Hour)
	expiredFrom := time.Now().Add(-48 * time.Hour)
	expiredTo := time.Now().Add(-24 * time.Hour)

	wildcard, wildcardKey := testCertificate(t, "*.ubos.org", []string{"*.ubos.org"}, validFrom, validTo)
	expired, expiredKey := testCertificate(t, "*.ubos.org", []string{"*.ubos.org"}, expiredFrom, expiredTo)
	other, otherKey := testCertificate(t, "other.example", []string{"other.example"}, validFrom, validTo)
	certOnly, _ := testCertificate(t, "lonely.example", []string{"lonely.example"}, validFrom, validTo)

	// The good pair is split across two PEM files, as a CA folder often ships it.
	if err := os.WriteFile(filepath.Join(dir, "wildcard-valid.pem"), certPEM(t, wildcard), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "wildcard-valid.key"), keyPEM(t, wildcardKey), 0o600); err != nil {
		t.Fatal(err)
	}
	writePFX(t, filepath.Join(dir, "expired.pfx"), expired, expiredKey, "RightPass")
	writePFX(t, filepath.Join(dir, "other.pfx"), other, otherKey, "RightPass")
	writePFX(t, filepath.Join(dir, "wrong.pfx"), other, otherKey, "WrongPass")
	if err := os.WriteFile(filepath.Join(dir, "cert-only.pem"), certPEM(t, certOnly), 0o600); err != nil {
		t.Fatal(err)
	}

	pw := "RightPass"
	choices, notes, err := scanCertificateFolder(dir, "statbus.ubos.org", &pw)
	if err != nil {
		t.Fatal(err)
	}
	if len(choices) != 3 {
		t.Fatalf("choices = %d, want 3: %+v notes=%v", len(choices), choices, notes)
	}
	first := choices[0]
	if !first.Covers || first.Expired || first.NotYetValid {
		t.Errorf("default is not the covering, valid candidate: %+v", first)
	}
	if strings.Join(first.Args, " ") != filepath.Join(dir, "wildcard-valid.pem")+" "+filepath.Join(dir, "wildcard-valid.key") {
		t.Errorf("PEM cert and key were not paired: %v", first.Args)
	}
	var sawExpired, sawOther bool
	for _, choice := range choices[1:] {
		if filepath.Base(choice.Args[0]) == "expired.pfx" {
			sawExpired = choice.Expired && choice.Covers
		}
		if filepath.Base(choice.Args[0]) == "other.pfx" {
			sawOther = !choice.Covers && !choice.Expired
		}
	}
	if !sawExpired || !sawOther {
		t.Errorf("expired/non-matching PFX candidates missing or mislabelled: %+v", choices)
	}
	joined := strings.Join(notes, "\n")
	if !strings.Contains(joined, "wrong.pfx: could not open with that password") {
		t.Errorf("wrong-password PFX is not labelled: %v", notes)
	}
	if !strings.Contains(joined, "cert-only.pem: certificate only, no matching private key found") {
		t.Errorf("certificate without a key is not labelled: %v", notes)
	}

	text := strings.Join(renderCertificateChoices(choices, notes, "statbus.ubos.org"), "\n")
	for _, want := range []string{"[default]", "does not cover statbus.ubos.org", "EXPIRED", "could not open with that password"} {
		if !strings.Contains(text, want) {
			t.Errorf("rendered list missing %q:\n%s", want, text)
		}
	}
	if strings.Contains(text, "RightPass") || strings.Contains(text, "WrongPass") {
		t.Errorf("a PFX password leaked into the candidate list:\n%s", text)
	}
}

func TestRankCertificateChoicesPrefersLatestCoveringCertificate(t *testing.T) {
	from := time.Now().Add(-time.Hour)
	early, _ := testCertificate(t, "statbus.ubos.org", []string{"statbus.ubos.org"}, from, time.Now().Add(10*24*time.Hour))
	late, _ := testCertificate(t, "statbus.ubos.org", []string{"statbus.ubos.org"}, from, time.Now().Add(300*24*time.Hour))
	other, _ := testCertificate(t, "other.example", []string{"other.example"}, from, time.Now().Add(400*24*time.Hour))
	choices := []certChoice{
		{Args: []string{"early.pem"}, Leaf: early},
		{Args: []string{"other.pem"}, Leaf: other},
		{Args: []string{"late.pem"}, Leaf: late},
	}
	rankCertificateChoices(choices, "statbus.ubos.org")
	if choices[0].Args[0] != "late.pem" {
		t.Fatalf("default = %v, want late.pem", choices[0].Args)
	}
	if choices[1].Args[0] != "early.pem" {
		t.Fatalf("second = %v, want early.pem", choices[1].Args)
	}
}

func TestResolveInstallPath(t *testing.T) {
	caller := t.TempDir()
	home := t.TempDir()
	t.Setenv("STATBUS_INSTALL_CALLER_PWD", caller)
	t.Setenv("HOME", home)

	if got, want := resolveInstallPath("/etc/ssl/cert.pem"), "/etc/ssl/cert.pem"; got != want {
		t.Errorf("absolute = %q, want %q", got, want)
	}
	if got, want := resolveInstallPath("~/certs/leaf.pem"), filepath.Join(home, "certs/leaf.pem"); got != want {
		t.Errorf("tilde = %q, want %q", got, want)
	}
	if got, want := resolveInstallPath("certs/leaf.pem"), filepath.Join(caller, "certs/leaf.pem"); got != want {
		t.Errorf("relative = %q, want %q", got, want)
	}
	missing, _, _, err := inspectCertificatePath("certs/missing.pem")
	if err == nil || !strings.Contains(err.Error(), filepath.Join(caller, "certs/missing.pem")) {
		t.Errorf("missing path error = %v, want the resolved absolute path", err)
	}
	if missing != filepath.Join(caller, "certs/missing.pem") {
		t.Errorf("resolved missing path = %q", missing)
	}
}

func TestCertificateFileNeedsKeyByContent(t *testing.T) {
	dir := t.TempDir()
	from := time.Now().Add(-time.Hour)
	cert, key := testCertificate(t, "statbus.ubos.org", []string{"statbus.ubos.org"}, from, time.Now().Add(24*time.Hour))

	pfx := filepath.Join(dir, "cert.pfx")
	writePFX(t, pfx, cert, key, "pw")
	if needs, err := certificateFileNeedsKey(pfx); err != nil || needs {
		t.Errorf("PFX needsKey = %v, err = %v; want false", needs, err)
	}

	bundle := filepath.Join(dir, "bundle.pem")
	if err := os.WriteFile(bundle, append(certPEM(t, cert), keyPEM(t, key)...), 0o600); err != nil {
		t.Fatal(err)
	}
	if needs, err := certificateFileNeedsKey(bundle); err != nil || needs {
		t.Errorf("PEM bundle needsKey = %v, err = %v; want false", needs, err)
	}

	certOnly := filepath.Join(dir, "cert.pem")
	if err := os.WriteFile(certOnly, certPEM(t, cert), 0o600); err != nil {
		t.Fatal(err)
	}
	if needs, err := certificateFileNeedsKey(certOnly); err != nil || !needs {
		t.Errorf("PEM certificate needsKey = %v, err = %v; want true", needs, err)
	}
}

func TestAskCertYesNoUsesInstallerShape(t *testing.T) {
	t.Setenv("STATBUS_INSTALL_PROMPTS_TO_TTY", "1")
	for _, tc := range []struct {
		answer string
		want   bool
	}{{"y\n", true}, {"yes\n", true}, {"no\n", false}, {"\n", false}} {
		stdinR, stdinW, err := os.Pipe()
		if err != nil {
			t.Fatal(err)
		}
		oldStdin := os.Stdin
		os.Stdin = stdinR
		stdoutR, stdoutW, err := os.Pipe()
		if err != nil {
			t.Fatal(err)
		}
		oldStdout := os.Stdout
		os.Stdout = stdoutW
		if _, err := stdinW.WriteString(tc.answer); err != nil {
			t.Fatal(err)
		}
		_ = stdinW.Close()
		got := askCertYesNo("  Do you have a certificate to install now?")
		_ = stdoutW.Close()
		os.Stdin = oldStdin
		os.Stdout = oldStdout
		captured, _ := io.ReadAll(stdoutR)
		if got != tc.want {
			t.Errorf("answer %q = %v, want %v", tc.answer, got, tc.want)
		}
		if !strings.Contains(string(captured), "Do you have a certificate to install now? [y/N]:") {
			t.Errorf("prompt for %q does not use the installer shape: %q", tc.answer, captured)
		}
	}
}
