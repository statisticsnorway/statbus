package upgrade

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func installParkedTargetDockerShim(t *testing.T, targetTag string, states map[string]string, failStart bool) string {
	t.Helper()
	serviceStates := map[string]string{"app": "running", "worker": "running", "rest": "running", "proxy": "running"}
	for service, state := range states {
		serviceStates[service] = state
	}

	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	startedPath := filepath.Join(shimDir, "started")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_TARGET_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_TARGET_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_TARGET_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		app_state="$STATBUS_TEST_APP_STATE"
		worker_state="$STATBUS_TEST_WORKER_STATE"
		rest_state="$STATBUS_TEST_REST_STATE"
		proxy_state="$STATBUS_TEST_PROXY_STATE"
		if [ -f "$STATBUS_TEST_STARTED_PATH" ]; then
			app_state=running
			worker_state=running
			rest_state=running
			proxy_state=running
		fi
		printf '%s\n' '{"ID":"app-container","Service":"app","State":"'"$app_state"'","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_CONTAINER_TAG"'"}'
		printf '%s\n' '{"ID":"worker-container","Service":"worker","State":"'"$worker_state"'","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_CONTAINER_TAG"'"}'
		printf '%s\n' '{"ID":"rest-container","Service":"rest","State":"'"$rest_state"'","Image":"postgrest/postgrest:v12.2.8"}'
		printf '%s\n' '{"ID":"proxy-container","Service":"proxy","State":"'"$proxy_state"'","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_CONTAINER_TAG"'"}'
		;;
	"inspect --format {{.Image}} app-container") printf '%s\n' "$STATBUS_TEST_APP_CONTAINER_ID" ;;
	"inspect --format {{.Image}} worker-container") printf '%s\n' "$STATBUS_TEST_WORKER_CONTAINER_ID" ;;
	"inspect --format {{.Image}} rest-container") printf '%s\n' "$STATBUS_TEST_REST_CONTAINER_ID" ;;
	"inspect --format {{.Image}} proxy-container") printf '%s\n' "$STATBUS_TEST_PROXY_CONTAINER_ID" ;;
	"image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-app:"*) printf '%s\n' "$STATBUS_TEST_APP_TARGET_ID" ;;
	"image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-worker:"*) printf '%s\n' "$STATBUS_TEST_WORKER_TARGET_ID" ;;
	"image inspect --format {{.Id}} postgrest/postgrest:v12.2.8") printf '%s\n' "$STATBUS_TEST_REST_TARGET_ID" ;;
	"image inspect --format {{.Id}} ghcr.io/statisticsnorway/statbus-proxy:"*) printf '%s\n' "$STATBUS_TEST_PROXY_TARGET_ID" ;;
	"compose start app worker rest proxy")
		if [ "$STATBUS_TEST_FAIL_START" = 1 ]; then
			echo "synthetic target start failure" >&2
			exit 42
		fi
		: > "$STATBUS_TEST_STARTED_PATH"
		;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_STARTED_PATH", startedPath)
	t.Setenv("STATBUS_TEST_TARGET_TAG", targetTag)
	t.Setenv("STATBUS_TEST_CONTAINER_TAG", targetTag)
	t.Setenv("STATBUS_TEST_APP_STATE", serviceStates["app"])
	t.Setenv("STATBUS_TEST_WORKER_STATE", serviceStates["worker"])
	t.Setenv("STATBUS_TEST_REST_STATE", serviceStates["rest"])
	t.Setenv("STATBUS_TEST_PROXY_STATE", serviceStates["proxy"])
	t.Setenv("STATBUS_TEST_FAIL_START", map[bool]string{false: "0", true: "1"}[failStart])
	t.Setenv("STATBUS_TEST_APP_TARGET_ID", servingEraTestImageID('a'))
	t.Setenv("STATBUS_TEST_WORKER_TARGET_ID", servingEraTestImageID('b'))
	t.Setenv("STATBUS_TEST_REST_TARGET_ID", servingEraTestImageID('c'))
	t.Setenv("STATBUS_TEST_PROXY_TARGET_ID", servingEraTestImageID('d'))
	t.Setenv("STATBUS_TEST_APP_CONTAINER_ID", servingEraTestImageID('a'))
	t.Setenv("STATBUS_TEST_WORKER_CONTAINER_ID", servingEraTestImageID('b'))
	t.Setenv("STATBUS_TEST_REST_CONTAINER_ID", servingEraTestImageID('c'))
	t.Setenv("STATBUS_TEST_PROXY_CONTAINER_ID", servingEraTestImageID('d'))
	return logPath
}

