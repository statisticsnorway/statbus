package config

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

const (
	dbMemGiB = int64(1) << 30

	// dbMemFallback is used when Docker's memory cannot be measured. It is the
	// value every installation carried before STATBUS-557, so a failed
	// measurement never makes an existing box smaller than it already was.
	dbMemFallback = "4G"

	// legacyAutoDbMemLimitLine is the exact line gen("DB_MEM_LIMIT", "4G")
	// wrote into .env.config on every installation before STATBUS-557. It is
	// verbatim: no spaces around "=", no quotes, no inline comment. Only that
	// exact form is treated as a derived value and removed on the next
	// generate; anything else (a different value, or the same value marked
	// with a comment such as "DB_MEM_LIMIT=4G # pinned") is the operator's
	// statement and is kept. Documented in doc/DEPLOYMENT.md.
	legacyAutoDbMemLimitLine = "DB_MEM_LIMIT=4G"
)

// dbMemLimitSource records where DB_MEM_LIMIT came from, so the installer can
// report it and a later reader can tell a derived value from a decision.
type dbMemLimitSource string

const (
	dbMemSourceDerived  dbMemLimitSource = "derived"
	dbMemSourceOperator dbMemLimitSource = "operator"
)

// dockerMemTotalBytes measures the memory Docker can use, in bytes. It is a
// variable so tests can inject a size without a Docker daemon.
//
// `docker info` reports the memory available to the Docker engine: on Linux
// that is the host's RAM, on macOS and Windows it is the memory assigned to
// the Docker VM. Either is what the containers can actually consume, which is
// the quantity DB_MEM_LIMIT must divide.
var dockerMemTotalBytes = measureDockerMemTotal

func measureDockerMemTotal() (int64, error) {
	// Docker command construction belongs to internal/compose; this call is a
	// read-only query and never reaches the compose stack.
	cmd, err := compose.DockerCommandContext(context.Background(), ".", "info", "--format", "{{.MemTotal}}")
	if err != nil {
		return 0, fmt.Errorf("docker info: %w", err)
	}
	out, err := cmd.Output()
	if err != nil {
		return 0, fmt.Errorf("docker info: %w", err)
	}
	total, err := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse docker MemTotal %q: %w", strings.TrimSpace(string(out)), err)
	}
	if total <= 0 {
		return 0, fmt.Errorf("docker reported %d bytes of memory", total)
	}
	return total, nil
}

// deriveDbMemLimit returns the database memory limit for a deployment mode
// measured against totalBytes available to Docker.
//
// The shares follow what each mode is:
//   - standalone: the box exists for this instance, so it gets everything
//     except max(2 GiB, 25%) kept for the OS and the other containers.
//   - private: a cloud slot sharing a host, capped at the documented 8 GiB per
//     instance (doc/CLOUD.md) and at half the host, whichever is smaller.
//   - development: a bounded quarter, capped at 4 GiB, because a development
//     slot shares its box with the developer's other work and may deliberately
//     run small to surface memory-heavy queries.
//
// An unrecognized mode takes the development share: an unknown mode must not
// be able to claim most of the host.
//
// The result is a whole number of GiB, rounded down, with a floor of 1G so a
// PostgreSQL container is always left enough to start.
func deriveDbMemLimit(mode string, totalBytes int64) string {
	if totalBytes < 0 {
		totalBytes = 0
	}

	var allocated int64
	switch mode {
	case "standalone":
		headroom := totalBytes / 4
		if headroom < 2*dbMemGiB {
			headroom = 2 * dbMemGiB
		}
		allocated = totalBytes - headroom
	case "private":
		allocated = min64(totalBytes/2, 8*dbMemGiB)
	default: // development, and any unrecognized mode
		allocated = min64(totalBytes/4, 4*dbMemGiB)
	}

	allocated = allocated / dbMemGiB * dbMemGiB
	if allocated < dbMemGiB {
		allocated = dbMemGiB
	}
	// "G" is the unit computeDbMemory and Docker's mem_limit expect.
	return fmt.Sprintf("%dG", allocated/dbMemGiB)
}

// resolveDbMemLimit picks the database memory limit: the operator's explicit
// value when one exists, otherwise the derived one. A failed measurement
// falls back to dbMemFallback and returns the cause for the report.
func resolveDbMemLimit(mode, operatorValue string, hasOperatorValue bool) (limit string, source dbMemLimitSource, detectedBytes int64, measureErr error) {
	if hasOperatorValue {
		return operatorValue, dbMemSourceOperator, 0, nil
	}
	total, err := dockerMemTotalBytes()
	if err != nil {
		return dbMemFallback, dbMemSourceDerived, 0, err
	}
	return deriveDbMemLimit(mode, total), dbMemSourceDerived, total, nil
}

// hasLegacyAutoDbMemLimit reports whether the effective DB_MEM_LIMIT line in
// the raw .env.config content is the exact line gen() used to write. The last
// assignment wins, matching dotenv's own read semantics. See
// legacyAutoDbMemLimitLine for the rule and why it is this narrow.
func hasLegacyAutoDbMemLimit(rawConfig string) bool {
	last := ""
	found := false
	for _, raw := range strings.Split(rawConfig, "\n") {
		trimmed := strings.TrimSpace(raw)
		if strings.HasPrefix(trimmed, "#") {
			continue
		}
		key, _, ok := strings.Cut(trimmed, "=")
		if !ok || strings.TrimSpace(key) != "DB_MEM_LIMIT" {
			continue
		}
		last = trimmed
		found = true
	}
	return found && last == legacyAutoDbMemLimitLine
}

// dbMemLimitReport is the single line the installer prints for the Settings
// step: what was detected, the mode, and what was allocated. An operator
// override needs no detection, so it reports only the mode and the value.
func dbMemLimitReport(cfg *ConfigEnv) string {
	if cfg.DbMemLimitSource == dbMemSourceOperator {
		return fmt.Sprintf("DB memory: mode %s, operator override %s", cfg.CaddyDeploymentMode, cfg.DbMemLimit)
	}
	if cfg.DbMemDetectErr != nil {
		return fmt.Sprintf("DB memory: could not measure memory available to Docker (%v); assuming %s, mode %s, allocated %s",
			cfg.DbMemDetectErr, dbMemFallback, cfg.CaddyDeploymentMode, cfg.DbMemLimit)
	}
	return fmt.Sprintf("DB memory: detected %s, mode %s, allocated %s",
		formatGiBAmount(cfg.DbMemDetectedBytes), cfg.CaddyDeploymentMode, cfg.DbMemLimit)
}

func formatGiBAmount(bytes int64) string {
	if bytes%dbMemGiB == 0 {
		return fmt.Sprintf("%d GiB", bytes/dbMemGiB)
	}
	return fmt.Sprintf("%.1f GiB", float64(bytes)/float64(dbMemGiB))
}
