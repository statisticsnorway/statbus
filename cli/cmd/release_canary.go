package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/release"
)

// canaryRole says WHO is expected to install a candidate on a slot, and it is
// what makes one state mean two different things (STATBUS-245 AC#4).
//
// The same row — offered, not yet installed — is Norway's EXPECTED RESTING
// STATE (a person installs it on purpose, to exercise the real operator
// surface) and a FAULT on dev (the chain should already have installed it).
// A gate that reports both as one undifferentiated silence hides the most
// important distinction in the release process.
type canaryRole int

const (
	// roleAutomatic — the release chain installs this slot. Waiting is a fault.
	roleAutomatic canaryRole = iota
	// roleOperator — a HUMAN installs this slot, deliberately. Waiting is normal
	// and may legitimately last a day.
	roleOperator
)

// canarySlot names a canary deployment target for `./sb release stable`'s
// observational gate. Each slot lives behind SSH; the gate probes the remote
// `public.upgrade` table for the about-to-be-promoted RC commit and reports
// WHAT IT FOUND rather than merely whether it was completed.
//
// label: short identifier the operator types into STATBUS_SKIP_CANARY.
// sshTarget: passed to `ssh` as-is. Either an alias from ~/.ssh/config
//
//	(statbus_dev, …) or user@host (statbus@rune.statbus.org).
//
// dbName: the PostgreSQL database name on the slot.
// role: who is expected to install here — see canaryRole.
// askWho: the human handle for AC#9. When the next move is "ask someone",
//
//	the gate must say WHO rather than leaving the reader to guess.
type canarySlot struct {
	label     string
	sshTarget string
	dbName    string
	role      canaryRole
	askWho    string
}

// canarySlots is the canary topology: exactly two slots, covering both
// deployment shapes and both roles.
//
//   - dev (niue / multi-tenant): the AUTOMATIC canary. The chain deploys it,
//     so anything other than "completed" is the chain's fault to investigate.
//   - no (rune / standalone): the OPERATOR canary. A person installs it, which
//     is the point — it exercises the surface a statistical office actually
//     uses. Waiting here is not a malfunction.
//
// Demo is deliberately NOT a canary slot: it tracks stable, so it can only
// confirm a release after promotion, which is too late to gate on.
var canarySlots = []canarySlot{
	{label: "dev", sshTarget: "statbus_dev", dbName: "statbus_dev", role: roleAutomatic, askWho: "the release chain (see the Release Fleet Orchestrator run for this tag)"},
	{label: "no", sshTarget: "statbus@rune.statbus.org", dbName: "statbus_no", role: roleOperator, askWho: "the Norway operator at SSB"},
}

// canaryOutcome is the FIVE-WAY answer (AC#2). It exists because four of these
// used to be one thing — "no completed row" — and the natural response to an
// unexplained silence is to re-run the gate and then hunt for a fault, usually
// in the wrong place.
type canaryOutcome string

const (
	canaryNotOffered       canaryOutcome = "NOT OFFERED"
	canaryAwaitingOperator canaryOutcome = "OFFERED, AWAITING OPERATOR"
	canaryOperatorStarted  canaryOutcome = "INSTALL STARTED"
	canaryAttemptFailed    canaryOutcome = "INSTALL ATTEMPT FAILED"
	canaryCompleted        canaryOutcome = "COMPLETED"
	// canarySuperseded — the box moved PAST this candidate: a newer one
	// displaced the offer. Nothing was tried and nothing failed.
	canarySuperseded canaryOutcome = "SUPERSEDED ON THE BOX"
	// canarySetAside — 'skipped' or 'dismissed': someone deliberately took this
	// candidate out of consideration on this box. Also not a failure, and
	// STATBUS-250's dev reset produces 'dismissed' ON PURPOSE at every reset.
	canarySetAside canaryOutcome = "SET ASIDE ON THE BOX"
)

// canaryProbe is what the box told us about this candidate.
type canaryProbe struct {
	found           bool
	state           string
	completedAt     string
	startedAt       string
	discoveredAt    string
	recoveryParked  string
	errorText       string
	checkInterval   string // configured discovery interval, e.g. "6h"
	lastDiscoveryAt string // newest discovered_at on the box, ANY release
}

