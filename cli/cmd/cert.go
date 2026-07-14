// Package cmd: cert subcommands (show, install, remove).
//
// Wraps the TLS_CERT_FILE / TLS_KEY_FILE template hook in
// caddy/templates/standalone.caddyfile.tmpl in an operator-friendly
// suite. Subsumes ops/convert-pfx-cert.sh end-to-end (PFX password
// prompt, pkcs12 decode, modulus-match validation, file placement,
// .env.config update, ./sb config generate, docker compose restart
// proxy, post-install TLS probe).
//
// Scope: standalone deployment mode. Private mode emits a hint that
// the upstream proxy owns the cert; development mode points at the
// self-signed Caddy internal CA.
//
// Conversational verb order (show first because it's the safest and
// the most likely first command an operator runs): show → install →
// remove. Bare `./sb cert` prints the usage block.
package cmd

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io/fs"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"golang.org/x/term"
	pkcs12 "software.sslmate.com/src/go-pkcs12"
)

// ─── Constants ───────────────────────────────────────────────────────────

// customCertHostDir is the project-root-relative directory where
// ./sb cert install writes the extracted cert + key. The Caddy proxy
// container mounts caddy/data as /data, so a file placed at
// caddy/data/custom-certs/<name>.crt on the host appears at
// /data/custom-certs/<name>.crt in the container.
const customCertHostDir = "caddy/data/custom-certs"

// customCertContainerDir is the in-container path that matches
// customCertHostDir via the docker-compose volume mount in
// caddy/docker-compose.yml (./data:/data). TLS_CERT_FILE / TLS_KEY_FILE
// in .env.config must use container-relative paths because Caddy
// reads them from inside the container.
const customCertContainerDir = "/data/custom-certs"

// acmeCertStorageDir is the Caddy ACME storage location under the
// caddy/data mount. Used by `./sb cert show` to surface the
// auto-issued Let's Encrypt cert.
const acmeCertStorageDir = "caddy/data/caddy/certificates"

// devSelfSignedCAPath is Caddy's internal CA root used in development
// mode (https://local.statbus.org:3011 etc.). Show command points at
// this when CADDY_DEPLOYMENT_MODE=development.
const devSelfSignedCAPath = "caddy/data/caddy/pki/authorities/local/root.crt"

// ─── Command definitions ────────────────────────────────────────────────

var certCmd = &cobra.Command{
	Use:   "cert",
	Short: "Manage TLS certificates (custom PFX/PEM or automatic Let's Encrypt)",
	Long: `Manage the TLS certificate StatBus uses to serve HTTPS.

There are two kinds of certificate StatBus can serve:

  AUTOMATIC (default):
      Caddy requests a certificate from Let's Encrypt the first time
      a browser connects via HTTPS. Renewals happen automatically.
      Free; requires the operator's domain to be reachable from the
      public internet on port 443. No setup steps needed.

  CUSTOM (this command):
      An operator-supplied certificate, e.g. one issued by an
      institutional CA, a commercial CA, or a national PKI.
      Albania's StatBus install uses this — the country's PKI
      issues a PFX certificate that gets installed via:
          ./sb cert install /path/to/certificate.pfx

Typical operator flow:

  ./sb cert show                              # what cert is on this server right now?
  ./sb cert install /downloads/site.pfx       # swap to a custom cert (PFX)
  ./sb cert install fullchain.pem privkey.pem # swap to a custom cert (PEM pair)
  ./sb cert remove                            # revert to automatic Let's Encrypt`,
	Example: `  # See what certificate is currently serving HTTPS
  ./sb cert show

  # Install a PFX (most common — your CA exports as PFX)
  ./sb cert install ~/Downloads/statbus-2026.pfx

  # Install a PEM pair (already-extracted fullchain + private key)
  ./sb cert install fullchain.pem privkey.pem

  # Go back to automatic Let's Encrypt
  ./sb cert remove`,
}

var certShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show the TLS certificate currently being served",
	Long: `Inspect the TLS certificate StatBus is currently serving on HTTPS.

Output fields:
  Source        Where the cert came from. "Custom" means operator-
                installed via ./sb cert install. "Automatic Let's
                Encrypt" means Caddy auto-issued via ACME.
  Path          Host filesystem path to the .crt file.
  Issuer        Common Name of the CA that signed the certificate.
                e.g. "Let's Encrypt R3" or "DigiCert Global Root CA".
  Subject       Common Name in the certificate's Subject field.
                Usually matches your site domain.
  SANs          Subject Alternative Names — every hostname this
                certificate is valid for. Browsers compare the URL's
                hostname against this list.
  NotBefore     When the certificate became valid.
  NotAfter      Expiry date + how many days until expiry. Browsers
                refuse expired certificates.
  Chain depth   Number of certificates in the chain. 1 = just the
                leaf (no intermediates — may break for browsers
                without your CA's root trusted). >1 = leaf +
                intermediate(s), which is the normal shape.
  SHA-256       Fingerprint of the leaf certificate. Compare to
                what the operator's CA sent you to confirm
                identity.`,
	Example: `  ./sb cert show`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runCertShow(config.ProjectDir())
	},
}

