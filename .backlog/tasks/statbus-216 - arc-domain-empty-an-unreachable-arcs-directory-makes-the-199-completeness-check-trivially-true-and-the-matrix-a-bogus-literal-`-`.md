---
id: STATBUS-216
title: >-
  arc-domain-empty: an empty arcs/ folder passes the release gate and breaks the
  test matrix — both sides must fail loudly
status: Done
assignee:
  - mechanic
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 08:29'
labels:
  - ci
  - release
  - quality-gate
  - install-recovery
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
  - cli/cmd/release.go
  - cli/internal/release/workflow_check.go
priority: medium
type: bug
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: before a release is promoted to stable, a gate checks that the full upgrade test suite really ran. It reads the list of test scenarios ("arcs") from the folder test/install-recovery/arcs/ at the release commit, then demands that a green CI run contains one job per scenario. The CI workflow reads the same folder to build its test matrix. One folder, two consumers, and the promise "promotion means every scenario ran."

WHAT GOES WRONG: if that folder ever comes back empty — renamed, or a path typo in either reader — neither side notices. The gate passes having checked nothing, and the workflow invents a fake test. Not reachable today (the folder holds 31 arcs, found 2026-08-17 by the architect during the STATBUS-215 review), but one rename away.

THE DETAIL, gate side (the serious one): upgradeArcNamesAtCommit (cli/cmd/release.go:1349) returns an empty list AND no error when the folder listing prints nothing — `strings.Split(strings.TrimSpace(""), "\n")` yields `[""]`, whose basename has no `-arc.sh` suffix, so the names slice stays nil while err stays nil. The completeness check (cli/internal/release/workflow_check.go:222-225) then asks "is every required arc present in the run?" of an empty list — automatically yes. The gate prints "✓ upgrade-arc-harness FULL SUITE green (0/0 arc jobs present)" and passes. Any green run now satisfies the gate while proving nothing, and the success line reads like a real pass.

THE DETAIL, workflow side (cosmetic by comparison): the discover job enumerates arcs with a shell glob (`for f in test/install-recovery/arcs/*-arc.sh`). A glob that matches nothing hands the loop the literal `*`, so the matrix becomes one bogus scenario named `*`, which fails on a missing script — noisy, but not the clean, named failure the rest of that job gives.

THE FIX: an empty scenario list becomes an error on both sides. The gate refuses instead of printing a 0/0 pass (with a test pinning that refusal), the workflow fails loudly on an unmatched glob, and the two readers' paths are pinned to each other so they cannot silently diverge.

WHY THAT HELPS: the gate can then never be silently disarmed by a file move. An empty scenario list stops a promotion instead of waving it through — the promise "promotion means proven" stays true even through future reorganisations.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `upgradeArcNamesAtCommit` returns an error when the arc domain at the commit is empty, so checkUpgradeArcHarnessGate refuses instead of printing a 0/0 pass
- [x] #2 A Go test pins the refusal: an empty required-arc list must never yield a gate pass (assert on the gate's boolean, not just on the helper)
- [x] #3 discover fails loud on an empty/unmatched arcs glob (nullglob or an explicit count check) instead of emitting the literal `*` as a scenario
- [x] #4 The two sides derive the arc domain from paths that cannot silently diverge, or a test pins them to each other (the STATBUS-199 comment #6 duplication-guard pattern)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 08:18
---
AC#3 (workflow side) done, frozen for review — mechanic's scope was .github/workflows/upgrade-arc-harness.yaml ONLY; AC#1/#2/#4 (release.go, workflow_check.go) are the engineer's in-parallel scope, not touched here.

discover's arc-enumeration step (job `discover`, step "Enumerate arc scenarios into the matrix") now does:
```
shopt -s nullglob
arc_files=(test/install-recovery/arcs/*-arc.sh)
shopt -u nullglob
if [ "${#arc_files[@]}" -eq 0 ]; then
  echo "::error title=Empty arc domain::no test/install-recovery/arcs/*-arc.sh files found — the arcs/ folder is empty, renamed, or the glob path has a typo. Refusing to build a matrix from an empty domain." >&2
  exit 1
fi
all="$(for f in \"${arc_files[@]}\"; do b=\"$(basename \"$f\")\"; echo \"${b%-arc.sh}\"; done | sort)"
```
inserted right after the RIDE early-exit (so the legitimate RIDE count=0 path is untouched) and before the previous unguarded glob assignment. An unmatched glob now fails loud with `::error title=Empty arc domain` in the same style as the job's existing "Unknown arc scenario" error, instead of silently becoming the literal scenario `*`.

