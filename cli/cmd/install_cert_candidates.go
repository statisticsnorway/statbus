package cmd

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// certChoice is one certificate the folder scan can install. Args is exactly
// the input loadCertMaterialWithPassword already understands: one file (PFX or
// a PEM bundle) or a certificate file plus its key file.
type certChoice struct {
	Args        []string
	Leaf        *x509.Certificate
	ChainLength int
	Covers      bool
	Expired     bool
	NotYetValid bool
}

// resolveInstallPath turns an interactive answer into an absolute path.
// Absolute paths are kept; ~ and ~/... expand to the install user's home;
// anything relative resolves against the directory the operator ran the
// installer from (install.sh exports it before cd'ing into the checkout).
func resolveInstallPath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return ""
	}
	if path == "~" || strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			if path == "~" {
				path = home
			} else {
				path = filepath.Join(home, strings.TrimPrefix(path, "~/"))
			}
		}
	}
	if filepath.IsAbs(path) {
		return filepath.Clean(path)
	}
	caller := os.Getenv("STATBUS_INSTALL_CALLER_PWD")
	if caller == "" {
		caller, _ = os.Getwd()
	}
	return filepath.Join(caller, path)
}

// certificateFileNeedsKey inspects the first answer by content. A PFX, or a
// PEM file holding a certificate and its matching key, needs no second
// question. Only a PEM certificate without a key does.
func certificateFileNeedsKey(path string) (bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	if looksLikeDER(data) {
		return false, nil
	}
	certs, key := loosePEMContents(data)
	if len(certs) == 0 {
		return false, fmt.Errorf("no PEM certificate found")
	}
	if key != nil && validateCertKeyMatch(certs[0], key) == nil {
		return false, nil
	}
	return true, nil
}

// inspectCertificatePath resolves an interactive answer and reports whether it
// is a folder and whether a separate key question is needed. A missing path
// carries the resolved absolute path back to the operator.
func inspectCertificatePath(answer string) (resolved string, isDir, needsKey bool, err error) {
	resolved = resolveInstallPath(answer)
	info, statErr := os.Stat(resolved)
	if statErr != nil {
		return resolved, false, false, fmt.Errorf("file not found: %s", resolved)
	}
	if info.IsDir() {
		return resolved, true, false, nil
	}
	needsKey, inspectErr := certificateFileNeedsKey(resolved)
	if inspectErr != nil {
		return resolved, false, false, fmt.Errorf("could not use %s: %w", resolved, inspectErr)
	}
	return resolved, false, needsKey, nil
}

// certFolderFiles lists regular files in a folder and reports whether any of
// them is DER-shaped (a PFX/PKCS#12), which is the only case that needs a
// password question. The order is stable so the numbered list is predictable.
func certFolderFiles(folder string) (files []string, hasPFX bool, err error) {
	entries, err := os.ReadDir(folder)
	if err != nil {
		return nil, false, err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		path := filepath.Join(folder, entry.Name())
		files = append(files, path)
		if data, readErr := os.ReadFile(path); readErr == nil && looksLikeDER(data) {
			hasPFX = true
		}
	}
	sort.Strings(files)
	return files, hasPFX, nil
}

// loosePEMContents extracts every CERTIFICATE and the first private key from a
// PEM file. Unlike parsePEMBundle it tolerates files that hold only one of the
// two, which is exactly what a CA folder contains.
func loosePEMContents(data []byte) (certs []*x509.Certificate, key interface{}) {
	rest := data
	for {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		switch block.Type {
		case "CERTIFICATE":
			if cert, err := x509.ParseCertificate(block.Bytes); err == nil {
				certs = append(certs, cert)
			}
		case "RSA PRIVATE KEY", "EC PRIVATE KEY", "PRIVATE KEY":
			if key == nil {
				if parsed, err := parsePrivateKeyBlock(block); err == nil {
					key = parsed
				}
			}
		}
	}
	return certs, key
}

