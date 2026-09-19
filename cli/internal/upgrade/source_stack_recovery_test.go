package upgrade

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func sourceStackHealthServer(t *testing.T) (*httptest.Server, *int) {
	t.Helper()
	var rpcHits int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ready" {
			w.WriteHeader(http.StatusOK)
			return
		}
		rpcHits++
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	return srv, &rpcHits
}

func setSourceStackImageIdentityEnv(t *testing.T) {
	t.Helper()
	t.Setenv("STATBUS_TEST_APP_SOURCE_ID", servingEraTestImageID('1'))
	t.Setenv("STATBUS_TEST_WORKER_SOURCE_ID", servingEraTestImageID('2'))
	t.Setenv("STATBUS_TEST_REST_SOURCE_ID", servingEraTestImageID('3'))
	t.Setenv("STATBUS_TEST_PROXY_SOURCE_ID", servingEraTestImageID('4'))
	t.Setenv("STATBUS_TEST_APP_TARGET_ID", servingEraTestImageID('a'))
	t.Setenv("STATBUS_TEST_WORKER_TARGET_ID", servingEraTestImageID('b'))
	t.Setenv("STATBUS_TEST_REST_TARGET_ID", servingEraTestImageID('c'))
	t.Setenv("STATBUS_TEST_PROXY_TARGET_ID", servingEraTestImageID('d'))
}

func writeSourceStackRecoveryFlag(t *testing.T, projDir, sourceTag string, identities map[string]sourceImageIdentity) {
	t.Helper()
	if identities == nil {
		identities = servingEraExpected(sourceTag)
	}
	flag := UpgradeFlag{ID: 1, Holder: HolderService, Phase: PhaseOldSbUpgrading, SourceServingImages: identities}
	data, err := json.Marshal(flag)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(projDir, "tmp", "upgrade-in-progress.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

const sourceStackImageInspectCases = `
	"image inspect --format {{.Id}} "*statbus-app*) printf '%s\n' "$STATBUS_TEST_APP_SOURCE_ID" ;;
	"image inspect --format {{.Id}} "*statbus-worker*) printf '%s\n' "$STATBUS_TEST_WORKER_SOURCE_ID" ;;
	"image inspect --format {{.Id}} "*postgrest*) printf '%s\n' "$STATBUS_TEST_REST_SOURCE_ID" ;;
	"image inspect --format {{.Id}} "*statbus-proxy*) printf '%s\n' "$STATBUS_TEST_PROXY_SOURCE_ID" ;;
	"inspect --format {{.Image}} "*) printf '%s\n' "$4" ;;
	`

func installSourceCaptureDockerShim(t *testing.T, treeTag, appTag, workerTag, proxyTag string, states map[string]string) {
	t.Helper()
	serviceStates := map[string]string{"app": "running", "worker": "running", "rest": "running", "proxy": "running"}
	for service, state := range states {
		serviceStates[service] = state
	}
	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_TREE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_TREE_TAG"'"},"rest":{"image":"postgrest/postgrest:v13"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_TREE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		printf '%s\n' '{"ID":"app-container","Service":"app","State":"'"$STATBUS_TEST_APP_STATE"'","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_APP_TAG"'"}'
		printf '%s\n' '{"ID":"worker-container","Service":"worker","State":"'"$STATBUS_TEST_WORKER_STATE"'","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_WORKER_TAG"'"}'
		printf '%s\n' '{"ID":"rest-container","Service":"rest","State":"'"$STATBUS_TEST_REST_STATE"'","Image":"postgrest/postgrest:v12.2.8"}'
		printf '%s\n' '{"ID":"proxy-container","Service":"proxy","State":"'"$STATBUS_TEST_PROXY_STATE"'","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_PROXY_TAG"'"}'
		;;
	"inspect --format {{.Image}} app-container") printf '%s\n' "$STATBUS_TEST_APP_SOURCE_ID" ;;
	"inspect --format {{.Image}} worker-container") printf '%s\n' "$STATBUS_TEST_WORKER_SOURCE_ID" ;;
	"inspect --format {{.Image}} rest-container") printf '%s\n' "$STATBUS_TEST_REST_SOURCE_ID" ;;
	"inspect --format {{.Image}} proxy-container") printf '%s\n' "$STATBUS_TEST_PROXY_SOURCE_ID" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_TREE_TAG", treeTag)
	t.Setenv("STATBUS_TEST_APP_TAG", appTag)
	t.Setenv("STATBUS_TEST_WORKER_TAG", workerTag)
	t.Setenv("STATBUS_TEST_PROXY_TAG", proxyTag)
	t.Setenv("STATBUS_TEST_APP_STATE", serviceStates["app"])
	t.Setenv("STATBUS_TEST_WORKER_STATE", serviceStates["worker"])
	t.Setenv("STATBUS_TEST_REST_STATE", serviceStates["rest"])
	t.Setenv("STATBUS_TEST_PROXY_STATE", serviceStates["proxy"])
}

