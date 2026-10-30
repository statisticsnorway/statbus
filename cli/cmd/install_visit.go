package cmd

// STATBUS-394 AC5: the last word of an install is whether a user can reach
// the advertised site. After verifyInstallServing proves every service runs
// and the API answers /ready, verifyAdvertisedSite fetches each origin the
// completion banner prints — the chosen name, connected to this box
// (127.0.0.1, never DNS or hairpin routing), HTTPS verified against the
// system trust store when the certificate is this install's to verify.

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// A visitCheck is one advertised origin and how a failure of it is treated.
type visitCheck struct {
	origin    string
	verifyTLS bool // verify the served certificate against the system trust store
	fatal     bool // a failure stops the install; otherwise it is reported as "HTTPS is not working yet"
}

const (
	// Caddy can still be loading or issuing the certificate when the step
	// table finishes, so the site check retries within a bounded budget.
	visitCheckBudget    = time.Minute
	visitCheckInterval  = 2 * time.Second
	visitAttemptTimeout = 10 * time.Second
)

// visitChecks plans the final site check from the generated configuration:
// the origins the banner advertises (installVisitOrigins, STATBUS-469), and
// which certificate setup the install generated for them. Plain HTTP and a
// supplied certificate (TLS_CERT_FILE/TLS_KEY_FILE in .env.config) are this
// install's own work, so a failure stops the install. An automatic ACME
// certificate is issued from outside after install (STATBUS-389: the operator
// owns reachability), so a failure is reported, not fatal. Development mode
// serves HTTPS with Caddy's internal CA (development.caddyfile.tmpl:
// `tls internal`), which no system trust store contains — verifying it would
// always fail without naming a real defect — so only the answer is checked.
func visitChecks(installDir string) []visitCheck {
	origins := installVisitOrigins(installDir)
	if len(origins) == 0 {
		return nil
	}
	env, _ := dotenv.Load(filepath.Join(installDir, ".env"))
	mode, _ := env.Get("CADDY_DEPLOYMENT_MODE")
	// TLS_CERT_FILE/TLS_KEY_FILE never reach the generated .env (only the
	// Caddy templates), so the certificate setup is read from .env.config.
	cfg, _ := dotenv.Load(filepath.Join(installDir, ".env.config"))
	certFile, _ := cfg.Get("TLS_CERT_FILE")
	keyFile, _ := cfg.Get("TLS_KEY_FILE")
	supplied := strings.TrimSpace(certFile) != "" && strings.TrimSpace(keyFile) != ""
	var checks []visitCheck
	for _, origin := range origins {
		if strings.HasPrefix(origin, "http://") {
			checks = append(checks, visitCheck{origin: origin, fatal: true})
			continue
		}
		switch {
		case mode == "development":
			checks = append(checks, visitCheck{origin: origin, verifyTLS: false, fatal: true})
		case supplied:
			checks = append(checks, visitCheck{origin: origin, verifyTLS: true, fatal: true})
		default:
			checks = append(checks, visitCheck{origin: origin, verifyTLS: true, fatal: false})
		}
	}
	return checks
}

// visitChecksForDir is the seam behind visitChecks.
var visitChecksForDir = visitChecks

// visitSystemRoots is a seam: the trust store the site check verifies
// certificates against. Tests substitute a pool holding the test CA.
var visitSystemRoots = x509.SystemCertPool

// verifyAdvertisedSite probes every advertised origin within budget. A fatal
// check that still fails at the deadline stops the install with the origins
// and reasons named. A failed non-fatal (ACME) check is returned as a warning
// and printed as "HTTPS is not working yet: <origin> <reason>", so install
// completes without claiming HTTPS works.
func verifyAdvertisedSite(installDir string, budget, interval time.Duration) (warnings []string, err error) {
	checks := visitChecksForDir(installDir)
	if len(checks) == 0 {
		return nil, nil
	}
	type failure struct {
		check  visitCheck
		reason string
	}
	deadline := time.Now().Add(budget)
	var failures []failure
	for {
		failures = failures[:0]
		for _, c := range checks {
			if reason := probeVisit(c); reason != "" {
				failures = append(failures, failure{c, reason})
			}
		}
		if len(failures) == 0 {
			for _, c := range checks {
				fmt.Printf("The advertised site %s answers.\n", c.origin)
			}
			for _, line := range publicDNSLines(context.Background(), installDir) {
				fmt.Println(line)
			}
			return nil, nil
		}
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(interval)
	}
	var fatalReasons []string
	for _, f := range failures {
		problem := f.check.origin + " " + f.reason
		if f.check.fatal {
			fatalReasons = append(fatalReasons, problem)
		} else {
			warnings = append(warnings, problem)
		}
	}
	for _, w := range warnings {
		fmt.Println("HTTPS is not working yet: " + w)
	}
	if len(fatalReasons) > 0 {
		return warnings, fmt.Errorf("the advertised site is not serving: %s", strings.Join(fatalReasons, "; "))
	}
	return warnings, nil
}

