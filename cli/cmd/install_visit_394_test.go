package cmd

// STATBUS-394 AC5: after every service runs and the API answers /ready, the
// installer fetches the advertised site the way a user would — the chosen
// name, connected to this box (never DNS or hairpin routing), HTTPS verified
// against the system trust store when the certificate is ours to verify.

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// visitTestCA returns a test CA, its key, and a pool trusting it.
func visitTestCA(t *testing.T) (*x509.Certificate, *ecdsa.PrivateKey, *x509.CertPool) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "visit test CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageCertSign,
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	ca, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	pool := x509.NewCertPool()
	pool.AddCert(ca)
	return ca, key, pool
}

// visitTestLeaf issues a server certificate for names, valid in
// [notBefore, notAfter), signed by ca.
func visitTestLeaf(t *testing.T, ca *x509.Certificate, caKey *ecdsa.PrivateKey, names []string, notBefore, notAfter time.Time) tls.Certificate {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: names[0]},
		DNSNames:     names,
		NotBefore:    notBefore,
		NotAfter:     notAfter,
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, ca, &key.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	return tls.Certificate{Certificate: [][]byte{der, ca.Raw}, PrivateKey: key}
}

// startVisitTestServer serves status on 127.0.0.1 (TLS when cert is given)
// and returns its port plus a record of the Host headers it saw.
func startVisitTestServer(t *testing.T, cert *tls.Certificate, status int) (string, *[]string) {
	t.Helper()
	var hosts []string
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hosts = append(hosts, r.Host)
		w.WriteHeader(status)
	}))
	if cert != nil {
		srv.TLS = &tls.Config{Certificates: []tls.Certificate{*cert}}
		srv.StartTLS()
	} else {
		srv.Start()
	}
	t.Cleanup(srv.Close)
	_, port, err := net.SplitHostPort(srv.Listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	return port, &hosts
}

// withVisitRoots points the trust-store seam at pool for one test.
func withVisitRoots(t *testing.T, pool *x509.CertPool) {
	t.Helper()
	old := visitSystemRoots
	t.Cleanup(func() { visitSystemRoots = old })
	visitSystemRoots = func() (*x509.CertPool, error) { return pool, nil }
}

