package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
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

func TestUninstallMountBoundaryRefusals(t *testing.T) {
	for _, tc := range []struct {
		name, target string
		inaccessible bool
	}{
		{"findmnt-hex-spaces", "$HOME/statbus/caddy\\x20data", false},
		{"mountinfo-octal-spaces", "$HOME/statbus/caddy\\040data", false},
		{"checkout-root", "$HOME/statbus", false},
		{"unresolvable-missing", "$HOME/statbus/caddy data/missing", false},
		{"unresolvable-permission", "$HOME/statbus/caddy data/hidden", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if tc.inaccessible && os.Geteuid() == 0 {
				t.Skip("root can resolve paths beneath chmod 000")
			}
			parent := t.TempDir()
			home := filepath.Join(parent, "home with space")
			mount := filepath.Join(home, "statbus", "caddy data")
			external := filepath.Join(parent, "external")
			for _, path := range []string{mount, external} {
				if err := os.MkdirAll(path, 0700); err != nil {
					t.Fatal(err)
				}
			}
			if err := os.WriteFile(filepath.Join(external, "sentinel"), []byte("untouched"), 0600); err != nil {
				t.Fatal(err)
			}
			if tc.inaccessible {
				if err := os.Mkdir(filepath.Join(mount, "hidden"), 0700); err != nil {
					t.Fatal(err)
				}
				if err := os.Chmod(mount, 0000); err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = os.Chmod(mount, 0700) })
			}
			bin := filepath.Join(home, "bin")
			if err := os.Mkdir(bin, 0700); err != nil {
				t.Fatal(err)
			}
			encodedHome := home
			if strings.Contains(tc.name, "hex") {
				encodedHome = strings.ReplaceAll(home, " ", "\\x20")
			}
			if strings.Contains(tc.name, "octal") {
				encodedHome = strings.ReplaceAll(home, " ", "\\040")
			}
			findmnt := "#!/bin/sh\nprintf '%s\\n' '" + strings.ReplaceAll(tc.target, "$HOME", encodedHome) + "'\n"
			if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte(findmnt), 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\necho called >> \"$HOME/teardown\"\n"), 0700); err != nil {
				t.Fatal(err)
			}
			script, _ := filepath.Abs("../../uninstall.sh")
			cmd := exec.Command("bash", script)
			cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
			out, err := cmd.CombinedOutput()
			if err == nil || !strings.Contains(string(out), "refusing removal") && !strings.Contains(string(out), "Mountpoint") || strings.Contains(string(out), "Step 2") {
				t.Fatalf("mount refusal: %v %s", err, out)
			}
			if _, err := os.Stat(filepath.Join(home, "teardown")); !os.IsNotExist(err) {
				t.Fatalf("Docker called: %v", err)
			}
			if data, err := os.ReadFile(filepath.Join(external, "sentinel")); err != nil || string(data) != "untouched" {
				t.Fatalf("sentinel: %v %s", err, data)
			}
		})
	}
}

func TestUninstallUnrelatedInaccessibleMountReachesDocker(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can resolve paths beneath chmod 000")
	}
	parent := t.TempDir()
	home := filepath.Join(parent, "home")
	private := filepath.Join(parent, "private")
	for _, path := range []string{filepath.Join(home, "statbus"), filepath.Join(private, "hidden")} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Chmod(private, 0000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(private, 0700) })
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	findmnt := "#!/bin/sh\nprintf '%s\\n' '" + filepath.Join(private, "hidden") + "'\n"
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte(findmnt), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\necho called >> \"$HOME/docker-called\"\nif [ \"$1\" = version ]; then echo 24.0.9; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "Upgrade Docker") || strings.Contains(string(out), "Cannot resolve mount target") {
		t.Fatalf("unrelated mount blocked Docker discovery: %v %s", err, out)
	}
	if _, err := os.Stat(filepath.Join(home, "docker-called")); err != nil {
		t.Fatalf("Docker not reached: %v %s", err, out)
	}
}

