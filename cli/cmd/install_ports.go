package cmd

import (
	"fmt"
	"net"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

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

func occupiedPortOwner(port installPort) string {
	address := net.JoinHostPort(port.host, strconv.Itoa(port.number))
	listener, err := net.Listen("tcp", address)
	if err == nil {
		_ = listener.Close()
		return ""
	}
	out, _ := exec.Command("ss", "-ltnp", fmt.Sprintf("( sport = :%d )", port.number)).CombinedOutput()
	if matches := listenerProgram.FindSubmatch(out); len(matches) > 1 {
		return string(matches[1])
	}
	return "another program"
}

func checkInstallPorts(dir string) error {
	cfg, err := dotenv.Load(filepath.Join(dir, ".env.config"))
	if err != nil {
		return err
	}
	mode, _ := cfg.Get("CADDY_DEPLOYMENT_MODE")
	code, _ := cfg.Get("DEPLOYMENT_SLOT_CODE")
	offset := 1
	if raw, ok := cfg.Get("DEPLOYMENT_SLOT_PORT_OFFSET"); ok {
		if parsed, e := strconv.Atoi(raw); e == nil {
			offset = parsed
		}
	}
	own, _ := exec.Command("docker", "ps", "--format", "{{.Names}} {{.Ports}}").Output()
	for _, p := range selectedInstallPorts(mode, offset) {
		owner := occupiedPortOwner(p)
		if owner == "" {
			continue
		}
		ownPort := false
		for _, line := range strings.Split(string(own), "\n") {
			if strings.HasPrefix(line, "statbus-"+code+"-") && strings.Contains(line, fmt.Sprintf(":%d->", p.number)) {
				ownPort = true
				break
			}
		}
		if ownPort {
			continue
		}
		remedy := "Stop that program or change its port"
		if owner != "another program" && strings.IndexFunc(owner, func(r rune) bool {
			allowed := r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_'
			return !allowed
		}) < 0 {
			unit := owner
			if owner == "apache2" {
				unit = "apache2"
			}
			if out, err := exec.Command("systemctl", "show", unit+".service", "--property=LoadState", "--value").Output(); err == nil && strings.TrimSpace(string(out)) == "loaded" {
				remedy = "sudo systemctl disable --now " + unit
			}
		}
		return fmt.Errorf("port %d is in use by %s. %s. Your answers are saved. Then run the same install command again: curl -fsSL https://statbus.org/install.sh | bash", p.number, owner, remedy)
	}
	return nil
}
