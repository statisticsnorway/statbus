package config

import (
	"errors"
	"path/filepath"
	"strings"
	"testing"
)

// envValue returns the value of key in a generated env file's content.
func envValue(t *testing.T, content, key string) (string, bool) {
	t.Helper()
	for _, line := range strings.Split(content, "\n") {
		if k, v, ok := strings.Cut(line, "="); ok && k == key {
			return v, true
		}
	}
	return "", false
}

// stubSiteDomainOwners replaces the docker lookup for the duplicate-domain
// check, so config tests never depend on what runs on the machine.
func stubSiteDomainOwners(t *testing.T, owners []SiteDomainOwner, err error) {
	t.Helper()
	previous := runningSiteDomainOwners
	runningSiteDomainOwners = func(string) ([]SiteDomainOwner, error) { return owners, err }
	t.Cleanup(func() { runningSiteDomainOwners = previous })
}

func generateDev(t *testing.T, config string) (env, cfg string, err error) {
	t.Helper()
	stubDockerMemTotal(t, 16*gib, nil)
	stubSiteDomainOwners(t, nil, nil)
	dir := minimalCheckout(t)
	writeEnvConfig(t, dir, config)
	err = GenerateInDir(dir, false)
	if err != nil {
		return "", "", err
	}
	return readFileString(t, filepath.Join(dir, ".env")), readFileString(t, filepath.Join(dir, ".env.config")), nil
}

const testSlotConfig = "CADDY_DEPLOYMENT_MODE=development\nDEPLOYMENT_SLOT_CODE=test\nDEPLOYMENT_SLOT_PORT_OFFSET=3\nSITE_DOMAIN=test.statbus.org\n"

// STATBUS-631: in development the slot's addresses are derived on every
// generate from SITE_DOMAIN, the slot's ports and DEV_HTTPS (default true).
// The browser and the upgrade callback use https on the slot's Caddy, or
// plain http on it; the host dev server's own calls stay on plain http,
// because Node does not trust Caddy's local certificate authority.
func TestDevelopmentAddressesFollowDevHttps_STATBUS631(t *testing.T) {
	cases := []struct {
		name        string
		declared    string
		wantBrowser string
		wantFlag    string
	}{
		{"absent means true", "", "https://test.statbus.org:3031", "true"},
		{"true", "DEV_HTTPS=true\n", "https://test.statbus.org:3031", "true"},
		{"false", "DEV_HTTPS=false\n", "http://test.statbus.org:3030", "false"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			env, cfg, err := generateDev(t, testSlotConfig+c.declared)
			if err != nil {
				t.Fatalf("GenerateInDir: %v", err)
			}
			want := map[string]string{
				"STATBUS_URL":             c.wantBrowser,
				"BROWSER_REST_URL":        c.wantBrowser,
				"PUBLIC_BROWSER_REST_URL": c.wantBrowser,
				"SERVER_REST_URL":         "http://test.statbus.org:3030",
			}
			for key, w := range want {
				if got, _ := envValue(t, env, key); got != w {
					t.Errorf(".env %s = %q, want %q", key, got, w)
				}
			}
			if got, _ := envValue(t, cfg, "DEV_HTTPS"); got != c.wantFlag {
				t.Errorf(".env.config DEV_HTTPS = %q, want %q", got, c.wantFlag)
			}
			for _, key := range []string{"STATBUS_URL", "BROWSER_REST_URL", "SERVER_REST_URL"} {
				if v, found := envValue(t, cfg, key); found {
					t.Errorf(".env.config holds %s=%s; in development it is derived, never stored", key, v)
				}
			}
		})
	}
}

