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
