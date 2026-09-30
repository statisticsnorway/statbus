package upgrade

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
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
	"inspect --format {{.Config.Image}} "*) "$0" compose ps -a --format json | grep "\"ID\":\"$4\"" | sed 's/.*"Image":"\([^"]*\)".*/\1/' ;;
	`

func installSourceCaptureDockerShim(t *testing.T, treeTag, appTag, workerTag, proxyTag string, states map[string]string) {
	installSourceCaptureDockerShimWithMissing(t, treeTag, appTag, workerTag, proxyTag, states, nil)
}

func installSourceCaptureDockerShimWithMissing(t *testing.T, treeTag, appTag, workerTag, proxyTag string, states map[string]string, missing map[string]bool) {
	t.Helper()
	serviceStates := map[string]string{"app": "running", "worker": "running", "rest": "running", "proxy": "running"}
	for service, state := range states {
		serviceStates[service] = state
	}
	shimDir := t.TempDir()
	shim := `#!/bin/sh
[ -z "${STATBUS_TEST_DOCKER_LOG:-}" ] || printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_TREE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_TREE_TAG"'"},"rest":{"image":"'"$STATBUS_TEST_TREE_REST_IMAGE"'"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_TREE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		[ "$STATBUS_TEST_APP_PRESENT" = 0 ] || printf '%s\n' '{"ID":"app-container","Service":"app","State":"'"$STATBUS_TEST_APP_STATE"'","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_APP_TAG"'"}'
		[ "$STATBUS_TEST_WORKER_PRESENT" = 0 ] || printf '%s\n' '{"ID":"worker-container","Service":"worker","State":"'"$STATBUS_TEST_WORKER_STATE"'","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_WORKER_TAG"'"}'
		[ "$STATBUS_TEST_REST_PRESENT" = 0 ] || printf '%s\n' '{"ID":"rest-container","Service":"rest","State":"'"$STATBUS_TEST_REST_STATE"'","Image":"postgrest/postgrest:v12.2.8"}'
		[ "$STATBUS_TEST_PROXY_PRESENT" = 0 ] || printf '%s\n' '{"ID":"proxy-container","Service":"proxy","State":"'"$STATBUS_TEST_PROXY_STATE"'","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_PROXY_TAG"'"}'
		;;
	"inspect --format {{.Config.Image}} "*-container) "$0" compose ps -a --format json | grep "\"ID\":\"$4\"" | sed 's/.*"Image":"\([^"]*\)".*/\1/' ;;
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
	t.Setenv("STATBUS_TEST_TREE_REST_IMAGE", "postgrest/postgrest:v13")
	t.Setenv("STATBUS_TEST_APP_TAG", appTag)
	t.Setenv("STATBUS_TEST_WORKER_TAG", workerTag)
	t.Setenv("STATBUS_TEST_PROXY_TAG", proxyTag)
	t.Setenv("STATBUS_TEST_APP_STATE", serviceStates["app"])
	t.Setenv("STATBUS_TEST_WORKER_STATE", serviceStates["worker"])
	t.Setenv("STATBUS_TEST_REST_STATE", serviceStates["rest"])
	t.Setenv("STATBUS_TEST_PROXY_STATE", serviceStates["proxy"])
	for _, service := range sourceServingServices {
		present := "1"
		if missing[service] {
			present = "0"
		}
		t.Setenv("STATBUS_TEST_"+strings.ToUpper(service)+"_PRESENT", present)
	}
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
	// The only compose up allowed is the database convergence, which Compose
	// turns into a no-op when db already matches the restored source model.
	withoutDBConverge := strings.ReplaceAll(log, "compose up -d --no-build --no-deps db\n", "")
	if strings.Contains(withoutDBConverge, "compose up") {
		t.Fatalf("already-source-era serving containers must not be recreated:\n%s", logBytes)
	}
}

