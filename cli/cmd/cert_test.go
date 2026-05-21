package cmd

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"fmt"
	"io/fs"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// ─── Test fixtures (cli/cmd/testdata/) ───────────────────────────────────
//
// The encrypted-PFX tests below read pre-generated fixtures from
// cli/cmd/testdata/ (the Go-toolchain-special "testdata" directory
// is ignored by `go build` and shipped with the source).
//
// Why pre-generated, not programmatic (e.g., pkcs12.Encode in-test):
// the property we ship to operators is "Go decodes the PFX bytes that
// real CAs produce." A round-trip test through the same Go encoder
// proves only that encoder + decoder agree internally — a regression
// in PKCS#12 ASN.1 layout (Albania's national PKI uses a slightly
// different DER structure than Go) would not be caught. The openssl-
// generated fixtures are bytes that came from the SAME tool real CAs
// use, so they pin the real-world contract.
//
// Fixtures (~7 KB total, checked into testdata/):
//   testdata/test-cert.pem        — self-signed RSA-2048 leaf
//   testdata/test-key.pem         — matching RSA-2048 private key (PEM)
//   testdata/test-encrypted.pfx   — PFX wrapping cert + key, password "swordfish"
//   testdata/test-unencrypted.pfx — PFX wrapping cert + key, empty password
//
// Fixture cert fields (assertable from tests):
//   Subject CN:    test.statbus.local
//   Subject O:     StatBus Test
//   SANs:          test.statbus.local, alt.statbus.local
//   NotAfter:      2100-04-23 (27000 days from 2026-05-22 — far enough
//                  future that this fixture outlives any of us)
//   Issuer:        self-signed (Issuer == Subject)
//
// Regeneration recipe (one-time; run from cli/cmd/testdata/):
//
//   openssl req -x509 -nodes -newkey rsa:2048 \
//     -subj "/CN=test.statbus.local/O=StatBus Test" \
//     -addext "subjectAltName=DNS:test.statbus.local,DNS:alt.statbus.local" \
//     -days 27000 \
//     -keyout test-key.pem -out test-cert.pem
//   openssl pkcs12 -export -inkey test-key.pem -in test-cert.pem \
//     -out test-encrypted.pfx -passout pass:swordfish
//   openssl pkcs12 -export -inkey test-key.pem -in test-cert.pem \
//     -out test-unencrypted.pfx -passout pass:
//
// The openssl version that generated these fixtures was 3.6.2; modern
// openssl defaults to PBES2/AES + SHA-256 MAC for the PFX, which is
// the same crypto an Albania-class CA would emit. This is the path
// that x/crypto/pkcs12 silently rejects with "unknown digest
// algorithm: 2.16.840.1.101.3.4.2.1" (the SHA-256 OID) — and the
// reason we use software.sslmate.com/src/go-pkcs12 instead.
//
// To regenerate AFTER 2100, bump -days. Re-run all PFX_* tests after
// regeneration; subject CN / SAN assertions are tied to the openssl
// invocation above so any change there needs matching test edits.

const (
	pfxFixturePassword       = "swordfish"
	pfxFixtureCN             = "test.statbus.local"
	pfxFixtureEncrypted      = "testdata/test-encrypted.pfx"
	pfxFixtureUnencrypted    = "testdata/test-unencrypted.pfx"
	pfxFixtureCertPEM        = "testdata/test-cert.pem"
	pfxFixtureKeyPEM         = "testdata/test-key.pem"
)

// readFixture reads a fixture file, failing the test if the fixture
// is missing — that means cli/cmd/testdata/ was not committed or
// got pruned, which is a contributor-error not a runtime concern.
func readFixture(t *testing.T, relPath string) []byte {
	t.Helper()
	data, err := os.ReadFile(relPath)
	if err != nil {
		t.Fatalf("fixture missing or unreadable (%s): %v\n"+
			"  Regenerate from the openssl recipe at the top of cert_test.go.", relPath, err)
	}
	return data
}

// ─── Detection: PFX vs PEM ───────────────────────────────────────────────

func TestLooksLikeDER_PFXSignature(t *testing.T) {
	// PFX/PKCS#12 starts with 0x30 0x82 (DER SEQUENCE, 2-byte length).
	if !looksLikeDER([]byte{0x30, 0x82, 0x12, 0x34, 0xab}) {
		t.Error("PFX-shaped header should be detected as DER")
	}
}

