package upgrade

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/invariants"
)

// Trigger identifies which path asked for the bundle. SSB triage uses it
// to know which upstream contract to hold the bundle against.
type Trigger string

const (
	// TriggerService — the upgrade service is gathering a bundle as part
	// of a failed/rolled_back state transition. Called from
	// (*Service).writeDiagnosticBundle.
	TriggerService Trigger = "service"

	// TriggerInstall — install.sh caught a non-zero exit from ./sb install.
	// The bundle includes install-terminal.txt so the wrapper can surface
	// the named invariant in the SYSTEM UNUSABLE banner.
	TriggerInstall Trigger = "install"

	// TriggerAdhoc — an operator invoked `./sb support gather` directly
	// (the "lifeline" path when the upgrade service is down). Behaves
	// like TriggerInstall with a different header so the triage reader
	// knows the bundle was operator-initiated, not failure-initiated.
	TriggerAdhoc Trigger = "adhoc"
)

// Support bundle — written beside the per-upgrade log as
// <name>.bundle.txt on failure terminal transitions. Plain-text,
// marker-sectioned (`=== name ===`) for grep-friendliness and
// AI-friendly line-range fetches. Operators attach the file to a
// support ticket; reading it in a browser just shows text/plain.
//
// Format is intentionally simple: each section starts with a marker
// line, body follows verbatim, a blank line separates sections. No
// escaping of the marker is needed — the marker shape `=== ... ===`
// is vanishingly unlikely in log tails, and a false positive only
// splits the visual section, never corrupts downstream tools.

const (
	bundleLogTailLines     = 500
	bundleJournalctlLines  = 200
	bundleGitLogCount      = 20
	bundleSectionCmdTimeout = 8 * time.Second
)

// Keys whose value must be redacted in the `redacted env` section.
// Case-insensitive; matches any substring so `POSTGRES_APP_PASSWORD`,
// `SLACK_WEBHOOK`, `PRIVATE_KEY`, `API_KEY`, etc. all land here.
var bundleEnvSecretKeyRe = regexp.MustCompile(`(?i)(PASSWORD|SECRET|TOKEN|WEBHOOK|PRIVATE_?KEY|API_?KEY)`)

// Inline redaction applied to the log-tail and journalctl-tail bodies.
// Scrubs accidental narration like "using token=abc123" → "using token=***REDACTED***".
var bundleInlineSecretRe = regexp.MustCompile(`(?i)(password|token|secret)=\S+`)

