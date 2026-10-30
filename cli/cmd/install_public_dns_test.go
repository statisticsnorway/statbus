package cmd

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func publicDNSFixture(t *testing.T, mode, domain string, lookup func(context.Context, string) ([]net.IP, error), outbound func(context.Context) (net.IP, error), local ...string) string {
	t.Helper()
	dir := t.TempDir()
	env := fmt.Sprintf("CADDY_DEPLOYMENT_MODE=%s\nSITE_DOMAIN=%s\n", mode, domain)
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0600); err != nil {
		t.Fatal(err)
	}
	oldLookup, oldOutbound, oldLocal := publicDNSLookup, publicOutboundIP, interfaceAddresses
	publicDNSLookup, publicOutboundIP = lookup, outbound
	interfaceAddresses = func() ([]net.IP, error) {
		ips := make([]net.IP, len(local))
		for i, s := range local {
			ips[i] = net.ParseIP(s)
		}
		return ips, nil
	}
	t.Cleanup(func() {
		publicDNSLookup, publicOutboundIP, interfaceAddresses = oldLookup, oldOutbound, oldLocal
	})
	return dir
}

func TestPublicDNSPointsAtThisServer(t *testing.T) {
	dir := publicDNSFixture(t, "standalone", "statbus.ubos.org",
		func(context.Context, string) ([]net.IP, error) { return []net.IP{net.ParseIP("196.0.117.82")}, nil },
		func(context.Context) (net.IP, error) { return net.ParseIP("196.0.117.82"), nil },
		"10.10.10.58", "196.0.117.82")
	want := []string{"Public DNS: statbus.ubos.org points to 196.0.117.82 (this server)."}
	if got := publicDNSLines(context.Background(), dir); strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("lines = %q, want %q", got, want)
	}
}

func TestPublicDNSMismatchWarns(t *testing.T) {
	dir := publicDNSFixture(t, "standalone", "statbus.ubos.org",
		func(context.Context, string) ([]net.IP, error) { return []net.IP{net.ParseIP("196.0.117.82")}, nil },
		func(context.Context) (net.IP, error) { return net.ParseIP("203.0.113.9"), nil },
		"10.10.10.58")
	want := []string{"WARNING: Public DNS sends statbus.ubos.org to 196.0.117.82, which is not this server (this server is 10.10.10.58, reaching the internet as 203.0.113.9). Visitors will not reach StatBus until DNS or port forwarding sends 443 and 80 here."}
	if got := publicDNSLines(context.Background(), dir); strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("lines = %q, want %q", got, want)
	}
}

func TestPublicDNSNATEqualAlsoRequiresForwarding(t *testing.T) {
	dir := publicDNSFixture(t, "standalone", "statbus.ubos.org",
		func(context.Context, string) ([]net.IP, error) { return []net.IP{net.ParseIP("203.0.113.9")}, nil },
		func(context.Context) (net.IP, error) { return net.ParseIP("203.0.113.9"), nil },
		"10.10.10.58")
	want := []string{
		"Public DNS: statbus.ubos.org points to 203.0.113.9 (this server).",
		"Make sure ports 443 and 80 on 203.0.113.9 are forwarded to this server.",
	}
	if got := publicDNSLines(context.Background(), dir); strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("lines = %q, want %q", got, want)
	}
}

func TestPublicDNSLookupFailureIsOneWarningLine(t *testing.T) {
	dir := publicDNSFixture(t, "standalone", "statbus.ubos.org",
		func(context.Context, string) ([]net.IP, error) {
			return nil, errors.New("no answer from 1.1.1.1 or 8.8.8.8")
		},
		func(context.Context) (net.IP, error) { return nil, errors.New("offline") },
		"10.10.10.58")
	want := []string{"Public DNS for statbus.ubos.org could not be checked: no answer from 1.1.1.1 or 8.8.8.8."}
	if got := publicDNSLines(context.Background(), dir); strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("lines = %q, want %q", got, want)
	}
}

func TestPublicDNSSkipsPrivateAndDevelopmentModes(t *testing.T) {
	for _, mode := range []string{"private", "development"} {
		dir := publicDNSFixture(t, mode, "statbus.ubos.org",
			func(context.Context, string) ([]net.IP, error) {
				t.Fatal("lookup must not run")
				return nil, nil
			},
			func(context.Context) (net.IP, error) {
				t.Fatal("outbound fetch must not run")
				return nil, nil
			})
		if got := publicDNSLines(context.Background(), dir); len(got) != 0 {
			t.Fatalf("%s mode produced %q", mode, got)
		}
	}
}

func TestPublicDNSSkipsNonPublicNames(t *testing.T) {
	for _, domain := range []string{"statbus.local", "localhost", "statbus.internal", "127.0.0.1"} {
		dir := publicDNSFixture(t, "standalone", domain,
			func(context.Context, string) ([]net.IP, error) {
				t.Fatal("lookup must not run")
				return nil, nil
			},
			func(context.Context) (net.IP, error) {
				t.Fatal("outbound fetch must not run")
				return nil, nil
			})
		if got := publicDNSLines(context.Background(), dir); len(got) != 0 {
			t.Fatalf("%s produced %q", domain, got)
		}
	}
}

func TestInstallTerminalWriterShowsPublicDNSLines(t *testing.T) {
	lines := []string{
		"Public DNS: statbus.ubos.org points to 196.0.117.82 (this server).",
		"Make sure ports 443 and 80 on 196.0.117.82 are forwarded to this server.",
		"WARNING: Public DNS sends statbus.ubos.org to 196.0.117.82, which is not this server (this server is 10.10.10.58, reaching the internet as 203.0.113.9). Visitors will not reach StatBus until DNS or port forwarding sends 443 and 80 here.",
		"Public DNS for statbus.ubos.org could not be checked: no answer from 1.1.1.1 or 8.8.8.8.",
	}
	input := strings.Join(lines, "\n") + "\n"
	if got := runTerminalFilter(t, input); got != input {
		t.Fatalf("public DNS lines hidden or altered:\n got:\n%s\nwant:\n%s", got, input)
	}
	for _, hostile := range []string{
		"Public DNS: statbus.ubos.org points to not-an-ip (this server).",
		"Public DNS for statbus.ubos.org could not be checked: line one\nline two",
		"Public DNS sends statbus.ubos.org somewhere else.",
	} {
		if got := runTerminalFilter(t, hostile+"\n"); got != "" {
			t.Fatalf("non-grammar public DNS line reached the terminal: %q", got)
		}
	}
}
