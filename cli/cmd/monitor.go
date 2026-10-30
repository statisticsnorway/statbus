package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/monitor"
)

// The monitor command is one health reading with three consumers: a person
// reading the terminal (the Nagios/Icinga plugin shape), a monitoring system
// calling the CLI through an agent (--format json), and an HTTP poller
// reading /monitor (Caddy serves the upgrader's cached reading).
//
// The upgrader refreshes the reading every 60 s. By default `status` reads
// that file; --live runs the checks now. When there is no reading (no
// upgrader yet) the command runs the checks and says so on stderr.
var (
	monitorStatusLive   bool
	monitorStatusFormat string
)

var monitorCmd = &cobra.Command{
	Use:   "monitor",
	Short: "One health reading for StatBus, for people and monitoring systems",
	Long: "Judges whether this StatBus is healthy and reports one answer.\n\n" +
		"Checks:\n" +
		"  services   5 serving containers running and the database healthy\n" +
		"  api        PostgREST answers its readiness endpoint\n" +
		"  site       SITE_DOMAIN answers over HTTPS; certificate days left\n" +
		"  disk       free space against the saved disk policy\n" +
		"  backups    age of the newest archive in ~/statbus-backups\n" +
		"  upgrader   unit active, no failed or parked upgrade\n" +
		"  worker     failed tasks in the last hour; stuck tasks\n\n" +
		"Subcommands:\n" +
		"  status [--live] [--format text|json]   report the cached reading, or run the checks now\n" +
		"  template [zabbix|uptime]                print a ready-made monitoring configuration\n\n" +
		"The text output is already a Nagios/Icinga plugin: its first line is\n" +
		"\"StatBus <STATUS> - <check> <detail>\", followed by one line per check.\n" +
		"Exit codes: 0 ok, 1 warning or upgrading, 2 critical, 3 unknown.\n\n" +
		"Examples:\n" +
		"  Nagios/Icinga:   ./sb monitor status\n" +
		"  Zabbix agent:    UserParameter=statbus.monitor,/home/statbus/statbus/sb monitor status --format json\n" +
		"  UptimeRobot/Kuma: https://<SITE_DOMAIN>/monitor (200 healthy, 503 critical or unknown)",
	GroupID: operationsGroupID,
	Args:    cobra.NoArgs,
	Run: func(command *cobra.Command, _ []string) {
		// The shared help template lists usage and commands but not Long, so
		// print the explanation the ticket requires before the command list.
		_, _ = fmt.Fprintln(command.OutOrStdout(), command.Long)
		_, _ = fmt.Fprintln(command.OutOrStdout())
		_ = command.Help()
	},
}

var monitorStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Report StatBus health (cached reading, or --live)",
	Long: "Reports the upgrader's cached health reading, or runs the checks now with --live.\n" +
		"A reading older than 3 minutes is reported as unknown. With no reading at all,\n" +
		"the checks run and the command says it did so on stderr.\n\n" +
		"Exit codes are the Nagios/Icinga contract: 0 ok, 1 warning or upgrading,\n" +
		"2 critical, 3 unknown.",
	Args: cobra.NoArgs,
	Run: func(command *cobra.Command, _ []string) {
		projectDir := config.ProjectDir()
		probes := monitor.DefaultProbes(projectDir, string(commitVersion), monitor.PsqlQuery(projectDir))
		code := runMonitorStatus(command.Context(), projectDir, monitorStatusLive, monitorStatusFormat,
			probes, time.Now(), command.OutOrStdout(), command.ErrOrStderr())
		os.Exit(code)
	},
}

