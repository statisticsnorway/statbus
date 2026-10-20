package config

import (
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// STATBUS-521 AC7: the ports install checks are the ports the generated
// settings publish, from one source of truth. For each deployment mode,
// PlannedHostPorts (and PlannedHostPortsInDir reading the same .env.config)
// must equal the seven bindings parsed from a REAL generated .env: HTTP,
// HTTPS, the app, the API, the API admin server, and the database's local
// and TLS routes.
func TestPlannedHostPortsMatchGeneratedEnv(t *testing.T) {
	for _, mode := range []string{"development", "private", "standalone"} {
		t.Run(mode, func(t *testing.T) {
			projDir := t.TempDir()
			configContent := "CADDY_DEPLOYMENT_MODE=" + mode + "\n" +
				"DEPLOYMENT_SLOT_CODE=test\n" +
				"DEPLOYMENT_SLOT_NAME=Test\n" +
				"DEPLOYMENT_SLOT_PORT_OFFSET=1\n"
			if mode == "standalone" {
				configContent += "SITE_DOMAIN=statbus.example.org\n"
			}
			if err := os.WriteFile(filepath.Join(projDir, ".env.config"), []byte(configContent), 0600); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0644); err != nil {
				t.Fatal(err)
			}
			cfg, err := loadOrGenerateConfig(projDir, false)
			if err != nil {
				t.Fatal(err)
			}
			dbMem, err := computeDbMemory(cfg.DbMemLimit)
			if err != nil {
				t.Fatal(err)
			}
			out, _, err := generateEnvContent(&Credentials{}, cfg, computeDerived(cfg), dbMem, projDir)
			if err != nil {
				t.Fatal(err)
			}
			env := dotenv.FromString(out)
			// pair reads a port key and its bind-address key; the bind
			// address carries the host, with or without its own :port.
			pair := func(portKey, bindKey string) HostPort {
				t.Helper()
				rawPort, ok := env.Get(portKey)
				if !ok {
					t.Fatalf("generated .env lacks %s", portKey)
				}
				port, err := strconv.Atoi(rawPort)
				if err != nil {
					t.Fatalf("%s=%q: %v", portKey, rawPort, err)
				}
				bind, ok := env.Get(bindKey)
				if !ok {
					t.Fatalf("generated .env lacks %s", bindKey)
				}
				host := bind
				if h, _, err := net.SplitHostPort(bind); err == nil {
					host = h
				}
				return HostPort{Host: host, Port: port}
			}
			// addr reads a combined host:port bind-address key.
			addr := func(bindKey string) HostPort {
				t.Helper()
				bind, ok := env.Get(bindKey)
				if !ok {
					t.Fatalf("generated .env lacks %s", bindKey)
				}
				host, rawPort, err := net.SplitHostPort(bind)
				if err != nil {
					t.Fatalf("%s=%q: %v", bindKey, bind, err)
				}
				port, err := strconv.Atoi(rawPort)
				if err != nil {
					t.Fatalf("%s=%q: %v", bindKey, bind, err)
				}
				return HostPort{Host: host, Port: port}
			}
			want := []HostPort{
				pair("CADDY_HTTP_PORT", "CADDY_HTTP_BIND_ADDRESS"),
				pair("CADDY_HTTPS_PORT", "CADDY_HTTPS_BIND_ADDRESS"),
				addr("APP_BIND_ADDRESS"),
				addr("REST_BIND_ADDRESS"),
				addr("REST_ADMIN_BIND_ADDRESS"),
				pair("CADDY_DB_PORT", "CADDY_DB_BIND_ADDRESS"),
				pair("CADDY_DB_TLS_PORT", "CADDY_DB_TLS_BIND_ADDRESS"),
			}
			planned, err := PlannedHostPorts(cfg)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(planned, want) {
				t.Fatalf("PlannedHostPorts = %+v, generated .env publishes %+v", planned, want)
			}
			fromDir, err := PlannedHostPortsInDir(projDir)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(fromDir, want) {
				t.Fatalf("PlannedHostPortsInDir = %+v, generated .env publishes %+v", fromDir, want)
			}
		})
	}
}

// The slot layout itself: development binds every service on loopback at
// 3000+offset*10 (+0..+6); standalone publishes HTTP/HTTPS and the database
// TLS route on the wildcard address and keeps the rest on loopback.
func TestPlannedHostPortsLayout(t *testing.T) {
	development, err := PlannedHostPorts(&ConfigEnv{CaddyDeploymentMode: "development", DeploymentSlotPortOffset: "2"})
	if err != nil {
		t.Fatal(err)
	}
	wantDevelopment := []HostPort{
		{"127.0.0.1", 3020}, {"127.0.0.1", 3021}, {"127.0.0.1", 3022}, {"127.0.0.1", 3023},
		{"127.0.0.1", 3026}, {"127.0.0.1", 3024}, {"127.0.0.1", 3025},
	}
	if !reflect.DeepEqual(development, wantDevelopment) {
		t.Fatalf("development = %+v, want %+v", development, wantDevelopment)
	}
	standalone, err := PlannedHostPorts(&ConfigEnv{CaddyDeploymentMode: "standalone", DeploymentSlotPortOffset: "1"})
	if err != nil {
		t.Fatal(err)
	}
	wantStandalone := []HostPort{
		{"0.0.0.0", 80}, {"0.0.0.0", 443}, {"127.0.0.1", 3012}, {"127.0.0.1", 3013},
		{"127.0.0.1", 3016}, {"127.0.0.1", 5431}, {"0.0.0.0", 5432},
	}
	if !reflect.DeepEqual(standalone, wantStandalone) {
		t.Fatalf("standalone = %+v, want %+v", standalone, wantStandalone)
	}
}
