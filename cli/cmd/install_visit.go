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
