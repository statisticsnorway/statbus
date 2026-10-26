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
	"fmt"
	"os"
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
		args = askInstallCert()
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

// askInstallCert is the interactive certificate question: optional, default
// keeps today's behaviour. It collects paths only; a PFX password is
// prompted by the shared loader exactly as ./sb cert install prompts.
// Returns nil when the operator declines or has nothing to give.
func askInstallCert() []string {
	fmt.Println()
	fmt.Println("  A standalone StatBus can serve your own TLS certificate (from your CA, as a")
	fmt.Println("  PFX/PKCS#12 file or a PEM certificate + key pair) instead of an automatic")
	fmt.Println("  Let's Encrypt certificate.")
	answer := questionnairePrompt("  Do you have a certificate to install now? (yes/no)", "no")
	if !strings.EqualFold(answer, "yes") && !strings.EqualFold(answer, "y") {
		fmt.Println("  Continuing with automatic certificates. Install your own later with: ./sb cert install")
		return nil
	}
	certPath := questionnairePrompt("  Certificate file (a PFX/PKCS#12 file, or a PEM fullchain)", "")
	if certPath == "" {
		fmt.Println("  No certificate file given; continuing without one. Install it later with: ./sb cert install")
		return nil
	}
	keyPath := questionnairePrompt("  Private key file (only for a PEM fullchain; leave empty for a PFX file)", "")
	if keyPath == "" {
		return []string{certPath}
	}
	return []string{certPath, keyPath}
}
