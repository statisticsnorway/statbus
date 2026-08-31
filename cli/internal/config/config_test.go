package config

import (
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"
)

// TestGenerateCaddyFiles_WritesExactlyCaddyConfigFiles proves the exported
// CaddyConfigFiles list (config.go) stays in sync with what generateCaddyFiles
// actually writes — install's config-diff step (STATBUS-332) snapshots
// exactly this list before/after a regenerate to catch a TLS_CERT_FILE /
// TLS_KEY_FILE change (a .env.config key that never reaches the generated
// .env, only these Caddy templates). If a new output file is ever added to
// generateCaddyFiles's own `templates` map without updating CaddyConfigFiles,
// that new file's content changes would go undetected by the diff step —
// this test fails the moment the two lists disagree, rather than that gap
// surfacing as a silently-unapplied Caddy config change on a real box.
func TestGenerateCaddyFiles_WritesExactlyCaddyConfigFiles(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	repoRoot := filepath.Join(filepath.Dir(thisFile), "..", "..", "..")
	realTemplatesDir := filepath.Join(repoRoot, "caddy", "templates")
	entries, err := os.ReadDir(realTemplatesDir)
	if err != nil {
		t.Fatalf("read repo caddy/templates: %v", err)
	}

	projDir := t.TempDir()
	tmplDir := filepath.Join(projDir, "caddy", "templates")
	if err := os.MkdirAll(tmplDir, 0755); err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		data, err := os.ReadFile(filepath.Join(realTemplatesDir, e.Name()))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(tmplDir, e.Name()), data, 0644); err != nil {
			t.Fatal(err)
		}
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:  "local",
		DeploymentSlotName:  "local",
		CaddyDeploymentMode: "development",
		SiteDomain:          "local.statbus.org",
	}
	derived := computeDerived(cfg)

	if err := generateCaddyFiles(derived, cfg, projDir, false); err != nil {
		t.Fatalf("generateCaddyFiles: %v", err)
	}

	outDir := filepath.Join(projDir, "caddy", "config")
	written, err := os.ReadDir(outDir)
	if err != nil {
		t.Fatalf("read output dir: %v", err)
	}
	var got []string
	for _, e := range written {
		if !e.IsDir() {
			got = append(got, e.Name())
		}
	}
	sort.Strings(got)
	want := append([]string(nil), CaddyConfigFiles...)
	sort.Strings(want)

	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("generateCaddyFiles wrote %v, but CaddyConfigFiles declares %v — keep them in sync", got, want)
	}
}

func TestParseMemSizeToMB(t *testing.T) {
	tests := []struct {
		input string
		want  int64
	}{
		{"4G", 4096},
		{"8G", 8192},
		{"1G", 1024},
		{"512M", 512},
		{"256M", 256},
		{"1024K", 1},
		{"2g", 2048}, // uppercase conversion
	}
	for _, tt := range tests {
		got, err := parseMemSizeToMB(tt.input)
		if err != nil {
			t.Errorf("parseMemSizeToMB(%q) error: %v", tt.input, err)
			continue
		}
		if got != tt.want {
			t.Errorf("parseMemSizeToMB(%q) = %d, want %d", tt.input, got, tt.want)
		}
	}
}

