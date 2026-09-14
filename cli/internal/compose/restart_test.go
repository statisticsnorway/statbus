package compose

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Execute the production command builder against an inert command fixture.
// This checks argv and failure propagation, not Docker/container behavior.
func TestRestartAndWaitCommandContract(t *testing.T) {
	dir := t.TempDir()
	trace := filepath.Join(dir, "trace")
	script := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_RESTART_TRACE"
case "$*" in *" down "*) exit "${STATBUS_RESTART_STOP_EXIT:-0}";; esac
exit 0
`
	if err := os.WriteFile(filepath.Join(dir, "docker"), []byte(script), 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_RESTART_TRACE", trace)
	for _, profile := range []string{"all", "all_except_app", "app"} {
		if err := os.WriteFile(trace, nil, 0600); err != nil {
			t.Fatal(err)
		}
		if err := RestartAndWait(profile, false); err != nil {
			t.Fatal(err)
		}
		data, err := os.ReadFile(trace)
		if err != nil {
			t.Fatal(err)
		}
		prefix := "compose --profile " + profile
		suffix := ""
		if profile == "app" {
			prefix = "compose"
			suffix = " app"
		}
		want := prefix + " down --remove-orphans" + suffix + "\n" + prefix + " up -d --wait --wait-timeout 120" + suffix + "\n"
		if string(data) != want {
			t.Fatalf("argv %q want %q", data, want)
		}
	}
	t.Setenv("STATBUS_RESTART_STOP_EXIT", "9")
	if err := os.WriteFile(trace, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := RestartAndWait("all", false); err == nil {
		t.Fatal("stop failure hidden")
	}
	data, _ := os.ReadFile(trace)
	if strings.Contains(string(data), " up ") {
		t.Fatal("start after failed stop")
	}
}
