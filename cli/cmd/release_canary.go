package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// canarySlot names a canary deployment target for `./sb release stable`'s
// observational gate. Each slot lives behind SSH; the gate probes the
// remote `public.upgrade` table to confirm the about-to-be-promoted RC
// commit reached a 'completed' state on that slot.
//
// label: short identifier the operator types into STATBUS_SKIP_CANARY.
// sshTarget: passed to `ssh` as-is. Either an alias from ~/.ssh/config
//	(statbus_dev, statbus_demo, …) or user@host (statbus@rune.statbus.org).
//	Convention per AGENTS.md "Manual Server Access".
// dbName: the PostgreSQL database name on the slot. Matches the slot code
//	per the multi-tenant scheme (statbus_<slot>) for niue slots, or
//	statbus_<country-code> for standalone hosts.
type canarySlot struct {
	label     string
	sshTarget string
	dbName    string
}

// canarySlots is the v1 hardcoded list — two slots covering both
// deployment shapes:
//
//   - dev (niue / multi-tenant): small fixture, fast smoke-test;
//     catches structural breakage cheap.
//   - no (rune / standalone): production-scale fixture; catches
//     scale-dependent regressions (worker drain time, OOM behaviour,
//     systemd-timeout interactions) before the stable tag exists.
//
// Later expansion (extra countries, extra environments) belongs in a
// per-project config rather than a binary constant. v1 keeps it inline
// so the gate works without operator setup.
var canarySlots = []canarySlot{
	{label: "dev", sshTarget: "statbus_dev", dbName: "statbus_dev"},
	{label: "no", sshTarget: "statbus@rune.statbus.org", dbName: "statbus_no"},
}

// checkCanaryGates runs the canary observational gate for every slot in
// canarySlots, honouring STATBUS_SKIP_CANARY bypasses. Returns true iff
// every (non-skipped) slot reports a completed upgrade row for rcCommit.
//
// Per-slot result lines are printed at the standard preflight indent
// regardless of pass/fail so the operator gets a single coherent
// preflight transcript. Failure prints actionable Fix lines listing both
// the deploy mechanism (per AGENTS.md) and the bypass env var as
// recoveries.
//
// Probe shape: SSH to the slot, run `./sb psql -d <db> -t -A` with the
// SQL piped in via stdin. Stdin-piped SQL avoids the SSH+shell+psql
// quoting nightmare flagged in CLAUDE.md — no quote escaping across
// three layers, just bytes on a pipe. ConnectTimeout=10 + BatchMode=yes
// keeps the gate fast (caps total preflight cost ~30s in the
// double-failure case) and prevents password prompts that would hang
// the run.
func checkCanaryGates(rcCommit string) bool {
	skip := release.ParseSkipLabels(os.Getenv(release.SkipCanaryEnvVar))
	allOK := true
	for _, slot := range canarySlots {
		if skip[slot.label] {
			fmt.Println(release.FormatSkipLabelsLog(release.SkipCanaryEnvVar, slot.label))
			fmt.Printf("  ⚠ Canary %-3s — bypass active; upgrade verification NOT confirmed for this slot\n", slot.label)
			continue
		}
		if !checkOneCanary(slot, rcCommit) {
			allOK = false
		}
	}
	return allOK
}

