//go:build livedb

package upgrade

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dbroles"
)

const verifierDockerArgv = "compose exec -T db psql -X -q -A -t -F | -v ON_ERROR_STOP=1 -U postgres -d postgres"

// checkVerifierDockerCall requires one command and the entire, unmodified SQL stdin.
func checkVerifierDockerCall(projDir, dockerLog, stdinLog string) error {
	target, err := dbroles.LoadTarget(projDir)
	if err != nil {
		return err
	}
	calls, err := os.ReadFile(dockerLog)
	if err != nil {
		return err
	}
	stdin, err := os.ReadFile(stdinLog)
	if err != nil {
		return err
	}
	if !bytes.Equal(calls, []byte(verifierDockerArgv+"\n")) || !bytes.Equal(stdin, []byte(dbroles.VerifierQuery(target))) {
		return fmt.Errorf("unexpected Docker command or SQL stdin: argv=%q stdin=%q", calls, stdin)
	}
	return nil
}

// proveWriteRejected sends an appended write through the very same PATH shim.
// It must fail the assertion even though its Docker argv is the permitted probe.
func proveWriteRejected(t *testing.T, projDir, dockerLog, stdinLog, shimDir string) {
	t.Helper()
	target, err := dbroles.LoadTarget(projDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dockerLog, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stdinLog, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(filepath.Join(shimDir, "docker"), strings.Fields(verifierDockerArgv)...)
	cmd.Stdin = strings.NewReader(dbroles.VerifierQuery(target) + "ALTER ROLE postgres LOGIN;\n")
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("negative shim invocation: %v: %s", err, output)
	}
	if err := checkVerifierDockerCall(projDir, dockerLog, stdinLog); err == nil {
		t.Fatal("appended ALTER ROLE passed read-only probe assertion")
	} else {
		t.Logf("negative write payload rejected: %v", err)
	}
}
