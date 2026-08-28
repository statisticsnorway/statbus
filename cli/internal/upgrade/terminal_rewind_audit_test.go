package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"
)

// STATBUS-242: every write to public.upgrade that lands between the pre-upgrade
// SNAPSHOT and a possible rollback RESTORE is lost unless a terminal write puts
// it back. That mechanism has bitten twice — recovery_attempts (observed live at
// rc.03, STATBUS-181) and backup_path (predicted during the rc.05 arc
// corrections, STATBUS-241). A third instance should be impossible, not merely
// unlikely.
//
// THE WINDOW (architect's enumeration, 242 comment #1):
//   OPENS   at backupDatabase — the snapshot is the table as it stands then.
//   CLOSES  at restoreDatabase — the volume, and with it EVERY ROW, rewinds.
//   TERMINALS run after the rewind and are the only chance to re-impose.
//
// THIS IS A SITE AUDIT, NOT A COLUMN AUDIT, and the distinction is load-bearing:
// one column can have several sites with opposite dispositions. `error` written
// mid-flight is in-window and superseded; `error` at a terminal IS the
// superseding write. A column-keyed table would be wrong in both directions.
//
// KEYING — a deliberate, reasoned deviation from the ruling's "file:line".
// Line numbers churn on every edit above a site, which would make this pin a
// permanent source of unrelated red and train people to re-bless it without
// reading. Sites are keyed by (file, statement kind, COLUMN SET) instead, which
// is stable under movement and still unique per distinct write. Duplicate
// identical statements are counted, so a NEW site that copies an existing one
// changes the count and still goes red. Line numbers are reported in the
// failure message, where they help, rather than in the key, where they rot.

// rewindDisposition classes, from the architect's enumeration (242 comment #2).
type rewindClass string

const (
	// classReimposed — in-window write whose meaning MUST survive the rewind.
	// Must name the terminal that re-imposes it and the FLAG field the value is
	// sourced from. Never a remembered variable (the STATBUS-241 ruling).
	classReimposed rewindClass = "RE-IMPOSED"
	// classSupersededByTerminal — the terminal write sets this column after the
	// rewind, so the in-window value never needed to survive.
	classSupersededByTerminal rewindClass = "SUPERSEDED-BY-TERMINAL"
	// classOutsideWindow — written BEFORE the snapshot, so the snapshot contains
	// it and the rewind restores it unchanged.
	classOutsideWindow rewindClass = "OUTSIDE-WINDOW"
	// classSuccessPathOnly — only reachable on a path where no restore occurs.
	classSuccessPathOnly rewindClass = "SUCCESS-PATH-ONLY"
	// classSelfHealing — discovery re-derives it from an external source of
	// truth on its next tick. The reason is "re-derived", NOT "unimportant": if
	// any of these ever stops being re-derived, its exemption expires with it.
	classSelfHealing rewindClass = "SELF-HEALING-DERIVED"
	// classRuledReimposeOwed — the architect has RULED that this site must be
	// re-imposed, and the implementation is NOT yet in the code. It is not
	// classReimposed (that would claim a re-imposition that does not exist) and
	// not classPendingRuling (the question is answered). It carries the ruling
	// and what the implementation costs, so the obligation cannot be mistaken
	// for either a done thing or an open one.
	classRuledReimposeOwed rewindClass = "RULED-REIMPOSE-OWED"
	// classPendingRuling — the site is KNOWN and enumerated, but whether the
	// rewound value is acceptable is a judgment call the builder must not make
	// alone. Carries the question and its owner. Accounted-for, not answered.
	classPendingRuling rewindClass = "PENDING-RULING"
)

type rewindDisposition struct {
	Class rewindClass
	// Why must read as a reason, not a label — the next reader decides whether
	// the exemption still holds from this sentence.
	Why string
	// Terminal and FlagField are required for classReimposed.
	Terminal  string
	FlagField string
	// Question and Owner are required for classPendingRuling.
	Question string
	Owner    string
	// Count is how many identical sites carry this key. A new copy changes it.
	Count int
}

// siteKey identifies a write site stably: file + kind + the columns it writes.
type siteKey struct {
	File    string
	Kind    string // "UPDATE" or "INSERT"
	Columns string
}

func (k siteKey) String() string {
	return fmt.Sprintf("%s [%s %s]", k.File, k.Kind, k.Columns)
}

