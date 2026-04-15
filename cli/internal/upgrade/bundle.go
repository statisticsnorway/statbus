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

	ctx, cancel := context.WithTimeout(parent, 10*time.Second)
	defer cancel()

	var rowJSON string
	if err := d.queryConn.QueryRow(ctx,
		"SELECT to_jsonb(public.upgrade)::text FROM public.upgrade WHERE id = $1", id).
		Scan(&rowJSON); err != nil {
		progress.Write("Warning: bundle write skipped — could not read upgrade row id=%d: %v", id, err)
		return
	}

	logRelPath := progress.RelPath()
	if logRelPath == "" {
		// No on-disk log path means no sibling location — bundle can't
		// sit next to a log that doesn't exist.
		progress.Write("Warning: bundle write skipped — progress log has no RelPath (id=%d)", id)
		return
	}
	logAbsPath := progress.AbsPath()
	bundlePath := strings.TrimSuffix(logAbsPath, ".log") + ".bundle.txt"

	// Stage to a .tmp file, fsync, rename — a partial bundle never
	// appears beside a valid log.
	tmpPath := bundlePath + ".tmp"
	f, err := os.Create(tmpPath)
	if err != nil {
		progress.Write("Warning: bundle write failed (create %s): %v", tmpPath, err)
		return
	}
	bw := bufio.NewWriter(f)

	writeBundleSections(ctx, bw, d.projDir, id, rowJSON, logAbsPath)

	if err := bw.Flush(); err != nil {
		progress.Write("Warning: bundle write failed (flush): %v", err)
		f.Close()
		os.Remove(tmpPath)
		return
	}
	if err := f.Sync(); err != nil {
		progress.Write("Warning: bundle write failed (fsync): %v", err)
		f.Close()
		os.Remove(tmpPath)
		return
	}
	if err := f.Close(); err != nil {
		progress.Write("Warning: bundle write failed (close): %v", err)
		os.Remove(tmpPath)
		return
	}
	if err := os.Rename(tmpPath, bundlePath); err != nil {
		progress.Write("Warning: bundle write failed (rename): %v", err)
		os.Remove(tmpPath)
		return
	}
	progress.Write("Support bundle written to %s", bundlePath)
}

// writeBundleSections emits all 8 sections to w in the canonical order.
// Extracted so bundle_test.go can drive the same writer against a byte
// buffer with a fixture row + env file.
func writeBundleSections(ctx context.Context, w io.Writer, projDir string, id int, rowJSON, logAbsPath string) {
	// Pull summary fields out of the row JSON for the header line.
	// Best-effort — a parse failure produces a header with blanks.
	var rowMap map[string]interface{}
	_ = json.Unmarshal([]byte(rowJSON), &rowMap)
	sha12 := shortField(rowMap, "commit_sha", 12)
	state := stringField(rowMap, "state")

	bundleSection(w, fmt.Sprintf("bundle for upgrade id=%d commit=%s state=%s", id, sha12, state), "")
	bundleSection(w, fmt.Sprintf("generated %s", time.Now().UTC().Format(time.RFC3339)), "")
	bundleSection(w, "upgrade row (key=value)", bundleRowBody(rowMap))
	bundleSection(w,
		fmt.Sprintf("log tail (last %d lines from %s)", bundleLogTailLines, filepath.Base(logAbsPath)),
		bundleLogTailBody(logAbsPath, bundleLogTailLines))
	bundleSection(w, "docker compose ps", bundleCommandBody(ctx, projDir, "docker", "compose", "ps"))
	if body, ok := bundleJournalctlBody(ctx); ok {
		bundleSection(w,
			fmt.Sprintf("journalctl tail (last %d lines from statbus-upgrade)", bundleJournalctlLines),
			body)
	}
	bundleSection(w, fmt.Sprintf("git log -%d", bundleGitLogCount),
		bundleCommandBody(ctx, projDir, "git", "log", fmt.Sprintf("-%d", bundleGitLogCount), "--oneline", "--decorate"))
	bundleSection(w, "redacted env", bundleRedactedEnvBody(projDir))
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
