package cmd

import (
	"context"
	"fmt"
	"net"
	"time"
)

// assessInstallDomain consults a public resolver, never /etc/hosts. DNS is
// evidence about the name, not proof that this host accepts inbound traffic.
func assessInstallDomain(domain string, lookup func(context.Context, string) ([]net.IP, error)) string {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	addresses, err := lookup(ctx, domain)
	if err != nil || len(addresses) == 0 {
		return fmt.Sprintf("%s is not confirmed in public DNS, so an automatic public certificate cannot be promised. Use local development for testing, or publish the name and allow inbound port 80 before using standalone.", domain)
	}
	return fmt.Sprintf("%s appears in public DNS; external access on port 80 has not been checked, so an automatic public certificate is not yet confirmed.", domain)
}

func publicDomainLookup(ctx context.Context, domain string) ([]net.IP, error) {
	resolver := net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, "udp", "1.1.1.1:53")
	}}
	return resolver.LookupIP(ctx, "ip", domain)
}