// ─────────────────────────────────────────────────────────────────────────
// THE ENUMERATION. Every entry is a decision someone made and can be argued
// with; an unaccounted site is a decision nobody has made yet, and that is
// what goes red.
// ─────────────────────────────────────────────────────────────────────────
var rewindAudit = map[siteKey]rewindDisposition{
	// ── A. RE-IMPOSED FROM THE FLAG — the two founding incidents ──
	{"cli/internal/upgrade/service.go", "UPDATE", "backup_path"}: {
		Class: classReimposed, Count: 1,
		Terminal:  "all five terminals, via terminalBackupPathSQL as $4",
		FlagField: "UpgradeFlag.BackupPath (read by flagSourcedBackupPath, never a parameter)",
		Why: "FOUNDING (STATBUS-241). The single row recorder, written after the swap+reconnect. " +
			"The ABORT branch restores the volume BEFORE its terminal write, rewinding this column to " +
			"a snapshot taken before the recorder ran — where it is NULL. Losing it fails the abort-hold " +
			"guard OPEN on exactly the population it protects.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "recovery_attempts"}: {
		Class: classReimposed, Count: 1,
		Terminal:  "all five terminals, as recovery_attempts = $2",
		FlagField: "read by the caller BEFORE any destructive step (attemptsAtCall)",
		Why: "FOUNDING (STATBUS-181), observed live at rc.03 where the counter stuck at 1. " +
			"The column decides park-versus-continue, so a rewind silently changes a recovery budget.",
	},

	// ── B. SUPERSEDED BY THE TERMINAL WRITE ITSELF ──
	{"cli/internal/upgrade/service.go", "UPDATE", "backup_path,error,recovery_attempts,state"}: {
		Class: classSupersededByTerminal, Count: 4,
		Why: "THE TERMINAL WRITES THEMSELVES (the four 'failed' tiers). They run AFTER the rewind and are " +
			"the superseding write — this is the site that re-imposes, not a site needing re-imposition.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "backup_path,error,recovery_attempts,rolled_back_at,state"}: {
		Class: classSupersededByTerminal, Count: 1,
		Why: "The rolled_back terminal. Sets rolled_back_at after the rewind; same reasoning as the four above.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "error"}: {
		Class: classSupersededByTerminal, Count: 1,
		Why: "Mid-flight error annotation, in-window. Overwritten by `error = $1` at every terminal, so the " +
			"rewound value never reaches a reader. (This is exactly why the audit keys on SITES: the same " +
			"column at a terminal is the superseding write.)",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "error,state"}: {
		Class: classSupersededByTerminal, Count: 1,
		Why: "completeInProgressUpgrade's observed-state failure write; sets state+error itself after any rewind.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "error,scheduled_at,state"}: {
		Class: classSupersededByTerminal, Count: 1,
		Why: "Claim-window failure write: sets its own state+error, and clears scheduled_at deliberately.",
	},

	// ── C. OUTSIDE THE WINDOW — written before the snapshot, so it contains them ──
	{"cli/internal/upgrade/service.go", "UPDATE", "from_commit_version,started_at,state"}: {
		Class: classOutsideWindow, Count: 1,
		Why: "The claim, inside executeUpgrade but BEFORE backupDatabase — the snapshot already holds it.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "log_relative_file_path"}: {
		Class: classOutsideWindow, Count: 1,
		Why: "Written before the backup; contained in the snapshot.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "from_commit_version,scheduled_at,started_at,state"}: {
		Class: classOutsideWindow, Count: 1,
		Why: "Un-claim / reset back to 'available'. Runs before any backup on its path.",
	},

	{"cli/internal/upgrade/service.go", "UPDATE", "completed_at,dismissed_at,error,log_relative_file_path,recreate,rolled_back_at,scheduled_at,skipped_at,started_at,state,superseded_at"}: {
		Class: classOutsideWindow, Count: 2,
		Why: "The SCHEDULE / re-arm writes (promoteExistingCandidate and the install-triggered sibling). They clear a " +
			"candidate's prior terminal state to arm it, and scheduling necessarily precedes execution — so they " +
			"run before any backup on their own path and the snapshot contains their result. NOTE for whoever " +
			"revisits: they deliberately NULL dismissed_at/skipped_at/superseded_at, which is a re-arm, not a loss.",
	},

	// ── D. SUCCESS PATH ONLY — no restore occurs on these paths ──
	{"cli/internal/upgrade/service.go", "UPDATE", "completed_at,docker_images_status,error,log_relative_file_path,state"}: {
		Class: classSuccessPathOnly, Count: 3,
		Why: "The completion writes. A completed upgrade never rolls back, so no rewind can follow them.",
	},

	// ── E. SELF-HEALING DERIVED — discovery re-derives from an external truth ──
	{"cli/internal/upgrade/service.go", "UPDATE", "docker_images_status"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Re-derived by discovery's next tick from the registry. Exemption expires if that stops being true.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "release_builds_status"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Re-derived from the release's build artifacts on the next tick. STATBUS-302: was 2 sites (the 'ready' UPDATE plus a 'failed' UPDATE reached via a `gh api` workflow-conclusion check); the 'failed' site is removed — gh is not installed on production boxes so that UPDATE never ran there, and no non-gh equivalent exists for this GitHub-Release-asset resource (ghcr.io is the wrong registry). The remaining 'ready' UPDATE is unaffected.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "docker_images_downloaded"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Re-derived by the next image check.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "commit_tags,release_status"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Re-derived from GitHub's release list on the next discovery tick.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "docker_images_status,error"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Image-build failure annotation; re-derived by the next image check.",
	},
	{"cli/internal/upgrade/service.go", "INSERT", "commit_sha,committed_at,commit_tags,release_status,summary,has_migrations,commit_version"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Discovery's own candidate registration — re-derived wholesale on the next tick.",
	},
	{"cli/internal/upgrade/service.go", "INSERT", "commit_sha,committed_at,summary,has_migrations,release_builds_status,commit_version"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Discovery's commit-channel registration; same re-derivation.",
	},
	{"cli/cmd/install.go", "INSERT", "commit_sha,committed_at,summary,state,completed_at,commit_version,release_status,scheduled_at,started_at,from_commit_version,commit_tags,has_migrations,docker_images_status,release_builds_status,log_relative_file_path"}: {
		Class: classSuccessPathOnly, Count: 1,
		Why: "The fresh-install record, written by install rather than by an upgrade. No upgrade window exists around it.",
	},
	{"cli/internal/upgrade/exec.go", "UPDATE", "backup_path"}: {
		Class: classSelfHealing, Count: 1,
		Why: "reconcileBackupDir NULLs a backup_path whose directory is gone. Re-derived by reconciliation itself " +
			"on the next pass, and a rewind that restores a path to a directory that no longer exists is re-cleared then.",
	},

	{"cli/internal/upgrade/service.go", "UPDATE", "commit_tags,commit_version,release_status"}: {
		Class: classSelfHealing, Count: 1,
		Why: "Discovery refreshing a known candidate's release metadata; re-derived from GitHub on the next tick.",
	},

	{"cli/internal/upgrade/service.go", "UPDATE", "error,recovery_parked_reason"}: {
		Class: classRuledReimposeOwed, Count: 1, Owner: "architect (ruled) / next builder (implements)",
		Why: "RULED RE-IMPOSE on the burden principle: an exemption requires proof, safety does not. A missed re-imposition here is a PARKED box silently un-parking into the deterministic failure it stopped at — STATBUS-229 exactly. If someone later proves no restore can follow a park, re-disposition EXEMPT with that proof recorded.",
		Question: "IMPLEMENTATION COST — RE-MEASURED, and the first measurement was wrong by a wide margin. " +
			"It was sized as a NEW FLAG FIELD (park state lives only in the row, so a flag-sourced re-imposition " +
			"needed one) — a flag-schema change, itself guarded by the STATBUS-232 writer pin. THE TRACE DELETED " +
			"THAT UNIT: no DESIGNED path lets a restore follow a live park (every route is parked-guarded — " +
			"recoveryRollback refuses at the point of use; applyNewSbUpgrading's rollbacks sit behind resumeNewSb's " +
			"parked-skip and it is the sole caller; claimScheduledUpgrade displaces any standing park and NULLs both " +
			"columns BEFORE the window opens; park and rollback are mutually exclusive branches in " +
			"parkForDeterministicFailure). The only interleaving was an ERROR path: the park-state read failed OPEN " +
			"on any error, so a transient failure at crash-recovery time would restore over a live park. THE COST IS " +
			"THEREFORE ONE BRANCH, not a flag field — narrowing the fail-open to SQLSTATE 42703 (where the column's " +
			"absence PROVES the row cannot be parked) and refusing on every other error. " +
			"THIS ENTRY STAYS RULED-REIMPOSE-OWED UNTIL THAT NARROWING SHIPS: the audit must state the TRUE CURRENT " +
			"STATE, not the intended one, and the flip to EXEMPT-with-proof belongs to the commit that lands it.",
	},

	{"cli/internal/upgrade/service.go", "UPDATE", "dismissed_at,state"}: {
		Class: classOutsideWindow, Count: 1,
		Why: "The `sb upgrade dismiss` write (STATBUS-250's first deliverable). Category C for the reason the " +
			"architect established on the app's dismissal: a restore rewinds to the snapshot of THAT upgrade, and " +
			"a dismissal is made OUTSIDE any upgrade window — it is a deliberate operator act, and in the " +
			"dev-reset case an act taken after a wreck, before the next upgrade starts. It is therefore inside " +
			"the snapshot of every subsequent upgrade and survives their rollbacks. Nothing rewind-robust is " +
			"owed here. THE IN-WINDOW RESIDUAL is the same one recorded on the app's write: a dismissal made " +
			"while an upgrade is in flight is reverted by that upgrade's rollback — human-visible (the row " +
			"reappears) and one command to redo. " +
			"NOTE the columns: state AND dismissed_at are written TOGETHER in one statement, because " +
			"chk_upgrade_state_attributes rejects a row whose state and timestamps disagree — a half-write is a " +
			"failed statement, not a silently contradictory row.",
	},

	// ── F. PENDING RULING — enumerated and known, disposition NOT self-assigned ──
	{"cli/internal/upgrade/service.go", "UPDATE", "error,recovery_parked_at,recovery_parked_reason,state,superseded_at"}: {
		Class: classRuledReimposeOwed, Count: 1, Owner: "architect (ruled) / next builder (implements)",
		Why: "RULED RE-IMPOSE on the burden principle: an exemption requires proof, safety does not. A missed re-imposition here is a PARKED box silently un-parking into the deterministic failure it stopped at — STATBUS-229 exactly. If someone later proves no restore can follow a park, re-disposition EXEMPT with that proof recorded.",
		Question: "IMPLEMENTATION COST — see the recoveryRollback-route entry above: the trace deleted the " +
			"flag-field unit. No DESIGNED path lets a restore follow a live park; the only interleaving was the " +
			"park-state read FAILING OPEN on any error. The cost is ONE BRANCH — narrow that fail-open to SQLSTATE " +
			"42703 and refuse on every other error. STAYS RULED-REIMPOSE-OWED until the narrowing ships: the audit " +
			"states the true current state, not the intended one.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "error,recovery_parked_at,recovery_parked_reason"}: {
		Class: classRuledReimposeOwed, Count: 1, Owner: "architect (ruled) / next builder (implements)",
		Why: "RULED RE-IMPOSE on the burden principle: an exemption requires proof, safety does not. A missed re-imposition here is a PARKED box silently un-parking into the deterministic failure it stopped at — STATBUS-229 exactly. If someone later proves no restore can follow a park, re-disposition EXEMPT with that proof recorded.",
		Question: "IMPLEMENTATION COST — see the recoveryRollback-route entry above: the trace deleted the " +
			"flag-field unit. No DESIGNED path lets a restore follow a live park; the only interleaving was the " +
			"park-state read FAILING OPEN on any error. The cost is ONE BRANCH — narrow that fail-open to SQLSTATE " +
			"42703 and refuse on every other error. STAYS RULED-REIMPOSE-OWED until the narrowing ships: the audit " +
			"states the true current state, not the intended one.",
	},
	{"cli/internal/upgrade/service.go", "UPDATE", "state,superseded_at"}: {
		Class: classSelfHealing, Count: 2,
		Why: "RULED SELF-HEALING (STATBUS-242): re-supersession at install time is sufficient. The recompute " +
			"already exists — supersedeBelowInstalled (service.go:4454) runs from INSIDE discover() " +
			"(service.go:4126), so every tick re-supersedes rows not newer than installed. " +
			"THE RESIDUAL, recorded rather than hidden: rows superseded relative to a SELECTED but " +
			"never-installed candidate stay un-superseded between a restore and the next successful install. " +
			"Nobody is harmed by it — the below-installed sweep catches them at that install in every branch, " +
			"and inside the window the damage is VISIBILITY ONLY: an operator may see stale 'available' rows " +
			"that should read superseded, while every automatic path picks the newest candidate regardless. " +
			"THE EXEMPTION EXPIRES if supersedeBelowInstalled ever stops running on the discovery tick — that " +
			"call site is what makes this self-healing rather than merely unimportant, so moving or removing it " +
			"re-opens this disposition.",
	},
}

