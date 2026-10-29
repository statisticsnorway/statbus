// Regression tests for STATBUS-429 AC4: the installer accepts an operator's
// certificate up front (PEM pair, or one PFX/PKCS#12 file whose password may
// come from an environment variable) through the SAME code path as
// `./sb cert install`, refuses certificate input in private and development
// modes, and leaves a fresh install configured to serve that certificate.
//
// The command's tail (config regenerate, Caddy restart, TLS probe) needs
// Docker and a network and is therefore out of unit scope; the tests pin the
// shared core (installCustomCertificate) and prove the install step's outcome
// is byte-identical to calling that core directly, which is what
// `./sb cert install` runs before its restart/probe tail.
package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// writeCertStepEnvConfig places the minimal .env.config the Certificate step
// reads: a deployment mode and (for standalone) a site domain.
func writeCertStepEnvConfig(t *testing.T, dir, mode string) {
	t.Helper()
	content := "CADDY_DEPLOYMENT_MODE=" + mode + "\nSITE_DOMAIN=statbus-test.local\n"
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// certStepFixture copies the PEM fixtures into a temp dir so tests never
// depend on the process working directory for INPUT paths.
func certStepFixture(t *testing.T) (certPath, keyPath string) {
	t.Helper()
	dir := t.TempDir()
	certPath = filepath.Join(dir, "test-cert.pem")
	keyPath = filepath.Join(dir, "test-key.pem")
	if err := os.WriteFile(certPath, readFixture(t, pfxFixtureCertPEM), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath, readFixture(t, pfxFixtureKeyPEM), 0o600); err != nil {
		t.Fatal(err)
	}
	return certPath, keyPath
}

// readEnvConfigCertValues returns the two TLS values the step must write.
func readEnvConfigCertValues(t *testing.T, dir string) (cert, key string) {
	t.Helper()
	f, err := dotenv.Load(filepath.Join(dir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	cert, _ = f.Get("TLS_CERT_FILE")
	key, _ = f.Get("TLS_KEY_FILE")
	return cert, key
}

func TestInstallCertEnvInput_PEMPair(t *testing.T) {
	certPath, keyPath := certStepFixture(t)
	t.Setenv("STATBUS_TLS_CERT_FILE", certPath)
	t.Setenv("STATBUS_TLS_KEY_FILE", keyPath)
	args, pfxPassword, present, err := installCertEnvInput()
	if err != nil || !present {
		t.Fatalf("present=%v err=%v", present, err)
	}
	if len(args) != 2 || args[0] != certPath || args[1] != keyPath {
		t.Fatalf("args=%v", args)
	}
	if pfxPassword != nil {
		t.Fatalf("PEM pair must not carry a PFX password, got %q", *pfxPassword)
	}
}

func TestInstallCertEnvInput_PFXPasswordFromEnv(t *testing.T) {
	t.Setenv("STATBUS_TLS_PFX_FILE", "testdata/test-encrypted.pfx")
	t.Setenv("STATBUS_TLS_PFX_PASSWORD", pfxFixturePassword)
	args, pfxPassword, present, err := installCertEnvInput()
	if err != nil || !present {
		t.Fatalf("present=%v err=%v", present, err)
	}
	if len(args) != 1 || args[0] != "testdata/test-encrypted.pfx" {
		t.Fatalf("args=%v", args)
	}
	if pfxPassword == nil || *pfxPassword != pfxFixturePassword {
		t.Fatalf("pfxPassword=%v", pfxPassword)
	}
}

func TestInstallCertEnvInput_None(t *testing.T) {
	_, _, present, err := installCertEnvInput()
	if err != nil || present {
		t.Fatalf("present=%v err=%v", present, err)
	}
}

func TestInstallCertEnvInput_Refusals(t *testing.T) {
	tests := []struct {
		name string
		env  map[string]string
		want string
	}{
		{"cert without key", map[string]string{"STATBUS_TLS_CERT_FILE": "/tmp/x.crt"}, "STATBUS_TLS_KEY_FILE"},
		{"key without cert", map[string]string{"STATBUS_TLS_KEY_FILE": "/tmp/x.key"}, "STATBUS_TLS_CERT_FILE"},
		{"pfx plus pem pair", map[string]string{
			"STATBUS_TLS_PFX_FILE":  "/tmp/x.pfx",
			"STATBUS_TLS_CERT_FILE": "/tmp/x.crt",
			"STATBUS_TLS_KEY_FILE":  "/tmp/x.key",
		}, "one"},
		{"password without pfx", map[string]string{"STATBUS_TLS_PFX_PASSWORD": "x"}, "STATBUS_TLS_PFX_FILE"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			for k, v := range tc.env {
				t.Setenv(k, v)
			}
			_, _, _, err := installCertEnvInput()
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want mention of %s", err, tc.want)
			}
		})
	}
}

// TestInstallCertStep_PEMPair_MatchesCertInstallPath is the core equivalence
// proof: the install step fed a PEM pair through the environment must leave
// EXACTLY the state installCustomCertificate (the ./sb cert install core)
// leaves for the same input — same placed bytes, same container paths in
// .env.config.
func TestInstallCertStep_PEMPair_MatchesCertInstallPath(t *testing.T) {
	certPath, keyPath := certStepFixture(t)

	stepDir := t.TempDir()
	writeCertStepEnvConfig(t, stepDir, "standalone")
	t.Setenv("STATBUS_TLS_CERT_FILE", certPath)
	t.Setenv("STATBUS_TLS_KEY_FILE", keyPath)
	if err := runInstallCertStep(stepDir); err != nil {
		t.Fatalf("runInstallCertStep: %v", err)
	}

	cmdDir := t.TempDir()
	writeCertStepEnvConfig(t, cmdDir, "standalone")
	if _, err := installCustomCertificate(cmdDir, []string{certPath, keyPath}, nil); err != nil {
		t.Fatalf("installCustomCertificate: %v", err)
	}

	stepCert, stepKey := readEnvConfigCertValues(t, stepDir)
	cmdCert, cmdKey := readEnvConfigCertValues(t, cmdDir)
	if stepCert != cmdCert || stepKey != cmdKey {
		t.Fatalf("step wrote %q/%q, cert install core wrote %q/%q", stepCert, stepKey, cmdCert, cmdKey)
	}
	if !strings.HasPrefix(stepCert, customCertContainerDir+"/") || !strings.HasSuffix(stepCert, ".crt") {
		t.Fatalf("TLS_CERT_FILE %q is not a custom-certs container path", stepCert)
	}
	for _, rel := range []string{
		filepath.Join(customCertHostDir, strings.TrimPrefix(stepCert, customCertContainerDir+"/")),
		filepath.Join(customCertHostDir, strings.TrimPrefix(stepKey, customCertContainerDir+"/")),
	} {
		stepBytes, err := os.ReadFile(filepath.Join(stepDir, rel))
		if err != nil {
			t.Fatalf("step did not place %s: %v", rel, err)
		}
		cmdBytes, err := os.ReadFile(filepath.Join(cmdDir, rel))
		if err != nil {
			t.Fatalf("cert install core did not place %s: %v", rel, err)
		}
		if string(stepBytes) != string(cmdBytes) {
			t.Fatalf("%s differs between install step and cert install core", rel)
		}
	}
}

func TestInstallCertStep_PFX_PasswordFromEnv(t *testing.T) {
	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "standalone")
	t.Setenv("STATBUS_TLS_PFX_FILE", "testdata/test-encrypted.pfx")
	t.Setenv("STATBUS_TLS_PFX_PASSWORD", pfxFixturePassword)
	if err := runInstallCertStep(dir); err != nil {
		t.Fatalf("runInstallCertStep: %v", err)
	}
	cert, key := readEnvConfigCertValues(t, dir)
	if cert != customCertContainerDir+"/test-encrypted.crt" || key != customCertContainerDir+"/test-encrypted.key" {
		t.Fatalf("TLS_CERT_FILE/TLS_KEY_FILE = %q/%q", cert, key)
	}
	placed, err := parseLeafCert(filepath.Join(dir, customCertHostDir, "test-encrypted.crt"))
	if err != nil {
		t.Fatalf("placed cert unreadable: %v", err)
	}
	if placed.Subject != pfxFixtureCN {
		t.Fatalf("placed cert subject %q, want %q", placed.Subject, pfxFixtureCN)
	}
}