// publicDNSLookup asks a public resolver directly, never the local system
// resolver: an /etc/hosts entry (as setup writes for the site name) must not
// make the check agree with itself. Cloudflare first, then Google, UDP,
// three seconds each; A and AAAA together.
var publicDNSLookup = func(ctx context.Context, name string) ([]net.IP, error) {
	var lastErr error
	for _, server := range []string{"1.1.1.1:53", "8.8.8.8:53"} {
		server := server
		resolver := &net.Resolver{
			PreferGo: true,
			Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
				dialer := net.Dialer{Timeout: 3 * time.Second}
				return dialer.DialContext(ctx, "udp", server)
			},
		}
		queryCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		addrs, err := resolver.LookupIPAddr(queryCtx, name)
		cancel()
		if err != nil {
			lastErr = err
			continue
		}
		ips := make([]net.IP, 0, len(addrs))
		for _, addr := range addrs {
			ips = append(ips, addr.IP)
		}
		if len(ips) == 0 {
			lastErr = fmt.Errorf("no A or AAAA record")
			continue
		}
		return ips, nil
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no public resolver answered")
	}
	return nil, lastErr
}

// publicOutboundIP reports the address this box reaches the internet as.
var publicOutboundIP = func(ctx context.Context) (net.IP, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.ipify.org", nil)
	if err != nil {
		return nil, err
	}
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ipify answered HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64))
	if err != nil {
		return nil, err
	}
	ip := net.ParseIP(strings.TrimSpace(string(body)))
	if ip == nil {
		return nil, fmt.Errorf("ipify returned %q, not an address", strings.TrimSpace(string(body)))
	}
	return ip, nil
}

// interfaceAddresses lists this box's own addresses, for comparison with the
// public DNS answer.
var interfaceAddresses = func() ([]net.IP, error) {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return nil, err
	}
	ips := make([]net.IP, 0, len(addrs))
	for _, addr := range addrs {
		if network, ok := addr.(*net.IPNet); ok {
			ips = append(ips, network.IP)
		}
	}
	return ips, nil
}

// publicDNSLines compares the name's public answer with this server. It is a
// warning only: a first install must not fail because the operator's DNS,
// NAT or internet connection is not ready yet. Private and development
// deployments do not advertise a public name, so they are skipped.
func publicDNSLines(ctx context.Context, installDir string) []string {
	env, err := dotenv.Load(filepath.Join(installDir, ".env"))
	if err != nil {
		return nil
	}
	mode, _ := env.Get("CADDY_DEPLOYMENT_MODE")
	if mode != "standalone" {
		return nil
	}
	domain, _ := env.Get("SITE_DOMAIN")
	domain = strings.TrimSpace(domain)
	if !publicDomainName(domain) {
		return nil
	}
	ips, lookupErr := publicDNSLookup(ctx, domain)
	if lookupErr != nil || len(ips) == 0 {
		reason := "no answer"
		if lookupErr != nil {
			reason = oneLine(lookupErr.Error())
		}
		return []string{fmt.Sprintf("Public DNS for %s could not be checked: %s.", domain, reason)}
	}
	local, _ := interfaceAddresses()
	outbound, outboundErr := publicOutboundIP(ctx)
	for _, ip := range ips {
		if containsIP(local, ip) {
			return []string{fmt.Sprintf("Public DNS: %s points to %s (this server).", domain, ip)}
		}
	}
	if outboundErr == nil && outbound != nil {
		for _, ip := range ips {
			if ip.Equal(outbound) {
				// The name resolves to the address this box reaches the
				// internet as. That can be this box behind NAT, or another
				// machine sharing the address, so forwarding still matters.
				return []string{
					fmt.Sprintf("Public DNS: %s points to %s (this server).", domain, ip),
					fmt.Sprintf("Make sure ports 443 and 80 on %s are forwarded to this server.", ip),
				}
			}
		}
	}
	var server string
	if primary := primaryLocalAddress(local); primary != nil {
		server = fmt.Sprintf("this server is %s", primary)
	}
	if outboundErr == nil && outbound != nil {
		if server != "" {
			server += fmt.Sprintf(", reaching the internet as %s", outbound)
		} else {
			server = fmt.Sprintf("reaching the internet as %s", outbound)
		}
	}
	detail := ""
	if server != "" {
		detail = " (" + server + ")"
	}
	return []string{fmt.Sprintf("WARNING: Public DNS sends %s to %s, which is not this server%s. Visitors will not reach StatBus until DNS or port forwarding sends 443 and 80 here.", domain, ips[0], detail)}
}