// appWriteSites are the write paths that do NOT go through Go at all —
// FINDING 2 (242 comment #1). public.upgrade is exposed through PostgREST under
// RLS, and the operator-facing dismiss/skip actions are APP writes. A scan of
// cli/ alone would pass while blind to exactly the columns Finding 1 identifies
// as unrecoverable, which would make this mechanism the very thing it exists to
// prevent: a check reporting on an examination it never performed.
var appWriteSites = map[siteKey]rewindDisposition{
	{"app/src/app/admin/upgrades/page.tsx", "PATCH", "dismissed_at"}: {
		Class: classOutsideWindow, Count: 1,
		Why: "OUTSIDE THE WINDOW (category C) — the true reason, and no new class was needed. A restore rewinds " +
			"to THIS upgrade's OWN snapshot, so an operator's dismissed_at written BEFORE the upgrade started is inside " +
			"that snapshot and comes back untouched. (An earlier draft filed this as a self-healing exemption " +
			"and said in its own text that the class was a stretch, because nothing re-derives a human decision. " +
			"It was: the column is not re-derived, it is CONTAINED — which category C already says exactly.) " +
			"THE IN-WINDOW RESIDUAL, kept: a decision made DURING an in-flight upgrade window is reverted by the " +
			"restore. That is human-visible in the admin UI and one click to redo, and it is recorded so a " +
			"future reader weighs it rather than discovering it.",
	},
	{"app/src/app/admin/upgrades/page.tsx", "PATCH", "state"}: {
		Class: classPendingRuling, Count: 3, Owner: "architect",
		Why: "The app sets state DIRECTLY alongside the timestamps — `state: \"scheduled\"`, `\"skipped\"`, " +
			"`\"dismissed\"` — so the operator's decision is carried by state as well as by the _at column. " +
			"Recorded because it widens Finding 1: the human act is TWO columns, not one, and a re-imposition " +
			"that restored only the timestamp would leave the row in a state that contradicts it.",
		Question: "If dismissed_at/skipped_at must survive a restore, state must survive with them or the row " +
			"becomes self-contradictory. Rule on the PAIR, not on the timestamp alone. STRENGTHENED by the " +
			"architect: this is not merely untidy — chk_upgrade_state_attributes REJECTS a row whose state and " +
			"timestamp columns disagree, so a half-re-imposition is a FAILED TERMINAL WRITE, not a silently " +
			"wrong row. The constraint turns the pair from a style question into a correctness one, and it means " +
			"a partial fix fails loudly rather than shipping a contradiction.",
	},
	{"app/src/app/admin/upgrades/page.tsx", "PATCH", "skipped_at"}: {
		Class: classOutsideWindow, Count: 1,
		Why: "OUTSIDE THE WINDOW (category C) — the true reason, and no new class was needed. A restore rewinds " +
			"to THIS upgrade's OWN snapshot, so an operator's skipped_at written BEFORE the upgrade started is inside " +
			"that snapshot and comes back untouched. (An earlier draft filed this as a self-healing exemption " +
			"and said in its own text that the class was a stretch, because nothing re-derives a human decision. " +
			"It was: the column is not re-derived, it is CONTAINED — which category C already says exactly.) " +
			"THE IN-WINDOW RESIDUAL, kept: a decision made DURING an in-flight upgrade window is reverted by the " +
			"restore. That is human-visible in the admin UI and one click to redo, and it is recorded so a " +
			"future reader weighs it rather than discovering it.",
	},
}

