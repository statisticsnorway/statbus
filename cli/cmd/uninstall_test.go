package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
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

// writeUninstallDockerMock writes a Docker stand-in that performs the helper's
// deletions on the real tree, so a test can assert what the script removed
// without a daemon.
func writeUninstallDockerMock(t *testing.T, bin string) {
	t.Helper()
	mock := `#!/bin/sh
case "$1" in
  version) echo 27.5.1 ;;
  run)
    case "$*" in
      *uninstall-preflight*) exit 0 ;;
      *'rm -rf -- ./tmp'*) rm -rf -- "$HOME/statbus/tmp" ;;
      *'cd /home-root && rm -rf -- "./'*)
        for last; do :; done
        rm -rf -- "$HOME/$last" ;;
      *'rm -rf -- "./'*)
        for last; do :; done
        rm -rf -- "$HOME/statbus/$last" ;;
    esac ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(mock), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte("#!/bin/sh\nshift\nexec \"$@\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
}

// runUninstallOnPTY runs uninstall.sh with a controlling terminal and feeds
// its prompts, so the interactive keep questions are exercised as an operator
// meets them.
func runUninstallOnPTY(t *testing.T, home, path, answers string) (string, error) {
	t.Helper()
	script, err := filepath.Abs("../../uninstall.sh")
	if err != nil {
		t.Fatal(err)
	}
	ptyScript := filepath.Join(t.TempDir(), "run-uninstall-pty.py")
	code := `import os, pty, sys
answers = open(sys.argv[1], "rb").read()
pid, fd = pty.fork()
if pid == 0:
    env = dict(os.environ)
    env["HOME"] = sys.argv[2]
    env["PATH"] = sys.argv[3]
    env.pop("STATBUS_UNINSTALL_CONFIRM", None)
    os.execvpe("bash", ["bash", sys.argv[4]], env)
os.write(fd, answers)
out = b""
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
_, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(out)
sys.exit(os.waitstatus_to_exitcode(status))
`
	if err := os.WriteFile(ptyScript, []byte(code), 0600); err != nil {
		t.Fatal(err)
	}
	answerPath := filepath.Join(t.TempDir(), "answers")
	if err := os.WriteFile(answerPath, []byte(answers), 0600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("python3", ptyScript, answerPath, home, path, script)
	var out strings.Builder
	cmd.Stdout = &out
	cmd.Stderr = &out
	err = cmd.Run()
	return out.String(), err
}

// STATBUS-419 AC6: keeping the users and credentials moves them out to the
// operator's home (mode 0600), then removes the whole checkout.
func TestUninstallKeepsUsersAndCredentialsAtHome(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	users := "- display_name: Ada\n  email: ada@example.org\n  password: ada-secret\n  role: admin_user\n"
	for path, content := range map[string]string{
		filepath.Join(dir, ".users.yml"):       users,
		filepath.Join(dir, ".env.credentials"): "GITHUB_TOKEN=kept-token\n",
	} {
		if err := os.WriteFile(path, []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	bin := ensureBinDir(t, home)
	writeUninstallDockerMock(t, bin)
	out, err := runUninstallOnPTY(t, home, binPath(home), "\n\nDELETE\n")
	if err != nil {
		t.Fatalf("interactive removal: %v\n%s", err, out)
	}
	if _, statErr := os.Stat(dir); !os.IsNotExist(statErr) {
		t.Fatalf("checkout survived: %v\n%s", statErr, out)
	}
	for path, want := range map[string]string{
		filepath.Join(home, "statbus.users.yml"):       users,
		filepath.Join(home, "statbus.env.credentials"): "GITHUB_TOKEN=kept-token\n",
	} {
		data, readErr := os.ReadFile(path)
		if readErr != nil || string(data) != want {
			t.Fatalf("%s: %q %v\n%s", path, data, readErr, out)
		}
		st, statErr := os.Stat(path)
		if statErr != nil || st.Mode().Perm() != 0600 {
			t.Fatalf("%s mode: %v %v", path, st, statErr)
		}
	}
	for _, want := range []string{
		"Keep the users? [Y/n]",
		"Keep the credentials? [Y/n]",
		"Move to " + filepath.Join(home, "statbus.users.yml") + ": " + filepath.Join(dir, ".users.yml"),
		"Move to " + filepath.Join(home, "statbus.env.credentials") + ": " + filepath.Join(dir, ".env.credentials"),
	} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
}

// A kept file never overwrites a different file already in the home, and the
// refusal happens before anything is deleted.
func TestUninstallRefusesToOverwriteDifferentHomeUserFile(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	writeUninstallDockerMock(t, ensureBinDir(t, home))
	if err := os.WriteFile(filepath.Join(dir, ".users.yml"), []byte("- email: new@example.org\n"), 0600); err != nil {
		t.Fatal(err)
	}
	homeUsers := filepath.Join(home, "statbus.users.yml")
	if err := os.WriteFile(homeUsers, []byte("- email: old@example.org\n"), 0600); err != nil {
		t.Fatal(err)
	}
	out, err := runUninstallOnPTY(t, home, binPath(home), "\n\nDELETE\n")
	if err == nil || !strings.Contains(out, "Refusing") || !strings.Contains(out, homeUsers) {
		t.Fatalf("different home file not refused: %v\n%s", err, out)
	}
	if data, readErr := os.ReadFile(homeUsers); readErr != nil || string(data) != "- email: old@example.org\n" {
		t.Fatalf("home file changed: %q %v", data, readErr)
	}
	if _, statErr := os.Stat(filepath.Join(dir, ".users.yml")); statErr != nil {
		t.Fatalf("checkout changed on refusal: %v\n%s", statErr, out)
	}
	if strings.Contains(out, "Step 2") {
		t.Fatalf("teardown ran after refusal:\n%s", out)
	}
}

func ensureBinDir(t *testing.T, home string) string {
	t.Helper()
	bin := filepath.Join(home, "bin")
	if err := os.MkdirAll(bin, 0700); err != nil {
		t.Fatal(err)
	}
	return bin
}

func binPath(home string) string {
	return filepath.Join(home, "bin") + ":" + os.Getenv("PATH")
}

// Unattended removal keeps neither file, so no home copy is created.
func TestUninstallUnattendedRemovesHomeUserState(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".users.yml", ".env.credentials"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("x\n"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	bin := ensureBinDir(t, home)
	writeUninstallDockerMock(t, bin)
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+binPath(home), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("unattended removal: %v\n%s", err, out)
	}
	if _, statErr := os.Stat(dir); !os.IsNotExist(statErr) {
		t.Fatalf("checkout survived: %v", statErr)
	}
	for _, path := range []string{filepath.Join(home, "statbus.users.yml"), filepath.Join(home, "statbus.env.credentials")} {
		if _, statErr := os.Stat(path); !os.IsNotExist(statErr) {
			t.Fatalf("unattended removal kept %s", path)
		}
	}
}

// STATBUS-419 AC7: after `sudo -iu statbus` there is no XDG_RUNTIME_DIR; the
// script supplies this user's own /run/user/<uid> so the user systemd manager
// (and the upgrader stop) is reachable.
func TestUninstallSuppliesUserRuntimeDirToSystemctl(t *testing.T) {
	home := t.TempDir()
	base := filepath.Join(home, "runtime")
	uid := fmt.Sprint(os.Getuid())
	if err := os.MkdirAll(filepath.Join(base, uid), 0700); err != nil {
		t.Fatal(err)
	}
	unitDir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(unitDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(unitDir, "statbus-upgrader@.service"), []byte("[Unit]\n"), 0600); err != nil {
		t.Fatal(err)
	}
	bin := ensureBinDir(t, home)
	systemctl := `#!/bin/sh
printf '%s\n' "${XDG_RUNTIME_DIR:-}" >> "$HOME/systemctl-runtime"
case "$*" in
  *is-active*) echo inactive ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(bin, "systemctl"), []byte(systemctl), 0700); err != nil {
		t.Fatal(err)
	}
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	var env []string
	for _, entry := range os.Environ() {
		if !strings.HasPrefix(entry, "XDG_RUNTIME_DIR=") {
			env = append(env, entry)
		}
	}
	cmd.Env = append(env, "HOME="+home, "PATH="+binPath(home),
		"STATBUS_UNINSTALL_CONFIRM=yes-delete-everything", "STATBUS_USER_RUNTIME_DIR_BASE="+base)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("removal with a user unit: %v\n%s", err, out)
	}
	captured, err := os.ReadFile(filepath.Join(home, "systemctl-runtime"))
	if err != nil {
		t.Fatalf("systemctl was not reached: %v\n%s", err, out)
	}
	lines := strings.Fields(string(captured))
	if len(lines) == 0 {
		t.Fatal("systemctl saw no XDG_RUNTIME_DIR")
	}
	for _, line := range lines {
		if line != filepath.Join(base, uid) {
			t.Fatalf("systemctl saw XDG_RUNTIME_DIR=%q, want %q\n%s", line, filepath.Join(base, uid), out)
		}
	}
	if !strings.Contains(string(out), "Step 1: stopping StatBus upgrader") {
		t.Fatalf("did not reach the upgrader stop:\n%s", out)
	}
}