func TestFormatMBForPG(t *testing.T) {
	tests := []struct {
		input int64
		want  string
	}{
		{1024, "1GB"},
		{2048, "2GB"},
		{512, "512MB"},
		{4096, "4GB"},
		{1536, "1536MB"}, // not evenly divisible by 1024
	}
	for _, tt := range tests {
		got := formatMBForPG(tt.input)
		if got != tt.want {
			t.Errorf("formatMBForPG(%d) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestFormatMBForDocker(t *testing.T) {
	tests := []struct {
		input int64
		want  string
	}{
		{1024, "1G"},
		{2048, "2G"},
		{512, "512M"},
		{4096, "4G"},
	}
	for _, tt := range tests {
		got := formatMBForDocker(tt.input)
		if got != tt.want {
			t.Errorf("formatMBForDocker(%d) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestComputeDbMemory4G(t *testing.T) {
	mem, err := computeDbMemory("4G")
	if err != nil {
		t.Fatal(err)
	}

	// 4G = 4096MB
	// shared_buffers: 25% = 1024MB = 1GB
	assertStr(t, "DbSharedBuffers", mem.DbSharedBuffers, "1GB")
	// effective_cache_size: 75% = 3072MB = 3GB
	assertStr(t, "DbEffectiveCacheSize", mem.DbEffectiveCacheSize, "3GB")
	// maintenance_work_mem: min(2048, 12.5%) = 512MB
	assertStr(t, "DbMaintenanceWorkMem", mem.DbMaintenanceWorkMem, "512MB")
	// work_mem: 4096/32 = 128MB
	assertStr(t, "DbWorkMem", mem.DbWorkMem, "128MB")
	// temp_buffers: max(256, 4096/8) = 512MB
	assertStr(t, "DbTempBuffers", mem.DbTempBuffers, "512MB")
	// wal_buffers: min(256, max(16, 4096*0.015=61)) = 61MB
	assertStr(t, "DbWalBuffers", mem.DbWalBuffers, "61MB")
	// max_connections: always 30
	if mem.DbMaxConnections != 30 {
		t.Errorf("DbMaxConnections = %d, want 30", mem.DbMaxConnections)
	}
	// max_wal_size: max(2048, 4096/2) = 2048
	assertStr(t, "DbMaxWalSize", mem.DbMaxWalSize, "2GB")
	// min_wal_size: max(256, 4096/8) = 512MB
	assertStr(t, "DbMinWalSize", mem.DbMinWalSize, "512MB")
	// shm_size: lowercase
	assertStr(t, "DbShmSize", mem.DbShmSize, "4g")
	// reservation: 4096/2 = 2048 = 2G
	assertStr(t, "DbMemReservation", mem.DbMemReservation, "2G")
}

func TestComputeDbMemory8G(t *testing.T) {
	mem, err := computeDbMemory("8G")
	if err != nil {
		t.Fatal(err)
	}

	// 8G = 8192MB
	assertStr(t, "DbSharedBuffers", mem.DbSharedBuffers, "2GB")
	assertStr(t, "DbEffectiveCacheSize", mem.DbEffectiveCacheSize, "6GB")
	assertStr(t, "DbMaintenanceWorkMem", mem.DbMaintenanceWorkMem, "1GB")
	assertStr(t, "DbWorkMem", mem.DbWorkMem, "256MB")
	assertStr(t, "DbTempBuffers", mem.DbTempBuffers, "1GB")
	assertStr(t, "DbWalBuffers", mem.DbWalBuffers, "122MB")
	assertStr(t, "DbMaxWalSize", mem.DbMaxWalSize, "4GB")
	assertStr(t, "DbMinWalSize", mem.DbMinWalSize, "1GB")
}

func TestComputeDerivedDevelopment(t *testing.T) {
	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}

	d := computeDerived(cfg)

	// Port offset 1: base 3000 + (1*10) = 3010
	if d.CaddyHttpPort != 3010 {
		t.Errorf("CaddyHttpPort = %d, want 3010", d.CaddyHttpPort)
	}
	if d.CaddyHttpsPort != 3011 {
		t.Errorf("CaddyHttpsPort = %d, want 3011", d.CaddyHttpsPort)
	}
	if d.AppPort != 3012 {
		t.Errorf("AppPort = %d, want 3012", d.AppPort)
	}
	if d.PostgrestPort != 3013 {
		t.Errorf("PostgrestPort = %d, want 3013", d.PostgrestPort)
	}
	if d.CaddyDbPort != 3014 {
		t.Errorf("CaddyDbPort = %d, want 3014", d.CaddyDbPort)
	}
	if d.CaddyDbTlsPort != 3015 {
		t.Errorf("CaddyDbTlsPort = %d, want 3015", d.CaddyDbTlsPort)
	}
	// PostgREST admin server: slot offset+6 = 3016, loopback-only.
	if d.RestAdminPort != 3016 {
		t.Errorf("RestAdminPort = %d, want 3016", d.RestAdminPort)
	}
	if d.RestAdminBindAddress != "127.0.0.1:3016" {
		t.Errorf("RestAdminBindAddress = %q, want 127.0.0.1:3016", d.RestAdminBindAddress)
	}
	if d.CaddyHttpBindAddress != "127.0.0.1:3010" {
		t.Errorf("CaddyHttpBindAddress = %q, want 127.0.0.1:3010", d.CaddyHttpBindAddress)
	}
	if d.DeploymentUser != "statbus_local" {
		t.Errorf("DeploymentUser = %q, want statbus_local", d.DeploymentUser)
	}
}

func TestComputeDerivedStandalone(t *testing.T) {
	cfg := &ConfigEnv{
		DeploymentSlotCode:       "mw",
		DeploymentSlotName:       "Malawi Statistics",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "standalone",
		SiteDomain:               "statbus.nso.mw",
	}

	d := computeDerived(cfg)

	if d.CaddyHttpPort != 80 {
		t.Errorf("CaddyHttpPort = %d, want 80", d.CaddyHttpPort)
	}
	if d.CaddyHttpsPort != 443 {
		t.Errorf("CaddyHttpsPort = %d, want 443", d.CaddyHttpsPort)
	}
	if d.CaddyDbPort != 5431 {
		t.Errorf("CaddyDbPort = %d, want 5431", d.CaddyDbPort)
	}
	if d.CaddyDbTlsPort != 5432 {
		t.Errorf("CaddyDbTlsPort = %d, want 5432", d.CaddyDbTlsPort)
	}
	// The admin port is offset-derived and NOT mode-overridden: standalone
	// remaps only http/https/db, so +6 stays uniform (offset 1 → 3016) across
	// modes — the property the design relies on for "free in every mode".
	if d.RestAdminPort != 3016 {
		t.Errorf("RestAdminPort = %d, want 3016 (offset+6, uniform across modes)", d.RestAdminPort)
	}
	if d.RestAdminBindAddress != "127.0.0.1:3016" {
		t.Errorf("RestAdminBindAddress = %q, want 127.0.0.1:3016", d.RestAdminBindAddress)
	}
	if d.CaddyHttpBindAddress != "0.0.0.0:80" {
		t.Errorf("CaddyHttpBindAddress = %q, want 0.0.0.0:80", d.CaddyHttpBindAddress)
	}
	if d.CaddyDbBindAddress != "127.0.0.1" {
		t.Errorf("CaddyDbBindAddress = %q, want 127.0.0.1", d.CaddyDbBindAddress)
	}
	if d.CaddyDbTlsBindAddress != "0.0.0.0" {
		t.Errorf("CaddyDbTlsBindAddress = %q, want 0.0.0.0", d.CaddyDbTlsBindAddress)
	}
}

func TestProjectDir(t *testing.T) {
	// Just verify it doesn't panic
	dir := ProjectDir()
	if dir == "" {
		t.Error("ProjectDir returned empty string")
	}
}

// TestGenerateEnvContent_RestAdminBindAddress verifies the generated .env
// carries REST_ADMIN_BIND_ADDRESS with the offset+6 loopback value. This
// guards the fragile positional-index wiring in the head template (%[26]s):
// an off-by-one there would either omit the line or leave a Go fmt error
// marker (%!), both caught here.
func TestGenerateEnvContent_RestAdminBindAddress(t *testing.T) {
	projDir := t.TempDir()
	// generateEnvContent requires a readable .env.example; .env.config is
	// optional. A minimal example suffices — the keys it lacks are added via
	// example.Set() during generation.
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}
	derived := computeDerived(cfg)

	out, _, err := generateEnvContent(&Credentials{}, cfg, derived, &DbMemory{}, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent: %v", err)
	}

	if !strings.Contains(out, "REST_ADMIN_BIND_ADDRESS=127.0.0.1:3016") {
		t.Errorf("generated .env missing REST_ADMIN_BIND_ADDRESS=127.0.0.1:3016; got:\n%s", out)
	}
	// No Go fmt error markers — proves every positional index (incl. %[26]s)
	// resolved to a real argument.
	if strings.Contains(out, "%!") {
		t.Errorf("generated .env contains a Go fmt error marker (positional-index wiring bug):\n%s", out)
	}
}

// TestGenerateEnvContent_OwnsPGRSTSchemas_STATBUS054 proves config.go OWNS
// PGRST_DB_SCHEMAS and overrides the Supabase-legacy value from .env.example.
// PostgREST v14 HARD-FAILS the whole schema-cache load when any listed schema is
// absent (v12 tolerated it); dev's .env carried the template's
// public,storage,graphql_public where only `public` exists, parking the v14 upgrade.
// A regen must emit ONLY public so `sb config generate` heals every box.
func TestGenerateEnvContent_OwnsPGRSTSchemas_STATBUS054(t *testing.T) {
	projDir := t.TempDir()
	// Seed the .env.example with the EXACT legacy value a real deployed box carries,
	// so this proves the override wins over the template — not merely that a minimal
	// example lacks the key.
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"),
		[]byte("PGRST_DB_SCHEMAS=public,storage,graphql_public\n"), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}
	derived := computeDerived(cfg)

	out, _, err := generateEnvContent(&Credentials{}, cfg, derived, &DbMemory{}, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent: %v", err)
	}

	var line string
	for _, l := range strings.Split(out, "\n") {
		if strings.HasPrefix(l, "PGRST_DB_SCHEMAS=") {
			line = l
			break
		}
	}
	if line != "PGRST_DB_SCHEMAS=public" {
		t.Errorf("PGRST_DB_SCHEMAS must be owned as =public (v14 hard-fails on absent schemas; STATBUS-054); the legacy public,storage,graphql_public must be overridden. got %q", line)
	}
}

// TestGenerateEnvContent_UpgradeCallbackSurvives guards STATBUS-131: UPGRADE_CALLBACK
// set in .env.config must carry through into the generated .env. Before this fix,
// sb config generate rebuilt .env from .env.example plus an enumerated Set list that
// omitted UPGRADE_CALLBACK entirely, silently wiping the operator's callback (and with
// it the STATBUS-046 park siren) on every install and at upgrade step 3.1.
func TestGenerateEnvContent_UpgradeCallbackSurvives(t *testing.T) {
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".env.config"), []byte("UPGRADE_CALLBACK=./ops/notify-slack.sh\n"), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}
	derived := computeDerived(cfg)

	out, _, err := generateEnvContent(&Credentials{}, cfg, derived, &DbMemory{}, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent: %v", err)
	}

	if !strings.Contains(out, "UPGRADE_CALLBACK=./ops/notify-slack.sh") {
		t.Errorf("generated .env dropped UPGRADE_CALLBACK from .env.config; got:\n%s", out)
	}
}

// TestGenerateEnvContent_UpgradeCallbackDefaultsEmpty verifies that when .env.config
// has no UPGRADE_CALLBACK, the generated .env still declares the key (empty) rather
// than omitting it — matching the ADMINISTRATOR_CONTACT precedent, so the key is
// discoverable and never silently absent.
func TestGenerateEnvContent_UpgradeCallbackDefaultsEmpty(t *testing.T) {
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0644); err != nil {
		t.Fatal(err)
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}
	derived := computeDerived(cfg)

	out, _, err := generateEnvContent(&Credentials{}, cfg, derived, &DbMemory{}, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent: %v", err)
	}

	if !strings.Contains(out, "UPGRADE_CALLBACK=\n") {
		t.Errorf("generated .env missing default-empty UPGRADE_CALLBACK= line; got:\n%s", out)
	}
}

