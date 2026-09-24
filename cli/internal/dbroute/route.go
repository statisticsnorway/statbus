// Package dbroute resolves the server-internal PostgreSQL endpoint.
package dbroute

import (
	"fmt"
	"path/filepath"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// Resolve reloads .env on every call, including after recovery regenerates it.
func Resolve(projDir string) (host, port string, err error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return "", "", fmt.Errorf("load .env: %w", err)
	}
	return FromFile(f)
}

// FromFile rejects missing internal endpoints rather than falling back to SITE_DOMAIN.
func FromFile(f *dotenv.File) (host, port string, err error) {
	host, ok := f.Get("CADDY_DB_BIND_ADDRESS")
	if !ok || host == "" {
		return "", "", fmt.Errorf("CADDY_DB_BIND_ADDRESS not found in .env — regenerate with: ./sb config generate")
	}
	port, ok = f.Get("CADDY_DB_PORT")
	if !ok || port == "" {
		return "", "", fmt.Errorf("CADDY_DB_PORT not found in .env — regenerate with: ./sb config generate")
	}
	return host, port, nil
}