// ─────────────────────────────────────────────────────────────────────────

var (
	// Go string literals: backtick-quoted (multi-line SQL) and double-quoted.
	// The SQL regexes run INSIDE these only. Scanning raw file text instead let
	// a WHERE-less statement's SET clause run on into a LATER statement's WHERE
	// and swallow every column between — and let a PROSE string that merely
	// mentions `INSERT INTO public.upgrade (...)` register as a write site.
	// Both were real false matches on the first run of this scanner.
	goStringRe = regexp.MustCompile("(?s)`[^`]*`|\"(?:[^\"\\\\]|\\\\.)*\"")
	updateRe   = regexp.MustCompile(`(?s)UPDATE\s+public\.upgrade\s+(?:AS\s+\w+\s+)?SET\s+(.*?)(?:\s+WHERE\s|$)`)
	insertRe   = regexp.MustCompile(`(?s)INSERT\s+INTO\s+public\.upgrade\s*\(([^)]*)\)`)
	// A column assignment: the identifier immediately before '='.
	assignRe = regexp.MustCompile(`(?m)([a-z_][a-z0-9_]*)\s*=`)
	// A real column name. Rejects the "..." of a prose mention.
	identRe = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)
)

// scanGoWriteSites walks the Go sources and returns every public.upgrade write
// site keyed stably. It reads whole files so multi-line backtick statements are
// captured — a line-based scan would miss them, and missing a site is the one
// failure this mechanism must not have.
func scanGoWriteSites(t *testing.T, repoRoot string) map[siteKey]int {
	t.Helper()
	fragments := loadSQLFragments(t, repoRoot)
	found := map[siteKey]int{}
	for _, rel := range []string{"cli/cmd", "cli/internal/upgrade"} {
		dir := filepath.Join(repoRoot, rel)
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatalf("read %s: %v", rel, err)
		}
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".go") || strings.HasSuffix(e.Name(), "_test.go") {
				continue
			}
			relPath := filepath.ToSlash(filepath.Join(rel, e.Name()))
			b, err := os.ReadFile(filepath.Join(dir, e.Name()))
			if err != nil {
				t.Fatal(err)
			}
			// Resolve SQL fragments that are CONCATENATED into a statement from
			// a named constant. Without this the five terminals scan as writing
			// only state/error/recovery_attempts — their backup_path clause lives
			// in terminalBackupPathSQL and is invisible to a literal-only scan.
			// An audit that cannot see the re-imposition it exists to track would
			// be the zero-scope shape all over again.
			src := resolveSQLFragments(string(b), fragments)

			// One statement per string literal: bounded, so nothing can span.
			for _, lit := range goStringRe.FindAllString(src, -1) {
				for _, m := range updateRe.FindAllStringSubmatch(lit, -1) {
					cols := columnsFromSetClause(m[1])
					if len(cols) == 0 {
						continue
					}
					found[siteKey{relPath, "UPDATE", strings.Join(cols, ",")}]++
				}
				for _, m := range insertRe.FindAllStringSubmatch(lit, -1) {
					cols := columnsFromList(m[1])
					if len(cols) == 0 {
						continue
					}
					found[siteKey{relPath, "INSERT", strings.Join(cols, ",")}]++
				}
			}
		}
	}
	return found
}