var certInstallCmd = &cobra.Command{
	Use:   "install <cert-file> [<key-file>]",
	Short: "Install a custom certificate (PFX or PEM pair) and reload Caddy",
	Long: `Install a custom TLS certificate.

There are two shapes of input:

  PFX (PKCS#12):
      A single file (extension usually .pfx or .p12) that holds the
      certificate chain AND the private key, encrypted with a
      password. Most institutional CAs export in this shape.
      Run:  ./sb cert install <your.pfx>
      You'll be prompted for the PFX password.

  PEM pair:
      Two separate files — fullchain.pem (one or more CERTIFICATE
      PEM blocks, leaf first) and privkey.pem (one PRIVATE KEY
      block). Common output of openssl extraction or ACME tools.
      Run:  ./sb cert install fullchain.pem privkey.pem

The detection happens by file CONTENT, not extension — if you
renamed a PFX to .crt, it'll still be recognised.

The install flow:

  1. Read + decode the certificate material.
  2. Verify the certificate and private key are a matched pair
     (their public keys must agree). Mismatch → loud refusal.
  3. Warn if the chain has only the leaf (no intermediates):
     browsers with system trust roots will still verify; non-
     system roots will break.
  4. Show you the cert details (issuer, subject, SANs, expiry)
     BEFORE writing anything — confirm it's the right cert.
  5. Place caddy/data/custom-certs/<sanitised-name>.{crt,key}.
  6. Update .env.config TLS_CERT_FILE + TLS_KEY_FILE.
  7. Regenerate Caddy configuration.
  8. Restart the Caddy container (docker compose restart proxy).
  9. Probe https://<SITE_DOMAIN> and confirm the served cert
     SHA-256 matches the installed one. If not, fail loud — Caddy
     did not pick up the new cert.

Scope: standalone deployment mode only. In private mode the
upstream proxy owns the certificate; in development mode Caddy
serves its own internal CA. ./sb cert show explains both.`,
	Example: `  # PFX with password (Albania's flow)
  ./sb cert install ~/Downloads/statbus-2026.pfx
  Enter PFX password: ********

  # PEM pair (already extracted)
  ./sb cert install fullchain.pem privkey.pem

  # File renamed from PFX → still detected via content
  ./sb cert install ~/cert-with-wrong-extension.crt`,
	Args: cobra.RangeArgs(1, 2),
	RunE: func(cmd *cobra.Command, args []string) error {
		return runCertInstall(config.ProjectDir(), args)
	},
}

var certRemoveCmd = &cobra.Command{
	Use:   "remove",
	Short: "Remove custom certificate and revert to automatic Let's Encrypt",
	Long: `Revert from a custom (operator-installed) certificate to automatic
Let's Encrypt issuance.

What this does:

  1. Archives your current custom cert files to
     caddy/data/custom-certs/archive/<timestamp>/ (move, not
     delete — you can retrieve them later if needed).
  2. Clears TLS_CERT_FILE + TLS_KEY_FILE in .env.config.
  3. Regenerates Caddy configuration.
  4. Restarts the Caddy container.

What happens next:

  Caddy will request a fresh certificate from Let's Encrypt the
  first time a browser connects via HTTPS. This requires:
  - Your SITE_DOMAIN is reachable from the public internet.
  - Port 80 + 443 on the host are open + forwarded to Caddy.
  - DNS for SITE_DOMAIN points at this host's public IP.

If any of those isn't true, you'll need to either install another
custom certificate OR fix the network setup. Run ./sb cert show
in a few minutes to confirm Caddy got the new cert.

Scope: standalone deployment mode only.`,
	Example: `  ./sb cert remove`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runCertRemove(config.ProjectDir())
	},
}

func init() {
	certCmd.AddCommand(certShowCmd)
	certCmd.AddCommand(certInstallCmd)
	certCmd.AddCommand(certRemoveCmd)
	rootCmd.AddCommand(certCmd)
}

// ─── show ───────────────────────────────────────────────────────────────

// certInfo is the parsed projection of a leaf certificate used for
// both display and verification (SHA-256 round-trip after Caddy
// restart). Source distinguishes custom (operator-installed) from
// ACME (auto-issued) so the operator knows what to do to rotate.
type certInfo struct {
	Source     string // "Custom" or "Automatic Let's Encrypt (ACME)" or "Development self-signed"
	Path       string // human-readable host path
	Issuer     string
	Subject    string
	SANs       []string
	NotBefore  time.Time
	NotAfter   time.Time
	ChainDepth int
	SHA256     [32]byte
}

// runCertShow dispatches based on deployment mode + presence of
// custom cert env vars. Standalone mode has the full workflow; the
// other two modes print mode-appropriate guidance.
func runCertShow(projDir string) error {
	mode, siteDomain, tlsCert, tlsKey, err := readModeAndCertEnv(projDir)
	if err != nil {
		return err
	}
	_ = tlsKey // present-or-absent of tlsKey informs nothing show needs

	switch mode {
	case "private":
		fmt.Println("Source:       Custom certificates are managed by the upstream proxy in private deployment mode.")
		fmt.Println("              StatBus's Caddy receives plaintext from the host proxy and trusts X-Forwarded-* headers.")
		fmt.Println()
		fmt.Printf("To inspect what the upstream proxy serves on %s:\n", siteDomain)
		fmt.Printf("  openssl s_client -connect %s:443 -showcerts </dev/null 2>/dev/null | openssl x509 -text -noout\n", siteDomain)
		return nil
	case "development":
		caPath := filepath.Join(projDir, devSelfSignedCAPath)
		if info, infoErr := parseLeafCert(caPath); infoErr == nil {
			info.Source = "Development mode (Caddy internal self-signed CA)"
			info.Path = caPath
			printCertInfo(info)
			return nil
		}
		// Cert not on disk yet — Caddy creates it on first HTTPS
		// request. Surface a uniform two-line summary so the
		// operator knows where to look once it appears.
		fmt.Println("Source:       Development mode (Caddy internal self-signed CA)")
		fmt.Printf("Path:         %s\n", caPath)
		fmt.Println("              (file not found yet; Caddy creates it on first HTTPS request)")
		return nil
	}

	// Standalone mode — custom or ACME.
	if tlsCert != "" {
		hostPath := containerToHostPath(projDir, tlsCert)
		info, parseErr := parseLeafCert(hostPath)
		if parseErr != nil {
			return fmt.Errorf("read custom cert at %s: %w", hostPath, parseErr)
		}
		info.Source = "Custom (TLS_CERT_FILE in .env.config)"
		info.Path = hostPath
		printCertInfo(info)
		return nil
	}

	// ACME path.
	acmeCertPath := findACMECert(projDir, siteDomain)
	if acmeCertPath == "" {
		fmt.Println("Source:       Automatic Let's Encrypt (ACME) — no certificate issued yet")
		fmt.Println()
		fmt.Println("No TLS certificate installed yet.")
		fmt.Println("  If services are running, Caddy will request one from Let's Encrypt on first HTTPS request.")
		fmt.Println("  Try: ./sb ps to confirm caddy is up.")
		return nil
	}
	info, parseErr := parseLeafCert(acmeCertPath)
	if parseErr != nil {
		return fmt.Errorf("read ACME cert at %s: %w", acmeCertPath, parseErr)
	}
	info.Source = "Automatic Let's Encrypt (ACME)"
	info.Path = acmeCertPath
	printCertInfo(info)
	return nil
}

