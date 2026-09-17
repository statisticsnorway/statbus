package cmd

import (
	"context"
	"reflect"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

func TestCommandContextDirChecksFinalDynamicComposeArgv(t *testing.T) {
	verb := strings.Join([]string{"u", "p"}, "")
	args := []string{"compose", verb, "-d", "app"}
	if _, err := commandContextDir(context.Background(), t.TempDir(), nil, "docker", args...); err == nil || !strings.Contains(err.Error(), "requires an explicit capability") {
		t.Fatalf("cmd dynamic compose-up without capability = %v, want refusal", err)
	}

	cmd, err := commandContextDir(context.Background(), t.TempDir(), compose.MintUpCapability(), "docker", args...)
	if err != nil {
		t.Fatalf("cmd capability-bearing compose-up refused: %v", err)
	}
	want := []string{"docker", "compose", "up", "-d", "app"}
	if !reflect.DeepEqual(cmd.Args, want) {
		t.Fatalf("cmd args = %v, want %v", cmd.Args, want)
	}
}
