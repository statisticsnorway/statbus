package upgrade

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/testguard"
)

func servingEraTestImageID(hexDigit byte) string {
	return "sha256:" + strings.Repeat(string(hexDigit), 64)

}

func servingEraExpected(sourceTag string) map[string]sourceImageIdentity {
	return map[string]sourceImageIdentity{
		"app":    {Reference: "ghcr.io/statisticsnorway/statbus-app:" + sourceTag, ImageID: servingEraTestImageID('1')},
		"worker": {Reference: "ghcr.io/statisticsnorway/statbus-worker:" + sourceTag, ImageID: servingEraTestImageID('2')},
		"rest":   {Reference: "postgrest/postgrest:v12.2.8", ImageID: servingEraTestImageID('3')},
		"proxy":  {Reference: "ghcr.io/statisticsnorway/statbus-proxy:" + sourceTag, ImageID: servingEraTestImageID('4')},
	}
}

func servingEraEntries(images map[string]sourceImageIdentity) []compose.PsEntry {
	entries := make([]compose.PsEntry, 0, len(images))
	for _, service := range sourceServingServices {
		if image, ok := images[service]; ok {
			entries = append(entries, compose.PsEntry{Service: service, Image: image.Reference, ImageID: image.ImageID, State: "running"})
		}
	}
	return entries
}

func targetServingIdentities(tag string) map[string]sourceImageIdentity {
	return map[string]sourceImageIdentity{
		"app":    {Reference: "ghcr.io/statisticsnorway/statbus-app:" + tag, ImageID: servingEraTestImageID('a')},
		"worker": {Reference: "ghcr.io/statisticsnorway/statbus-worker:" + tag, ImageID: servingEraTestImageID('b')},
		"rest":   {Reference: "postgrest/postgrest:v13", ImageID: servingEraTestImageID('c')},
		"proxy":  {Reference: "ghcr.io/statisticsnorway/statbus-proxy:" + tag, ImageID: servingEraTestImageID('d')},
	}
}

func TestDeriveServingEraFromActualContainerImages(t *testing.T) {
	const sourceTag = "1234abcd"
	expected := servingEraExpected(sourceTag)

	tests := []struct {
		name       string
		images     map[string]sourceImageIdentity
		want       ServingEra
		wantErrSub string
	}{
		{
			name:   "all exact source images",
			images: expected,
			want:   ServingEraSource,
		},
		{
			name:   "coherent target images",
			images: targetServingIdentities("target99"),
			want:   ServingEraTarget,
		},
		{
			name: "target version with unchanged upstream rest",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				images["rest"] = expected["rest"]
				return images
			}(),
			want: ServingEraTarget,
		},
		{
			name: "mixed source and target",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				images["app"] = expected["app"]
				images["rest"] = expected["rest"]
				return images
			}(),
			wantErrSub: "mixed source/target",
		},
		{
			name: "incoherent target tags",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				images["worker"] = sourceImageIdentity{Reference: "ghcr.io/statisticsnorway/statbus-worker:other999", ImageID: servingEraTestImageID('e')}
				return images
			}(),
			wantErrSub: "mixed non-source serving tags",
		},
		{
			name: "missing container",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				delete(images, "rest")
				return images
			}(),
			wantErrSub: "rest container is missing",
		},
		{
			name: "source tag on wrong image repository",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: "evil.example/statbus-app:" + sourceTag, ImageID: servingEraTestImageID('e')}
				return images
			}(),
			wantErrSub: "source-like tag",
		},
		{
			name: "source tagged services with wrong rest",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["rest"] = sourceImageIdentity{Reference: "postgrest/postgrest:v13", ImageID: servingEraTestImageID('c')}
				return images
			}(),
			wantErrSub: "rest immutable image ID",
		},
		{
			name: "same-short rebuild fails closed",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: expected["app"].Reference, ImageID: servingEraTestImageID('e')}
				return images
			}(),
			wantErrSub: "moving tag or same-short rebuild",
		},
		{
			name: "moving source tag fails closed",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["proxy"] = sourceImageIdentity{Reference: expected["proxy"].Reference, ImageID: servingEraTestImageID('f')}
				return images
			}(),
			wantErrSub: "moving tag or same-short rebuild",
		},
		{
			name: "unresolvable immutable identity fails closed",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: expected["app"].Reference}
				return images
			}(),
			wantErrSub: "no resolvable immutable image identity",
		},
		{
			name: "digest aliases with exact image IDs are source",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: "mirror.example/statbus-app@" + servingEraTestImageID('9'), ImageID: expected["app"].ImageID}
				return images
			}(),
			want: ServingEraSource,
		},
		{
			name: "local references use immutable IDs",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				for _, service := range sourceVersionTaggedServingServices {
					identity := images[service]
					identity.Reference = "ghcr.io/statisticsnorway/statbus-" + service + ":local"
					images[service] = identity
				}
				return images
			}(),
			want: ServingEraSource,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			era, err := deriveServingEra(servingEraEntries(tc.images), expected, sourceTag)
			if tc.wantErrSub == "" {
				if err != nil || era != tc.want {
					t.Fatalf("deriveServingEra = (%q, %v), want (%q, nil)", era, err, tc.want)
				}
				return
			}
			var eraErr *sourceServingEraUnknownError
			if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), tc.wantErrSub) || era != "" {
				t.Fatalf("deriveServingEra = (%q, %T %v), want named refusal containing %q", era, err, err, tc.wantErrSub)
			}
		})
	}
}