// printCertInfo emits the structured, aligned-column output. Layout
// fixed so the operator can grep / parse if they want; column widths
// chosen so values fit common cases (CN <= 60 chars, SANs comma-
// joined).
func printCertInfo(info certInfo) {
	fmt.Printf("Source:       %s\n", info.Source)
	fmt.Printf("Path:         %s\n", info.Path)
	fmt.Printf("Issuer:       %s\n", info.Issuer)
	fmt.Printf("Subject:      %s\n", info.Subject)
	if len(info.SANs) > 0 {
		fmt.Printf("SANs:         %s\n", strings.Join(info.SANs, ", "))
	}
	fmt.Printf("NotBefore:    %s\n", info.NotBefore.UTC().Format("2006-01-02 15:04:05 UTC"))
	fmt.Printf("NotAfter:     %s%s\n", info.NotAfter.UTC().Format("2006-01-02 15:04:05 UTC"), expiryAnnotation(info.NotAfter))
	if info.ChainDepth > 1 {
		fmt.Printf("Chain depth:  %d (leaf + %d intermediate(s))\n", info.ChainDepth, info.ChainDepth-1)
	} else {
		fmt.Printf("Chain depth:  %d (leaf only)\n", info.ChainDepth)
	}
	fmt.Printf("SHA-256:      %s\n", fingerprintHex(info.SHA256))
}

func expiryAnnotation(notAfter time.Time) string {
	d := time.Until(notAfter)
	days := int(d.Hours() / 24)
	switch {
	case d <= 0:
		return fmt.Sprintf("  (EXPIRED %d days ago)", -days)
	case days < 14:
		return fmt.Sprintf("  (expires in %d days — RENEW SOON)", days)
	default:
		return fmt.Sprintf("  (expires in %d days)", days)
	}
}

// ─── install ────────────────────────────────────────────────────────────

// runCertInstall is the workflow that subsumes ops/convert-pfx-cert.sh.
// Two input shapes (PFX or PEM pair) → detected by content, not
// extension → validated, placed, env-updated, configured, restarted,
// and probe-verified.
func runCertInstall(projDir string, args []string) error {
	mode, siteDomain, _, _, err := readModeAndCertEnv(projDir)
	if err != nil {
		return err
	}
	if mode != "standalone" {
		return fmt.Errorf("./sb cert install is only supported in standalone deployment mode (current: %q).\n"+
			"  - private mode: the upstream proxy owns the certificate; install it there.\n"+
			"  - development mode: Caddy uses its internal CA; no install needed",
			mode)
	}
	if siteDomain == "" {
		return errors.New("SITE_DOMAIN not set in .env.config — post-install TLS probe needs it. " +
			"Set SITE_DOMAIN, run `./sb config generate`, then retry")
	}

	chain, key, baseName, err := loadCertMaterial(args)
	if err != nil {
		return err
	}
	if len(chain) == 0 {
		return errors.New("no certificates parsed from input")
	}
	leaf := chain[0]
	if err := validateCertKeyMatch(leaf, key); err != nil {
		return fmt.Errorf("certificate/key mismatch: %w\n"+
			"  The certificate's public key does not match the private key.\n"+
			"  Most likely cause: PFX or PEM file is malformed, or wrong key paired with wrong cert",
			err)
	}
	fmt.Println("✓ Certificate and key match (public-key check)")

	if len(chain) < 2 {
		fmt.Println("⚠ Chain has only the leaf certificate — no intermediates.")
		fmt.Println("  Caddy needs the full chain to serve clients with non-system roots.")
		fmt.Println("  Continuing, but if browsers report \"certificate not trusted\", re-export the PFX with all intermediates.")
	} else {
		fmt.Printf("✓ Chain validated (%d certificates: leaf + %d intermediate(s))\n", len(chain), len(chain)-1)
	}

	// Print cert details so the operator confirms it's the right one.
	fmt.Println()
	info := buildCertInfo(chain)
	info.Source = "About to install (custom)"
	info.Path = filepath.Join(customCertHostDir, baseName+".crt")
	printCertInfo(info)
	fmt.Println()

	// Place files.
	hostCertPath, hostKeyPath, err := writeCertAndKey(projDir, baseName, chain, key)
	if err != nil {
		return fmt.Errorf("write cert/key files: %w", err)
	}
	fmt.Printf("✓ Files placed: %s, %s\n", hostCertPath, hostKeyPath)

	// Update .env.config.
	containerCertPath := customCertContainerDir + "/" + baseName + ".crt"
	containerKeyPath := customCertContainerDir + "/" + baseName + ".key"
	if err := updateEnvConfigCertPaths(projDir, containerCertPath, containerKeyPath); err != nil {
		return fmt.Errorf("update .env.config: %w", err)
	}
	fmt.Printf("✓ .env.config updated (TLS_CERT_FILE=%s, TLS_KEY_FILE=%s)\n", containerCertPath, containerKeyPath)

	// Regenerate Caddy config (in-process, not shell-out).
	if err := config.Generate(false); err != nil {
		return fmt.Errorf("config generate: %w", err)
	}
	fmt.Println("✓ Configuration regenerated")

	// Restart proxy.
	if err := runCmdDir(projDir, "docker", "compose", "restart", "proxy"); err != nil {
		return fmt.Errorf("docker compose restart proxy: %w", err)
	}
	fmt.Println("✓ Caddy restarted")

	// Verify via TLS probe that the served cert matches what we
	// just installed. Polls for up to 30s because Caddy can take a
	// few seconds to bind after restart.
	expectedSHA := info.SHA256
	if err := verifyServedCert(siteDomain, expectedSHA, 30*time.Second); err != nil {
		return fmt.Errorf("post-install verification FAILED: %w\n"+
			"  The cert is on disk and .env.config is updated, but Caddy isn't serving it yet.\n"+
			"  Check: docker compose logs proxy\n"+
			"         ./sb cert show",
			err)
	}
	fmt.Printf("✓ Verified: https://%s serves the new certificate\n", siteDomain)

	fmt.Println()
	fmt.Println("Run ./sb cert show to inspect the live certificate.")
	return nil
}