// The install creates ~/statbus-maintenance (the maintenance page switch) and
// ~/statbus-upgrade-snapshots (the upgrade snapshots) next to the checkout. A
// box installed before STATBUS-574 may still hold its snapshots in
// ~/statbus-backups. Removal takes all of them, and the plan lists each one.
func TestUninstallRemovesTheInstallsHomeFolders(t *testing.T) {
	// The upgrade snapshots only fit the installation being removed, so they
	// go whether or not the database backups are kept.
	for _, tc := range []struct{ name, answers string }{
		{"keep the database backup", "n\nn\n\nDELETE\n"},
		{"delete the database backup", "n\nn\nn\nDELETE\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			home := t.TempDir()
			dir := filepath.Join(home, "statbus")
			snapshots := filepath.Join(home, "statbus-upgrade-snapshots")
			legacySnapshots := filepath.Join(home, "statbus-backups")
			for _, sub := range []string{filepath.Join(dir, "tmp"), filepath.Join(dir, "dbdumps"), filepath.Join(home, "statbus-maintenance"), filepath.Join(snapshots, "pre-upgrade-active"), filepath.Join(legacySnapshots, "pre-upgrade-active")} {
				if err := os.MkdirAll(sub, 0700); err != nil {
					t.Fatal(err)
				}
			}
			for path, body := range map[string]string{
				filepath.Join(home, "statbus-maintenance", "active"):            "upgrade\n",
				filepath.Join(snapshots, "snapshot-2026-11-06T10-00-00.tar.gz"): "archive",
				filepath.Join(legacySnapshots, "v2026.11.0-pre.tar.gz"):         "archive",
				filepath.Join(dir, "dbdumps", "un_20261105_121219.pg_dump"):     "dump",
			} {
				if err := os.WriteFile(path, []byte(body), 0600); err != nil {
					t.Fatal(err)
				}
			}
			writeUninstallDockerMock(t, ensureBinDir(t, home))
			out, err := runUninstallOnPTY(t, home, binPath(home), tc.answers)
			if err != nil {
				t.Fatalf("interactive removal: %v\n%s", err, out)
			}
			for _, path := range []string{dir, filepath.Join(home, "statbus-maintenance"), snapshots, legacySnapshots} {
				if _, statErr := os.Stat(path); !os.IsNotExist(statErr) {
					t.Errorf("%s survived the removal: %v\n%s", path, statErr, out)
				}
			}
			for _, want := range []string{"  Path (recursively): " + filepath.Join(home, "statbus-maintenance"), "  Path (recursively): " + snapshots, "  Path (recursively): " + legacySnapshots} {
				if !strings.Contains(out, want) {
					t.Errorf("plan is missing %q:\n%s", want, out)
				}
			}
		})
	}
}

