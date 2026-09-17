package upgrade

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
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

func TestStartSourceApplicationStackStartsOnlyVerifiedSourceEraContainers(t *testing.T) {
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	srv, rpcHits := sourceStackHealthServer(t)

	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	  "compose ps -a --format json")
		    printf '%s\n' '{"Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		    printf '%s\n' '{"Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"}'
		    printf '%s\n' '{"Service":"rest","State":"exited","Image":"postgrest/postgrest:v12.2.8"}'
		    printf '%s\n' '{"Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}'
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

func TestStartSourceApplicationStackRecreatesDerivedTargetEraFromSourceTemplate(t *testing.T) {
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	srv, rpcHits := sourceStackHealthServer(t)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	convergedPath := filepath.Join(shimDir, "converged")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
  "compose ps -a --format json")
		if [ -f "$STATBUS_TEST_CONVERGED" ]; then
				printf '%s\n' '{"Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"}'
				printf '%s\n' '{"Service":"worker","State":"running","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"}'
				printf '%s\n' '{"Service":"rest","State":"running","Image":"postgrest/postgrest:v12.2.8"}'
				printf '%s\n' '{"Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}'
			else
				printf '%s\n' '{"Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:target999"}'
				printf '%s\n' '{"Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:target999"}'
				printf '%s\n' '{"Service":"rest","State":"exited","Image":"postgrest/postgrest:v13"}'
				printf '%s\n' '{"Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:target999"}'
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
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		printf '%s\n' '{"Service":"app","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-app:target999"}'
		printf '%s\n' '{"Service":"worker","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-worker:target999"}'
		printf '%s\n' '{"Service":"proxy","State":"exited","Image":"ghcr.io/statisticsnorway/statbus-proxy:target999"}'
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
	git := newGitRepoFixture(t)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose config --format json") printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:wrong"}}}' ;;
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
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	srv, rpcHits := sourceStackHealthServer(t)
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		printf '%s\n' '{"Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:target999"}'
		printf '%s\n' '{"Service":"worker","State":"running","Image":"ghcr.io/statisticsnorway/statbus-worker:target999"}'
		printf '%s\n' '{"Service":"rest","State":"running","Image":"postgrest/postgrest:v13"}'
		printf '%s\n' '{"Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:target999"}'
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
