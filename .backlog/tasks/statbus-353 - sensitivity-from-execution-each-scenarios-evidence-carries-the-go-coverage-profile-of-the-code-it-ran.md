---
id: STATBUS-353
title: >-
  sensitivity from execution: each scenario's evidence carries the Go coverage profile of the code it ran, and a diff is sensitive only if it touches that code
status: To Do
assignee: []
created_date: '2026-09-04 10:21'
updated_date: '2026-09-04 10:21'
labels:
  - release
  - cli
  - cost
dependencies:
  - STATBUS-352
priority: medium
type: task
ordinal: 346000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## The idea

After STATBUS-352 the Go part of the sensitivity set is "every package the box-side binary can reach". That is still the whole binary for every scenario: a change to the park/un-park code makes `0-happy-install` re-run, though a fresh install never parks. The exact set is smaller and per scenario: the functions that scenario actually executed.

Go 1.20+ can build a binary with `-cover`; at run time, with `GOCOVERDIR` set, it writes a coverage profile per process. If each harness scenario runs an instrumented `sb`, collects the profiles from the VM, and uploads them next to its log, the scenario's evidence says exactly which functions it exercised. A later candidate is then covered by that evidence if its diff touches none of those functions.

## What to do

1. **Instrumented build:** `./dev.sh build-sb --cover` (`go build -cover -coverpkg=./...`). The harness (`test/install-recovery/lib/vm-bootstrap.sh`) exports `GOCOVERDIR=/var/lib/statbus/cover` for every `./sb` invocation on the VM, including the systemd unit's environment, and copies the directory back with the logs. The install-recovery and upgrade-arc workflows upload it as an artifact named `cover-<scenario>`.
2. **Profile to function set:** `go tool covdata textfmt` gives per-file line blocks. Map blocks to top-level function declarations with `go/ast` at the commit the profile came from, producing a set of `package.Func` names. Store that set as the scenario's evidence detail (artifact or a small JSON next to the log).
3. **Diff to function set:** for the diff between the anchoring tag and the target, parse both sides with `go/ast` and produce the set of functions whose body text differs (line numbers shift; compare by name and body hash, not by line). A renamed or deleted function counts as touched; a new function counts as touched only if something in the executed set now calls it (conservative: treat any change in a file the scenario executed as touched, until call-graph precision is worth it).
4. **`DecideCoverage`:** when the anchoring evidence carries a function set, use step 3 instead of the path list for `.go` files. Non-Go artefacts keep the path list from 352. When no profile exists (older evidence), fall back to 352's package closure and say so in the output.
5. **Fidelity, named up front:** the two smokes exist to run the RELEASED binary (STATBUS-339). An instrumented build is a different binary. Profiles therefore come from the fleets only (they already build `sb` from the commit); the smokes keep proving the released artefact and inherit sensitivity from the fleet profile of the same scenario name (`0-happy-install` and `0-happy-upgrade` run in both).

## Done when

- Every fleet scenario's run uploads a coverage artifact, and `./sb release covered <scenario> <sha>` names the anchoring run's function set size and the touched functions that blocked coverage, if any.
- A commit that changes only `internal/upgrade` park/un-park code reports `0-happy-install` covered and `postswap-health-park` must-run.
- A commit that changes a function no scenario executed (dead or tool-side) reports every scenario covered.
- Evidence without a profile still decides via 352's closure and prints `no coverage profile at <tag>; decided by package closure`.

## Why after 352

352 makes the box/tool split real in the tree and gives the fallback this ticket needs. Without it, a profile-less anchor has no sound rule to fall back on.
<!-- SECTION:DESCRIPTION:END -->