// loadCertMaterial dispatches on argv shape + file content. Returns
// the cert chain (leaf first), the private key, and a sanitised
// base name for output file naming.
//
// Errors are actionable rather than stack-tracey:
//   - File not found → "File not found: <path>" + suggestion
//   - PFX wrong password → "Invalid PFX password — re-run with the
//     correct password (the one your CA emailed you with the cert)"
//   - PFX corrupt / not actually PFX → fall through to PEM parse
//   - Neither PFX nor PEM → "input is neither a valid PKCS#12 PFX
//     nor a PEM bundle"
//
// All decode failures happen BEFORE any file is written to disk;
// no partial state to clean up.
func loadCertMaterial(args []string) ([]*x509.Certificate, interface{}, string, error) {
	switch len(args) {
	case 1:
		path := args[0]
		data, err := readCertFile(path)
		if err != nil {
			return nil, nil, "", err
		}
		// Single file → try PFX first (content-detect), fall back
		// to PEM. tryDecodePFX prompts for password ONLY when the
		// input looks like DER (0x30 0x82). For PEM-shaped input,
		// it returns immediately with a sentinel so we fall
		// through without bothering the operator for a password.
		chain, key, decodeErr := decodePFXOrFallback(data)
		if decodeErr != nil {
			return nil, nil, "", decodeErr
		}
		if chain != nil {
			return chain, key, sanitiseBaseName(path), nil
		}
		// PEM fallback (single-file with cert + key concatenated).
		chain, key, err = parsePEMBundle(data)
		if err != nil {
			return nil, nil, "", fmt.Errorf("input %s is neither a valid PKCS#12 PFX nor a PEM bundle: %w\n"+
				"  Expected: a .pfx file (single file containing cert + private key, password-protected),\n"+
				"  or a single PEM file containing both CERTIFICATE and PRIVATE KEY blocks", path, err)
		}
		return chain, key, sanitiseBaseName(path), nil
	case 2:
		// Two files → PEM pair (fullchain + key).
		certData, err := readCertFile(args[0])
		if err != nil {
			return nil, nil, "", err
		}
		keyData, err := readCertFile(args[1])
		if err != nil {
			return nil, nil, "", err
		}
		chain, err := parsePEMChain(certData)
		if err != nil {
			return nil, nil, "", fmt.Errorf("could not parse certificate file %s: %w\n"+
				"  Expected: a PEM file containing one or more CERTIFICATE blocks (fullchain format)", args[0], err)
		}
		key, err := parsePEMKey(keyData)
		if err != nil {
			return nil, nil, "", fmt.Errorf("could not parse private key file %s: %w\n"+
				"  Expected: a PEM file containing one PRIVATE KEY / RSA PRIVATE KEY / EC PRIVATE KEY block", args[1], err)
		}
		return chain, key, sanitiseBaseName(args[0]), nil
	default:
		return nil, nil, "", fmt.Errorf("install takes 1 arg (PFX or single-file PEM bundle) or 2 args (fullchain.pem + key.pem); got %d", len(args))
	}
}

// readCertFile reads a cert/key/PFX file with an actionable error
// when the path doesn't exist or isn't readable.
func readCertFile(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, fmt.Errorf("file not found: %s\n"+
				"  Check the path spelling and that the file exists where you expect.\n"+
				"  Hint: ls -la %s   (to confirm the file is there)", path, filepath.Dir(path))
		}
		if errors.Is(err, fs.ErrPermission) {
			return nil, fmt.Errorf("permission denied reading %s\n"+
				"  Check file ownership / permissions:\n"+
				"    ls -la %s\n"+
				"  The file must be readable by the user running ./sb cert", path, path)
		}
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	return data, nil
}

// decodePFXOrFallback inspects the file and either decodes as PFX
// (prompting for password) or returns (nil, nil, nil) to signal
// "not a PFX — try PEM next." Returns a non-nil error ONLY when the
// input clearly IS a PFX but the password is wrong / file is
// corrupt — in that case we surface a loud, actionable error rather
// than silently falling through to PEM (which would then fail with
// a misleading "no PEM blocks found").
func decodePFXOrFallback(data []byte) ([]*x509.Certificate, interface{}, error) {
	if !looksLikeDER(data) {
		// Clearly not a PFX (PEM or unknown) — fall through.
		return nil, nil, nil
	}
	pw, err := readPassword("Enter PFX password (leave empty if none): ")
	if err != nil {
		return nil, nil, fmt.Errorf("could not read password from terminal: %w", err)
	}
	chain, key, err := decodePFX(data, pw)
	if err != nil {
		return nil, nil, err
	}
	fmt.Println("✓ PFX validated")
	fmt.Printf("✓ Certificate chain extracted (%d cert(s))\n", len(chain))
	fmt.Println("✓ Private key extracted")
	return chain, key, nil
}

