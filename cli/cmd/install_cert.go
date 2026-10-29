// install_cert.go: the installer's Certificate step (STATBUS-429 AC4).
//
// An operator can hand their real certificate to the installer instead of
// installing first and repairing with `./sb cert install` afterwards. Both
// routes run the SAME code path: this step only collects the input
// (environment variables for unattended installs, a question on a terminal)
// and then calls installCustomCertificate, the exact core
// `./sb cert install` runs before its restart/probe tail. Parsing, PFX
// support, password handling, file placement under caddy/data/custom-certs/
// and the TLS_CERT_FILE/TLS_KEY_FILE write into .env.config are therefore
// identical by construction, and the hostrepair path inside
// writeCertAndKey covers a root-owned caddy/data on rerun installs.
//
// The step sits after Configuration (.env.config exists) and before
// Settings/Services: the certificate is on disk and .env.config carries the
// container paths BEFORE config generation renders the Caddy templates that
// reference them (and validateTLSPaths stat()s them) and before the proxy
// is ever started, so a fresh install is born serving the certificate.
//
// Inputs (host paths; .env.config's TLS_CERT_FILE/TLS_KEY_FILE remain the
// CONTAINER paths they always were):
//
//	STATBUS_TLS_CERT_FILE + STATBUS_TLS_KEY_FILE   a PEM fullchain + key pair
//	STATBUS_TLS_PFX_FILE                           one PFX/PKCS#12 file
//	STATBUS_TLS_PFX_PASSWORD                       its password (else prompted on a TTY)
//
// Certificate input is standalone-only: private and development modes are
// refused with the same plain reason `./sb cert install` gives.
package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// The certificate input variables, named like the existing
// STATBUS_ENV_CONFIG / STATBUS_USERS_FILE inputs and forwarded by
// install.sh exactly as those are.
const (
	envTLSCertFile    = "STATBUS_TLS_CERT_FILE"
	envTLSKeyFile     = "STATBUS_TLS_KEY_FILE"
	envTLSPFXFile     = "STATBUS_TLS_PFX_FILE"
	envTLSPFXPassword = "STATBUS_TLS_PFX_PASSWORD"
)

// installCertEnvInput collects the unattended certificate input. present is
// false when no variable is set at all (today's behaviour: no certificate).
// A set-but-invalid combination is a refusal, never a silent pick between
// two explicit answers.
func installCertEnvInput() (args []string, pfxPassword *string, present bool, err error) {
	cert := os.Getenv(envTLSCertFile)
	key := os.Getenv(envTLSKeyFile)
	pfx := os.Getenv(envTLSPFXFile)
	password := os.Getenv(envTLSPFXPassword)

	if pfx != "" && (cert != "" || key != "") {
		return nil, nil, false, fmt.Errorf("supply the certificate one way, not two: either %s (a single PFX/PKCS#12 file) or the %s/%s pair", envTLSPFXFile, envTLSCertFile, envTLSKeyFile)
	}
	if cert != "" && key == "" {
		return nil, nil, false, fmt.Errorf("%s is set but %s is not — a PEM certificate needs its private key file in %s", envTLSCertFile, envTLSKeyFile, envTLSKeyFile)
	}
	if key != "" && cert == "" {
		return nil, nil, false, fmt.Errorf("%s is set but %s is not — a PEM private key needs its certificate file in %s", envTLSKeyFile, envTLSCertFile, envTLSCertFile)
	}
	if password != "" && pfx == "" {
		return nil, nil, false, fmt.Errorf("%s is set but %s is not — the password belongs to a PFX/PKCS#12 file named by %s", envTLSPFXPassword, envTLSPFXFile, envTLSPFXFile)
	}

	switch {
	case pfx != "":
		if password != "" {
			pfxPassword = &password
		}
		return []string{pfx}, pfxPassword, true, nil
	case cert != "":
		return []string{cert, key}, nil, true, nil
	}
	return nil, nil, false, nil
}