// TestSourceRecoveryConvergesDatabaseSoNextDaemonBootDoesNotRecreateIt is the
// regression for rc.16 arc run 36468921894 (c-rollback-resurrection). The
// forward step's db-up left the db container on the TARGET compose model; the
// rollback restored source git/.env and only resumed that container, then
// reported rolled_back. The daemon's next boot ran EnsureDBUp
// (`docker compose up -d db`), Compose saw the drift and recreated the
// database 30 s after success had been reported ("the database system is
// shutting down"). The shim models Compose's config-hash rule: `up` on db
// recreates only while the container's model differs from the on-disk model.
func TestSourceRecoveryConvergesDatabaseSoNextDaemonBootDoesNotRecreateIt(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	srv, _ := sourceStackHealthServer(t)

	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	eventsPath := filepath.Join(shimDir, "db-events.log")
	modelPath := filepath.Join(shimDir, "db-model")
	// The db container as the failed forward step left it: target model.
	if err := os.WriteFile(modelPath, []byte("target\n"), 0o644); err != nil {
		t.Fatal(err)
	}
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
	"compose up "*" db")
		if [ "$(cat "$STATBUS_TEST_DB_MODEL")" != source ]; then
			printf 'recreate db: %s\n' "$*" >> "$STATBUS_TEST_DB_EVENTS"
			printf 'source\n' > "$STATBUS_TEST_DB_MODEL"
		fi
		;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_DB_EVENTS", eventsPath)
	t.Setenv("STATBUS_TEST_DB_MODEL", modelPath)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)

	readEvents := func() string {
		t.Helper()
		data, err := os.ReadFile(eventsPath)
		if err != nil && !os.IsNotExist(err) {
			t.Fatal(err)
		}
		return string(data)
	}

	// Rollback / park recovery: the shared source-era serving gate.
	d := &Service{projDir: git.dir, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	if err := d.startSourceApplicationStack(context.Background(), nil); err != nil {
		t.Fatalf("startSourceApplicationStack: %v", err)
	}
	duringRecovery := readEvents()

	// The daemon's next boot (systemd restart after rolled_back, exit 75).
	if err := d.EnsureDBUp(context.Background()); err != nil {
		t.Fatalf("EnsureDBUp: %v", err)
	}
	afterBoot := strings.TrimPrefix(readEvents(), duringRecovery)

	dockerLog, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if afterBoot != "" {
		t.Fatalf("the daemon boot after a successful source recovery recreated the database (an outage after success was reported):\n%s\ndocker transcript:\n%s", afterBoot, dockerLog)
	}
	if strings.Count(duringRecovery, "recreate db:") != 1 || !strings.Contains(duringRecovery, "--no-deps db") {
		t.Fatalf("source recovery must converge the target-era db container exactly once, db only, inside the recovery window; got:\n%s\ndocker transcript:\n%s", duringRecovery, dockerLog)
	}
	log := string(dockerLog)
	convergeIdx := strings.Index(log, "compose up -d --no-build --no-deps db\n")
	startIdx := strings.Index(log, "compose start app worker rest proxy\n")
	if convergeIdx < 0 || startIdx < 0 || convergeIdx > startIdx {
		t.Fatalf("db must converge before the source serving tier starts: converge=%d start=%d\n%s", convergeIdx, startIdx, dockerLog)
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
	"inspect --format {{.Config.Image}} "*-container) "$0" compose ps -a --format json | grep "\"ID\":\"$4\"" | sed 's/.*"Image":"\([^"]*\)".*/\1/' ;;
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
	"inspect --format {{.Config.Image}} "*-container) "$0" compose ps -a --format json | grep "\"ID\":\"$4\"" | sed 's/.*"Image":"\([^"]*\)".*/\1/' ;;
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

