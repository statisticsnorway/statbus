package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func installParkedSuccessorConvergenceShim(t *testing.T, treeTag, sourceTag string, failConvergence bool) string {
	t.Helper()
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	convergedPath := filepath.Join(shimDir, "converged")
	stoppedPath := filepath.Join(shimDir, "stopped")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
  "compose --profile all config --format json")
    printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_TREE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_TREE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_TREE_TAG"'"}}}'
    ;;
	  "compose ps -a --format json")
	    tag="$STATBUS_TEST_SOURCE_TAG"
	    client_state=running
	    if [ -f "$STATBUS_TEST_STOPPED_PATH" ]; then client_state=exited; fi
    app_id="$STATBUS_TEST_APP_SOURCE_ID"
    worker_id="$STATBUS_TEST_WORKER_SOURCE_ID"
    rest_id="$STATBUS_TEST_REST_SOURCE_ID"
    proxy_id="$STATBUS_TEST_PROXY_SOURCE_ID"
    if [ -f "$STATBUS_TEST_CONVERGED_PATH" ]; then
      tag="$STATBUS_TEST_TREE_TAG"
      app_id="$STATBUS_TEST_APP_TREE_ID"
      worker_id="$STATBUS_TEST_WORKER_TREE_ID"
      rest_id="$STATBUS_TEST_REST_TREE_ID"
      proxy_id="$STATBUS_TEST_PROXY_TREE_ID"
    fi
	    printf '%s\n' '{"ID":"app-container","Service":"app","State":"'"$client_state"'","Image":"ghcr.io/statisticsnorway/statbus-app:'"$tag"'","ImageID":"'"$app_id"'"}'
	    printf '%s\n' '{"ID":"worker-container","Service":"worker","State":"'"$client_state"'","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$tag"'","ImageID":"'"$worker_id"'"}'
	    printf '%s\n' '{"ID":"rest-container","Service":"rest","State":"'"$client_state"'","Image":"postgrest/postgrest:v12.2.8","ImageID":"'"$rest_id"'"}'
    printf '%s\n' '{"ID":"proxy-container","Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$tag"'","ImageID":"'"$proxy_id"'"}'
    ;;
  "inspect --format {{.Image}} app-container")
    if [ -f "$STATBUS_TEST_CONVERGED_PATH" ]; then printf '%s\n' "$STATBUS_TEST_APP_TREE_ID"; else printf '%s\n' "$STATBUS_TEST_APP_SOURCE_ID"; fi
    ;;
  "inspect --format {{.Image}} worker-container")
    if [ -f "$STATBUS_TEST_CONVERGED_PATH" ]; then printf '%s\n' "$STATBUS_TEST_WORKER_TREE_ID"; else printf '%s\n' "$STATBUS_TEST_WORKER_SOURCE_ID"; fi
    ;;
  "inspect --format {{.Image}} rest-container")
    if [ -f "$STATBUS_TEST_CONVERGED_PATH" ]; then printf '%s\n' "$STATBUS_TEST_REST_TREE_ID"; else printf '%s\n' "$STATBUS_TEST_REST_SOURCE_ID"; fi
    ;;
  "inspect --format {{.Image}} proxy-container")
    if [ -f "$STATBUS_TEST_CONVERGED_PATH" ]; then printf '%s\n' "$STATBUS_TEST_PROXY_TREE_ID"; else printf '%s\n' "$STATBUS_TEST_PROXY_SOURCE_ID"; fi
    ;;
	  "image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-app:"*) [ "$STATBUS_TEST_MISSING_TREE_IMAGES" = 1 ] && exit 44; printf '%s\n' "$STATBUS_TEST_APP_TREE_ID" ;;
	  "image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-worker:"*) [ "$STATBUS_TEST_MISSING_TREE_IMAGES" = 1 ] && exit 44; printf '%s\n' "$STATBUS_TEST_WORKER_TREE_ID" ;;
	  "image inspect --format {{.Id}} postgrest/postgrest:v12.2.8") [ "$STATBUS_TEST_MISSING_TREE_IMAGES" = 1 ] && exit 44; printf '%s\n' "$STATBUS_TEST_REST_TREE_ID" ;;
	  "image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-proxy:"*) [ "$STATBUS_TEST_MISSING_TREE_IMAGES" = 1 ] && exit 44; printf '%s\n' "$STATBUS_TEST_PROXY_TREE_ID" ;;
	  "compose up -d --no-build --no-deps app worker rest proxy")
	    if [ "$STATBUS_TEST_FAIL_CONVERGENCE" = 1 ] || [ "$STATBUS_TEST_MISSING_TREE_IMAGES" = 1 ]; then
	      echo "synthetic parked successor convergence failure" >&2
	      exit 42
	    fi
	    : > "$STATBUS_TEST_CONVERGED_PATH"
	    ;;
	  "compose stop app worker rest") : > "$STATBUS_TEST_STOPPED_PATH" ;;
	  *" pull "*) echo "synthetic stop after source capture" >&2; exit 77 ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_CONVERGED_PATH", convergedPath)
	t.Setenv("STATBUS_TEST_STOPPED_PATH", stoppedPath)
	t.Setenv("STATBUS_TEST_TREE_TAG", treeTag)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)
	t.Setenv("STATBUS_TEST_FAIL_CONVERGENCE", map[bool]string{false: "0", true: "1"}[failConvergence])
	t.Setenv("STATBUS_TEST_APP_SOURCE_ID", servingEraTestImageID('1'))
	t.Setenv("STATBUS_TEST_WORKER_SOURCE_ID", servingEraTestImageID('2'))
	t.Setenv("STATBUS_TEST_REST_SOURCE_ID", servingEraTestImageID('3'))
	t.Setenv("STATBUS_TEST_PROXY_SOURCE_ID", servingEraTestImageID('4'))
	t.Setenv("STATBUS_TEST_APP_TREE_ID", servingEraTestImageID('a'))
	t.Setenv("STATBUS_TEST_WORKER_TREE_ID", servingEraTestImageID('b'))
	t.Setenv("STATBUS_TEST_REST_TREE_ID", servingEraTestImageID('c'))
	t.Setenv("STATBUS_TEST_PROXY_TREE_ID", servingEraTestImageID('d'))
	return logPath
}