// publicDomainName reports whether name is a public DNS name worth asking a
// public resolver about. Local names and bare addresses never are.
func publicDomainName(name string) bool {
	if name == "" || net.ParseIP(name) != nil || !strings.Contains(name, ".") {
		return false
	}
	lower := strings.ToLower(name)
	for _, suffix := range []string{".local", ".localhost", ".internal", ".test", ".example", ".invalid", ".home", ".lan"} {
		if strings.HasSuffix(lower, suffix) {
			return false
		}
	}
	return true
}

func containsIP(ips []net.IP, want net.IP) bool {
	for _, ip := range ips {
		if ip != nil && ip.Equal(want) {
			return true
		}
	}
	return false
}

// primaryLocalAddress picks the address to name in a mismatch warning,
// preferring an IPv4 address that is neither loopback nor link-local.
func primaryLocalAddress(ips []net.IP) net.IP {
	var fallback net.IP
	for _, ip := range ips {
		if ip == nil || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
			continue
		}
		if ip.To4() != nil {
			return ip
		}
		if fallback == nil {
			fallback = ip
		}
	}
	return fallback
}

func oneLine(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if s == "" {
		return "no answer"
	}
	return s
}

// probeVisit fetches the origin once and returns "" when it answered with a
// 2xx/3xx status, else a plain-words classification of what failed.
func probeVisit(c visitCheck) string {
	u, err := url.Parse(c.origin)
	if err != nil || u.Hostname() == "" {
		return "is not an address that can be fetched"
	}
	resp, err := visitClient(u, c.verifyTLS).Get(c.origin)
	if err != nil {
		return classifyVisitError(err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 400 {
		return ""
	}
	return fmt.Sprintf("answered with HTTP status %d", resp.StatusCode)
}

// visitClient builds the client a user on this box effectively has: the
// chosen name, but connected to this box. Every dial for the origin's
// host:port goes to 127.0.0.1 on the same port, so the answer proves this
// box serves the name without relying on DNS or hairpin routing. TLS
// verification uses the system trust store with ServerName set to the
// advertised name.
func visitClient(u *url.URL, verifyTLS bool) *http.Client {
	dialer := &net.Dialer{Timeout: visitAttemptTimeout}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			_, port, err := net.SplitHostPort(addr)
			if err != nil {
				return nil, err
			}
			return dialer.DialContext(ctx, network, net.JoinHostPort("127.0.0.1", port))
		},
	}
	if u.Scheme == "https" {
		tlsConfig := &tls.Config{ServerName: u.Hostname()}
		if verifyTLS {
			if roots, err := visitSystemRoots(); err == nil && roots != nil {
				tlsConfig.RootCAs = roots
			}
		} else {
			tlsConfig.InsecureSkipVerify = true
		}
		transport.TLSClientConfig = tlsConfig
	}
	return &http.Client{Transport: transport, Timeout: visitAttemptTimeout}
}

// classifyVisitError names, in plain operator words, why fetching the
// advertised origin failed.
func classifyVisitError(err error) string {
	var invalidErr x509.CertificateInvalidError
	if errors.As(err, &invalidErr) {
		return "its certificate is expired or not yet valid"
	}
	var unknownAuthority x509.UnknownAuthorityError
	if errors.As(err, &unknownAuthority) {
		return "its certificate is not trusted (signed by an unknown authority)"
	}
	var hostnameErr x509.HostnameError
	if errors.As(err, &hostnameErr) {
		return "its certificate does not cover this name"
	}
	return "did not answer"
}
