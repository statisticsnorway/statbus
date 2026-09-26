package cmd

import (
	"fmt"
	"net"
	"strings"
	"testing"
	"time"
)

func TestDatabaseRouteFailureNamesProvider(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	conn, err := net.DialTimeout("tcp", address, time.Second)
	if err == nil {
		_ = conn.Close()
		t.Fatal("unavailable route accepted connection")
	}
	cause, fix := classifyInstallFailure("Migrations", fmt.Errorf("dial tcp %s: %w", address, err))
	for _, want := range []string{address, "web entry point"} {
		if !strings.Contains(cause, want) {
			t.Errorf("cause %q does not name %q", cause, want)
		}
	}
	if !strings.Contains(fix, "Start or repair the web entry point") || !strings.Contains(fix, "retry") {
		t.Errorf("missing recovery action: %q", fix)
	}
}

func TestPsqlDatabaseRouteFailureNamesProvider(t *testing.T) {
	for _, diagnostic := range []string{
		`psql: error: connection to server at "localhost" (::1), port 5432 failed: Connection refused`,
		`psql: error: connection to server at "127.0.0.1" (127.0.0.1), port 5432 failed: Connection refused`,
	} {
		cause, fix := classifyInstallFailure("Migrations", fmt.Errorf("%s", diagnostic))
		if !strings.Contains(cause, ":5432") || !strings.Contains(cause, "web entry point") || !strings.Contains(fix, "retry") {
			t.Errorf("diagnostic %q classified as cause %q, fix %q", diagnostic, cause, fix)
		}
	}
}