func TestUninstallMountSymlinkAncestorStillRefuses(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus", "caddy")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(home, "outside-alias")
	if err := os.Symlink(dir, alias); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte("#!/bin/sh\nprintf '%s\\n' '"+alias+"'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\necho called >> \"$HOME/docker-called\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "Mountpoint") {
		t.Fatalf("symlink ancestor mount accepted: %v %s", err, out)
	}
	if _, err := os.Stat(filepath.Join(home, "docker-called")); !os.IsNotExist(err) {
		t.Fatalf("Docker reached: %v", err)
	}
}

func TestUninstallLateMountRefusesBeforeFileDeletion(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	mount := filepath.Join(dir, "caddy")
	if err := os.MkdirAll(mount, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mount, "sentinel"), []byte("untouched"), 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	findmnt := `#!/bin/sh
count=0
[ ! -f "$HOME/check-count" ] || count=$(cat "$HOME/check-count")
count=$((count+1))
echo "$count" > "$HOME/check-count"
[ "$count" -lt 3 ] || printf '%s\n' "$HOME/statbus/caddy"
`
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte(findmnt), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = version ]; then echo 27.5.1; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "Mountpoint") {
		t.Fatalf("late mount refusal: %v %s", err, out)
	}
	if data, err := os.ReadFile(filepath.Join(mount, "sentinel")); err != nil || string(data) != "untouched" {
		t.Fatalf("sentinel: %v %s", err, data)
	}
}

