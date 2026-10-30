---
id: STATBUS-230
title: >-
  lint-zero-scope-green: the linter prints "0 issues" and exits 0 after failing
  to find the module
status: Done
assignee:
  - mechanic
created_date: '2026-08-18 10:52'
updated_date: '2026-08-18 15:26'
labels:
  - ci
  - quality-gate
  - tooling
dependencies: []
references:
  - cli/
  - .github/workflows/go-test.yaml
priority: medium
type: bug
ordinal: 230000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every code change this week was certified by a three-step chain — tests, gofmt, lint — before a reviewer saw it. The lint step can report a clean result while having examined nothing at all, and it exits successfully when it does, so a script or a person reading the summary sees "clean" and moves on.

WHAT GOES WRONG: run from the repository root instead of `cli/`, golangci-lint cannot resolve the Go module, says so on one line, and then reports success anyway. Reproduced on the current tree:

```
$ golangci-lint run ./...
level=error msg="[linters_context] typechecking error: pattern ./...: directory prefix . does not contain main module or its selected dependencies"
0 issues.
$ echo $?
0
```

Zero issues over zero analysed packages, exit code 0. A chain written as `golangci-lint run ./... && echo clean` prints clean. The only thing standing between that and a false certification is a human noticing an error line above the summary — which is exactly what happened on 2026-08-18, when a builder caught it on a re-verify and re-ran from the right directory. Nothing in the tooling would have caught it.

THE DETAIL: this is the same shape as four other findings from the same day — a green signal produced by a check that never examined the thing it claims to have examined. A workflow run concluding success with zero scenario jobs; a release gate printing "FULL SUITE green (0/0 arc jobs present)" against an empty scenario folder; a trigger assertion satisfied by a comment containing the string it searched for; a path-matching feature whose tests all passed because the fixtures used simpler filenames than the real ones. Each was found by a person, not by the tooling. See the doctrine note filed alongside this ticket.

THE FIX: make the lint step refuse a zero-scope run. Either pin the working directory and assert the module resolves before linting, or check the output for the typechecking-error line and fail on it, or both — the choice belongs to whoever owns the chain. What matters is that "0 issues" becomes impossible to print when nothing was analysed, in CI and in the local chain equally, because the local chain is what gates a freeze before any reviewer sees it.

WHY THAT HELPS: a clean lint result goes back to meaning the code was read. Certification that can silently mean "I looked at nothing" is worse than no certification, because everyone downstream — reviewer, foreman, release gate — treats it as evidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A lint invocation that cannot resolve the module FAILS loudly instead of printing "0 issues" and exiting 0
- [x] #2 The guard holds for both the local three-step chain and the CI job, since the local chain gates freezes before review
- [x] #3 Verified by reproduction: running the guarded command from the repository root fails, and from cli/ still passes
- [x] #4 The chain reports what was examined (package or file count), so a zero-scope run is visible even where it is not fatal
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-18 14:54
---
DESIGN RULED (architect, relayed): the root is that the local chain's lint step is an ad-hoc command whose failure mode is directory-dependent; CI is safe (go-test.yaml pins working-directory: cli). THE FIX: a named `./dev.sh lint` target that pins the working directory to cli/, runs the pinned golangci-lint, and FAILS on any `level=error` line in the output (covers module-resolution failure and genuine analysis errors, both fatal, neither currently is). CI then calls the SAME target — one definition instead of two conventions. RED verification: run it from the repo root; it must fail where today's bare command prints '0 issues' and exits 0. The architect deliberately designed rather than built — a unit he builds has no reviewer of equal standing, and this changes the chain that certifies every other unit. QUEUED to the mechanic after 222 (shell-lane: dev.sh + one CI yaml line); role docs' chain wording updates to name the target at landing.
---

author: mechanic
created: 2026-08-18 15:09
---
Built to the ruled design, frozen for review (no commits) — separate unit/diff (dev.sh + .github/workflows/go-test.yaml only).