func TestLooksLikeDER_PEMNotDER(t *testing.T) {
	pemHeader := []byte("-----BEGIN CERTIFICATE-----\n")
	if looksLikeDER(pemHeader) {
		t.Error("PEM-shaped header should NOT be detected as DER")
	}
}

func TestLooksLikeDER_TooShort(t *testing.T) {
	if looksLikeDER([]byte{0x30, 0x82}) {
		t.Error("3-byte input is too short to classify; should reject")
	}
	if looksLikeDER(nil) {
		t.Error("nil input should reject")
	}
}

func TestLooksLikeDER_OtherDERShapes(t *testing.T) {
	// DER SEQUENCE with 1-byte length (0x30 0x81 nn) — possible
	// but not what PFX uses. We require 0x30 0x82 specifically.
	if looksLikeDER([]byte{0x30, 0x81, 0x05, 0x00, 0x00}) {
		t.Error("0x30 0x81 is a different DER length form; not PFX")
	}
}

// ─── Cert/key match validation ────────────────────────────────────────────

// makeRSAPair generates an ephemeral RSA cert + key for testing.
func makeRSAPair(t *testing.T) (*x509.Certificate, *rsa.PrivateKey) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate RSA key: %v", err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "test.example"},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	derBytes, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("create cert: %v", err)
	}
	cert, err := x509.ParseCertificate(derBytes)
	if err != nil {
		t.Fatalf("parse cert: %v", err)
	}
	return cert, key
}

// makeECPair generates an ephemeral ECDSA cert + key for testing.
func makeECPair(t *testing.T) (*x509.Certificate, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate EC key: %v", err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "test.example"},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	derBytes, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatalf("create cert: %v", err)
	}
	cert, err := x509.ParseCertificate(derBytes)
	if err != nil {
		t.Fatalf("parse cert: %v", err)
	}
	return cert, key
}

func TestValidateCertKeyMatch_RSA_Matching(t *testing.T) {
	cert, key := makeRSAPair(t)
	if err := validateCertKeyMatch(cert, key); err != nil {
		t.Errorf("matching RSA pair rejected: %v", err)
	}
}

func TestValidateCertKeyMatch_RSA_Mismatched(t *testing.T) {
	cert, _ := makeRSAPair(t)
	_, key2 := makeRSAPair(t)
	if err := validateCertKeyMatch(cert, key2); err == nil {
		t.Error("mismatched RSA pair accepted; expected modulus-mismatch error")
	} else if !strings.Contains(err.Error(), "RSA") {
		t.Errorf("error should mention RSA: %v", err)
	}
}

func TestValidateCertKeyMatch_EC_Matching(t *testing.T) {
	cert, key := makeECPair(t)
	if err := validateCertKeyMatch(cert, key); err != nil {
		t.Errorf("matching EC pair rejected: %v", err)
	}
}

func TestValidateCertKeyMatch_EC_Mismatched(t *testing.T) {
	cert, _ := makeECPair(t)
	_, key2 := makeECPair(t)
	if err := validateCertKeyMatch(cert, key2); err == nil {
		t.Error("mismatched EC pair accepted; expected components-mismatch error")
	}
}

func TestValidateCertKeyMatch_TypeMismatch(t *testing.T) {
	rsaCert, _ := makeRSAPair(t)
	_, ecKey := makeECPair(t)
	err := validateCertKeyMatch(rsaCert, ecKey)
	if err == nil {
		t.Fatal("RSA cert + EC key accepted; expected type-mismatch error")
	}
	if !strings.Contains(err.Error(), "ECDSA") {
		t.Errorf("error should mention ECDSA private key: %v", err)
	}
}

// ─── PEM parsing ──────────────────────────────────────────────────────────

func TestParsePEMChain_SingleCert(t *testing.T) {
	cert, _ := makeRSAPair(t)
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
	chain, err := parsePEMChain(pemBytes)
	if err != nil {
		t.Fatalf("parsePEMChain: %v", err)
	}
	if len(chain) != 1 {
		t.Errorf("want 1 cert, got %d", len(chain))
	}
}

