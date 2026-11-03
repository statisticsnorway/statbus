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
	return askCertQuestion(label, "[y/N]")
}

// askCertDefaultYesNo is askCertYesNo with the default reversed, for a
// confirmation whose suggested answer is yes: Enter, y and yes all accept.
func askCertDefaultYesNo(label string) bool {
	return askCertQuestion(label, "[Y/n]")
}

func askCertQuestion(label, shape string) bool {
	fmt.Printf("%s %s: ", label, shape)
	installTTYPromptAnswer("%s %s: ", label, shape)
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	answer := strings.ToLower(strings.TrimSpace(line))
	if shape == "[Y/n]" && answer == "" {
		return true
	}
	return answer == "y" || answer == "yes"
}

// askCertificateYesNo is the seam existing interactive-certificate tests use to
// answer the yes/no question without a terminal.
var askCertificateYesNo = askCertYesNo

// askCertificateDefaultYes is the seam for confirming the only usable
// certificate found in a folder.
var askCertificateDefaultYes = askCertDefaultYesNo

// chooseCertFolder is the seam the picker tests use to observe which folder the
// picker hands to the existing content-based folder chooser. Production always
// runs chooseCertificateFromFolder, unchanged.
var chooseCertFolder = chooseCertificateFromFolder

// certAttempts bounds the certificate path question the way the questionnaire
// bounds its own answers (askAttempts in cli/internal/installinput): a closed
// stdin cannot loop forever, and an operator who has nothing to give after
// three answers continues without a custom certificate.
const certAttempts = 3

// certContinueWithout is the one closing sentence every certificate dead end
// prints: the install goes on with automatic certificates, and the operator can
// add their own afterwards. One wording, so no path can leave the choice
// silent about what happens next.
func certContinueWithout() {
	certNotice("  Continuing with automatic certificates. Install your own later with: ./sb cert install")
}

// certRetryHint is what a retryable dead end says instead: another answer can
// still supply a certificate, and Enter ends the choice.
func certRetryHint() {
	certNotice("  Try another file or folder, or press Enter to continue without a certificate.")
}

// certFolderRetry is set by chooseCertificateFromFolder when it returns no
// certificate because the folder held nothing usable (read failure, no
// certificate with a matching key), as opposed to the operator declining the
// one usable certificate. The path question offers another answer in the
// first case and stops in the second. The test seam leaves it false, so a
// seam-driven nil still means the operator declined.
var certFolderRetry bool

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
//
// After "yes" the installer first lists the folders under ~ that hold
// certificate files by name (tmp/picker-proto/PROPOSAL.md). The list is a
// suggestion, not a scan: it never reads contents, so it needs no password,
// and the operator can always type another path instead. Choosing a folder
// runs chooseCertificateFromFolder, unchanged, which does the content checks
// and asks for a PFX password at most once.
func askInstallCert(dir string) ([]string, *string) {
	fmt.Println()
	for _, line := range certificateExplanation {
		certNotice("%s", line)
	}
	if !askCertificateYesNo("  Do you have a certificate to install now?") {
		certContinueWithout()
		return nil, nil
	}
	home, _ := os.UserHomeDir()
	folders := findCertificateCandidates(home)
	if len(folders) == 0 {
		certNotice("  No certificate files found under ~.")
		return askInstallCertPath(dir)
	}
	for _, line := range renderCertificateFolderChoices(folders, home) {
		certNotice("%s", line)
	}
	answer := questionnairePrompt("  Use which", "1")
	number, convErr := strconv.Atoi(strings.TrimSpace(answer))
	switch {
	case convErr == nil && number >= 1 && number <= len(folders):
		args, password := finishCertFolderChoice(folders[number-1].Path, dir)
		if args != nil || !certFolderRetry {
			return args, password
		}
		certRetryHint()
		return askInstallCertPath(dir)
	case convErr == nil && number == len(folders)+1:
		return askInstallCertPath(dir)
	}
	certNotice("  That is not one of the listed numbers; type a path instead.")
	return askInstallCertPath(dir)
}

// askInstallCertPath is the path question the installer has always asked: an
// absolute path, ~/..., or a path relative to where the installer was started.
// A path that cannot supply a certificate does not end the choice: the question
// is asked again, up to certAttempts times, and Enter continues without one.
func askInstallCertPath(dir string) ([]string, *string) {
	certNotice("  Paths may be absolute, start with ~/, or be relative to the directory you ran the installer from.")
	for attempt := 0; attempt < certAttempts; attempt++ {
		certPath := questionnairePrompt("  Certificate file or folder (a PFX/PKCS#12 file, a PEM fullchain, or a folder to inspect)", "")
		if certPath == "" {
			certContinueWithout()
			return nil, nil
		}
		args, password, retry := certificateFromAnswer(certPath, dir)
		if args != nil {
			return args, password
		}
		if !retry {
			certContinueWithout()
			return nil, nil
		}
		if attempt < certAttempts-1 {
			certRetryHint()
		}
	}
	certContinueWithout()
	return nil, nil
}

