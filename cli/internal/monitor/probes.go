package monitor

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/unitfloor"
)

// DBQuery runs one read-only SQL statement and returns its single text value.
// It is the seam between the checks and whichever process owns a database
// connection: the upgrader uses its existing connection, the CLI uses psql.
type DBQuery func(ctx context.Context, sql string) (string, error)

// The two queue/upgrade questions asked of the database. They are constants
// (not assembled at call sites) so the SQL is reviewable in one place.
const (
	// failedLastHour: tasks that finished failed in the last hour.
	// stuck: tasks still processing after an hour, which the task watchdog
	// will eventually reap but which already means the worker is not OK.
	workerTasksSQL = `SELECT
  (SELECT count(*) FROM worker.tasks WHERE state = 'failed' AND completed_at > now() - interval '1 hour')::text
  || ',' ||
  (SELECT count(*) FROM worker.tasks WHERE state = 'processing' AND process_start_at < now() - interval '1 hour')::text`

	// parked: an upgrade waiting for an operator (public.upgrade row).
	// failed: an upgrade that failed in the last day. Older failures have
	// already been superseded by later successful upgrades or dismissed.
	upgradeStateSQL = `SELECT
  (SELECT count(*) FROM public.upgrade WHERE recovery_parked_at IS NOT NULL AND state = 'in_progress')::text
  || ',' ||
  (SELECT count(*) FROM public.upgrade WHERE state = 'failed' AND completed_at > now() - interval '24 hours')::text`
)

// DefaultProbes wires the real probes for a box. version is the reading's
// version label; query supplies the database-backed checks.
func DefaultProbes(projectDir, version string, query DBQuery) Probes {
	return Probes{
		Services: ComposeServicesProbe(projectDir),
		API:      PostgRESTReadyProbe(projectDir),
		Site:     SiteProbe(projectDir),
		Disk:     DiskProbe(projectDir),
		Backups:  BackupsProbe(projectDir),
		Upgrader: UpgraderProbe(query),
		Worker:   WorkerProbe(query),
		Version:  version,
	}
}

// ComposeServicesProbe reports how many of the five serving containers are
// running and whether the database healthcheck is healthy. The upgrader is a
// systemd unit and is checked separately.
func ComposeServicesProbe(projectDir string) func(context.Context) (ServiceResult, error) {
	required := []string{"db", "proxy", "rest", "app", "worker"}
	return func(ctx context.Context) (ServiceResult, error) {
		ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
		defer cancel()
		cmd, err := compose.CommandContext(ctx, projectDir, "--profile", "all", "ps", "-a", "--format", "json")
		if err != nil {
			return ServiceResult{}, err
		}
		out, err := cmd.Output()
		if err != nil {
			return ServiceResult{}, err
		}
		statuses, err := parseComposeStatuses(out)
		if err != nil {
			return ServiceResult{}, err
		}
		byService := make(map[string]composeStatus, len(statuses))
		for _, status := range statuses {
			if previous, ok := byService[status.Service]; ok && previous.State == "running" {
				continue
			}
			byService[status.Service] = status
		}
		result := ServiceResult{Total: len(required)}
		for _, service := range required {
			status, ok := byService[service]
			if ok && status.State == "running" {
				result.Running++
			}
		}
		if db, ok := byService["db"]; ok {
			result.DBHealthy = db.Health == "healthy"
		}
		return result, nil
	}
}

type composeStatus struct {
	Service string `json:"Service"`
	State   string `json:"State"`
	Health  string `json:"Health"`
}

func parseComposeStatuses(out []byte) ([]composeStatus, error) {
	trimmed := strings.TrimSpace(string(out))
	if trimmed == "" {
		return nil, nil
	}
	if strings.HasPrefix(trimmed, "[") {
		var statuses []composeStatus
		if err := json.Unmarshal([]byte(trimmed), &statuses); err != nil {
			return nil, fmt.Errorf("parse compose ps json: %w", err)
		}
		return statuses, nil
	}
	var statuses []composeStatus
	for _, line := range strings.Split(trimmed, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var status composeStatus
		if err := json.Unmarshal([]byte(line), &status); err != nil {
			return nil, fmt.Errorf("parse compose ps json line: %w", err)
		}
		statuses = append(statuses, status)
	}
	return statuses, nil
}