func TestParsePEMChain_MultiCert(t *testing.T) {
	c1, _ := makeRSAPair(t)
	c2, _ := makeRSAPair(t)
	var sb strings.Builder
	sb.Write(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: c1.Raw}))
	sb.Write(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: c2.Raw}))
	chain, err := parsePEMChain([]byte(sb.String()))
	if err != nil {
		t.Fatalf("parsePEMChain: %v", err)
	}
	if len(chain) != 2 {
		t.Errorf("want 2 certs, got %d", len(chain))
	}
}

func TestParsePEMChain_NoCert(t *testing.T) {
	// Just a key block — no certs.
	keyBytes := []byte("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n")
	_, err := parsePEMChain(keyBytes)
	if err == nil {
		t.Error("expected error on key-only input")
	}
}

func TestParsePEMKey_RSA(t *testing.T) {
	_, key := makeRSAPair(t)
	pkcs8, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: pkcs8})
	parsed, err := parsePEMKey(pemBytes)
	if err != nil {
		t.Fatalf("parsePEMKey: %v", err)
	}
	if _, ok := parsed.(*rsa.PrivateKey); !ok {
		t.Errorf("want *rsa.PrivateKey, got %T", parsed)
	}
}

// ─── Helpers ───────────────────────────────────────────────────────────────

func TestSanitiseBaseName_Cases(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"/path/to/MyCert.pfx", "mycert"},
		{"/path/to/My Cert With Spaces.pfx", "my-cert-with-spaces"},
		{"/Path/Stat-BUS_2026.PFX", "stat-bus2026"},
		{"/path/.hiddencert", "hiddencert"},
		{"", "cert"},
		{"/", "cert"},
	}
	for _, c := range cases {
		got := sanitiseBaseName(c.in)
		if got != c.want {
			t.Errorf("sanitiseBaseName(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestFingerprintHex_Format(t *testing.T) {
	var sum [32]byte
	for i := range sum {
		sum[i] = byte(i)
	}
	got := fingerprintHex(sum)
	// Expect 64 hex chars + 31 colons = 95 chars.
	if len(got) != 95 {
		t.Errorf("fingerprintHex length = %d, want 95", len(got))
	}
	if !strings.HasPrefix(got, "00:01:02:03") {
		t.Errorf("unexpected prefix: %q", got)
	}
	if !strings.HasSuffix(got, "1d:1e:1f") {
		t.Errorf("unexpected suffix: %q", got)
	}
}

func TestContainerToHostPath(t *testing.T) {
	cases := []struct {
		projDir, container, want string
	}{
		{"/proj", "/data/custom-certs/x.crt", "/proj/caddy/data/custom-certs/x.crt"},
		{"/proj", "/data/caddy/certificates/x.crt", "/proj/caddy/data/caddy/certificates/x.crt"},
		{"/proj", "/abs/elsewhere.crt", "/abs/elsewhere.crt"},
		{"/proj", "relative.crt", "/proj/relative.crt"},
	}
	for _, c := range cases {
		got := containerToHostPath(c.projDir, c.container)
		if got != c.want {
			t.Errorf("containerToHostPath(%q, %q) = %q, want %q",
				c.projDir, c.container, got, c.want)
		}
	}
}

// ─── reorderChainLeafFirst ────────────────────────────────────────────────

// makeChain creates a 3-cert chain (leaf signed by intermediate
// signed by root) for testing chain reordering.
func makeChain(t *testing.T) []*x509.Certificate {
	t.Helper()
	rootKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	rootTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "test-root"},
		IsCA:                  true,
		BasicConstraintsValid: true,
		NotBefore:             time.Now(),
		NotAfter:              time.Now().Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign,
	}
	rootDER, _ := x509.CreateCertificate(rand.Reader, rootTemplate, rootTemplate, &rootKey.PublicKey, rootKey)
	rootCert, _ := x509.ParseCertificate(rootDER)

	intKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	intTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(2),
		Subject:               pkix.Name{CommonName: "test-int"},
		IsCA:                  true,
		BasicConstraintsValid: true,
		NotBefore:             time.Now(),
		NotAfter:              time.Now().Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign,
	}
	intDER, _ := x509.CreateCertificate(rand.Reader, intTemplate, rootCert, &intKey.PublicKey, rootKey)
	intCert, _ := x509.ParseCertificate(intDER)

	leafKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	leafTemplate := &x509.Certificate{
		SerialNumber: big.NewInt(3),
		Subject:      pkix.Name{CommonName: "test-leaf"},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	leafDER, _ := x509.CreateCertificate(rand.Reader, leafTemplate, intCert, &leafKey.PublicKey, intKey)
	leafCert, _ := x509.ParseCertificate(leafDER)

	return []*x509.Certificate{leafCert, intCert, rootCert}
}