// certificateFromAnswer turns one path answer into certificate arguments.
// retry reports that the answer was understood but supplied no usable
// certificate, so another answer is worth asking for.
func certificateFromAnswer(certPath, dir string) (args []string, password *string, retry bool) {
	resolved, isDir, needsKey, err := inspectCertificatePath(certPath)
	if err != nil {
		certNotice("  %s", err)
		return nil, nil, true
	}
	if isDir {
		args, password = finishCertFolderChoice(resolved, dir)
		if args != nil {
			return args, password, false
		}
		return nil, nil, certFolderRetry
	}
	if !needsKey {
		return []string{resolved}, nil, false
	}
	keyPath := questionnairePrompt("  Private key file (only for a PEM fullchain; leave empty for a PFX file)", "")
	if keyPath == "" {
		certNotice("  A PEM certificate needs its private key.")
		return nil, nil, true
	}
	resolvedKey := resolveInstallPath(keyPath)
	if _, statErr := os.Stat(resolvedKey); statErr != nil {
		certNotice("  File not found: %s", resolvedKey)
		return nil, nil, true
	}
	return []string{resolved, resolvedKey}, nil, false
}

// finishCertFolderChoice runs the folder chooser. certFolderRetry afterwards
// says whether no certificate came back because the folder held nothing usable
// (another answer is worth asking for) or because the operator declined the one
// certificate it held (the choice ends).
func finishCertFolderChoice(folder, dir string) ([]string, *string) {
	certFolderRetry = false
	return chooseCertFolder(folder, dir)
}

// chooseCertificateFromFolder asks once for the PFX password when the folder
// contains PFX files, then presents the content-detected candidates. The
// password stays in memory only: it is never printed, logged, or persisted.
func chooseCertificateFromFolder(folder, dir string) ([]string, *string) {
	certFolderRetry = false
	_, siteDomain, _, _, err := readModeAndCertEnv(dir)
	if err != nil {
		siteDomain = ""
	}
	_, hasPFX, err := certFolderFiles(folder)
	if err != nil {
		certNotice("  Could not read folder %s: %v", folder, err)
		certFolderRetry = true
		return nil, nil
	}
	var pfxPassword *string
	if hasPFX {
		certNotice("  The folder contains PFX/PKCS#12 files. Their password is only used to read them and is not stored.")
		// readPassword disables terminal echo before the prompt reaches the
		// screen and ends the line on the terminal afterwards, so the masked
		// stars cannot run into the choices printed next (STATBUS-422).
		password, readErr := readPassword("  PFX password (type it and press Enter; it will not be shown; leave empty if none): ")
		if readErr == nil {
			pfxPassword = &password
		}
	}
	choices, notes, err := scanCertificateFolder(folder, siteDomain, pfxPassword)
	if err != nil {
		certNotice("  Could not inspect folder %s: %v", folder, err)
		certFolderRetry = true
		return nil, nil
	}
	if len(choices) == 0 {
		for _, note := range notes {
			certNotice("  - %s", note)
		}
		certNotice("  No usable certificate with a matching private key was found in %s.", folder)
		certFolderRetry = true
		return nil, nil
	}
	for _, line := range renderCertificateNotes(notes) {
		certNotice("%s", line)
	}
	if len(choices) == 1 {
		// One usable certificate is not a list: confirm it, with the same
		// information a numbered line carries (STATBUS-422).
		certNotice("%s", certificateChoiceLine(choices[0], siteDomain))
		if !askCertificateDefaultYes("  Install this certificate?") {
			certContinueWithout()
			return nil, nil
		}
		return choices[0].Args, pfxPassword
	}
	for _, line := range renderCertificateChoices(choices, nil, siteDomain) {
		certNotice("%s", line)
	}
	answer := questionnairePrompt("  Install which certificate number", "1")
	number, convErr := strconv.Atoi(strings.TrimSpace(answer))
	if convErr != nil || number < 1 || number > len(choices) {
		certNotice("  That is not one of the listed numbers.")
		certContinueWithout()
		return nil, nil
	}
	return choices[number-1].Args, pfxPassword
}