func TestInstallCertStep_PFX_WrongPassword(t *testing.T) {
	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "standalone")
	t.Setenv("STATBUS_TLS_PFX_FILE", "testdata/test-encrypted.pfx")
	t.Setenv("STATBUS_TLS_PFX_PASSWORD", "WRONG-not-swordfish")
	err := runInstallCertStep(dir)
	// The same decode failure ./sb cert install surfaces for this fixture:
	// the pkcs12 library returns prose ("decryption password incorrect")
	// rather than wrapping ErrDecryption (pinned by
	// TestDecodePFX_EncryptedFixture_WrongPassword).
	if err == nil || !strings.Contains(err.Error(), "password incorrect") {
		t.Fatalf("got %v, want the PFX wrong-password refusal", err)
	}
	// No partial state: no files placed, .env.config untouched.
	if entries, readErr := os.ReadDir(filepath.Join(dir, customCertHostDir)); readErr == nil && len(entries) > 0 {
		t.Fatalf("wrong password left files behind: %v", entries)
	}
	cert, key := readEnvConfigCertValues(t, dir)
	if cert != "" || key != "" {
		t.Fatalf(".env.config mutated on failure: %q/%q", cert, key)
	}
}

func TestInstallCertStep_MissingKeyFile(t *testing.T) {
	certPath, _ := certStepFixture(t)
	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "standalone")
	t.Setenv("STATBUS_TLS_CERT_FILE", certPath)
	t.Setenv("STATBUS_TLS_KEY_FILE", filepath.Join(t.TempDir(), "absent.key"))
	err := runInstallCertStep(dir)
	if err == nil || !strings.Contains(err.Error(), "file not found") {
		t.Fatalf("got %v, want file not found", err)
	}
}

