---
id: STATBUS-234
title: >-
  test-cache-stale-green: a cached test pass can vouch for files it never
  re-read — one flag makes every pin re-examine reality
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-18 15:38'
updated_date: '2026-08-18 15:42'
labels:
  - ci
  - quality-gate
  - tooling
dependencies: []
references:
  - .github/workflows/go-test.yaml
  - dev.sh
  - .claude/team/engineer.md
priority: medium
type: bug
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several of our most important tests are pins: they read files OUTSIDE the Go module — workflow YAML, the exempt list, shell scripts — and assert facts about them. Go's test cache does not track those outside files, so a cached "ok" can vouch for content that has since changed.

WHAT THE EVIDENCE SHOWS (engineer, 2026-08-18, demonstrated not reasoned): prime the cache with a green run, append an entry to ops/release/ci-exempt-paths.txt, re-run without -count=1 — "ok (cached)", a green that examined nothing current. The seventh instance of doc-033's class: a check reporting a verdict over something it never read. Applies to the whole pin family (arc-path pin, run.sh marker pin, images-never-rides pin, trigger pins, exempt-list equality pin), not just the newest. CI exposure is PLAUSIBLE but unconfirmed: go-test.yaml runs plain go test ./... and setup-go@v5 caches by default — verify, don't inherit, per the house rule.

THE FIX: -count=1 on the CI go test invocation (one flag in go-test.yaml), the same in dev.sh's chain if it runs go test anywhere, and the role docs' freeze chain already says -count=1 informally — make it uniform. Verify the CI-exposure question empirically while in there (does a cached pass actually survive across CI runs with setup-go's cache?) and record the answer either way.

WHAT IS ACHIEVED: a pin's green goes back to meaning "I read the file today" — the property the entire pin strategy stands on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI's go test runs with -count=1 (and dev.sh's chain where applicable); the change is commented with the outside-module cache gap
- [ ] #2 The CI-exposure question answered empirically and recorded: could a cached pass have crossed CI runs before this fix
- [ ] #3 Role docs' chain wording names -count=1 uniformly
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 15:42
---
Built, frozen for review (no commits). Files: .github/workflows/go-test.yaml, .claude/team/engineer.md, .claude/team/mechanic.md.

AC#1: go-test.yaml's `go test` step now runs `go test ./... -count=1`, comment names the outside-module cache gap (workflow YAML, ops/release/*.txt, shell scripts — the whole pin family) and cites the engineer's 2026-08-18 demonstration verbatim. Checked dev.sh for any `go test` invocation — `grep -n "go test" dev.sh` returns NO MATCHES (exit 1) — dev.sh has no go-test wrapper at all today (only `./dev.sh lint` from STATBUS-230 wraps a quality-chain step; go test and gofmt are still raw ad-hoc commands run directly in cli/, per the engineer's own STATBUS-219 freeze reports). Nothing to change there — verified, not silently skipped. fast-tests.yaml's own `go test` invocation (line 208, a single targeted test) already carries `-count=1` — pre-existing, confirmed unaffected.

AC#3: engineer.md and mechanic.md are the ONLY role docs mentioning `go test` at all (grepped all of .claude/team/*.md — architect.md/foreman.md/operator.md/tester.md/README.md don't mention it). Both updated: `go test ./...` → `go test ./... -count=1`, each with an inline parenthetical naming the outside-module-pin cache gap so the wording carries the reason, not just the flag.

AC#2, EMPIRICALLY ANSWERED via `gh run view --log` on real CI history, not reasoned: **NO — a cached pass could NOT have crossed CI runs before this fix, for a reason stronger than luck.** Found the smoking gun in the `Set up Go` step's own log (run 32151213525, a genuinely consecutive board-only push — verified `git diff --stat <prev>..<this> -- cli/` is empty, so cli/'s Go source was byte-identical to the previous run):
```
##[warning]Restore cache failed: Dependencies file is not found in /home/runner/work/statbus/statbus. Supported file pattern: go.sum
```
`actions/setup-go@v5`'s `cache: true` (default) looks for `go.sum` at the REPO ROOT, but this repo's go.mod/go.sum live in `cli/` — so the cache-restore step silently no-ops on EVERY run, `GOCACHE` starts fresh every time, and every test result line in every go-test.yaml run I checked shows a real timing (`9.333s`, `0.025s`, etc.), never `(cached)`. Checked multiple consecutive board-only-push run pairs (02fd57142c→cc84e0771d→47e7aee0fc, all cli/-diff-empty) — same result every time.

So the CI exposure was NEVER actually reachable — not because nothing could go stale, but because an UNRELATED, pre-existing setup-go misconfiguration has been accidentally keeping CI's test cache permanently cold. FLAGGING THIS AS ITS OWN FINDING, not fixed here (out of 234's stated scope — the ticket asks for -count=1 + the empirical answer, not a setup-go fix): `cache-dependency-path: cli/go.sum` on the `actions/setup-go@v5` step would make the cache restore actually work, which would be a real CI speed win (currently every run rebuilds from scratch) — but would also flip AC#2's current "no" answer to a live "yes" the moment it's applied, making THIS ticket's -count=1 fix load-bearing for the first time rather than redundant-but-correct. Your call whether that's worth its own ticket; noting it so nobody 'fixes' the cache restore later without knowing -count=1 is what makes that safe.

The LOCAL exposure (the one the engineer actually demonstrated) is real regardless of any of this — a developer's own `$GOCACHE` absolutely does persist across `go test` invocations in the same working copy, which is exactly how the bug was found. -count=1 in CI and in both role docs' freeze-verification wording is fully justified independent of the CI-cache finding above.

Validated: `ruby -ryaml` + `actionlint` clean on go-test.yaml (zero findings). Ran `go test ./... -count=1` in cli/ for real — all packages report real timings, exit 0, confirming the flag doesn't break anything and behaves as expected.
---
<!-- COMMENTS:END -->