// writeDiagnosticBundle composes a support bundle beside the per-upgrade
// log and writes it atomically as <name>.bundle.txt. Called from every
// failure terminal-state transition (failUpgrade, rollback ABORT,
// rollback normal, completeInProgressUpgrade health-fail,
// recoverFromFlag crash-recovery) BEFORE the terminal UPDATE so an
// operator reading a `failed` or `rolled_back` row is guaranteed a
// sibling bundle.
//
// Non-fatal: failures are logged via progress.Write and the caller
// proceeds. The whole operation is wrapped in a 10s context so a hung
// docker/journalctl/git never blocks the upgrade pipeline's rollback.
func (d *Service) writeDiagnosticBundle(parent context.Context, id int, progress *ProgressLog) {
	if d.queryConn == nil {
		return // pre-connect failure path — no DB to query, no bundle
	}

	// Narrate via stderr rather than through the progress pointer.
	// In completeInProgressUpgrade the progress log is closed before
	// writeDiagnosticBundle is called, so progress.Write() would silently
	// fail to reach the log file. Stderr is always open.
	narrate := func(format string, args ...interface{}) {
		fmt.Fprintf(os.Stderr, "[%s] %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(format, args...))
	}

	ctx, cancel := context.WithTimeout(parent, 10*time.Second)
	defer cancel()

	var rowJSON string
	if err := d.queryConn.QueryRow(ctx,
		"SELECT to_jsonb(public.upgrade)::text FROM public.upgrade WHERE id = $1", id).
		Scan(&rowJSON); err != nil {
		narrate("Warning: bundle write skipped — could not read upgrade row id=%d: %v", id, err)
		return
	}

	logRelPath := progress.RelPath()
	if logRelPath == "" {
		// No on-disk log path means no sibling location — bundle can't
		// sit next to a log that doesn't exist.
		narrate("Warning: bundle write skipped — progress log has no RelPath (id=%d)", id)
		return
	}
	logAbsPath := progress.AbsPath()
	bundlePath := strings.TrimSuffix(logAbsPath, ".log") + ".bundle.txt"

	// Stage to a .tmp file, fsync, rename — a partial bundle never
	// appears beside a valid log.
	tmpPath := bundlePath + ".tmp"
	f, err := os.Create(tmpPath)
	if err != nil {
		narrate("Warning: bundle write failed (create %s): %v", tmpPath, err)
		return
	}
	bw := bufio.NewWriter(f)

	WriteBundleSections(ctx, bw, d.projDir, id, rowJSON, logAbsPath, TriggerService)

	if err := bw.Flush(); err != nil {
		narrate("Warning: bundle write failed (flush): %v", err)
		f.Close()
		os.Remove(tmpPath)
		return
	}
	if err := f.Sync(); err != nil {
		narrate("Warning: bundle write failed (fsync): %v", err)
		f.Close()
		os.Remove(tmpPath)
		return
	}
	if err := f.Close(); err != nil {
		narrate("Warning: bundle write failed (close): %v", err)
		os.Remove(tmpPath)
		return
	}
	if err := os.Rename(tmpPath, bundlePath); err != nil {
		narrate("Warning: bundle write failed (rename): %v", err)
		os.Remove(tmpPath)
		return
	}
	narrate("Support bundle written to %s", bundlePath)
	if progress != nil {
		progress.Write("Support bundle written to %s", bundlePath)
	}
}

// WriteBundleSections emits all sections to w in the canonical order.
// Extracted so bundle_test.go can drive the same writer against a byte
// buffer with a fixture row + env file, and so cli/cmd/support_bundle.go
// can call it without a live database connection.
//
// trigger identifies the path that asked for the bundle (service
// failure transition / install.sh wrapper / operator ad-hoc). It is
// embedded in the header so SSB triage knows the upstream contract.
// Install and adhoc triggers additionally emit install-terminal.txt
// so the wrapper's SYSTEM UNUSABLE banner has a named-invariant
// anchor even when the upgrade row does not exist.
func WriteBundleSections(ctx context.Context, w io.Writer, projDir string, id int, rowJSON, logAbsPath string, trigger Trigger) {
	// Pull summary fields out of the row JSON for the header line.
	// Best-effort — a parse failure produces a header with blanks.
	var rowMap map[string]interface{}
	_ = json.Unmarshal([]byte(rowJSON), &rowMap)
	sha12 := shortField(rowMap, "commit_sha", 12)
	state := stringField(rowMap, "state")

	bundleSection(w, fmt.Sprintf("bundle for upgrade id=%d commit=%s state=%s trigger=%s", id, sha12, state, trigger), "")
	bundleSection(w, fmt.Sprintf("generated %s", time.Now().UTC().Format(time.RFC3339)), "")
	bundleSection(w, "upgrade row (key=value)", bundleRowBody(rowMap))
	if trigger == TriggerInstall || trigger == TriggerAdhoc {
		bundleSection(w, "install-terminal.txt (named invariant that drove termination)", bundleInstallTerminalBody(projDir))
	}
	bundleSection(w, "invariants registered in the shipped binary", bundleInvariantsBody())
	bundleSection(w,
		fmt.Sprintf("log tail (last %d lines from %s)", bundleLogTailLines, filepath.Base(logAbsPath)),
		bundleLogTailBody(logAbsPath, bundleLogTailLines))
	bundleSection(w, "docker compose ps", bundleCommandBody(ctx, projDir, "docker", "compose", "ps"))
	bundleSection(w, "container log snapshot (pre-rollback capture)", bundleContainerLogsBody(projDir, logAbsPath))
	if body, ok := bundleJournalctlBody(ctx); ok {
		bundleSection(w,
			fmt.Sprintf("journalctl tail (last %d lines from statbus-upgrade)", bundleJournalctlLines),
			body)
	}
	bundleSection(w, fmt.Sprintf("git log -%d", bundleGitLogCount),
		bundleCommandBody(ctx, projDir, "git", "log", fmt.Sprintf("-%d", bundleGitLogCount), "--oneline", "--decorate"))
	bundleSection(w, "caddy config", bundleCaddyConfigBody(projDir))
	bundleSection(w, "redacted env", bundleRedactedEnvBody(projDir))
}

// bundleInvariantsBody dumps the runtime registry. Always emitted so a
// bundle reader can confirm which named invariants the binary was
// capable of checking at the moment the bundle was written.
func bundleInvariantsBody() string {
	var sb strings.Builder
	invariants.Dump(&sb)
	if sb.Len() == 0 {
		return "(registry is empty)"
	}
	return sb.String()
}

// bundleInstallTerminalBody reads <projDir>/tmp/install-terminal.txt,
// which install-path guard sites append to via invariants.MarkTerminal.
// Empty/absent file renders as a placeholder — the absence itself is
// diagnostic (install.sh may have fired after a SIGKILL that preceded
// any invariant site).
func bundleInstallTerminalBody(projDir string) string {
	body := invariants.ReadTerminal(projDir)
	if body == "" {
		return "(file absent — install terminated without reaching a named-invariant site; see log tail)"
	}
	return body
}

// bundleContainerLogsBody describes the per-service log snapshot taken
// by captureContainerLogs() at rollback time. Reports the directory path
// + file sizes, not the file contents — operators triaging from the
// bundle follow the path to read the verbatim per-service logs. This
// keeps the bundle size bounded (4 services × 500 lines could otherwise
// add tens of KB of low-signal output) while still surfacing the snapshot's
// existence and where to look.
func bundleContainerLogsBody(projDir, logAbsPath string) string {
	if logAbsPath == "" {
		return "(no log path — pre-connect failure path)"
	}
	base := strings.TrimSuffix(filepath.Base(logAbsPath), filepath.Ext(logAbsPath))
	dirRel := filepath.Join("tmp", "upgrade-logs", base+".containers")
	dirAbs := filepath.Join(projDir, dirRel)
	entries, err := os.ReadDir(dirAbs)
	if err != nil {
		return fmt.Sprintf("(no snapshot at %s: %v — capture may have failed or this row never ran rollback)", dirRel, err)
	}
	var sb strings.Builder
	fmt.Fprintf(&sb, "snapshot dir: %s\n", dirRel)
	for _, e := range entries {
		info, ierr := e.Info()
		if ierr != nil {
			continue
		}
		fmt.Fprintf(&sb, "  %s  %d bytes\n", e.Name(), info.Size())
	}
	return sb.String()
}

// bundleSection writes `=== name ===\nbody\n\n` uniformly. Empty body
// emits the marker line followed by a blank line — useful for header
// and timestamp sections that are headers only.
func bundleSection(w io.Writer, name, body string) {
	if body == "" {
		fmt.Fprintf(w, "=== %s ===\n\n", name)
		return
	}
	// Ensure the body ends with exactly one newline before the blank
	// separator so sections render uniformly regardless of whether the
	// producer remembered the trailing \n.
	trimmed := strings.TrimRight(body, "\n")
	fmt.Fprintf(w, "=== %s ===\n%s\n\n", name, trimmed)
}

// bundleRowBody formats the upgrade row as sorted `key: value` lines.
// Sorted keys keep unit-test assertions deterministic and make diffs
// between two bundles readable.
func bundleRowBody(row map[string]interface{}) string {
	if len(row) == 0 {
		return "(unavailable — could not parse upgrade row)"
	}
	keys := make([]string, 0, len(row))
	for k := range row {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var sb strings.Builder
	for _, k := range keys {
		fmt.Fprintf(&sb, "%s: %s\n", k, formatRowValue(row[k]))
	}
	return sb.String()
}

// formatRowValue stringifies a JSON value for the `upgrade row` section.
// Scalars render as their natural text; nulls render as `null`;
// anything else (shouldn't happen — no nested fields on public.upgrade)
// falls back to compact JSON so the line stays single-line.
func formatRowValue(v interface{}) string {
	if v == nil {
		return "null"
	}
	switch t := v.(type) {
	case string:
		return t
	case bool:
		if t {
			return "true"
		}
		return "false"
	case float64:
		// json.Unmarshal decodes all numbers as float64. Integer columns
		// (id, epoch timestamps) render without the trailing `.0` via %g.
		return fmt.Sprintf("%g", t)
	default:
		b, _ := json.Marshal(v)
		return string(b)
	}
}

// bundleLogTailBody reads the last n lines of the log file and runs
// them through the inline secret scrub. Returns a placeholder when the
// file is absent or unreadable so the bundle stays consistent.
func bundleLogTailBody(absPath string, n int) string {
	data, err := os.ReadFile(absPath)
	if err != nil {
		return fmt.Sprintf("(log unavailable: %v)", err)
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return bundleInlineSecretRe.ReplaceAllString(strings.Join(lines, "\n"), "$1=***REDACTED***")
}

// bundleCommandBody runs a helper command, bounded by ctx, and returns
// combined stdout+stderr. Prefixes the output with the command line so
// the bundle reader can verify exactly what was executed. Returns the
// error text in-band if the command fails — the section is still worth
// showing for diagnostic context.
func bundleCommandBody(parent context.Context, dir, name string, args ...string) string {
	ctx, cancel := context.WithTimeout(parent, bundleSectionCmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	prepareCmd(cmd)
	out, err := cmd.CombinedOutput()
	header := fmt.Sprintf("$ %s %s\n", name, strings.Join(args, " "))
	body := string(out)
	if err != nil {
		body += fmt.Sprintf("\n(command failed: %v)\n", err)
	}
	return header + body
}

// bundleJournalctlBody returns the tail of the statbus-upgrade unit's
// journal. (`"", false)` when the binary isn't available — caller skips
// the section entirely so bundles produced on non-systemd hosts don't
// carry a pointless empty stub.
func bundleJournalctlBody(parent context.Context) (string, bool) {
	if _, err := exec.LookPath("journalctl"); err != nil {
		return "", false
	}
	ctx, cancel := context.WithTimeout(parent, bundleSectionCmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "journalctl",
		"-u", "statbus-upgrade",
		"-n", fmt.Sprintf("%d", bundleJournalctlLines),
		"--no-pager")
	prepareCmd(cmd)
	out, err := cmd.CombinedOutput()
	body := string(out)
	if err != nil {
		// Binary present but errored — show the failure rather than
		// silently skipping, so operators see that journalctl is
		// unhappy (permission, missing unit, etc.).
		body += fmt.Sprintf("\n(journalctl failed: %v)\n", err)
	}
	return bundleInlineSecretRe.ReplaceAllString(body, "$1=***REDACTED***"), true
}

// bundleRedactedEnvBody emits `KEY=value` lines from <projDir>/.env,
// replacing the value with `***REDACTED***` whenever the key matches
// the secret pattern. Sorted for deterministic output. Returns a
// placeholder when the file can't be read.
func bundleRedactedEnvBody(projDir string) string {
	envPath := filepath.Join(projDir, ".env")
	f, err := dotenv.Load(envPath)
	if err != nil {
		return fmt.Sprintf("(env unavailable: %v)", err)
	}
	all := f.Parse()
	keys := make([]string, 0, len(all))
	for k := range all {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var sb strings.Builder
	for _, k := range keys {
		value := all[k]
		if bundleEnvSecretKeyRe.MatchString(k) {
			value = "***REDACTED***"
		}
		fmt.Fprintf(&sb, "%s=%s\n", k, value)
	}
	return sb.String()
}

// bundleCaddyConfigBody concatenates all .caddyfile files from
// caddy/config/ into a single body with sub-headers per file. These are
// generated files (gitignored) that capture the deployed Caddy routing,
// TLS, and proxy config — critical for diagnosing connection and
// certificate issues.
func bundleCaddyConfigBody(projDir string) string {
	configDir := filepath.Join(projDir, "caddy", "config")
	entries, err := os.ReadDir(configDir)
	if err != nil {
		return fmt.Sprintf("(caddy config unavailable: %v)", err)
	}

	var sb strings.Builder
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), "caddyfile") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(configDir, e.Name()))
		if err != nil {
			fmt.Fprintf(&sb, "--- %s ---\n(read error: %v)\n\n", e.Name(), err)
			continue
		}
		// Redact any inline secrets (e.g., basic_auth passwords, API tokens)
		content := bundleInlineSecretRe.ReplaceAllString(string(data), "$1=***REDACTED***")
		fmt.Fprintf(&sb, "--- %s ---\n%s\n", e.Name(), strings.TrimRight(content, "\n"))
	}
	if sb.Len() == 0 {
		return "(no .caddyfile files found in caddy/config/)"
	}
	return sb.String()
}

// shortField pulls a string column from the row map and truncates it
// to n characters for the bundle header.
func shortField(row map[string]interface{}, key string, n int) string {
	s := stringField(row, key)
	if len(s) > n {
		return s[:n]
	}
	return s
}

func stringField(row map[string]interface{}, key string) string {
	if row == nil {
		return ""
	}
	if v, ok := row[key].(string); ok {
		return v
	}
	return ""
}