func TestStartSourceApplicationStackStartsOnlyVerifiedSourceEraContainers(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	srv, rpcHits := sourceStackHealthServer(t)

	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	  "compose ps -a --format json")
		    printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_SOURCE_ID"'","Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_APP_SOURCE_ID"'"}'
		    printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'","Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'"}'
		    printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_SOURCE_ID"'","Service":"rest","State":"exited","Image":"postgrest/postgrest:v12.2.8","ImageID":"'"$STATBUS_TEST_REST_SOURCE_ID"'"}'
		    printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'","Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'"}'
	    ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)

	d := &Service{projDir: git.dir, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	if err := d.startSourceApplicationStack(context.Background(), nil); err != nil {
		t.Fatalf("startSourceApplicationStack: %v", err)
	}
	if *rpcHits != 1 {
		t.Fatalf("health gate hits = %d, want 1", *rpcHits)
	}
	logBytes, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	log := string(logBytes)
	if !strings.Contains(log, "compose start app worker rest proxy\n") {
		t.Fatalf("verified source-era serving containers were not started in place:\n%s", logBytes)
	}
	if strings.Contains(log, "compose up") {
		t.Fatalf("already-source-era containers must not be recreated:\n%s", logBytes)
	}
}

func TestSourceServingContainerEntriesRejectsComposeImageIDDisagreement(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	projDir := t.TempDir()
	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	"compose ps -a --format json")
		printf '%s\n' '{"ID":"app-container","Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:source","ImageID":"'"$STATBUS_TEST_APP_TARGET_ID"'"}'
		;;
	"inspect --format {{.Image}} app-container") printf '%s\n' "$STATBUS_TEST_APP_SOURCE_ID" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	d := &Service{projDir: projDir}
	_, err := d.sourceServingContainerEntries(context.Background())
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) {
		t.Fatalf("error = %v, want sourceServingEraUnknownError", err)
	}
	if !strings.Contains(err.Error(), "Docker Compose reported "+servingEraTestImageID('a')) ||
		!strings.Contains(err.Error(), "Docker daemon reported "+servingEraTestImageID('1')) {
		t.Fatalf("disagreement error must name both immutable identities: %v", err)
	}
}

func TestCaptureSourceServingImageIdentitiesPersistsBeforeTargetPull(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	"image inspect "*) exit 88 ;;
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		printf '%s\n' '{"ID":"app-container","Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"worker-container","Service":"worker","State":"running","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"rest-container","Service":"rest","State":"running","Image":"postgrest/postgrest:v12.2.8"}'
		printf '%s\n' '{"ID":"proxy-container","Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		;;
	"inspect --format {{.Image}} app-container") printf '%s\n' "$STATBUS_TEST_APP_SOURCE_ID" ;;
	"inspect --format {{.Image}} worker-container") printf '%s\n' "$STATBUS_TEST_WORKER_SOURCE_ID" ;;
	"inspect --format {{.Image}} rest-container") printf '%s\n' "$STATBUS_TEST_REST_SOURCE_ID" ;;
	"inspect --format {{.Image}} proxy-container") printf '%s\n' "$STATBUS_TEST_PROXY_SOURCE_ID" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)

	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(17, strings.Repeat("f", 40), nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })
	if err := d.captureSourceServingImageIdentities(context.Background()); err != nil {
		t.Fatalf("captureSourceServingImageIdentities: %v", err)
	}
	flag, err := ReadFlagFile(git.dir)
	if err != nil {
		t.Fatal(err)
	}
	want := servingEraExpected(sourceTag)
	if flag == nil || !reflect.DeepEqual(flag.SourceServingImages, want) {
		t.Fatalf("recorded source identities = %#v, want %#v", flag, want)
	}

	execute := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) executeUpgrade(")
	writeIdx := strings.Index(execute, "d.writeUpgradeFlag(")
	captureIdx := strings.Index(execute, "d.captureSourceServingImageIdentities(ctx)")
	pullIdx := strings.Index(execute, "d.pullImagesForCommitShort(")
	if writeIdx < 0 || captureIdx < writeIdx || pullIdx < captureIdx {
		t.Fatalf("source identity order must be flag -> immutable capture -> target pull; write=%d capture=%d pull=%d", writeIdx, captureIdx, pullIdx)
	}
}

