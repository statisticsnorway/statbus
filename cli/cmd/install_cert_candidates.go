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

// The name-only search that feeds the installer's certificate picker
// (tmp/picker-proto/PROPOSAL.md). It reads directory entries and file
// metadata, never file contents, so it needs no password and touches no
// secret. Only the folder chooser inspects contents afterwards.
const (
	certCandidateMaxSize  = 200 * 1024
	certSearchHomeDepth   = 4
	certSearchEtcSSLDepth = 2
)

// certSearchExtensions are the file-name suffixes a certificate can arrive
// with. The search never trusts them as proof of content.
var certSearchExtensions = []string{".pfx", ".p12", ".pem", ".crt", ".cer"}

// certSearchSkippedNames are directory names that never hold an operator's
// certificate but can be large (or unreadable) to walk.
var certSearchSkippedNames = map[string]bool{
	".git":         true,
	".cache":       true,
	"node_modules": true,
}

// certSearchRoot is one place the picker looks, and how many directory levels
// below it may descend. A file directly inside the root is at level 0.
type certSearchRoot struct {
	Path     string
	MaxDepth int
}

// certCandidateFolder is one folder holding name-matched certificate files.
// Newest is the latest modification time among its candidates, which orders
// the list: the certificate an operator just copied in comes first.
type certCandidateFolder struct {
	Path   string
	Files  []string
	Newest time.Time
}

// certCandidateRoots is the seam the picker tests use to keep the search
// inside a temporary home instead of the machine's real /etc/ssl.
var certCandidateRoots = func(home string) []certSearchRoot {
	return []certSearchRoot{
		{Path: home, MaxDepth: certSearchHomeDepth},
		{Path: "/etc/ssl", MaxDepth: certSearchEtcSSLDepth},
	}
}

// findCertificateCandidates is the seam askInstallCert uses; tests replace it
// (or certCandidateRoots) to control where the list comes from.
var findCertificateCandidates = func(home string) []certCandidateFolder {
	return findCertCandidates(certCandidateRoots(home), filepath.Join(home, "statbus"))
}

// findCertCandidates collects the folders under roots that hold a certificate
// by name, skipping installDir (the checkout's own test certificates are not
// the operator's) and the well-known noise directories. Unreadable folders are
// skipped silently: the operator asked for a list, not for a filesystem audit.
func findCertCandidates(roots []certSearchRoot, installDir string) []certCandidateFolder {
	byFolder := map[string]*certCandidateFolder{}
	for _, root := range roots {
		if root.Path == "" {
			continue
		}
		collectCertCandidates(root.Path, 0, root.MaxDepth, installDir, byFolder)
	}
	folders := make([]certCandidateFolder, 0, len(byFolder))
	for _, folder := range byFolder {
		sort.Strings(folder.Files)
		folders = append(folders, *folder)
	}
	sort.Slice(folders, func(i, j int) bool {
		if !folders[i].Newest.Equal(folders[j].Newest) {
			return folders[i].Newest.After(folders[j].Newest)
		}
		return folders[i].Path < folders[j].Path
	})
	return folders
}

// collectCertCandidates walks one directory tree. depth counts levels below
// the root; a directory at maxDepth is still scanned, but not descended into.
func collectCertCandidates(dir string, depth, maxDepth int, installDir string, byFolder map[string]*certCandidateFolder) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		path := filepath.Join(dir, entry.Name())
		if entry.IsDir() {
			if depth >= maxDepth || certSearchSkippedNames[entry.Name()] || path == installDir {
				continue
			}
			collectCertCandidates(path, depth+1, maxDepth, installDir, byFolder)
			continue
		}
		if !certCandidateName(entry.Name()) {
			continue
		}
		info, statErr := os.Stat(path) // follows a symlink to the real certificate
		if statErr != nil || info.IsDir() || info.Size() >= certCandidateMaxSize {
			continue
		}
		folder := byFolder[dir]
		if folder == nil {
			folder = &certCandidateFolder{Path: dir}
			byFolder[dir] = folder
		}
		folder.Files = append(folder.Files, entry.Name())
		if info.ModTime().After(folder.Newest) {
			folder.Newest = info.ModTime()
		}
	}
}

// certCandidateName reports whether a file name carries a certificate suffix.
func certCandidateName(name string) bool {
	ext := strings.ToLower(filepath.Ext(name))
	for _, candidate := range certSearchExtensions {
		if ext == candidate {
			return true
		}
	}
	return false
}

// displayCertPath shortens a path under home to ~/..., keeping the list short
// enough to fit a terminal and hiding which user's home it was.
func displayCertPath(path, home string) string {
	if home == "" {
		return path
	}
	if path == home {
		return "~"
	}
	if strings.HasPrefix(path, home+string(filepath.Separator)) {
		return "~/" + filepath.ToSlash(strings.TrimPrefix(path, home+string(filepath.Separator)))
	}
	return path
}

// renderCertificateFolderChoices is the numbered list: newest folder first,
// its candidate file names, then the escape hatch to type any path.
func renderCertificateFolderChoices(folders []certCandidateFolder, home string) []string {
	lines := []string{"  Certificates found:"}
	for i, folder := range folders {
		lines = append(lines, fmt.Sprintf("  %d) %s   %s", i+1, displayCertPath(folder.Path, home), strings.Join(folder.Files, ", ")))
	}
	lines = append(lines, fmt.Sprintf("  %d) Another file or folder (type a path)", len(folders)+1))
	return lines
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