// A completed removal leaves the home as the operator had it, plus only what
// they chose to keep and the removal log: the install/uninstall lock file
// (~/.statbus-uninstall.lock) is removed once nothing holds it.
func TestUninstallLeavesNoLockFileBehind(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0700); err != nil {
		t.Fatal(err)
	}
	writeUninstallDockerMock(t, ensureBinDir(t, home))
	script, _ := filepath.Abs("../../uninstall.sh")
	cmd := exec.Command("bash", script)
	cmd.Env = append(os.Environ(), "HOME="+home, "PATH="+binPath(home), "STATBUS_UNINSTALL_CONFIRM=yes-delete-everything")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("unattended removal: %v\n%s", err, out)
	}
	entries, err := os.ReadDir(home)
	if err != nil {
		t.Fatal(err)
	}
	var left []string
	for _, entry := range entries {
		left = append(left, entry.Name())
	}
	if got := strings.Join(left, " "); got != "bin statbus-uninstall.log" {
		t.Fatalf("home after removal holds %q, want only the test's bin and statbus-uninstall.log", got)
	}
}

// uninstallPrompts lists the questions an uninstall asked, in the order they
// appear. On a terminal several prompts can share one output line (the
// answer's echo is not a newline), so they are found by position.
func uninstallPrompts(out string) []string {
	text := strings.ReplaceAll(out, "\r", "")
	backup := regexp.MustCompile(`Keep the [0-9]+ database backups?\? \[Y/n\]`)
	type found struct {
		at     int
		prompt string
	}
	var all []found
	for _, q := range []string{"Keep the users? [Y/n]", "Keep the credentials? [Y/n]", "Type DELETE to execute this exact plan:"} {
		for from := 0; ; {
			i := strings.Index(text[from:], q)
			if i < 0 {
				break
			}
			all = append(all, found{from + i, q})
			from += i + len(q)
		}
	}
	for _, loc := range backup.FindAllStringIndex(text, -1) {
		all = append(all, found{loc[0], text[loc[0]:loc[1]]})
	}
	sort.Slice(all, func(i, j int) bool { return all[i].at < all[j].at })
	prompts := make([]string, 0, len(all))
	for _, f := range all {
		prompts = append(prompts, f.prompt)
	}
	return prompts
}

