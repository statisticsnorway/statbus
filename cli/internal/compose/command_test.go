package compose

import (
	"context"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestDockerComposeCommandChecksFinalDynamicArgvForUpCapability(t *testing.T) {
	verb := strings.Join([]string{"u", "p"}, "")
	args := []string{verb, "-d", "app"}
	if _, err := dockerComposeCommand(context.Background(), t.TempDir(), nil, args...); err == nil || !strings.Contains(err.Error(), "requires an explicit capability") {
		t.Fatalf("dynamic compose-up without capability = %v, want refusal", err)
	}

	projDir := t.TempDir()
	cmd, err := dockerComposeCommand(context.Background(), projDir, MintUpCapability(), args...)
	if err != nil {
		t.Fatalf("capability-bearing compose-up refused: %v", err)
	}
	wantArgs := []string{"docker", "compose", "up", "-d", "app"}
	if !reflect.DeepEqual(cmd.Args, wantArgs) {
		t.Fatalf("command args = %v, want %v", cmd.Args, wantArgs)
	}
	if cmd.Dir != filepath.Clean(projDir) {
		t.Fatalf("command dir = %q, want %q", cmd.Dir, filepath.Clean(projDir))
	}
}