// PostgRESTReadyProbe asks PostgREST's loopback admin /ready endpoint, the
// same proof install uses. A connection failure is a known "not ready"
// verdict, not an inability to measure.
func PostgRESTReadyProbe(projectDir string) func(context.Context) (bool, error) {
	return func(ctx context.Context) (bool, error) {
		env, err := dotenv.Load(filepath.Join(projectDir, ".env"))
		if err != nil {
			return false, err
		}
		bind, ok := env.Get("REST_ADMIN_BIND_ADDRESS")
		bind = strings.TrimSpace(bind)
		if !ok || bind == "" {
			return false, fmt.Errorf("REST_ADMIN_BIND_ADDRESS is not set")
		}
		ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://"+bind+"/ready", nil)
		if err != nil {
			return false, err
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			return false, nil
		}
		_ = resp.Body.Close()
		return resp.StatusCode == http.StatusOK, nil
	}
}

// SiteProbe fetches the advertised site from this box (127.0.0.1 at the
// advertised port, as the installer's visit check does) and reports the
// certificate's remaining days.
//
// TLS verification is deliberately skipped for THIS probe: the question is
// "does the site answer, and how long has its certificate got?", and an
// expired or internal-CA certificate must still yield the days figure so the
// check can call it critical. A trusted-name check would only turn that into
// a silent non-answer.
func SiteProbe(projectDir string) func(context.Context) (SiteResult, error) {
	return func(ctx context.Context) (SiteResult, error) {
		env, err := dotenv.Load(filepath.Join(projectDir, ".env"))
		if err != nil {
			return SiteResult{}, err
		}
		domain, ok := env.Get("SITE_DOMAIN")
		domain = strings.TrimSpace(domain)
		if !ok || domain == "" {
			return SiteResult{}, fmt.Errorf("SITE_DOMAIN is not set")
		}
		origin := "https://" + domain
		if mode, _ := env.Get("CADDY_DEPLOYMENT_MODE"); mode == "development" {
			port, _ := env.Get("CADDY_HTTPS_PORT")
			if strings.TrimSpace(port) == "" {
				port = "443"
			}
			origin = "https://" + net.JoinHostPort(domain, port)
		}
		parsed, err := url.Parse(origin)
		if err != nil || parsed.Hostname() == "" {
			return SiteResult{}, fmt.Errorf("SITE_DOMAIN is not a fetchable address")
		}
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		client := siteClient(parsed)
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, origin, nil)
		if err != nil {
			return SiteResult{}, err
		}
		resp, err := client.Do(req)
		if err != nil {
			return SiteResult{Answered: false}, nil
		}
		_ = resp.Body.Close()
		result := SiteResult{Answered: true}
		if resp.TLS != nil && len(resp.TLS.PeerCertificates) > 0 {
			result.HasCert = true
			days := int(time.Until(resp.TLS.PeerCertificates[0].NotAfter).Hours() / 24)
			if days < 0 {
				days = 0
			}
			result.CertDays = days
		}
		return result, nil
	}
}

func siteClient(origin *url.URL) *http.Client {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			_, port, err := net.SplitHostPort(addr)
			if err != nil {
				return nil, err
			}
			return dialer.DialContext(ctx, network, net.JoinHostPort("127.0.0.1", port))
		},
		TLSClientConfig: &tls.Config{
			ServerName:         origin.Hostname(),
			InsecureSkipVerify: true, // days-left and answer, not trust; see SiteProbe
		},
	}
	return &http.Client{Transport: transport, Timeout: 10 * time.Second}
}

// DiskProbe measures the filesystem Docker stores data on, falling back to
// the project directory when Docker cannot name its root (the same 20/40 GB
// policy then still applies). The path never reaches a detail string.
func DiskProbe(projectDir string) func(context.Context) (DiskResult, error) {
	return func(ctx context.Context) (DiskResult, error) {
		policy, err := diskpolicy.Load(projectDir)
		if err != nil {
			return DiskResult{}, err
		}
		path := projectDir
		if root, rootErr := diskpolicy.DockerRoot(ctx, projectDir); rootErr == nil {
			path = root
		}
		measurement, err := diskpolicy.Measure(path)
		if err != nil {
			return DiskResult{}, err
		}
		return DiskResult{
			FreeGB:        measurement.FreeGB,
			MinimumGB:     policy.MinimumGB,
			RecommendedGB: policy.RecommendedGB,
		}, nil
	}
}