func treeServingIdentities(treeTag string) map[string]sourceImageIdentity {
	return map[string]sourceImageIdentity{
		"app":    {Reference: "ghcr.io/statisticsnorway/statbus-app:" + treeTag, ImageID: servingEraTestImageID('a')},
		"worker": {Reference: "ghcr.io/statisticsnorway/statbus-worker:" + treeTag, ImageID: servingEraTestImageID('b')},
		"rest":   {Reference: "postgrest/postgrest:v12.2.8", ImageID: servingEraTestImageID('c')},
		"proxy":  {Reference: "ghcr.io/statisticsnorway/statbus-proxy:" + treeTag, ImageID: servingEraTestImageID('d')},
	}
}

func TestAstraReviewParkedSourceMustPermitNextDaemonCapture(t *testing.T) {
	git := newGitRepoFixture(t)
	treeTag := git.newSHA[:8]
	sourceTag := git.oldSHA[:8]
	logPath := installParkedSuccessorConvergenceShim(t, treeTag, sourceTag, false)
	srv, _ := sourceStackHealthServer(t)
	d := &Service{projDir: git.dir, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	candidateC := strings.Repeat("c", 40)
	if err := d.writeUpgradeFlag(33, candidateC, nil, "scheduled", "scheduled", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })

	if err := d.convergeParkedServingTierToCurrentTree(context.Background(), nil); err != nil {
		t.Fatalf("converge parked A containers to B tree: %v", err)
	}
	if err := d.captureSourceServingImageIdentities(context.Background()); err != nil {
		t.Fatalf("capture B as C source after convergence: %v", err)
	}
	flag, err := ReadFlagFile(git.dir)
	if err != nil {
		t.Fatal(err)
	}
	if flag == nil || !reflect.DeepEqual(flag.SourceServingImages, treeServingIdentities(treeTag)) {
		t.Fatalf("C source capture = %#v, want converged B identities %#v", flag, treeServingIdentities(treeTag))
	}
	logBytes, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	log := string(logBytes)
	if got := strings.Count(log, "compose up -d --no-build --no-deps app worker rest proxy\n"); got != 1 {
		t.Fatalf("parked successor must use exactly one controlled B-tree recreate, got %d:\n%s", got, log)
	}
}

func TestParkedSuccessorConvergenceFailureIsNamedTerminalNoRetry(t *testing.T) {
	git := newGitRepoFixture(t)
	logPath := installParkedSuccessorConvergenceShim(t, git.newSHA[:8], git.oldSHA[:8], true)
	d := &Service{projDir: git.dir}
	err := d.convergeParkedServingTierToCurrentTree(context.Background(), nil)
	if err == nil || !strings.Contains(err.Error(), "synthetic parked successor convergence failure") {
		t.Fatalf("convergence error = %v, want named synthetic failure", err)
	}
	logBytes, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if strings.Count(string(logBytes), "compose up -d --no-build --no-deps app worker rest proxy\n") != 1 {
		t.Fatalf("convergence failure must not loop:\n%s", logBytes)
	}

	src := readUpgradeServiceSource(t)
	claim := extractFuncBody(t, src, "func (d *Service) claimScheduledUpgradePass(")
	if !strings.Contains(claim, "tree_convergence_required = tree_convergence_required OR $3") ||
		!strings.Contains(claim, "&claim.Snapshot.RequiresServingTreeConvergence") {
		t.Fatal("a claim that displaces a park must persist and return the durable convergence requirement")
	}
	execute := extractFuncBody(t, src, "func (d *Service) executeUpgrade(")
	gateStart := strings.Index(execute, "if claim.RequiresServingTreeConvergence {")
	capture := strings.Index(execute, "d.captureSourceServingImageIdentities(ctx)")
	if gateStart < 0 || capture <= gateStart {
		t.Fatalf("successor convergence must precede source capture: gate=%d capture=%d", gateStart, capture)
	}
	gate := execute[gateStart:capture]
	for _, required := range []string{
		"d.convergeParkedServingTierToCurrentTree(ctx, progress)",
		"d.terminateServingTreeConvergenceFailure(ctx, id, err, progress)",
		"return fmt.Errorf",
	} {
		if !strings.Contains(gate, required) {
			t.Fatalf("successor convergence terminal is missing %q", required)
		}
	}
	terminal := extractFuncBody(t, src, "func (d *Service) terminateServingTreeConvergenceFailure(")
	for _, required := range []string{
		"PARKED_SERVING_TREE_CONVERGENCE_FAILED",
		"d.ensureRecoveryClientsStopped(ctx, progress)",
		"d.failUpgradeCodedKeepingFlag(ctx, id, ErrDockerUpFailed",
	} {
		if !strings.Contains(terminal, required) {
			t.Fatalf("successor convergence contained terminal is missing %q", required)
		}
	}
	for _, forbidden := range []string{"recordInProgressFailure", "newSbUpgradingFailure", "continue"} {
		if strings.Contains(gate, forbidden) {
			t.Fatalf("successor convergence failure must be terminal and non-looping, found %q", forbidden)
		}
	}
}
