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
	"encoding/json"
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
	DashboardUsername             string
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
	// PostgresSeedDB is the canonical fresh-from-migrations DB.
	// Build-time only; never worker-active. Dumped by `./sb db seed
	// dump` into the published statbus-seed image. Slot-independent
	// (one seed per workspace, not per deployment slot).
	PostgresSeedDB       string
	PostgresAppUser      string
	PostgresNotifyUser   string
	AccessJwtExpiry      string
	RefreshJwtExpiry     string
	CaddyDeploymentMode  string
	SiteDomain           string
	Debug                string
	NextPublicDebug      string
	DbMemLimit           string
	TlsCertFile          string
	TlsKeyFile           string
	AptUseHttpsOnly      string
	AdministratorContact string
	// UpgradeChannel is what this box follows. STATBUS-307: it is DERIVED from
	// CADDY_DEPLOYMENT_MODE on every config generate unless .env.config declares
	// one explicitly, and it is written only to the generated .env — never back
	// into .env.config. There is no longer a second key to disagree with it.
	UpgradeChannel string
}

// DbMemory holds derived PostgreSQL memory tuning values.
type DbMemory struct {
	DbMemLimit           string
	DbShmSize            string
	DbMemReservation     string
	DbSharedBuffers      string
	DbMaintenanceWorkMem string
	DbEffectiveCacheSize string
	DbWorkMem            string
	DbTempBuffers        string
	DbWalBuffers         string
	DbMaxConnections     int64
	DbMaxWalSize         string
	DbMinWalSize         string
}