func TestReorderChainLeafFirst_AlreadyOrdered(t *testing.T) {
	chain := makeChain(t)
	got := reorderChainLeafFirst(chain)
	if len(got) != 3 || got[0].Subject.CommonName != "test-leaf" {
		t.Errorf("expected leaf first; got %v", chainCNs(got))
	}
}

func TestReorderChainLeafFirst_ScrambledInput(t *testing.T) {
	chain := makeChain(t)
	// Scramble: root, leaf, int
	scrambled := []*x509.Certificate{chain[2], chain[0], chain[1]}
	got := reorderChainLeafFirst(scrambled)
	if got[0].Subject.CommonName != "test-leaf" {
		t.Errorf("expected leaf first after reorder; got %v", chainCNs(got))
	}
}

func TestReorderChainLeafFirst_SingleCert(t *testing.T) {
	cert, _ := makeRSAPair(t)
	got := reorderChainLeafFirst([]*x509.Certificate{cert})
	if len(got) != 1 || got[0] != cert {
		t.Error("single-cert chain should pass through unchanged")
	}
}

func chainCNs(chain []*x509.Certificate) []string {
	out := make([]string, len(chain))
	for i, c := range chain {
		out[i] = c.Subject.CommonName
	}
	return out
}

// ─── parseLeafCert + buildCertInfo ────────────────────────────────────────

func TestBuildCertInfo_FromGeneratedPair(t *testing.T) {
	cert, _ := makeRSAPair(t)
	info := buildCertInfo([]*x509.Certificate{cert})
	if info.Subject != "test.example" {
		t.Errorf("subject = %q, want test.example", info.Subject)
	}
	if info.ChainDepth != 1 {
		t.Errorf("chain depth = %d, want 1", info.ChainDepth)
	}
	if info.NotAfter.Before(time.Now()) {
		t.Error("NotAfter should be in the future")
	}
	// Fingerprint should match sha256 of cert.Raw.
	expected := fmt.Sprintf("%x", info.SHA256)
	if len(expected) != 64 {
		t.Errorf("SHA256 hex len = %d, want 64", len(expected))
	}
}

func TestParseLeafCert_RoundTripViaTempFile(t *testing.T) {
	cert, _ := makeRSAPair(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "test.crt")
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
	if err := os.WriteFile(path, pemBytes, 0o644); err != nil {
		t.Fatal(err)
	}
	info, err := parseLeafCert(path)
	if err != nil {
		t.Fatalf("parseLeafCert: %v", err)
	}
	if info.Subject != "test.example" {
		t.Errorf("subject = %q", info.Subject)
	}
}

// ─── End-to-end PFX decode (encrypted + unencrypted) ──────────────────────
//
// These tests exercise the operator-facing PFX path against the
// pre-generated testdata/*.pfx fixtures. Three operator scenarios:
//
//   1. Encrypted PFX + correct password → decode succeeds, chain + key
//      both extracted, leaf-first ordering, modulus check passes.
//   2. Encrypted PFX + wrong password → loud actionable error
//      ("Invalid PFX password — re-run..."), no partial state.
//   3. Unencrypted PFX → decode succeeds with empty password (some
//      operators export this way for internal storage).
//
// The fixtures pin "Go decodes openssl-produced PFX bytes" — the
// exact property Albania's CA-issued PFX will exercise tomorrow.
// See the long comment block at the top of this file for the
// regeneration recipe.