// loadSQLFragments reads the named SQL-fragment constants so concatenated
// statements can be scanned whole. Fails loudly if a fragment it expects is
// gone: a silently-unresolved fragment would shrink a site's column set and
// quietly drop a tracked column out of the audit.
func loadSQLFragments(t *testing.T, repoRoot string) map[string]string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(repoRoot, "cli", "internal", "upgrade", "service.go"))
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, name := range []string{"terminalBackupPathSQL", "recoveryBudgetResetCols"} {
		re := regexp.MustCompile("(?s)" + name + "\\s*=\\s*(?:`([^`]*)`|\"([^\"]*)\")")
		m := re.FindStringSubmatch(string(b))
		if m == nil {
			t.Fatalf("SQL fragment constant %s not found — if it was renamed, update this scanner; if it was removed, the terminals no longer re-impose what it carried and THAT is the finding", name)
		}
		frag := m[1]
		if frag == "" {
			frag = m[2]
		}
		out[name] = frag
	}
	return out
}

// resolveSQLFragments splices each fragment's text into the string literals it
// is concatenated with, so the statement scans as the SQL that actually runs.
func resolveSQLFragments(src string, fragments map[string]string) string {
	for name, sql := range fragments {
		src = strings.ReplaceAll(src, `"+`+name+`+"`, sql)
		src = strings.ReplaceAll(src, `" + `+name+` + "`, sql)
	}
	return src
}