// decodePFX is the pure decode primitive: takes bytes + password,
// returns chain (leaf-first) + key. No I/O, no prompting, no
// surface-level output — pure for unit testability against
// password-protected and unencrypted PFX fixtures.
//
// Uses sslmate's pkcs12.DecodeChain — it handles both modern PFX
// crypto (PBES2/AES, SHA-256 MAC, the OpenSSL 3.x default) and
// legacy SHA-1-MAC/3DES PFX that older national PKIs may still
// emit. The stdlib (golang.org/x/crypto/pkcs12) was frozen at
// SHA-1 only and rejects any modern PFX with "unknown digest
// algorithm: 2.16.840.1.101.3.4.2.1" — the SHA-256 OID — which
// would be a hostile error message to surface to a training
// operator the day before they need to install a real cert.
//
// DecodeChain returns the private key already parsed (no PEM round
// trip / PKCS#1-vs-PKCS#8 ambiguity) and the cert chain pre-split
// into (leaf, intermediates). We re-assemble [leaf, …intermediates]
// for the rest of the install flow.
func decodePFX(data []byte, password string) ([]*x509.Certificate, interface{}, error) {
	key, leaf, caCerts, err := pkcs12.DecodeChain(data, password)
	if err != nil {
		// sslmate surfaces ErrDecryption when the password is
		// wrong. Translate to an actionable operator-facing
		// message; other errors get a generic "PFX decode
		// failed" wrapper that preserves the upstream detail.
		if errors.Is(err, pkcs12.ErrDecryption) || strings.Contains(strings.ToLower(err.Error()), "decryption") {
			return nil, nil, fmt.Errorf("invalid PFX password — re-run and enter the password from your CA's email or PFX export\n"+
				"  (pkcs12 decryption returned: %v)", err)
		}
		return nil, nil, fmt.Errorf("PFX decode failed: %w\n"+
			"  The file may be corrupt or not a valid PKCS#12 PFX archive.\n"+
			"  Try opening it with: openssl pkcs12 -info -in <your.pfx>", err)
	}
	if leaf == nil {
		return nil, nil, errors.New("PFX decoded but contained no leaf certificate (file is structurally a PKCS#12 but has no end-entity cert)")
	}
	if key == nil {
		return nil, nil, errors.New("PFX decoded but contained no private key (file has certificates but no private key)")
	}
	chain := append([]*x509.Certificate{leaf}, caCerts...)
	// Chain order: DecodeChain returns leaf separately from caCerts,
	// but caCerts ordering isn't guaranteed root-first vs leaf-first.
	// reorderChainLeafFirst is idempotent — if leaf is already at
	// index 0 (which it is post-prepend), it leaves the order alone;
	// if the operator hand-crafted the PFX with a scrambled chain,
	// we still arrive at leaf-first.
	chain = reorderChainLeafFirst(chain)
	return chain, key, nil
}

// reorderChainLeafFirst puts the leaf cert at index 0 by finding the
// cert that isn't an issuer of any other cert in the chain.
// pkcs12.ToPEM doesn't guarantee a particular order; downstream
// callers (writeCertAndKey, buildCertInfo) assume leaf-first.
func reorderChainLeafFirst(chain []*x509.Certificate) []*x509.Certificate {
	if len(chain) <= 1 {
		return chain
	}
	// Build a set of Subject DNs that ARE issuers of some other
	// cert. The leaf is the one whose Subject DN is NOT in the set.
	issuerSubjects := make(map[string]bool)
	for _, c := range chain {
		issuerSubjects[c.Issuer.String()] = true
	}
	for i, c := range chain {
		if !issuerSubjects[c.Subject.String()] {
			if i == 0 {
				return chain
			}
			out := make([]*x509.Certificate, 0, len(chain))
			out = append(out, c)
			for j, other := range chain {
				if j != i {
					out = append(out, other)
				}
			}
			return out
		}
	}
	// All certs are issuers of someone in the chain (cycle? shouldn't
	// happen for valid PKI). Return as-is.
	return chain
}

// looksLikeDER is a coarse PKCS#12-vs-PEM discriminator. PFX/PKCS#12
// files are DER-encoded ASN.1 and start with the SEQUENCE tag (0x30)
// + 2-byte length prefix (0x82 NN NN for long-form). PEM starts
// with "-----BEGIN". Test 4 bytes for the DER signature; everything
// else falls through to PEM parsing.
func looksLikeDER(data []byte) bool {
	if len(data) < 4 {
		return false
	}
	return data[0] == 0x30 && data[1] == 0x82
}

// parsePEMBundle handles a single file containing both cert(s) and
// key in PEM format (operator may concatenate fullchain + key for
// convenience).
func parsePEMBundle(data []byte) ([]*x509.Certificate, interface{}, error) {
	var chain []*x509.Certificate
	var key interface{}
	rest := data
	for {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		switch block.Type {
		case "CERTIFICATE":
			cert, err := x509.ParseCertificate(block.Bytes)
			if err != nil {
				return nil, nil, fmt.Errorf("parse certificate block: %w", err)
			}
			chain = append(chain, cert)
		case "RSA PRIVATE KEY", "EC PRIVATE KEY", "PRIVATE KEY":
			k, err := parsePrivateKeyBlock(block)
			if err != nil {
				return nil, nil, err
			}
			key = k
		}
	}
	if len(chain) == 0 {
		return nil, nil, errors.New("no CERTIFICATE blocks found")
	}
	if key == nil {
		return nil, nil, errors.New("no PRIVATE KEY block found")
	}
	return chain, key, nil
}