func TestCaptureSourceServingImageIdentitiesAcceptsInlineTargetTree(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	targetTag := git.newSHA[:8]
	installSourceCaptureDockerShim(t, targetTag, sourceTag, sourceTag, sourceTag, nil)

	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(18, git.newSHA, nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })
	if err := d.captureSourceServingImageIdentities(context.Background()); err != nil {
		t.Fatalf("captureSourceServingImageIdentities with target tree: %v", err)
	}
	flag, err := ReadFlagFile(git.dir)
	if err != nil {
		t.Fatal(err)
	}
	want := servingEraExpected(sourceTag)
	if flag == nil || !reflect.DeepEqual(flag.SourceServingImages, want) {
		t.Fatalf("recorded source identities = %#v, want container-derived %#v", flag, want)
	}
}

func TestCaptureSourceServingImageIdentitiesRejectsThirdTree(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	treeTag := git.newSHA[:8]
	installSourceCaptureDockerShim(t, treeTag, sourceTag, sourceTag, sourceTag, nil)

	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(19, strings.Repeat("f", 40), nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })
	err := d.captureSourceServingImageIdentities(context.Background())
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "neither the running source compose model nor pending target ffffffff") {
		t.Fatalf("capture error = %v, want named third-tree refusal", err)
	}
}

func TestCaptureSourceServingImageIdentitiesRejectsMixedContainerTags(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	targetTag := git.newSHA[:8]
	installSourceCaptureDockerShim(t, targetTag, sourceTag, "deadbeef", sourceTag, nil)

	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(20, git.newSHA, nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })
	err := d.captureSourceServingImageIdentities(context.Background())
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "pre-upgrade source containers have mixed tags") {
		t.Fatalf("capture error = %v, want named mixed-tag refusal", err)
	}
}

func TestCaptureSourceServingImageIdentitiesRequiresRunningServingStack(t *testing.T) {
	tests := []struct {
		name       string
		states     map[string]string
		wantErrSub string
	}{
		{name: "all running"},
		{
			name: "all exited",
			states: map[string]string{
				"app": "exited", "worker": "exited", "rest": "exited", "proxy": "exited",
			},
			wantErrSub: `pre-upgrade source container for app is not running (state "exited")`,
		},
		{
			name:       "mixed running and exited",
			states:     map[string]string{"worker": "exited"},
			wantErrSub: `pre-upgrade source container for worker is not running (state "exited")`,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			setSourceStackImageIdentityEnv(t)
			git := newGitRepoFixture(t)
			sourceTag := git.oldSHA[:8]
			targetTag := git.newSHA[:8]
			installSourceCaptureDockerShim(t, targetTag, sourceTag, sourceTag, sourceTag, tc.states)

			d := &Service{projDir: git.dir}
			if err := d.writeUpgradeFlag(21, git.newSHA, nil, "test", "test", false); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = d.removeUpgradeFlag() })
			err := d.captureSourceServingImageIdentities(context.Background())
			if tc.wantErrSub == "" {
				if err != nil {
					t.Fatalf("captureSourceServingImageIdentities with running serving stack: %v", err)
				}
			} else {
				var eraErr *sourceServingEraUnknownError
				if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), tc.wantErrSub) {
					t.Fatalf("capture error = %v, want named non-running refusal containing %q", err, tc.wantErrSub)
				}
			}

			flag, readErr := ReadFlagFile(git.dir)
			if readErr != nil {
				t.Fatal(readErr)
			}
			if tc.wantErrSub == "" {
				want := servingEraExpected(sourceTag)
				if flag == nil || !reflect.DeepEqual(flag.SourceServingImages, want) {
					t.Fatalf("running capture identities = %#v, want %#v", flag, want)
				}
			}
			if tc.wantErrSub != "" && flag != nil && len(flag.SourceServingImages) != 0 {
				t.Fatalf("non-running capture mutated SourceServingImages: %#v", flag.SourceServingImages)
			}
		})
	}
}