// installCertShouldAsk reports whether this run may ask the operator about
// a certificate: an interactive terminal on a standalone configuration that
// has no certificate yet. Private and development installs are never asked;
// unattended runs are never asked.
func installCertShouldAsk(dir string) bool {
	if nonInteractive || !stdinIsTerminal() {
		return false
	}
	mode, _, tlsCert, _, err := readModeAndCertEnv(dir)
	if err != nil {
		return false
	}
	return mode == "standalone" && tlsCert == ""
}

// checkInstallCertDone: explicit input (even an invalid combination) must be
// CONSUMED or refused by the runner, so it reports not-done; an interactive
// standalone install without a certificate asks once per run.
func checkInstallCertDone(dir string) bool {
	if _, _, present, err := installCertEnvInput(); present || err != nil {
		return false
	}
	return !installCertShouldAsk(dir)
}

// runInstallCertStep feeds the operator's certificate into
// installCustomCertificate, the ./sb cert install core. Without input it is
// a no-op beyond the one optional question.
func runInstallCertStep(dir string) error {
	args, pfxPassword, present, err := installCertEnvInput()
	if err != nil {
		return err
	}
	if !present {
		if !installCertShouldAsk(dir) {
			return nil
		}
		args, pfxPassword = askInstallCert(dir)
		if args == nil {
			return nil
		}
	}

	// A PFX password that was not supplied can only be asked for on a
	// terminal; unattended runs must name the variable instead of dying
	// inside a password read on a closed stdin.
	if pfxPassword == nil && !stdinIsTerminal() {
		if data, readErr := os.ReadFile(args[0]); readErr == nil && looksLikeDER(data) && len(args) == 1 {
			return fmt.Errorf("%s is password-protected and no terminal is available to ask. "+
				"Set %s to the PFX password, then run the same install command again", envTLSPFXFile, envTLSPFXPassword)
		}
	}

	// Never silently prefer one explicit answer over another: certificate
	// paths already in .env.config that this step (or ./sb cert install) did
	// not itself place there conflict with the environment input.
	if present {
		if err := refuseConflictingCertConfig(dir); err != nil {
			return err
		}
	}

	if _, err := installCustomCertificate(dir, args, pfxPassword); err != nil {
		return err
	}
	return nil
}

// refuseConflictingCertConfig refuses when .env.config already names
// certificate paths outside the custom-certs directory this code path owns
// (e.g. TLS_CERT_FILE supplied through the answer file too). Paths already
// under /data/custom-certs/ were written by this same code path — a rerun
// or a prior ./sb cert install — and are overwritten idempotently.
func refuseConflictingCertConfig(dir string) error {
	_, _, tlsCert, tlsKey, err := readModeAndCertEnv(dir)
	if err != nil {
		return err
	}
	owns := func(p string) bool { return strings.HasPrefix(p, customCertContainerDir+"/") }
	if tlsCert == "" && tlsKey == "" {
		return nil
	}
	if owns(tlsCert) && owns(tlsKey) {
		return nil
	}
	return fmt.Errorf(".env.config already has TLS_CERT_FILE=%q/TLS_KEY_FILE=%q, and the %s/%s environment input also supplies a certificate. "+
		"Supply the certificate once: either remove the TLS_CERT_FILE/TLS_KEY_FILE lines from the configuration, or unset the STATBUS_TLS_* variables",
		tlsCert, tlsKey, envTLSCertFile, envTLSPFXFile)
}

// certNotice prints one operator-facing line both to ordinary stdout (direct
// ./sb use) and, when install.sh captures output, through the marked prompt
// stream that ops/install-terminal-output.awk keeps. Without the marker the
// explanation would be filtered out and the operator would see only the final
// question.
func certNotice(format string, args ...any) {
	message := fmt.Sprintf(format, args...)
	fmt.Println(message)
	installTTYPrompt("%s", message)
}

// askCertYesNo uses the installer's [y/N] shape rather than the generic
// questionnaire's [no] suffix. y/yes is accepted; anything else is no.
func askCertYesNo(label string) bool {
	fmt.Printf("%s [y/N]: ", label)
	installTTYPrompt("%s [y/N]: ", label)
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	answer := strings.TrimSpace(line)
	return strings.EqualFold(answer, "y") || strings.EqualFold(answer, "yes")
}