// checkOneCanary runs the probe for a single slot and prints the result.
// Returns true on pass, false on any failure (SSH down, query empty,
// row present but state != completed).
//
// Three distinct failure shapes get distinct diagnostics so the operator
// knows whether to fix SSH, fix the deploy, or bypass:
//   - SSH connection failure → "can't connect to <target>" + SSH hints
//   - empty result → "no completed upgrade row for <commit>" + deploy hints
//   - psql/query error → raw stderr surfaced
func checkOneCanary(slot canarySlot, rcCommit string) bool {
	rcShort := rcCommit
	if len(rcShort) > 12 {
		rcShort = rcShort[:12]
	}

	// SQL is parameterised by rcCommit only. The commit_sha column has a
	// CHECK constraint ^[a-f0-9]{40}$ — git rev-parse always returns
	// that shape, so direct interpolation is safe (no operator-controlled
	// input reaches this).
	sql := fmt.Sprintf(
		"SELECT state || '|' || COALESCE(completed_at::text, '') "+
			"FROM public.upgrade "+
			"WHERE commit_sha = '%s' AND state = 'completed' "+
			"LIMIT 1;",
		rcCommit)

	cmd := exec.Command("ssh",
		"-o", "BatchMode=yes",
		"-o", "ConnectTimeout=10",
		slot.sshTarget,
		fmt.Sprintf("cd statbus && ./sb psql -d %s -t -A", slot.dbName))
	cmd.Stdin = strings.NewReader(sql)
	out, err := cmd.CombinedOutput()
	if err != nil {
		// SSH or remote psql failed. Surface the raw error to help
		// the operator distinguish "host unreachable" from "psql
		// crashed" from "auth failed".
		fmt.Printf("  ✗ Canary %-3s — probe failed: %v\n", slot.label, err)
		if trimmed := strings.TrimSpace(string(out)); trimmed != "" {
			fmt.Printf("      ssh output:\n        %s\n",
				strings.ReplaceAll(trimmed, "\n", "\n        "))
		}
		fmt.Printf("      Fix: check `ssh %s` reachability (BatchMode=yes; ConnectTimeout=10s applied).\n", slot.sshTarget)
		fmt.Printf("           Or bypass: %s=%s ./sb release stable\n", release.SkipCanaryEnvVar, slot.label)
		return false
	}

	result := strings.TrimSpace(string(out))
	if result == "" {
		// SSH worked, query returned no row — the canary either
		// hasn't deployed this commit yet, or the deploy didn't
		// complete (still in_progress, failed, rolled_back).
		fmt.Printf("  ✗ Canary %-3s — no completed upgrade row for %s on %s\n",
			slot.label, rcShort, slot.dbName)
		fmt.Printf("      Fix: deploy this commit to %s via your preferred mechanism, then retry:\n", slot.label)
		switch slot.label {
		case "dev":
			fmt.Println("        git push -f origin master:ops/cloud/deploy/dev")
		case "no":
			fmt.Println("        git push -f origin master:ops/standalone/deploy/rune-no")
		default:
			fmt.Printf("        (slot-specific deploy mechanism — see doc/CLOUD.md or AGENTS.md)\n")
		}
		fmt.Printf("        Wait for upgrade-service to complete, then re-run `./sb release stable`.\n")
		fmt.Printf("      Bypass (use sparingly — slot upgrade NOT verified): %s=%s ./sb release stable\n",
			release.SkipCanaryEnvVar, slot.label)
		return false
	}

	// Row present. Format: "state|completed_at" e.g. "completed|2026-05-21 23:14:32.567+00"
	parts := strings.SplitN(result, "|", 2)
	state := parts[0]
	completedAt := ""
	if len(parts) == 2 {
		completedAt = parts[1]
	}

	if state != "completed" {
		// Defensive: query has `AND state = 'completed'` so this
		// shouldn't happen, but if the slot returned something
		// unexpected (rowless EOF behaviour, multi-row, weird
		// psql output) surface it rather than silently passing.
		fmt.Printf("  ✗ Canary %-3s — unexpected state %q for %s on %s\n",
			slot.label, state, rcShort, slot.dbName)
		return false
	}

	// Tidy timestamp for human reading: trim fractional seconds + tz.
	displayTime := tidyCanaryTimestamp(completedAt)
	fmt.Printf("  ✓ Canary %-3s — commit %s completed on %s (at %s)\n",
		slot.label, rcShort, slot.dbName, displayTime)
	return true
}

// tidyCanaryTimestamp turns a psql timestamptz into a human-readable
// display string by parsing+formatting. Falls back to the raw input on
// parse failure so we never lose information.
//
// Format target: "2026-05-21 23:14:32 UTC" (per foreman's spec).
func tidyCanaryTimestamp(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return "<unknown>"
	}
	// psql -t -A emits e.g. "2026-05-21 23:14:32.567891+00". Try a
	// few layouts in order of likelihood.
	layouts := []string{
		"2006-01-02 15:04:05.999999-07",
		"2006-01-02 15:04:05.999999+00",
		"2006-01-02 15:04:05-07",
		"2006-01-02 15:04:05+00",
		"2006-01-02 15:04:05",
	}
	for _, layout := range layouts {
		if t, err := time.Parse(layout, s); err == nil {
			return t.UTC().Format("2006-01-02 15:04:05 UTC")
		}
	}
	return s
}
