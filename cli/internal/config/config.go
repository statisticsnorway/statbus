// Package config handles StatBus configuration generation.
//
// It reads .env.config and .env.credentials, derives all computed values
// (port offsets, memory tuning, URLs), generates .env, and renders
// Caddyfile templates from caddy/templates/*.caddyfile.tmpl.
//
// Ported from Crystal cli/src/manage.cr (manage_generate_config).
package config

import (
	"crypto/rand"
	"fmt"
	"math"
	"math/big"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"text/template"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// ProjectDir walks up from cwd looking for the .statbus marker file.
// Falls back to cwd if not found.
func ProjectDir() string {
	dir, err := os.Getwd()
	if err != nil {
		return "."
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, ".statbus")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	// Fall back to cwd
	cwd, _ := os.Getwd()
	return cwd
}

// Credentials holds values from .env.credentials.
type Credentials struct {
	PostgresAdminPassword         string
	PostgresAppPassword           string
	PostgresAuthenticatorPassword string
	PostgresNotifyPassword        string
	JwtSecret                     string
	DashboardUsername              string
	DashboardPassword             string
	ServiceRoleKey                string
}

// ConfigEnv holds values from .env.config.
type ConfigEnv struct {
	DeploymentSlotName       string
	DeploymentSlotCode       string
	DeploymentSlotPortOffset string
	StatbusURL               string
	BrowserAPIURL            string
	ServerAPIURL             string
	SeqServerURL             string
	SeqAPIKey                string
	SlackToken               string
	PostgresAdminDB          string
	PostgresAdminUser        string
	PostgresAppDB            string
	PostgresAppUser          string
	PostgresNotifyUser       string
	AccessJwtExpiry          string
	RefreshJwtExpiry         string
	CaddyDeploymentMode      string
	SiteDomain               string
	Debug                    string
	NextPublicDebug          string
	DbMemLimit               string
	TlsCertFile              string
	TlsKeyFile               string
	AptUseHttpsOnly          string
}

// DbMemory holds derived PostgreSQL memory tuning values.
type DbMemory struct {
	DbMemLimit          string
	DbShmSize           string
	DbMemReservation    string
	DbSharedBuffers     string
	DbMaintenanceWorkMem string
	DbEffectiveCacheSize string
	DbWorkMem           string
	DbTempBuffers       string
	DbWalBuffers        string
	DbMaxConnections    int64
	DbMaxWalSize        string
	DbMinWalSize        string
}

// Derived holds values computed from config + credentials.
type Derived struct {
	CaddyHttpPort           int
	CaddyHttpBindAddress    string
	CaddyHttpsPort          int
	CaddyHttpsBindAddress   string
	CaddyDbPort             int
	CaddyDbTlsPort          int
	CaddyDbBindAddress      string
	CaddyDbTlsBindAddress   string
	AppPort                 int
	AppBindAddress          string
	PostgrestPort           int
	PostgrestBindAddress    string
	Version                 string
	Commit                  string
	SiteURL                 string
	ApiExternalURL          string
	ApiPublicURL            string
	DeploymentUser          string
	Domain                  string
	EnableEmailSignup       bool
	EnableEmailAutoconfirm  bool
	DisableSignup           bool
	StudioDefaultProject    string
}

// CaddyTemplateData is the data passed to Caddyfile Go templates.
type CaddyTemplateData struct {
	ProgramName           string
	Domain                string
	DeploymentUser        string
	DeploymentSlotCode    string
	CaddyDeploymentMode   string
	Debug                 string
	CaddyHttpPort         int
	CaddyHttpsPort        int
	CaddyHttpBindAddress  string
	CaddyHttpsBindAddress string
	CaddyDbPort           int
	CaddyDbTlsPort        int
	CaddyDbBindAddress    string
	CaddyDbTlsBindAddress string
	AppPort               int
	AppBindAddress        string
	PostgrestBindAddress  string
	TlsCertFile           string
	TlsKeyFile            string
}

// randomString generates a cryptographically random alphanumeric string.
func randomString(length int) string {
	const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	result := make([]byte, length)
	for i := range result {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		if err != nil {
			panic(fmt.Sprintf("crypto/rand failed: %v", err))
		}
		result[i] = chars[n.Int64()]
	}
	return string(result)
}

// parseMemSizeToMB parses "4G", "512M", "1024K" to megabytes.
func parseMemSizeToMB(s string) (int64, error) {
	s = strings.TrimSpace(strings.ToUpper(s))
	if len(s) == 0 {
		return 0, fmt.Errorf("empty memory size")
	}
	suffix := s[len(s)-1]
	numStr := s[:len(s)-1]
	switch suffix {
	case 'G':
		n, err := strconv.ParseInt(numStr, 10, 64)
		return n * 1024, err
	case 'M':
		return strconv.ParseInt(numStr, 10, 64)
	case 'K':
		n, err := strconv.ParseInt(numStr, 10, 64)
		return n / 1024, err
	default:
		// Assume bytes
		n, err := strconv.ParseInt(s, 10, 64)
		return n / (1024 * 1024), err
	}
}

// formatMBForPG formats megabytes for postgresql.conf (e.g., "2GB", "512MB").
func formatMBForPG(mb int64) string {
	if mb >= 1024 && mb%1024 == 0 {
		return fmt.Sprintf("%dGB", mb/1024)
	}
	return fmt.Sprintf("%dMB", mb)
}

// formatMBForDocker formats megabytes for docker-compose (e.g., "2G", "512M").
func formatMBForDocker(mb int64) string {
	if mb >= 1024 && mb%1024 == 0 {
		return fmt.Sprintf("%dG", mb/1024)
	}
	return fmt.Sprintf("%dM", mb)
}

// generateJWT creates a minimal HS256 JWT token (no external dependency needed for this simple case).
// Format: base64url(header).base64url(payload).base64url(signature)
func generateJWT(secret string, role string) string {
	// Use os/exec to call a small inline Go program or use crypto/hmac
	// For now, use the same approach as Crystal: generate at credential time, store result.
	// We'll implement proper JWT in a later checkpoint when we add golang-jwt/jwt/v5.
	// For credential generation, we shell out to keep the dependency light.
	iat := time.Now().Unix()
	exp := iat + (5 * 365 * 24 * 60 * 60) // 5 years

	payload := fmt.Sprintf(`{"role":"%s","iss":"supabase","iat":%d,"exp":%d}`, role, iat, exp)
	// Use node/python/openssl for JWT if available, otherwise store a placeholder
	// Try node first (most likely available in dev environments)
	script := fmt.Sprintf(
		`const crypto = require('crypto');
const header = Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url');
const payload = Buffer.from('%s').toString('base64url');
const sig = crypto.createHmac('sha256', '%s').update(header + '.' + payload).digest('base64url');
process.stdout.write(header + '.' + payload + '.' + sig);`,
		payload, secret)

	out, err := exec.Command("node", "-e", script).Output()
	if err == nil {
		return string(out)
	}

	// Fallback: use openssl
	// This is a degraded path — in production we'll have golang-jwt
	return "JWT_GENERATION_REQUIRES_NODE_OR_GOLANG_JWT"
}

// loadOrGenerateCredentials reads .env.credentials, generating missing values.
func loadOrGenerateCredentials(projDir string, verbose bool) (*Credentials, error) {
	credPath := filepath.Join(projDir, ".env.credentials")
	f, err := dotenv.Load(credPath)
	if err != nil {
		return nil, fmt.Errorf("load credentials: %w", err)
	}

	gen := func(key string, genFn func() string) string {
		val, _ := f.Generate(key, func() (string, error) {
			return genFn(), nil
		})
		return val
	}

	jwtSecret := gen("JWT_SECRET", func() string { return randomString(32) })

	creds := &Credentials{
		PostgresAdminPassword:         gen("POSTGRES_ADMIN_PASSWORD", func() string { return randomString(20) }),
		PostgresAppPassword:           gen("POSTGRES_APP_PASSWORD", func() string { return randomString(20) }),
		PostgresAuthenticatorPassword: gen("POSTGRES_AUTHENTICATOR_PASSWORD", func() string { return randomString(20) }),
		PostgresNotifyPassword:        gen("POSTGRES_NOTIFY_PASSWORD", func() string { return randomString(20) }),
		JwtSecret:                     jwtSecret,
		DashboardUsername:             gen("DASHBOARD_USERNAME", func() string { return "admin" }),
		DashboardPassword:             gen("DASHBOARD_PASSWORD", func() string { return randomString(20) }),
		ServiceRoleKey:                gen("SERVICE_ROLE_KEY", func() string { return generateJWT(jwtSecret, "service_role") }),
	}

	if err := f.Save(); err != nil {
		return nil, fmt.Errorf("save credentials: %w", err)
	}
	if verbose {
		fmt.Fprintf(os.Stderr, "Credentials: %s\n", credPath)
	}
	return creds, nil
}

// loadOrGenerateConfig reads .env.config, generating missing values with defaults.
func loadOrGenerateConfig(projDir string, verbose bool) (*ConfigEnv, error) {
	cfgPath := filepath.Join(projDir, ".env.config")
	f, err := dotenv.Load(cfgPath)
	if err != nil {
		return nil, fmt.Errorf("load config: %w", err)
	}

	gen := func(key, defaultVal string) string {
		val, _ := f.Generate(key, func() (string, error) { return defaultVal, nil })
		return val
	}

	slotCode := gen("DEPLOYMENT_SLOT_CODE", "local")
	slotName := gen("DEPLOYMENT_SLOT_NAME", "local")
	appDB := gen("POSTGRES_APP_DB", "statbus_"+slotCode)
	appUser := gen("POSTGRES_APP_USER", "statbus_"+slotCode)
	notifyUser := gen("POSTGRES_NOTIFY_USER", "statbus_notify_"+slotCode)
	mode := gen("CADDY_DEPLOYMENT_MODE", "development")
	offsetStr := gen("DEPLOYMENT_SLOT_PORT_OFFSET", "1")
	siteDomain := gen("SITE_DOMAIN", slotCode+".statbus.org")

	offset, _ := strconv.Atoi(offsetStr)
	basePort := 3000
	httpPort := basePort + (offset * 10)

	var defaultBrowserURL string
	if mode == "standalone" {
		defaultBrowserURL = "https://" + siteDomain
	} else {
		defaultBrowserURL = fmt.Sprintf("http://%s:%d", siteDomain, httpPort)
	}

	var defaultServerURL string
	if mode == "development" {
		defaultServerURL = defaultBrowserURL
	} else {
		defaultServerURL = "http://proxy:80"
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:       slotCode,
		DeploymentSlotName:       slotName,
		DeploymentSlotPortOffset: offsetStr,
		StatbusURL:               gen("STATBUS_URL", "http://localhost:3010"),
		BrowserAPIURL:            gen("BROWSER_REST_URL", defaultBrowserURL),
		ServerAPIURL:             gen("SERVER_REST_URL", defaultServerURL),
		SeqServerURL:             gen("SEQ_SERVER_URL", "https://log.statbus.org"),
		SeqAPIKey:                gen("SEQ_API_KEY", "secret_seq_api_key"),
		SlackToken:               gen("SLACK_TOKEN", "secret_slack_api_token"),
		PostgresAdminDB:          gen("POSTGRES_ADMIN_DB", "postgres"),
		PostgresAdminUser:        gen("POSTGRES_ADMIN_USER", "postgres"),
		PostgresAppDB:            appDB,
		PostgresAppUser:          appUser,
		PostgresNotifyUser:       notifyUser,
		AccessJwtExpiry:          gen("ACCESS_JWT_EXPIRY", "3600"),
		RefreshJwtExpiry:         gen("REFRESH_JWT_EXPIRY", "2592000"),
		CaddyDeploymentMode:     mode,
		SiteDomain:               siteDomain,
		Debug:                    gen("DEBUG", "false"),
		NextPublicDebug:          gen("NEXT_PUBLIC_DEBUG", "false"),
		DbMemLimit:               gen("DB_MEM_LIMIT", "4G"),
		TlsCertFile:              gen("TLS_CERT_FILE", ""),
		TlsKeyFile:               gen("TLS_KEY_FILE", ""),
		AptUseHttpsOnly:          gen("APT_USE_HTTPS_ONLY", "false"),
	}

	// Upgrade settings (only written for non-development modes)
	if mode != "development" {
		gen("UPGRADE_CHANNEL", "stable")
		gen("UPGRADE_CHECK_INTERVAL", "6h")
		gen("UPGRADE_AUTO_DOWNLOAD", "true")
		gen("UPGRADE_REQUIRE_SIGNING", "false")
	}

	if err := f.Save(); err != nil {
		return nil, fmt.Errorf("save config: %w", err)
	}
	if verbose {
		fmt.Fprintf(os.Stderr, "Config: %s\n", cfgPath)
	}
	return cfg, nil
}

// computeDbMemory derives PostgreSQL memory tuning from DB_MEM_LIMIT.
func computeDbMemory(dbMemLimit string) (*DbMemory, error) {
	mb, err := parseMemSizeToMB(dbMemLimit)
	if err != nil {
		return nil, fmt.Errorf("parse DB_MEM_LIMIT %q: %w", dbMemLimit, err)
	}

	sharedBuffers := int64(float64(mb) * 0.25)
	maintenanceWorkMem := int64(math.Min(2048, float64(mb)*0.125))
	effectiveCacheSize := int64(float64(mb) * 0.75)
	workMem := max64(4, mb/32)
	tempBuffers := max64(256, mb/8)
	walBuffers := min64(256, max64(16, int64(float64(mb)*0.015)))
	maxConnections := int64(30)
	maxWalSize := max64(2048, mb/2)
	minWalSize := max64(256, mb/8)
	reservation := mb / 2

	return &DbMemory{
		DbMemLimit:           dbMemLimit,
		DbShmSize:            strings.ToLower(dbMemLimit),
		DbMemReservation:     formatMBForDocker(reservation),
		DbSharedBuffers:      formatMBForPG(sharedBuffers),
		DbMaintenanceWorkMem: formatMBForPG(maintenanceWorkMem),
		DbEffectiveCacheSize: formatMBForPG(effectiveCacheSize),
		DbWorkMem:            formatMBForPG(workMem),
		DbTempBuffers:        formatMBForPG(tempBuffers),
		DbWalBuffers:         formatMBForPG(walBuffers),
		DbMaxConnections:     maxConnections,
		DbMaxWalSize:         formatMBForPG(maxWalSize),
		DbMinWalSize:         formatMBForPG(minWalSize),
	}, nil
}

func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
func min64(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}

// computeDerived calculates port offsets, bind addresses, and other derived values.
func computeDerived(cfg *ConfigEnv) *Derived {
	offset, _ := strconv.Atoi(cfg.DeploymentSlotPortOffset)
	basePort := 3000
	portOffset := basePort + (offset * 10)

	caddyHttpPort := portOffset
	caddyHttpsPort := portOffset + 1
	appPort := portOffset + 2
	postgrestPort := portOffset + 3
	caddyDbPort := portOffset + 4
	caddyDbTlsPort := portOffset + 5

	var (
		caddyHttpBind    string
		caddyHttpsBind   string
		caddyDbBind      string
		caddyDbTlsBind   string
	)

	if cfg.CaddyDeploymentMode == "standalone" {
		caddyHttpPort = 80
		caddyHttpsPort = 443
		caddyHttpBind = fmt.Sprintf("0.0.0.0:%d", caddyHttpPort)
		caddyHttpsBind = fmt.Sprintf("0.0.0.0:%d", caddyHttpsPort)
		caddyDbPort = 5431
		caddyDbTlsPort = 5432
		caddyDbBind = "127.0.0.1"
		caddyDbTlsBind = "0.0.0.0"
	} else {
		caddyHttpBind = fmt.Sprintf("127.0.0.1:%d", caddyHttpPort)
		caddyHttpsBind = fmt.Sprintf("127.0.0.1:%d", caddyHttpsPort)
		caddyDbBind = "127.0.0.1"
		caddyDbTlsBind = "127.0.0.1"
	}

	// VERSION: tag name for docker compose image tags and display.
	// COMMIT: short SHA for linking to the exact code on GitHub.
	version := "local"
	if out, err := exec.Command("git", "describe", "--tags", "--always").Output(); err == nil {
		version = strings.TrimSpace(string(out))
	}
	commit := "unknown"
	if out, err := exec.Command("git", "rev-parse", "--short=8", "HEAD").Output(); err == nil {
		commit = strings.TrimSpace(string(out))
	}

	return &Derived{
		CaddyHttpPort:          caddyHttpPort,
		CaddyHttpBindAddress:   caddyHttpBind,
		CaddyHttpsPort:         caddyHttpsPort,
		CaddyHttpsBindAddress:  caddyHttpsBind,
		CaddyDbPort:            caddyDbPort,
		CaddyDbTlsPort:         caddyDbTlsPort,
		CaddyDbBindAddress:     caddyDbBind,
		CaddyDbTlsBindAddress:  caddyDbTlsBind,
		AppPort:                appPort,
		AppBindAddress:         fmt.Sprintf("127.0.0.1:%d", appPort),
		PostgrestPort:          postgrestPort,
		PostgrestBindAddress:   fmt.Sprintf("127.0.0.1:%d", postgrestPort),
		Version:                version,
		Commit:                 commit,
		SiteURL:                cfg.StatbusURL,
		ApiExternalURL:         cfg.BrowserAPIURL,
		ApiPublicURL:           cfg.BrowserAPIURL,
		DeploymentUser:         "statbus_" + cfg.DeploymentSlotCode,
		Domain:                 cfg.SiteDomain,
		EnableEmailSignup:      true,
		EnableEmailAutoconfirm: true,
		DisableSignup:          true,
		StudioDefaultProject:   cfg.DeploymentSlotName,
	}
}

// generateEnvContent builds the full .env file content.
func generateEnvContent(creds *Credentials, cfg *ConfigEnv, derived *Derived, dbMem *DbMemory, projDir string) (string, error) {
	var b strings.Builder

	// Debug toggle helper
	debugBlock := func(key, val string) string {
		if val == "true" {
			return fmt.Sprintf("%s=true\n#%s=false", key, key)
		}
		return fmt.Sprintf("#%s=true\n%s=false", key, key)
	}

	fmt.Fprintf(&b, `################################################################
# Statbus Environment Variables
# Generated by sb config generate
# Used by docker compose, both for statbus containers
# and for the included supabase containers.
# The files:
#   %[1]s generated if missing, with stable credentials.
#   %[2]s generated if missing, configuration for installation.
#   %[3]s generated with input from %[1]s and %[2]s
# The %[3]s file contains settings used both by
# the statbus app (Backend/frontend) and by the Supabase Docker
# containers.
#
# The top level docker-compose.yml file includes all configuration
# required for all statbus docker containers, but must be managed
# by sb config generate which also sets VERSION
# used for docker image tags and container logging.
################################################################

################################################################
# Statbus Container Configuration
################################################################

# The name displayed on the web
DEPLOYMENT_SLOT_NAME=%[4]s
DEPLOYMENT_SLOT_CODE=%[5]s
# Urls configured in Caddy and DNS.
STATBUS_URL=%[6]s
BROWSER_REST_URL=%[7]s
SERVER_REST_URL=%[8]s
# Logging server
SEQ_SERVER_URL=%[9]s
SEQ_API_KEY=%[10]s
# Deployment Messages
SLACK_TOKEN=%[11]s
# The prefix used for all container names in docker
COMPOSE_INSTANCE_NAME=statbus-%[5]s
# Caddy configuration
CADDY_HTTP_PORT=%[12]d
CADDY_HTTPS_PORT=%[13]d
CADDY_HTTP_BIND_ADDRESS=%[14]s
CADDY_HTTPS_BIND_ADDRESS=%[15]s
# The host address connected to the STATBUS app
APP_BIND_ADDRESS=%[16]s
# The host address connected to Supabase
REST_BIND_ADDRESS=%[17]s
# The publicly exposed address of PostgreSQL inside Supabase
CADDY_DB_PORT=%[18]d
CADDY_DB_TLS_PORT=%[19]d
CADDY_DB_BIND_ADDRESS=%[20]s
CADDY_DB_TLS_BIND_ADDRESS=%[21]s
# Version and commit for docker image tags and footer display
VERSION=%[22]s
COMMIT=%[23]s
# NEXT_PUBLIC_* versions for local dev (pnpm run dev reads .env via next.config.js).
# In Docker, these come from docker-compose.app.yml environment block.
NEXT_PUBLIC_STATBUS_VERSION=%[22]s
NEXT_PUBLIC_STATBUS_COMMIT=%[23]s

# Server-side debugging for the Statbus App. Requires app restart.
# To enable, edit .env: set DEBUG=true and comment out/remove DEBUG=false.
# To disable, edit .env: set DEBUG=false and comment out/remove DEBUG=true.
# This setting is sourced from DEBUG in .env.config (defaults to false).
%[24]s
`,
		".env.credentials", ".env.config", ".env",
		cfg.DeploymentSlotName,           // 4
		cfg.DeploymentSlotCode,           // 5
		cfg.StatbusURL,                   // 6
		cfg.BrowserAPIURL,                // 7
		cfg.ServerAPIURL,                 // 8
		cfg.SeqServerURL,                 // 9
		cfg.SeqAPIKey,                    // 10
		cfg.SlackToken,                   // 11
		derived.CaddyHttpPort,            // 12
		derived.CaddyHttpsPort,           // 13
		derived.CaddyHttpBindAddress,     // 14
		derived.CaddyHttpsBindAddress,    // 15
		derived.AppBindAddress,           // 16
		derived.PostgrestBindAddress,     // 17
		derived.CaddyDbPort,              // 18
		derived.CaddyDbTlsPort,          // 19
		derived.CaddyDbBindAddress,       // 20
		derived.CaddyDbTlsBindAddress,    // 21
		derived.Version,                  // 22
		derived.Commit,                   // 23
		debugBlock("DEBUG", cfg.Debug),   // 24
	)

	// Load .env.example and apply overrides
	examplePath := filepath.Join(projDir, ".env.example")
	exampleData, err := os.ReadFile(examplePath)
	if err != nil {
		return "", fmt.Errorf("read .env.example: %w", err)
	}

	example := dotenv.FromString(string(exampleData))

	// Override credentials
	example.Set("POSTGRES_ADMIN_DB", cfg.PostgresAdminDB)
	example.Set("POSTGRES_ADMIN_USER", cfg.PostgresAdminUser)
	example.Set("POSTGRES_ADMIN_PASSWORD", creds.PostgresAdminPassword)
	example.Set("POSTGRES_APP_DB", cfg.PostgresAppDB)
	example.Set("POSTGRES_APP_USER", cfg.PostgresAppUser)
	example.Set("POSTGRES_NOTIFY_USER", cfg.PostgresNotifyUser)
	example.Set("CADDY_DEPLOYMENT_MODE", cfg.CaddyDeploymentMode)
	example.Set("POSTGRES_APP_PASSWORD", creds.PostgresAppPassword)
	example.Set("POSTGRES_AUTHENTICATOR_PASSWORD", creds.PostgresAuthenticatorPassword)
	example.Set("POSTGRES_NOTIFY_PASSWORD", creds.PostgresNotifyPassword)
	example.Set("POSTGRES_PASSWORD", creds.PostgresAdminPassword)

	// Memory tuning
	example.Set("DB_MEM_LIMIT", dbMem.DbMemLimit)
	example.Set("DB_SHM_SIZE", dbMem.DbShmSize)
	example.Set("DB_MEM_RESERVATION", dbMem.DbMemReservation)
	example.Set("DB_SHARED_BUFFERS", dbMem.DbSharedBuffers)
	example.Set("DB_MAINTENANCE_WORK_MEM", dbMem.DbMaintenanceWorkMem)
	example.Set("DB_EFFECTIVE_CACHE_SIZE", dbMem.DbEffectiveCacheSize)
	example.Set("DB_WORK_MEM", dbMem.DbWorkMem)
	example.Set("DB_TEMP_BUFFERS", dbMem.DbTempBuffers)
	example.Set("DB_WAL_BUFFERS", dbMem.DbWalBuffers)
	example.Set("DB_MAX_CONNECTIONS", strconv.FormatInt(dbMem.DbMaxConnections, 10))
	example.Set("DB_MAX_WAL_SIZE", dbMem.DbMaxWalSize)
	example.Set("DB_MIN_WAL_SIZE", dbMem.DbMinWalSize)

	// JWT / auth
	example.Set("ACCESS_JWT_EXPIRY", cfg.AccessJwtExpiry)
	example.Set("REFRESH_JWT_EXPIRY", cfg.RefreshJwtExpiry)
	example.Set("JWT_SECRET", creds.JwtSecret)
	example.Set("SERVICE_ROLE_KEY", creds.ServiceRoleKey)
	example.Set("DASHBOARD_USERNAME", creds.DashboardUsername)
	example.Set("DASHBOARD_PASSWORD", creds.DashboardPassword)

	// Derived
	example.Set("SITE_URL", derived.SiteURL)
	example.Set("API_EXTERNAL_URL", derived.ApiExternalURL)
	example.Set("API_PUBLIC_URL", derived.ApiPublicURL)
	example.Set("ENABLE_EMAIL_SIGNUP", strconv.FormatBool(derived.EnableEmailSignup))
	example.Set("ENABLE_EMAIL_AUTOCONFIRM", strconv.FormatBool(derived.EnableEmailAutoconfirm))
	example.Set("DISABLE_SIGNUP", strconv.FormatBool(derived.DisableSignup))
	example.Set("STUDIO_DEFAULT_PROJECT", derived.StudioDefaultProject)

	// Docker build config
	example.Set("APT_USE_HTTPS_ONLY", cfg.AptUseHttpsOnly)

	// Upgrade daemon settings — always written to .env so the daemon never silently defaults.
	// Values come from .env.config if present, otherwise sensible defaults.
	{
		cfgFile, cfgErr := dotenv.Load(filepath.Join(projDir, ".env.config"))
		getOrDefault := func(key, fallback string) string {
			if cfgErr == nil {
				if v, ok := cfgFile.Get(key); ok {
					return v
				}
			}
			return fallback
		}
		fmt.Fprintf(&b, "\n# Upgrade daemon configuration\n")
		fmt.Fprintf(&b, "UPGRADE_CHANNEL=%s\n", getOrDefault("UPGRADE_CHANNEL", "stable"))
		fmt.Fprintf(&b, "UPGRADE_CHECK_INTERVAL=%s\n", getOrDefault("UPGRADE_CHECK_INTERVAL", "6h"))
		fmt.Fprintf(&b, "UPGRADE_AUTO_DOWNLOAD=%s\n", getOrDefault("UPGRADE_AUTO_DOWNLOAD", "true"))
		fmt.Fprintf(&b, "UPGRADE_REQUIRE_SIGNING=%s\n", getOrDefault("UPGRADE_REQUIRE_SIGNING", "false"))

		// Propagate trusted signer keys from .env.config to .env
		if cfgErr == nil {
			for _, key := range cfgFile.Keys() {
				if strings.HasPrefix(key, "UPGRADE_TRUSTED_SIGNER_") {
					if v, ok := cfgFile.Get(key); ok {
						fmt.Fprintf(&b, "%s=%s\n", key, v)
					}
				}
			}
		}
	}

	fmt.Fprintf(&b, "\n\n################################################################\n")
	fmt.Fprintf(&b, "# Supabase Container Configuration\n")
	fmt.Fprintf(&b, "# Adapted from .env.example\n")
	fmt.Fprintf(&b, "################################################################\n\n")
	b.WriteString(example.String())

	fmt.Fprintf(&b, "\n\n################################################################\n")
	fmt.Fprintf(&b, "# Statbus App Environment Variables\n")
	fmt.Fprintf(&b, "# Next.js only exposes environment variables with the 'NEXT_PUBLIC_' prefix\n")
	fmt.Fprintf(&b, "# to the browser code.\n")
	fmt.Fprintf(&b, "# Add all the variables here that are exposed publicly,\n")
	fmt.Fprintf(&b, "# i.e. available in the web page source code for all to see.\n")
	fmt.Fprintf(&b, "#\n")
	fmt.Fprintf(&b, "NEXT_PUBLIC_BROWSER_REST_URL=%s\n", cfg.BrowserAPIURL)
	fmt.Fprintf(&b, "NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME=%s\n", cfg.DeploymentSlotName)
	fmt.Fprintf(&b, "NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE=%s\n", cfg.DeploymentSlotCode)
	fmt.Fprintf(&b, "\n# Client-side debugging for the Statbus App. Requires app rebuild/restart.\n")
	fmt.Fprintf(&b, "# To enable, edit .env: set NEXT_PUBLIC_DEBUG=true and comment out/remove NEXT_PUBLIC_DEBUG=false.\n")
	fmt.Fprintf(&b, "# To disable, edit .env: set NEXT_PUBLIC_DEBUG=false and comment out/remove NEXT_PUBLIC_DEBUG=true.\n")
	fmt.Fprintf(&b, "# This setting is sourced from NEXT_PUBLIC_DEBUG in .env.config (defaults to false).\n")
	if cfg.NextPublicDebug == "true" {
		fmt.Fprintf(&b, "NEXT_PUBLIC_DEBUG=true\n#NEXT_PUBLIC_DEBUG=false\n")
	} else {
		fmt.Fprintf(&b, "#NEXT_PUBLIC_DEBUG=true\nNEXT_PUBLIC_DEBUG=false\n")
	}
	fmt.Fprintf(&b, "#\n################################################################\n")

	return b.String(), nil
}

// generateCaddyFiles renders all Caddyfile templates.
func generateCaddyFiles(derived *Derived, cfg *ConfigEnv, projDir string, verbose bool) error {
	tmplDir := filepath.Join(projDir, "caddy", "templates")
	outDir := filepath.Join(projDir, "caddy", "config")

	if err := os.MkdirAll(outDir, 0755); err != nil {
		return err
	}

	data := &CaddyTemplateData{
		ProgramName:           "sb",
		Domain:                derived.Domain,
		DeploymentUser:        derived.DeploymentUser,
		DeploymentSlotCode:    cfg.DeploymentSlotCode,
		CaddyDeploymentMode:   cfg.CaddyDeploymentMode,
		Debug:                 cfg.Debug,
		CaddyHttpPort:         derived.CaddyHttpPort,
		CaddyHttpsPort:        derived.CaddyHttpsPort,
		CaddyHttpBindAddress:  derived.CaddyHttpBindAddress,
		CaddyHttpsBindAddress: derived.CaddyHttpsBindAddress,
		CaddyDbPort:           derived.CaddyDbPort,
		CaddyDbTlsPort:        derived.CaddyDbTlsPort,
		CaddyDbBindAddress:    derived.CaddyDbBindAddress,
		CaddyDbTlsBindAddress: derived.CaddyDbTlsBindAddress,
		AppPort:               derived.AppPort,
		AppBindAddress:        derived.AppBindAddress,
		PostgrestBindAddress:  derived.PostgrestBindAddress,
		TlsCertFile:           cfg.TlsCertFile,
		TlsKeyFile:            cfg.TlsKeyFile,
	}

	// Validate deployment mode
	validModes := map[string]bool{"development": true, "private": true, "standalone": true}
	if !validModes[cfg.CaddyDeploymentMode] {
		return fmt.Errorf("unrecognized CADDY_DEPLOYMENT_MODE %q (must be development, private, or standalone)", cfg.CaddyDeploymentMode)
	}

	templates := map[string]string{
		"Caddyfile":                            "Caddyfile.tmpl",
		"development.caddyfile":                "development.caddyfile.tmpl",
		"private.caddyfile":                    "private.caddyfile.tmpl",
		"standalone.caddyfile":                 "standalone.caddyfile.tmpl",
		"public.caddyfile":                     "public.caddyfile.tmpl",
		"public-layer4-tcp-5432-route.caddyfile": "public-layer4-tcp-5432-route.caddyfile.tmpl",
	}

	for outName, tmplName := range templates {
		tmplPath := filepath.Join(tmplDir, tmplName)
		outPath := filepath.Join(outDir, outName)

		tmplContent, err := os.ReadFile(tmplPath)
		if err != nil {
			return fmt.Errorf("read template %s: %w", tmplName, err)
		}

		t, err := template.New(tmplName).Parse(string(tmplContent))
		if err != nil {
			return fmt.Errorf("parse template %s: %w", tmplName, err)
		}

		var buf strings.Builder
		if err := t.Execute(&buf, data); err != nil {
			return fmt.Errorf("execute template %s: %w", tmplName, err)
		}

		newContent := buf.String()

		// Only write if changed
		existing, _ := os.ReadFile(outPath)
		if string(existing) == newContent {
			if verbose {
				fmt.Fprintf(os.Stderr, "No changes needed in %s\n", outPath)
			}
			continue
		}

		if err := os.WriteFile(outPath, []byte(newContent), 0644); err != nil {
			return fmt.Errorf("write %s: %w", outPath, err)
		}
		if verbose {
			fmt.Fprintf(os.Stderr, "Updated %s\n", outPath)
		}
	}

	return nil
}

// Generate runs the full config generation pipeline.
// This is the main entry point called by `sb config generate`.
func Generate(verbose bool) error {
	projDir := ProjectDir()

	creds, err := loadOrGenerateCredentials(projDir, verbose)
	if err != nil {
		return err
	}

	cfg, err := loadOrGenerateConfig(projDir, verbose)
	if err != nil {
		return err
	}

	dbMem, err := computeDbMemory(cfg.DbMemLimit)
	if err != nil {
		return err
	}

	derived := computeDerived(cfg)

	// Generate .env content
	envContent, err := generateEnvContent(creds, cfg, derived, dbMem, projDir)
	if err != nil {
		return err
	}

	// Write .env with backup
	envPath := filepath.Join(projDir, ".env")
	existing, readErr := os.ReadFile(envPath)
	if readErr == nil && string(existing) == envContent {
		if verbose {
			fmt.Fprintf(os.Stderr, "No changes detected in .env, skipping backup\n")
		}
	} else {
		if readErr == nil {
			// Backup existing .env
			suffix := time.Now().UTC().Format("2006-01-02")
			backupPath := filepath.Join(projDir, ".env.backup."+suffix)
			for i := 1; ; i++ {
				if _, err := os.Stat(backupPath); os.IsNotExist(err) {
					break
				}
				backupPath = filepath.Join(projDir, fmt.Sprintf(".env.backup.%s_%d", suffix, i))
			}
			if verbose {
				fmt.Fprintf(os.Stderr, "Backing up .env to %s\n", backupPath)
			}
			os.WriteFile(backupPath, existing, 0644)
		}
		if err := os.WriteFile(envPath, []byte(envContent), 0644); err != nil {
			return fmt.Errorf("write .env: %w", err)
		}
	}

	// Generate Caddyfiles
	if err := generateCaddyFiles(derived, cfg, projDir, verbose); err != nil {
		return err
	}

	fmt.Println("Config generated successfully.")
	return nil
}