func TestCaptureSourceServingImageIdentitiesWritesIndependentAtomicCarrier(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	installSourceCaptureDockerShim(t, git.newSHA[:8], sourceTag, sourceTag, sourceTag, nil)

	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(181, git.newSHA, nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })
	if err := d.captureSourceServingImageIdentities(context.Background()); err != nil {
		t.Fatalf("captureSourceServingImageIdentities: %v", err)
	}

	carrierPath := filepath.Join(git.dir, "tmp", "upgrade-source-images.json")
	data, err := os.ReadFile(carrierPath)
	if err != nil {
		t.Fatalf("read independent source-image carrier: %v", err)
	}
	var carrier struct {
		ID        int                            `json:"id"`
		CommitSHA string                         `json:"commit_sha"`
		Images    map[string]sourceImageIdentity `json:"source_serving_images"`
		States    map[string]string              `json:"source_serving_states"`
	}
	if err := json.Unmarshal(data, &carrier); err != nil {
		t.Fatalf("decode independent source-image carrier: %v", err)
	}
	wantStates := map[string]string{"app": "running", "worker": "running", "rest": "running", "proxy": "running"}
	if carrier.ID != 181 || carrier.CommitSHA != git.newSHA || !reflect.DeepEqual(carrier.Images, servingEraExpected(sourceTag)) || !reflect.DeepEqual(carrier.States, wantStates) {
		t.Fatalf("carrier = %#v, want id=181 commit=%s images=%#v states=%#v", carrier, git.newSHA, servingEraExpected(sourceTag), wantStates)
	}
	temps, err := filepath.Glob(filepath.Join(git.dir, "tmp", ".upgrade-source-images.json.tmp-*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(temps) != 0 {
		t.Fatalf("atomic source-image carrier temps remain: %v", temps)
	}
}

func TestCorruptMarkerRemovalRetainsSourceImageCarrierForFlaglessRecovery(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	installSourceCaptureDockerShim(t, git.newSHA[:8], sourceTag, sourceTag, sourceTag, nil)

	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(182, git.newSHA, nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	if err := d.captureSourceServingImageIdentities(context.Background()); err != nil {
		t.Fatalf("captureSourceServingImageIdentities: %v", err)
	}
	d.flagLock.Close()
	d.flagLock = nil
	if err := os.WriteFile(d.flagPath(), []byte("{truncated"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := d.recoverFromFlag(context.Background()); err != nil {
		t.Fatalf("recoverFromFlag(corrupt): %v", err)
	}
	if _, err := os.Stat(d.flagPath()); !os.IsNotExist(err) {
		t.Fatalf("corrupt marker still exists or stat failed: %v", err)
	}
	carrierPath := filepath.Join(git.dir, "tmp", "upgrade-source-images.json")
	if _, err := os.Stat(carrierPath); err != nil {
		t.Fatalf("corrupt-marker removal deleted the independent source-image carrier: %v", err)
	}

	// Model the restored source tree. Recovery must use the pre-pull carrier,
	// never derive identity from whatever containers happen to exist now.
	if out, err := runCommandOutput(git.dir, "git", "checkout", "--detach", git.oldSHA); err != nil {
		t.Fatalf("restore source checkout: %v\n%s", err, out)
	}
	t.Setenv("STATBUS_TEST_TREE_TAG", sourceTag)
	t.Setenv("STATBUS_TEST_TREE_REST_IMAGE", "postgrest/postgrest:v12.2.8")
	got, gotTag, err := d.sourceServingExpectedImages(context.Background())
	if err != nil {
		t.Fatalf("flagless source-image proof from carrier: %v", err)
	}
	if gotTag != sourceTag || !reflect.DeepEqual(got, servingEraExpected(sourceTag)) {
		t.Fatalf("flagless carrier proof = tag %q images %#v, want tag %q images %#v", gotTag, got, sourceTag, servingEraExpected(sourceTag))
	}

	logPath := filepath.Join(t.TempDir(), "docker.log")
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	// The capture above modeled a serving box (app/worker/rest running). By the
	// time recovery restarts the source stack the upgrade has stopped them
	// (executeUpgrade's compose stop); the database convergence verifies that
	// before it may recreate db. Live clients are covered by
	// TestSourceDatabaseConvergenceStopsLiveClientsFirst.
	for _, service := range sourceServingClientServices {
		t.Setenv("STATBUS_TEST_"+strings.ToUpper(service)+"_STATE", "exited")
	}
	srv, rpcHits := sourceStackHealthServer(t)
	d.cachedURL = srv.URL + "/rpc/auth_status"
	d.cachedReadyURL = srv.URL + "/ready"
	if err := d.startSourceApplicationStack(context.Background(), nil); err != nil {
		t.Fatalf("restart source stack from independent carrier: %v", err)
	}
	if *rpcHits == 0 {
		t.Fatal("source stack restart did not reach the functional health gate")
	}
	logBytes, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(logBytes), "compose start app worker rest proxy\n") {
		t.Fatalf("source stack was not restarted in place from the carrier proof:\n%s", logBytes)
	}
}

func sourceStackTestProgress(t *testing.T, projDir string) (*ProgressLog, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "progress.log")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })
	return &ProgressLog{projDir: projDir, absPath: path, file: file}, path
}

