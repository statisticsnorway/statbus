package cmd

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"testing"
)

func TestInstallTerminalWriterReceivesEveryStepLine(t *testing.T) {
	var input strings.Builder
	var want strings.Builder
	source, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	stepTable := strings.SplitN(string(source), "steps := []step{", 2)
	if len(stepTable) != 2 {
		t.Fatal("step table not found")
	}
	stepTable = strings.SplitN(stepTable[1], "total := len(steps)", 2)
	names := regexp.MustCompile(`(?m)^\s*\{"([A-Za-z +]+)",`).FindAllStringSubmatch(stepTable[0], -1)
	if len(names) != 17 {
		t.Fatalf("expected all 17 step names, found %d", len(names))
	}
	for i, match := range names {
		name := match[1]
		for _, status := range []string{"OK", "RUNNING", "DONE", "FAILED: This part of installation could not finish."} {
			line := fmt.Sprintf("[%d/17] %-20s %s\n", i+1, name, status)
			input.WriteString(line)
			want.WriteString(line)
		}
	}
	for _, status := range []string{"FAILED — falling back to full migrations", "no seed image — full migrations will run"} {
		line := fmt.Sprintf("[13/17] %-20s %s\n", "Seed", status)
		input.WriteString(line)
		want.WriteString(line)
	}
	input.WriteString("  Starting every service: database, web server, API, web app, background worker ...\n")
	want.WriteString("  Starting every service: database, web server, API, web app, background worker ...\n")
	for _, line := range []string{
		"  the database (db): running (healthy)",
		"  the web server (proxy): restarting",
		"  the API service (rest): exited",
		"  the web app (app): stopped",
		"  the background worker (worker): absent",
		"  the automatic update service (upgrade): inactive",
		"INSTALL_SERVICE: the web app (app) has stopped; its recent logs are in the install log.",
	} {
		input.WriteString(line + "\n")
		want.WriteString(strings.TrimPrefix(line, "INSTALL_SERVICE: ") + "\n")
	}
	input.WriteString("INSTALL_LOG_SERVICE: app: stopped\n  Last lines from the web app (app):\n    secret docker log\n")
	input.WriteString("  Container proxy Recreate\n2026/09/24 INVARIANT state: pgx\nINSTALL_CAUSE: secret\n")
	cmd := exec.Command("awk", "-f", "../../ops/install-terminal-output.awk")
	cmd.Stdin = strings.NewReader(input.String())
	got, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, []byte(want.String())) {
		t.Fatalf("terminal writer:\n%s\nwant:\n%s", got, want.String())
	}
}

// TestInstallTerminalWriterShowsEveryInstallState: every sentence
// logInstallState prints must reach the operator's terminal. The interrupted
// first-install line ("The database exists but setup stopped ...") was
// filtered out, so rc.10/rc.11's 5-install-interrupted-first-run could not see
// it on either fleet. The sentences are read from install.go itself so a new
// state line cannot be added without the filter noticing.
func TestInstallTerminalWriterShowsEveryInstallState(t *testing.T) {
	source, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	body := strings.SplitN(string(source), "func logInstallState(", 2)
	if len(body) != 2 {
		t.Fatal("logInstallState not found")
	}
	body = strings.SplitN(body[1], "\n}\n", 2)
	matches := regexp.MustCompile(`fmt\.Println\("([^"]+)"\)`).FindAllStringSubmatch(body[0], -1)
	if len(matches) < 10 {
		t.Fatalf("expected every install-state sentence, found %d", len(matches))
	}
	var input strings.Builder
	for _, m := range matches {
		input.WriteString(m[1] + "\n")
	}
	cmd := exec.Command("awk", "-f", "../../ops/install-terminal-output.awk")
	cmd.Stdin = strings.NewReader(input.String())
	got, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != input.String() {
		t.Fatalf("install-state lines hidden from the operator:\n got:\n%s\nwant:\n%s", got, input.String())
	}
}
