package config

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

const gib = int64(1) << 30

// stubDockerMemTotal replaces the injected Docker memory measurement for one
// test and restores the real one afterwards.
func stubDockerMemTotal(t *testing.T, total int64, err error) {
	t.Helper()
	previous := dockerMemTotalBytes
	dockerMemTotalBytes = func() (int64, error) { return total, err }
	t.Cleanup(func() { dockerMemTotalBytes = previous })
}

// minimalCheckout is the smallest checkout generateInDir needs: .env.example,
// the Caddy templates, and the maintenance output directory.
func minimalCheckout(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	repoRoot := filepath.Join(filepath.Dir(thisFile), "..", "..", "..")
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "ops", "maintenance"), 0755); err != nil {
		t.Fatal(err)
	}
	example, err := os.ReadFile(filepath.Join(repoRoot, ".env.example"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.example"), example, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(dir, "caddy", "templates"), os.DirFS(filepath.Join(repoRoot, "caddy", "templates"))); err != nil {
		t.Fatal(err)
	}
	return dir
}

func writeEnvConfig(t *testing.T, dir, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

func readFileString(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestDeriveDbMemLimitPerMode(t *testing.T) {
	tests := []struct {
		mode  string
		total int64
		want  string
	}{
		// standalone: total - max(2 GiB, 25%).
		{"standalone", 4 * gib, "2G"},
		{"standalone", 8 * gib, "6G"},
		{"standalone", 16 * gib, "12G"},
		{"standalone", 64 * gib, "48G"},
		// private (cloud): min(8 GiB, 50%).
		{"private", 4 * gib, "2G"},
		{"private", 8 * gib, "4G"},
		{"private", 16 * gib, "8G"},
		{"private", 64 * gib, "8G"},
		// development: min(4 GiB, 25%).
		{"development", 4 * gib, "1G"},
		{"development", 8 * gib, "2G"},
		{"development", 16 * gib, "4G"},
		{"development", 64 * gib, "4G"},
	}
	for _, tt := range tests {
		t.Run(tt.mode+"-"+tt.want, func(t *testing.T) {
			if got := deriveDbMemLimit(tt.mode, tt.total); got != tt.want {
				t.Errorf("deriveDbMemLimit(%q, %d bytes) = %q, want %q", tt.mode, tt.total, got, tt.want)
			}
		})
	}
}

func TestDeriveDbMemLimitRoundsDownAndFloorsAtOneGiB(t *testing.T) {
	tests := []struct {
		mode  string
		total int64
		want  string
	}{
		// 13 GiB standalone: 13 - max(2, 3.25) = 9.75 -> 9G.
		{"standalone", 13 * gib, "9G"},
		// Floor: a host too small for the headroom still gets 1G.
		{"standalone", 1 * gib, "1G"},
		{"private", 1 * gib, "1G"},
		{"development", 1 * gib, "1G"},
		{"development", 512 << 20, "1G"},
		{"standalone", 0, "1G"},
	}
	for _, tt := range tests {
		t.Run(tt.mode+"-"+tt.want, func(t *testing.T) {
			if got := deriveDbMemLimit(tt.mode, tt.total); got != tt.want {
				t.Errorf("deriveDbMemLimit(%q, %d bytes) = %q, want %q", tt.mode, tt.total, got, tt.want)
			}
		})
	}
}

// TestDbMemLimitOperatorOverrideIsKept: a DB_MEM_LIMIT the operator wrote is
// not derived over, and remains in .env.config.
func TestDbMemLimitOperatorOverrideIsKept(t *testing.T) {
	tests := []struct {
		override string
		want     string
	}{
		// A value other than the legacy 4G is unambiguously the operator's.
		{"8G", "8G"},
		// Pinning 4G on purpose: the inline comment marks it as a statement
		// rather than the exact line gen() used to write.
		{"4G # pinned on purpose", "4G"},
	}
	for _, tt := range tests {
		t.Run(strings.ReplaceAll(tt.override, " ", "_"), func(t *testing.T) {
			stubDockerMemTotal(t, 64*gib, nil)
			dir := minimalCheckout(t)
			writeEnvConfig(t, dir, "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example\nDB_MEM_LIMIT="+tt.override+"\n")

			if err := GenerateInDir(dir, false); err != nil {
				t.Fatalf("GenerateInDir: %v", err)
			}

			env := readFileString(t, filepath.Join(dir, ".env"))
			if !strings.Contains(env, "\nDB_MEM_LIMIT="+tt.want+"\n") {
				t.Errorf("generated .env did not keep the operator override %q:\n%s", tt.want, env)
			}
			config := readFileString(t, filepath.Join(dir, ".env.config"))
			if !strings.Contains(config, "DB_MEM_LIMIT="+tt.override) {
				t.Errorf(".env.config lost the operator override %q:\n%s", tt.override, config)
			}
		})
	}
}

// TestLegacyAutoWrittenDbMemLimitIsReDerived: installations created before
// STATBUS-557 carry the exact line gen("DB_MEM_LIMIT", "4G") wrote. That line
// is derived, not an operator statement, so it is removed and re-derived.
func TestLegacyAutoWrittenDbMemLimitIsReDerived(t *testing.T) {
	stubDockerMemTotal(t, 16*gib, nil)
	dir := minimalCheckout(t)
	// Verbatim shape written by gen(): no spaces, quotes, or inline comment.
	writeEnvConfig(t, dir, "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example\nDB_MEM_LIMIT=4G\n")

	if err := GenerateInDir(dir, false); err != nil {
		t.Fatalf("GenerateInDir: %v", err)
	}

	env := readFileString(t, filepath.Join(dir, ".env"))
	if !strings.Contains(env, "\nDB_MEM_LIMIT=12G\n") {
		t.Errorf("generated .env did not re-derive the legacy 4G value to 12G:\n%s", env)
	}
	config := readFileString(t, filepath.Join(dir, ".env.config"))
	if strings.Contains(config, "DB_MEM_LIMIT") {
		t.Errorf(".env.config still carries the legacy derived line:\n%s", config)
	}
}

// TestDbMemLimitReDerivesAfterResize: re-running config generate against a
// resized host moves the limit, because nothing is remembered between runs.
func TestDbMemLimitReDerivesAfterResize(t *testing.T) {
	dir := minimalCheckout(t)
	writeEnvConfig(t, dir, "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example\n")

	stubDockerMemTotal(t, 8*gib, nil)
	if err := GenerateInDir(dir, false); err != nil {
		t.Fatalf("GenerateInDir at 8 GiB: %v", err)
	}
	env := readFileString(t, filepath.Join(dir, ".env"))
	if !strings.Contains(env, "\nDB_MEM_LIMIT=6G\n") {
		t.Errorf("at 8 GiB, .env should allocate 6G:\n%s", env)
	}

	stubDockerMemTotal(t, 32*gib, nil)
	if err := GenerateInDir(dir, false); err != nil {
		t.Fatalf("GenerateInDir at 32 GiB: %v", err)
	}
	env = readFileString(t, filepath.Join(dir, ".env"))
	if !strings.Contains(env, "\nDB_MEM_LIMIT=24G\n") {
		t.Errorf("at 32 GiB, .env should allocate 24G after the resize:\n%s", env)
	}
}

// TestDbMemLimitDetectionFailureFallsBack: when Docker's memory cannot be
// read, the installer uses 4G and the report says the measurement failed.
func TestDbMemLimitDetectionFailureFallsBack(t *testing.T) {
	stubDockerMemTotal(t, 0, errors.New("docker daemon not running"))
	dir := minimalCheckout(t)
	writeEnvConfig(t, dir, "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.example\n")

	if err := GenerateInDir(dir, false); err != nil {
		t.Fatalf("GenerateInDir: %v", err)
	}

	env := readFileString(t, filepath.Join(dir, ".env"))
	if !strings.Contains(env, "\nDB_MEM_LIMIT=4G\n") {
		t.Errorf("failed measurement should fall back to 4G:\n%s", env)
	}

	cfg, err := loadOrGenerateConfig(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	report := dbMemLimitReport(cfg)
	if !strings.Contains(report, "could not measure") || !strings.Contains(report, "4G") {
		t.Errorf("report should say the measurement failed and 4G was used, got %q", report)
	}
}

func TestDbMemLimitReport(t *testing.T) {
	tests := []struct {
		name string
		cfg  *ConfigEnv
		want string
	}{
		{
			name: "derived",
			cfg: &ConfigEnv{
				CaddyDeploymentMode: "standalone",
				DbMemLimit:          "12G",
				DbMemLimitSource:    dbMemSourceDerived,
				DbMemDetectedBytes:  16 * gib,
			},
			want: "DB memory: detected 16 GiB, mode standalone, allocated 12G",
		},
		{
			name: "operator",
			cfg: &ConfigEnv{
				CaddyDeploymentMode: "private",
				DbMemLimit:          "6G",
				DbMemLimitSource:    dbMemSourceOperator,
			},
			want: "DB memory: mode private, operator override 6G",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := dbMemLimitReport(tt.cfg); got != tt.want {
				t.Errorf("dbMemLimitReport() = %q, want %q", got, tt.want)
			}
		})
	}
}
