package upgrade

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"
)

func TestBootInstallHeldLiveFlockStopsBeforeMutatingActions(t *testing.T) {
	dir := t.TempDir()
	owner, err := acquireFreshFlock(dir, UpgradeFlag{
		Holder:    HolderInstall,
		Trigger:   "install",
		StartedAt: time.Now(),
		PID:       os.Getpid(),
	})
	if err != nil {
		t.Fatal(err)
	}
	defer owner.Close()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	flag, err := (&Service{projDir: dir}).waitForInstallHolderBeforeBoot(ctx)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("live install-holder boot gate error = %v, want context cancellation", err)
	}
	if flag != nil {
		t.Fatalf("live install-holder boot gate returned actionable flag: %+v", flag)
	}
	// The production call site invokes config generation and database bring-up
	// only after this gate returns successfully. Cancellation while the real flock
	// is held proves neither action becomes reachable.
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