var monitorTemplateCmd = &cobra.Command{
	Use:   "template [zabbix|uptime]",
	Short: "Print a ready-made monitoring configuration",
	Long: "Prints configuration that reads the same health reading this command reports.\n\n" +
		"  zabbix  a Zabbix 7 template (YAML export) whose master item runs\n" +
		"          ./sb monitor status --format json through an agent UserParameter\n" +
		"  uptime  the public /monitor URL and the HTTP statuses Uptime Kuma,\n" +
		"          UptimeRobot and similar monitors should expect\n\n" +
		"With no argument, lists the platforms.",
	Args: cobra.MaximumNArgs(1),
	RunE: func(command *cobra.Command, args []string) error {
		out := command.OutOrStdout()
		if len(args) == 0 {
			_, _ = fmt.Fprintln(out, "Platforms:")
			_, _ = fmt.Fprintln(out, "  zabbix   Zabbix 7 template (agent UserParameter)")
			_, _ = fmt.Fprintln(out, "  uptime   HTTP URL for Uptime Kuma, UptimeRobot and similar")
			return nil
		}
		switch args[0] {
		case "zabbix":
			_, _ = fmt.Fprint(out, monitor.ZabbixTemplate())
			return nil
		case "uptime":
			domain, err := monitorSiteDomain(config.ProjectDir())
			if err != nil {
				return err
			}
			_, _ = fmt.Fprint(out, monitor.UptimeTemplate(domain))
			return nil
		default:
			return fmt.Errorf("unknown template %q; the platforms are zabbix and uptime", args[0])
		}
	},
}

// runMonitorStatus writes the selected rendering and returns the process exit
// code. It is separated from the cobra Run hook so tests can drive it with
// fixture probes and captured output.
func runMonitorStatus(ctx context.Context, projectDir string, live bool, format string,
	probes monitor.Probes, now time.Time, out, errOut io.Writer) int {
	if format != "text" && format != "json" {
		_, _ = fmt.Fprintf(errOut, "unknown format %q; the formats are text and json\n", format)
		return exitUsage
	}
	reading, fromCache := loadMonitorReading(ctx, projectDir, live, probes, now)
	if !live && !fromCache {
		_, _ = fmt.Fprintln(errOut, "No cached reading found; ran the checks now.")
	}
	switch format {
	case "json":
		data, err := json.MarshalIndent(reading, "", "  ")
		if err != nil {
			_, _ = fmt.Fprintf(errOut, "encode reading: %v\n", err)
			return exitBinaryUnusable
		}
		_, _ = fmt.Fprintln(out, string(data))
	default:
		_, _ = fmt.Fprint(out, monitor.RenderText(reading, now))
	}
	return reading.Status.ExitCode()
}

// loadMonitorReading implements the cache-by-default rule: --live runs the
// checks; otherwise a cached reading is used, turning stale into unknown. No
// cache at all means run the checks now (fromCache=false tells the caller to
// say so).
func loadMonitorReading(ctx context.Context, projectDir string, live bool, probes monitor.Probes, now time.Time) (monitor.Reading, bool) {
	if live {
		return monitor.Run(ctx, probes), false
	}
	cached, err := monitor.ReadCache(projectDir)
	if err != nil {
		return monitor.Run(ctx, probes), false
	}
	if monitor.Stale(cached, now) {
		return monitor.AsStale(cached), true
	}
	return cached, true
}

// monitorSiteDomain reads the advertised name the uptime instructions point
// at. It is the one piece of site-specific text either template needs.
func monitorSiteDomain(projectDir string) (string, error) {
	env, err := dotenv.Load(filepath.Join(projectDir, ".env"))
	if err != nil {
		return "", fmt.Errorf("read SITE_DOMAIN: %w", err)
	}
	domain, ok := env.Get("SITE_DOMAIN")
	domain = strings.TrimSpace(domain)
	if !ok || domain == "" {
		return "", fmt.Errorf("SITE_DOMAIN is not set in .env; run ./sb config generate after configuring the site")
	}
	return domain, nil
}

func init() {
	monitorStatusCmd.Flags().BoolVar(&monitorStatusLive, "live", false, "run the checks now instead of reading the cached reading")
	monitorStatusCmd.Flags().StringVar(&monitorStatusFormat, "format", "text", "output format: text or json")
	monitorCmd.AddCommand(monitorStatusCmd)
	monitorCmd.AddCommand(monitorTemplateCmd)
	rootCmd.AddCommand(monitorCmd)
}
