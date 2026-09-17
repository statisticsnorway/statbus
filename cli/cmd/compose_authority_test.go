package cmd

import (
	"context"
	"strings"
	"testing"
)

func TestCommandContextDirChecksFinalDynamicComposeArgv(t *testing.T) {
	verb := strings.Join([]string{"u", "p"}, "")
	args := []string{"compose", verb, "-d", "app"}
	if _, err := commandContextDir(context.Background(), t.TempDir(), "docker", args...); err == nil || !strings.Contains(err.Error(), "must be constructed with compose.Up") {
		t.Fatalf("cmd dynamic compose-up through generic entry = %v, want refusal", err)
	}
}