func TestStartSourceApplicationStackLegacyPreCaptureStartsDaemonVerifiedContainers(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, map[string]sourceImageIdentity{})
	srv, rpcHits := sourceStackHealthServer(t)
	progress, progressPath := sourceStackTestProgress(t, git.dir)

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
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_SOURCE_ID"'","Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'","Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_SOURCE_ID"'","Service":"rest","State":"exited","Image":"postgrest/postgrest:v12.2.8"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'","Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}'
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
	if err := d.startSourceApplicationStack(context.Background(), progress); err != nil {
		t.Fatalf("legacy source stack start: %v", err)
	}
	if *rpcHits != 1 {
		t.Fatalf("health gate hits = %d, want 1", *rpcHits)
	}
	dockerLog, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"inspect --format {{.Image}} " + servingEraTestImageID('1'),
		"inspect --format {{.Image}} " + servingEraTestImageID('2'),
		"inspect --format {{.Image}} " + servingEraTestImageID('3'),
		"inspect --format {{.Image}} " + servingEraTestImageID('4'),
		"compose start app worker rest proxy",
	} {
		if !strings.Contains(string(dockerLog), want) {
			t.Fatalf("legacy existing-container proof did not execute %q:\n%s", want, dockerLog)
		}
	}
	progressBytes, err := os.ReadFile(progressPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(progressBytes), "legacy source era (pre-capture release)") {
		t.Fatalf("legacy proof was not distinctly labeled in progress:\n%s", progressBytes)
	}
}

func TestStartSourceApplicationStackLegacyPreCaptureRecreatesWhenContainersAreAbsent(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, map[string]sourceImageIdentity{})
	srv, rpcHits := sourceStackHealthServer(t)
	progress, progressPath := sourceStackTestProgress(t, git.dir)

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
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_SOURCE_ID"'","Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"}'
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'","Service":"worker","State":"running","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"}'
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_SOURCE_ID"'","Service":"rest","State":"running","Image":"postgrest/postgrest:v12.2.8"}'
			printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'","Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}'
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
	if err := d.startSourceApplicationStack(context.Background(), progress); err != nil {
		t.Fatalf("legacy source stack recreation: %v", err)
	}
	if *rpcHits != 1 {
		t.Fatalf("health gate hits = %d, want 1", *rpcHits)
	}
	dockerLog, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-app:" + sourceTag,
		"image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-worker:" + sourceTag,
		"image inspect --format {{.Id}} postgrest/postgrest:v12.2.8",
		"image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-proxy:" + sourceTag,
		"compose up -d --no-build --no-deps app worker rest proxy",
	} {
		if !strings.Contains(string(dockerLog), want) {
			t.Fatalf("legacy absent-container proof did not execute %q:\n%s", want, dockerLog)
		}
	}
	progressBytes, err := os.ReadFile(progressPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(progressBytes), "legacy source era (pre-capture release)") {
		t.Fatalf("legacy recreation was not distinctly labeled in progress:\n%s", progressBytes)
	}
}

func TestStartSourceApplicationStackLegacyPreCaptureRejectsDigestModelWithoutContainers(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, map[string]sourceImageIdentity{})

	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	digest := servingEraTestImageID('9')
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app@'"$STATBUS_TEST_DIGEST"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json") ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)
	t.Setenv("STATBUS_TEST_DIGEST", digest)

	d := &Service{projDir: git.dir}
	err := d.startSourceApplicationStack(context.Background(), nil)
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "legacy source era") || !strings.Contains(err.Error(), "digest") {
		t.Fatalf("legacy digest-model refusal = %T %v, want named fail-closed legacy digest refusal", err, err)
	}
	dockerLog, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	for _, forbidden := range []string{"image inspect", "compose start", "compose up"} {
		if strings.Contains(string(dockerLog), forbidden) {
			t.Fatalf("legacy digest model must refuse before %q:\n%s", forbidden, dockerLog)
		}
	}
}

