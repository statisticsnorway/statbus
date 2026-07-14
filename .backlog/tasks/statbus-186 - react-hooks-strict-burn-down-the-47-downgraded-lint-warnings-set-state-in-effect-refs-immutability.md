---
id: STATBUS-186
title: >-
  react-hooks-strict: burn down the 47 downgraded lint warnings
  (set-state-in-effect, refs, immutability)
status: To Do
assignee: []
created_date: '2026-07-14 19:08'
labels:
  - quality-gate
  - typescript
  - frontend
dependencies: []
priority: low
ordinal: 187000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the app's ESLint gate carries zero standing warnings — the react-hooks v6 strict findings the STATBUS-177 introduction downgraded to 'warn' get real refactors, then the rules return to 'error'.
> ORIGIN: STATBUS-177 (2026-07-14) landed the no-explicit-any gate minimal-first; next/core-web-vitals shipped 22 non-any errors (react-hooks/set-state-in-effect ×11, react-hooks/refs ×7, immutability ×2, react/no-unescaped-entities ×2 — 47 warning occurrences total under warn) that are real React refactors, distinct from the any burn-down. Downgraded deliberately so the gate wasn't buried; this ticket is the promise that they don't rot as permanent warnings.
> NOTE: the codebase also carries ~18 pre-existing unjustified eslint-disable comments (no-var, no-console, exhaustive-deps, 4 bare no-explicit-any) from before ESLint existed — sweep them in the same unit: justify, fix, or remove.
> COMPLEXITY: engineer; the set-state-in-effect fixes interact with the Jotai/useGuardedEffect conventions (frontend rules) — follow .claude/rules/frontend.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The four downgraded rules return to error with zero findings (real refactors, not disables)
- [ ] #2 Pre-existing unjustified eslint-disable comments swept: justified, fixed, or removed
- [ ] #3 pnpm run lint: 0 errors, 0 warnings
<!-- AC:END -->
