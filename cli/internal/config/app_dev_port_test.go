package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"text/template"
)

// STATBUS-623: each checkout's host dev server has its own port in the slot's
// block (offset+7), and the slot's development Caddy forwards pages to it, so
// `./dev.sh https on` serves this checkout's code over HTTP/2 instead of
// whichever dev server holds port 3000.
func TestComputeDerivedAppDevPort_STATBUS623(t *testing.T) {
	for _, c := range []struct {
		offset string
		want   int
	}{
		{"1", 3017},
		{"3", 3037},
	} {
		d := computeDerived(&ConfigEnv{
			DeploymentSlotCode:       "local",
			DeploymentSlotName:       "local",
			DeploymentSlotPortOffset: c.offset,
			CaddyDeploymentMode:      "development",
			SiteDomain:               "local.statbus.org",
		})
		if d.AppDevPort != c.want {
			t.Errorf("offset %s: AppDevPort = %d, want %d", c.offset, d.AppDevPort, c.want)
		}
	}
}

func TestDevelopmentCaddyfileServesTheSlotsDevServer_STATBUS623(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "caddy", "templates", "development.caddyfile.tmpl"))
	if err != nil {
		t.Fatal(err)
	}
	tmpl, err := template.New("development").Parse(string(raw))
	if err != nil {
		t.Fatal(err)
	}
	var out strings.Builder
	if err := tmpl.Execute(&out, &CaddyTemplateData{
		ProgramName:         "sb",
		Domain:              "test.statbus.org",
		DeploymentSlotCode:  "test",
		CaddyDeploymentMode: "development",
		AppDevPort:          3037,
	}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "reverse_proxy host.docker.internal:3037 app:3000") {
		t.Errorf("development Caddyfile does not forward pages to host.docker.internal:3037 first:\n%s", out.String())
	}
}

func TestGeneratedEnvNamesAppDevPort_STATBUS623(t *testing.T) {
	cfg := &ConfigEnv{
		DeploymentSlotCode:       "test",
		DeploymentSlotName:       "test",
		DeploymentSlotPortOffset: "3",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "test.statbus.org",
	}
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0644); err != nil {
		t.Fatal(err)
	}
	env, _, err := generateEnvContent(&Credentials{}, cfg, computeDerived(cfg), &DbMemory{}, projDir)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(env, "\nAPP_DEV_PORT=3037\n") {
		t.Errorf("generated .env has no APP_DEV_PORT=3037 line")
	}
}