// outcome classifies the probe. Parked is deliberately folded into the FAILED
// class rather than the started class: a parked row is stopped and waiting for a
// human decision, so rendering it as "in progress" would tell the reader to wait
// for something that will never move on its own.
func (p canaryProbe) outcome() canaryOutcome {
	if !p.found {
		return canaryNotOffered
	}
	switch p.state {
	case "completed":
		return canaryCompleted
	case "available":
		return canaryAwaitingOperator
	case "scheduled":
		return canaryOperatorStarted
	case "in_progress":
		if strings.TrimSpace(p.recoveryParked) != "" {
			return canaryAttemptFailed
		}
		return canaryOperatorStarted
	case "failed", "rolled_back":
		return canaryAttemptFailed
	case "superseded":
		// A newer candidate displaced this offer (service.go sets this on an
		// 'available' row). Reading this as "tried and did not succeed" would
		// send the operator hunting an upgrade log for a failure that never
		// happened.
		return canarySuperseded
	case "skipped", "dismissed":
		// Deliberately taken out of consideration. STATBUS-250's dev reset
		// DISMISSES the wrecking candidate by design, so a healthy reset must
		// not make this gate shout that an install failed.
		return canarySetAside
	default:
		// An unknown state is NOT quietly treated as waiting. It is a thing we
		// do not understand about a box we are about to promote past, which is
		// closer to a fault than to patience.
		return canaryAttemptFailed
	}
}

// checkCanaryGates runs the canary observational gate for every slot,
// honouring STATBUS_SKIP_CANARY bypasses. Returns true iff every (non-skipped)
// slot reports a COMPLETED upgrade row for rcCommit.
//
// STATBUS-245: this adds EXPLANATION, never permission (AC#8). Exactly one
// outcome passes — completed — and the wait never ages into a pass (AC#7). A
// gate that timed out into green would silently delete the human canary step
// that is the whole reason the operator slot exists.
func checkCanaryGates(rcTag, rcCommit string) bool {
	skip := release.ParseSkipLabels(os.Getenv(release.SkipCanaryEnvVar))
	allOK := true
	for _, slot := range canarySlots {
		if skip[slot.label] {
			fmt.Println(release.FormatSkipLabelsLog(release.SkipCanaryEnvVar, slot.label))
			fmt.Printf("  ⚠ Canary %-3s — bypass active; upgrade verification NOT confirmed for this slot\n", slot.label)
			continue
		}
		if !checkOneCanary(slot, rcTag, rcCommit) {
			allOK = false
		}
	}
	return allOK
}

// checkOneCanary probes one slot and renders the outcome. Returns true only for
// COMPLETED.
func checkOneCanary(slot canarySlot, rcTag, rcCommit string) bool {
	rcShort := rcCommit
	if len(rcShort) > 12 {
		rcShort = rcShort[:12]
	}

	probe, err := runCanaryProbe(slot, rcCommit)
	if err != nil {
		fmt.Printf("  ✗ Canary %-3s — PROBE FAILED: could not read the box's state\n", slot.label)
		fmt.Printf("      %v\n", err)
		fmt.Printf("      Your next move: check reachability with `ssh %s` (the gate uses BatchMode=yes, ConnectTimeout=10s, so it never prompts).\n", slot.sshTarget)
		fmt.Printf("      This is a probe failure, NOT a verdict about the release: the box may be perfectly healthy and simply unreachable from here.\n")
		fmt.Printf("      Bypass (records that this slot was NOT verified): %s=%s ./sb release stable\n", release.SkipCanaryEnvVar, slot.label)
		return false
	}

	outcome := probe.outcome()
	if outcome == canaryCompleted {
		fmt.Printf("  ✓ Canary %-3s — %s: commit %s installed on %s (at %s)\n",
			slot.label, outcome, rcShort, slot.dbName, tidyCanaryTimestamp(probe.completedAt))
		return true
	}

	// Everything below refuses. The shape differs per outcome on purpose: a
	// pending human action must not look like a malfunction, and a failure must
	// never look like patience (AC#3, AC#5).
	fmt.Printf("  ✗ Canary %-3s — %s (commit %s on %s)\n", slot.label, outcome, rcShort, slot.dbName)
	printCanaryExplanation(slot, outcome, probe, rcTag)
	fmt.Printf("      Bypass (records that this slot was NOT verified): %s=%s ./sb release stable\n",
		release.SkipCanaryEnvVar, slot.label)
	return false
}

