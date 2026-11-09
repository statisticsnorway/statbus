package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Manual box, November 9 at 11:03 UTC: the operator ran the uninstaller a
// second time after a complete removal. ~/statbus, the unit file and every
// container were gone, yet it asked about users and credentials again and
// printed an empty removal plan. With nothing installed it says so, names what
// an earlier removal kept, and asks nothing.
func TestUninstallWithNothingInstalledSaysSoAndAsksNothing(t *testing.T) {
	home := t.TempDir()
	for path, body := range map[string]string{
		filepath.Join(home, "statbus.users.yml"):                             "- email: ada@example.org\n",
		filepath.Join(home, "statbus.env.credentials"):                       "GITHUB_TOKEN=kept\n",
		filepath.Join(home, "statbus.dbdumps", "un_20261109_105016.pg_dump"): "dump",
	} {
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	writeUninstallDockerMock(t, ensureBinDir(t, home))
	// Answers for the prompts a regression would ask, so it fails on the
	// asserted output instead of waiting at a prompt. A correct run asks nothing.
	out, err := runUninstallOnPTY(t, home, binPath(home), "\n\nDELETE\n")
	if err != nil {
		t.Fatalf("removal with nothing installed must succeed: %v\n%s", err, out)
	}
	if got := uninstallPrompts(out); len(got) != 0 {
		t.Fatalf("asked %q with nothing installed:\n%s", got, out)
	}
	text := strings.ReplaceAll(out, "\r", "")
	for _, want := range []string{
		"StatBus is not installed here: there is no " + filepath.Join(home, "statbus") + ", no upgrader service and no StatBus container.",
		"Kept from an earlier removal:",
		"  " + filepath.Join(home, "statbus.users.yml"),
		"  " + filepath.Join(home, "statbus.env.credentials"),
		"  " + filepath.Join(home, "statbus.dbdumps") + " (1 database backup)",
		"Nothing was removed.",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("output lacks %q:\n%s", want, text)
		}
	}
	for _, kept := range []string{"statbus.users.yml", "statbus.env.credentials", filepath.Join("statbus.dbdumps", "un_20261109_105016.pg_dump")} {
		if _, statErr := os.Stat(filepath.Join(home, kept)); statErr != nil {
			t.Errorf("%s was touched: %v", kept, statErr)
		}
	}
}

// The backup question names what is at stake: how many, their size and the
// newest backup's date. The default stays Yes (owner, November 9).
func TestUninstallBackupQuestionNamesSizeAndDate(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "dbdumps"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o700); err != nil {
		t.Fatal(err)
	}
	dump := filepath.Join(dir, "dbdumps", "un_20261109_105016.pg_dump")
	if err := os.WriteFile(dump, make([]byte, 2_655_953), 0o600); err != nil {
		t.Fatal(err)
	}
	when := time.Date(2026, 11, 9, 10, 50, 17, 0, time.UTC)
	if err := os.Chtimes(dump, when, when); err != nil {
		t.Fatal(err)
	}
	writeUninstallDockerMock(t, ensureBinDir(t, home))
	out, err := runUninstallOnPTY(t, home, binPath(home), "\n\n\nDELETE\n")
	if err != nil {
		t.Fatalf("interactive removal: %v\n%s", err, out)
	}
	want := "Keep the 1 database backup (2.5 MB, newest from 2026-11-09 10:50 UTC)? [Y/n]"
	if !strings.Contains(out, want) {
		t.Fatalf("backup question lacks size and date, want %q:\n%s", want, out)
	}
	if _, statErr := os.Stat(filepath.Join(home, "statbus.dbdumps", "un_20261109_105016.pg_dump")); statErr != nil {
		t.Fatalf("Enter (the default Yes) did not keep the backup: %v\n%s", statErr, out)
	}
}

// The last word of a removal is what it verified: the upgrader service is gone
// (no unit file, systemd reports it inactive), the checkout is gone, and what
// was kept is where. Linger stays on, since setup enabled it for the account.
func TestUninstallEndsWithAVerifiedSummary(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".users.yml"), []byte("- email: ada@example.org\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	unitDir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(unitDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(unitDir, "statbus-upgrader@.service"), []byte("[Unit]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	bin := ensureBinDir(t, home)
	writeUninstallDockerMock(t, bin)
	systemctl := "#!/bin/sh\ncase \"$*\" in\n  *is-active*) echo inactive ;;\nesac\nexit 0\n"
	if err := os.WriteFile(filepath.Join(bin, "systemctl"), []byte(systemctl), 0o700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+binPath(home), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	raw, err := cmd.CombinedOutput()
	out := string(raw)
	if err != nil {
		t.Fatalf("removal: %v\n%s", err, out)
	}
	at := strings.Index(out, "Removal complete")
	if at < 0 {
		t.Fatalf("no completion summary:\n%s", out)
	}
	summary := out[at:]
	for _, want := range []string{
		"Removal complete. Verified:",
		"  Upgrader service: removed (no unit file; systemd reports it inactive)",
		"  StatBus containers: none remain",
		"  Installation folder " + dir + ": removed",
		"  Kept: nothing",
		"  The account keeps its user services (linger), which setup enabled.",
	} {
		if !strings.Contains(summary, want) {
			t.Errorf("summary lacks %q:\n%s", want, out)
		}
	}
}
