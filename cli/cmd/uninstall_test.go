package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestUninstallScriptSelectionsAndRerun(t *testing.T) {
	script, err := filepath.Abs("../../uninstall.sh")
	if err != nil {
		t.Fatal(err)
	}
	run := func(home, confirmation string, input string) (string, error) {
		t.Helper()
		command := exec.Command("bash", script)
		command.Env = append(os.Environ(), "HOME="+home, "STATBUS_UNINSTALL_CONFIRM="+confirmation)
		command.Stdin = strings.NewReader(input)
		output, err := command.CombinedOutput()
		return string(output), err
	}
	home := t.TempDir()
	if output, err := run(home, "", ""); err == nil || !strings.Contains(output, "yes-delete-everything") {
		t.Fatalf("missing confirmation: %v %s", err, output)
	}
	// Missing installation is safe to remove repeatedly on a machine without Docker.
	for i := 0; i < 2; i++ {
		output, err := run(home, "yes-delete-everything", "")
		if err != nil {
			t.Fatalf("rerun %d: %v %s", i, err, output)
		}
	}
	// A half-install with no containers removes its checkout, credentials and dumps.
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte("#!/bin/sh\nshift\nexec \"$@\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "dbdumps"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.credentials"), []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	command := exec.Command("bash", script)
	command.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("delete selection: %v %s", err, output)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("checkout survived deletion: %v", err)
	}
}