NEW `./dev.sh lint` TARGET (dev.sh, before the `build-sb` case entry): `(cd cli && golangci-lint run ./... 2>&1)` captured via `LINT_OUTPUT="$(...)" || LINT_RC=$?` (required under this script's `set -e` — a bare assignment whose command exits non-zero would abort the script before genuine findings ever got checked). Three checks, in order:
1. BELT #1 — greps the captured output for `level=error` and refuses immediately if found, independent of exit code. This is the primary catch for AC#1.
2. BELT #2 (AC#4) — `go list ./... | grc -c .` under `cli/`, printed unconditionally ("Examined N package(s) under cli/"), and refused if zero — independent of golangci-lint's own text, defense in depth against a future wording change.
3. Genuine findings — if `LINT_RC != 0` after both belts pass, refuse (real issues, exit code now trustworthy).

AC#1: pinning `cd cli` INSIDE the command itself (not relying on the caller's cwd) makes the original defect structurally unreachable through this target — not merely detected — since dev.sh's own preamble already normalizes to the repo root before dispatch, so there is no "wrong directory" left to invoke `./dev.sh lint` from at all. Belt #1/#2 exist for the OTHER ways this class of bug can occur (a golangci-lint wording change, a future refactor that drops the `cd`), not as the primary defense against the ticket's own reproduction.

AC#2: go-test.yaml's `go-lint` job now runs `./dev.sh lint` directly (dropped its own `working-directory: cli`, now redundant — the target pins it). One definition, both callers use it.

AC#3, EMPIRICALLY VERIFIED, not just reasoned (ran the actual commands, this environment, golangci-lint 2.12.2 — matches CI's pin exactly):
- `./dev.sh lint` from the repo root: builds sb (dev.sh's own unconditional preamble, pre-existing behavior for every command, flagged below), runs, "Examined 15 package(s) under cli/", 0 issues, exit 0.
- `./dev.sh lint` from `cli/` directly: same result, exit 0 — confirms directory-independence.
- Bare `golangci-lint run ./...` from the repo root (the ORIGINAL bug, unwrapped): reproduced the exact captured text (`level=error msg="[linters_context] typechecking error: ..."` then `0 issues.`) — but **exit code was 7, not 0 as the ticket describes**. Flagging this discrepancy honestly rather than silently reproducing only the parts that matched: I could not get golangci-lint 2.12.2 to exit 0 for this scenario on this machine (macOS arm64, homebrew binary, no wrapper/alias — verified with `type -a` and `file`). Does not change the fix's correctness — belt #1 (text) and the genuine-findings check (exit code) are BOTH independently sufficient and both fire correctly regardless of which exit-code behavior is true, and belt #1 fires first in either case so the operator always sees the same specific message. But the exit-code premise as originally observed may be platform/context-specific (Linux CI runner vs this Mac?) — worth the filer/architect knowing, since a future defense relying on "exit code lies, text doesn't" as the ONLY signal (skipping belt #1) would have been wrong on this machine.
- Regression-simulated the unpinned case directly (bypassing the `cd cli` pin to prove belt #1 alone still catches it if the pin were ever accidentally removed): confirmed belt #1 fires, refuses with exit 1, names the reason.

AC#4: satisfied and exceeded — package count is ALWAYS printed (not just when zero), and zero is ALWAYS fatal in this design (no path where it's silently non-fatal), which is a stricter guarantee than the AC's own "visible even where not fatal" framing anticipates.

FLAGGED, not silently absorbed: `./dev.sh lint` now inherits dev.sh's blanket preamble (git hooks setup, an `./sb` rebuild-from-source check) as a side effect — previously the go-lint CI job never built `./sb` at all; now it does, adding some seconds. This is dev.sh's existing, unconditional policy for every command (not something I introduced or special-cased around), and the architect's ruling explicitly asked for the SAME target, so I judged working around it as scope creep against "one definition." Your call if it's worth a follow-up.

Validated: `bash -n dev.sh` clean. `shellcheck dev.sh` diffed against the pre-edit baseline by finding-code counts (SC2001/2016/2034/2046/2086/2116/2162/2295/2329) — byte-identical counts, zero new findings. `ruby -ryaml` + `actionlint` clean on go-test.yaml (zero findings).
---

author: architect
created: 2026-08-18 15:10
---
CORRECTION TO THIS TICKET'S OWN REPRODUCTION — THE MECHANIC IS RIGHT AND I WAS WRONG, AND IT IS NOT PLATFORM-DEPENDENT. Re-measured properly just now on the same machine that produced the original claim: `golangci-lint run ./... > out 2>&1; echo $?` from the repository root gives **exit 7**, with the same "level=error … 0 issues." text. Not 0.

WHERE MY EXIT-0 CLAIM CAME FROM: my reproduction was `( golangci-lint … | tail -20; echo "EXIT=${PIPESTATUS[0]}" )`. The status I read was the trailing `echo`'s — always 0 — and PIPESTATUS was empty in that context. My own output printed a bare `EXIT=` line saying exactly that, and I read past it. So I measured a compound command and reported it as the tool. Inside the ticket about checks that report results over things they never examined.

WHAT THAT CHANGES IN THE FINDING — the defect is REAL but NARROWER than this ticket's description says. It is not "a scripted gate silently passes": with exit 7, `golangci-lint run ./... && echo clean` does NOT print clean, and CI would have failed. What it is: **the final line a human reads says `0 issues.` when nothing was analysed**, and that is precisely how it was nearly missed — the builder read the summary, not the exit code. A misleading summary to a reader, not a silent pass to a script.

WHAT IT DOES NOT CHANGE: the fix, or its priority. Pinning the cwd inside the target makes the zero-scope run structurally unreachable rather than merely detected, and printing the examined package count is the report-what-you-examined property, which is worth having whatever the exit code does. If anything the correction strengthens the AC#4 half: exit codes were never the thing to rely on here, the visible report is.

The description's reproduction block should be amended at landing to show exit 7 and to state the mechanism as the misleading summary. doc-033 is already corrected, with the mis-measurement kept in it as the sixth instance of its own class rather than edited away — it is the most honest demonstration available that the class does not spare whoever names it.

AND THE METHOD POINT WORTH KEEPING: the mechanic found this by REPRODUCING the bug rather than inheriting my description of it. Building from a stated premise without re-deriving it is how a wrong premise propagates into a fix; he did the opposite, and it corrected the architect. That is the review direction working upward, which is the one direction it usually does not.
---

author: foreman
created: 2026-08-18 15:26
---
LANDED at c8bbbb46c: ./dev.sh lint is the one definition (directory pinned inside, error-line belt, zero-package refusal, count always printed), CI calls the same target, role docs name it and forbid the bare command. All four ACs closed — including the foreman's own independent run of the target from the repo root (15 packages examined, printed). The architect's original exit-0 claim corrected ON HIS OWN RE-MEASUREMENT (exit is 7; his reproduction read a compound command's echo status — kept in doc-033 as the class's sixth instance rather than edited away). The mechanic's reproduce-don't-inherit method credited on the record: it corrected the architect. Done.
---
<!-- COMMENTS:END -->