func TestSourceServingExpectedImageReferencesHandlesDigestAndLocal(t *testing.T) {
	git := newGitRepoFixture(t)
	digest := servingEraTestImageID('9')
	tests := []struct {
		name       string
		appRef     string
		workerRef  string
		proxyRef   string
		wantErrSub string
	}{
		{
			name:      "explicit local references",
			appRef:    "ghcr.io/statisticsnorway/statbus-app:local",
			workerRef: "ghcr.io/statisticsnorway/statbus-worker:local",
			proxyRef:  "ghcr.io/statisticsnorway/statbus-proxy:local",
		},
		{
			name:      "immutable digest references",
			appRef:    "ghcr.io/statisticsnorway/statbus-app@" + digest,
			workerRef: "ghcr.io/statisticsnorway/statbus-worker@" + digest,
			proxyRef:  "ghcr.io/statisticsnorway/statbus-proxy@" + digest,
		},
		{
			name:       "malformed digest fails closed",
			appRef:     "ghcr.io/statisticsnorway/statbus-app@sha256:not-a-digest",
			workerRef:  "ghcr.io/statisticsnorway/statbus-worker@" + digest,
			proxyRef:   "ghcr.io/statisticsnorway/statbus-proxy@" + digest,
			wantErrSub: "malformed digest reference",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			shimDir := t.TempDir()
			config := fmt.Sprintf(`{"services":{"app":{"image":%q},"worker":{"image":%q},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":%q}}}`, tc.appRef, tc.workerRef, tc.proxyRef)
			shim := "#!/bin/sh\ncase \"$*\" in\n  \"compose --profile all config --format json\") printf '%s\\n' '" + config + "' ;;\nesac\n"
			if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
			d := &Service{projDir: git.dir}
			references, _, err := d.sourceServingExpectedImageReferences(context.Background())
			if tc.wantErrSub != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErrSub) {
					t.Fatalf("source references error = %v, want %q", err, tc.wantErrSub)
				}
				return
			}
			if err != nil {
				t.Fatalf("sourceServingExpectedImageReferences: %v", err)
			}
			if references["app"] != tc.appRef || references["worker"] != tc.workerRef || references["proxy"] != tc.proxyRef {
				t.Fatalf("references = %#v, want app=%q worker=%q proxy=%q", references, tc.appRef, tc.workerRef, tc.proxyRef)
			}
		})
	}
}

func TestSourceServingExpectedImageReferencesIgnoresStderrWarnings(t *testing.T) {
	git := newGitRepoFixture(t)
	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
  "compose --profile all config --format json")
    printf '%s\n' 'Compose warning: an unrelated variable is not set' >&2
    printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:local"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:local"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:local"}}}'
    ;;
esac
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	d := &Service{projDir: git.dir}
	references, _, err := d.sourceServingExpectedImageReferences(context.Background())
	if err != nil {
		t.Fatalf("sourceServingExpectedImageReferences with Compose stderr warning: %v", err)
	}
	if references["app"] != "ghcr.io/statisticsnorway/statbus-app:local" {
		t.Fatalf("app reference = %q, want local image after stderr warning", references["app"])
	}
}

