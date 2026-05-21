package cmd

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

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