// Derived holds values computed from config + credentials.
type Derived struct {
	CaddyHttpPort         int
	CaddyHttpBindAddress  string
	CaddyHttpsPort        int
	CaddyHttpsBindAddress string
	CaddyDbPort           int
	CaddyDbTlsPort        int
	CaddyDbBindAddress    string
	CaddyDbTlsBindAddress string
	AppPort               int
	AppBindAddress        string
	PostgrestPort         int
	PostgrestBindAddress  string
	// RestAdminBindAddress is the loopback host mapping for PostgREST's admin
	// server (slot offset+6), the source of the /ready signal the post-swap
	// upgrade warmup polls. Bound 127.0.0.1-only and never routed through
	// Caddy: the admin endpoints (/ready,/live,/config,/schema_cache) are
	// unauthenticated in v12, same trust level as the main REST loopback port.
	RestAdminPort        int
	RestAdminBindAddress string
	Version              string
	// CommitShort is the 8-char display form of the git commit (produced by
	// `git rev-parse --short=8 HEAD`). Length fixed at 8; not encoded in
	// the field name — there's only one short form (rc.63 canonical
	// naming). Display-only: used in .env as COMMIT_SHORT /
	// PUBLIC_STATBUS_COMMIT_SHORT so the frontend can show
	// "commit 61e79e26" links. Equality comparisons against
	// public.upgrade.commit_sha (40 chars) go through the ldflag-set
	// cmd.commit in Go, NOT through this .env-materialised form.
	//
	// NOTE: COMMIT_SHORT is also the canonical Docker image tag — see
	// docker-compose.app.yml and .github/workflows/release.yaml.
	CommitShort            string
	SiteURL                string
	ApiExternalURL         string
	ApiPublicURL           string
	DeploymentUser         string
	Domain                 string
	EnableEmailSignup      bool
	EnableEmailAutoconfirm bool
	DisableSignup          bool
	StudioDefaultProject   string
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

const credentialsHeader = `# A running system never reads this file back. Editing it changes nothing and leaves it mismatched with the database.
# To apply a changed value, delete and recreate the ENTIRE environment (destructive: all data lost; ./dev.sh recreate-database on dev, full reinstall on a production box), or apply the specific change manually with the proper commands (a support operation).
# This file's purpose is stable identity: recreates and restores get the same credentials back.`

// loadOrGenerateCredentials reads .env.credentials, generating missing values.
func loadOrGenerateCredentials(projDir string, verbose bool) (*Credentials, error) {
	credPath := filepath.Join(projDir, ".env.credentials")
	_, err := os.Stat(credPath)
	credentialsCreated := os.IsNotExist(err)
	if err != nil && !credentialsCreated {
		return nil, fmt.Errorf("stat credentials: %w", err)
	}
	f, err := dotenv.Load(credPath)
	if err != nil {
		return nil, fmt.Errorf("load credentials: %w", err)
	}
	if credentialsCreated {
		for _, line := range strings.Split(credentialsHeader, "\n") {
			f.Puts(line)
		}
		f.Puts("")
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

// notifyUserCollisionWarning returns the WARN message when appUser and
// notifyUser are identical (empty string when they're distinct, i.e. no
// warning). Pure (no I/O) so the exact wording and the trigger condition are
// unit-tested directly without capturing stderr.
func notifyUserCollisionWarning(appUser, notifyUser string) string {
	if notifyUser == "" || notifyUser != appUser {
		return ""
	}
	return fmt.Sprintf("WARN: POSTGRES_NOTIFY_USER and POSTGRES_APP_USER are both %q — "+
		"any fresh database cluster will fail to initialize (init-db.sh creates the app user "+
		"first, then refuses to create an identically-named notify user). Fix POSTGRES_NOTIFY_USER "+
		"in .env.config.\n", appUser)
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
	// POSTGRES_SEED_DB intentionally NOT slot-suffixed — the seed DB
	// is build-time-only (no worker, no per-deployment data); one
	// canonical seed per workspace serves every slot. Plan section R.
	seedDB := gen("POSTGRES_SEED_DB", "statbus_seed")
	appUser := gen("POSTGRES_APP_USER", "statbus_"+slotCode)
	notifyUser := gen("POSTGRES_NOTIFY_USER", "statbus_notify_"+slotCode)
	// LOUD WARN, never refuse: config generate is the daemon's own boot
	// pre-flight (service.go's connect path) and install's — a hard refuse
	// here would brick a currently-functional misconfigured box. The
	// collision is a LATENT hazard: a running box with an already-initialized
	// cluster is unaffected; only a FRESH cluster under this config fails
	// (init-db.sh's own hard refuse catches that case loudly). This warning
	// is the only signal an operator gets before that fresh-cluster failure.
	if w := notifyUserCollisionWarning(appUser, notifyUser); w != "" {
		fmt.Fprint(os.Stderr, w)
	}
	// STATBUS-307, the King's principle: THE DEFAULTS ARE THOSE SUITABLE FOR AN
	// NSO STANDALONE INSTALLATION. Anything else must be specified.
	//
	// This was `development` — the direct inversion. A fresh install is
	// overwhelmingly a statistical office standing up a production box, not a
	// developer's laptop; a developer already specifies their mode, and every
	// EXISTING box carries the key explicitly because gen() wrote it on first
	// generate, so this flip reaches only genuinely fresh installations.
	mode := gen("CADDY_DEPLOYMENT_MODE", "standalone")
	offsetStr := gen("DEPLOYMENT_SLOT_PORT_OFFSET", "1")

	// SITE_DOMAIN IS THE ONE KEY WITH NO HONEST DEFAULT, and the reason is the
	// rule that decides every other default in this function:
	//
	//	A default is honest when the PRODUCT owns the fact, and dishonest when
	//	the WORLD owns it.
	//
	// The product may declare "you are a standalone production installation" —
	// that is a statement about itself. It may not declare "your domain is
	// X.statbus.org" — that is a statement about a world it cannot see, and on a
	// standalone box it is certainly wrong: statbus.org is ours, not the
	// statistical office's. Generating it anyway produces a configuration that
	// cannot serve, discovered later and further from the cause.
	//
	// Scoped to standalone deliberately. Development and private slots are OUR
	// deployments, where <slot>.statbus.org IS the honest value and the existing
	// default stays correct.
	if mode == "standalone" {
		if _, ok := f.Get("SITE_DOMAIN"); !ok {
			return nil, newRefusal(missingSiteDomainRefusal())
		}
	}
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
		PostgresSeedDB:           seedDB,
		PostgresAppUser:          appUser,
		PostgresNotifyUser:       notifyUser,
		AccessJwtExpiry:          gen("ACCESS_JWT_EXPIRY", "3600"),
		RefreshJwtExpiry:         gen("REFRESH_JWT_EXPIRY", "2592000"),
		CaddyDeploymentMode:      mode,
		SiteDomain:               siteDomain,
		Debug:                    gen("DEBUG", "false"),
		NextPublicDebug:          gen("PUBLIC_DEBUG", "false"),
		DbMemLimit:               gen("DB_MEM_LIMIT", "4G"),
		TlsCertFile:              gen("TLS_CERT_FILE", ""),
		TlsKeyFile:               gen("TLS_KEY_FILE", ""),
		AptUseHttpsOnly:          gen("APT_USE_HTTPS_ONLY", "false"),
		AdministratorContact:     gen("ADMINISTRATOR_CONTACT", ""),
	}

	// STATBUS-307 fleet transition. Runs BEFORE resolution so a box carrying the
	// retired key resolves against its translated state in the same pass, rather
	// than deriving from mode this time and picking up its declared channel only
	// on the next generate — which would move a leading box onto stable for one
	// cycle. Ordering is the whole correctness of it.
	//
	// f.Save() at the end of this function persists the mutation; the notice goes
	// to stderr because a box quietly rewriting its own configuration is the
	// thing this ticket exists to stop, even when the rewrite is right.
	if notice := MigrateLegacyUpgradeRole(f, mode); notice != "" {
		fmt.Fprint(os.Stderr, notice)
	}

	// STATBUS-307: the channel is derived from the deployment mode unless
	// .env.config declares one. Deliberately NOT a gen() call — gen preserves an
	// existing value forever AND writes its default back into .env.config, and
	// both are wrong here. Writing it back would re-create the seeded value whose
	// staleness let five production installations follow release candidates for
	// two months; preserving it forever would stop a mode change from moving the
	// derived channel of a box that never stated one. The full reasoning is in
	// upgrade_channel.go.
	upgradeChannel, err := ResolveUpgradeChannel(f, mode)
	if err != nil {
		// A refusal, not a warning. The failure this ticket exists for was a
		// channel nobody could see was wrong; continuing past an invalid
		// declaration would reproduce exactly that.
		return nil, err
	}
	cfg.UpgradeChannel = upgradeChannel

	// UPGRADE_CALLBACK (STATBUS-131): shell command invoked on install
	// completion and on every upgrade start/success/failure/park event
	// (see ops/notify-slack.sh for the reference implementation). Written
	// unconditionally (default empty, all modes) so .env.config is the
	// self-documenting, durable home for this key — the operator sets it
	// there, NOT in the generated .env, which this same command overwrites
	// on every install and at upgrade step 3.1.
	gen("UPGRADE_CALLBACK", "")

	// Upgrade-service polling settings — only the deployed service uses these,
	// so they are written for non-development modes only.
	if mode != "development" {
		gen("UPGRADE_CHECK_INTERVAL", "6h")
		gen("UPGRADE_AUTO_DOWNLOAD", "true")
		// Scheduled logical-backup settings (STATBUS-113): the always-on upgrade
		// service takes a periodic pg_dump (BACKUP_INTERVAL) and prunes the dump
		// dir to BACKUP_RETENTION_COUNT. Default on for standalone installs where
		// this IS the backup; set BACKUP_ENABLED=false to opt out (e.g. a box with
		// its own infra-level snapshots).
		gen("BACKUP_ENABLED", "true")
		gen("BACKUP_INTERVAL", "24h")
		gen("BACKUP_RETENTION_COUNT", "7")
		// Signing is enforced when UPGRADE_TRUSTED_SIGNER_* keys are present.
		// No separate flag needed — key presence determines enforcement.
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
	// +6: PostgREST admin server (loopback-only /ready warmup signal). Verified
	// free in every mode — config.go assigns only +0..+5, and standalone
	// overrides only http/https/db, so +6 is uniform across all deployment modes.
	restAdminPort := portOffset + 6

	var (
		caddyHttpBind  string
		caddyHttpsBind string
		caddyDbBind    string
		caddyDbTlsBind string
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

	// VERSION: `git describe` output for display / ldflag. Not the Docker
	// image tag — see COMMIT_SHORT below.
	// COMMIT_SHORT: 8-char commit SHA. Tracks `git rev-parse --short=8 HEAD`.
	// Two purposes:
	//  1. Canonical Docker image tag (rc.63: images are tagged by commit
	//     identity, not by release label — see docker-compose.app.yml).
	//  2. Display in the frontend for "commit 61e79e26" links.
	// Equality comparisons against public.upgrade.commit_sha (40 chars)
	// go through the ldflag-set cmd.commit in Go, not through this
	// display form.
	version := "local"
	if out, err := exec.Command("git", "describe", "--tags", "--always").Output(); err == nil {
		version = strings.TrimSpace(string(out))
	}
	commitShort := "unknown"
	if out, err := exec.Command("git", "rev-parse", "--short=8", "HEAD").Output(); err == nil {
		commitShort = strings.TrimSpace(string(out))
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
		RestAdminPort:          restAdminPort,
		RestAdminBindAddress:   fmt.Sprintf("127.0.0.1:%d", restAdminPort),
		Version:                version,
		CommitShort:            commitShort,
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

// restExposedSchemas is the value config.go OWNS for PGRST_DB_SCHEMAS. Only
// `public` is served over /rest: the app never sends Accept-Profile/Content-Profile
// (it is single-schema), and the auth entry points are public.login/refresh/logout —
// auth is reached THROUGH public, not exposed as its own REST schema. The worker
// schema is deliberately excluded and surfaced via public views. The Supabase-legacy
// `storage` and `graphql_public` in .env.example were NEVER created here; PostgREST
// v14 HARD-FAILS the entire schema-cache load when any listed schema is absent (v12
// silently loaded only what existed), which parked dev's v14 upgrade with `schema
// "storage" does not exist` and a /ready that 503'd forever. config.go emitting only
// existing schemas heals every box on `sb config generate` by overwriting the stale
// template value persisted in a box's .env (STATBUS-054). Add a schema here only when
// we genuinely expose it over /rest.
const restExposedSchemas = "public"

// generateEnvContent builds the full .env file content.
// generateEnvContent renders the generated .env content, and — STATBUS-332 —
// the restart-class SET each key it writes belongs to. Classes are declared
// immediately after the write that decides each key's value: the giant
// positional-format block below (26 keys, one Fprintf, chosen deliberately
// LOW-RISK over restructuring into 26 individual calls — see the comment at
// its declare block) and the .Set()-based Supabase/JWT/memory-tuning keys
// (via setKV, a thin wrapper) both keep the value write and its class
// declaration in the SAME function, adjacent, in one commit — never a
// separate table someone else maintains and forgets (architect's ruling).
//
// Classification method: mechanical, not guessed — every class below was
// checked against the actual consumer, either a literal `${KEY}`
// interpolation in one of the 5 docker-compose files (app/worker/rest/db/
// proxy), a Caddy template field ACTUALLY used in caddy/templates/*.tmpl
// (checked by literal grep, not by which fields CaddyTemplateData merely
// populates — AppBindAddress and PostgrestBindAddress are populated but
// unused by any current template, so they are NOT proxy-restart-classed),
// postgres/start-postgres.sh's own env reads (the DB_* memory-tuning keys,
// consumed via a custom entrypoint script rather than compose
// interpolation), or a daemon field Service.loadConfig()/loadTrustedSigners()
// caches once at startup (cli/internal/upgrade/service.go). Keys read FRESH
// on every use (UPGRADE_CALLBACK, STATBUS_URL, ADMINISTRATOR_CONTACT — all
// call dotenv.Load(".env") themselves at the moment they're needed, verified
// by reading runCallback/readAdministratorContact directly) need no restart
// at all: class none. Keys with zero verified consumer anywhere in this
// repo (legacy Supabase/GoTrue/Studio template carryovers this project's
// trimmed compose stack never runs — SERVICE_ROLE_KEY, DASHBOARD_*,
// API_EXTERNAL_URL, API_PUBLIC_URL, ENABLE_EMAIL_*, DISABLE_SIGNUP,
// STUDIO_DEFAULT_PROJECT — plus intermediate/derived values folded into
// OTHER keys that ARE classed, like CADDY_HTTP_PORT/CADDY_HTTPS_PORT feeding
// CADDY_HTTP_BIND_ADDRESS) are also class none.
//
// ONE KNOWN GAP, recorded rather than silently absorbed: APT_USE_HTTPS_ONLY
// is a `build: args:` value (postgres/docker-compose.yml) — it affects
// `docker compose build`, not a running container, so no RESTART class
// actually applies to it; classed `db` here as the closest available
// signal (something about db needs operator attention) rather than adding
// an eighth class for one build-time-only key the night before a cut.
func generateEnvContent(creds *Credentials, cfg *ConfigEnv, derived *Derived, dbMem *DbMemory, projDir string) (string, map[string][]RestartClass, error) {
	var b strings.Builder
	classes := newEnvKeyClasses()

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
# Domain and URLs configured in Caddy and DNS.
SITE_DOMAIN=%[25]s
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
# PostgREST admin server — loopback-only (slot offset+6). Source of the /ready
# signal the post-swap upgrade health check polls. NEVER public, no Caddy route.
REST_ADMIN_BIND_ADDRESS=%[26]s
# The publicly exposed address of PostgreSQL inside Supabase
CADDY_DB_PORT=%[18]d
CADDY_DB_TLS_PORT=%[19]d
CADDY_DB_BIND_ADDRESS=%[20]s
CADDY_DB_TLS_BIND_ADDRESS=%[21]s
# Version and commit for docker image tags and server-side config injection.
# layout.tsx reads these via process.env and injects into HTML as window.__STATBUS_CONFIG__.
# COMMIT_SHORT is the 8-char display form (git rev-parse --short=8 HEAD)
# AND the canonical Docker image tag (rc.63: images tagged by commit
# identity, not release label).
# Equality comparisons against public.upgrade.commit_sha use the 40-char
# cmd.commit ldflag in Go, not this .env value.
VERSION=%[22]s
COMMIT_SHORT=%[23]s
PUBLIC_STATBUS_VERSION=%[22]s
PUBLIC_STATBUS_COMMIT_SHORT=%[23]s

# Server-side debugging for the Statbus App. Requires app restart.
# To enable, edit .env: set DEBUG=true and comment out/remove DEBUG=false.
# To disable, edit .env: set DEBUG=false and comment out/remove DEBUG=true.
# This setting is sourced from DEBUG in .env.config (defaults to false).
%[24]s
`,
		".env.credentials", ".env.config", ".env",
		cfg.DeploymentSlotName,         // 4
		cfg.DeploymentSlotCode,         // 5
		cfg.StatbusURL,                 // 6
		cfg.BrowserAPIURL,              // 7
		cfg.ServerAPIURL,               // 8
		cfg.SeqServerURL,               // 9
		cfg.SeqAPIKey,                  // 10
		cfg.SlackToken,                 // 11
		derived.CaddyHttpPort,          // 12
		derived.CaddyHttpsPort,         // 13
		derived.CaddyHttpBindAddress,   // 14
		derived.CaddyHttpsBindAddress,  // 15
		derived.AppBindAddress,         // 16
		derived.PostgrestBindAddress,   // 17
		derived.CaddyDbPort,            // 18
		derived.CaddyDbTlsPort,         // 19
		derived.CaddyDbBindAddress,     // 20
		derived.CaddyDbTlsBindAddress,  // 21
		derived.Version,                // 22
		derived.CommitShort,            // 23
		debugBlock("DEBUG", cfg.Debug), // 24
		cfg.SiteDomain,                 // 25
		derived.RestAdminBindAddress,   // 26
	)

	// STATBUS-332 restart-class declarations for the 26 keys written by the
	// Fprintf above. Kept as ONE block immediately after the writer that
	// decided their values — not scattered per-argument into the 26-slot
	// positional format string above, which would have meant hand-editing a
	// dense, error-prone printf under time pressure for no additional
	// drift-safety: TestGenerateEnvContent_EveryKeyHasARestartClass (below,
	// in config_test.go) enumerates keys from a REAL generated .env, not
	// from this list, so a key added to the Fprintf without an entry here
	// fails that test immediately — the same protection a truly inline
	// declaration would give, at much lower risk to the highest-blast-radius
	// function in this package.
	classes.declare("DEPLOYMENT_SLOT_NAME") // no verified consumer (see func doc)
	classes.declare("DEPLOYMENT_SLOT_CODE", RestartApp, RestartRest, RestartDB, RestartProxyRestart)
	classes.declare("SITE_DOMAIN", RestartProxyRestart) // Caddy template field .Domain
	classes.declare("STATBUS_URL")                      // read fresh by runCallback, never cached
	classes.declare("BROWSER_REST_URL")                 // no verified consumer
	classes.declare("SERVER_REST_URL")                  // app's OWN compose env hardcodes "http://proxy:80", never reads this key
	classes.declare("SEQ_SERVER_URL", RestartApp, RestartWorker)
	classes.declare("SEQ_API_KEY", RestartApp, RestartWorker)
	classes.declare("SLACK_TOKEN", RestartUpgradeDaemon) // ops/notify-slack.sh, the UPGRADE_CALLBACK reference implementation
	classes.declare("COMPOSE_INSTANCE_NAME", RestartApp, RestartWorker, RestartRest, RestartDB, RestartProxyRestart)
	classes.declare("CADDY_HTTP_PORT")  // intermediate only — folded into CADDY_HTTP_BIND_ADDRESS
	classes.declare("CADDY_HTTPS_PORT") // intermediate only — folded into CADDY_HTTPS_BIND_ADDRESS
	classes.declare("CADDY_HTTP_BIND_ADDRESS", RestartProxyRestart)
	classes.declare("CADDY_HTTPS_BIND_ADDRESS", RestartProxyRestart)
	classes.declare("APP_BIND_ADDRESS", RestartApp) // app's own compose env only; NOT a Caddy template field (verified)
	classes.declare("REST_BIND_ADDRESS", RestartRest)
	classes.declare("REST_ADMIN_BIND_ADDRESS", RestartRest)
	classes.declare("CADDY_DB_PORT", RestartProxyRestart)
	classes.declare("CADDY_DB_TLS_PORT", RestartProxyRestart)
	classes.declare("CADDY_DB_BIND_ADDRESS", RestartProxyRestart)
	classes.declare("CADDY_DB_TLS_BIND_ADDRESS", RestartProxyRestart)
	classes.declare("VERSION", RestartApp, RestartWorker)
	classes.declare("COMMIT_SHORT", RestartApp, RestartWorker, RestartDB, RestartProxyRestart)
	classes.declare("PUBLIC_STATBUS_VERSION")      // not passed via compose env to any container
	classes.declare("PUBLIC_STATBUS_COMMIT_SHORT") // not passed via compose env to any container
	classes.declare("DEBUG", RestartApp, RestartWorker, RestartDB, RestartProxyRestart)

	// Load .env.example and apply overrides
	examplePath := filepath.Join(projDir, ".env.example")
	exampleData, err := os.ReadFile(examplePath)
	if err != nil {
		return "", nil, fmt.Errorf("read .env.example: %w", err)
	}

	example := dotenv.FromString(string(exampleData))

	// setKV writes an override into the .env.example-derived body AND
	// declares its restart class at this same call site (STATBUS-332) — the
	// class travels with the value, in the same edit, forever.
	setKV := func(key, val string, cls ...RestartClass) {
		example.Set(key, val)
		classes.declare(key, cls...)
	}

	// Override credentials
	setKV("POSTGRES_ADMIN_DB", cfg.PostgresAdminDB, RestartDB)
	setKV("POSTGRES_ADMIN_USER", cfg.PostgresAdminUser, RestartDB, RestartWorker)
	setKV("POSTGRES_ADMIN_PASSWORD", creds.PostgresAdminPassword, RestartDB, RestartWorker)
	setKV("POSTGRES_APP_DB", cfg.PostgresAppDB, RestartDB, RestartWorker)
	setKV("POSTGRES_SEED_DB", cfg.PostgresSeedDB) // one-shot CLI reads only (db.go/seed.go/dbdump.go) — always fresh, no restart
	setKV("POSTGRES_APP_USER", cfg.PostgresAppUser, RestartDB)
	setKV("POSTGRES_NOTIFY_USER", cfg.PostgresNotifyUser, RestartApp, RestartDB)
	setKV("CADDY_DEPLOYMENT_MODE", cfg.CaddyDeploymentMode, RestartProxyRestart) // proxy compose env AND Caddy template field .CaddyDeploymentMode
	setKV("POSTGRES_APP_PASSWORD", creds.PostgresAppPassword, RestartApp, RestartDB)
	setKV("POSTGRES_AUTHENTICATOR_PASSWORD", creds.PostgresAuthenticatorPassword, RestartApp, RestartRest, RestartDB)
	setKV("POSTGRES_NOTIFY_PASSWORD", creds.PostgresNotifyPassword, RestartApp, RestartDB)
	setKV("POSTGRES_PASSWORD", creds.PostgresAdminPassword, RestartDB) // the postgres image's own var name for POSTGRES_ADMIN_PASSWORD

	// Memory tuning — read by postgres/start-postgres.sh's own entrypoint at
	// container start (not compose `${VAR}` interpolation; verified via
	// postgres/postgresql.conf + start-postgres.sh, not assumed absent
	// merely because they're outside the 5 compose files' environment: blocks).
	setKV("DB_MEM_LIMIT", dbMem.DbMemLimit, RestartDB)
	setKV("DB_SHM_SIZE", dbMem.DbShmSize, RestartDB)
	setKV("DB_MEM_RESERVATION", dbMem.DbMemReservation, RestartDB)
	setKV("DB_SHARED_BUFFERS", dbMem.DbSharedBuffers, RestartDB)
	setKV("DB_MAINTENANCE_WORK_MEM", dbMem.DbMaintenanceWorkMem, RestartDB)
	setKV("DB_EFFECTIVE_CACHE_SIZE", dbMem.DbEffectiveCacheSize, RestartDB)
	setKV("DB_WORK_MEM", dbMem.DbWorkMem, RestartDB)
	setKV("DB_TEMP_BUFFERS", dbMem.DbTempBuffers, RestartDB)
	setKV("DB_WAL_BUFFERS", dbMem.DbWalBuffers, RestartDB)
	setKV("DB_MAX_CONNECTIONS", strconv.FormatInt(dbMem.DbMaxConnections, 10), RestartDB)
	setKV("DB_MAX_WAL_SIZE", dbMem.DbMaxWalSize, RestartDB)
	setKV("DB_MIN_WAL_SIZE", dbMem.DbMinWalSize, RestartDB)

	// JWT / auth
	setKV("ACCESS_JWT_EXPIRY", cfg.AccessJwtExpiry, RestartRest, RestartDB)
	setKV("REFRESH_JWT_EXPIRY", cfg.RefreshJwtExpiry, RestartRest)
	setKV("JWT_SECRET", creds.JwtSecret, RestartRest, RestartDB)
	setKV("SERVICE_ROLE_KEY", creds.ServiceRoleKey)      // legacy Supabase key; no container in this project's compose stack consumes it
	setKV("DASHBOARD_USERNAME", creds.DashboardUsername) // Supabase Studio — not run by this project's compose stack
	setKV("DASHBOARD_PASSWORD", creds.DashboardPassword) // Supabase Studio — not run by this project's compose stack

	// Derived
	setKV("SITE_URL", derived.SiteURL, RestartRest)
	setKV("API_EXTERNAL_URL", derived.ApiExternalURL)                                     // legacy Supabase — no consumer in this compose stack
	setKV("API_PUBLIC_URL", derived.ApiPublicURL)                                         // legacy Supabase — no consumer in this compose stack
	setKV("ENABLE_EMAIL_SIGNUP", strconv.FormatBool(derived.EnableEmailSignup))           // GoTrue — not run by this project
	setKV("ENABLE_EMAIL_AUTOCONFIRM", strconv.FormatBool(derived.EnableEmailAutoconfirm)) // GoTrue — not run by this project
	setKV("DISABLE_SIGNUP", strconv.FormatBool(derived.DisableSignup))                    // GoTrue — not run by this project
	setKV("STUDIO_DEFAULT_PROJECT", derived.StudioDefaultProject)                         // Supabase Studio — not run by this project

	// PostgREST — OWN the exposed-schema list (STATBUS-054). Overrides whatever
	// .env.example carries (historically the Supabase-legacy public,storage,
	// graphql_public) so a regen emits only schemas that exist; PostgREST v14 hard-
	// fails the schema-cache load otherwise. See restExposedSchemas.
	setKV("PGRST_DB_SCHEMAS", restExposedSchemas, RestartRest)

	// Docker build config. KNOWN GAP (see func doc): this is a `build: args:`
	// value — it affects `docker compose build`, never a running container,
	// so no restart class actually applies. Classed db as the closest
	// available signal rather than adding an eighth class for one build-time
	// key the night before a cut.
	setKV("APT_USE_HTTPS_ONLY", cfg.AptUseHttpsOnly, RestartDB)

	// Upgrade service settings — always written to .env so the service never silently defaults.
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
		fmt.Fprintf(&b, "\n# Upgrade service configuration\n")
		// UPGRADE_CHANNEL is written ONLY here, into the generated .env, never
		// back into .env.config (STATBUS-307). That one-way flow is what makes
		// "seeding stops" true: an unremarkable box stores nothing about upgrade
		// policy, so there is no stale value to outlive the policy that set it —
		// the failure that put five production installations on release
		// candidates for two months.
		fmt.Fprintf(&b, "# Derived from CADDY_DEPLOYMENT_MODE=%s. To follow a different channel,\n", cfg.CaddyDeploymentMode)
		fmt.Fprintf(&b, "# set %s in .env.config — not here; this file is regenerated.\n", UpgradeChannelKey)
		fmt.Fprintf(&b, "UPGRADE_CHANNEL=%s\n", cfg.UpgradeChannel)
		classes.declare("UPGRADE_CHANNEL", RestartUpgradeDaemon) // Service.loadConfig() caches d.channel at startup
		fmt.Fprintf(&b, "UPGRADE_CHECK_INTERVAL=%s\n", getOrDefault("UPGRADE_CHECK_INTERVAL", "6h"))
		classes.declare("UPGRADE_CHECK_INTERVAL", RestartUpgradeDaemon) // Service.loadConfig() caches d.interval
		fmt.Fprintf(&b, "UPGRADE_AUTO_DOWNLOAD=%s\n", getOrDefault("UPGRADE_AUTO_DOWNLOAD", "true"))
		classes.declare("UPGRADE_AUTO_DOWNLOAD", RestartUpgradeDaemon) // Service.loadConfig() caches d.autoDL
		// UPGRADE_CALLBACK (STATBUS-131): shell command invoked on install
		// completion (install.go runInstallCallback) and on upgrade
		// start/success/failure/park events (service.go runCallback). Set
		// this in .env.config — this .env file is regenerated by every `sb
		// config generate` run (including install and upgrade step 3.1), so
		// a value set only here is silently wiped on the next run. See
		// ops/notify-slack.sh for the reference implementation.
		fmt.Fprintf(&b, "UPGRADE_CALLBACK=%s\n", getOrDefault("UPGRADE_CALLBACK", ""))
		classes.declare("UPGRADE_CALLBACK") // runCallback() calls dotenv.Load(".env") itself on every invocation — never cached
		// Scheduled logical-backup settings (STATBUS-113) — read by the service's loadConfig().
		fmt.Fprintf(&b, "BACKUP_ENABLED=%s\n", getOrDefault("BACKUP_ENABLED", "true"))
		classes.declare("BACKUP_ENABLED", RestartUpgradeDaemon)
		fmt.Fprintf(&b, "BACKUP_INTERVAL=%s\n", getOrDefault("BACKUP_INTERVAL", "24h"))
		classes.declare("BACKUP_INTERVAL", RestartUpgradeDaemon)
		fmt.Fprintf(&b, "BACKUP_RETENTION_COUNT=%s\n", getOrDefault("BACKUP_RETENTION_COUNT", "7"))
		classes.declare("BACKUP_RETENTION_COUNT", RestartUpgradeDaemon)
		fmt.Fprintf(&b, "# Contact shown on maintenance.html when set; leave empty to omit\n")
		fmt.Fprintf(&b, "ADMINISTRATOR_CONTACT=%s\n", getOrDefault("ADMINISTRATOR_CONTACT", ""))
		classes.declare("ADMINISTRATOR_CONTACT") // readAdministratorContact() calls dotenv.Load(".env") itself on every read — never cached
		// Propagate trusted signer keys from .env.config to .env
		if cfgErr == nil {
			for _, key := range cfgFile.Keys() {
				if strings.HasPrefix(key, "UPGRADE_TRUSTED_SIGNER_") {
					if v, ok := cfgFile.Get(key); ok {
						fmt.Fprintf(&b, "%s=%s\n", key, v)
						// Service.loadTrustedSigners() caches these at startup (and
						// re-checks at scheduled-upgrade dispatch) — declared per
						// CONCRETE key name as each one is written, since the set
						// is only known at generation time (STATBUS-332: this is
						// still "at the site", just inside a loop instead of a
						// single call).
						classes.declare(key, RestartUpgradeDaemon)
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
	// Every key that reached the generated .env verbatim from .env.example,
	// never touched by a setKV/declare call above, is a confirmed-dead
	// legacy Supabase-stack carryover (grep-verified against every compose
	// file, no consumer) — see declareIfAbsent's doc comment. This is the
	// ONE place a whole-file default is applied, and only for keys nothing
	// above already classified, so it can never mask a real key's real class.
	for _, key := range example.Keys() {
		classes.declareIfAbsent(key, RestartNone)
	}

	fmt.Fprintf(&b, "\n\n################################################################\n")
	fmt.Fprintf(&b, "# Statbus App Environment Variables\n")
	fmt.Fprintf(&b, "# Public variables — injected into HTML by layout.tsx as window.__STATBUS_CONFIG__.\n")
	fmt.Fprintf(&b, "# These are visible in the web page source code.\n")
	fmt.Fprintf(&b, "#\n")
	fmt.Fprintf(&b, "PUBLIC_BROWSER_REST_URL=%s\n", cfg.BrowserAPIURL)
	classes.declare("PUBLIC_BROWSER_REST_URL", RestartApp)
	fmt.Fprintf(&b, "PUBLIC_DEPLOYMENT_SLOT_NAME=%s\n", cfg.DeploymentSlotName)
	classes.declare("PUBLIC_DEPLOYMENT_SLOT_NAME") // not passed via compose env to any container
	fmt.Fprintf(&b, "PUBLIC_DEPLOYMENT_SLOT_CODE=%s\n", cfg.DeploymentSlotCode)
	classes.declare("PUBLIC_DEPLOYMENT_SLOT_CODE") // not passed via compose env to any container
	fmt.Fprintf(&b, "\n# Client-side debugging for the Statbus App. Requires app rebuild/restart.\n")
	fmt.Fprintf(&b, "# To enable, edit .env: set PUBLIC_DEBUG=true and comment out/remove PUBLIC_DEBUG=false.\n")
	fmt.Fprintf(&b, "# To disable, edit .env: set PUBLIC_DEBUG=false and comment out/remove PUBLIC_DEBUG=true.\n")
	fmt.Fprintf(&b, "# This setting is sourced from PUBLIC_DEBUG in .env.config (defaults to false).\n")
	if cfg.NextPublicDebug == "true" {
		fmt.Fprintf(&b, "PUBLIC_DEBUG=true\n#PUBLIC_DEBUG=false\n")
	} else {
		fmt.Fprintf(&b, "#PUBLIC_DEBUG=true\nPUBLIC_DEBUG=false\n")
	}
	classes.declare("PUBLIC_DEBUG", RestartApp)
	fmt.Fprintf(&b, "#\n################################################################\n")

	return b.String(), classes.Classes(), nil
}

// CaddyConfigFiles lists every file generateCaddyFiles writes into
// caddy/config/ — MUST match the keys of that function's own `templates`
// map below. Exported so install's config-diff step (STATBUS-332) can
// snapshot the SAME set before/after a regenerate and fold a content
// change into RestartProxyRestart: TLS_CERT_FILE/TLS_KEY_FILE are
// .env.config keys that are NEVER written into the generated .env (they
// only ever reach these Caddy templates), so a .env-only diff cannot see a
// cert-path change — this file-content comparison is the second, additive
// signal that closes that gap. TestGenerateCaddyFiles_WritesExactlyCaddyConfigFiles
// (config_test.go) proves this list stays in sync with the real output
// rather than drifting into a second, silently-stale table.
var CaddyConfigFiles = []string{
	"Caddyfile",
	"development.caddyfile",
	"private.caddyfile",
	"standalone.caddyfile",
	"public.caddyfile",
	"public-layer4-tcp-5432-route.caddyfile",
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
		"Caddyfile":                              "Caddyfile.tmpl",
		"development.caddyfile":                  "development.caddyfile.tmpl",
		"private.caddyfile":                      "private.caddyfile.tmpl",
		"standalone.caddyfile":                   "standalone.caddyfile.tmpl",
		"public.caddyfile":                       "public.caddyfile.tmpl",
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
	envContent, _, err := generateEnvContent(creds, cfg, derived, dbMem, projDir)
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
			// STATBUS-185: hard-fail. This backup is the recovery copy of the
			// current .env, and the overwrite below is exactly when it is
			// needed. Returning here — BEFORE the overwrite — is non-destructive:
			// the working .env is left intact, so a backup failure never
			// destroys the operator's only copy. Refuse loudly with a remedy.
			if err := os.WriteFile(backupPath, existing, 0644); err != nil {
				return fmt.Errorf("failed to back up the existing .env to %s: %w\n"+
					"Refusing to overwrite .env without a recovery copy — your current .env is left untouched. "+
					"Fix the cause (disk space / permissions in %s), then re-run", backupPath, err, projDir)
			}
		}
		if err := os.WriteFile(envPath, []byte(envContent), 0644); err != nil {
			return fmt.Errorf("write .env: %w", err)
		}
	}

	// Generate Caddyfiles
	if err := generateCaddyFiles(derived, cfg, projDir, verbose); err != nil {
		return err
	}

	// Generate ops/maintenance/contact.js — loaded optionally by maintenance.html
	// to show the administrator contact in the "upgrade taking too long" warning.
	// Empty contact = file is removed (maintenance.html omits the fragment).
	if err := generateMaintenanceContact(cfg.AdministratorContact, projDir, verbose); err != nil {
		return fmt.Errorf("generate maintenance contact: %w", err)
	}

	fmt.Println("Config generated successfully.")
	return nil
}

// EnvKeyRestartClasses returns the restart-class declarations made at each
// generated .env key's own write site inside generateEnvContent, WITHOUT
// writing anything (STATBUS-332). install's config-diff step calls this,
// in-process, to look up which service(s) must restart for a key that
// changed between the pre- and post-regeneration .env snapshots.
//
// This is NOT a second table: it runs the exact same load-and-generate
// pipeline Generate uses (loadOrGenerateCredentials / loadOrGenerateConfig /
// computeDbMemory / computeDerived / generateEnvContent) and simply keeps the
// classes return value that Generate itself discards — the declarations
// live only in generateEnvContent's key-writing sites, read here, never
// hand-copied.
func EnvKeyRestartClasses(projDir string) (map[string][]RestartClass, error) {
	creds, err := loadOrGenerateCredentials(projDir, false)
	if err != nil {
		return nil, err
	}
	cfg, err := loadOrGenerateConfig(projDir, false)
	if err != nil {
		return nil, err
	}
	dbMem, err := computeDbMemory(cfg.DbMemLimit)
	if err != nil {
		return nil, err
	}
	derived := computeDerived(cfg)
	_, classes, err := generateEnvContent(creds, cfg, derived, dbMem, projDir)
	if err != nil {
		return nil, err
	}
	return classes, nil
}

// generateMaintenanceContact writes ops/maintenance/contact.js with the
// ADMINISTRATOR_CONTACT value (may be empty string). maintenance.html loads
// this file optionally (onerror=void 0) and appends the contact to the
// warning message. Always writing — even when empty — avoids stale files
// left behind when the variable is cleared after an earlier non-empty run.
func generateMaintenanceContact(contact, projDir string, verbose bool) error {
	outPath := filepath.Join(projDir, "ops", "maintenance", "contact.js")
	data, err := json.Marshal(contact)
	if err != nil {
		return fmt.Errorf("marshal contact: %w", err)
	}
	content := fmt.Sprintf("window.STATBUS_ADMIN_CONTACT=%s;\n", data)
	if err := os.WriteFile(outPath, []byte(content), 0644); err != nil {
		return fmt.Errorf("write %s: %w", outPath, err)
	}
	if verbose {
		fmt.Fprintf(os.Stderr, "Wrote %s\n", outPath)
	}
	return nil
}
