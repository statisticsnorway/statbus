package config

import (
	"bytes"
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// SiteDomainLabel is the docker label the proxy service carries with its
// slot's SITE_DOMAIN (caddy/docker-compose.yml), so a slot can see which
// running slots on the same machine answer for which domain.
const SiteDomainLabel = "org.statbus.site_domain"

// SiteDomainOwner is a running proxy container that carries SiteDomainLabel:
// its compose project and the checkout folder it was started from.
type SiteDomainOwner struct{ Project, Folder string }

// runningSiteDomainOwners lists the running proxy containers labelled with
// domain. A variable so tests do not depend on the machine's docker.
var runningSiteDomainOwners = func(domain string) ([]SiteDomainOwner, error) {
	// Docker command construction belongs to internal/compose; this is a
	// read-only query of running containers.
	cmd, err := compose.DockerCommandContext(context.Background(), ".", "ps",
		"--filter", "label="+SiteDomainLabel+"="+domain,
		"--format", `{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.project.working_dir"}}`,
	)
	if err != nil {
		return nil, err
	}
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	var owners []SiteDomainOwner
	for _, line := range strings.Split(string(bytes.TrimSpace(out)), "\n") {
		if line == "" {
			continue
		}
		project, folder, _ := strings.Cut(line, "\t")
		owners = append(owners, SiteDomainOwner{Project: project, Folder: folder})
	}
	return owners, nil
}

// RefuseSharedSiteDomain stops a slot from using a SITE_DOMAIN that another
// running slot on this machine already uses (STATBUS-631). The sign-in
// cookies are named 'statbus' and 'statbus-refresh' in every slot, and
// browsers keep cookies per host name, not per port, so two slots on one
// domain sign each other out. One SITE_DOMAIN per slot is the rule that keeps
// the names fixed (4b4dc87f9).
//
// This is an early, friendly message, not the guarantee. It sees only running
// containers, and only ones whose proxy carries the label, and it gives way
// when docker cannot be asked. Production and cloud must not rely on it: on a
// cloud host the guarantee is the host Caddy, which imports every slot's
// public.caddyfile and refuses the whole configuration ("ambiguous site
// definition") when two slots declare the same domain; a standalone box has
// one slot. It runs in every mode only so the rule has no special case.
//
// project is this slot's compose project (COMPOSE_INSTANCE_NAME) and folder
// its checkout; containers from either are this slot's own.
func RefuseSharedSiteDomain(domain, project, folder string) error {
	owners, err := runningSiteDomainOwners(domain)
	if err != nil {
		return nil
	}
	own := filepath.Clean(folder)
	if abs, absErr := filepath.Abs(folder); absErr == nil {
		own = abs
	}
	for _, o := range owners {
		if o.Project == project || filepath.Clean(o.Folder) == own {
			continue
		}
		return newRefusal(fmt.Sprintf(
			"SITE_DOMAIN=%s is already used by the running slot %s (%s).\n"+
				"  Sign-in cookies are kept per domain, so two slots on one domain sign each other out.\n"+
				"  Give this slot its own SITE_DOMAIN in .env.config (and an /etc/hosts entry for it),\n"+
				"  or stop the other slot first.",
			domain, o.Project, o.Folder))
	}
	return nil
}

// RefuseSharedSiteDomainInDir runs RefuseSharedSiteDomain for the checkout's
// generated .env, for sb start: a slot whose domain was free at generate
// time may meet another slot started on it since. A checkout without a
// generated .env has nothing to compare and passes.
func RefuseSharedSiteDomainInDir(projDir string) error {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return nil
	}
	domain, _ := f.Get("SITE_DOMAIN")
	project, _ := f.Get("COMPOSE_INSTANCE_NAME")
	if domain == "" {
		return nil
	}
	return RefuseSharedSiteDomain(domain, project, projDir)
}
