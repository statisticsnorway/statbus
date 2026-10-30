---
id: STATBUS-085
title: >-
  selfheal-advice-strings: stalenessGuard's non-self-heal + ambiguous-identity
  branches still tell operators './dev.sh cross-build-sb' — wrong on a
  no-host-Go box
status: Done
assignee: []
created_date: '2026-06-18 08:34'
updated_date: '2026-07-08 22:04'
labels:
  - install-recovery
  - rc.04-followup
dependencies: []
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every error message proposes an action that works on the box it appears on.
> BENEFIT: two failure branches stop telling a toolchain-less production operator to run a command that cannot work there ("./dev.sh cross-build-sb") — impossible advice at a failure moment is worse than no advice.
> STAGE: Stage 1 → Stage 3.
> COMPLEXITY: mechanic-simple (two advice strings).
> DEPENDS ON: nothing.

---

Engineer flag from the STATBUS-084 build-fix review. The self-heal branch now procures from Docker, but root.go's NON-self-heal hard-fail branch (~root.go:104) and the ambiguous-identity branch (~:178) still advise `./dev.sh cross-build-sb`, which fails on a toolchain-less production box (Albania). Reword to Docker-procurement advice. Low-severity (advice strings only), out of the 084 blast radius.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: an error message's advice must be executable by the person reading it, on the box they read it on. SHIPPED 5197d7eee (2026-07-08), dual-reviewed. Three messages fixed, not the ticket's two — the engineer's grep found the load-bearing third: the shared stale-drift message in freshness.IsStale, which is what a stale production box actually prints (single production consumer: the staleness guard itself, grep-verified). Identified-stale → the install command's toolchain-free procure. No commit identity → the documented rescue bootstrap, byte-identical to the canonical one-liner (verified against README and DEPLOYMENT docs) — that branch exits before the procure dispatch and has no commit to procure against, so nothing gentler can work; this is the deployment doctrine word for word. Developer toolchain commands survive only as marked secondary lines. Guard logic untouched. Two pin tests keep toolchain-primary advice from returning.
<!-- SECTION:FINAL_SUMMARY:END -->
