package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// certWarningFixture writes a PEM pair for name, valid in [notBefore, notAfter],
// and a standalone .env.config whose SITE_DOMAIN is site.
func certWarningFixture(t *testing.T, name, site string, notBefore, notAfter time.Time) (dir, certPath, keyPath string) {
	t.Helper()
	dir = t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN="+site+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cert, key := testCertificate(t, name, []string{name}, notBefore, notAfter)
	in := t.TempDir()
	certPath, keyPath = filepath.Join(in, "cert.pem"), filepath.Join(in, "key.pem")
	if err := os.WriteFile(certPath, certPEM(t, cert), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath, keyPEM(t, key), 0o600); err != nil {
		t.Fatal(err)
	}
	return dir, certPath, keyPath
}

func stubUseAnyway(t *testing.T, answer bool) *[]string {
	t.Helper()
	var asked []string
	saved := askUseCertificateAnyway
	askUseCertificateAnyway = func(label string) bool { asked = append(asked, label); return answer }
	t.Cleanup(func() { askUseCertificateAnyway = saved })
	return &asked
}

// An expired certificate, or one that does not cover the site, is warned about
// by name and needs its own yes before anything is written (owner, rc.18
// manual box). No leaves no files and .env.config unchanged.
func TestInstallCustomCertificateWarnsAndAsksBeforeUsingAProblemCertificate(t *testing.T) {
	now := time.Now()
	cases := []struct {
		name, certName, site string
		notBefore, notAfter  time.Time
		warning              string
	}{
		{"expired", "statbus.example.org", "statbus.example.org", now.Add(-48 * time.Hour), now.Add(-24 * time.Hour), "⚠ This certificate expired on "},
		{"not yet valid", "statbus.example.org", "statbus.example.org", now.Add(24 * time.Hour), now.Add(48 * time.Hour), "⚠ This certificate is not valid until "},
		{"other name", "other.example.org", "statbus.example.org", now.Add(-time.Hour), now.Add(24 * time.Hour), "⚠ This certificate does not cover statbus.example.org."},
	}
	for _, c := range cases {
		t.Run(c.name+", declined", func(t *testing.T) {
			dir, certPath, keyPath := certWarningFixture(t, c.certName, c.site, c.notBefore, c.notAfter)
			asked := stubUseAnyway(t, false)
			var err error
			out := pickerCapture(t, func() { _, err = installCustomCertificate(dir, []string{certPath, keyPath}, nil) })
			if err == nil {
				t.Fatalf("declining a problem certificate installed it:\n%s", out)
			}
			if !strings.Contains(out, c.warning) {
				t.Fatalf("output lacks %q:\n%s", c.warning, out)
			}
			if strings.Join(*asked, "|") != "  Use it anyway?" {
				t.Fatalf("questions = %q, want one 'Use it anyway?'", *asked)
			}
			if entries, _ := os.ReadDir(filepath.Join(dir, customCertHostDir)); len(entries) > 0 {
				t.Fatalf("declined certificate left files: %v", entries)
			}
			if cert, key := readEnvConfigCertValues(t, dir); cert != "" || key != "" {
				t.Fatalf(".env.config changed on decline: %q/%q", cert, key)
			}
		})
		t.Run(c.name+", accepted", func(t *testing.T) {
			dir, certPath, keyPath := certWarningFixture(t, c.certName, c.site, c.notBefore, c.notAfter)
			stubUseAnyway(t, true)
			if _, err := installCustomCertificate(dir, []string{certPath, keyPath}, nil); err != nil {
				t.Fatalf("accepting the warning must install: %v", err)
			}
			if cert, _ := readEnvConfigCertValues(t, dir); cert == "" {
				t.Fatal("accepted certificate did not reach .env.config")
			}
		})
	}
}

// A certificate that is valid now and covers the site asks nothing extra.
func TestInstallCustomCertificateGoodCertificateAsksNothingExtra(t *testing.T) {
	dir, certPath, keyPath := certWarningFixture(t, "statbus.example.org", "statbus.example.org", time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	asked := stubUseAnyway(t, false)
	if _, err := installCustomCertificate(dir, []string{certPath, keyPath}, nil); err != nil {
		t.Fatal(err)
	}
	if len(*asked) != 0 {
		t.Fatalf("a good certificate asked %q", *asked)
	}
}