func TestLegacySourceServingExpectedImagesAcceptsExplicitLocalTags(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose ps -a --format json") ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	references := map[string]string{
		"app":    "ghcr.io/statisticsnorway/statbus-app:local",
		"worker": "ghcr.io/statisticsnorway/statbus-worker:local",
		"rest":   "postgrest/postgrest:v12.2.8",
		"proxy":  "ghcr.io/statisticsnorway/statbus-proxy:local",
	}
	d := &Service{projDir: t.TempDir()}
	expected, proof, err := d.legacySourceServingExpectedImages(context.Background(), references)
	if err != nil {
		t.Fatalf("explicit local legacy references: %v", err)
	}
	if proof != sourceServingIdentityProofLegacyModel {
		t.Fatalf("proof = %q, want %q", proof, sourceServingIdentityProofLegacyModel)
	}
	for _, service := range sourceServingServices {
		if expected[service].Reference != references[service] {
			t.Fatalf("%s reference = %q, want %q", service, expected[service].Reference, references[service])
		}
	}
}

func TestLegacySourceConvergenceFailureSurvivesInRollbackRowDetail(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, map[string]sourceImageIdentity{})

	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_SOURCE_ID"'","Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'","Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_SOURCE_ID"'","Service":"rest","State":"exited","Image":"postgrest/postgrest:v12.2.8"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'","Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		;;
	"compose start app worker rest proxy")
		echo 'injected legacy source start failure' >&2
		exit 42
		;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)

	d := &Service{projDir: git.dir}
	servicesErr := d.startSourceApplicationStack(context.Background(), nil)
	if servicesErr == nil || !strings.Contains(servicesErr.Error(), "legacy source era (pre-capture release)") || !strings.Contains(servicesErr.Error(), "injected legacy source start failure") {
		t.Fatalf("legacy convergence error = %v, want path label and exact cause", servicesErr)
	}
	var legacyErr *legacySourceEraError
	if !errors.As(servicesErr, &legacyErr) {
		t.Fatalf("legacy convergence error = %T %v, want typed legacy marker", servicesErr, servicesErr)
	}
	details := rollbackCompletionErrors{servicesStart: servicesErr}.details()
	rowError := "upgrade failed — ROLLBACK INCOMPLETE; " + strings.Join(details, "; ")
	for _, want := range []string{"legacy source era (pre-capture release)", "injected legacy source start failure"} {
		if !strings.Contains(rowError, want) {
			t.Fatalf("durable rollback row error %q does not retain %q", rowError, want)
		}
	}
}

func TestLegacySourceProofAcquisitionFailureSurvivesInRollbackRowDetail(t *testing.T) {
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, map[string]sourceImageIdentity{})

	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		echo 'injected legacy compose ps failure' >&2
		exit 42
		;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)

	d := &Service{projDir: git.dir}
	servicesErr := d.startSourceApplicationStack(context.Background(), nil)
	var legacyErr *legacySourceEraError
	if !errors.As(servicesErr, &legacyErr) {
		t.Fatalf("legacy proof acquisition error = %T %v, want typed legacy marker", servicesErr, servicesErr)
	}
	details := rollbackCompletionErrors{servicesStart: servicesErr}.details()
	rowError := "upgrade failed — ROLLBACK INCOMPLETE; " + strings.Join(details, "; ")
	for _, want := range []string{legacySourceEraLabel, "injected legacy compose ps failure"} {
		if !strings.Contains(rowError, want) {
			t.Fatalf("durable rollback row error %q does not retain %q", rowError, want)
		}
	}
}

func TestStartSourceApplicationStackLegacyPreCaptureRejectsAmbiguousPartialContainers(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, map[string]sourceImageIdentity{})

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
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_SOURCE_ID"'","Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'","Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'","Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}'
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
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "legacy source era") || !strings.Contains(err.Error(), "partial") {
		t.Fatalf("legacy partial-container refusal = %T %v, want named fail-closed legacy ambiguity", err, err)
	}
	dockerLog, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if strings.Contains(string(dockerLog), "compose start") || strings.Contains(string(dockerLog), "compose up") {
		t.Fatalf("ambiguous legacy source identity must refuse before any serving action:\n%s", dockerLog)
	}
}

