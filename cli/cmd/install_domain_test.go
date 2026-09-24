package cmd

import (
	"context"
	"errors"
	"net"
	"strings"
	"testing"
)

func TestDomainAssessmentSeparatesDNSFromReachability(t *testing.T) {
	absent := assessInstallDomain("absent.example", func(context.Context, string) ([]net.IP, error) { return nil, errors.New("nxdomain") })
	if !strings.Contains(absent, "not confirmed in public DNS") || strings.Contains(absent, "checked external") {
		t.Fatal(absent)
	}
	present := assessInstallDomain("found.example", func(context.Context, string) ([]net.IP, error) { return []net.IP{net.ParseIP("203.0.113.8")}, nil })
	if !strings.Contains(present, "external access on port 80 has not been checked") {
		t.Fatal(present)
	}
}