func TestStartSourceApplicationStackRecreatesDerivedTargetEraFromSourceTemplate(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	srv, rpcHits := sourceStackHealthServer(t)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	convergedPath := filepath.Join(shimDir, "converged")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
  "compose ps -a --format json")
		if [ -f "$STATBUS_TEST_CONVERGED" ]; then
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_SOURCE_ID"'","Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_APP_SOURCE_ID"'"}'
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'","Service":"worker","State":"running","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'"}'
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_SOURCE_ID"'","Service":"rest","State":"running","Image":"postgrest/postgrest:v12.2.8","ImageID":"'"$STATBUS_TEST_REST_SOURCE_ID"'"}'
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'","Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'"}'
				else
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_TARGET_ID"'","Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:target999","ImageID":"'"$STATBUS_TEST_APP_TARGET_ID"'"}'
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'","Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:target999","ImageID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'"}'
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_TARGET_ID"'","Service":"rest","State":"exited","Image":"postgrest/postgrest:v13","ImageID":"'"$STATBUS_TEST_REST_TARGET_ID"'"}'
					printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'","Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:target999","ImageID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'"}'
			fi
	    ;;
	"compose up -d --no-build --no-deps app worker rest proxy") touch "$STATBUS_TEST_CONVERGED" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_CONVERGED", convergedPath)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)

	d := &Service{projDir: git.dir, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	if err := d.startSourceApplicationStack(context.Background(), nil); err != nil {
		t.Fatalf("startSourceApplicationStack: %v", err)
	}
	if *rpcHits != 1 {
		t.Fatalf("health gate hits = %d, want 1", *rpcHits)
	}
	logBytes, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	log := string(logBytes)
	if !strings.Contains(log, "compose up -d --no-build --no-deps app worker rest proxy\n") {
		t.Fatalf("derived target-era containers were not authoritatively recreated from the restored source template:\n%s", logBytes)
	}
	if strings.Contains(log, "compose start app worker rest") {
		t.Fatalf("target-era containers must never be blindly resumed:\n%s", logBytes)
	}
}

func TestStartSourceApplicationStackRefusesMissingContainerAsUnknownEra(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_TARGET_ID"'","Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:target999","ImageID":"'"$STATBUS_TEST_APP_TARGET_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'","Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:target999","ImageID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'","Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:target999","ImageID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'"}'
		# rest deliberately missing: no caller may call this "target" by assertion.
		;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)

	d := &Service{projDir: git.dir}
	err := d.startSourceApplicationStack(context.Background(), nil)
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "rest container is missing") {
		t.Fatalf("missing-container refusal = %T %v, want named unknown-era refusal", err, err)
	}
	logBytes, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if strings.Contains(string(logBytes), "compose start") || strings.Contains(string(logBytes), "compose up") {
		t.Fatalf("unknown era must refuse before any serving action:\n%s", logBytes)
	}
}

func TestStartSourceApplicationStackRefusesWhenSourceEraCannotBeEstablished(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json") printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:wrong"}}}' ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)

	d := &Service{projDir: git.dir}
	err := d.startSourceApplicationStack(context.Background(), nil)
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "source serving era cannot be established") {
		t.Fatalf("era refusal = %T %v, want named sourceServingEraUnknownError", err, err)
	}
	logBytes, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	log := string(logBytes)
	if strings.Contains(log, "compose start") || strings.Contains(log, "compose up") {
		t.Fatalf("unknown source era must refuse before starting or recreating anything:\n%s", logBytes)
	}
}

func TestStartSourceApplicationStackRefusesWhenRecreateDoesNotConverge(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	srv, rpcHits := sourceStackHealthServer(t)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	stoppedPath := filepath.Join(shimDir, "stopped")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
		"compose ps -a --format json")
			state=running
			if [ -f "$STATBUS_TEST_STOPPED" ]; then state=exited; fi
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_TARGET_ID"'","Service":"app","State":"'"$state"'","Image":"ghcr.io/statisticsnorway/statbus-app:target999","ImageID":"'"$STATBUS_TEST_APP_TARGET_ID"'"}'
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'","Service":"worker","State":"'"$state"'","Image":"ghcr.io/statisticsnorway/statbus-worker:target999","ImageID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'"}'
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_TARGET_ID"'","Service":"rest","State":"'"$state"'","Image":"postgrest/postgrest:v13","ImageID":"'"$STATBUS_TEST_REST_TARGET_ID"'"}'
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'","Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:target999","ImageID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'"}'
			;;
		"compose stop app worker rest") touch "$STATBUS_TEST_STOPPED" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)
	t.Setenv("STATBUS_TEST_STOPPED", stoppedPath)

	d := &Service{projDir: git.dir, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	err := d.startSourceApplicationStack(context.Background(), nil)
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "remained target") {
		t.Fatalf("non-converged recreate = %T %v, want named fail-closed era refusal", err, err)
	}
	if *rpcHits != 0 {
		t.Fatalf("health gate hits = %d, want 0 before source era is proved", *rpcHits)
	}
	logBytes, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if !strings.Contains(string(logBytes), "compose up -d --no-build --no-deps app worker rest proxy\n") {
		t.Fatalf("source convergence was not attempted:\n%s", logBytes)
	}
	if !strings.Contains(string(logBytes), "compose stop app worker rest\n") {
		t.Fatalf("non-converged recreation was not actively contained:\n%s", logBytes)
	}
}