func TestSourceServingExpectedImagesRecordedPathDoesNotFallBackToLegacy(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	recorded := servingEraExpected(sourceTag)
	delete(recorded, "worker")
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, recorded)
	installSourceCaptureDockerShim(t, sourceTag, sourceTag, sourceTag, sourceTag, nil)

	d := &Service{projDir: git.dir}
	_, _, err := d.sourceServingExpectedImages(context.Background())
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "recovery marker has no pre-upgrade source image identity for worker") {
		t.Fatalf("partial recorded proof = %T %v, want marker-specific fail-closed refusal without legacy fallback", err, err)
	}
}

func TestTruthfulTerminalCleanupRemovesMarkerAndSourceImageCarrier(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir}
	commitSHA := strings.Repeat("a", 40)
	if err := d.writeUpgradeFlag(183, commitSHA, nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil || flag == nil {
		t.Fatalf("read marker before carrier write: flag=%#v err=%v", flag, err)
	}
	if err := d.writeSourceServingImagesCarrierAtomically(*flag, map[string]sourceImageIdentity{
		"app": {Reference: "app:source", ImageID: servingEraTestImageID('1')},
	}, map[string]string{"app": "running"}); err != nil {
		t.Fatal(err)
	}
	if err := d.removeUpgradeArtifacts(); err != nil {
		t.Fatalf("removeUpgradeArtifacts: %v", err)
	}
	for _, path := range []string{d.flagPath(), sourceServingImagesCarrierPath(projDir)} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("truthful terminal cleanup left %s: %v", path, err)
		}
	}
}

