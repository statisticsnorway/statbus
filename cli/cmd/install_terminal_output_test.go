package cmd

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
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

// TestInstallTerminalWriterShowsEveryInstallState runs the real
// logInstallState for every install.State (both live-holder forms included)
// and pipes its output through the operator terminal filter: every non-blank
// line must reach the terminal exactly once. The interrupted first-install
// line was filtered out, so rc.11's 5-install-interrupted-first-run could not
// see it (LXD run 36373249889). A new State or a new line in
// logInstallState is exercised automatically and cannot be hidden silently.
// The three NothingScheduled drift sub-lines depend on a live database and
// are checked as literals below, along with the two fixed transitions
// printed around logInstallState in runInstall.
func TestInstallTerminalWriterShowsEveryInstallState(t *testing.T) {
	started := time.Date(2026, 9, 28, 3, 44, 5, 0, time.UTC)
	cases := []struct {
		name   string
		state  install.State
		detail *install.Detail
	}{
		{"install holder with pid", install.StateLiveUpgrade, &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: upgrade.HolderInstall, StartedAt: started, PID: 4242}}},
		{"install holder without pid", install.StateLiveUpgrade, &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: upgrade.HolderInstall, StartedAt: started}}},
		{"service holder", install.StateLiveUpgrade, &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: upgrade.HolderService, StartedAt: started}}},
	}
	for s := install.StateFresh; s <= install.StateFreshDBIncomplete; s++ {
		if s == install.StateLiveUpgrade {
			continue
		}
		cases = append(cases, struct {
			name   string
			state  install.State
			detail *install.Detail
		}{s.String(), s, &install.Detail{}})
	}
	projDir := t.TempDir()
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := captureStdout(t, func() { logInstallState(projDir, c.state, c.detail) })
			var want strings.Builder
			for _, line := range strings.Split(out, "\n") {
				if strings.TrimSpace(line) != "" {
					want.WriteString(line + "\n")
				}
			}
			if want.Len() == 0 {
				t.Fatalf("state %s printed nothing", c.state)
			}
			if got := runTerminalFilter(t, out); got != want.String() {
				t.Fatalf("install-state lines hidden or duplicated:\n got:\n%s\nwant:\n%s", got, want.String())
			}
		})
	}
	literals := "  The database is up to date.\n  Database updates will be applied.\n  The database and installed program differ. Repair will reconcile them.\nRecovery finished. Checking the installation again.\nThe database could not be checked. Continuing with installation repair.\n"
	if got := runTerminalFilter(t, literals); got != literals {
		t.Fatalf("fixed state lines hidden or duplicated:\n got:\n%s\nwant:\n%s", got, literals)
	}
	// Only the exact holder grammar passes; appended or substituted text must not.
	for _, hostile := range []string{
		"an installation started at 2026-09-28T03:44:05Z (process 42) is still running. Wait for it to finish, then run the same install command again; token=secret",
		"an installation started at yesterday is still running. Wait for it to finish, then run the same install command again",
		"an installation started at 2026-09-28T03:44:05Z (process x) is still running. Wait for it to finish, then run the same install command again",
	} {
		if got := runTerminalFilter(t, hostile+"\n"); got != "" {
			t.Fatalf("non-grammar holder text reached the terminal: %q", got)
		}
	}
}

func runTerminalFilter(t *testing.T, input string) string {
	t.Helper()
	cmd := exec.Command("awk", "-f", "../../ops/install-terminal-output.awk")
	cmd.Stdin = strings.NewReader(input)
	got, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	return string(got)
}