// parsePEMChain extracts CERTIFICATE blocks only — used for the
// fullchain.pem half of a two-arg install.
func parsePEMChain(data []byte) ([]*x509.Certificate, error) {
	var chain []*x509.Certificate
	rest := data
	for {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		if block.Type != "CERTIFICATE" {
			continue
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, err
		}
		chain = append(chain, cert)
	}
	if len(chain) == 0 {
		return nil, errors.New("no CERTIFICATE blocks found")
	}
	return chain, nil
}

// parsePEMKey extracts a single PRIVATE KEY block (any flavour).
func parsePEMKey(data []byte) (interface{}, error) {
	for {
		var block *pem.Block
		block, data = pem.Decode(data)
		if block == nil {
			break
		}
		switch block.Type {
		case "RSA PRIVATE KEY", "EC PRIVATE KEY", "PRIVATE KEY":
			return parsePrivateKeyBlock(block)
		}
	}
	return nil, errors.New("no PRIVATE KEY block found")
}

func parsePrivateKeyBlock(block *pem.Block) (interface{}, error) {
	if block == nil {
		return nil, errors.New("nil block")
	}
	switch block.Type {
	case "RSA PRIVATE KEY":
		return x509.ParsePKCS1PrivateKey(block.Bytes)
	case "EC PRIVATE KEY":
		return x509.ParseECPrivateKey(block.Bytes)
	case "PRIVATE KEY":
		return x509.ParsePKCS8PrivateKey(block.Bytes)
	}
	return nil, fmt.Errorf("unknown private key type %q", block.Type)
}

// validateCertKeyMatch compares the cert's public key against the
// private key's public key. Handles RSA, ECDSA, Ed25519. Returns
// nil on match, error on mismatch or unknown type.
//
// Replaces the openssl `rsa -modulus | md5` dance in
// ops/convert-pfx-cert.sh. Works for all three modern key types
// (RSA still common; ECDSA via Let's Encrypt; Ed25519 less common
// but supported).
func validateCertKeyMatch(cert *x509.Certificate, privateKey interface{}) error {
	switch pk := privateKey.(type) {
	case *rsa.PrivateKey:
		certPub, ok := cert.PublicKey.(*rsa.PublicKey)
		if !ok {
			return fmt.Errorf("cert public key is %T but private key is RSA", cert.PublicKey)
		}
		if pk.N.Cmp(certPub.N) != 0 || pk.E != certPub.E {
			return errors.New("RSA modulus/exponent mismatch")
		}
		return nil
	case *ecdsa.PrivateKey:
		certPub, ok := cert.PublicKey.(*ecdsa.PublicKey)
		if !ok {
			return fmt.Errorf("cert public key is %T but private key is ECDSA", cert.PublicKey)
		}
		if pk.X.Cmp(certPub.X) != 0 || pk.Y.Cmp(certPub.Y) != 0 || pk.Curve != certPub.Curve {
			return errors.New("ECDSA public key components mismatch")
		}
		return nil
	case ed25519.PrivateKey:
		certPub, ok := cert.PublicKey.(ed25519.PublicKey)
		if !ok {
			return fmt.Errorf("cert public key is %T but private key is Ed25519", cert.PublicKey)
		}
		pkPub := pk.Public().(ed25519.PublicKey)
		if !bytesEqual(pkPub, certPub) {
			return errors.New("Ed25519 public key mismatch")
		}
		return nil
	}
	return fmt.Errorf("unsupported private key type %T", privateKey)
}

func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// writeCertAndKey writes the cert chain (PEM, leaf first then any
// intermediates) and the private key (PEM PKCS#8) to
// caddy/data/custom-certs/<baseName>.{crt,key}. chmod 644 on cert,
// 600 on key.
//
// Atomic-ish: marshals everything in memory FIRST (so marshal errors
// don't leave half-written state on disk), writes via tempfile+rename,
// and removes the cert if the key write fails. The operator never sees
// "cert written, key missing" state on a failed run.
func writeCertAndKey(projDir, baseName string, chain []*x509.Certificate, key interface{}) (string, string, error) {
	dir := filepath.Join(projDir, customCertHostDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", "", fmt.Errorf("create dir %s: %w", dir, err)
	}
	certPath := filepath.Join(dir, baseName+".crt")
	keyPath := filepath.Join(dir, baseName+".key")

	// PHASE 1 — marshal everything in memory FIRST. If either
	// marshalling step fails, nothing has touched disk yet.
	var certBuf strings.Builder
	for _, c := range chain {
		block := &pem.Block{Type: "CERTIFICATE", Bytes: c.Raw}
		certBuf.Write(pem.EncodeToMemory(block))
	}
	certBytes := []byte(certBuf.String())

	keyBytes, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return "", "", fmt.Errorf("marshal private key: %w\n"+
			"  The key type may be unsupported (RSA / ECDSA / Ed25519 are supported)", err)
	}
	keyPem := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyBytes})

	// PHASE 2 — write cert atomically via tempfile+rename.
	if err := writeAtomic(certPath, certBytes, 0o644); err != nil {
		return "", "", fmt.Errorf("write certificate %s: %w", certPath, err)
	}

	// PHASE 3 — write key atomically. If it fails, remove the cert
	// we just wrote so the operator isn't left with an orphan .crt
	// and a missing .key (which would produce confusing Caddy
	// errors at restart time).
	if err := writeAtomic(keyPath, keyPem, 0o600); err != nil {
		_ = os.Remove(certPath)
		return "", "", fmt.Errorf("write private key %s: %w\n"+
			"  Cleaned up the partial certificate file; no orphan state left behind", keyPath, err)
	}
	return certPath, keyPath, nil
}