// columnsFromSetClause extracts and SORTS the assigned column names, so the key
// does not depend on the order someone happened to write them in.
func columnsFromSetClause(set string) []string {
	seen := map[string]bool{}
	var cols []string
	for _, m := range assignRe.FindAllStringSubmatch(set, -1) {
		c := m[1]
		// Skip SQL keywords and the right-hand side of expressions like
		// `COALESCE(recovery_parked_reason, '')` where the name recurs.
		if c == "now" || c == "coalesce" || seen[c] || !identRe.MatchString(c) {
			continue
		}
		seen[c] = true
		cols = append(cols, c)
	}
	sort.Strings(cols)
	return cols
}

// columnsFromList extracts an INSERT's column list, preserving source order —
// an INSERT's column list is written deliberately and reads better unsorted.
func columnsFromList(list string) []string {
	var cols []string
	for _, raw := range strings.Split(list, ",") {
		c := strings.TrimSpace(strings.Trim(strings.TrimSpace(raw), "\n\t "))
		if c == "" || !identRe.MatchString(c) {
			continue
		}
		cols = append(cols, c)
	}
	return cols
}

// TestEveryPostSnapshotWriteSiteIsAccountedFor_STATBUS242 is the mechanism
// (AC#2): a new or moved write site with no disposition goes RED until someone
// decides what the rewind means for it.
func TestEveryPostSnapshotWriteSiteIsAccountedFor_STATBUS242(t *testing.T) {
	repoRoot := repoRootFromTest(t)
	found := scanGoWriteSites(t, repoRoot)

	if len(found) == 0 {
		t.Fatal("the scan found NO public.upgrade write sites — a check that examines nothing must fail, not pass (doc-033). The regexes or the paths are broken.")
	}

	var unaccounted []string
	for k, n := range found {
		d, ok := rewindAudit[k]
		if !ok {
			unaccounted = append(unaccounted, fmt.Sprintf("%s  (%d site(s))", k, n))
			continue
		}
		if d.Count != n {
			unaccounted = append(unaccounted, fmt.Sprintf(
				"%s  — %d site(s) found, %d dispositioned. A COPY of an already-dispositioned statement is still a new site: confirm the disposition covers it, then update Count.",
				k, n, d.Count))
		}
	}
	sort.Strings(unaccounted)
	if len(unaccounted) > 0 {
		t.Errorf(`%d public.upgrade write site(s) are NOT accounted for in the STATBUS-242 rewind audit.

WHY THIS IS RED: the rollback restore rewinds public.upgrade to the pre-upgrade
snapshot, so ANY value written between the snapshot and the restore is lost
unless a terminal write re-imposes it. That has already cost two incidents —
recovery_attempts (STATBUS-181, seen live) and backup_path (STATBUS-241).

WHAT TO DO: add an entry to rewindAudit for each site below with exactly one
disposition — RE-IMPOSED (naming the terminal AND the flag field the value comes
from, never a remembered variable), or an exemption naming which class applies
and WHY. If you cannot decide, use PENDING-RULING with the question and an owner
— an honest open question is accounted for; an undecided site is not.

Unaccounted sites:
  %s`, len(unaccounted), strings.Join(unaccounted, "\n  "))
	}

	// The reverse direction: an entry for a site that no longer exists is a
	// stale premise, and stale premises are what this campaign keeps tripping
	// over. It must be removed rather than left looking authoritative.
	var stale []string
	for k := range rewindAudit {
		if _, ok := found[k]; !ok {
			stale = append(stale, k.String())
		}
	}
	sort.Strings(stale)
	if len(stale) > 0 {
		t.Errorf("%d audit entr(ies) describe a write site that no longer exists — remove them rather than leaving a list that reads as current:\n  %s",
			len(stale), strings.Join(stale, "\n  "))
	}
}