// BackupsProbe reports the newest archive in ~/statbus-backups and the
// configured cadence. A missing directory is "no backups yet"; an unreadable
// one is an inability to measure.
func BackupsProbe(projectDir string) func(context.Context) (BackupResult, error) {
	return func(ctx context.Context) (BackupResult, error) {
		result := BackupResult{Enabled: true, Interval: 24 * time.Hour}
		if env, err := dotenv.Load(filepath.Join(projectDir, ".env")); err == nil {
			if value, ok := env.Get("BACKUP_ENABLED"); ok && value == "false" {
				result.Enabled = false
			}
			if value, ok := env.Get("BACKUP_INTERVAL"); ok {
				if interval, parseErr := time.ParseDuration(value); parseErr == nil && interval > 0 {
					result.Interval = interval
				}
			}
		}
		home, err := os.UserHomeDir()
		if err != nil {
			return BackupResult{}, err
		}
		entries, err := os.ReadDir(filepath.Join(home, "statbus-backups"))
		if os.IsNotExist(err) {
			return result, nil
		}
		if err != nil {
			return BackupResult{}, err
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			info, err := entry.Info()
			if err != nil {
				continue
			}
			if info.ModTime().After(result.Newest) {
				result.Newest = info.ModTime()
			}
		}
		return result, nil
	}
}

// UpgraderProbe reports the upgrader unit's state and any failed or parked
// upgrade. On a platform without systemd user units it reports not
// applicable, so a developer machine is not permanently red.
func UpgraderProbe(query DBQuery) func(context.Context) (UpgraderResult, error) {
	return func(ctx context.Context) (UpgraderResult, error) {
		if runtime.GOOS != "linux" {
			return UpgraderResult{Applicable: false}, nil
		}
		user := os.Getenv("USER")
		current := unitfloor.InstanceName(user)
		legacy := ""
		if user != "" {
			legacy = "statbus-upgrade@" + user + ".service"
		}
		active := unitActive(current) || unitActive(legacy)
		if query == nil {
			return UpgraderResult{Applicable: true, Active: active}, nil
		}
		out, err := query(ctx, upgradeStateSQL)
		if err != nil {
			return UpgraderResult{}, err
		}
		parked, failed := parseTwoCounts(out)
		return UpgraderResult{
			Applicable: true,
			Active:     active,
			Parked:     parked > 0,
			Failed:     failed > 0,
		}, nil
	}
}

func unitActive(unit string) bool {
	if unit == "" {
		return false
	}
	out, _ := exec.Command("systemctl", "--user", "is-active", unit).Output()
	state := strings.TrimSpace(string(out))
	return state == "active" || state == "activating"
}

// WorkerProbe reports failed and stuck worker tasks.
func WorkerProbe(query DBQuery) func(context.Context) (WorkerResult, error) {
	return func(ctx context.Context) (WorkerResult, error) {
		if query == nil {
			return WorkerResult{}, fmt.Errorf("no database query")
		}
		out, err := query(ctx, workerTasksSQL)
		if err != nil {
			return WorkerResult{}, err
		}
		failed, stuck := parseTwoCounts(out)
		return WorkerResult{FailedLastHour: failed, Stuck: stuck}, nil
	}
}

func parseTwoCounts(out string) (int, int) {
	parts := strings.Split(strings.TrimSpace(out), ",")
	if len(parts) != 2 {
		return 0, 0
	}
	first, _ := strconv.Atoi(strings.TrimSpace(parts[0]))
	second, _ := strconv.Atoi(strings.TrimSpace(parts[1]))
	return first, second
}

// PsqlQuery is the CLI's DBQuery: one read-only statement through the same
// psql route ./sb psql uses (host psql or docker compose exec, chosen by
// DOCKER_PSQL).
func PsqlQuery(projectDir string) DBQuery {
	return func(ctx context.Context, sql string) (string, error) {
		psqlPath, prefix, env, err := migrate.PsqlCommand(projectDir)
		if err != nil {
			return "", err
		}
		args := append(append([]string{}, prefix...), "-tA", "-c", sql)
		cmd, err := migrate.CommandContext(ctx, projectDir, psqlPath, args...)
		if err != nil {
			return "", err
		}
		cmd.Env = env
		out, err := cmd.Output()
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(out)), nil
	}
}
