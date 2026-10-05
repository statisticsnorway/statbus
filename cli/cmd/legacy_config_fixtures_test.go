package cmd

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

func TestLegacyReleaseConfigGenerationEntryPoints_STATBUS445(t *testing.T) {
	fixtures, err := filepath.Glob(filepath.Join("..", "internal", "config", "testdata", "legacy-config", "v*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 4 {
		t.Fatalf("expected four release fixtures, got %d: %v", len(fixtures), fixtures)
	}

	entryPoints := []struct {
		name string
		run  func(*testing.T, string, bool)
	}{
		{
			name: "settings-step",
			run: func(t *testing.T, dir string, _ bool) {
				t.Helper()
				if err := config.GenerateForInstallInDir(dir, false); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "service-command",
			run: func(t *testing.T, dir string, _ bool) {
				t.Helper()
				withWorkingDir(t, dir, func() {
					previous := migrateLegacySecrets
					migrateLegacySecrets = true
					t.Cleanup(func() { migrateLegacySecrets = previous })
					if err := configGenerateCmd.RunE(configGenerateCmd, nil); err != nil {
						t.Fatal(err)
					}
				})
			},
		},
		{
			name: "install-crash-recovery",
			run: func(t *testing.T, dir string, _ bool) {
				t.Helper()
				if err := regenerateCrashRecoveryConfig(dir, func(gotDir, executable string, args ...string) error {
					if gotDir != dir || executable != filepath.Join(dir, "sb") || !slices.Equal(args, []string{"config", "generate", "--migrate-legacy-secrets"}) {
						t.Fatalf("unexpected crash-recovery command: dir=%q executable=%q args=%q", gotDir, executable, args)
					}
					return config.GenerateForInstallInDir(dir, false)
				}); err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "plain-strict",
			run: func(t *testing.T, dir string, hasLegacySecrets bool) {
				t.Helper()
				err := config.GenerateInDir(dir, false)
				if hasLegacySecrets {
					if err == nil || !strings.Contains(err.Error(), "in .env.config is a secret") {
						t.Fatalf("strict generation must refuse legacy secrets, got %v", err)
					}
					if err := config.GenerateForInstallInDir(dir, false); err != nil {
						t.Fatalf("migrate before strict generation: %v", err)
					}
					err = config.GenerateInDir(dir, false)
				}
				if err != nil {
					t.Fatal(err)
				}
			},
		},
	}

	for _, fixture := range fixtures {
		fixture := fixture
		t.Run(filepath.Base(fixture), func(t *testing.T) {
			expectedSecrets, hasLegacySecrets := fixtureSecrets(t, fixture)
			for _, entryPoint := range entryPoints {
				entryPoint := entryPoint
				t.Run(entryPoint.name, func(t *testing.T) {
					dir := prepareLegacyConfigCheckout(t, fixture)
					entryPoint.run(t, dir, hasLegacySecrets)
					assertLegacyConfigGenerated(t, dir, expectedSecrets)
				})
			}
		})
	}
}

func prepareLegacyConfigCheckout(t *testing.T, fixture string) string {
	t.Helper()
	dir := t.TempDir()
	repoRoot := filepath.Join("..", "..")
	for _, name := range []string{".env.config", ".env.credentials"} {
		source := filepath.Join(fixture, name)
		data, err := os.ReadFile(source)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, name), data, 0600); err != nil {
			t.Fatal(err)
		}
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
	if err := os.MkdirAll(filepath.Join(dir, "ops", "maintenance"), 0755); err != nil {
		t.Fatal(err)
	}
	return dir
}

func fixtureSecrets(t *testing.T, fixture string) (map[string]string, bool) {
	t.Helper()
	values := make(map[string]string)
	hasLegacySecrets := false
	for _, name := range []string{".env.credentials", ".env.config"} {
		file, err := dotenv.Load(filepath.Join(fixture, name))
		if err != nil {
			t.Fatal(err)
		}
		for _, key := range []string{"GITHUB_TOKEN", "SLACK_TOKEN", "SEQ_API_KEY"} {
			if value, ok := file.Get(key); ok && strings.TrimSpace(value) != "" {
				values[key] = value
				if name == ".env.config" {
					hasLegacySecrets = true
				}
			}
		}
	}
	return values, hasLegacySecrets
}

func assertLegacyConfigGenerated(t *testing.T, dir string, expectedSecrets map[string]string) {
	t.Helper()
	configData, err := os.ReadFile(filepath.Join(dir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	credentials, err := dotenv.Load(filepath.Join(dir, ".env.credentials"))
	if err != nil {
		t.Fatal(err)
	}
	for key, want := range expectedSecrets {
		if strings.Contains(string(configData), key+"=") {
			t.Errorf("%s remains in .env.config", key)
		}
		if got, ok := credentials.Get(key); !ok || got != want {
			t.Errorf("%s credential = %q, present=%v, want %q", key, got, ok, want)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, ".env")); err != nil {
		t.Fatalf("generated .env: %v", err)
	}
}

func withWorkingDir(t *testing.T, dir string, fn func()) {
	t.Helper()
	previous, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := os.Chdir(previous); err != nil {
			t.Fatalf("restore working directory: %v", err)
		}
	}()
	fn()
}
