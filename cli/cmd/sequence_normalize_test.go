package cmd

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// funcBodiesContaining scans src for top-level `func name(...) ... { ... }`
// declarations and returns the FULL TEXT (signature through the start of the
// next declaration, or end of file for the last one) of every function whose
// body contains needle. Same decl-scanning technique as the STATBUS-291
// functionsCalling helper (cli/internal/upgrade/channel_resolution_git_test.go)
// — third reuse of the pattern, this copy returns bodies (not just
// signatures) because the STATBUS-316 guard below needs to check for a
// SECOND needle inside the same body, not just report which functions match
// the first.
func funcBodiesContaining(src, needle string) []string {
	decl := regexp.MustCompile(`(?m)^func (?:\([^)]*\) )?[A-Za-z0-9_]+\(`)
	locs := decl.FindAllStringIndex(src, -1)

	var out []string
	for i, loc := range locs {
		bodyEnd := len(src)
		if i+1 < len(locs) {
			bodyEnd = locs[i+1][0]
		}
		body := src[loc[0]:bodyEnd]
		if strings.Contains(body, needle) {
			out = append(out, body)
		}
	}
	return out
}

// restoreGuardAllowlist names restore-path functions that call
// runPgRestoreAtomic( but are DELIBERATELY not required to also call
// normalizeAllSequences(, with the reason on record. Checked and empty as
// of STATBUS-316: restoreVerifyDB (seed_verify.go) was reviewed and DOES
// get the call — computeSeedDigest's three inputs (pg_dump --schema-only
// with no --sequence-data, per-table row-content digests, and the
// migration ledger) never observe sequence current-value state, so
// normalizing there cannot mask the physical-state drift the AC#4 proof
// exists to catch. If a future restore path is found that genuinely must
// skip normalization (e.g. because it inspects the artifact AS PUBLISHED
// and normalizing would mask real drift), name it here with the reason —
// never by silently leaving it uncovered.
var restoreGuardAllowlist = map[string]string{}

// TestEveryRestorePathNormalizesSequences_STATBUS316 is the guard the
// architect specified: every function that calls runPgRestoreAtomic( —
// discovered from source, not enumerated by hand — must also call
// normalizeAllSequences( in the same body, unless named in
// restoreGuardAllowlist with a reason. A fifth restore path written without
// the call fails this test the day it's added, rather than silently
// carrying STATBUS-316's exact disease forward.
//
// The minimum-count assertion is load-bearing: a regex that stops matching
// (e.g. after a refactor changes the declaration shape) must fail LOUD, not
// silently report zero restore paths and pass by vacuous truth.
func TestEveryRestorePathNormalizesSequences_STATBUS316(t *testing.T) {
	files := []string{
		"cli/cmd/db.go",
		"cli/cmd/seed.go",
		"cli/cmd/seed_build.go",
		"cli/cmd/seed_verify.go",
		"cli/cmd/install.go",
	}

	var totalRestoreFuncs int
	for _, rel := range files {
		src, err := os.ReadFile(thisRepoFile(t, rel))
		if err != nil {
			t.Fatalf("read %s: %v", rel, err)
		}
		bodies := funcBodiesContaining(string(src), "runPgRestoreAtomic(")
		for _, body := range bodies {
			sig := body[:strings.IndexByte(body, '\n')]
			name := strings.TrimSpace(sig)

			// The wrapper's own definition is not a "caller" of itself — its
			// body legitimately mentions its own name in an error-message
			// string (db.go: "runPgRestoreAtomic(%s): caller must not...").
			if strings.HasPrefix(name, "func runPgRestoreAtomic(") {
				continue
			}
			totalRestoreFuncs++

			allowed := false
			var reason string
			for allowedSig, r := range restoreGuardAllowlist {
				if strings.Contains(name, allowedSig) {
					allowed, reason = true, r
					break
				}
			}
			if allowed {
				t.Logf("%s: allowlisted, not required to normalize sequences (%s)", name, reason)
				continue
			}
			if !strings.Contains(body, "normalizeAllSequences(") {
				t.Errorf(`%s (in %s) calls runPgRestoreAtomic but never calls normalizeAllSequences.

This is exactly STATBUS-316's disease: a restored artifact's sequences carry
whatever burn history the SOURCE accumulated, not a position derived from
the data this restore just loaded. Either call normalizeAllSequences(projDir,
dbName) once at this function's genuine completion point, or — if this path
genuinely must not normalize (e.g. it inspects the artifact AS PUBLISHED and
normalizing would mask real drift) — add it to restoreGuardAllowlist in
sequence_normalize_test.go with the reason on record.`, name, rel)
			}
		}
	}

	// STATBUS-316's own five named restore entries: runPgRestoreAtomic itself
	// (not a caller of itself), restoreSeedDump (1 call site), restoreLocal
	// (3 call sites but 1 function), runSeedRestoreCmd (1, the RunE this
	// ticket named after extracting it from an anonymous closure so this
	// exact scan could see it), restoreVerifyDB (1) — 4 functions minimum.
	// runSeedRestore (install.go) is a pass-through subprocess caller and
	// does not itself call runPgRestoreAtomic, so it correctly contributes 0.
	const minExpectedRestoreFuncs = 4
	if totalRestoreFuncs < minExpectedRestoreFuncs {
		t.Fatalf("found only %d function(s) calling runPgRestoreAtomic across %v — expected at least %d "+
			"(restoreSeedDump, restoreLocal, runSeedRestoreCmd, restoreVerifyDB). "+
			"This scan finding fewer than the known restore paths means the regex or file list broke, "+
			"not that restore paths went away — a broken scan must fail loud, not silently pass on zero coverage.",
			totalRestoreFuncs, files, minExpectedRestoreFuncs)
	}
}