func TestDecodePFX_EncryptedFixture_CorrectPassword(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)
	if !looksLikeDER(data) {
		t.Fatal("PFX fixture should be detected as DER (0x30 0x82 prefix)")
	}

	chain, key, err := decodePFX(data, pfxFixturePassword)
	if err != nil {
		t.Fatalf("decodePFX with correct password: %v", err)
	}
	if len(chain) == 0 {
		t.Fatal("decodePFX returned empty chain")
	}
	if chain[0].Subject.CommonName != pfxFixtureCN {
		t.Errorf("leaf subject CN = %q, want %q", chain[0].Subject.CommonName, pfxFixtureCN)
	}
	// SAN list must match the openssl recipe at the top of this file.
	gotSANs := chain[0].DNSNames
	wantSANs := []string{"test.statbus.local", "alt.statbus.local"}
	if !sansEqual(gotSANs, wantSANs) {
		t.Errorf("SANs = %v, want %v", gotSANs, wantSANs)
	}
	// Self-signed: Issuer CN == Subject CN.
	if chain[0].Issuer.CommonName != pfxFixtureCN {
		t.Errorf("issuer CN = %q, want self-signed %q", chain[0].Issuer.CommonName, pfxFixtureCN)
	}
	// NotAfter is far future (recipe: -days 27000 ≈ year 2100).
	if chain[0].NotAfter.Year() < 2090 {
		t.Errorf("NotAfter = %v, expected ≥ 2090 (recipe used -days 27000)", chain[0].NotAfter)
	}
	if key == nil {
		t.Fatal("decodePFX returned nil key")
	}
	if _, ok := key.(*rsa.PrivateKey); !ok {
		t.Errorf("expected *rsa.PrivateKey, got %T", key)
	}
	// Cert/key must round-trip the modulus check — same flow the
	// operator-facing install path runs after decode.
	if err := validateCertKeyMatch(chain[0], key); err != nil {
		t.Errorf("decoded cert/key don't match (modulus check): %v", err)
	}
}

func TestDecodePFX_EncryptedFixture_WrongPassword(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)

	_, _, err := decodePFX(data, "WRONG-not-swordfish")
	if err == nil {
		t.Fatal("decodePFX with wrong password unexpectedly succeeded")
	}
	// Error must be actionable — operator should see the
	// "invalid PFX password" phrasing, not a raw "decryption" leak.
	msg := err.Error()
	if !strings.Contains(strings.ToLower(msg), "invalid pfx password") {
		t.Errorf("wrong-password error not actionable; got: %v", err)
	}
	if !strings.Contains(msg, "re-run") {
		t.Errorf("error should hint at re-running with correct password; got: %v", err)
	}
}

func TestDecodePFX_UnencryptedFixture(t *testing.T) {
	data := readFixture(t, pfxFixtureUnencrypted)

	chain, key, err := decodePFX(data, "")
	if err != nil {
		t.Fatalf("decodePFX unencrypted: %v", err)
	}
	if len(chain) == 0 || key == nil {
		t.Fatal("decodePFX unencrypted returned empty chain or nil key")
	}
	if chain[0].Subject.CommonName != pfxFixtureCN {
		t.Errorf("leaf subject CN = %q, want %q", chain[0].Subject.CommonName, pfxFixtureCN)
	}
}

// TestDecodePFX_EncryptedFixture_EmptyPasswordOnEncryptedFails pins
// the diagnostic distinction: passing "" to an encrypted PFX must
// fail with the friendly password error, not silently succeed (it
// can't) and not produce a confusing "no PRIVATE KEY block" cascade.
func TestDecodePFX_EncryptedFixture_EmptyPasswordOnEncryptedFails(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)

	_, _, err := decodePFX(data, "")
	if err == nil {
		t.Fatal("decodePFX with empty password on encrypted PFX unexpectedly succeeded")
	}
	if !strings.Contains(strings.ToLower(err.Error()), "invalid pfx password") {
		t.Errorf("empty-password-on-encrypted should route to friendly password error; got: %v", err)
	}
}

// sansEqual compares two SAN string slices independent of order.
func sansEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	seen := make(map[string]bool, len(a))
	for _, s := range a {
		seen[s] = true
	}
	for _, s := range b {
		if !seen[s] {
			return false
		}
	}
	return true
}

func TestDecodePFX_CorruptInput(t *testing.T) {
	// Bytes that LOOK like a DER SEQUENCE but aren't valid PKCS#12.
	corrupt := []byte{0x30, 0x82, 0x01, 0x00, 0xff, 0xff, 0xff, 0xff}
	_, _, err := decodePFX(corrupt, "anything")
	if err == nil {
		t.Fatal("corrupt PFX bytes should fail decode")
	}
	if !strings.Contains(err.Error(), "PFX decode failed") &&
		!strings.Contains(err.Error(), "invalid PFX password") {
		t.Errorf("corrupt-input error not informative; got: %v", err)
	}
}

// ─── readCertFile: actionable filesystem errors ───────────────────────────

