package cmd

import (
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
)

// The one refusal shape (STATBUS-521): the port, the listener's name when ss
// showed it (else "another program"), what is ours (StatBus needs the port),
// and no command for the other program.
func TestPortConflictGuidance(t *testing.T) {
	const tail = ". StatBus needs this port. Stop that program or move it to another port."
	for _, owner := range []string{"python3", "another program"} {
		want := "Port 80 is in use by " + owner + tail
		if got := portConflictGuidance(80, owner); got != want {
			t.Fatalf("guidance for %q:\n got  %q\n want %q", owner, got, want)
		}
	}
	// A name outside the safe pattern never crosses the diagnostic boundary.
	if got := portConflictGuidance(80, "bad name $(id)"); got != "Port 80 is in use by another program"+tail {
		t.Fatalf("unsafe owner not filtered: %q", got)
	}
	message := servicePortConflictCause(errors.New("the web server (proxy) could not publish host port 80/tcp; port listener unavailable"))
	if !strings.HasPrefix(message, "Port 80 is in use by ") || !strings.HasSuffix(message, tail) {
		t.Fatalf("service port failure lost the port refusal shape: %s", message)
	}
}

func TestOwnPublishedPortRangeAndForeignSlot(t *testing.T) {
	// docker ps human output: statbus-local-proxy 127.0.0.1:3014-3015->3014-3015/tcp, 127.0.0.1:3010->80/tcp
	// Compose's project-scoped JSON reports each publisher instead of that compressed column.
	statuses, err := parseServiceStatuses([]byte(`{"Name":"statbus-local-proxy","Service":"proxy","State":"running","Publishers":[{"URL":"127.0.0.1","TargetPort":3014,"PublishedPort":3014,"Protocol":"tcp"},{"URL":"127.0.0.1","TargetPort":3015,"PublishedPort":3015,"Protocol":"tcp"},{"URL":"127.0.0.1","TargetPort":80,"PublishedPort":3010,"Protocol":"tcp"}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, port := range []int{3010, 3014, 3015} {
		if !ownPublishedPort(statuses, port) {
			t.Fatalf("own published port %d not recognized", port)
		}
	}
	if ownPublishedPort(statuses, 3016) {
		t.Fatal("foreign listener accepted as our port")
	}
	// Docker Compose scopes ps to this project: a different slot's container is absent.
	if ownPublishedPort(nil, 3014) {
		t.Fatal("different slot's container accepted as ours")
	}
	statuses[0].State = "exited"
	if !ownPublishedPort(statuses, 3014) {
		t.Fatal("Compose publisher ignored because service is not running")
	}
}

func TestCheckInstallPortsOwnAndForeign(t *testing.T) {
	dir := t.TempDir()
	writeConfig := func(mode string) {
		content := "CADDY_DEPLOYMENT_MODE=" + mode + "\nDEPLOYMENT_SLOT_CODE=local\nDEPLOYMENT_SLOT_PORT_OFFSET=1\n"
		if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	writeConfig("development")
	rerun := diskpolicy.RerunCommand()
	oldProbe, oldOwner := probeServiceStatuses, occupiedPortOwner
	t.Cleanup(func() { probeServiceStatuses, occupiedPortOwner = oldProbe, oldOwner })
	occupiedPortOwner = func(port installPort) string {
		if port.number == 3014 || port.number == 3015 {
			return "another program"
		}
		return ""
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) {
		return parseServiceStatuses([]byte(`{"Service":"proxy","State":"running","Publishers":[{"PublishedPort":3014,"Protocol":"tcp"},{"PublishedPort":3015,"Protocol":"tcp"}]}`))
	}
	if err := checkInstallPorts(dir); err != nil {
		t.Fatalf("own running proxy rejected: %v", err)
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return nil, nil } // Other slot is not this Compose project.
	err := checkInstallPorts(dir)
	want := "Port 3014 is in use by another program. StatBus needs this port. Stop that program or move it to another port. Your answers are saved. Then run the same install command again: " + rerun
	if err == nil || err.Error() != want {
		t.Fatalf("foreign listener refusal:\n got  %v\n want %s", err, want)
	}
	// When the ownership probe itself fails, the refusal says so: install could
	// not confirm whether the listener is StatBus's own.
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return nil, errors.New("compose unavailable") }
	err = checkInstallPorts(dir)
	want = "Port 3014 is in use by another program. StatBus needs this port. Stop that program or move it to another port. Docker service ownership could not be checked. Your answers are saved. Then run the same install command again: " + rerun
	if err == nil || err.Error() != want {
		t.Fatalf("probe-failure refusal:\n got  %v\n want %s", err, want)
	}
	occupiedPortOwner = func(installPort) string { return "" }
	if err := checkInstallPorts(dir); err != nil {
		t.Fatalf("free ports should not require Docker: %v", err)
	}
	writeConfig("standalone")
	occupiedPortOwner = func(port installPort) string {
		if port.number == 80 || port.number == 5432 {
			return "another program"
		}
		return ""
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) {
		return parseServiceStatuses([]byte(`{"Service":"proxy","Publishers":[{"PublishedPort":80,"Protocol":"tcp"},{"PublishedPort":5432,"Protocol":"tcp"}]}`))
	}
	if err := checkInstallPorts(dir); err != nil {
		t.Fatalf("standalone own ports rejected: %v", err)
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return nil, nil }
	if err := checkInstallPorts(dir); err == nil || !strings.Contains(err.Error(), "Port 80 is in use by another program") {
		t.Fatalf("standalone foreign port not refused: %v", err)
	}
	// A listener named by ss is reported by name, with and without the
	// ownership-check variant; no remedy command is prescribed either way.
	occupiedPortOwner = func(port installPort) string {
		if port.number == 80 {
			return "apache2"
		}
		return ""
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return nil, errors.New("compose unavailable") }
	err = checkInstallPorts(dir)
	want = "Port 80 is in use by apache2. StatBus needs this port. Stop that program or move it to another port. Docker service ownership could not be checked. Your answers are saved. Then run the same install command again: " + rerun
	if err == nil || err.Error() != want {
		t.Fatalf("named listener with failed ownership probe:\n got  %v\n want %s", err, want)
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return nil, nil }
	err = checkInstallPorts(dir)
	want = "Port 80 is in use by apache2. StatBus needs this port. Stop that program or move it to another port. Your answers are saved. Then run the same install command again: " + rerun
	if err == nil || err.Error() != want {
		t.Fatalf("named listener refusal:\n got  %v\n want %s", err, want)
	}
}

// The listener's name comes only from ss output: unprivileged `ss -ltnp` when
// it can see the process, `sudo -n ss -ltnp` when it cannot, never a
// hardcoded unit list (STATBUS-521).
func TestOccupiedPortOwnerNamesListenerFromSs(t *testing.T) {
	if m := listenerProgram.FindStringSubmatch(`users:(("apache2",pid=123,fd=4))`); len(m) != 2 || m[1] != "apache2" {
		t.Fatalf("owner: %v", m)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = listener.Close() }()
	address := listener.Addr().(*net.TCPAddr)
	bin := t.TempDir()
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0700); err != nil {
			t.Fatal(err)
		}
	}
	const noProcess = `State Recv-Q Send-Q Local Address:Port Peer Address:Port\nLISTEN 0 128 0.0.0.0:80 0.0.0.0:*\n`
	write("ss", "#!/bin/sh\ncase \" $*\" in\n  *-ltnp*) printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\\nLISTEN 0 128 0.0.0.0:80 0.0.0.0:* users:((\"apache2\",pid=123,fd=4))\\n' ;;\n  *) printf '"+noProcess+"' ;;\nesac\n")
	write("sudo", "#!/bin/sh\nexit 1\n")
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	if owner := occupiedPortOwner(installPort{"127.0.0.1", address.Port}); owner != "apache2" {
		t.Fatalf("owner from ss -ltnp = %q", owner)
	}
	// Only root's ss can see the process: unprivileged ss shows the listener
	// without a process, sudo -n ss -ltnp names it.
	write("ss", "#!/bin/sh\nprintf '"+noProcess+"'\n")
	write("sudo", "#!/bin/sh\nprintf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\\nLISTEN 0 128 0.0.0.0:80 0.0.0.0:* users:((\"caddy\",pid=9,fd=3))\\n'\n")
	if owner := occupiedPortOwner(installPort{"127.0.0.1", address.Port}); owner != "caddy" {
		t.Fatalf("owner from sudo -n ss -ltnp = %q", owner)
	}
	// Neither ss can name the process: the listener is real but unnamed.
	write("sudo", "#!/bin/sh\nexit 1\n")
	if owner := occupiedPortOwner(installPort{"127.0.0.1", address.Port}); owner != "another program" {
		t.Fatalf("unnamed listener = %q", owner)
	}
	// A port without a listener must not be called occupied just because a
	// privileged bind or another local error failed.
	if strings.TrimSpace(occupiedPortOwner(installPort{"127.0.0.1", 0})) != "" {
		t.Fatal("free ephemeral port reported occupied")
	}
}