func TestSourceServingExpectedImageReferencesRendersActualRepoComposeModel(t *testing.T) {
	if !testguard.IsolatedDockerInvocation() {
		t.Skip("actual-repository Compose render requires STATBUS_LIVE_DB_TEST=1")
	}
	if _, err := exec.LookPath("docker"); err != nil {
		t.Skip("docker CLI not available")
	}
	repoRoot := filepath.Dir(thisRepoFile(t, "docker-compose.yml"))
	noEnvFile := filepath.Join(t.TempDir(), "no-env")
	if err := os.WriteFile(noEnvFile, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for key, value := range map[string]string{
		"ACCESS_JWT_EXPIRY":               "3600",
		"APP_BIND_ADDRESS":                "127.0.0.1:3912",
		"CADDY_DB_BIND_ADDRESS":           "127.0.0.1",
		"CADDY_DB_PORT":                   "3914",
		"CADDY_DB_TLS_BIND_ADDRESS":       "127.0.0.1",
		"CADDY_DB_TLS_PORT":               "3915",
		"CADDY_DEPLOYMENT_MODE":           "development",
		"CADDY_HTTP_BIND_ADDRESS":         "127.0.0.1:3910",
		"CADDY_HTTPS_BIND_ADDRESS":        "127.0.0.1:3911",
		"CADDY_LOG_PATH":                  "/tmp/statbus-compose-profile-test.log",
		"COMMIT_SHORT":                    "local",
		"COMPOSE_ENV_FILES":               noEnvFile,
		"COMPOSE_FILE":                    "docker-compose.yml",
		"COMPOSE_INSTANCE_NAME":           "statbus-compose-profile-test",
		"COMPOSE_PROFILES":                "",
		"DEBUG":                           "0",
		"DEPLOYMENT_SLOT_CODE":            "test",
		"DEPLOYMENT_SLOT_NAME":            "Compose profile test",
		"HOME":                            t.TempDir(),
		"JWT_SECRET":                      "test-jwt-secret",
		"POSTGRES_ADMIN_PASSWORD":         "test-admin-password",
		"POSTGRES_ADMIN_USER":             "postgres",
		"POSTGRES_APP_DB":                 "statbus_test",
		"POSTGRES_APP_PASSWORD":           "test-app-password",
		"POSTGRES_AUTHENTICATOR_PASSWORD": "test-authenticator-password",
		"POSTGRES_NOTIFY_PASSWORD":        "test-notify-password",
		"POSTGRES_NOTIFY_USER":            "test-notify",
		"PGRST_DB_SCHEMAS":                "public,auth",
		"PUBLIC_BROWSER_REST_URL":         "http://test.invalid/rest",
		"PUBLIC_DEBUG":                    "0",
		"REFRESH_JWT_EXPIRY":              "2592000",
		"REST_ADMIN_BIND_ADDRESS":         "127.0.0.1:3916",
		"REST_BIND_ADDRESS":               "127.0.0.1:3913",
		"SEQ_API_KEY":                     "test-seq-key",
		"SEQ_SERVER_URL":                  "http://seq.test.invalid",
		"SITE_URL":                        "http://test.invalid",
		"VERBOSE":                         "0",
		"VERSION":                         "test",
	} {
		t.Setenv(key, value)
	}

	// The older source-era tests use synthetic fixtures whose services are not
	// profile-gated. That is why ten review rounds missed the production model:
	// this test deliberately renders the actual root Compose files through the
	// source-image derivation path used immediately before an upgrade pull.
	d := &Service{projDir: repoRoot}
	references, _, err := d.sourceServingExpectedImageReferences(context.Background())
	if err != nil {
		t.Fatalf("sourceServingExpectedImageReferences(actual repo): %v", err)
	}
	for _, service := range []string{"app", "worker", "rest", "proxy"} {
		if strings.TrimSpace(references[service]) == "" {
			t.Errorf("actual repo Compose render has no image for %s: %#v", service, references)
		}
	}

	cmd, err := commandContext(context.Background(), repoRoot, "docker", "compose", "--profile", fullServiceComposeProfile, "config", "--format", "json")
	if err != nil {
		t.Fatal(err)
	}
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("render actual repo Compose model: %v", err)
	}
	var rendered sourceComposeConfig
	if err := json.Unmarshal(out, &rendered); err != nil {
		t.Fatalf("parse actual repo Compose model: %v", err)
	}
	for _, service := range []string{"app", "worker", "rest", "proxy", "db"} {
		if _, ok := rendered.Services[service]; !ok {
			t.Errorf("actual repo full Compose model is missing %s", service)
		}
	}
}

