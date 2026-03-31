package upgrade

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"time"
)

// watchdog sends periodic sd_notify(WATCHDOG=1) to systemd.
// If the service hangs (stuck subprocess, deadlock), the pings stop,
// and systemd kills+restarts the service after WatchdogSec expires.
//
// Enable in the systemd unit file:
//
//	[Service]
//	WatchdogSec=300
//	WatchdogSignal=SIGKILL
//
// The service pings at half the watchdog interval to provide margin.
type watchdog struct {
	ticker   *time.Ticker
	done     chan struct{}
	socket   string
	interval time.Duration
}

// newWatchdog creates a watchdog if WATCHDOG_USEC and NOTIFY_SOCKET are set.
// Returns nil if not running under systemd with watchdog enabled.
func newWatchdog() *watchdog {
	socket := os.Getenv("NOTIFY_SOCKET")
	usecStr := os.Getenv("WATCHDOG_USEC")
	if socket == "" || usecStr == "" {
		return nil
	}

	usec, err := strconv.ParseInt(usecStr, 10, 64)
	if err != nil || usec <= 0 {
		return nil
	}

	// Ping at half the watchdog interval for safety margin
	interval := time.Duration(usec) * time.Microsecond / 2

	w := &watchdog{
		ticker:   time.NewTicker(interval),
		done:     make(chan struct{}),
		socket:   socket,
		interval: interval,
	}

	go w.loop()
	return w
}

func (w *watchdog) loop() {
	for {
		select {
		case <-w.ticker.C:
			w.ping()
		case <-w.done:
			return
		}
	}
}

func (w *watchdog) ping() {
	conn, err := net.Dial("unixgram", w.socket)
	if err != nil {
		fmt.Fprintf(os.Stderr, "watchdog: dial %s: %v\n", w.socket, err)
		return
	}
	defer conn.Close()
	conn.Write([]byte("WATCHDOG=1"))
}

// Stop stops the watchdog ticker.
func (w *watchdog) Stop() {
	w.ticker.Stop()
	close(w.done)
}

// sdNotify sends a message to the systemd NOTIFY_SOCKET.
// No-op if not running under systemd.
func sdNotify(state string) {
	socket := os.Getenv("NOTIFY_SOCKET")
	if socket == "" {
		return
	}
	conn, err := net.Dial("unixgram", socket)
	if err != nil {
		return
	}
	defer conn.Close()
	conn.Write([]byte(state))
}
