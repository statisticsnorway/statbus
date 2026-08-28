---
id: STATBUS-272
title: >-
  worker-fatal-refinement: after 265, a read-only refusal at the reset means the
  exemption did not take — the FATAL should say so first; and the
  sequential-startup coupling needs its note at the line
status: Done
assignee: []
created_date: '2026-08-27 13:15'
updated_date: '2026-08-28 22:41'
labels:
  - worker
dependencies: []
priority: low
type: enhancement
ordinal: 265000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two ruled refinements from the 264+265 landing review (architect, 2026-08-27), deliberately NOT held against the rc.10-blocking pair:

1. THE TICKETS CHANGED EACH OTHER'S MEANING: 264's exhaustion FATAL was written for a world where a read-only refusal at the reset was expected; 265 makes it nearly unreachable (the exemption is a SET, which succeeds even against a read-only default). With both landed, a read-only refusal at the reset means THE EXEMPTION DID NOT TAKE — sharper and more alarming than "the database may be read-only on purpose". The FATAL should lead with that diagnosis, keeping the deliberate-cases guidance (window/abort-hold/maintenance) as the secondary branch. As written it sends a responder to check deliberateness when the real answer is a failed exemption — diagnostic misdirection of the class the week was spent removing.

2. LATENT COUPLING, note at the line: 265's SET/RESET scoping is safe BECAUSE worker startup is sequential — nothing else uses the shared connection between SET and RESET. If the worker ever gains concurrent startup work on that connection, the exemption leaks into user work and the guard quietly stops guarding. Two mechanisms holding each other up must say so where the next editor will look (same rule as the dismiss/re-arm interlock).

WHAT IS ACHIEVED: the crash-loop's first line names the actual failure, and the invariant that keeps the exemption safe is written where it will be seen before it is broken.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLOSED at the worker FATAL-reorder commit: message leads with the exemption-failure diagnosis (secondary-check labeling for the deliberate cases, strengthened closing line covering all three SET sources), latent-coupling note at the SET/RESET site. No test pinned the text (grepped first); verified via entrypoint build + mutation-proof-of-reach (undefined-var planted in the new text failed the build at the exact line, reverted byte-identical); pre-existing crystal-format drift left untouched as out of scope.
<!-- SECTION:NOTES:END -->