func TestUninstallOldOrUnprobeableDockerRefusesWithoutDeletion(t *testing.T) {
	for _, tc := range []struct{ name, client, server string }{
		{"old-client", "24.0.9", "27.5.1"},
		{"old-server", "27.5.1", "24.0.9"},
		{"unprobeable", "", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			home := t.TempDir()
			owned := filepath.Join(home, "statbus", "caddy")
			if err := os.MkdirAll(owned, 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(owned, "sentinel"), []byte("untouched"), 0600); err != nil {
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
if [ "$1" = version ]; then
  case "$*" in *Client*) printf '%s\n' '` + tc.client + `' ;; *Server*) printf '%s\n' '` + tc.server + `' ;; esac
  exit 0
fi
if [ "$1" = run ]; then echo called > "$HOME/deleted"; fi
`
			if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
				t.Fatal(err)
			}
			script, _ := filepath.Abs("../../uninstall.sh")
			cmd := exec.Command("bash", script)
			cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
			out, err := cmd.CombinedOutput()
			if err == nil || !strings.Contains(string(out), "Upgrade Docker") || strings.Contains(string(out), "Step 2") {
				t.Fatalf("version refusal: %v %s", err, out)
			}
			if _, err := os.Stat(filepath.Join(home, "deleted")); !os.IsNotExist(err) {
				t.Fatalf("Docker helper called: %v", err)
			}
			if data, err := os.ReadFile(filepath.Join(owned, "sentinel")); err != nil || string(data) != "untouched" {
				t.Fatalf("sentinel: %v %s", err, data)
			}
		})
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

func TestUninstallMarkerRefusalDoesNotUnlinkReplacedTmp(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	external := filepath.Join(home, "external")
	for _, path := range []string{dir, external} {
		if err := os.Mkdir(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	marker := filepath.Join(external, "upgrade-in-progress.json")
	if err := os.WriteFile(marker, []byte("external sentinel"), 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	// Simulate a bind over tmp after the initial mount scan, before the second scan.
	findmnt := `#!/bin/sh
if [ ! -e "$HOME/scanned" ]; then
  touch "$HOME/scanned"
elif [ ! -e "$HOME/swapped" ]; then
  mv "$HOME/statbus/tmp" "$HOME/original-tmp"
  mv "$HOME/external" "$HOME/statbus/tmp"
  echo swapped > "$HOME/swapped"
  printf '%s\n' "$HOME/statbus/tmp"
fi
`
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte(findmnt), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = version ]; then echo 27.5.1; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if _, swapErr := os.Stat(filepath.Join(home, "swapped")); swapErr != nil {
		t.Fatalf("race not exercised: %v %s", swapErr, out)
	}
	if err == nil {
		t.Fatalf("expected refusal: %s", out)
	}
	if data, readErr := os.ReadFile(filepath.Join(dir, "tmp", "upgrade-in-progress.json")); readErr != nil || string(data) != "external sentinel" {
		t.Fatalf("external marker changed: %v %q, uninstall: %s", readErr, data, out)
	}
	if _, statErr := os.Stat(filepath.Join(home, "original-tmp", "upgrade-in-progress.json")); !os.IsNotExist(statErr) {
		t.Fatalf("refusal left an unlocked install marker (Detect would classify crashed): %v %s", statErr, out)
	}
}

func TestUninstallInitialTmpPinDoesNotUnlinkDetachedMount(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	underlay := filepath.Join(home, "underlay-tmp")
	for _, path := range []string{dir, underlay} {
		if err := os.Mkdir(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	// The initial visible tmp stands in for an external bind. Its empty marker
	// must survive even when findmnt simulates lazy detachment of that mount.
	if err := os.Mkdir(filepath.Join(dir, "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "tmp", "upgrade-in-progress.json"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	findmnt := `#!/bin/sh
if [ ! -e "$HOME/detached" ]; then
  mv "$HOME/statbus/tmp" "$HOME/external-tmp"
  mv "$HOME/underlay-tmp" "$HOME/statbus/tmp"
  touch "$HOME/detached"
fi
`
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte(findmnt), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = version ]; then echo 24.0.0; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if _, detachErr := os.Stat(filepath.Join(home, "detached")); detachErr != nil {
		t.Fatalf("detachment not exercised: %v %s", detachErr, out)
	}
	if err == nil || !strings.Contains(string(out), "Docker client and server version 25") {
		t.Fatalf("expected old-Docker refusal: %v %s", err, out)
	}
	if _, markerErr := os.Stat(filepath.Join(home, "external-tmp", "upgrade-in-progress.json")); markerErr != nil {
		t.Fatalf("external empty marker was removed: %v %s", markerErr, out)
	}
	if _, markerErr := os.Stat(filepath.Join(dir, "tmp", "upgrade-in-progress.json")); !os.IsNotExist(markerErr) {
		t.Fatalf("refusal left new install marker: %v %s", markerErr, out)
	}
}

func TestUninstallInitialCheckoutPinDoesNotUnlinkDetachedMount(t *testing.T) {
	home := t.TempDir()
	for _, root := range []string{"statbus", "underlay"} {
		if err := os.MkdirAll(filepath.Join(home, root, "tmp"), 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(home, "statbus", "tmp", "upgrade-in-progress.json"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	findmnt := `#!/bin/sh
if [ ! -e "$HOME/detached" ]; then
  mv "$HOME/statbus" "$HOME/external-checkout"
  mv "$HOME/underlay" "$HOME/statbus"
  touch "$HOME/detached"
fi
`
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte(findmnt), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = version ]; then echo 24.0.0; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if _, detachErr := os.Stat(filepath.Join(home, "detached")); detachErr != nil {
		t.Fatalf("detachment not exercised: %v %s", detachErr, out)
	}
	if err == nil || !strings.Contains(string(out), "Docker client and server version 25") {
		t.Fatalf("expected old-Docker refusal: %v %s", err, out)
	}
	if _, markerErr := os.Stat(filepath.Join(home, "external-checkout", "tmp", "upgrade-in-progress.json")); markerErr != nil {
		t.Fatalf("external checkout marker was removed: %v %s", markerErr, out)
	}
	if _, markerErr := os.Stat(filepath.Join(home, "statbus", "tmp", "upgrade-in-progress.json")); !os.IsNotExist(markerErr) {
		t.Fatalf("refusal left new install marker: %v %s", markerErr, out)
	}
}

func TestUninstallPinnedTmpDetachedDuringSecondMountScan(t *testing.T) {
	home := t.TempDir()
	for _, path := range []string{filepath.Join(home, "statbus", "tmp"), filepath.Join(home, "external-tmp")} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(home, "external-tmp", "upgrade-in-progress.json"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	// The first scan reports clean but a same-filesystem bind arrives just
	// afterward. The second scan detaches it while tmp is pinned, so only the
	// post-scan inode comparison can prevent marker writes on that old cwd.
	findmnt := `#!/bin/sh
if [ ! -e "$HOME/first-scan" ]; then
  mv "$HOME/statbus/tmp" "$HOME/underlay-tmp"
  mv "$HOME/external-tmp" "$HOME/statbus/tmp"
  touch "$HOME/first-scan"
elif [ ! -e "$HOME/second-scan" ]; then
  mv "$HOME/statbus/tmp" "$HOME/external-tmp"
  mv "$HOME/underlay-tmp" "$HOME/statbus/tmp"
  touch "$HOME/second-scan"
fi
`
	if err := os.WriteFile(filepath.Join(bin, "findmnt"), []byte(findmnt), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\necho called > \"$HOME/docker-called\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if _, scanErr := os.Stat(filepath.Join(home, "second-scan")); scanErr != nil {
		t.Fatalf("second scan not exercised: %v %s", scanErr, out)
	}
	if _, markerErr := os.Stat(filepath.Join(home, "external-tmp", "upgrade-in-progress.json")); markerErr != nil {
		t.Fatalf("detached external marker removed: %v %s", markerErr, out)
	}
	if _, markerErr := os.Stat(filepath.Join(home, "statbus", "tmp", "upgrade-in-progress.json")); !os.IsNotExist(markerErr) {
		t.Fatalf("wrote marker to underlay: %v %s", markerErr, out)
	}
	if _, dockerErr := os.Stat(filepath.Join(home, "docker-called")); !os.IsNotExist(dockerErr) {
		t.Fatalf("Docker reached despite unsafe pin: %v %s", dockerErr, out)
	}
	if err == nil || !strings.Contains(string(out), "Pinned checkout or tmp differs") {
		t.Fatalf("expected post-scan provenance refusal: %v %s", err, out)
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

func TestUninstallMarkerOpenRejectsSymlinkIntroducedAfterPrecheck(t *testing.T) {
	home := t.TempDir()
	tmp := filepath.Join(home, "statbus", "tmp")
	if err := os.MkdirAll(tmp, 0700); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	realPerl, err := exec.LookPath("perl")
	if err != nil {
		t.Fatal(err)
	}
	// The wrapper runs only at marker-open time, after check_tmp_boundary.
	// A swapped symlink must not make O_CREAT produce an outside file.
	perl := `#!/bin/sh
case "$*" in
  *'Cannot write install marker'*)
    ln -s "$HOME/external-marker" "$HOME/statbus/tmp/upgrade-in-progress.json";;
esac
exec "` + realPerl + `" "$@"
`
	if err := os.WriteFile(filepath.Join(bin, "perl"), []byte(perl), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if _, markerErr := os.Stat(filepath.Join(home, "external-marker")); !os.IsNotExist(markerErr) {
		t.Fatalf("outside marker created by symlink race: %v %s", markerErr, out)
	}
	if err == nil || !strings.Contains(string(out), "Cannot open the install lock") {
		t.Fatalf("expected no-follow marker refusal: %v %s", err, out)
	}
	if strings.Contains(string(out), "Step 2") {
		t.Fatalf("teardown reached after marker swap: %s", out)
	}
}

func TestUninstallUnreadableInstallLockHasOperatorRemedy(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root bypasses the lock file's permission bits")
	}
	home := t.TempDir()
	tmp := filepath.Join(home, "statbus", "tmp")
	if err := os.MkdirAll(tmp, 0700); err != nil {
		t.Fatal(err)
	}
	lock := filepath.Join(tmp, "upgrade-in-progress.json")
	if err := os.WriteFile(lock, []byte("existing"), 0000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(lock, 0600) })
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "repair its permissions") || strings.Contains(string(out), "Step 2") {
		t.Fatalf("lock remedy: %v %s", err, out)
	}
}

func TestUninstallNonWritableTmpUsesDockerWithoutMktempError(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	tmp := filepath.Join(dir, "tmp")
	if err := os.MkdirAll(tmp, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmp, "upgrade-in-progress.json"), []byte("existing marker"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(tmp, 0500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(tmp, 0700) })
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte("#!/bin/sh\nexit 1\n"), 0700); err != nil {
		t.Fatal(err)
	}
	docker := `#!/bin/sh
if [ "$1" = version ]; then echo 27.5.1; exit 0; fi
if [ "$1" = ps ] && [ "$2" = -aq ]; then echo db1; exit 0; fi
if [ "$1" = inspect ] && [ "$2" = --format ]; then echo ghcr.io/statisticsnorway/statbus-db:sha-test; exit 0; fi
case "$*" in
  'image ls'*) echo ghcr.io/statisticsnorway/statbus-db:sha-test;;
  *uninstall-preflight*) echo helper-probed > "$HOME/docker-probe";;
  *'rm -rf -- ./tmp'*) chmod 0700 "$HOME/statbus/tmp"; rm -rf -- "$HOME/statbus/tmp";;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err != nil || strings.Contains(string(out), "mktemp") {
		t.Fatalf("Docker fallback from non-writable tmp: %v %s", err, out)
	}
	if _, err := os.Stat(filepath.Join(home, "docker-probe")); err != nil {
		t.Fatalf("Docker probe not reached: %v %s", err, out)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("checkout survived: %v %s", err, out)
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
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(`#!/bin/sh
if [ "$1" = version ]; then echo 27.5.1; exit 0; fi
if [ "$1" = run ]; then
  case "$*" in
    *'rm -rf -- ./tmp'*) rm -rf -- "$HOME/statbus/tmp";;
    *'rm -rf -- "./$2"'*) rm -rf -- "$HOME/statbus/dbdumps" "$HOME/statbus/.env.credentials";;
  esac
fi
`), 0700); err != nil {
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
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nif [ \"$1\" = version ]; then echo 27.5.1; exit 0; fi\nif [ \"$1\" = run ]; then exit 1; fi\nif [ \"$1\" = rm ]; then echo deleted > \"$HOME/deleted\"; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	_, deletedErr := os.Stat(filepath.Join(home, "deleted"))
	if err == nil || !strings.Contains(string(out), "Docker cannot safely remove checkout files") || !os.IsNotExist(deletedErr) || strings.Contains(string(out), "Step 2") {
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
if [ "$1" = version ]; then echo 27.5.1; exit 0; fi
if [ "$1" = ps ] && [ "$2" = -aq ]; then echo db1; exit 0; fi
if [ "$1" = inspect ] && [ "$2" = --format ]; then echo ghcr.io/statisticsnorway/statbus-db:sha-test; exit 0; fi
case "$*" in
  'image ls'*) echo ghcr.io/statisticsnorway/statbus-db:sha-test; exit 0;;
esac
if [ "$1" = run ]; then
  [ ! -e "$HOME/image-removed" ] || exit 1
  printf '<%s>\n' "$@" >> "$HOME/docker-argv"
  case "$*" in
    *uninstall-preflight*) exit 0;;
    *' caddy') chmod -R u+w "$HOME/statbus/caddy"; rm -rf -- "$HOME/statbus/caddy";;
    *'rm -rf -- ./tmp'*) rm -rf -- "$HOME/statbus/tmp";;
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
	if err != nil || !strings.Contains(string(argv), "<type=bind,src="+home+",dst=/home-root,bind-recursive=disabled,bind-propagation=rprivate>") || !strings.Contains(string(argv), "<--user>") || !strings.Contains(string(argv), "<0:0>") || !strings.Contains(string(argv), "<caddy>") {
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
if [ "$1" = version ]; then echo 27.5.1; exit 0; fi
case "$*" in
  'image inspect alpine:3.20') exit 1;;
  'pull alpine:3.20') touch "$HOME/pulled";;
  'image rm alpine:3.20') touch "$HOME/helper-removed";;
  *uninstall-preflight*) [ -e "$HOME/pulled" ] || exit 1;;
  *' caddy') chmod 0700 "$HOME/statbus/caddy"; rm -rf -- "$HOME/statbus/caddy";;
  *'rm -rf -- ./tmp'*) chmod 0700 "$HOME/statbus"; rm -rf -- "$HOME/statbus/tmp";;
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

