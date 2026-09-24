---
id: STATBUS-408
title: >-
  A fresh install interrupted after the database exists continues where it
  stopped on the next run
status: To Do
assignee: []
created_date: '2026-09-24 15:46'
labels:
  - install
  - recovery
  - database
dependencies: []
references:
  - /Users/jhf/ssb/.jcode/scratch/rest-loop.md
priority: high
type: bug
ordinal: 361000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A rerun recognizes a database created by an incomplete first installation and resumes from the first incomplete step. The pre-1.0 classification remains reserved for an established legacy installation.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

A Hetzner Ubuntu 26.04 VM confirmed that a port-80 failure after database creation leaves the database reachable without `public.upgrade`. Every rerun was then refused as a pre-1.0 installation by `install/state.go:141-147`, before seed or migrations could continue. This recovery dead end encourages removal of the installation directory while the database volume survives, which can create a credentials split.

Related: STATBUS-411 covers a newly initialized database after removing and recreating its volume, rather than this ticket's interrupted install with the original volume retained. Both need the same state distinction but separate harness scenarios.

## Proving scenario

In install-recovery, hold port 80 through step 8, confirm the database volume exists, then free the port and run the one install command. The rerun identifies an incomplete fresh installation, resumes at the first incomplete step, and reaches green with the original volume.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A reachable database without the upgrade table is recognized as an incomplete fresh installation when first-install markers show setup is unfinished.
- [ ] #2 The next run resumes at the first incomplete step and preserves the existing database volume.
- [ ] #3 Established pre-1.0 installations continue to receive the legacy upgrade guidance.
- [ ] #4 The interrupted-after-database harness scenario reaches green through the one install command.
<!-- AC:END -->

## Review correction 2026-09-24

Use `cli/internal/install/state.go:141-147` and exact VM reproduction lines from `/Users/jhf/ssb/.jcode/scratch/rest-loop.md`. Add **new** `test/install-recovery/scenarios/5-install-interrupted-after-database-created.sh`, inducing failure after database creation rather than a port-80 preflight. Shared STATBUS-408/411 marker semantics must distinguish interrupted first install from established pre-1.0 using exact upgrade-table/schema/seed markers, cover both fake-probe edge cases, and observe preserved data.
