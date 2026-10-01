package upgrade

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func testInstallHeldBootWaitOptions(log *bytes.Buffer, notifications *atomic.Int32) installHeldBootWaitOptions {
	return installHeldBootWaitOptions{
		limit:    40 * time.Millisecond,
		poll:     2 * time.Millisecond,
		watchdog: 5 * time.Millisecond,
		logf: func(format string, args ...any) {
			_, _ = fmt.Fprintf(log, format, args...)
		},
		notify: func(state string) {
			if state == "WATCHDOG=1" {
				notifications.Add(1)
			}
		},
	}
}

func acquireTestInstallFlock(t *testing.T) (string, *FlagLock) {
	return acquireTestInstallFlockWithTrigger(t, "install")
}

func acquireTestInstallFlockWithTrigger(t *testing.T, trigger string) (string, *FlagLock) {
	t.Helper()
	dir := t.TempDir()
	owner, err := acquireFreshFlock(dir, UpgradeFlag{
		Holder:    HolderInstall,
		Trigger:   trigger,
		StartedAt: time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC),
		PID:       os.Getpid(),
	})
	if err != nil {
		t.Fatal(err)
	}
	return dir, owner
}

func TestBootRestartTriggeredHeldFlockDoesNotDefer(t *testing.T) {
	dir, owner := acquireTestInstallFlockWithTrigger(t, "restart")
	defer owner.Close()

	var log bytes.Buffer
	var notifications atomic.Int32
	flag, err := (&Service{projDir: dir}).waitForInstallHolderBeforeBootWithOptions(
		context.Background(), testInstallHeldBootWaitOptions(&log, &notifications),
	)
	if err != nil {
		t.Fatalf("restart-triggered hold deferred daemon boot: %v", err)
	}
	if flag == nil || flag.Trigger != "restart" {
		t.Fatalf("restart marker = %+v, want preserved restart trigger", flag)
	}
	if log.Len() != 0 || notifications.Load() != 0 {
		t.Fatalf("restart-triggered hold unexpectedly waited: log=%q notifications=%d", log.String(), notifications.Load())
	}
}

func TestBootLegacyEmptyTriggerHeldFlockDoesNotDeferBecauseNoInstallWriterOmittedTrigger(t *testing.T) {
	dir, owner := acquireTestInstallFlockWithTrigger(t, "")
	defer owner.Close()

	var log bytes.Buffer
	var notifications atomic.Int32
	flag, err := (&Service{projDir: dir}).waitForInstallHolderBeforeBootWithOptions(
		context.Background(), testInstallHeldBootWaitOptions(&log, &notifications),
	)
	if err != nil {
		t.Fatalf("empty-trigger hold deferred daemon boot: %v", err)
	}
	if flag == nil || flag.Trigger != "" {
		t.Fatalf("empty-trigger marker = %+v, want preserved empty trigger", flag)
	}
	if log.Len() != 0 || notifications.Load() != 0 {
		t.Fatalf("empty-trigger hold unexpectedly waited: log=%q notifications=%d", log.String(), notifications.Load())
	}
}

func TestBootInstallHeldLiveFlockExpiresWithWatchdogAndOneHolderLog(t *testing.T) {
	dir, owner := acquireTestInstallFlock(t)
	defer owner.Close()

	var log bytes.Buffer
	var notifications atomic.Int32
	flag, err := (&Service{projDir: dir}).waitForInstallHolderBeforeBootWithOptions(
		context.Background(), testInstallHeldBootWaitOptions(&log, &notifications),
	)
	if !errors.Is(err, errInstallHeldBootWaitExpired) {
		t.Fatalf("live install-holder boot gate error = %v, want expiry sentinel", err)
	}
	if flag != nil {
		t.Fatalf("expired live install-holder gate returned actionable flag: %+v", flag)
	}
	if got := notifications.Load(); got < 1 {
		t.Fatalf("watchdog notifications = %d, want at least one while flock remained held", got)
	}
	if got := strings.Count(log.String(), "Upgrade daemon boot deferred:"); got != 1 {
		t.Fatalf("holder-identifying log count = %d, want exactly one; log=%q", got, log.String())
	}
	if !strings.Contains(log.String(), "an installation started at 2026-10-01T12:00:00Z") ||
		!strings.Contains(log.String(), fmt.Sprintf("process %d", os.Getpid())) {
		t.Fatalf("boot defer log does not identify holder: %q", log.String())
	}
}

func TestBootInstallHeldFlockReleaseAllowsContinuation(t *testing.T) {
	dir, owner := acquireTestInstallFlock(t)
	var log bytes.Buffer
	var notifications atomic.Int32
	opts := testInstallHeldBootWaitOptions(&log, &notifications)
	opts.limit = 250 * time.Millisecond

	released := make(chan struct{})
	go func() {
		time.Sleep(15 * time.Millisecond)
		owner.Close()
		close(released)
	}()

	flag, err := (&Service{projDir: dir}).waitForInstallHolderBeforeBootWithOptions(context.Background(), opts)
	<-released
	if err != nil {
		t.Fatalf("gate did not continue after live flock release: %v", err)
	}
	if flag == nil || flag.Holder != HolderInstall {
		t.Fatalf("released stale marker = %+v, want preserved install metadata", flag)
	}
	if got := strings.Count(log.String(), "Upgrade daemon boot deferred:"); got != 1 {
		t.Fatalf("release-path holder log count = %d, want exactly one", got)
	}
}