func TestUninstallQuiescenceAndUnattributedImage(t *testing.T) {
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
		} else if err != nil || !os.IsNotExist(removedErr) {
			t.Fatalf("unattributed image must be retained: %v %s %v", err, out, removedErr)
		}
	}
}

func TestUninstallSharedDaemonKeepsOtherProjectImages(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("COMPOSE_INSTANCE_NAME=statbus-a\n"), 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	docker := `#!/bin/sh
case "$1 $2" in
  'version '*) echo 27.5.1;;
  'ps -aq')
    case "$*" in *'project=statbus-a'*) printf '%s\n' a1 a2;; *) printf '%s\n' a1 a2 b1 b2;; esac;;
  'inspect --format')
    case "$4" in
      a1|b1) echo ghcr.io/statisticsnorway/statbus-app:sha-shared;;
      a2) echo ghcr.io/statisticsnorway/statbus-db:sha-own;;
      b2) echo ghcr.io/statisticsnorway/statbus-worker:sha-foreign;;
    esac;;
  'image ls') printf '%s\n' ghcr.io/statisticsnorway/statbus-app:sha-shared ghcr.io/statisticsnorway/statbus-db:sha-own ghcr.io/statisticsnorway/statbus-worker:sha-foreign ghcr.io/statisticsnorway/statbus-worker:sha-orphan;;
  'image rm') echo "$3" >> "$HOME/removed-images";;
  'rm -f') echo "$*" >> "$HOME/removed-containers";;
  'run --rm')
    case "$*" in *'rm -rf -- ./tmp'*) rm -rf -- "$HOME/statbus/tmp";; *' .env') rm -f -- "$HOME/statbus/.env";; esac;;
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
		t.Fatalf("shared daemon uninstall: %v %s", err, out)
	}
	removed, err := os.ReadFile(filepath.Join(home, "removed-images"))
	if err != nil {
		t.Fatalf("removed-images: %v; output: %s", err, out)
	}
	if strings.Contains(string(removed), "sha-shared") || strings.Contains(string(removed), "sha-foreign") || strings.Contains(string(removed), "sha-orphan") || !strings.Contains(string(removed), "sha-own") {
		t.Fatalf("wrong image scope: %s; output: %s", removed, out)
	}
	if strings.Contains(string(out), "sha-orphan") {
		t.Fatalf("unreferenced foreign tag entered deletion plan: %s", out)
	}
	if !strings.Contains(string(out), "shared") {
		t.Fatalf("no explanation for retained shared tag: %s", out)
	}
	removedContainers, err := os.ReadFile(filepath.Join(home, "removed-containers"))
	if err != nil || !strings.Contains(string(removedContainers), "a1 a2") || strings.Contains(string(removedContainers), "b1") {
		t.Fatalf("other project containers touched: %v %s", err, removedContainers)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatalf("checkout remains: %v %s", err, out)
	}
}

func TestUninstallHelperRejectsDifferentCheckoutInode(t *testing.T) {
	for _, stage := range []string{"preflight", "path", "tmp"} {
		t.Run(stage, func(t *testing.T) {
			home := t.TempDir()
			dir := filepath.Join(home, "statbus")
			external := filepath.Join(home, "external")
			for _, path := range []string{filepath.Join(dir, "tmp"), filepath.Join(external, "tmp"), filepath.Join(home, "mapped-root")} {
				if err := os.MkdirAll(path, 0700); err != nil {
					t.Fatal(err)
				}
			}
			for _, path := range []string{filepath.Join(dir, "victim"), filepath.Join(external, "victim"), filepath.Join(external, "tmp", "sentinel")} {
				if err := os.WriteFile(path, []byte("untouched"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			mapped := filepath.Join(home, "mapped-root", "statbus")
			initial := dir
			if stage == "preflight" {
				initial = external
			}
			if err := os.Symlink(initial, mapped); err != nil {
				t.Fatal(err)
			}
			bin := filepath.Join(home, "bin")
			if err := os.Mkdir(bin, 0700); err != nil {
				t.Fatal(err)
			}
			// The fake Docker executes the exact -c payload, mapping /home-root
			// to mapped-root. A fake stat translates GNU stat syntax on macOS.
			stat := "#!/bin/sh\nif [ \"$1\" = -c ]; then "
			if runtime.GOOS == "darwin" {
				stat += "exec /usr/bin/stat -f '%d:%i' \"$3\"\n"
			} else {
				stat += "exec /usr/bin/stat \"$@\"\n"
			}
			stat += "fi\nexec /usr/bin/stat \"$@\"\n"
			if err := os.WriteFile(filepath.Join(bin, "stat"), []byte(stat), 0700); err != nil {
				t.Fatal(err)
			}
			docker := `#!/usr/bin/env bash
if [[ $1 == version ]]; then echo 27.5.1; exit 0; fi
if [[ $1 != run ]]; then exit 0; fi
count=0
[[ ! -e "$HOME/helper-count" ]] || count=$(cat "$HOME/helper-count")
count=$((count+1))
echo "$count" > "$HOME/helper-count"
if [[ "$STAGE" == path && $count == 2 || "$STAGE" == tmp && $count == 3 ]]; then
  rm "$HOME/mapped-root/statbus"
  ln -s "$HOME/external" "$HOME/mapped-root/statbus"
fi
while [[ $1 != -c ]]; do shift; done
shift
helper=$1; shift
helper=${helper//\/home-root\/statbus/$HOME\/mapped-root\/statbus}
/bin/sh -c "$helper" "$@"
`
			if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
				t.Fatal(err)
			}
			script, _ := filepath.Abs("../../uninstall.sh")
			cmd := exec.Command("bash", script)
			cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STAGE="+stage, "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
			out, err := cmd.CombinedOutput()
			if err == nil {
				t.Fatalf("different inode accepted: %s", out)
			}
			calls, readErr := os.ReadFile(filepath.Join(home, "helper-count"))
			want := map[string]string{"preflight": "1\n", "path": "2\n", "tmp": "3\n"}[stage]
			if readErr != nil || string(calls) != want {
				t.Fatalf("helper stage %s not exercised: %v %q %s", stage, readErr, calls, out)
			}
			if stage == "preflight" && strings.Contains(string(out), "Step 2") {
				t.Fatalf("preflight failed after teardown: %s", out)
			}
			for _, path := range []string{filepath.Join(external, "victim"), filepath.Join(external, "tmp", "sentinel")} {
				if data, readErr := os.ReadFile(path); readErr != nil || string(data) != "untouched" {
					t.Fatalf("external path %s changed: %v %q %s", path, readErr, data, out)
				}
			}
		})
	}
}

func TestUninstallReportsUnexpectedCheckoutLeftovers(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "unexpected"), []byte("leftover"), 0600); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	// Fake helper omits an unexpected path, but does remove tmp.
	docker := "#!/bin/sh\nif [ \"$1\" = version ]; then echo 27.5.1; fi\ncase \"$*\" in *'rm -rf -- ./tmp'*) rm -rf -- \"$HOME/statbus/tmp\";; esac\n"
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "Unexpected checkout files remain") || strings.Contains(string(out), "Removal complete") {
		t.Fatalf("unexplained leftover: %v %s", err, out)
	}
}

func TestUninstallKeepsPulledHelperUsedByAnotherContainer(t *testing.T) {
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, "statbus", "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	docker := `#!/bin/sh
case "$1 $2" in
  'version '*) echo 27.5.1;;
  'image inspect') exit 1;;
  'pull alpine:3.20') touch "$HOME/pulled";;
  'ps -aq') [ ! -e "$HOME/pulled" ] || { case "$*" in *--filter*) :;; *) echo other-container;; esac; };;
  'inspect --format') echo alpine:3.20;;
  'image rm') echo "$3" > "$HOME/removed-image";;
  'run --rm') case "$*" in *'rm -rf -- ./tmp'*) rm -rf -- "$HOME/statbus/tmp";; esac;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+bin+":"+os.Getenv("PATH"), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	out, err := cmd.CombinedOutput()
	if err != nil || !strings.Contains(string(out), "Keeping shared image tag alpine:3.20") {
		t.Fatalf("helper retention: %v %s", err, out)
	}
	if _, err := os.Stat(filepath.Join(home, "removed-image")); !os.IsNotExist(err) {
		t.Fatalf("shared helper removed: %v", err)
	}
}
