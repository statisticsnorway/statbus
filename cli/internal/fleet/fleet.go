// Package fleet resolves an SSB-operated deployment slot to the box that
// hosts it.
//
// The registry is FLEET_REGISTRY in cloud.sh, the fleet operator tool's single
// list of boxes. Both deployment shapes appear there: the multi-tenant cloud
// slots on niue (statbus_<code>@niue.statbus.org) and standalone hosts
// (statbus@rune.statbus.org for Norway). Reading that list rather than
// synthesizing an address from the slot code keeps `./sb` and `./cloud.sh`
// from disagreeing about where a slot lives — STATBUS-562: Norway moved to
// rune and `sb db download no` still tried statbus_no@niue.
package fleet

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	// CloudFile is the fleet registry's filename in the checkout root.
	CloudFile = "cloud.sh"

	// RemoteWorkdir is the checkout directory on every fleet box, relative to
	// the service account's home. niue's slot users and the standalone boxes
	// all keep it in ~/statbus, so remote commands may change into it once the
	// registry has chosen user@host.
	RemoteWorkdir = "statbus"

	// entryFields is the FLEET_REGISTRY contract: code|group|ssh target|public
	// domain|auth.
	entryFields = 5
)

// Slot is one FLEET_REGISTRY entry.
type Slot struct {
	// Code is the short slot name an operator types (dev, no, ma, ...).
	Code string
	// Group is cloud (multi-tenant niue) or standalone (dedicated box).
	Group string
	// SSHTarget is user@host exactly as ssh takes it.
	SSHTarget string
	// Domain is the public domain the slot serves.
	Domain string
	// Auth is the fleet policy for the optional GitHub token: token or anon.
	Auth string
}

// SSHUserHost splits the registry's user@host target. The split is validated
// when the registry loads, so this only fails for a Slot built by hand.
func (s Slot) SSHUserHost() (user, host string, err error) {
	user, host, ok := strings.Cut(s.SSHTarget, "@")
	if !ok || user == "" || host == "" || strings.Contains(host, "@") {
		return "", "", fmt.Errorf("slot %q has an unusable SSH target %q (want user@host)", s.Code, s.SSHTarget)
	}
	return user, host, nil
}

// Database is the PostgreSQL database name on the slot. Every fleet box names
// it after the slot code, including the standalone boxes (Norway is
// statbus_no on rune).
func (s Slot) Database() string { return "statbus_" + s.Code }

// Registry is the parsed FLEET_REGISTRY.
type Registry struct {
	path  string
	slots map[string]Slot
}

// Load reads the fleet registry from the checkout's cloud.sh.
func Load(projectDir string) (*Registry, error) {
	return LoadFile(filepath.Join(projectDir, CloudFile))
}

// LoadFile parses the FLEET_REGISTRY array out of a cloud.sh-shaped file.
// Unreadable or malformed input is an error: falling back to a synthesized
// address is exactly the defect this package removes.
func LoadFile(path string) (*Registry, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("fleet registry: %w", err)
	}
	defer func() { _ = f.Close() }()

	registry := &Registry{path: path, slots: make(map[string]Slot)}
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	inRegistry := false
	foundRegistry := false
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := strings.TrimSpace(scanner.Text())
		if !inRegistry {
			if strings.HasPrefix(line, "FLEET_REGISTRY=(") {
				inRegistry = true
				foundRegistry = true
			}
			continue
		}
		if line == ")" {
			inRegistry = false
			break
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		slot, err := parseEntry(line)
		if err != nil {
			return nil, fmt.Errorf("%s:%d: %w", path, lineNo, err)
		}
		if _, dup := registry.slots[slot.Code]; dup {
			return nil, fmt.Errorf("%s:%d: duplicate fleet slot %q", path, lineNo, slot.Code)
		}
		registry.slots[slot.Code] = slot
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read fleet registry %s: %w", path, err)
	}
	if !foundRegistry {
		return nil, fmt.Errorf("%s: no FLEET_REGISTRY=(...) array", path)
	}
	if inRegistry {
		return nil, fmt.Errorf("%s: FLEET_REGISTRY array is not closed with ')'", path)
	}
	if len(registry.slots) == 0 {
		return nil, fmt.Errorf("%s: FLEET_REGISTRY is empty", path)
	}
	return registry, nil
}

// parseEntry reads one quoted "code|group|target|domain|auth" line.
func parseEntry(line string) (Slot, error) {
	if !strings.HasPrefix(line, `"`) || !strings.HasSuffix(line, `"`) || len(line) < 2 {
		return Slot{}, fmt.Errorf("registry entry %q is not a quoted string", line)
	}
	fields := strings.Split(line[1:len(line)-1], "|")
	if len(fields) != entryFields {
		return Slot{}, fmt.Errorf("registry entry %q has %d fields, want %d (code|group|ssh target|public domain|auth)", line, len(fields), entryFields)
	}
	slot := Slot{
		Code:      fields[0],
		Group:     fields[1],
		SSHTarget: fields[2],
		Domain:    fields[3],
		Auth:      fields[4],
	}
	for name, value := range map[string]string{
		"code": slot.Code, "group": slot.Group, "ssh target": slot.SSHTarget,
		"public domain": slot.Domain, "auth": slot.Auth,
	} {
		if value == "" {
			return Slot{}, fmt.Errorf("registry entry %q has an empty %s", line, name)
		}
	}
	if _, _, err := slot.SSHUserHost(); err != nil {
		return Slot{}, err
	}
	return slot, nil
}

// Lookup returns the slot's box. An unknown code is an error rather than a
// synthesized host, so a typo cannot silently target the wrong machine.
func (r *Registry) Lookup(code string) (Slot, error) {
	slot, ok := r.slots[code]
	if !ok {
		return Slot{}, fmt.Errorf("unknown box %q (not in %s)", code, r.path)
	}
	return slot, nil
}