func TestInstallCertStep_RefusedInPrivateMode(t *testing.T) {
	certPath, keyPath := certStepFixture(t)
	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "private")
	t.Setenv("STATBUS_TLS_CERT_FILE", certPath)
	t.Setenv("STATBUS_TLS_KEY_FILE", keyPath)
	err := runInstallCertStep(dir)
	if err == nil ||
		!strings.Contains(err.Error(), "standalone deployment mode") ||
		!strings.Contains(err.Error(), "private") {
		t.Fatalf("got %v, want a plain refusal naming standalone-only and the private mode", err)
	}
	if _, statErr := os.Stat(filepath.Join(dir, customCertHostDir)); !os.IsNotExist(statErr) {
		t.Fatal("refusal must not place certificate files")
	}
}

func TestInstallCertStep_RefusedInDevelopmentMode(t *testing.T) {
	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "development")
	t.Setenv("STATBUS_TLS_PFX_FILE", "testdata/test-encrypted.pfx")
	t.Setenv("STATBUS_TLS_PFX_PASSWORD", pfxFixturePassword)
	err := runInstallCertStep(dir)
	if err == nil ||
		!strings.Contains(err.Error(), "standalone deployment mode") ||
		!strings.Contains(err.Error(), "development") {
		t.Fatalf("got %v, want a plain refusal naming standalone-only and the development mode", err)
	}
}

// TestInstallCertStep_NoInputIsANoOp pins today's behaviour as the default:
// no environment input, no terminal (or --non-interactive) → nothing is
// asked, nothing is written, and the step reports done on the next pass.
func TestInstallCertStep_NoInputIsANoOp(t *testing.T) {
	defer func() func() {
		ni, st := nonInteractive, stdinIsTerminal
		return func() { nonInteractive, stdinIsTerminal = ni, st }
	}()()

	for _, tc := range []struct {
		name           string
		nonInteractive bool
		terminal       bool
	}{
		{"non-interactive", true, true},
		{"no terminal", false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			nonInteractive = tc.nonInteractive
			stdinIsTerminal = func() bool { return tc.terminal }
			dir := t.TempDir()
			writeCertStepEnvConfig(t, dir, "standalone")
			if !checkInstallCertDone(dir) {
				t.Fatal("check must report done when there is no input and nobody to ask")
			}
			if err := runInstallCertStep(dir); err != nil {
				t.Fatalf("runInstallCertStep: %v", err)
			}
			cert, key := readEnvConfigCertValues(t, dir)
			if cert != "" || key != "" {
				t.Fatalf("no-input run wrote TLS_CERT_FILE/TLS_KEY_FILE: %q/%q", cert, key)
			}
		})
	}
}