func writeParkedSourceIdentityFlag(t *testing.T, projDir, targetSHA, sourceTag string) {
	t.Helper()
	flag := UpgradeFlag{
		ID:                  1,
		CommitSHA:           targetSHA,
		Holder:              HolderService,
		Phase:               PhaseNewSbSwapped,
		SourceServingImages: servingEraExpected(sourceTag),
	}
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

func writeParkedSourceIdentityCarrier(t *testing.T, projDir, targetSHA, sourceTag string) {
	t.Helper()
	carrier := sourceServingImagesCarrier{
		ID:                  1,
		CommitSHA:           targetSHA,
		SourceServingImages: servingEraExpected(sourceTag),
	}
	data, err := json.Marshal(carrier)
	if err != nil {
		t.Fatal(err)
	}
	path := sourceServingImagesCarrierPath(projDir)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func readParkedTargetDockerLog(t *testing.T, logPath string) string {
	t.Helper()
	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func parkedSourceOperabilityService(t *testing.T, projDir string) (*Service, string, *bool) {
	t.Helper()
	srv, _ := sourceStackHealthServer(t)
	home := t.TempDir()
	t.Setenv("HOME", home)
	maintenancePath := maintenanceFlagHostPath()
	if err := os.MkdirAll(filepath.Dir(maintenancePath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(maintenancePath, []byte("parked maintenance"), 0o644); err != nil {
		t.Fatal(err)
	}
	lifted := false
	d := &Service{
		projDir:        projDir,
		cachedURL:      srv.URL + "/rpc/auth_status",
		cachedReadyURL: srv.URL + "/ready",
		parkEraVerdictForTest: func(_ context.Context, _ int) (bool, string) {
			return parkEraDecision(20260921000000, 20260921000000)
		},
		liftReadOnlyWindowForTest: func(reason string) (string, error) {
			if !strings.Contains(reason, "parked source health") {
				t.Fatalf("read-only lift reason = %q, want parked source health", reason)
			}
			lifted = true
			return "ALTER DATABASE test SET default_transaction_read_only = off", nil
		},
	}
	return d, maintenancePath, &lifted
}

// TestParkForDeterministicFailureAtTargetPreStartRoutesToTargetOperability composes
// the live helper tests below with the real park route. It is the mutation oracle:
// restoring the old unconditional ObservedAlreadyAtNew return removes the helper
// call and makes this pre-start case red.
func TestParkForDeterministicFailureAtTargetPreStartRoutesToTargetOperability(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	park := extractFuncBody(t, src, "func (d *Service) parkForDeterministicFailure(")
	atTargetIdx := strings.Index(park, "if obsState == ObservedAlreadyAtNew {")
	unreadableIdx := strings.Index(park, "d.parkServiceRecovery(ctx, id, restoreTargetSHA, progress, d.StartDatabaseRouteServingMayRun, true)")
	if atTargetIdx < 0 || unreadableIdx <= atTargetIdx {
		t.Fatalf("could not isolate the at-target park branch: atTarget@%d unreadable@%d", atTargetIdx, unreadableIdx)
	}
	branch := park[atTargetIdx:unreadableIdx]
	ensureIdx := strings.Index(branch, "d.ensureParkedAtNewServingTier(ctx, id, commitSHA, progress)")
	appendIdx := strings.Index(branch, "d.appendParkNarrative(id, operabilityNote)")
	returnIdx := strings.Index(branch, `return fmt.Errorf("parked on deterministic forward failure: %s", reason)`)
	if ensureIdx < 0 || appendIdx < ensureIdx || returnIdx < appendIdx {
		t.Fatalf("pre-start at-target park must ensure target operability and record its narrative before returning: ensure@%d append@%d return@%d", ensureIdx, appendIdx, returnIdx)
	}
	for _, forbidden := range []string{"parkServiceRecovery", "restoreSourceServices", "StartDatabaseRouteServingMustBeStopped"} {
		if strings.Contains(branch, forbidden) {
			t.Fatalf("pre-start at-target park must not reach source-era action %q", forbidden)
		}
	}
}

func TestEnsureParkedAtNewServingTierStartsStoppedTargetContainersInPlace(t *testing.T) {
	git := newGitRepoFixture(t)
	logPath := installParkedTargetDockerShim(t, git.newSHA[:8], map[string]string{
		"app": "exited", "worker": "exited", "rest": "exited", "proxy": "running",
	}, false)

	d := &Service{projDir: git.dir}
	note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
	if !strings.Contains(note, "started in place for parked-box operability") {
		t.Fatalf("success narrative = %q, want in-place operability start", note)
	}
	log := readParkedTargetDockerLog(t, logPath)
	if !strings.Contains(log, "compose start app worker rest proxy\n") {
		t.Fatalf("stopped target serving tier was not started in place:\n%s", log)
	}
	for _, forbidden := range []string{"compose up", "compose stop", "compose down"} {
		if strings.Contains(log, forbidden) {
			t.Fatalf("target park operability must not use %q:\n%s", forbidden, log)
		}
	}
}

func TestEnsureParkedAtNewServingTierStartsProvedSourceContainersInPlace(t *testing.T) {
	for _, proof := range []struct {
		name  string
		write func(*testing.T, string, string, string)
	}{
		{name: "recovery-marker", write: writeParkedSourceIdentityFlag},
		{name: "source-image-carrier", write: writeParkedSourceIdentityCarrier},
	} {
		t.Run(proof.name, func(t *testing.T) {
			git := newGitRepoFixture(t)
			sourceTag := git.oldSHA[:8]
			logPath := installParkedTargetDockerShim(t, git.newSHA[:8], map[string]string{
				"app": "exited", "worker": "exited", "rest": "exited", "proxy": "running",
			}, false)
			t.Setenv("STATBUS_TEST_CONTAINER_TAG", sourceTag)
			t.Setenv("STATBUS_TEST_APP_CONTAINER_ID", servingEraTestImageID('1'))
			t.Setenv("STATBUS_TEST_WORKER_CONTAINER_ID", servingEraTestImageID('2'))
			t.Setenv("STATBUS_TEST_REST_CONTAINER_ID", servingEraTestImageID('3'))
			t.Setenv("STATBUS_TEST_PROXY_CONTAINER_ID", servingEraTestImageID('4'))
			proof.write(t, git.dir, git.newSHA, sourceTag)

			d, maintenancePath, lifted := parkedSourceOperabilityService(t, git.dir)
			note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
			if !strings.Contains(note, "serving source-era containers for parked-box operability") {
				t.Fatalf("source-era success narrative = %q, want honest source-era operability label", note)
			}
			log := readParkedTargetDockerLog(t, logPath)
			if got := strings.Count(log, "compose start app worker rest proxy\n"); got != 1 {
				t.Fatalf("proved source-era tier must be started exactly once in place, got %d starts:\n%s", got, log)
			}
			for _, forbidden := range []string{"compose up", "compose stop", "compose down", "image inspect"} {
				if strings.Contains(log, forbidden) {
					t.Fatalf("source-era park operability must not use target-image or recreate action %q:\n%s", forbidden, log)
				}
			}
			if _, err := os.Stat(maintenancePath); !os.IsNotExist(err) {
				t.Fatalf("successful source operability must remove the sanctioned maintenance marker, stat err=%v", err)
			}
			if !*lifted {
				t.Fatal("successful source operability must lift the read-only window after health")
			}
		})
	}
}

func TestAstraReviewPostDeltaParkMustNotStartSource(t *testing.T) {
	// Exact reachable step-11 disk-precheck shape: target migrations committed,
	// so position is AtNew, but compose up has not run and the stopped serving
	// containers are still the recorded source era.
	const sourceMax int64 = 20260921000000
	const targetMax int64 = 20260922000000
	observed, _, _ := migrationObservedStateFromVersions([]int64{sourceMax, targetMax}, []int64{sourceMax, targetMax})
	if observed != ObservedAlreadyAtNew {
		t.Fatalf("post-migration pre-step-11 fixture position = %v, want AtNew", observed)
	}
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	logPath := installParkedTargetDockerShim(t, git.newSHA[:8], map[string]string{
		"app": "exited", "worker": "exited", "rest": "exited", "proxy": "running",
	}, false)
	t.Setenv("STATBUS_TEST_CONTAINER_TAG", sourceTag)
	t.Setenv("STATBUS_TEST_APP_CONTAINER_ID", servingEraTestImageID('1'))
	t.Setenv("STATBUS_TEST_WORKER_CONTAINER_ID", servingEraTestImageID('2'))
	t.Setenv("STATBUS_TEST_REST_CONTAINER_ID", servingEraTestImageID('3'))
	t.Setenv("STATBUS_TEST_PROXY_CONTAINER_ID", servingEraTestImageID('4'))
	writeParkedSourceIdentityFlag(t, git.dir, git.newSHA, sourceTag)

	srv, _ := sourceStackHealthServer(t)
	d := &Service{
		projDir:        git.dir,
		cachedURL:      srv.URL + "/rpc/auth_status",
		cachedReadyURL: srv.URL + "/ready",
		parkEraVerdictForTest: func(_ context.Context, _ int) (bool, string) {
			return parkEraDecision(targetMax, sourceMax)
		},
		liftReadOnlyWindowForTest: func(string) (string, error) {
			return "ALTER DATABASE test SET default_transaction_read_only = off", nil
		},
	}
	note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
	log := readParkedTargetDockerLog(t, logPath)
	if strings.Contains(log, "compose start") {
		t.Fatalf("post-migration pre-step-11 park must not start source containers:\n%s", log)
	}
	if !strings.Contains(note, "migration delta applied") || !strings.Contains(note, "source-schema compatibility proof refused") {
		t.Fatalf("post-delta refusal narrative = %q, want real schema-comparator refusal", note)
	}
	wantNarrative := "source-schema proof refused the source-era start; db+proxy were started route-only by MayRun for that proof; app/worker/rest serving tier was untouched"
	if !strings.Contains(note, wantNarrative) {
		t.Fatalf("post-delta refusal narrative = %q, want precise MayRun route-only wording %q", note, wantNarrative)
	}
}

func TestMayRunSchemaRefusalNarrativeDoesNotClaimFailedRouteStarted(t *testing.T) {
	note := mayRunSchemaRefusalNarrative("services held down: the database could not be started to verify source-version identity (synthetic route failure)")
	if !strings.Contains(note, "MayRun attempted route-only db+proxy startup but it did not complete") ||
		!strings.Contains(note, "app/worker/rest serving tier was untouched") {
		t.Fatalf("failed MayRun route narrative = %q, want truthful attempted-route wording", note)
	}
	if strings.Contains(note, "db+proxy were started") {
		t.Fatalf("failed MayRun route narrative falsely claims route startup succeeded: %q", note)
	}
}

func TestAstraReviewFlaglessParkMustRespectOperatorStartLock(t *testing.T) {
	git := newGitRepoFixture(t)
	sourceTag := git.oldSHA[:8]
	logPath := installParkedTargetDockerShim(t, git.newSHA[:8], nil, false)
	writeParkedSourceIdentityFlag(t, git.dir, git.newSHA, sourceTag)
	guard, err := AcquireOperatorStartGuard(git.dir, "operator:start:test")
	if err != nil {
		t.Fatalf("AcquireOperatorStartGuard: %v", err)
	}
	defer func() {
		if releaseErr := guard.Release(); releaseErr != nil {
			t.Errorf("release operator start guard: %v", releaseErr)
		}
	}()

	d := &Service{projDir: git.dir}
	note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
	if !strings.Contains(note, "another live actor holds the upgrade marker flock") || !strings.Contains(note, "no containers were started") {
		t.Fatalf("flock contention narrative = %q", note)
	}
	logBytes, readErr := os.ReadFile(logPath)
	if readErr != nil && !os.IsNotExist(readErr) {
		t.Fatal(readErr)
	}
	log := string(logBytes)
	if strings.Contains(log, "compose start") || strings.Contains(log, "compose up") {
		t.Fatalf("flagless park must not mutate containers while operator start owns the flock:\n%s", log)
	}
}

func TestEnsureParkedAtNewServingTierKeepsRunningHealthLegUntouched(t *testing.T) {
	git := newGitRepoFixture(t)
	logPath := installParkedTargetDockerShim(t, git.newSHA[:8], nil, false)

	d := &Service{projDir: git.dir}
	note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
	if note != "" {
		t.Fatalf("running target serving tier narrative = %q, want empty", note)
	}
	log := readParkedTargetDockerLog(t, logPath)
	if strings.Contains(log, "compose start") {
		t.Fatalf("health-leg park must not restart an already-running target serving tier:\n%s", log)
	}
	if strings.Contains(note, "services held down") {
		t.Fatalf("health-leg park must not acquire held-closed narrative: %q", note)
	}
}

func TestEnsureParkedAtNewServingTierStartFailureIsNarrativeOnly(t *testing.T) {
	git := newGitRepoFixture(t)
	logPath := installParkedTargetDockerShim(t, git.newSHA[:8], map[string]string{
		"app": "exited", "worker": "exited", "rest": "exited", "proxy": "running",
	}, true)

	d := &Service{projDir: git.dir}
	note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
	if !strings.Contains(note, "could not be started in place") || !strings.Contains(note, "synthetic target start failure") {
		t.Fatalf("failure narrative = %q, want the bounded start failure", note)
	}
	if !strings.Contains(note, "park remains landed") {
		t.Fatalf("failure narrative must preserve the durable park: %q", note)
	}
	log := readParkedTargetDockerLog(t, logPath)
	if !strings.Contains(log, "compose start app worker rest proxy\n") {
		t.Fatalf("failed operability attempt did not use compose start:\n%s", log)
	}
	if strings.Contains(log, "compose up") {
		t.Fatalf("failed operability attempt must never recreate containers:\n%s", log)
	}
}

func TestEnsureParkedAtNewServingTierUnknownStateStillAttemptsTargetStart(t *testing.T) {
	git := newGitRepoFixture(t)
	logPath := installParkedTargetDockerShim(t, git.newSHA[:8], map[string]string{"app": "mystery"}, false)

	d := &Service{projDir: git.dir}
	note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
	if !strings.Contains(note, "started in place for parked-box operability") {
		t.Fatalf("unknown-state narrative = %q, want the safe target start path", note)
	}
	log := readParkedTargetDockerLog(t, logPath)
	if !strings.Contains(log, "compose start app worker rest proxy\n") {
		t.Fatalf("unknown state must fail safe to the target start attempt:\n%s", log)
	}
}

func TestEnsureParkedAtNewServingTierLeavesUnprovedSourceContainersDown(t *testing.T) {
	git := newGitRepoFixture(t)
	logPath := installParkedTargetDockerShim(t, git.newSHA[:8], map[string]string{
		"app": "exited", "worker": "exited", "rest": "exited", "proxy": "running",
	}, false)
	t.Setenv("STATBUS_TEST_CONTAINER_TAG", git.oldSHA[:8])
	t.Setenv("STATBUS_TEST_APP_CONTAINER_ID", servingEraTestImageID('1'))
	t.Setenv("STATBUS_TEST_WORKER_CONTAINER_ID", servingEraTestImageID('2'))
	t.Setenv("STATBUS_TEST_REST_CONTAINER_ID", servingEraTestImageID('3'))
	t.Setenv("STATBUS_TEST_PROXY_CONTAINER_ID", servingEraTestImageID('4'))

	d := &Service{
		projDir: git.dir,
		parkEraVerdictForTest: func(context.Context, int) (bool, string) {
			return parkEraDecision(1, 1)
		},
	}
	note := d.ensureParkedAtNewServingTier(context.Background(), 1, git.newSHA, nil)
	if !strings.Contains(note, "source-era identities could not be proven") ||
		!strings.Contains(note, "neither the recovery marker nor the source-image carrier") ||
		!strings.Contains(note, "the park remains landed") {
		t.Fatalf("unproved source-era narrative = %q, want narrative-only refusal with landed park", note)
	}
	log := readParkedTargetDockerLog(t, logPath)
	if strings.Contains(log, "compose start") {
		t.Fatalf("unproved source-era containers must remain down:\n%s", log)
	}
}