// TestRewindAuditEntriesAreWellFormed_STATBUS242 keeps the enumeration honest:
// a disposition that names no reason, no terminal, or no owner is a box ticked
// rather than a decision made.
func TestRewindAuditEntriesAreWellFormed_STATBUS242(t *testing.T) {
	all := map[siteKey]rewindDisposition{}
	for k, v := range rewindAudit {
		all[k] = v
	}
	for k, v := range appWriteSites {
		all[k] = v
	}

	for k, d := range all {
		if strings.TrimSpace(d.Why) == "" {
			t.Errorf("%s: every disposition must carry a REASON — the next reader decides whether it still holds from that sentence", k)
		}
		switch d.Class {
		case classReimposed:
			if d.Terminal == "" || d.FlagField == "" {
				t.Errorf("%s: RE-IMPOSED must name the terminal that re-imposes it AND the flag field the value is sourced from (the STATBUS-241 ruling: never a remembered variable)", k)
			}
		case classPendingRuling:
			if strings.TrimSpace(d.Question) == "" || strings.TrimSpace(d.Owner) == "" {
				t.Errorf("%s: PENDING-RULING must carry the QUESTION and an OWNER, or it is an open question nobody is holding", k)
			}
		case classRuledReimposeOwed:
			if strings.TrimSpace(d.Question) == "" || strings.TrimSpace(d.Owner) == "" {
				t.Errorf("%s: RULED-REIMPOSE-OWED must name what the implementation costs (Question) and who owns it", k)
			}
		case classSupersededByTerminal, classOutsideWindow, classSuccessPathOnly, classSelfHealing:
			// Reason-only classes; Why is already required above.
		default:
			t.Errorf("%s: unknown disposition class %q", k, d.Class)
		}
		if d.Count < 1 {
			t.Errorf("%s: Count must be at least 1", k)
		}
	}

	// The two founding incidents must remain visible as such (AC#3). If either
	// entry is ever removed or reclassified, the audit has lost the evidence it
	// was built from.
	founding := []siteKey{
		{"cli/internal/upgrade/service.go", "UPDATE", "backup_path"},
		{"cli/internal/upgrade/service.go", "UPDATE", "recovery_attempts"},
	}
	for _, k := range founding {
		d, ok := rewindAudit[k]
		if !ok || d.Class != classReimposed {
			t.Errorf("%s must remain a RE-IMPOSED founding entry (AC#3) — it is one of the two incidents this mechanism exists because of", k)
		}
	}
	if !strings.Contains(rewindAudit[founding[0]].Why, "STATBUS-241") {
		t.Error("the backup_path entry must cite STATBUS-241 (AC#3)")
	}
	if !strings.Contains(rewindAudit[founding[1]].Why, "STATBUS-181") {
		t.Error("the recovery_attempts entry must cite STATBUS-181 (AC#3)")
	}
}

