---
id: STATBUS-085
title: >-
  selfheal-advice-strings: stalenessGuard's non-self-heal + ambiguous-identity
  branches still tell operators './dev.sh cross-build-sb' — wrong on a
  no-host-Go box
status: To Do
assignee: []
created_date: '2026-06-18 08:34'
labels:
  - install-recovery
  - rc.04-followup
dependencies: []
priority: low
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Engineer flag from the STATBUS-084 build-fix review. The self-heal branch now procures from Docker, but root.go's NON-self-heal hard-fail branch (~root.go:104) and the ambiguous-identity branch (~:178) still advise `./dev.sh cross-build-sb`, which fails on a toolchain-less production box (Albania). Reword to Docker-procurement advice. Low-severity (advice strings only), out of the 084 blast radius.
<!-- SECTION:DESCRIPTION:END -->
