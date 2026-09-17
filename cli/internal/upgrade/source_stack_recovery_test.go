package upgrade

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStartSourceApplicationStackExecutesComposeAndHealthGate(t *testing.T) {
	var rpcHits int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ready" {
			w.WriteHeader(http.StatusOK)
			return
		}
		rpcHits++
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)

	d := &Service{projDir: t.TempDir(), cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	if err := d.startSourceApplicationStack(context.Background(), nil); err != nil {
		t.Fatalf("startSourceApplicationStack: %v", err)
	}
	if rpcHits != 1 {
		t.Fatalf("health gate hits = %d, want 1", rpcHits)
	}
	logBytes, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(logBytes), "compose up -d --no-build app worker rest proxy\n") {
		t.Fatalf("source application stack was not explicitly converged:\n%s", logBytes)
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
