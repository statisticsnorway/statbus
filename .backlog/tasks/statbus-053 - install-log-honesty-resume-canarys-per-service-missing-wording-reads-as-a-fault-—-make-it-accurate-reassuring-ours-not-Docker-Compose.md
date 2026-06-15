---
id: STATBUS-053
title: >-
  install-log-honesty: resume canary's per-service 'missing' wording reads as a
  fault — make it accurate + reassuring (ours, not Docker Compose)
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-15 11:08'
updated_date: '2026-06-15 11:11'
labels:
  - upgrade
  - install-log-honesty
  - operator-ux
dependencies: []
references:
  - cli/internal/upgrade/containers.go
  - cli/internal/upgrade/service.go
priority: medium
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King-raised 2026-06-15 (screenshot of an upgrade on another cloud install): the post-swap container report shows "app: missing / worker: missing / rest: missing" (+ "db: tag=… (want …)"), which reads as an alarming fault to an operator testing an upgrade — not reassuring for the external-standalone confidence the campaign is building toward.

## VERIFIED: this is OUR text, not Docker Compose
cli/internal/upgrade/containers.go, evaluateContainersAtFlagTarget (the resumePostSwap self-heal canary):
- L142 `fmt.Sprintf("%s: missing", svc)` — the container is not in `docker compose ps` (not created/running).
- L146 `"%s: state=%q (want running)"` — container exists but is stopped.
- L155 `"%s: tag=%q (want %q or %q) image=%q"` — running but at the wrong image tag.
Logged at service.go:4709-4711 (the EXPECTED forward-roll case = the King's screenshot) and service.go:4684-4695 (the genuine-failure case).

## The intent already exists — only the words were left undone
service.go:4697-4701 already carries the comment: "'mismatched' is the expected post-swap state — the prior process stopped containers on purpose with old images so the new binary can restart them with target tags. The list reads as a fault ONLY because of word choice and one-line formatting. Break into a header + per-container lines so the operator can scan it." The 039 work added the reassuring HEADER (service.go:4706: "containers carry pre-upgrade tags (expected — restarting on target tag). Resuming via applyPostSwap.") but never updated the per-line WORDS. So the header says "expected" while the lines still say "missing." This task completes that stated intent.

## Accuracy nuance (so the new wording is honest, not just softer)
"missing" = the CONTAINER is absent from `docker compose ps` — NOT (necessarily) that the image needs downloading. The very next steps reconcile it: "Regenerating configuration → Pulling updated images → Starting services" (pull-if-needed + (re)create). So the King's suggested "needs download / scheduled for download" is the right SPIRIT but imprecise; "not started yet (will be (re)created)" is accurate. Also: the SAME mismatch strings appear in BOTH the reassuring (expected) and the genuine-failure context, so the WORDS must stay accurate in both — make them neutral-factual and let the surrounding header carry the reassurance (expected) or the alarm (failure).

## Proposed direction (King to bless the exact operator voice)
- "missing" → "not started yet" (neutral-factual; the upcoming `up -d` creates it)
- "state=X (want running)" → "stopped (state=X)"
- "tag=X (want Y)" → "on prior tag X (target Y)"
- Optional reassuring lead in the EXPECTED case only (service.go:4702-4711): e.g. "Services not yet at the target version — will be brought up:" before the per-line list.

## Scope / DoD
- Cosmetic ONLY: the canary DECISION is `len(mismatched)==0` (containers.go:159) — unchanged. Only the human-readable strings + the expected-case framing change.
- Update postswap_test.go:310-311 (comment referencing "app: missing worker: missing rest: missing") + any string-asserting test.
- go -C cli vet/build/test green. do-not-self-commit: report to foreman with the diff for review + commit.
- King blesses the final operator voice before commit (operator-facing UX).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The per-service canary strings (containers.go evaluateContainersAtFlagTarget) are accurate AND non-alarming in BOTH the expected-forward-roll and genuine-failure contexts; 'missing' is reframed to a neutral-factual term (e.g. 'not started yet'), not left reading as a fault
- [ ] #2 The EXPECTED forward-roll case (service.go:4702-4711) reads clearly as 'these are expected and will be brought up' end-to-end (header + per-line words agree)
- [ ] #3 The exact operator-facing voice is blessed by the King before commit
- [ ] #4 Cosmetic only: the canary decision (len(mismatched)==0) is unchanged; postswap_test.go comment + any string-asserting test updated; go vet/build/test green
- [ ] #5 do-not-self-commit: foreman byte-level reviewed + committed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
King 2026-06-15: 'File and have someone fix it right away' — wording DELEGATED to us (AC#3 bless-gate is satisfied by that delegation; ship accurate non-alarming text, foreman reviews at commit). Assigned mechanic, In Progress.

CHOSEN WORDING (neutral-factual — accurate in BOTH the expected-forward-roll AND genuine-failure contexts; NOT forward-looking-only):
- containers.go L142 '%s: missing' → '%s: not running (no container)'
- containers.go L146 '%s: state=%q (want running)' → '%s: not running (state=%q)'
- containers.go L155 '%s: tag=%q (want %q or %q) image=%q' → '%s: running on tag %q (target %q or %q) image=%q'
The reassurance is carried by the existing expected-case header (service.go:4706 'containers carry pre-upgrade tags (expected — restarting on target tag)'); an optional one-line lead before the per-service loop (~service.go:4709) is allowed if it reads better. Logic (len(mismatched)==0) unchanged; tests/comments updated; do-not-self-commit.
<!-- SECTION:NOTES:END -->
