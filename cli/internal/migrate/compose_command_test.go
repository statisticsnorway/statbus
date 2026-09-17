package migrate

import (
	"context"
	"strings"
	"testing"
)

func TestCommandContextRejectsDynamicComposeUp(t *testing.T) {
	verb := "u" + "p"
	_, err := CommandContext(context.Background(), t.TempDir(), "docker", "compose", verb, "-d", "db")
	if err == nil || !strings.Contains(err.Error(), "requires an explicit capability") {
		t.Fatalf("dynamic docker compose up = %v, want explicit capability refusal", err)
	}
}

func TestCommandContextRoutesComposeThroughSharedWrapper(t *testing.T) {
	projDir := t.TempDir()
	cmd, err := CommandContext(context.Background(), projDir, "docker", "compose", "exec", "-T", "db", "psql")
	if err != nil {
		t.Fatal(err)
	}
	if cmd.Dir != projDir {
		t.Fatalf("command directory = %q, want %q", cmd.Dir, projDir)
	}
	want := []string{"docker", "compose", "exec", "-T", "db", "psql"}
	if strings.Join(cmd.Args, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("command argv = %q, want %q", cmd.Args, want)
	}
}
