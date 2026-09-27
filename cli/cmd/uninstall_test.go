package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
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

func TestUninstallHeldFlockRefusesBeforeDocker(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus", "tmp")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(filepath.Join(dir, "upgrade-in-progress.json"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := f.Close(); err != nil {
			t.Error(err)
		}
	}()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := syscall.Flock(int(f.Fd()), syscall.LOCK_UN); err != nil {
			t.Error(err)
		}
	}()
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "mutex is held") || strings.Contains(string(out), "Step 2") {
		t.Fatalf("held flock: %v %s", err, out)
	}
}

func TestUninstallWholeTreePreflightRefusesBeforeDocker(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus", "other-root-owned-location")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0500); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := os.Chmod(dir, 0700); err != nil && !os.IsNotExist(err) {
			t.Error(err)
		}
	}()
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = rm ]; then echo deleted > \"$HOME/deleted\"; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	_, deletedErr := os.Stat(filepath.Join(home, "deleted"))
	if err == nil || !strings.Contains(string(out), "Whole-tree removal requires") && !strings.Contains(string(out), "non-writable") || !os.IsNotExist(deletedErr) {
		t.Fatalf("preflight: %v %s", err, out)
	}
}

func TestUninstallQuiescenceAndOrphanImage(t *testing.T) {
	script, _ := filepath.Abs("../../uninstall.sh")
	for _, active := range []bool{true, false} {
		home := t.TempDir()
		bin := filepath.Join(home, "bin")
		if err := os.Mkdir(bin, 0700); err != nil {
			t.Fatal(err)
		}
		docker := "#!/bin/sh\ncase \"$*\" in\n  'image ls'*) echo ghcr.io/statisticsnorway/statbus-app:sha-test;;\n  'image rm'*) echo removed > \"$HOME/image-removed\";;\nesac\n"
		if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
			t.Fatal(err)
		}
		state := "inactive"
		if active {
			state = "active"
		}
		unit := "#!/bin/sh\ncase \"$*\" in\n *is-active*) echo " + state + ";;\nesac\n"
		if err := os.WriteFile(filepath.Join(bin, "systemctl"), []byte(unit), 0700); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command("bash", script)
		cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
		out, err := cmd.CombinedOutput()
		_, removedErr := os.Stat(filepath.Join(home, "image-removed"))
		if active {
			if err == nil || !strings.Contains(string(out), "not inactive") || !os.IsNotExist(removedErr) {
				t.Fatalf("active unit: %v %s", err, out)
			}
		} else if err != nil || removedErr != nil {
			t.Fatalf("orphan image: %v %s %v", err, out, removedErr)
		}
	}
}