func TestBootStaleInstallFlagWithoutFlockAllowsNormalBoot(t *testing.T) {
	dir, owner := acquireTestInstallFlock(t)
	owner.Close()

	var log bytes.Buffer
	var notifications atomic.Int32
	flag, err := (&Service{projDir: dir}).waitForInstallHolderBeforeBootWithOptions(
		context.Background(), testInstallHeldBootWaitOptions(&log, &notifications),
	)
	if err != nil {
		t.Fatalf("stale install marker blocked boot: %v", err)
	}
	if flag == nil || flag.Holder != HolderInstall {
		t.Fatalf("stale marker = %+v, want preserved install metadata", flag)
	}
	if log.Len() != 0 || notifications.Load() != 0 {
		t.Fatalf("stale marker unexpectedly waited: log=%q notifications=%d", log.String(), notifications.Load())
	}
}

func TestInstallHeldBootExpiryMapsToRestartPreventedExit75(t *testing.T) {
	code, ok := installHeldBootWaitExitCode(fmt.Errorf("wrapped: %w", errInstallHeldBootWaitExpired))
	if !ok || code != 75 {
		t.Fatalf("expiry mapping = (%d, %t), want (75, true)", code, ok)
	}
	if exitInstallHeldBootWait != 75 {
		t.Fatalf("exitInstallHeldBootWait = %d, want 75", exitInstallHeldBootWait)
	}
	if code, ok := installHeldBootWaitExitCode(context.Canceled); ok || code != 0 {
		t.Fatalf("non-expiry mapping = (%d, %t), want (0, false)", code, ok)
	}

	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")
	mapping := strings.Index(run, "installHeldBootWaitExitCode(err)")
	exit := strings.Index(run, "os.Exit(exitCode)")
	if mapping < 0 || exit < mapping {
		t.Fatalf("Run must map the expiry sentinel and take os.Exit(exitCode): mapping=%d exit=%d", mapping, exit)
	}
}

func TestUpgradeUnitPreventsExit75RestartAndLeavesStartupBudget(t *testing.T) {
	unit, err := os.ReadFile(thisRepoFile(t, "ops/statbus-upgrade.service"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(unit)
	prevent := regexp.MustCompile(`(?m)^RestartPreventExitStatus=(.*)$`).FindStringSubmatch(text)
	if len(prevent) != 2 || !strings.Contains(" "+prevent[1]+" ", " 75 ") {
		t.Fatalf("RestartPreventExitStatus must contain 75, got %q", prevent)
	}
	timeoutMatch := regexp.MustCompile(`(?m)^TimeoutStartSec=([0-9]+)$`).FindStringSubmatch(text)
	if len(timeoutMatch) != 2 {
		t.Fatal("unit must declare numeric TimeoutStartSec")
	}
	timeoutSeconds, err := strconv.Atoi(timeoutMatch[1])
	if err != nil {
		t.Fatal(err)
	}
	startupTimeout := time.Duration(timeoutSeconds) * time.Second
	const requiredStartupRemainder = 60 * time.Second
	if installHeldBootWaitLimit+requiredStartupRemainder > startupTimeout {
		t.Fatalf("install-held wait %s leaves less than %s of TimeoutStartSec=%s for normal boot",
			installHeldBootWaitLimit, requiredStartupRemainder, startupTimeout)
	}
}

func TestRunBootInterlockPrecedesConfigAndDatabaseActions(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	run := extractFuncBody(t, string(src), "func (d *Service) Run(")
	gate := strings.Index(run, "d.waitForInstallHolderBeforeBoot(ctx)")
	config := strings.Index(run, `runCommandOutput(d.projDir, "./sb", "config", "generate"`)
	compose := strings.Index(run, "ensureDatabaseForBoot(ctx, bootFlag")
	if gate < 0 || config < 0 || compose < 0 || gate > config || gate > compose {
		t.Fatalf("boot interlock must precede config and database actions: gate=%d config=%d db=%d", gate, config, compose)
	}
}

func TestBootDatabaseStrategyStartsExistingOutsideForwardRecovery(t *testing.T) {
	var recreateCalls, startCalls int
	err := ensureDatabaseForBoot(context.Background(), nil,
		func(context.Context) error { recreateCalls++; return nil },
		func(context.Context) error { startCalls++; return nil },
	)
	if err != nil {
		t.Fatal(err)
	}
	if recreateCalls != 0 || startCalls != 1 {
		t.Fatalf("ordinary boot calls recreate=%d start-existing=%d, want 0/1", recreateCalls, startCalls)
	}
}

func TestBootDatabaseStrategyRecreatesForPostSwapRecovery(t *testing.T) {
	flag := &UpgradeFlag{Holder: HolderService, Phase: PhaseNewSbSwapped, CommitSHA: "abc123"}
	var recreateCalls, startCalls int
	err := ensureDatabaseForBoot(context.Background(), flag,
		func(context.Context) error { recreateCalls++; return nil },
		func(context.Context) error { startCalls++; return nil },
	)
	if err != nil {
		t.Fatal(err)
	}
	if recreateCalls != 1 || startCalls != 0 {
		t.Fatalf("post-swap recovery calls recreate=%d start-existing=%d, want 1/0", recreateCalls, startCalls)
	}
}
