package cmd

import (
	"crypto/x509"
	"encoding/pem"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

// Manual box, November 9 at 10:32 UTC: the operator was handed the test
// certificate while the installer waited at its certificate prompt, and its CA
// joined the box's trust store then. The installer had already made HTTPS
// requests (the GitHub signing-key fetch), and Go reads the system trust store
// once per process, so the final site check still refused the certificate as
// "not trusted" although the server trusted it. The site check must verify
// against the trust store as it is when it runs.
func TestSiteCheckTrustsACAAddedDuringTheInstall(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("the installer runs on Linux, where the trust store is the system CA bundle file; run this in CI or a Linux container")
	}
	ca, caKey, _ := visitTestCA(t)
	now := time.Now()
	leaf := visitTestLeaf(t, ca, caKey, []string{"statbus.example.org"}, now.Add(-time.Hour), now.Add(time.Hour))
	port, _ := startVisitTestServer(t, &leaf, http.StatusOK)

	// The trust store as the install starts: another CA only.
	other, _, _ := visitTestCA(t)
	bundle := filepath.Join(t.TempDir(), "ca-certificates.crt")
	writePEM(t, bundle, other)
	t.Setenv("SSL_CERT_FILE", bundle)
	t.Setenv("SSL_CERT_DIR", t.TempDir())
	// An early HTTPS request reads the trust store, as the signer fetch does.
	if _, err := visitSystemRoots(); err != nil {
		t.Fatal(err)
	}

	// The certificate's CA joins the trust store mid-install.
	writePEM(t, bundle, other, ca)

	check := visitCheck{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}
	if reason := probeVisit(check); reason != "" {
		t.Fatalf("site check refused a certificate the trust store now accepts: %s", reason)
	}
}

func writePEM(t *testing.T, path string, certs ...*x509.Certificate) {
	t.Helper()
	var data []byte
	for _, c := range certs {
		data = append(data, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: c.Raw})...)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}