// writeAtomic writes data to path via a sibling tempfile + rename
// so a partial write never appears at the target path. Used for
// cert + key placement to keep failures clean.
func writeAtomic(path string, data []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, filepath.Base(path)+".tmp.*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := func() { _ = os.Remove(tmpName) }
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		cleanup()
		return err
	}
	if err := tmp.Chmod(mode); err != nil {
		_ = tmp.Close()
		cleanup()
		return err
	}
	if err := tmp.Close(); err != nil {
		cleanup()
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		cleanup()
		return err
	}
	return nil
}

// updateEnvConfigCertPaths reads .env.config, sets/replaces
// TLS_CERT_FILE + TLS_KEY_FILE (container paths), and writes back.
// Idempotent — existing values are overwritten cleanly via
// dotenv.Set; missing keys are appended at the bottom of the file.
func updateEnvConfigCertPaths(projDir, certPath, keyPath string) error {
	cfgPath := filepath.Join(projDir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return err
	}
	f.Set("TLS_CERT_FILE", certPath)
	f.Set("TLS_KEY_FILE", keyPath)
	return f.Save()
}

// verifyServedCert opens a TLS connection to siteDomain:443 and
// confirms the leaf cert SHA-256 matches expectedSHA. Polls every
// 2s up to timeout because Caddy can take a few seconds to bind
// after `docker compose restart proxy`.
//
// InsecureSkipVerify is intentional here: we're verifying SHA-256
// against the cert we just placed on disk, not chain validity. If
// the operator's chain has a problem, `./sb cert show` surfaces it
// post-hoc; the post-install probe just confirms Caddy is serving
// THIS cert.
func verifyServedCert(siteDomain string, expectedSHA [32]byte, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	var lastErr error
	for time.Now().Before(deadline) {
		addr := net.JoinHostPort(siteDomain, "443")
		dialer := &net.Dialer{Timeout: 5 * time.Second}
		conn, err := tls.DialWithDialer(dialer, "tcp", addr,
			&tls.Config{InsecureSkipVerify: true, ServerName: siteDomain})
		if err != nil {
			lastErr = err
			time.Sleep(2 * time.Second)
			continue
		}
		state := conn.ConnectionState()
		_ = conn.Close()
		if len(state.PeerCertificates) == 0 {
			lastErr = errors.New("TLS handshake completed but no peer certificates returned")
			time.Sleep(2 * time.Second)
			continue
		}
		servedSHA := sha256.Sum256(state.PeerCertificates[0].Raw)
		if servedSHA == expectedSHA {
			return nil
		}
		return fmt.Errorf("served cert SHA-256 %s != installed cert SHA-256 %s",
			fingerprintHex(servedSHA), fingerprintHex(expectedSHA))
	}
	return fmt.Errorf("could not verify served cert within %s: %v", timeout, lastErr)
}

// ─── remove ─────────────────────────────────────────────────────────────

// runCertRemove reverts to ACME by unsetting TLS_CERT_FILE +
// TLS_KEY_FILE in .env.config, archiving the current custom certs
// (move rather than delete — operator may need to retrieve them),
// regenerating config, restarting Caddy.
func runCertRemove(projDir string) error {
	mode, _, tlsCert, tlsKey, err := readModeAndCertEnv(projDir)
	if err != nil {
		return err
	}
	if mode != "standalone" {
		return fmt.Errorf("./sb cert remove is only supported in standalone deployment mode (current: %q)", mode)
	}
	if tlsCert == "" && tlsKey == "" {
		fmt.Println("No custom certificate configured (TLS_CERT_FILE + TLS_KEY_FILE empty). Nothing to remove.")
		return nil
	}

	// Archive existing files to a timestamped subdirectory under
	// caddy/data/custom-certs/archive/<timestamp>/. Operator can
	// rm -rf it later if they want to free space.
	archiveDir := filepath.Join(projDir, customCertHostDir, "archive", time.Now().UTC().Format("20060102-150405"))
	if err := os.MkdirAll(archiveDir, 0o755); err != nil {
		return fmt.Errorf("create archive dir: %w", err)
	}
	for _, container := range []string{tlsCert, tlsKey} {
		if container == "" {
			continue
		}
		hostPath := containerToHostPath(projDir, container)
		if _, statErr := os.Stat(hostPath); statErr != nil {
			continue
		}
		dst := filepath.Join(archiveDir, filepath.Base(hostPath))
		if err := os.Rename(hostPath, dst); err != nil {
			return fmt.Errorf("archive %s → %s: %w", hostPath, dst, err)
		}
		fmt.Printf("✓ Archived %s → %s\n", hostPath, dst)
	}

	// Unset env vars.
	cfgPath := filepath.Join(projDir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return err
	}
	f.Set("TLS_CERT_FILE", "")
	f.Set("TLS_KEY_FILE", "")
	if err := f.Save(); err != nil {
		return err
	}
	fmt.Println("✓ .env.config cleared (TLS_CERT_FILE=, TLS_KEY_FILE=)")

	// Regenerate + restart.
	if err := config.Generate(false); err != nil {
		return fmt.Errorf("config generate: %w", err)
	}
	fmt.Println("✓ Configuration regenerated")
	if err := runCmdDir(projDir, "docker", "compose", "restart", "proxy"); err != nil {
		return fmt.Errorf("docker compose restart proxy: %w", err)
	}
	fmt.Println("✓ Caddy restarted")

	fmt.Println()
	fmt.Println("Caddy will request a new ACME certificate from Let's Encrypt on the next HTTPS request.")
	fmt.Println("Run ./sb cert show in a few minutes to inspect the auto-issued cert.")
	return nil
}

// ─── Helpers ───────────────────────────────────────────────────────────