func TestStartSourceApplicationStackContainsPartialRecreateFailure(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	srv, rpcHits := sourceStackHealthServer(t)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	stoppedPath := filepath.Join(shimDir, "stopped")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		state=running
		if [ -f "$STATBUS_TEST_STOPPED" ]; then state=exited; fi
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_TARGET_ID"'","Service":"app","State":"'"$state"'","Image":"ghcr.io/statisticsnorway/statbus-app:target999","ImageID":"'"$STATBUS_TEST_APP_TARGET_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'","Service":"worker","State":"'"$state"'","Image":"ghcr.io/statisticsnorway/statbus-worker:target999","ImageID":"'"$STATBUS_TEST_WORKER_TARGET_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_TARGET_ID"'","Service":"rest","State":"'"$state"'","Image":"postgrest/postgrest:v13","ImageID":"'"$STATBUS_TEST_REST_TARGET_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'","Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:target999","ImageID":"'"$STATBUS_TEST_PROXY_TARGET_ID"'"}'
		;;
	"compose up -d --no-build --no-deps app worker rest proxy")
		# Model Compose starting part of the tier and then returning an error.
		exit 17
		;;
	"compose stop app worker rest") touch "$STATBUS_TEST_STOPPED" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)
	t.Setenv("STATBUS_TEST_STOPPED", stoppedPath)

	d := &Service{projDir: git.dir, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	err := d.startSourceApplicationStack(context.Background(), nil)
	if err == nil || !strings.Contains(err.Error(), "recreate source serving containers") || !strings.Contains(err.Error(), "stopped and positively verified") {
		t.Fatalf("partial recreate error = %v, want original failure plus verified containment", err)
	}
	if *rpcHits != 0 {
		t.Fatalf("health gate hits = %d, want 0 after compose-up failure", *rpcHits)
	}
	logBytes, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	log := string(logBytes)
	upIdx := strings.Index(log, "compose up -d --no-build --no-deps app worker rest proxy\n")
	stopIdx := strings.Index(log, "compose stop app worker rest\n")
	postVerifyIdx := strings.LastIndex(log, "compose ps -a --format json\n")
	if upIdx < 0 || stopIdx < upIdx || postVerifyIdx < stopIdx {
		t.Fatalf("partial recreate containment order must be failed up -> stop -> positive reinspection:\n%s", log)
	}
}

func TestSourceStackRecoveryPreconditionStopsWithoutRemovingContainers(t *testing.T) {
	source := readUpgradeServiceSource(t)
	body := extractFuncBody(t, source, "func (d *Service) executeUpgrade(")
	if !strings.Contains(body, `runCommand(projDir, "docker", "compose", "stop", "app", "worker", "rest")`) {
		t.Fatal("executeUpgrade must preserve app/worker/rest containers with compose stop so recovery can start them in place")
	}
}

func TestPreSwapPairTerminalConvergesBeforeReassuringWrite(t *testing.T) {
	source := readUpgradeServiceSource(t)
	body := extractFuncBody(t, source, "func (d *Service) recoveryRollback(")
	terminalIdx := strings.Index(body, "rollbackResumeIsTerminal(")
	convergeIdx := strings.Index(body, "d.convergeUnchangedSourceServices(ctx")
	reassureIdx := strings.Index(body, "preSwapStoppedMessage(attempts)")
	writeIdx := strings.Index(body, "d.writeRollbackTerminal(id")
	for name, idx := range map[string]int{
		"pair terminal":      terminalIdx,
		"source convergence": convergeIdx,
		"reassuring message": reassureIdx,
		"terminal write":     writeIdx,
	} {
		if idx < 0 {
			t.Fatalf("recoveryRollback missing %s", name)
		}
	}
	if terminalIdx >= convergeIdx || convergeIdx >= reassureIdx || reassureIdx >= writeIdx {
		t.Fatalf("PreSwap pair terminal must converge and health-prove source services before reassurance/write: terminal=%d converge=%d reassure=%d write=%d", terminalIdx, convergeIdx, reassureIdx, writeIdx)
	}
	if !strings.Contains(body, "ErrRollbackServicesUp") || !strings.Contains(body, "could not be restored to normal service") {
		t.Error("pair-terminal convergence failure must record a truthful degraded services-up terminal, not UPGRADE_STOPPED_NOTHING_CHANGED")
	}
}