// TestInstallCertStep_InteractiveDecline: a standalone fresh install on a
// terminal asks, and "no" keeps today's behaviour.
func TestInstallCertStep_InteractiveDecline(t *testing.T) {
	defer func() func() {
		ni, st, qp := nonInteractive, stdinIsTerminal, questionnairePrompt
		return func() { nonInteractive, stdinIsTerminal, questionnairePrompt = ni, st, qp }
	}()()
	nonInteractive = false
	stdinIsTerminal = func() bool { return true }
	questionnairePrompt = func(label, fallback string) string { return fallback }

	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "standalone")
	if checkInstallCertDone(dir) {
		t.Fatal("a standalone fresh install on a terminal must be asked")
	}
	if err := runInstallCertStep(dir); err != nil {
		t.Fatalf("runInstallCertStep: %v", err)
	}
	cert, _ := readEnvConfigCertValues(t, dir)
	if cert != "" {
		t.Fatalf("declined certificate still wrote TLS_CERT_FILE=%q", cert)
	}
}

// TestInstallCertStep_InteractiveAcceptPaths drives the interactive question
// with a PEM pair and asserts the same outcome as the environment path.
func TestInstallCertStep_InteractiveAcceptPaths(t *testing.T) {
	defer func() func() {
		ni, st, qp, yn := nonInteractive, stdinIsTerminal, questionnairePrompt, askCertificateYesNo
		return func() { nonInteractive, stdinIsTerminal, questionnairePrompt, askCertificateYesNo = ni, st, qp, yn }
	}()()
	certPath, keyPath := certStepFixture(t)
	nonInteractive = false
	stdinIsTerminal = func() bool { return true }
	askCertificateYesNo = func(string) bool { return true }
	questionnairePrompt = func(label, fallback string) string {
		switch {
		case strings.Contains(label, "Certificate file"):
			return certPath
		case strings.Contains(label, "Private key file"):
			return keyPath
		}
		return fallback
	}

	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "standalone")
	if err := runInstallCertStep(dir); err != nil {
		t.Fatalf("runInstallCertStep: %v", err)
	}
	cert, key := readEnvConfigCertValues(t, dir)
	if cert != customCertContainerDir+"/test-cert.crt" || key != customCertContainerDir+"/test-cert.key" {
		t.Fatalf("TLS_CERT_FILE/TLS_KEY_FILE = %q/%q", cert, key)
	}
}

// TestInstallCertStep_RefusesConflictingEnvConfig: when .env.config already
// carries certificate paths from another explicit answer (the answer file's
// TLS_CERT_FILE) the installer must not silently prefer one explicit answer
// over another.
func TestInstallCertStep_RefusesConflictingEnvConfig(t *testing.T) {
	certPath, keyPath := certStepFixture(t)
	dir := t.TempDir()
	writeCertStepEnvConfig(t, dir, "standalone")
	f, err := dotenv.Load(filepath.Join(dir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	f.Set("TLS_CERT_FILE", "/data/other/answer-file.crt")
	f.Set("TLS_KEY_FILE", "/data/other/answer-file.key")
	if err := f.Save(); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STATBUS_TLS_CERT_FILE", certPath)
	t.Setenv("STATBUS_TLS_KEY_FILE", keyPath)
	err = runInstallCertStep(dir)
	if err == nil || !strings.Contains(err.Error(), "TLS_CERT_FILE") {
		t.Fatalf("got %v, want a conflict refusal naming TLS_CERT_FILE", err)
	}
}

// TestCertificateStepPosition pins the Certificate step between
// Configuration/Trusted signers and Settings: the certificate must be on
// disk and in .env.config BEFORE Settings generates the Caddy configuration
// that references it and long before Services starts the proxy (AC4).
func TestCertificateStepPosition(t *testing.T) {
	source, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	stepTable := strings.SplitN(string(source), "steps := []step{", 2)
	if len(stepTable) != 2 {
		t.Fatal("step table not found")
	}
	stepTable[1] = strings.SplitN(stepTable[1], "total := len(steps)", 2)[0]
	indexOf := func(name string) int {
		return strings.Index(stepTable[1], `{"`+name+`",`)
	}
	configuration, certificate, settings, services :=
		indexOf("Configuration"), indexOf("Certificate"), indexOf("Settings"), indexOf("Services")
	if certificate < 0 {
		t.Fatal("no Certificate step in the install step table")
	}
	if configuration < 0 || configuration >= certificate || certificate >= settings || settings >= services {
		t.Fatalf("Certificate must sit after Configuration and before Settings/Services (conf=%d cert=%d settings=%d services=%d)",
			configuration, certificate, settings, services)
	}
}
