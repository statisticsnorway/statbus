//go:build linux

package upgrade

import (
	"fmt"
	"net"
	"syscall"
	"time"
)

// newKeepaliveDialer returns a net.Dialer with aggressive TCP keepalive settings
// tuned for the upgrade service's long-lived PostgreSQL connections:
//
//   - TCP_KEEPIDLE  = 30s  (first probe after 30s idle; via net.Dialer.KeepAlive)
//   - TCP_KEEPINTVL = 10s  (10s between probes; via setsockopt in Control)
//   - TCP_KEEPCNT   = 3    (3 failed probes then RST; via setsockopt in Control)
//
// Dead-peer detection window: ~60s (30s idle + 3 × 10s).
func newKeepaliveDialer() *net.Dialer {
	return &net.Dialer{
		KeepAlive: 30 * time.Second, // TCP_KEEPIDLE
		Control: func(network, address string, c syscall.RawConn) error {
			var sockoptErr error
			if err := c.Control(func(fd uintptr) {
				if e := syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPINTVL, 10); e != nil {
					sockoptErr = fmt.Errorf("TCP_KEEPINTVL: %w", e)
					return
				}
				if e := syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPCNT, 3); e != nil {
					sockoptErr = fmt.Errorf("TCP_KEEPCNT: %w", e)
					return
				}
			}); err != nil {
				return err
			}
			return sockoptErr
		},
	}
}
