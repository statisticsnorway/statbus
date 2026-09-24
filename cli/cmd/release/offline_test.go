package releasecmd

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	dialContext := transport.DialContext
	transport.DialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
		host, _, err := net.SplitHostPort(address)
		if err != nil {
			return nil, fmt.Errorf("release command tests refuse network address %q: %w", address, err)
		}
		ip := net.ParseIP(host)
		if host != "localhost" && (ip == nil || !ip.IsLoopback()) {
			return nil, fmt.Errorf("release command tests refuse non-loopback network access to %s", address)
		}
		return dialContext(ctx, network, address)
	}
	http.DefaultTransport = transport
	os.Exit(m.Run())
}