func TestSourceImageCarrierWriterUsesAtomicDurabilityDiscipline(t *testing.T) {
	srcBytes, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/source_image_carrier.go"))
	if err != nil {
		t.Fatal(err)
	}
	body := extractFuncBody(t, string(srcBytes), "func (d *Service) writeSourceServingImagesCarrierAtomically(")
	steps := []string{
		"os.CreateTemp(",
		"syscall.Flock(",
		"tmp.Write(data)",
		"tmp.Sync()",
		"os.Rename(tmpPath, path)",
		"dirFile.Sync()",
	}
	last := -1
	for _, step := range steps {
		idx := strings.Index(body, step)
		if idx < 0 || idx <= last {
			t.Fatalf("source-image carrier atomic order missing/out of order at %q: previous=%d current=%d", step, last, idx)
		}
		last = idx
	}
	if !strings.Contains(body, "d.flagLock == nil || d.flagLock.file == nil") {
		t.Fatal("source-image carrier writer must require the canonical recovery-marker flock")
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
	if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), "neither the captured source compose model nor pending target ffffffff") {
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

func TestCaptureSourceServingImageIdentitiesRequiresRunningRouteAndRecordsWorkerState(t *testing.T) {
	tests := []struct {
		name       string
		states     map[string]string
		missing    map[string]bool
		wantErrSub string
	}{
		{name: "all running"},
		{
			name: "all exited is ambiguous",
			states: map[string]string{
				"app": "exited", "worker": "exited", "rest": "exited", "proxy": "exited",
			},
			wantErrSub: `pre-upgrade source route container for app is not running (state "exited")`,
		},
		{
			name:   "intentionally stopped worker",
			states: map[string]string{"worker": "exited"},
		},
		{
			name:   "created worker",
			states: map[string]string{"worker": "created"},
		},
		{
			name:   "dead worker",
			states: map[string]string{"worker": "dead"},
		},
		{
			name:       "app exited",
			states:     map[string]string{"app": "exited"},
			wantErrSub: `pre-upgrade source route container for app is not running (state "exited")`,
		},
		{
			name:       "rest exited",
			states:     map[string]string{"rest": "exited"},
			wantErrSub: `pre-upgrade source route container for rest is not running (state "exited")`,
		},
		{
			name:       "proxy exited",
			states:     map[string]string{"proxy": "exited"},
			wantErrSub: `pre-upgrade source route container for proxy is not running (state "exited")`,
		},
		{
			name:       "paused worker",
			states:     map[string]string{"worker": "paused"},
			wantErrSub: `pre-upgrade source worker is neither running nor stably stopped (state "paused")`,
		},
		{
			name:       "restarting worker",
			states:     map[string]string{"worker": "restarting"},
			wantErrSub: `pre-upgrade source worker is neither running nor stably stopped (state "restarting")`,
		},
		{
			name:       "empty state",
			states:     map[string]string{"worker": ""},
			wantErrSub: `pre-upgrade source container for worker has empty or unknown state ""`,
		},
		{
			name:       "unknown state",
			states:     map[string]string{"worker": "removing"},
			wantErrSub: `pre-upgrade source container for worker has empty or unknown state "removing"`,
		},
		{
			name:       "missing container",
			missing:    map[string]bool{"worker": true},
			wantErrSub: "pre-upgrade source container for worker is missing",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			setSourceStackImageIdentityEnv(t)
			git := newGitRepoFixture(t)
			sourceTag := git.oldSHA[:8]
			targetTag := git.newSHA[:8]
			installSourceCaptureDockerShimWithMissing(t, targetTag, sourceTag, sourceTag, sourceTag, tc.states, tc.missing)

			d := &Service{projDir: git.dir}
			if err := d.writeUpgradeFlag(21, git.newSHA, nil, "test", "test", false); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = d.removeUpgradeFlag() })
			err := d.captureSourceServingImageIdentities(context.Background())
			if tc.wantErrSub == "" {
				if err != nil {
					t.Fatalf("captureSourceServingImageIdentities with running route tier and admitted worker state: %v", err)
				}
			} else {
				var eraErr *sourceServingEraUnknownError
				if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), tc.wantErrSub) {
					t.Fatalf("capture error = %v, want named capture refusal containing %q", err, tc.wantErrSub)
				}
			}

			flag, readErr := ReadFlagFile(git.dir)
			if readErr != nil {
				t.Fatal(readErr)
			}
			if tc.wantErrSub == "" {
				want := servingEraExpected(sourceTag)
				if flag == nil || !reflect.DeepEqual(flag.SourceServingImages, want) {
					t.Fatalf("known-state capture identities = %#v, want %#v", flag, want)
				}
				wantStates := map[string]string{"app": "running", "worker": "running", "rest": "running", "proxy": "running"}
				for service, state := range tc.states {
					wantStates[service] = state
				}
				if !reflect.DeepEqual(flag.SourceServingStates, wantStates) {
					t.Fatalf("recorded source states = %#v, want %#v", flag.SourceServingStates, wantStates)
				}
			}
			if tc.wantErrSub != "" && flag != nil && (len(flag.SourceServingImages) != 0 || len(flag.SourceServingStates) != 0) {
				t.Fatalf("refused capture mutated marker: images=%#v states=%#v", flag.SourceServingImages, flag.SourceServingStates)
			}
			if tc.wantErrSub != "" {
				if _, statErr := os.Stat(sourceServingImagesCarrierPath(git.dir)); !os.IsNotExist(statErr) {
					t.Fatalf("refused capture wrote independent carrier: %v", statErr)
				}
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
		rm -f "$STATBUS_TEST_STOPPED"
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
	// The database convergence stops the live target clients before db can be
	// recreated (F2); the containment stop under test is the one AFTER the failed up.
	stopIdx := -1
	if upIdx >= 0 {
		if rel := strings.Index(log[upIdx:], "compose stop app worker rest\n"); rel >= 0 {
			stopIdx = upIdx + rel
		}
	}
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

// Demo incident: compose ps prints the sha256 image ID in Image when the tag
// display is lost. The container's Config.Image must be the reference used.
func TestSourceServingContainerEntriesUsesConfigImageNotComposeDisplay(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	"compose ps -a --format json")
		printf '%s\n' '{"ID":"worker-container","Service":"worker","State":"running","Image":"sha256:5207b175fa080e47a942e236a29fe801113df99c634aaef2272d9d5e34fa1645"}'
		;;
	"inspect --format {{.Image}} worker-container") printf '%s\n' "$STATBUS_TEST_WORKER_SOURCE_ID" ;;
	"inspect --format {{.Config.Image}} worker-container") printf '%s\n' "ghcr.io/statisticsnorway/statbus-worker:fe4a769a" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	d := &Service{projDir: t.TempDir()}
	entries, err := d.sourceServingContainerEntries(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Image != "ghcr.io/statisticsnorway/statbus-worker:fe4a769a" {
		t.Fatalf("entries = %+v, want Config.Image reference", entries)
	}
}