// askCertificateYesNo is the seam existing interactive-certificate tests use to
// answer the yes/no question without a terminal.
var askCertificateYesNo = askCertYesNo

// certificateExplanation is the fixed text shown before the certificate
// question. Kept as data so the terminal-filter test proves every line
// survives install.sh's tee|awk pipeline.
var certificateExplanation = []string{
	"  A standalone StatBus can serve your own TLS certificate (from your CA, as a",
	"  PFX/PKCS#12 file or a PEM certificate + key pair) instead of an automatic",
	"  Let's Encrypt certificate.",
}

// askInstallCert is the interactive certificate question: optional, default
// keeps today's behaviour. A file path behaves as before. A folder is scanned
// by content, listed with its usable certificates, and the chosen files then
// flow through installCustomCertificate. Returns nil when the operator
// declines or has nothing to give.
func askInstallCert(dir string) ([]string, *string) {
	fmt.Println()
	for _, line := range certificateExplanation {
		certNotice("%s", line)
	}
	if !askCertificateYesNo("  Do you have a certificate to install now?") {
		certNotice("  Continuing with automatic certificates. Install your own later with: ./sb cert install")
		return nil, nil
	}
	certNotice("  Paths may be absolute, start with ~/, or be relative to the directory you ran the installer from.")
	certPath := questionnairePrompt("  Certificate file or folder (a PFX/PKCS#12 file, a PEM fullchain, or a folder to inspect)", "")
	if certPath == "" {
		certNotice("  No certificate file given; continuing without one. Install it later with: ./sb cert install")
		return nil, nil
	}
	resolved, isDir, needsKey, err := inspectCertificatePath(certPath)
	if err != nil {
		certNotice("  %s", err)
		return nil, nil
	}
	if isDir {
		return chooseCertificateFromFolder(resolved, dir)
	}
	if !needsKey {
		return []string{resolved}, nil
	}
	keyPath := questionnairePrompt("  Private key file (only for a PEM fullchain; leave empty for a PFX file)", "")
	if keyPath == "" {
		certNotice("  A PEM certificate needs its private key; continuing without a custom certificate.")
		return nil, nil
	}
	resolvedKey := resolveInstallPath(keyPath)
	if _, statErr := os.Stat(resolvedKey); statErr != nil {
		certNotice("  File not found: %s", resolvedKey)
		return nil, nil
	}
	return []string{resolved, resolvedKey}, nil
}

// chooseCertificateFromFolder asks once for the PFX password when the folder
// contains PFX files, then presents the content-detected candidates. The
// password stays in memory only: it is never printed, logged, or persisted.
func chooseCertificateFromFolder(folder, dir string) ([]string, *string) {
	_, siteDomain, _, _, err := readModeAndCertEnv(dir)
	if err != nil {
		siteDomain = ""
	}
	_, hasPFX, err := certFolderFiles(folder)
	if err != nil {
		certNotice("  Could not read folder %s: %v", folder, err)
		return nil, nil
	}
	var pfxPassword *string
	if hasPFX {
		certNotice("  The folder contains PFX/PKCS#12 files. Their password is only used to read them and is not stored.")
		certNotice("  PFX password (typing is hidden; leave empty if none):")
		password, readErr := readPassword("")
		if readErr == nil {
			pfxPassword = &password
		}
	}
	choices, notes, err := scanCertificateFolder(folder, siteDomain, pfxPassword)
	if err != nil {
		certNotice("  Could not inspect folder %s: %v", folder, err)
		return nil, nil
	}
	if len(choices) == 0 {
		for _, note := range notes {
			certNotice("  - %s", note)
		}
		certNotice("  No usable certificate with a matching private key was found in %s.", folder)
		return nil, nil
	}
	for _, line := range renderCertificateChoices(choices, notes, siteDomain) {
		certNotice("%s", line)
	}
	answer := questionnairePrompt("  Install which certificate number", "1")
	number, convErr := strconv.Atoi(strings.TrimSpace(answer))
	if convErr != nil || number < 1 || number > len(choices) {
		certNotice("  That is not one of the listed numbers; continuing without a custom certificate.")
		return nil, nil
	}
	return choices[number-1].Args, pfxPassword
}