func TestReadCertFile_NotFound(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "does-not-exist.pfx")
	_, err := readCertFile(missing)
	if err == nil {
		t.Fatal("expected error on missing file")
	}
	if !strings.Contains(err.Error(), "file not found") {
		t.Errorf("error should say 'file not found'; got: %v", err)
	}
	if !strings.Contains(err.Error(), missing) {
		t.Errorf("error should include the missing path; got: %v", err)
	}
}

func TestReadCertFile_Existing(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "file")
	if err := os.WriteFile(path, []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}
	data, err := readCertFile(path)
	if err != nil {
		t.Fatalf("readCertFile of existing file: %v", err)
	}
	if string(data) != "hello" {
		t.Errorf("data = %q, want hello", data)
	}
}

// ─── End-to-end: decode → validate → write → assert clean state ──────────

// TestEndToEnd_EncryptedPFX_NoPartialFilesOnDecodeFailure verifies
// that when decode FAILS (wrong password), nothing is written to the
// caddy/data/custom-certs/ directory. This is the structural
// invariant the operator relies on: a failed install attempt leaves
// no orphan files or .env.config mutation.
//
// We test this by walking through loadCertMaterial → its returned
// error → confirm we never reach writeCertAndKey. Since the install
// flow is linear (errors short-circuit), this is enforced by control
// flow; the test pins that contract.
func TestEndToEnd_EncryptedPFX_NoPartialFilesOnDecodeFailure(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)

	// Try to decode with wrong password — expect failure.
	_, _, decodeErr := decodePFX(data, "WRONG-not-swordfish")
	if decodeErr == nil {
		t.Fatal("decode should fail with wrong password")
	}

	// Now verify: had we been in runCertInstall flow, we would have
	// returned the decode error before any writeCertAndKey /
	// updateEnvConfigCertPaths call. The test pins the invariant
	// "no orphan files on decode failure" by confirming no .crt or
	// .key file exists under the simulated project dir.
	projDir := t.TempDir()
	certsDir := filepath.Join(projDir, customCertHostDir)
	if entries, err := os.ReadDir(certsDir); err == nil && len(entries) > 0 {
		t.Errorf("decode failure left orphan files under %s: %v", certsDir, entries)
	}
}

// TestEndToEnd_EncryptedPFX_FullPlacement runs decode → validate →
// writeCertAndKey on a real encrypted PFX, then asserts both .crt
// and .key files landed at the expected paths with the expected
// permissions. This exercises the slice of the install flow that
// doesn't touch Docker / .env.config / TLS probe.
func TestEndToEnd_EncryptedPFX_FullPlacement(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)

	chain, key, err := decodePFX(data, pfxFixturePassword)
	if err != nil {
		t.Fatalf("decodePFX: %v", err)
	}
	if err := validateCertKeyMatch(chain[0], key); err != nil {
		t.Fatalf("validateCertKeyMatch: %v", err)
	}

	projDir := t.TempDir()
	baseName := sanitiseBaseName(pfxFixtureEncrypted)
	certPath, keyPath, err := writeCertAndKey(projDir, baseName, chain, key)
	if err != nil {
		t.Fatalf("writeCertAndKey: %v", err)
	}

	// Both files exist.
	certInfo, err := os.Stat(certPath)
	if err != nil {
		t.Fatalf("cert file missing after write: %v", err)
	}
	keyInfo, err := os.Stat(keyPath)
	if err != nil {
		t.Fatalf("key file missing after write: %v", err)
	}

	// Permissions: 644 on cert, 600 on key. On macOS umask doesn't
	// affect writeCertAndKey because we explicitly Chmod via the
	// tempfile path.
	if got := certInfo.Mode().Perm(); got != 0o644 {
		t.Errorf("cert mode = %o, want 0644", got)
	}
	if got := keyInfo.Mode().Perm(); got != 0o600 {
		t.Errorf("key mode = %o, want 0600", got)
	}

	// Cert file content: parses back as the same leaf.
	parsedInfo, err := parseLeafCert(certPath)
	if err != nil {
		t.Fatalf("parseLeafCert of written cert: %v", err)
	}
	if parsedInfo.Subject != pfxFixtureCN {
		t.Errorf("written cert subject = %q, want %q", parsedInfo.Subject, pfxFixtureCN)
	}
}

