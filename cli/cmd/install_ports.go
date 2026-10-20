package cmd

import (
	"context"
	"fmt"
	"net"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
)

type installPort struct {
	host   string
	number int
}

var listenerProgram = regexp.MustCompile(`users:\(\("([^"]+)"`)
var safePortOwner = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// occupiedPortOwner observes a taken port and names the program holding it
// when ss can see one. We do not know what runs on the operator's machine,
// so the check only ever observes: a bind attempt, then ss to confirm a
// listener, then the process name from ss output — unprivileged first, then
// through sudo -n, which never asks for a password or stalls an unattended
// installation. No program is named from a guess or a hardcoded list.
var occupiedPortOwner = func(port installPort) string {
	address := net.JoinHostPort(port.host, strconv.Itoa(port.number))
	listener, err := net.Listen("tcp", address)
	if err == nil {
		_ = listener.Close()
		return ""
	}
	filter := fmt.Sprintf("( sport = :%d )", port.number)
	// A failed bind on a privileged port alone does not prove a listener exists.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	listeners, listenErr := exec.CommandContext(ctx, "ss", "-ltn", filter).Output()
	if listenErr != nil || !strings.Contains(string(listeners), "LISTEN") {
		return ""
	}
	out, _ := exec.CommandContext(ctx, "ss", "-ltnp", filter).Output()
	if matches := listenerProgram.FindSubmatch(out); len(matches) > 1 {
		return string(matches[1])
	}
	// A non-root user can see the listener but often not its process name.
	out, _ = exec.CommandContext(ctx, "sudo", "-n", "ss", "-ltnp", filter).Output()
	if matches := listenerProgram.FindSubmatch(out); len(matches) > 1 {
		return string(matches[1])
	}
	return "another program"
}

// portConflictGuidance is the one refusal shape for a taken port
// (STATBUS-521): an observation — the port, and the listener's program name
// when ss showed it — and what is ours: StatBus needs this port. It
// prescribes no command for the other program; stopping or moving it is the
// operator's call, on their machine, for software we know nothing about.
//
// Assembled from a numeric port and a process name discovered locally, never
// from Docker output or an arbitrary exception.
func portConflictGuidance(number int, owner string) string {
	// ss process names can contain arbitrary printable characters. Never pass
	// an unrecognized owner through the installer diagnostic boundary.
	if !safePortOwner.MatchString(owner) {
		owner = "another program"
	}
	return fmt.Sprintf("Port %d is in use by %s. StatBus needs this port. Stop that program or move it to another port.", number, owner)
}

func ownPublishedPort(statuses []serviceStatus, number int) bool {
	for _, status := range statuses {
		for _, publisher := range status.Publishers {
			if publisher.PublishedPort == number && publisher.Protocol == "tcp" {
				return true
			}
		}
	}
	return false
}

// checkInstallPorts refuses to continue when a port the generated settings
// bind is held by a program that is not this installation's own services.
// The ports and addresses checked are the ones the generated .env publishes
// (config.PlannedHostPortsInDir, the same computation that writes .env), so
// the check cannot drift from what the services bind (STATBUS-521).
func checkInstallPorts(dir string) error {
	planned, err := config.PlannedHostPortsInDir(dir)
	if err != nil {
		return fmt.Errorf("the ports to check could not be read from the configuration: %w", err)
	}
	for _, plannedPort := range planned {
		p := installPort{host: plannedPort.Host, number: plannedPort.Port}
		owner := occupiedPortOwner(p)
		if owner == "" {
			continue
		}
		statuses, probeErr := probeServiceStatuses(dir)
		if probeErr != nil {
			// The listener is independently confirmed even when Compose cannot tell
			// whether it belongs to this installation. Keep the diagnostic private
			// and give every owner shape the same terminal-safe port refusal.
			installDiagnostic(dir, "Docker port ownership probe for %d failed: %v", p.number, probeErr)
			return fmt.Errorf("%s Docker service ownership could not be checked. Your answers are saved. Then run the same install command again: %s", portConflictGuidance(p.number, owner), diskpolicy.RerunCommand())
		}
		if ownPublishedPort(statuses, p.number) {
			continue
		}
		return fmt.Errorf("%s Your answers are saved. Then run the same install command again: %s", portConflictGuidance(p.number, owner), diskpolicy.RerunCommand())
	}
	return nil
}
