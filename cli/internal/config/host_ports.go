package config

import (
	"fmt"
	"net"
	"path/filepath"
	"strconv"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// HostPort is one host address and port the generated settings bind.
type HostPort struct {
	Host string
	Port int
}

// PlannedHostPorts returns the host addresses and ports the generated .env
// binds for cfg, in one fixed order: HTTP, HTTPS, the app, the API, the API
// admin server, and the database's local and TLS routes. It derives them from
// the same computation (computeDerived) that generateEnvContent writes .env
// from, so install's port check cannot drift from what the services bind
// (STATBUS-521).
func PlannedHostPorts(cfg *ConfigEnv) ([]HostPort, error) {
	d := computeDerived(cfg)
	// HTTP/HTTPS pair a port key with a host:port bind address; the bind
	// address carries the host.
	hostOf := func(bindAddress string) (string, error) {
		host, _, err := net.SplitHostPort(bindAddress)
		if err != nil {
			return "", fmt.Errorf("generated bind address %q: %w", bindAddress, err)
		}
		return host, nil
	}
	// The app, API and API admin bind addresses carry host:port together.
	addr := func(bindAddress string) (HostPort, error) {
		host, rawPort, err := net.SplitHostPort(bindAddress)
		if err != nil {
			return HostPort{}, fmt.Errorf("generated bind address %q: %w", bindAddress, err)
		}
		port, err := strconv.Atoi(rawPort)
		if err != nil {
			return HostPort{}, fmt.Errorf("generated bind address %q: %w", bindAddress, err)
		}
		return HostPort{Host: host, Port: port}, nil
	}
	ports := make([]HostPort, 0, 7)
	for _, spec := range []struct {
		bind string
		port int
	}{
		{d.CaddyHttpBindAddress, d.CaddyHttpPort},
		{d.CaddyHttpsBindAddress, d.CaddyHttpsPort},
	} {
		host, err := hostOf(spec.bind)
		if err != nil {
			return nil, err
		}
		ports = append(ports, HostPort{Host: host, Port: spec.port})
	}
	for _, bind := range []string{d.AppBindAddress, d.PostgrestBindAddress, d.RestAdminBindAddress} {
		hp, err := addr(bind)
		if err != nil {
			return nil, err
		}
		ports = append(ports, hp)
	}
	// The database bind addresses are a bare host paired with a port key.
	ports = append(ports,
		HostPort{Host: d.CaddyDbBindAddress, Port: d.CaddyDbPort},
		HostPort{Host: d.CaddyDbTlsBindAddress, Port: d.CaddyDbTlsPort},
	)
	return ports, nil
}

// PlannedHostPortsInDir reads the deployment mode and slot offset from
// projDir's .env.config, applying the generator's own defaults
// (loadOrGenerateConfig: standalone, slot offset 1), and returns the
// PlannedHostPorts the generated .env will bind.
func PlannedHostPortsInDir(projDir string) ([]HostPort, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env.config"))
	if err != nil {
		return nil, fmt.Errorf("load .env.config: %w", err)
	}
	mode, ok := f.Get("CADDY_DEPLOYMENT_MODE")
	if !ok || mode == "" {
		mode = "standalone"
	}
	offset, ok := f.Get("DEPLOYMENT_SLOT_PORT_OFFSET")
	if !ok || offset == "" {
		offset = "1"
	}
	return PlannedHostPorts(&ConfigEnv{CaddyDeploymentMode: mode, DeploymentSlotPortOffset: offset})
}