// scanCertificateFolder inspects every file by content, not by extension. It
// returns selectable choices and plain notes for files it cannot offer (a PFX
// the password does not open, a certificate with no key, or an unreadable
// file). The scan never prints and never handles a password beyond decoding.
func scanCertificateFolder(folder, siteDomain string, pfxPassword *string) (choices []certChoice, notes []string, err error) {
	files, _, err := certFolderFiles(folder)
	if err != nil {
		return nil, nil, err
	}
	type certFile struct {
		path  string
		chain []*x509.Certificate
	}
	type keyFile struct {
		path string
		key  interface{}
	}
	var certFiles []certFile
	var keyFiles []keyFile

	pw := ""
	if pfxPassword != nil {
		pw = *pfxPassword
	}
	for _, path := range files {
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			notes = append(notes, fmt.Sprintf("%s: could not read", filepath.Base(path)))
			continue
		}
		if looksLikeDER(data) {
			chain, key, decodeErr := decodePFX(data, pw)
			if decodeErr != nil {
				notes = append(notes, fmt.Sprintf("%s: could not open with that password", filepath.Base(path)))
				continue
			}
			if key == nil || len(chain) == 0 {
				notes = append(notes, fmt.Sprintf("%s: no certificate and private key inside", filepath.Base(path)))
				continue
			}
			choices = append(choices, certChoice{Args: []string{path}, Leaf: chain[0], ChainLength: len(chain)})
			continue
		}
		certs, key := loosePEMContents(data)
		if len(certs) > 0 {
			if key != nil && validateCertKeyMatch(certs[0], key) == nil {
				choices = append(choices, certChoice{Args: []string{path}, Leaf: certs[0], ChainLength: len(certs)})
				keyFiles = append(keyFiles, keyFile{path: path, key: key})
			} else {
				certFiles = append(certFiles, certFile{path: path, chain: certs})
			}
		} else if key != nil {
			keyFiles = append(keyFiles, keyFile{path: path, key: key})
		} else {
			notes = append(notes, fmt.Sprintf("%s: no PEM certificate or private key found", filepath.Base(path)))
		}
	}

	// Pair certificate-only PEM files with a matching key elsewhere in the
	// folder. Only a public-key match offers a pair.
	for _, cert := range certFiles {
		paired := ""
		for _, key := range keyFiles {
			if key.path != cert.path && validateCertKeyMatch(cert.chain[0], key.key) == nil {
				paired = key.path
				break
			}
		}
		if paired == "" {
			notes = append(notes, fmt.Sprintf("%s: certificate only, no matching private key found", filepath.Base(cert.path)))
			continue
		}
		choices = append(choices, certChoice{Args: []string{cert.path, paired}, Leaf: cert.chain[0], ChainLength: len(cert.chain)})
	}

	rankCertificateChoices(choices, siteDomain)
	return choices, notes, nil
}

// rankCertificateChoices puts the best usable certificate first: it covers the
// chosen site, it is currently valid, and among equals the latest expiry wins.
// Expired and non-matching choices stay in the list, marked, so the operator
// can see why they are not the default.
func rankCertificateChoices(choices []certChoice, siteDomain string) {
	now := time.Now()
	for i := range choices {
		leaf := choices[i].Leaf
		choices[i].Expired = now.After(leaf.NotAfter)
		choices[i].NotYetValid = now.Before(leaf.NotBefore)
		choices[i].Covers = siteDomain != "" && leaf.VerifyHostname(siteDomain) == nil
	}
	sort.SliceStable(choices, func(i, j int) bool {
		if choices[i].Covers != choices[j].Covers {
			return choices[i].Covers
		}
		iValid := !choices[i].Expired && !choices[i].NotYetValid
		jValid := !choices[j].Expired && !choices[j].NotYetValid
		if iValid != jValid {
			return iValid
		}
		if !choices[i].Leaf.NotAfter.Equal(choices[j].Leaf.NotAfter) {
			return choices[i].Leaf.NotAfter.After(choices[j].Leaf.NotAfter)
		}
		return strings.Join(choices[i].Args, " ") < strings.Join(choices[j].Args, " ")
	})
}

// renderCertificateChoices is the operator-facing list. The first choice is
// the default. Notes are shown after the numbered choices, never hidden.
func renderCertificateChoices(choices []certChoice, notes []string, siteDomain string) []string {
	var lines []string
	for i, choice := range choices {
		leaf := choice.Leaf
		sans := strings.Join(leaf.DNSNames, ", ")
		if sans == "" {
			sans = "(none)"
		}
		coverage := "SITE_DOMAIN not set"
		if siteDomain != "" {
			if choice.Covers {
				coverage = "covers " + siteDomain
			} else {
				coverage = "does not cover " + siteDomain
			}
		}
		flags := ""
		if i == 0 {
			flags += " [default]"
		}
		if choice.Expired {
			flags += " EXPIRED"
		}
		if choice.NotYetValid {
			flags += " not valid yet"
		}
		lines = append(lines, fmt.Sprintf("%d) %s  CN=%s  SANs: %s  expires %s  %s%s",
			i+1, strings.Join(choice.Args, " + "), leaf.Subject.CommonName, sans,
			leaf.NotAfter.Format("2006-01-02"), coverage, flags))
	}
	for _, note := range notes {
		lines = append(lines, "  - "+note)
	}
	return lines
}