func runServingEntriesWithConfigImage(t *testing.T, configCase string) error {
	t.Helper()
	setSourceStackImageIdentityEnv(t)
	shimDir := t.TempDir()
	shim := `#!/bin/sh
case "$*" in
	"compose ps -a --format json")
		printf '%s\n' '{"ID":"worker-container","Service":"worker","State":"running","Image":"ghcr.io/statisticsnorway/statbus-worker:fe4a769a"}'
		;;
	"inspect --format {{.Image}} worker-container") printf '%s\n' "$STATBUS_TEST_WORKER_SOURCE_ID" ;;
	"inspect --format {{.Config.Image}} worker-container")
` + configCase + `
		;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	d := &Service{projDir: t.TempDir()}
	_, err := d.sourceServingContainerEntries(context.Background())
	return err
}

// Empty, malformed or failing Config.Image must refuse, never fall back to
// the compose ps display string (STATBUS-436).
func TestSourceServingContainerEntriesRefusesUnprovableConfigImage(t *testing.T) {
	for name, c := range map[string]string{
		"empty":     `printf '\n'`,
		"multiline": `printf 'a:1\nb:2\n'`,
		"failure":   `exit 9`,
	} {
		t.Run(name, func(t *testing.T) {
			err := runServingEntriesWithConfigImage(t, c)
			var eraErr *sourceServingEraUnknownError
			if !errors.As(err, &eraErr) {
				t.Fatalf("error = %v, want sourceServingEraUnknownError", err)
			}
		})
	}
}

// wrapDockerComposePsDisplay makes `docker compose ps` print a raw sha256 in
// Image for every container (the demo incident), while the inner shim keeps
// answering Config.Image with the real requested reference. When
// emptyConfigImage is set, Config.Image inspection returns empty instead.
func wrapDockerComposePsDisplay(t *testing.T, emptyConfigImage bool) {
	t.Helper()
	inner, err := exec.LookPath("docker")
	if err != nil {
		t.Fatal(err)
	}
	wrapDir := t.TempDir()
	empty := "0"
	if emptyConfigImage {
		empty = "1"
	}
	wrapper := `#!/bin/sh
if [ "$*" = "compose ps -a --format json" ]; then
	` + inner + ` "$@" | sed '/"Service":"worker"/s/"Image":"[^"]*"/"Image":"sha256:5207b175fa080e47a942e236a29fe801113df99c634aaef2272d9d5e34fa1645"/'
	exit 0
fi
if [ "` + empty + `" = 1 ] && [ "$2" = "--format" ] && [ "$3" = "{{.Config.Image}}" ]; then echo; exit 0; fi
exec ` + inner + ` "$@"
`
	if err := os.WriteFile(filepath.Join(wrapDir, "docker"), []byte(wrapper), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", wrapDir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func TestCaptureSourceServingImageIdentitiesSurvivesLostComposeDisplay(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	treeTag := git.newSHA[:8]
	installSourceCaptureDockerShim(t, treeTag, sourceTag, sourceTag, sourceTag, nil)
	wrapDockerComposePsDisplay(t, false)
	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(21, git.newSHA, nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })
	if err := d.captureSourceServingImageIdentities(context.Background()); err != nil {
		t.Fatalf("real capture with lost compose display must succeed from Config.Image: %v", err)
	}
}

func TestCaptureSourceServingImageIdentitiesRefusesEmptyConfigImage(t *testing.T) {
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	treeTag := git.newSHA[:8]
	installSourceCaptureDockerShim(t, treeTag, sourceTag, sourceTag, sourceTag, nil)
	wrapDockerComposePsDisplay(t, true)
	d := &Service{projDir: git.dir}
	if err := d.writeUpgradeFlag(22, git.newSHA, nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })
	err := d.captureSourceServingImageIdentities(context.Background())
	var eraErr *sourceServingEraUnknownError
	if !errors.As(err, &eraErr) {
		t.Fatalf("real capture error = %v, want sourceServingEraUnknownError (deterministic, parkable)", err)
	}
}