// STATBUS-419 AC9: kept database backups leave the checkout, like the kept
// users and credentials, so ~/statbus is removed completely; the upgrade
// snapshots are removed, since they only fit the installation being removed.
// The plan and the answers are in the removal log.
func TestUninstallKeepsBackupsOutsideTheCheckout(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	for _, sub := range []string{filepath.Join(dir, "tmp"), filepath.Join(dir, "dbdumps"), filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active")} {
		if err := os.MkdirAll(sub, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	for path, body := range map[string]string{
		filepath.Join(dir, "dbdumps", ".gitkeep"):                                   "",
		filepath.Join(dir, "dbdumps", "un_20261105_121219.pg_dump"):                 "dump",
		filepath.Join(dir, "dbdumps", "un_20261105_121219.logs.tar.gz"):             "logs",
		filepath.Join(home, "statbus-upgrade-snapshots", "pre-upgrade-active", "x"): "snapshot",
	} {
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	writeUninstallDockerMock(t, ensureBinDir(t, home))
	out, err := runUninstallOnPTY(t, home, binPath(home), "\n\n\nDELETE\n")
	if err != nil {
		t.Fatalf("interactive removal: %v\n%s", err, out)
	}
	wantPrompts := []string{"Keep the users? [Y/n]", "Keep the credentials? [Y/n]", "Keep the 1 database backup? [Y/n]", "Type DELETE to execute this exact plan:"}
	if got := uninstallPrompts(out); strings.Join(got, "|") != strings.Join(wantPrompts, "|") {
		t.Fatalf("prompts = %q, want %q\n%s", got, wantPrompts, out)
	}
	kept := filepath.Join(home, "statbus.dbdumps")
	for name, want := range map[string]string{"un_20261105_121219.pg_dump": "dump", "un_20261105_121219.logs.tar.gz": "logs"} {
		if data, readErr := os.ReadFile(filepath.Join(kept, name)); readErr != nil || string(data) != want {
			t.Fatalf("%s: %q %v\n%s", name, data, readErr, out)
		}
	}
	for _, gone := range []string{dir, filepath.Join(home, "statbus-upgrade-snapshots")} {
		if _, statErr := os.Stat(gone); !os.IsNotExist(statErr) {
			t.Fatalf("%s survived the removal: %v\n%s", gone, statErr, out)
		}
	}
	planLine := "  Move to " + kept + ": " + filepath.Join(dir, "dbdumps") + " (1 database backup)"
	if !strings.Contains(out, planLine) {
		t.Errorf("plan is missing %q:\n%s", planLine, out)
	}
	log, readErr := os.ReadFile(filepath.Join(home, "statbus-uninstall.log"))
	if readErr != nil {
		t.Fatal(readErr)
	}
	for _, want := range []string{"StatBus removal plan (only listed resources will be deleted):", planLine, "Answers: keep users=yes, keep credentials=yes, keep the 1 database backup=yes"} {
		if !strings.Contains(string(log), want) {
			t.Errorf("removal log is missing %q:\n%s", want, log)
		}
	}
}

// With no database backup there is nothing to keep, so nothing is asked about
// backups, and the empty upgrade-snapshot folder goes.
func TestUninstallAsksAboutBackupsOnlyWhenThereAreSome(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	for _, sub := range []string{filepath.Join(dir, "tmp"), filepath.Join(dir, "dbdumps"), filepath.Join(home, "statbus-upgrade-snapshots")} {
		if err := os.MkdirAll(sub, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "dbdumps", ".gitkeep"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	writeUninstallDockerMock(t, ensureBinDir(t, home))
	out, err := runUninstallOnPTY(t, home, binPath(home), "\n\nDELETE\n")
	if err != nil {
		t.Fatalf("interactive removal: %v\n%s", err, out)
	}
	wantPrompts := []string{"Keep the users? [Y/n]", "Keep the credentials? [Y/n]", "Type DELETE to execute this exact plan:"}
	if got := uninstallPrompts(out); strings.Join(got, "|") != strings.Join(wantPrompts, "|") {
		t.Fatalf("prompts = %q, want %q\n%s", got, wantPrompts, out)
	}
	for _, gone := range []string{dir, filepath.Join(home, "statbus-upgrade-snapshots"), filepath.Join(home, "statbus.dbdumps")} {
		if _, statErr := os.Stat(gone); !os.IsNotExist(statErr) {
			t.Fatalf("%s exists after the removal: %v\n%s", gone, statErr, out)
		}
	}
}

// A kept backup never overwrites a different file of the same name in
// ~/statbus.dbdumps: the uninstall refuses before stopping or deleting anything.
func TestUninstallRefusesToOverwriteADifferentKeptBackup(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, "statbus")
	for _, sub := range []string{filepath.Join(dir, "tmp"), filepath.Join(dir, "dbdumps"), filepath.Join(home, "statbus.dbdumps")} {
		if err := os.MkdirAll(sub, 0o700); err != nil {
			t.Fatal(err)
		}
	}
	checkoutDump := filepath.Join(dir, "dbdumps", "x_20261105_121219.pg_dump")
	homeDump := filepath.Join(home, "statbus.dbdumps", "x_20261105_121219.pg_dump")
	for path, body := range map[string]string{checkoutDump: "new", homeDump: "old"} {
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	writeUninstallDockerMock(t, ensureBinDir(t, home))
	out, err := runUninstallOnPTY(t, home, binPath(home), "\n\n\nDELETE\n")
	if err == nil || !strings.Contains(out, "Refusing to overwrite "+homeDump) {
		t.Fatalf("different kept backup not refused: %v\n%s", err, out)
	}
	for path, want := range map[string]string{checkoutDump: "new", homeDump: "old"} {
		if data, _ := os.ReadFile(path); string(data) != want {
			t.Fatalf("%s = %q, want %q", path, data, want)
		}
	}
	if strings.Contains(out, "Step 2") {
		t.Fatalf("teardown ran after refusal:\n%s", out)
	}
}
