package compose

import (
	"fmt"
	"strings"
)

// Profiles are the compose profiles accepted by ./sb start, stop and restart.
// Each profile selects a purpose-built subset of the stack from
// docker-compose*.yml.
var Profiles = []string{"all", "all_except_app", "app"}

// Services are the individual compose services accepted by the same commands.
// They mirror the service keys in docker-compose.yml and its included files.
var Services = []string{"db", "worker", "rest", "app", "proxy"}

// Target is a name ./sb start, stop or restart accepted. Service tells the two
// kinds apart: a service is named directly on the compose command line, while
// a profile is passed with --profile (down/up) or as the trailing service of
// `down` for the app-only profile.
type Target struct {
	Name    string
	Service bool
}

// ResolveTarget maps a user-supplied name to a compose target. Profiles are
// checked first because "app" is both a profile (the frontend) and a service
// (the same frontend container); the profile keeps its existing meaning.
func ResolveTarget(name string) (Target, error) {
	for _, profile := range Profiles {
		if name == profile {
			return Target{Name: name}, nil
		}
	}
	for _, service := range Services {
		if name == service {
			return Target{Name: name, Service: true}, nil
		}
	}
	return Target{}, fmt.Errorf("unknown target %q: profiles %s; services %s",
		name, strings.Join(Profiles, ", "), strings.Join(Services, ", "))
}

// StopArgs returns the docker compose arguments that stop this target. A
// service stops only that container; a profile brings its whole selection
// down.
func (t Target) StopArgs() []string {
	if t.Service {
		return []string{"stop", t.Name}
	}
	args := []string{"down", "--remove-orphans"}
	if t.Name == "app" {
		return append(args, t.Name)
	}
	return append([]string{"--profile", t.Name}, args...)
}

// UpPrefix returns the compose global options that select this target for up,
// pull and config. Services and the app-only profile are addressed by name
// instead, so they need no prefix.
func (t Target) UpPrefix() []string {
	if t.Service || t.Name == "app" {
		return nil
	}
	return []string{"--profile", t.Name}
}

// UpServiceArgs returns the trailing service name, if any, for up, pull and
// config.
func (t Target) UpServiceArgs() []string {
	if t.Service || t.Name == "app" {
		return []string{t.Name}
	}
	return nil
}
