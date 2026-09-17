package compose

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenericComposeCommandRejectsUpAtSubcommandPosition(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "direct", args: []string{"up", "-d", "app"}},
		{name: "after file", args: []string{"-f", "x.yml", "up", "-d"}},
		{name: "after equals global", args: []string{"--project-name=statbus", "up", "-d"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := CommandContext(context.Background(), t.TempDir(), tc.args...)
			if err == nil || !strings.Contains(err.Error(), "must be constructed with compose.Up") {
				t.Fatalf("generic compose command error = %v, want compose.Up refusal", err)
			}
		})
	}
}

func TestGenericComposeCommandParsesGlobalFlagValues(t *testing.T) {
	projDir := t.TempDir()
	cmd, err := CommandContext(context.Background(), projDir, "--project-name", "up", "ps")
	if err != nil {
		t.Fatalf("project name value up was misclassified as subcommand: %v", err)
	}
	wantArgs := []string{"docker", "compose", "--project-name", "up", "ps"}
	if strings.Join(cmd.Args, "\x00") != strings.Join(wantArgs, "\x00") {
		t.Fatalf("command args = %q, want %q", cmd.Args, wantArgs)
	}
	if cmd.Dir != filepath.Clean(projDir) {
		t.Fatalf("command dir = %q, want %q", cmd.Dir, filepath.Clean(projDir))
	}
}

func TestGenericComposeCommandRejectsUnknownGlobalFlag(t *testing.T) {
	_, err := CommandContext(context.Background(), t.TempDir(), "--future-flag", "value", "ps")
	if err == nil || !strings.Contains(err.Error(), "unrecognized docker compose global flag") {
		t.Fatalf("unknown global flag error = %v, want fail-closed refusal", err)
	}
}

func TestDockerCommandContextCannotHideComposeBehindDockerGlobalOptions(t *testing.T) {
	verb := strings.Join([]string{"u", "p"}, "")
	_, err := DockerCommandContext(context.Background(), t.TempDir(), "--context", "remote", "compose", verb, "-d", "app")
	if err == nil || !strings.Contains(err.Error(), "global options before compose are unsupported") {
		t.Fatalf("hidden compose argv = %v, want fail-closed refusal", err)
	}
}

func TestComposeSubcommandParserRecognizesDocumentedGlobalFlags(t *testing.T) {
	valueFlags := []string{"-f", "--file", "-p", "--project-name", "--profile", "--env-file", "--project-directory", "--ansi", "--parallel", "--progress"}
	for _, flag := range valueFlags {
		t.Run(flag+" separate", func(t *testing.T) {
			index, err := composeSubcommandIndex([]string{flag, "value", "ps"})
			if err != nil || index != 2 {
				t.Fatalf("separate value parse = index %d err %v, want 2 nil", index, err)
			}
		})
		t.Run(flag+" equals", func(t *testing.T) {
			index, err := composeSubcommandIndex([]string{flag + "=value", "ps"})
			if err != nil || index != 1 {
				t.Fatalf("equals value parse = index %d err %v, want 1 nil", index, err)
			}
		})
	}
	for _, flag := range []string{"--compatibility", "--dry-run"} {
		t.Run(flag, func(t *testing.T) {
			index, err := composeSubcommandIndex([]string{flag, "ps"})
			if err != nil || index != 1 {
				t.Fatalf("boolean parse = index %d err %v, want 1 nil", index, err)
			}
		})
	}
}

func TestUpInjectsSubcommandAfterGlobalOptions(t *testing.T) {
	projDir := t.TempDir()
	cmd, err := Up(context.Background(), projDir, "--profile", "all", "-d", "--no-build", "app")
	if err != nil {
		t.Fatal(err)
	}
	wantArgs := []string{"docker", "compose", "--profile", "all", "up", "-d", "--no-build", "app"}
	if strings.Join(cmd.Args, "\x00") != strings.Join(wantArgs, "\x00") {
		t.Fatalf("command args = %q, want %q", cmd.Args, wantArgs)
	}
}

func TestUpRejectsCallerSuppliedSubcommand(t *testing.T) {
	_, err := Up(context.Background(), t.TempDir(), "up", "-d", "app")
	if err == nil || !strings.Contains(err.Error(), "must omit") {
		t.Fatalf("caller-supplied up error = %v, want refusal", err)
	}
}
