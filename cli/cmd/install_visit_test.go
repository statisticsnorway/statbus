package cmd

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// STATBUS-469: the completion banner names origins the installation actually
// serves, read from the generated .env the services bind to.
func TestInstallVisitOriginsFollowModeAndPorts_STATBUS469(t *testing.T) {
	for _, c := range []struct {
		name, env string
		want      []string
	}{
		{"development", "CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\nCADDY_HTTP_PORT=3010\nCADDY_HTTPS_PORT=3011\n",
			[]string{"http://local.statbus.org:3010", "https://local.statbus.org:3011"}},
		{"standalone", "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example.org\nCADDY_HTTP_PORT=80\nCADDY_HTTPS_PORT=443\n",
			[]string{"https://statbus.example.org"}},
		{"private", "CADDY_DEPLOYMENT_MODE=private\nSITE_DOMAIN=dev.statbus.org\nCADDY_HTTP_PORT=3020\nCADDY_HTTPS_PORT=3021\n",
			[]string{"https://dev.statbus.org"}},
	} {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(c.env), 0o600); err != nil {
				t.Fatal(err)
			}
			// .env.config carries the operator's answers; .env is generated from it.
			if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte(c.env), 0o600); err != nil {
				t.Fatal(err)
			}
			if got := installVisitOrigins(dir); !reflect.DeepEqual(got, c.want) {
				t.Errorf("installVisitOrigins = %q, want %q", got, c.want)
			}
		})
	}
}