// TestAppWritePathsAreCovered_STATBUS242 is FINDING 2 made mechanical. The
// operator's dismiss and skip go through PostgREST, not through Go — so a
// cli/-only scan would pass while blind to precisely the columns Finding 1
// identifies as unrecoverable.
//
// This test COVERS those paths rather than merely declaring them out of scope.
// If the app tree is not present (a cli-only checkout), it says so loudly
// instead of passing quietly: a check must report what it examined.
func TestAppWritePathsAreCovered_STATBUS242(t *testing.T) {
	repoRoot := repoRootFromTest(t)
	appDir := filepath.Join(repoRoot, "app", "src")
	if _, err := os.Stat(appDir); err != nil {
		t.Fatalf(`the app tree is not present at app/src, so this test CANNOT cover the PostgREST write paths.

It is failing rather than passing to say so plainly: public.upgrade is written
from the app (operator dismiss/skip via PATCH /rest/upgrade), those columns are
exactly the ones nothing re-derives, and a green result here would claim an
examination that did not happen (STATBUS-242 Finding 2, doc-033).`)
	}

	// Find every app file that writes to the upgrade endpoint.
	writers := map[string]bool{}
	err := filepath.Walk(appDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		if !strings.HasSuffix(path, ".ts") && !strings.HasSuffix(path, ".tsx") {
			return nil
		}
		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		src := string(b)
		if !strings.Contains(src, "/rest/upgrade") {
			return nil
		}
		// A write is a PATCH or POST against that endpoint.
		if strings.Contains(src, `method: "PATCH"`) || strings.Contains(src, `method: "POST"`) {
			rel, _ := filepath.Rel(repoRoot, path)
			writers[filepath.ToSlash(rel)] = true
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walk app/src: %v", err)
	}
	if len(writers) == 0 {
		t.Fatal("no app writer of /rest/upgrade was found — either the app stopped writing it (then remove appWriteSites) or the detection broke. Either way this must not pass silently.")
	}

	// Every column an app writer sets must be dispositioned. Over-inclusive by
	// design: a name that merely looks like an upgrade column still demands an
	// entry, because the cost of a spurious entry is a sentence and the cost of
	// a missed one is a third incident.
	// A WRITE, not a type declaration. `dismissed_at: string | null;` in an
	// interface is not a write, and an audit that claimed it was would describe
	// an app that does not exist. Writes assign an expression and end in a
	// comma; declarations name a type and end in a semicolon.
	// The write IDIOMS the app actually uses: a fresh timestamp, or a literal.
	// `state: activeUpgradeRow.state` is a property COPY inside a local object,
	// not a PATCH body, and counting it would put a column in the audit that the
	// app never writes — an enumeration is only worth having if it is true.
	//
	// KNOWN BLIND SPOT, stated rather than hidden (doc-033): a write whose value
	// is an opaque variable (`state: someComputedValue`) would not match. It is
	// named here because a check must report what it examined; if the app ever
	// writes that way, this scan is why the audit missed it.
	colRe := regexp.MustCompile(`(?m)^\s*([a-z_]+_at|state|error)\s*:\s*(?:new Date\(|"|')[^;]*,\s*$`)
	var missing []string
	for file := range writers {
		b, rerr := os.ReadFile(filepath.Join(repoRoot, file))
		if rerr != nil {
			t.Fatal(rerr)
		}
		for _, m := range colRe.FindAllStringSubmatch(string(b), -1) {
			col := m[1]
			if _, ok := appWriteSites[siteKey{file, "PATCH", col}]; !ok {
				missing = append(missing, fmt.Sprintf("%s writes %q", file, col))
			}
		}
	}
	sort.Strings(missing)
	missing = dedupeStrings(missing)
	if len(missing) > 0 {
		t.Errorf(`%d app write(s) to public.upgrade are not in the STATBUS-242 audit.

These are the writes with NOTHING to re-derive them: a rollback restore reverts
an operator's deliberate act with no record it ever happened. Add an entry to
appWriteSites for each, or PENDING-RULING with the question and an owner.

  %s`, len(missing), strings.Join(missing, "\n  "))
	}
}

func dedupeStrings(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

func repoRootFromTest(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	// cli/internal/upgrade/<file> → up three = repo root.
	return filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(thisFile))))
}