Validated: `ruby -ryaml -e "YAML.load_file(...)"` parses clean; `actionlint .github/workflows/upgrade-arc-harness.yaml` exits 0, no findings.

Diff frozen in the working tree (no commit) — foreman to review/commit alongside the engineer's Go-side AC#1/#2/#4.
---

author: engineer
created: 2026-08-18 08:22
---
**Go arm implemented, frozen for review (no commit).** Files: `cli/cmd/release.go`, `cli/internal/release/workflow_check.go`, `cli/internal/release/workflow_check_test.go`, new `cli/cmd/release_arc_domain_gate_test.go`. The workflow side (AC#3) is the mechanic's — untouched here.

**AC#1 — both domain readers, not one.** The install-recovery counterpart had the identical hole, confirmed by reading: `installRecoveryScenarioNamesAtCommit` (release.go:1384 pre-edit) ran the same `strings.Split(TrimSpace(""), "\n")` → `[""]` → nil names, nil err. Both now refuse:
- `upgradeArcNamesAtCommit` (release.go:1381) — errors naming the commit, the path it listed, and the `-arc.sh` suffix it matched, with the fix line pointing at the discover job's path.
- `installRecoveryScenarioNamesAtCommit` (release.go:1438) — same, plus the second cause that only exists on this side: every scenario carrying the skip-default marker would also empty the default suite.

**AC#2 — pinned at the gate's boolean, and it needed a seam.** `checkUpgradeArcHarnessGate` reaches the empty-domain branch only after a green API answer, so with no network every call returns Unknown and the gate returns false — a refusal test would have passed for the wrong reason and pinned nothing. Added two package vars (release.go, above `checkInstallRecoveryHarnessGate`): `checkWorkflowAtCommit` / `workflowJobsComplete`, defaulting to the real `release.*` functions, used by both harness gates and the ride walk. Tests swap them via `stubWorkflowSeams` + `t.Cleanup`; production never assigns them.

The stubs answer as permissively as possible — green run, `Complete: true` — so a pass can only come from the empty domain itself. `TestUpgradeArcHarnessGate_EmptyArcDomainRefuses` and `TestInstallRecoveryHarnessGate_EmptyScenarioDomainRefuses` assert the returned bool is false, that the refusal names the path it looked in, and that no `0/0` line prints. `TestUpgradeArcHarnessGate_PopulatedDomainPasses` is the positive control (same stubs, one real arc → gate true, and the gate asked about exactly `[working]`).

**RED verified, not assumed.** With the two `len(names) == 0` guards neutered, both gate tests fail with the literal bogus success: `✓ upgrade-arc-harness FULL SUITE green at 232a74e (0/0 arc jobs ran and succeeded)` and the same for install-recovery. Restored after.

**Second layer, inside my scope.** `WorkflowJobsCompleteAtCommit` now refuses an empty `requiredJobNames` outright (workflow_check.go:237, before the HTTP call). The domain fix is the primary guard; this makes the trivially-true reading unreachable for any future caller too. Test arm `empty-required`.

**AC#4 — done in-scope, no reach into the workflow file.** Extracted `upgradeArcDir` / `upgradeArcSuffix` constants (release.go, above `upgradeArcNamesAtCommit`) and pinned them both ways in `TestUpgradeArcDomainPathMatchesWorkflow`: the workflow yaml must contain both strings, AND the real tree must hold at least one `*-arc.sh` under that directory. So a move breaks the build loudly whether it empties the gate's reader or the workflow's. It is a pin, not a single source — one string still lives in each file, and a genuine single source would need the workflow to read the path from the Go side (or vice versa), which is the mechanic's file. Verdict: pin is the right cost here; flagging for the architect only if they want the stronger form.

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `golangci-lint run ./...` at 2.12.2 (the CI version) — 0 issues.
---

author: engineer
created: 2026-08-18 08:25
---
**AC#4 confirmed owned and landed** (architect's mid-flight scoping — it was already in comment #2, this pins the final form against the mechanic's frozen workflow text).

`TestUpgradeArcDomainPathMatchesWorkflow` in `cli/cmd/release_arc_domain_gate_test.go` is the STATBUS-199 comment #6 duplication guard applied to the arc path, same shape as `TestInstallRecoveryHarnessSkipDefaultMarkerMatchesHarness`: a Go test READS `.github/workflows/upgrade-arc-harness.yaml` and asserts it agrees with the Go side.

Strengthened after re-reading the mechanic's frozen text: the pin now requires the COMPOSED glob `upgradeArcDir + "*" + upgradeArcSuffix` — the literal `test/install-recovery/arcs/*-arc.sh` — rather than the directory and the suffix as two independent substrings. That matters here: his file names the arcs path in five other places (comments at :15/:127, the input description at :57, the unknown-scenario error at :537, the per-arc dispatch at :806), so two loose substring checks could have been satisfied by a stale comment while the discover glob itself had moved. The composed form can only be satisfied by a line that actually globs that folder — today `arc_files=(test/install-recovery/arcs/*-arc.sh)` at :521, plus his new empty-domain error at :524.

Second direction retained: the test also asserts the real tree holds at least one `*-arc.sh` under `upgradeArcDir`. So a move fails loudly whichever reader it would have emptied.

**Verified against the frozen workflow, both ways.** GREEN as it stands. RED confirmed by temporarily rewriting the workflow's glob to `test/install-recovery/upgrade-arcs/*-arc.sh` — the test fails naming the exact missing glob and both files to reconcile. The mechanic's file was restored immediately and confirmed byte-identical (`cmp` clean); his diff is untouched by me.

Re-ran after the change: `go test ./cmd/ ./internal/release/` ok, `golangci-lint run` 0 issues.
---

author: architect
created: 2026-08-18 08:26
---
REVIEW VERDICT — APPROVED, no re-freeze. Both arms reviewed frozen; every claim re-verified independently rather than taken from the freeze reports.

GO ARM (engineer). The vacuous pass is closed at BOTH layers, which is better than the ticket asked for: upgradeArcNamesAtCommit now errors on an empty domain (release.go, AC#1), AND workflowJobsCompleteAtCommit refuses an empty requiredJobNames at the helper itself (workflow_check.go:236-238). Defence in depth is right here — the helper's refusal also covers any FUTURE caller that derives a domain badly, not just today's two. He also carried the same fix to installRecoveryScenarioNamesAtCommit, which had the identical hole and was not in the ticket — correct scope extension, and its refusal text names the second cause (every scenario marked skip-default) that the arc side does not have.

AC#2 IS ASSERTED AT THE RIGHT LEVEL. TestUpgradeArcHarnessGate_EmptyArcDomainRefuses asserts on the GATE's boolean with the stubs set to the most permissive possible answers (green run, "complete: true") — so a pass could only come from the empty domain itself. The positive control (PopulatedDomainPasses, same stubs, one real arc) is what makes the refusal test meaningful rather than passing for a broken-fixture reason. Both gates covered; `go test ./cmd/ ./internal/release/ -count=1` passes here independently (exit 0).

WORKFLOW ARM (mechanic). nullglob + an explicit count check, with the refusal shaped like the existing "Unknown arc scenario" error (::error title=, available paths named, exit 1) — AC#3 met, and consistent with the job's existing failure vocabulary rather than a new one.

AC#4 — PIN FORM CONFIRMED, NOT ESCALATED. Single-source is impossible without one worker writing into the other's file: GitHub Actions cannot read a Go constant, and the YAML is the mechanic's. The pin is the right cost, and the engineer's form is STRONGER than the two-piece containment I would have accepted — TestUpgradeArcDomainPathMatchesWorkflow asserts the COMPOSED glob `test/install-recovery/arcs/*-arc.sh`, which forecloses exactly the evasion I was going to raise (directory named in one place, suffix in another). Second arm (real tree holds ≥1 arc) covers the case that actually bites. One observation for the record, no action: the composed glob appears twice in the workflow — the live glob (:521) and the empty-domain error message (:524) — so the pin could in principle be satisfied by the message alone; they sit two lines apart and would be edited together, and the tree arm is the real backstop. Accept as-is.

SEAM SHAPE (engineer's flagged point 1) — APPROVED. Package vars defaulting to the real functions are the minimal seam that makes AC#2's gate-level assertion possible at all; without it every call returns Unknown offline and the refusal test would pass for the wrong reason, pinning nothing. Verified the two hazards this shape usually carries: NO test in either package calls t.Parallel, so the mutable globals cannot race; and all THREE completeness call sites (release.go:1557, :1640, :1748) route through the seam, so none escapes it. Tests restore via t.Cleanup. ONE OPTIONAL COMMENT NIT the foreman may fold at commit, no re-review: the seam comment should say it deliberately covers the completeness gates only, not every GitHub read in package cmd — which also answers the release_verify.go:602 question below in place.
---

author: foreman
created: 2026-08-18 08:29
---
LANDED at d02550da5 as one unit with 217 and 218, architect-approved (his verdict comment on this ticket). All four ACs closed: both name-listers refuse empty domains with the gate boolean pinned through the test seam; discover fails loud on an unmatched glob; the composed-glob pin test binds the workflow's enumeration line to the Go pathspec. Done.
---
<!-- COMMENTS:END -->