// silentPort is a loopback port nothing listens on.
func silentPort(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	_, port, err := net.SplitHostPort(l.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	if err := l.Close(); err != nil {
		t.Fatal(err)
	}
	return port
}

func TestProbeVisitClassifies_STATBUS394(t *testing.T) {
	ca, caKey, pool := visitTestCA(t)
	now := time.Now()
	goodLeaf := visitTestLeaf(t, ca, caKey, []string{"statbus.example.org"}, now.Add(-time.Hour), now.Add(time.Hour))

	t.Run("answers with a verified certificate", func(t *testing.T) {
		port, hosts := startVisitTestServer(t, &goodLeaf, http.StatusOK)
		withVisitRoots(t, pool)
		check := visitCheck{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}
		if reason := probeVisit(check); reason != "" {
			t.Fatalf("reason = %q, want success", reason)
		}
		// The request carried the advertised name, not an IP: the check
		// really fetched the site the way a user's client would.
		if len(*hosts) != 1 || (*hosts)[0] != "statbus.example.org:"+port {
			t.Fatalf("server saw Host %v", *hosts)
		}
	})
	t.Run("certificate not trusted", func(t *testing.T) {
		port, _ := startVisitTestServer(t, &goodLeaf, http.StatusOK)
		withVisitRoots(t, x509.NewCertPool())
		check := visitCheck{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}
		if reason := probeVisit(check); !strings.Contains(reason, "not trusted") {
			t.Fatalf("reason = %q, want not trusted", reason)
		}
	})
	t.Run("name not covered", func(t *testing.T) {
		otherLeaf := visitTestLeaf(t, ca, caKey, []string{"other.example.org"}, now.Add(-time.Hour), now.Add(time.Hour))
		port, _ := startVisitTestServer(t, &otherLeaf, http.StatusOK)
		withVisitRoots(t, pool)
		check := visitCheck{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}
		if reason := probeVisit(check); !strings.Contains(reason, "does not cover") {
			t.Fatalf("reason = %q, want name not covered", reason)
		}
	})
	t.Run("certificate expired", func(t *testing.T) {
		expiredLeaf := visitTestLeaf(t, ca, caKey, []string{"statbus.example.org"}, now.Add(-48*time.Hour), now.Add(-24*time.Hour))
		port, _ := startVisitTestServer(t, &expiredLeaf, http.StatusOK)
		withVisitRoots(t, pool)
		check := visitCheck{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}
		if reason := probeVisit(check); !strings.Contains(reason, "expired or not yet valid") {
			t.Fatalf("reason = %q, want expired", reason)
		}
	})
	t.Run("no answer", func(t *testing.T) {
		withVisitRoots(t, pool)
		check := visitCheck{origin: "https://statbus.example.org:" + silentPort(t), verifyTLS: true, fatal: true}
		if reason := probeVisit(check); !strings.Contains(reason, "did not answer") {
			t.Fatalf("reason = %q, want did not answer", reason)
		}
	})
	t.Run("HTTP status outside 2xx/3xx", func(t *testing.T) {
		port, _ := startVisitTestServer(t, &goodLeaf, http.StatusInternalServerError)
		withVisitRoots(t, pool)
		check := visitCheck{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}
		if reason := probeVisit(check); !strings.Contains(reason, "answered with HTTP status 500") {
			t.Fatalf("reason = %q, want HTTP status 500", reason)
		}
	})
	t.Run("plain HTTP answers", func(t *testing.T) {
		port, _ := startVisitTestServer(t, nil, http.StatusOK)
		check := visitCheck{origin: "http://statbus.example.org:" + port, fatal: true}
		if reason := probeVisit(check); reason != "" {
			t.Fatalf("reason = %q, want success", reason)
		}
	})
	t.Run("development HTTPS skips trust verification but still requires an answer", func(t *testing.T) {
		// Caddy's internal CA is in no system trust store; an empty pool must
		// not fail a development HTTPS check, but a dead port still must.
		port, _ := startVisitTestServer(t, &goodLeaf, http.StatusOK)
		withVisitRoots(t, x509.NewCertPool())
		check := visitCheck{origin: "https://statbus.example.org:" + port, verifyTLS: false, fatal: true}
		if reason := probeVisit(check); reason != "" {
			t.Fatalf("reason = %q, want success without trust verification", reason)
		}
		check = visitCheck{origin: "https://statbus.example.org:" + silentPort(t), verifyTLS: false, fatal: true}
		if reason := probeVisit(check); !strings.Contains(reason, "did not answer") {
			t.Fatalf("reason = %q, want did not answer", reason)
		}
	})
}

func TestVisitChecksFollowCertificateSetup_STATBUS394(t *testing.T) {
	writeEnv := func(t *testing.T, env, envConfig string) string {
		t.Helper()
		dir := t.TempDir()
		if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte(envConfig), 0o600); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	for _, c := range []struct {
		name      string
		env       string
		envConfig string
		want      []visitCheck
	}{
		{
			name:      "standalone with a supplied certificate is verified and fatal",
			env:       "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example.org\n",
			envConfig: "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example.org\nTLS_CERT_FILE=/data/custom-certs/domain.crt\nTLS_KEY_FILE=/data/custom-certs/domain.key\n",
			want:      []visitCheck{{origin: "https://statbus.example.org", verifyTLS: true, fatal: true}},
		},
		{
			name:      "standalone on automatic ACME is verified but not fatal",
			env:       "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example.org\n",
			envConfig: "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example.org\n",
			want:      []visitCheck{{origin: "https://statbus.example.org", verifyTLS: true, fatal: false}},
		},
		{
			name:      "development checks plain HTTP and the internal-CA HTTPS origin without trust verification",
			env:       "CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\nCADDY_HTTP_PORT=3010\nCADDY_HTTPS_PORT=3011\n",
			envConfig: "CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\n",
			want: []visitCheck{
				{origin: "http://local.statbus.org:3010", verifyTLS: false, fatal: true},
				{origin: "https://local.statbus.org:3011", verifyTLS: false, fatal: true},
			},
		},
		{
			name:      "private without a supplied certificate is verified but not fatal",
			env:       "CADDY_DEPLOYMENT_MODE=private\nSITE_DOMAIN=dev.statbus.org\n",
			envConfig: "CADDY_DEPLOYMENT_MODE=private\nSITE_DOMAIN=dev.statbus.org\n",
			want:      []visitCheck{{origin: "https://dev.statbus.org", verifyTLS: true, fatal: false}},
		},
	} {
		t.Run(c.name, func(t *testing.T) {
			dir := writeEnv(t, c.env, c.envConfig)
			got := visitChecks(dir)
			if len(got) != len(c.want) {
				t.Fatalf("visitChecks = %+v, want %+v", got, c.want)
			}
			for i := range c.want {
				if got[i] != c.want[i] {
					t.Errorf("check %d = %+v, want %+v", i, got[i], c.want[i])
				}
			}
		})
	}
}

// withVisitChecksSeam points the check-planning seam at checks for one test.
func withVisitChecksSeam(t *testing.T, checks []visitCheck) {
	t.Helper()
	old := visitChecksForDir
	t.Cleanup(func() { visitChecksForDir = old })
	visitChecksForDir = func(string) []visitCheck { return checks }
}

func TestVerifyAdvertisedSite_STATBUS394(t *testing.T) {
	ca, caKey, pool := visitTestCA(t)
	now := time.Now()
	goodLeaf := visitTestLeaf(t, ca, caKey, []string{"statbus.example.org"}, now.Add(-time.Hour), now.Add(time.Hour))

	t.Run("success prints the answering origins", func(t *testing.T) {
		port, _ := startVisitTestServer(t, &goodLeaf, http.StatusOK)
		withVisitRoots(t, pool)
		withVisitChecksSeam(t, []visitCheck{{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}})
		var warnings []string
		var err error
		out := captureStdout(t, func() {
			warnings, err = verifyAdvertisedSite(t.TempDir(), 0, time.Millisecond)
		})
		if err != nil || len(warnings) != 0 {
			t.Fatalf("err=%v warnings=%v", err, warnings)
		}
		if !strings.Contains(out, "https://statbus.example.org:"+port+" answers") {
			t.Fatalf("output = %q", out)
		}
	})
	t.Run("a supplied certificate that does not serve stops the install", func(t *testing.T) {
		withVisitRoots(t, pool)
		origin := "https://statbus.example.org:" + silentPort(t)
		withVisitChecksSeam(t, []visitCheck{{origin: origin, verifyTLS: true, fatal: true}})
		var err error
		captureStdout(t, func() {
			_, err = verifyAdvertisedSite(t.TempDir(), 0, time.Millisecond)
		})
		if err == nil || !strings.Contains(err.Error(), origin+" did not answer") {
			t.Fatalf("err = %v, want the origin and its reason", err)
		}
	})
	t.Run("an untrusted supplied certificate stops the install with the reason", func(t *testing.T) {
		port, _ := startVisitTestServer(t, &goodLeaf, http.StatusOK)
		withVisitRoots(t, x509.NewCertPool())
		withVisitChecksSeam(t, []visitCheck{{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}})
		var err error
		captureStdout(t, func() {
			_, err = verifyAdvertisedSite(t.TempDir(), 0, time.Millisecond)
		})
		if err == nil || !strings.Contains(err.Error(), "not trusted") {
			t.Fatalf("err = %v, want certificate not trusted", err)
		}
	})
	t.Run("ACME HTTPS not working yet completes with the honest line", func(t *testing.T) {
		port, _ := startVisitTestServer(t, &goodLeaf, http.StatusOK)
		withVisitRoots(t, x509.NewCertPool())
		origin := "https://statbus.example.org:" + port
		withVisitChecksSeam(t, []visitCheck{{origin: origin, verifyTLS: true, fatal: false}})
		var warnings []string
		var err error
		out := captureStdout(t, func() {
			warnings, err = verifyAdvertisedSite(t.TempDir(), 0, time.Millisecond)
		})
		if err != nil {
			t.Fatalf("err = %v, want install to complete", err)
		}
		if len(warnings) != 1 || !strings.Contains(warnings[0], origin) || !strings.Contains(warnings[0], "not trusted") {
			t.Fatalf("warnings = %v", warnings)
		}
		if !strings.Contains(out, "HTTPS is not working yet: "+origin) {
			t.Fatalf("output = %q, want the HTTPS is not working yet line", out)
		}
	})
	t.Run("a failed fatal check and a failed ACME check stop with both named", func(t *testing.T) {
		withVisitRoots(t, pool)
		httpOrigin := "http://statbus.example.org:" + silentPort(t)
		acmeOrigin := "https://statbus.example.org:" + silentPort(t)
		withVisitChecksSeam(t, []visitCheck{
			{origin: httpOrigin, fatal: true},
			{origin: acmeOrigin, verifyTLS: true, fatal: false},
		})
		var err error
		captureStdout(t, func() {
			_, err = verifyAdvertisedSite(t.TempDir(), 0, time.Millisecond)
		})
		if err == nil || !strings.Contains(err.Error(), httpOrigin+" did not answer") {
			t.Fatalf("err = %v, want the fatal origin named", err)
		}
	})
}