// printCanaryExplanation writes the reader's NEXT MOVE (AC#9). Every branch ends
// with a command to run, a person to ask, or a place to look — never a bare
// state name.
func printCanaryExplanation(slot canarySlot, outcome canaryOutcome, probe canaryProbe, rcTag string) {
	// NAME THE CANDIDATE. The obvious one-shot command resolves the newest tag
	// on the box's CHANNEL, not the candidate this gate is waiting on — so the
	// moment a newer RC exists, an operator following that instruction installs
	// a DIFFERENT version and the gate goes on refusing, inexplicably to them.
	// `register` accepts a tag or a full SHA and is the prerequisite for
	// `schedule`. Naming the target also keeps this gate and the observation
	// card saying the same thing to the same person.
	target := rcTag
	if target == "" {
		target = "<the candidate tag>"
	}
	operatorInstall := fmt.Sprintf("ssh %s 'cd statbus && ./sb upgrade register %s && ./sb upgrade schedule %s'",
		slot.sshTarget, target, target)

	switch outcome {
	case canaryNotOffered:
		fmt.Printf("      The box has no row for this commit at all — it has not yet DISCOVERED the release.\n")
		fmt.Print(canaryDiscoveryContext(probe))
		if slot.role == roleOperator {
			fmt.Printf("      Your next move: wait for the next discovery tick, or make it check now:\n")
			fmt.Printf("        ssh %s 'cd statbus && ./sb upgrade check && ./sb upgrade list'\n", slot.sshTarget)
			// Read the RUNNING service, not .env: loadConfig() runs only at
			// daemon startup, so the file can say one thing while the live
			// service still follows the old channel — and a grep of the file
			// then falsely confirms the box is fine. (The old hint here named
			// `./sb upgrade channel` with no argument, which could only ever
			// have errored; it required one.)
			fmt.Printf("      If it still does not appear, the release may not be published on this box's channel — check what the RUNNING service follows with\n"+
				"      `ssh %s \"journalctl --user -u statbus-upgrade@\\$USER | grep 'Upgrade service started' | tail -1\"`.\n", slot.sshTarget)
		} else {
			fmt.Printf("      This slot is installed by the release chain, so 'not offered' points at the CHAIN, not at the box.\n")
			fmt.Printf("      Your next move: look at %s\n", slot.askWho)
			fmt.Printf("        Then, to see what the box itself knows: ssh %s 'cd statbus && ./sb upgrade list'\n", slot.sshTarget)
		}

	case canaryAwaitingOperator:
		waited := canaryWaitedFor(probe.discoveredAt)
		if slot.role == roleOperator {
			// Norway's resting state. This is NOT a malfunction and must not
			// read like one.
			fmt.Printf("      NOTHING IS WRONG — this slot is installed BY A PERSON, on purpose, to exercise the real operator surface.\n")
			fmt.Printf("      The box has been holding the offer%s.\n", waited)
			fmt.Printf("      Your next move: ask %s\n", slot.askWho)
			fmt.Printf("        The exact command they run on the box — it NAMES this candidate:\n")
			fmt.Printf("          cd statbus && ./sb upgrade register %s && ./sb upgrade schedule %s\n", target, target)
			fmt.Printf("        Or, if you have access yourself: %s\n", operatorInstall)
		} else {
			// Same row, opposite meaning.
			fmt.Printf("      THIS IS A FAULT ON THIS SLOT: %s is installed by the release chain, so it should never sit waiting for a person.\n", slot.label)
			fmt.Printf("      The offer has been sitting unclaimed%s, which means the chain's deploy step did not run or did not reach this box.\n", waited)
			fmt.Printf("      Your next move: look at %s\n", slot.askWho)
			fmt.Printf("        To see the box's side: ssh %s 'cd statbus && ./sb upgrade list'\n", slot.sshTarget)
			fmt.Printf("        To unblock it by hand once you know why: %s\n", operatorInstall)
		}

	case canaryOperatorStarted:
		fmt.Printf("      An install IS RUNNING — this is progress, not a problem. Wait, then re-run this gate.\n")
		if started := tidyCanaryTimestamp(probe.startedAt); started != "<unknown>" {
			fmt.Printf("      Started at %s.\n", started)
		}
		fmt.Printf("      Your next move: watch it, and re-run `./sb release stable` when it finishes:\n")
		fmt.Printf("        ssh %s 'cd statbus && ./sb upgrade list'\n", slot.sshTarget)
		fmt.Printf("        Live log:  ssh %s 'cd statbus && tail -f tmp/upgrade-logs/*.log'\n", slot.sshTarget)

	case canarySuperseded:
		// NOTHING WAS TRIED. Sending this reader to an upgrade log would be
		// sending them to look for a failure that never happened.
		fmt.Printf("      The box has MOVED PAST this candidate — a newer one displaced the offer. Nothing was attempted and nothing failed.\n")
		fmt.Printf("      This usually means candidates are being cut faster than this box is asked to install them.\n")
		fmt.Printf("      Your next move: decide which candidate you are actually promoting.\n")
		fmt.Printf("        If the newer one: re-run `./sb release stable` against it instead.\n")
		fmt.Printf("        If THIS one: it must be re-offered on the box —\n")
		fmt.Printf("          %s\n", operatorInstall)
		fmt.Printf("        To see what the box has now: ssh %s 'cd statbus && ./sb upgrade list'\n", slot.sshTarget)

	case canarySetAside:
		// Also not a failure — and STATBUS-250's dev reset produces this state
		// deliberately, so shouting "install failed" here would make a healthy
		// reset look like a broken box.
		fmt.Printf("      This candidate was DELIBERATELY SET ASIDE on the box (state: %s) — skipped or dismissed by a person or by a reset. It is not a failure.\n", probe.state)
		fmt.Printf("      A dev reset dismisses the candidate it reset away from ON PURPOSE, so this can be the healthy end of a recovery rather than a fault.\n")
		fmt.Printf("      Your next move: find out who set it aside and why before overriding it.\n")
		fmt.Printf("        See the row and its timestamps: ssh %s 'cd statbus && ./sb upgrade list'\n", slot.sshTarget)
		fmt.Printf("        If it SHOULD run after all, re-offer it explicitly:\n")
		fmt.Printf("          %s\n", operatorInstall)

	case canaryAttemptFailed:
		// Deliberately the loudest branch: this needs ACTION, not time, and it
		// must never be mistaken for waiting.
		parked := strings.TrimSpace(probe.recoveryParked) != ""
		if parked {
			fmt.Printf("      THE INSTALL IS PARKED — it stopped at a deterministic failure and will NOT resume on its own. Waiting will not help.\n")
		} else {
			fmt.Printf("      THE INSTALL WAS TRIED AND DID NOT SUCCEED (state: %s). This needs ACTION, not time.\n", probe.state)
		}
		if e := strings.TrimSpace(probe.errorText); e != "" {
			fmt.Printf("      The box's own reason:\n        %s\n", strings.ReplaceAll(e, "\n", "\n        "))
		}
		fmt.Printf("      Your next move, in order:\n")
		fmt.Printf("        1. Read the box's upgrade log:  ssh %s 'cd statbus && ls -t tmp/upgrade-logs/ | head -3'\n", slot.sshTarget)
		fmt.Printf("        2. See the row in full:         ssh %s 'cd statbus && ./sb upgrade list'\n", slot.sshTarget)
		fmt.Printf("        3. Recover / re-attempt:        ssh %s 'cd statbus && ./sb install'\n", slot.sshTarget)
		fmt.Printf("      Do NOT promote past this: a canary that failed to install is the signal this gate exists to catch.\n")
	}
}

