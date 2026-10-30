package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"text/template"
)

// TestCaddyTemplates_MonitorRoute pins STATBUS-541's public health route in
// every template that can serve a site: /monitor must be its own handler,
// above the maintenance handler (so a maintenance page never hides the
// reading), and the maintenance matcher must exclude it. The 503 marker is
// the upgrader's critical/unknown signal.
func TestCaddyTemplates_MonitorRoute(t *testing.T) {
	data := &CaddyTemplateData{
		ProgramName:           "sb",
		Domain:                "statbus.example.org",
		DeploymentUser:        "statbus",
		DeploymentSlotCode:    "test",
		CaddyDeploymentMode:   "private",
		CaddyHttpPort:         8080,
		CaddyHttpsPort:        8443,
		CaddyHttpBindAddress:  "127.0.0.1:8080",
		CaddyHttpsBindAddress: "127.0.0.1:8443",
		CaddyDbPort:           5432,
		CaddyDbTlsPort:        5433,
		CaddyDbBindAddress:    "127.0.0.1:5432",
		CaddyDbTlsBindAddress: "127.0.0.1:5433",
		AppPort:               3000,
		AppBindAddress:        "127.0.0.1:3000",
		PostgrestBindAddress:  "127.0.0.1:3001",
	}
	for _, name := range []string{"private.caddyfile.tmpl", "standalone.caddyfile.tmpl", "development.caddyfile.tmpl"} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join("..", "..", "..", "caddy", "templates", name)
			raw, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			tmpl, err := template.New(name).Parse(string(raw))
			if err != nil {
				t.Fatalf("parse %s: %v", name, err)
			}
			var rendered strings.Builder
			if err := tmpl.Execute(&rendered, data); err != nil {
				t.Fatalf("execute %s: %v", name, err)
			}
			body := rendered.String()

			monitor := strings.Index(body, "handle /monitor {")
			if monitor < 0 {
				t.Fatalf("%s: no handle /monitor route", name)
			}
			for _, wanted := range []string{
				"file monitor.critical",
				"rewrite * /monitor.json",
				"status 503",
			} {
				if !strings.Contains(body[monitor:], wanted) {
					t.Errorf("%s: /monitor route missing %q", name, wanted)
				}
			}

			maintenance := strings.Index(body, "@maintenance {")
			if maintenance >= 0 {
				if monitor > maintenance {
					t.Errorf("%s: /monitor route is below the maintenance handler", name)
				}
				if !strings.Contains(body[maintenance:], "not path /monitor") {
					t.Errorf("%s: maintenance matcher does not exclude /monitor", name)
				}
			}
		})
	}
}
