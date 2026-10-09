package config

import (
	"os"
	"path/filepath"
	"testing"
)

// STATBUS-484: the upgrade callback announces the instance's real external URL.
// The default was a hardcoded http://localhost:3010, so a standalone box told
// whoever read the notification to visit the developer's laptop. The value must
// be derived the same way every other external address is — which today means
// it must equal what the browser is given (BROWSER_REST_URL), in every mode.
//
// This is written through loadOrGenerateConfig rather than against a helper, so
// it pins the wiring too: a correct derivation that never reaches the written
// config would be a passing helper and a broken product.
func TestStatbusURLDefaultsToTheExternalAddress(t *testing.T) {
	cases := []struct {
		name   string
		mode   string
		domain string
		offset string
		want   string
	}{
		{"standalone", "standalone", "statbus.example.no", "1", "https://statbus.example.no"},
		{"private slot", "private", "ma.statbus.org", "2", "http://ma.statbus.org:3020"},
		{"development", "development", "local.statbus.org", "1", "http://local.statbus.org:3010"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			projDir := t.TempDir()
			content := "CADDY_DEPLOYMENT_MODE=" + c.mode + "\n" +
				"SITE_DOMAIN=" + c.domain + "\n" +
				"DEPLOYMENT_SLOT_PORT_OFFSET=" + c.offset + "\n"
			if err := os.WriteFile(filepath.Join(projDir, ".env.config"), []byte(content), 0644); err != nil {
				t.Fatal(err)
			}

			cfg, err := loadOrGenerateConfig(projDir, false)
			if err != nil {
				t.Fatalf("loadOrGenerateConfig: %v", err)
			}

			if cfg.StatbusURL != c.want {
				t.Errorf("STATBUS_URL default = %q, want %q (the instance's real external URL)", cfg.StatbusURL, c.want)
			}
			if cfg.StatbusURL != cfg.BrowserAPIURL {
				t.Errorf("STATBUS_URL %q must be derived the same way as BROWSER_REST_URL %q", cfg.StatbusURL, cfg.BrowserAPIURL)
			}
		})
	}
}