func assertStr(t *testing.T, name, got, want string) {
	t.Helper()
	if got != want {
		t.Errorf("%s = %q, want %q", name, got, want)
	}
}

// STATBUS-150 — a POSTGRES_NOTIFY_USER == POSTGRES_APP_USER collision makes
// init-db.sh's own later CREATE USER fail on every fresh cluster. This is a
// WARN, never a refuse (config generate is the daemon's own boot pre-flight —
// a hard refuse would brick a currently-functional misconfigured box), so the
// exact trigger condition and wording are pinned here directly.
func TestNotifyUserCollisionWarning(t *testing.T) {
	if w := notifyUserCollisionWarning("statbus_local", "statbus_notify_local"); w != "" {
		t.Errorf("distinct users must not warn; got %q", w)
	}
	if w := notifyUserCollisionWarning("statbus_local", ""); w != "" {
		t.Errorf("empty notifyUser must not warn (never equal, never collide); got %q", w)
	}
	w := notifyUserCollisionWarning("statbus_test", "statbus_test")
	for _, want := range []string{"WARN", "POSTGRES_NOTIFY_USER", "POSTGRES_APP_USER", "statbus_test", "fresh database cluster will fail to initialize"} {
		if !strings.Contains(w, want) {
			t.Errorf("collision warning missing %q; got %q", want, w)
		}
	}
}