// STATBUS-631: a checkout set up before DEV_HTTPS carries the three addresses
// in .env.config, possibly stale (another slot's port, the docker-only
// http://proxy:80). They are removed, and DEV_HTTPS keeps the choice the old
// browser address expressed.
func TestStoredDevelopmentAddressesBecomeDevHttps_STATBUS631(t *testing.T) {
	cases := []struct {
		name        string
		browser     string
		wantFlag    string
		wantBrowser string
	}{
		{"https choice kept", "https://local.statbus.org:3011", "true", "https://test.statbus.org:3031"},
		{"http choice kept", "http://localhost:3013", "false", "http://test.statbus.org:3030"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			stored := "STATBUS_URL=http://localhost:3013\nBROWSER_REST_URL=" + c.browser + "\nSERVER_REST_URL=http://proxy:80\n"
			env, cfg, err := generateDev(t, testSlotConfig+stored)
			if err != nil {
				t.Fatalf("GenerateInDir: %v", err)
			}
			if got, _ := envValue(t, cfg, "DEV_HTTPS"); got != c.wantFlag {
				t.Errorf(".env.config DEV_HTTPS = %q, want %q", got, c.wantFlag)
			}
			for _, key := range []string{"STATBUS_URL", "BROWSER_REST_URL", "SERVER_REST_URL"} {
				if v, found := envValue(t, cfg, key); found {
					t.Errorf(".env.config still holds %s=%s", key, v)
				}
			}
			if got, _ := envValue(t, env, "BROWSER_REST_URL"); got != c.wantBrowser {
				t.Errorf(".env BROWSER_REST_URL = %q, want %q", got, c.wantBrowser)
			}
			if got, _ := envValue(t, env, "SERVER_REST_URL"); got != "http://test.statbus.org:3030" {
				t.Errorf(".env SERVER_REST_URL = %q, want http://test.statbus.org:3030", got)
			}
		})
	}
}

func TestDevHttpsAcceptsOnlyTrueOrFalse_STATBUS631(t *testing.T) {
	_, _, err := generateDev(t, testSlotConfig+"DEV_HTTPS=yes\n")
	if !errors.Is(err, ErrPrincipledRefusal) {
		t.Fatalf("DEV_HTTPS=yes: err = %v, want a principled refusal", err)
	}
	if !strings.Contains(err.Error(), "DEV_HTTPS") {
		t.Errorf("refusal does not name DEV_HTTPS: %v", err)
	}
}

// STATBUS-631: DEV_HTTPS belongs to development. Standalone and private slots
// keep their addresses as before and never carry the key.
func TestDevHttpsStaysOutOfOtherModes_STATBUS631(t *testing.T) {
	cases := []struct {
		name, config, wantBrowser, wantServer string
	}{
		{"standalone", "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example.no\n", "https://statbus.example.no", "http://proxy:80"},
		{"private", "CADDY_DEPLOYMENT_MODE=private\nDEPLOYMENT_SLOT_CODE=ma\nDEPLOYMENT_SLOT_PORT_OFFSET=2\nSITE_DOMAIN=ma.statbus.org\n", "http://ma.statbus.org:3020", "http://proxy:80"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			env, cfg, err := generateDev(t, c.config)
			if err != nil {
				t.Fatalf("GenerateInDir: %v", err)
			}
			if _, found := envValue(t, cfg, "DEV_HTTPS"); found {
				t.Errorf(".env.config carries DEV_HTTPS outside development:\n%s", cfg)
			}
			if got, _ := envValue(t, env, "BROWSER_REST_URL"); got != c.wantBrowser {
				t.Errorf(".env BROWSER_REST_URL = %q, want %q", got, c.wantBrowser)
			}
			if got, _ := envValue(t, env, "SERVER_REST_URL"); got != c.wantServer {
				t.Errorf(".env SERVER_REST_URL = %q, want %q", got, c.wantServer)
			}
		})
	}
}

// STATBUS-631: one SITE_DOMAIN per slot on a machine. A running proxy from
// another compose project on the same domain stops config generate, naming
// that slot and its folder; this checkout's own containers do not.
func TestSiteDomainHeldByAnotherRunningSlotIsRefused_STATBUS631(t *testing.T) {
	stubDockerMemTotal(t, 16*gib, nil)
	dir := minimalCheckout(t)
	writeEnvConfig(t, dir, testSlotConfig)

	stubSiteDomainOwners(t, []SiteDomainOwner{{Project: "statbus-local", Folder: "/Users/dev/statbus"}}, nil)
	err := GenerateInDir(dir, false)
	if !errors.Is(err, ErrPrincipledRefusal) {
		t.Fatalf("duplicate domain: err = %v, want a principled refusal", err)
	}
	for _, want := range []string{"test.statbus.org", "statbus-local", "/Users/dev/statbus"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal does not name %q: %v", want, err)
		}
	}

	stubSiteDomainOwners(t, []SiteDomainOwner{{Project: "statbus-test", Folder: "/elsewhere"}, {Project: "statbus-old", Folder: dir}}, nil)
	if err := GenerateInDir(dir, false); err != nil {
		t.Fatalf("own project or own folder must not count as another slot: %v", err)
	}

	stubSiteDomainOwners(t, nil, errors.New("docker: command not found"))
	if err := GenerateInDir(dir, false); err != nil {
		t.Fatalf("an unavailable docker must not stop generate: %v", err)
	}
}