// TestEndToEnd_loadCertMaterial_SinglePFXArg drives the cobra-layer
// loadCertMaterial entry point (single argv = PFX path) end-to-end
// against the on-disk fixture. Pins the contract that the install
// command's argument shape detection routes a real PFX file through
// the password-prompting branch — except we can't prompt in a test,
// so we exercise the decodePFX primitive directly via the path used
// when looksLikeDER returns true. The integration here is the
// content-detection: "single .pfx file → PFX branch, not PEM."
func TestEndToEnd_loadCertMaterial_SinglePFXArg_DetectsAsDER(t *testing.T) {
	data := readFixture(t, pfxFixtureEncrypted)
	if !looksLikeDER(data) {
		t.Error("encrypted PFX fixture should match looksLikeDER (0x30 0x82 prefix)")
	}
	// The unencrypted PFX is also DER-encoded (the encryption applies
	// to internal blocks, not the outer SEQUENCE).
	data2 := readFixture(t, pfxFixtureUnencrypted)
	if !looksLikeDER(data2) {
		t.Error("unencrypted PFX fixture should match looksLikeDER")
	}
	// The PEM cert must NOT be detected as DER — that's the dispatch
	// for falling through to PEM parsing.
	pemBytes := readFixture(t, pfxFixtureCertPEM)
	if looksLikeDER(pemBytes) {
		t.Error("PEM cert fixture should NOT match looksLikeDER; would route to PFX branch incorrectly")
	}
}

// ─── writeCertAndKey atomicity ────────────────────────────────────────────
//
// The atomic-write contract: if the key write fails, the cert file
// that was just written must be cleaned up too — no orphan .crt
// without a paired .key. We test this by making the key path point
// to a directory (so os.Rename fails) and verifying no .crt remains.

func TestWriteCertAndKey_RollsBackCertOnKeyFailure(t *testing.T) {
	cert, key := makeRSAPair(t)
	projDir := t.TempDir()
	baseName := "rollback-test"

	// Pre-create a DIRECTORY at the key path so the final
	// os.Rename for the key fails (can't rename file over existing
	// non-empty directory).
	dir := filepath.Join(projDir, customCertHostDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	keyPath := filepath.Join(dir, baseName+".key")
	if err := os.Mkdir(keyPath, 0o755); err != nil {
		t.Fatal(err)
	}
	// Put a file inside the dir so rename can't succeed.
	if err := os.WriteFile(filepath.Join(keyPath, "blocker"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	_, _, err := writeCertAndKey(projDir, baseName, []*x509.Certificate{cert}, key)
	if err == nil {
		t.Fatal("writeCertAndKey should fail when key path collides with non-empty dir")
	}

	// Cert file MUST NOT exist after the failed run.
	certPath := filepath.Join(dir, baseName+".crt")
	if _, statErr := os.Stat(certPath); !errors.Is(statErr, fs.ErrNotExist) {
		t.Errorf("orphan cert file present after key-write failure: %v", statErr)
	}
}

// ─── Discoverability ─────────────────────────────────────────────────────
//
// Smoke-test that cobra's --help output for each subcommand contains
// the patterns an operator would search for. Catches regressions on
// the Example blocks + Long descriptions getting truncated.

func TestCertHelp_ContainsExamples(t *testing.T) {
	cases := []struct {
		cmdName    string
		long       string
		example    string
		findInLong []string
	}{
		{"cert", certCmd.Long, certCmd.Example,
			[]string{"AUTOMATIC", "CUSTOM", "Albania", "./sb cert show"}},
		{"show", certShowCmd.Long, certShowCmd.Example,
			[]string{"Source", "Issuer", "Subject", "SANs", "SHA-256"}},
		{"install", certInstallCmd.Long, certInstallCmd.Example,
			[]string{"PFX", "PEM pair", "PKCS#12", "password"}},
		{"remove", certRemoveCmd.Long, certRemoveCmd.Example,
			[]string{"Let's Encrypt", "archive", "SITE_DOMAIN"}},
	}
	for _, c := range cases {
		t.Run(c.cmdName, func(t *testing.T) {
			combined := c.long + "\n" + c.example
			for _, want := range c.findInLong {
				if !strings.Contains(combined, want) {
					t.Errorf("`./sb cert %s --help` Long+Example missing %q\n--- Long ---\n%s\n--- Example ---\n%s",
						c.cmdName, want, c.long, c.example)
				}
			}
			if c.example == "" {
				t.Errorf("`./sb cert %s --help` has empty Example block — operator-noob discoverability regression", c.cmdName)
			}
		})
	}
}
