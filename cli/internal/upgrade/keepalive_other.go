//go:build !linux

package upgrade

import (
	"net"
	"time"
)

// newKeepaliveDialer returns a net.Dialer with TCP keepalive enabled.
// On non-Linux platforms TCP_KEEPINTVL and TCP_KEEPCNT are not available
// via the stdlib syscall package, so only TCP_KEEPIDLE (KeepAlive field)
// is set. The kernel defaults for interval and count apply (~75s / 9 probes).
// Production deployments run on Linux; this stub exists for cross-compilation
// and local development on macOS.
func newKeepaliveDialer() *net.Dialer {
	return &net.Dialer{
		KeepAlive: 30 * time.Second, // TCP_KEEPIDLE — probe after 30s idle
	}
}