// canaryDiscoveryContext renders AC#6 — the check interval and when the box last
// discovered anything — so "not offered" carries a duration instead of being a
// bare absence.
//
// It says "last discovered a release", NOT "last checked", because that is what
// the data supports: a check that finds nothing new leaves no record. Claiming
// the stronger reading would be the same overstatement this gate exists to stop.
func canaryDiscoveryContext(probe canaryProbe) string {
	var b strings.Builder
	interval := strings.TrimSpace(probe.checkInterval)
	if interval == "" {
		interval = "<not recorded on this box>"
	}
	fmt.Fprintf(&b, "      Discovery: the box checks every %s.\n", interval)
	if last := tidyCanaryTimestamp(probe.lastDiscoveryAt); last != "<unknown>" {
		fmt.Fprintf(&b, "      It last DISCOVERED a release at %s%s (a check that finds nothing new leaves no record, so this is not the last check).\n",
			last, canaryWaitedFor(probe.lastDiscoveryAt))
	} else {
		fmt.Fprintf(&b, "      It has no record of ever discovering a release — which points at the channel or at connectivity, not at this candidate.\n")
	}
	return b.String()
}

// canaryWaitedFor renders " — N ago" for a psql timestamp, or "" when it cannot
// be parsed. Returned as a fragment so callers can compose a sentence.
func canaryWaitedFor(ts string) string {
	t, ok := parseCanaryTimestamp(ts)
	if !ok {
		return ""
	}
	d := time.Since(t)
	if d < 0 {
		return ""
	}
	return fmt.Sprintf(" for %s", humaniseCanaryDuration(d))
}

