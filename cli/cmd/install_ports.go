package cmd

import (
	"context"
	"fmt"
	"net"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

type installPort struct {
	host   string
	number int
}

func selectedInstallPorts(mode string, offset int) []installPort {
	base := 3000 + offset*10
	ports := []installPort{{"127.0.0.1", base}, {"127.0.0.1", base + 1}, {"127.0.0.1", base + 2}, {"127.0.0.1", base + 3}, {"127.0.0.1", base + 4}, {"127.0.0.1", base + 5}, {"127.0.0.1", base + 6}}
	if mode == "standalone" {
		ports[0] = installPort{"0.0.0.0", 80}
		ports[1] = installPort{"0.0.0.0", 443}
		ports[4] = installPort{"127.0.0.1", 5431}
		ports[5] = installPort{"0.0.0.0", 5432}
	}
	return ports
}

var listenerProgram = regexp.MustCompile(`users:\(\("([^"]+)"`)

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
	// Unprivileged ss often masks the process, but systemd reports active units.
	units, _ := exec.CommandContext(ctx, "systemctl", "list-units", "--type=socket,service", "--state=active", "--no-legend", "--plain").Output()
	for _, name := range []string{"apache2", "nginx", "caddy"} {
		if strings.Contains(string(units), name+".service") || strings.Contains(string(units), name+".socket") {
			return name
		}
	}
	out, _ := exec.CommandContext(ctx, "ss", "-ltnp", filter).Output()
	if matches := listenerProgram.FindSubmatch(out); len(matches) > 1 {
		return string(matches[1])
	}
	// A non-root user can see the listener but often not its process name.
	// sudo -n never asks for a password or stalls an unattended installation.
	out, _ = exec.CommandContext(ctx, "sudo", "-n", "ss", "-ltnp", filter).Output()
	if matches := listenerProgram.FindSubmatch(out); len(matches) > 1 {
		return string(matches[1])
	}
	return "another program"
}

// portConflictGuidance is assembled from a numeric port and a process name
// discovered locally, never from Docker output or an arbitrary exception.
func portConflictGuidance(number int, owner string) string {
	remedy := fmt.Sprintf("Find the listener with sudo ss -ltnp '( sport = :%d )', then stop that program to free port %d", number, number)
	if owner != "another program" && strings.IndexFunc(owner, func(r rune) bool {
		return (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') && r != '-' && r != '_'
	}) < 0 {
		if out, err := exec.Command("systemctl", "show", owner+".service", "--property=LoadState", "--value").Output(); err == nil && strings.TrimSpace(string(out)) == "loaded" {
			remedy = "Free the port with sudo systemctl disable --now " + owner
		} else {
			remedy = fmt.Sprintf("Free the port with sudo kill $(sudo lsof -tiTCP:%d -sTCP:LISTEN)", number)
		}
	}
	return fmt.Sprintf("port %d is in use by %s. %s.", number, owner, remedy)
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

func checkInstallPorts(dir string) error {
	cfg, err := dotenv.Load(filepath.Join(dir, ".env.config"))
	if err != nil {
		return err
	}
	mode, _ := cfg.Get("CADDY_DEPLOYMENT_MODE")
	offset := 1
	if raw, ok := cfg.Get("DEPLOYMENT_SLOT_PORT_OFFSET"); ok {
		if parsed, e := strconv.Atoi(raw); e == nil {
			offset = parsed
		}
	}
	for _, p := range selectedInstallPorts(mode, offset) {
		owner := occupiedPortOwner(p)
		if owner == "" {
			continue
		}
		statuses, probeErr := probeServiceStatuses(dir)
		if probeErr != nil {
			return fmt.Errorf("port %d is in use, but the installer could not ask Docker which service holds it: %w. Your answers are saved. Then run the same install command again: %s", p.number, probeErr, diskpolicy.RerunCommand())
		}
		if ownPublishedPort(statuses, p.number) {
			continue
		}
		return fmt.Errorf("%s Your answers are saved. Then run the same install command again: %s", portConflictGuidance(p.number, owner), diskpolicy.RerunCommand())
	}
	return nil
}