// TestCaddyTemplates_UnmatchedHostCatchAll_STATBUS189 pins the explicit :80
// catch-all in every deployment-mode Caddy template. Without it, Caddy answers a
// request that matches no site key with HTTP 200 and an EMPTY body — so an
// external monitor pointed at a bare IP:port reads GREEN regardless of the box's
// health (the STATBUS-071 c-rollback arc read two such 200s as an "unexplained
// heal"). The block is static (no template variables), so a source-level pin is
// exactly as strong as a render-level one. If a template legitimately drops the
// block, this test is the reviewed place to say why.
func TestCaddyTemplates_UnmatchedHostCatchAll_STATBUS189(t *testing.T) {
	templates := []string{
		"development.caddyfile.tmpl",
		"standalone.caddyfile.tmpl",
		"private.caddyfile.tmpl",
	}
	for _, name := range templates {
		path := filepath.Join("..", "..", "..", "caddy", "templates", name)
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		src := string(data)
		if !strings.Contains(src, "STATBUS-189") || !strings.Contains(src, `respond "no matching site for this host" 404`) {
			t.Errorf("%s: missing the STATBUS-189 unmatched-host catch-all (:80 respond 404) — unmatched hosts would read Caddy's implicit 200-empty and false-green external monitors", name)
		}
	}
}
