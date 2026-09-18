---
id: STATBUS-374
title: >-
  release pre-flight regressed by runtime executable allowlist: enforce
  launch-site policy statically
status: Done
assignee: []
created_date: '2026-09-18 13:16'
updated_date: '2026-09-18 13:16'
labels:
  - release
  - cli
  - fail-fast
dependencies: []
references:
  - STATBUS-369
priority: high
type: bug
ordinal: 1
---

## Incident (2026-09-18 morning)

On clean master `69e13bd0c`, the owner ran `./sb release prerelease` twice
with a host Go toolchain. Both runs reported only:

    ✗ Go CLI builds

There was no compiler output, while `cd cli && go build ./...` succeeded.
The release pre-flight itself had regressed.

## Root cause

The rc.17 fix set and review rounds 8-9 (`e276e06b4`, then `44a0cb394`)
turned `cli/internal/upgrade`'s `commandContext` into a runtime executable
allowlist. It admitted a closed set including `git`, `docker`, `rsync`, `sb`,
and `dev.sh`. `release.go:138` sent `go build` through
`upgrade.RunCommandOutput`, so the allowlist refused the host `go` executable
before the compiler ran.

The review battery proved the typed Compose-up authority gate and ran Go tests,
but never executed the operator workflow `./sb release prerelease`. The result
was a silent pre-flight failure on the exact clean tree the gate was meant to
admit.

## Process cause

The runtime allowlist was over-engineering: it enforced a static source
property at runtime, duplicated the `go/types` gate, hid the contract behind a
runtime error, and failed the operator instead of the developer. It stood in
for the necessary elaboration: enumerate every process-launch site and
investigate why each site exists.

The origin trace in `tmp/origin-trace.md` attributes that design to coordinator
session `rabbit` on model `k3`. Its round-6 brief moved the invariant to a
runtime chokepoint and escalated the design through round 10. The implementers
(Sol, effort high) and reviewers (Terra and Luna) followed and reviewed that
brief; they were not the source of the runtime-enforcement inference.

## Agreed design principle

Process-launch authority that is a property of source code is enforced in a
static, type-resolved test:

1. Enumerate every launch site by type resolution, including the generic
   upgrade runners.
2. Give every approved site an entry with an exact `Count` and a genuinely
   site-specific `Reason`.
3. Fail on a new, changed, duplicate, or stale site, naming the site that needs
   review.
4. Keep runtime checks for runtime facts. Do not use a runtime executable
   switch to enforce the static inventory.

## Resolution

Done in `7244856d5` (`release: restore host Go preflight build`):

- removed the runtime executable switch from `commandContext`;
- enforced 187 site-specific launch reasons, with empty, duplicate, and
  boilerplate reasons rejected;
- invoked the host Go tool directly for release pre-flight compilation;
- changed cleanliness checking to `git status --porcelain --untracked-files=all`,
  replacing diff-based checks that missed untracked files; and
- gated `dev.sh` binary procurement on host platform.

The regression and the static-policy principle are recorded here as part of
STATBUS-369's release-ladder history.