func TestComposePsListsExistingProfiledContainersWithoutProfileSelection(t *testing.T) {
	if !testguard.IsolatedDockerInvocation() {
		t.Skip("live Docker integration probe requires STATBUS_LIVE_DB_TEST=1")
	}
	if _, err := exec.LookPath("docker"); err != nil || exec.Command("docker", "info").Run() != nil {
		t.Skip("docker daemon not available")
	}

	dir := t.TempDir()
	project := fmt.Sprintf("statbus-compose-ps-profile-%d", time.Now().UnixNano())
	// The livedb runner owns its own throwaway Compose project. This nested
	// profile probe must not inherit that project's name or enumerate its
	// fixture service alongside the profile-gated app.
	t.Setenv("COMPOSE_PROJECT_NAME", project)
	image := project + ":local"
	composePath := filepath.Join(dir, "compose.yaml")
	if err := os.WriteFile(filepath.Join(dir, "Dockerfile"), []byte("FROM scratch\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	composeYAML := fmt.Sprintf("name: %s\nservices:\n  app:\n    image: %s\n    command: [\"/not-present\"]\n    profiles: [all]\n", project, image)
	if err := os.WriteFile(composePath, []byte(composeYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = exec.Command("docker", "compose", "-f", composePath, "--profile", "all", "down", "--remove-orphans").Run()
		_ = exec.Command("docker", "image", "rm", image).Run()
	})
	if out, err := exec.Command("docker", "build", "-q", "-t", image, dir).CombinedOutput(); err != nil {
		t.Fatalf("build scratch image: %v\n%s", err, out)
	}
	if out, err := exec.Command("docker", "compose", "-f", composePath, "--profile", "all", "create", "app").CombinedOutput(); err != nil {
		t.Fatalf("create profile-gated app container: %v\n%s", err, out)
	}

	psEntries := func(args ...string) []compose.PsEntry {
		t.Helper()
		out, err := exec.Command("docker", append([]string{"compose", "-f", composePath}, args...)...).Output()
		if err != nil {
			t.Fatalf("docker compose %v: %v", args, err)
		}
		entries, err := compose.ParsePsJSON(out)
		if err != nil {
			t.Fatalf("parse docker compose %v output: %v", args, err)
		}
		return entries
	}
	// Unlike config/pull, ps enumerates existing project containers independently
	// of model profile selection. This executable check protects every audited bare
	// compose ps call used for recovery state and immutable-identity inspection.
	bare := psEntries("ps", "-a", "--format", "json")
	profiled := psEntries("--profile", "all", "ps", "-a", "--format", "json")
	if len(bare) != 1 || bare[0].Service != "app" {
		t.Fatalf("bare compose ps did not see the existing profile-gated app container: %#v", bare)
	}
	if !reflect.DeepEqual(bare, profiled) {
		t.Fatalf("compose ps visibility changed with profile selection:\nbare: %#v\nall:  %#v", bare, profiled)
	}
}

func TestStartSourceApplicationStackDerivesEraAtItsBoundary(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) startSourceApplicationStack(")
	deriveIdx := strings.Index(body, "deriveServingEra(entries, expected, sourceTag)")
	if deriveIdx < 0 {
		t.Fatal("source-stack boundary no longer derives ServingEra from actual container images")
	}
	for _, required := range []string{
		"deriveServingEra(entries, expected, sourceTag)",
		"case ServingEraSource:",
		"case ServingEraTarget:",
		"deriveServingEra(postEntries, expected, sourceTag)",
		"postEra != ServingEraSource",
	} {
		if !strings.Contains(body, required) {
			t.Errorf("source-stack boundary lost explicit derived-era precondition %q", required)
		}
	}
	if strings.Contains(body[:deriveIdx], `"compose", "start"`) ||
		strings.Contains(body[:deriveIdx], `"compose", "up"`) {
		t.Fatal("source-stack boundary must derive an observed ServingEra before any start or recreate command")
	}
}
