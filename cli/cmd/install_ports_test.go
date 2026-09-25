package cmd

import (
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPortConflictGuidance(t *testing.T) {
	for _, owner := range []string{"python3", "another program"} {
		message := portConflictGuidance(80, owner)
		if !strings.Contains(message, "port 80 is in use by "+owner) || !strings.Contains(message, "sudo ") {
			t.Fatalf("missing actionable port cause: %s", message)
		}
	}
	message := servicePortConflictCause(errors.New("the web server (proxy) could not publish host port 80/tcp; port listener unavailable"))
	if !strings.Contains(message, "port 80 is in use by") || !strings.Contains(message, "sudo ") {
		t.Fatalf("service port failure lost actionable cause: %s", message)
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
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("CADDY_DEPLOYMENT_MODE=development\nDEPLOYMENT_SLOT_CODE=local\nDEPLOYMENT_SLOT_PORT_OFFSET=1\n"), 0600); err != nil {
		t.Fatal(err)
	}
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
	if err := checkInstallPorts(dir); err == nil || !strings.Contains(err.Error(), "port 3014 is in use by another program") {
		t.Fatalf("foreign listener not refused: %v", err)
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return nil, errors.New("compose unavailable") }
	if err := checkInstallPorts(dir); err == nil || !strings.Contains(err.Error(), "port 3014 is in use") || !strings.Contains(err.Error(), "could not ask Docker") || !strings.Contains(err.Error(), "compose unavailable") || !strings.Contains(err.Error(), "Your answers are saved") || strings.Contains(err.Error(), "another program") {
		t.Fatalf("probe failure incorrectly blamed a foreign program: %v", err)
	}
	occupiedPortOwner = func(installPort) string { return "" }
	if err := checkInstallPorts(dir); err != nil {
		t.Fatalf("free ports should not require Docker: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("CADDY_DEPLOYMENT_MODE=standalone\nDEPLOYMENT_SLOT_CODE=local\nDEPLOYMENT_SLOT_PORT_OFFSET=1\n"), 0600); err != nil {
		t.Fatal(err)
	}
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
	if err := checkInstallPorts(dir); err == nil || !strings.Contains(err.Error(), "port 80 is in use by another program") {
		t.Fatalf("standalone foreign port not refused: %v", err)
	}
	occupiedPortOwner = func(port installPort) string {
		if port.number == 80 {
			return "apache2"
		}
		return ""
	}
	probeServiceStatuses = func(string) ([]serviceStatus, error) { return nil, errors.New("compose unavailable") }
	bin := t.TempDir()
	if err := os.WriteFile(filepath.Join(bin, "systemctl"), []byte("#!/bin/sh\necho loaded\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	if err := checkInstallPorts(dir); err == nil || !strings.Contains(err.Error(), "port 80 is in use by apache2. Free the port with sudo systemctl disable --now apache2.") || !strings.Contains(err.Error(), "Your answers are saved. Then run the same install command again: curl -fsSL https://statbus.org/install.sh") {
		t.Fatalf("Apache remedy lost when Docker probe fails: %v", err)
	}
}

func TestOccupiedPortOwnerWithoutSudo(t *testing.T) {
	standalone := selectedInstallPorts("standalone", 1)
	if standalone[0].number != 80 || standalone[1].number != 443 || standalone[4].number != 5431 || standalone[5].number != 5432 {
		t.Fatalf("standalone ports: %+v", standalone)
	}
	private := selectedInstallPorts("private", 2)
	if private[0].number != 3020 || private[4].number != 3024 || private[6].number != 3026 {
		t.Fatalf("private ports: %+v", private)
	}
	if m := listenerProgram.FindStringSubmatch(`users:(("apache2",pid=123,fd=4))`); len(m) != 2 || m[1] != "apache2" {
		t.Fatalf("owner: %v", m)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = listener.Close() }()
	bin := t.TempDir()
	for name, body := range map[string]string{
		"ss":        "#!/bin/sh\nprintf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\\nLISTEN 0 128 0.0.0.0:80 0.0.0.0:*\\n'\n",
		"systemctl": "#!/bin/sh\nprintf 'apache2.service loaded active running Apache Web Server\\n'\n",
		"sudo":      "#!/bin/sh\nexit 1\n",
	} {
		if err := os.WriteFile(filepath.Join(bin, name), []byte(body), 0700); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	address := listener.Addr().(*net.TCPAddr)
	if owner := occupiedPortOwner(installPort{"127.0.0.1", address.Port}); owner != "apache2" {
		t.Fatalf("owner without sudo = %q", owner)
	}
	// A port without a listener must not be called occupied just because a
	// privileged bind or another local error failed.
	if strings.TrimSpace(occupiedPortOwner(installPort{"127.0.0.1", 0})) != "" {
		t.Fatal("free ephemeral port reported occupied")
	}
}