// humaniseCanaryDuration renders a duration the way a person waiting would say
// it. Days matter here: Norway's wait is legitimately measured in them.
func humaniseCanaryDuration(d time.Duration) string {
	switch {
	case d < time.Minute:
		return "less than a minute"
	case d < time.Hour:
		return fmt.Sprintf("%d minute(s)", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh%02dm", int(d.Hours()), int(d.Minutes())%60)
	default:
		days := int(d.Hours()) / 24
		hours := int(d.Hours()) % 24
		return fmt.Sprintf("%d day(s) %dh", days, hours)
	}
}

// runCanaryProbe asks the box for the candidate's row AND the discovery context
// in ONE ssh round trip.
//
// The row query no longer filters to state='completed' (AC#1) — that filter is
// what collapsed four distinct situations into "no row". Two labelled lines are
// requested so a missing row (the NOT OFFERED case) is naturally the absence of
// the ROW line rather than an ambiguous empty result.
//
// SQL is interpolated with rcCommit only, which carries a ^[a-f0-9]{40}$ CHECK
// constraint upstream — no operator-controlled input reaches this. Piped on
// stdin to avoid the SSH+shell+psql quoting layers (CLAUDE.md).
func runCanaryProbe(slot canarySlot, rcCommit string) (canaryProbe, error) {
	sql := fmt.Sprintf(`SELECT 'ROW|' || u.state
  || '|' || COALESCE(u.completed_at::text, '')
  || '|' || COALESCE(u.started_at::text, '')
  || '|' || COALESCE(u.discovered_at::text, '')
  || '|' || COALESCE(u.recovery_parked_at::text, '')
  || '|' || COALESCE(replace(u.error, E'\n', ' '), '')
FROM public.upgrade u WHERE u.commit_sha = '%s' ORDER BY u.id DESC LIMIT 1;
SELECT 'CTX|'
  || COALESCE((SELECT value FROM public.system_info WHERE key = 'upgrade_check_interval'), '')
  || '|' || COALESCE((SELECT max(discovered_at)::text FROM public.upgrade), '');`, rcCommit)

	cmd := exec.Command("ssh",
		"-o", "BatchMode=yes",
		"-o", "ConnectTimeout=10",
		slot.sshTarget,
		fmt.Sprintf("cd statbus && ./sb psql -d %s -t -A", slot.dbName))
	cmd.Stdin = strings.NewReader(sql)
	out, err := cmd.CombinedOutput()
	if err != nil {
		detail := strings.TrimSpace(string(out))
		if detail != "" {
			return canaryProbe{}, fmt.Errorf("%v\n      ssh output:\n        %s", err, strings.ReplaceAll(detail, "\n", "\n        "))
		}
		return canaryProbe{}, err
	}
	return parseCanaryProbeOutput(string(out)), nil
}

// parseCanaryProbeOutput turns the two labelled lines into a probe. Split out
// from the ssh call so the classification and rendering are testable without a
// network or a box.
func parseCanaryProbeOutput(out string) canaryProbe {
	var p canaryProbe
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "ROW|"):
			// Error text goes LAST and may itself contain '|', so the split is
			// bounded to keep the remainder intact.
			f := strings.SplitN(strings.TrimPrefix(line, "ROW|"), "|", 6)
			for len(f) < 6 {
				f = append(f, "")
			}
			p.found = true
			p.state, p.completedAt, p.startedAt, p.discoveredAt, p.recoveryParked, p.errorText = f[0], f[1], f[2], f[3], f[4], f[5]
		case strings.HasPrefix(line, "CTX|"):
			f := strings.SplitN(strings.TrimPrefix(line, "CTX|"), "|", 2)
			for len(f) < 2 {
				f = append(f, "")
			}
			p.checkInterval, p.lastDiscoveryAt = f[0], f[1]
		}
	}
	return p
}

// parseCanaryTimestamp parses a psql timestamptz across the layouts psql -t -A
// emits. Returns ok=false rather than a zero time so callers can omit the
// clause instead of printing a wrong one.
func parseCanaryTimestamp(s string) (time.Time, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return time.Time{}, false
	}
	layouts := []string{
		"2006-01-02 15:04:05.999999-07",
		"2006-01-02 15:04:05.999999+00",
		"2006-01-02 15:04:05-07",
		"2006-01-02 15:04:05+00",
		"2006-01-02 15:04:05",
	}
	for _, layout := range layouts {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// tidyCanaryTimestamp renders a psql timestamptz for humans, falling back to the
// raw input so information is never lost.
func tidyCanaryTimestamp(s string) string {
	if strings.TrimSpace(s) == "" {
		return "<unknown>"
	}
	if t, ok := parseCanaryTimestamp(s); ok {
		return t.UTC().Format("2006-01-02 15:04:05 UTC")
	}
	return strings.TrimSpace(s)
}
