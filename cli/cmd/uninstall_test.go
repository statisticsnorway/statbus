package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestUninstallNestedMountRefusesBeforeTeardown(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	mountpoint := filepath.Join(dir, "caddy", "data")
	external := filepath.Join(home, "external")
	for _, path := range []string{mountpoint, external} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(external, "sentinel"), []byte("untouched"), 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte("#!/bin/sh\nprintf '%s\\n' \"$HOME/statbus/caddy/data\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\necho called >> \"$HOME/teardown\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), mountpoint) || strings.Contains(string(out), "Step 2") {
		t.Fatalf("nested mount refusal: %v %s", err, out)
	}
	if _, err := os.Stat(filepath.Join(home, "teardown")); !os.IsNotExist(err) {
		t.Fatalf("Docker called before mount refusal: %v", err)
	}
	if data, err := os.ReadFile(filepath.Join(external, "sentinel")); err != nil || string(data) != "untouched" {
		t.Fatalf("external sentinel: %v %s", err, data)
	}
}

func TestUninstallSymlinkedTmpRefusesBeforeExternalWrite(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	external := filepath.Join(home, "external")
	for _, path := range []string{dir, external} {
		if err := os.Mkdir(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(external, filepath.Join(dir, "tmp")); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\necho called >> \"$HOME/teardown\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "symlink") || strings.Contains(string(out), "Step 2") {
		t.Fatalf("symlinked tmp refusal: %v %s", err, out)
	}
	entries, err := os.ReadDir(external)
	if err != nil || len(entries) != 0 {
		t.Fatalf("external directory changed: %v %v", err, entries)
	}
	if _, err := os.Stat(filepath.Join(home, "teardown")); !os.IsNotExist(err) {
		t.Fatalf("Docker called before tmp refusal: %v", err)
	}
}

func TestUninstallSymlinkedInstallLockRefusesBeforeExternalWrite(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus", "tmp")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	external := filepath.Join(home, "external-lock")
	if err := os.Symlink(external, filepath.Join(dir, "upgrade-in-progress.json")); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "symlink") || strings.Contains(string(out), "Step 2") {
		t.Fatalf("symlinked install lock refusal: %v %s", err, out)
	}
	if _, err := os.Stat(external); !os.IsNotExist(err) {
		t.Fatalf("external lock file created: %v", err)
	}
}

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
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = run ]; then exit 1; fi\nif [ \"$1\" = rm ]; then echo deleted > \"$HOME/deleted\"; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	_, deletedErr := os.Stat(filepath.Join(home, "deleted"))
	if err == nil || !strings.Contains(string(out), "Docker cannot remove checkout files") || !os.IsNotExist(deletedErr) || strings.Contains(string(out), "Step 2") {
		t.Fatalf("preflight: %v %s", err, out)
	}
}

func TestUninstallNoSudoDockerRemovesUnwritableTree(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	owned := filepath.Join(dir, "caddy", "data with spaces")
	if err := os.MkdirAll(owned, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(owned, "container-file"), []byte("secret"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(owned, 0500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(owned, 0700) })
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte("#!/bin/sh\nexit 1\n"), 0700); err != nil {
		t.Fatal(err)
	}
	// Simulate Docker's root bind mount: check that the script passes the exact
	// mount and top-level basename, without breaking paths containing spaces.
	docker := `#!/bin/sh
case "$*" in
  'image ls'*) echo ghcr.io/statisticsnorway/statbus-db:sha-test; exit 0;;
esac
if [ "$1" = run ]; then
  [ ! -e "$HOME/image-removed" ] || exit 1
  printf '<%s>\n' "$@" >> "$HOME/docker-argv"
  case "$*" in
    *uninstall-preflight*) exit 0;;
    *' caddy') chmod -R u+w "$HOME/statbus/caddy"; rm -rf -- "$HOME/statbus/caddy";;
    *'/target/tmp'*) rm -rf -- "$HOME/statbus/tmp";;
    *) exit 1;;
  esac
fi
if [ "$1" = image ] && [ "$2" = rm ]; then touch "$HOME/image-removed"; fi
`
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("no-sudo Docker removal: %v %s", err, out)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("checkout survived: %v %s", err, out)
	}
	argv, err := os.ReadFile(filepath.Join(home, "docker-argv"))
	if err != nil || !strings.Contains(string(argv), "<type=bind,src="+dir+",dst=/target>") || !strings.Contains(string(argv), "<--user>") || !strings.Contains(string(argv), "<0:0>") || !strings.Contains(string(argv), "<caddy>") {
		t.Fatalf("Docker bind/paths: %v %s", err, argv)
	}
	if _, err := os.Stat(filepath.Join(home, "image-removed")); err != nil {
		t.Fatalf("DB image not removed after cleanup: %v", err)
	}
}

func TestUninstallDockerPullsAndRemovesHelperOnPartialInstall(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	owned := filepath.Join(dir, "caddy")
	if err := os.MkdirAll(owned, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(owned, 0500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(owned, 0700) })
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte("#!/bin/sh\nexit 1\n"), 0700); err != nil {
		t.Fatal(err)
	}
	docker := `#!/bin/sh
case "$*" in
  'image inspect alpine:3.20') exit 1;;
  'pull alpine:3.20') touch "$HOME/pulled";;
  'image rm alpine:3.20') touch "$HOME/helper-removed";;
  *uninstall-preflight*) [ -e "$HOME/pulled" ] || exit 1;;
  *' caddy') chmod 0700 "$HOME/statbus/caddy"; rm -rf -- "$HOME/statbus/caddy";;
  *'/target/tmp'*) chmod 0700 "$HOME/statbus"; rm -rf -- "$HOME/statbus/tmp";;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("partial-install fallback: %v %s", err, out)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("checkout survived: %v", err)
	}
	if _, err := os.Stat(filepath.Join(home, "helper-removed")); err != nil {
		t.Fatalf("pulled helper not removed: %v", err)
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