// readModeAndCertEnv loads .env.config and returns the four values
// every cert subcommand needs. Centralised so the error message is
// uniform when .env.config is missing.
func readModeAndCertEnv(projDir string) (mode, siteDomain, tlsCert, tlsKey string, err error) {
	cfgPath := filepath.Join(projDir, ".env.config")
	f, loadErr := dotenv.Load(cfgPath)
	if loadErr != nil {
		err = fmt.Errorf("load .env.config: %w", loadErr)
		return
	}
	mode, _ = f.Get("CADDY_DEPLOYMENT_MODE")
	if mode == "" {
		mode = "development"
	}
	siteDomain, _ = f.Get("SITE_DOMAIN")
	tlsCert, _ = f.Get("TLS_CERT_FILE")
	tlsKey, _ = f.Get("TLS_KEY_FILE")
	return
}

// containerToHostPath maps a Caddy-container path (/data/...) back
// to a host-filesystem path under caddy/data/. Used by show + remove
// to read / archive cert files that .env.config references by
// container path.
//
// Falls back to treating the input as already-host-relative if it
// doesn't start with /data/ (defensive — operator might have set
// TLS_CERT_FILE to a non-conventional path).
func containerToHostPath(projDir, containerPath string) string {
	if strings.HasPrefix(containerPath, "/data/") {
		return filepath.Join(projDir, "caddy", "data", strings.TrimPrefix(containerPath, "/data/"))
	}
	if filepath.IsAbs(containerPath) {
		return containerPath
	}
	return filepath.Join(projDir, containerPath)
}

// findACMECert scans Caddy's ACME storage for a leaf cert matching
// siteDomain. Returns the host path or "" if not found. Caddy stores
// per-domain certs at
// caddy/data/caddy/certificates/<issuer-dir>/<domain>/<domain>.crt
// — we walk the storage to find the first match.
func findACMECert(projDir, siteDomain string) string {
	base := filepath.Join(projDir, acmeCertStorageDir)
	var found string
	_ = filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			// Walk errors (permission denied, missing dir) are
			// expected during fresh installs; swallow and
			// continue the walk.
			return nil
		}
		if d.IsDir() {
			return nil
		}
		name := d.Name()
		if !strings.HasSuffix(name, ".crt") {
			return nil
		}
		// Caddy names the leaf as <domain>.crt.
		if siteDomain != "" && name == siteDomain+".crt" {
			found = path
			return errors.New("done") // stop walk early
		}
		// Fall back: any .crt that's not an issuer chain file.
		if !strings.HasSuffix(name, ".issuer.crt") && !strings.HasSuffix(name, ".chain.crt") && found == "" {
			found = path
		}
		return nil
	})
	return found
}

// parseLeafCert opens a PEM file, parses every CERTIFICATE block,
// and builds a certInfo from the leaf (first block).
func parseLeafCert(path string) (certInfo, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return certInfo{}, err
	}
	chain, err := parsePEMChain(data)
	if err != nil {
		return certInfo{}, fmt.Errorf("parse %s: %w", path, err)
	}
	return buildCertInfo(chain), nil
}

// buildCertInfo derives the displayable info from a parsed chain.
// Leaf is chain[0]; chain depth is len(chain).
func buildCertInfo(chain []*x509.Certificate) certInfo {
	leaf := chain[0]
	return certInfo{
		Issuer:     leaf.Issuer.CommonName,
		Subject:    leaf.Subject.CommonName,
		SANs:       leaf.DNSNames,
		NotBefore:  leaf.NotBefore,
		NotAfter:   leaf.NotAfter,
		ChainDepth: len(chain),
		SHA256:     sha256.Sum256(leaf.Raw),
	}
}

// fingerprintHex formats a SHA-256 digest as colon-separated hex
// (canonical X.509 fingerprint shape, easy to compare visually to
// `openssl x509 -fingerprint` output).
func fingerprintHex(sum [32]byte) string {
	var sb strings.Builder
	for i, b := range sum {
		if i > 0 {
			sb.WriteByte(':')
		}
		fmt.Fprintf(&sb, "%02x", b)
	}
	return sb.String()
}

// sanitiseBaseName derives a filesystem-safe basename from an input
// path: lowercase, spaces → hyphens, strip non-alphanumeric-hyphen.
// Mirrors ops/convert-pfx-cert.sh's `tr` chain.
func sanitiseBaseName(path string) string {
	base := filepath.Base(path)
	// Strip extension. Guard against dotfiles where filepath.Ext
	// returns the entire basename (e.g. ".hiddencert" has Ext=".hiddencert")
	// — for those, the "extension" is really the name; don't strip.
	if ext := filepath.Ext(base); ext != "" && ext != base {
		base = strings.TrimSuffix(base, ext)
	}
	base = strings.TrimPrefix(base, ".")
	base = strings.ToLower(base)
	base = strings.ReplaceAll(base, " ", "-")
	var sb strings.Builder
	for _, r := range base {
		switch {
		case r >= 'a' && r <= 'z':
			sb.WriteRune(r)
		case r >= '0' && r <= '9':
			sb.WriteRune(r)
		case r == '-':
			sb.WriteRune(r)
		}
	}
	out := sb.String()
	if out == "" {
		out = "cert"
	}
	return out
}

// readPassword prompts on stderr and reads a password from stdin
// without echo. Falls back to a non-echoing read on stderr if
// stdin isn't a terminal (script-driven install: operator piped
// password via a here-doc; we just take whatever's on the line).
func readPassword(prompt string) (string, error) {
	fmt.Fprint(os.Stderr, prompt)
	defer fmt.Fprintln(os.Stderr)
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		// Non-interactive — read a line from stdin without
		// trying to disable echo (would error on non-tty fd).
		var line string
		_, err := fmt.Fscanln(os.Stdin, &line)
		if err != nil {
			return "", err
		}
		return line, nil
	}
	bytes, err := term.ReadPassword(int(os.Stdin.Fd()))
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

