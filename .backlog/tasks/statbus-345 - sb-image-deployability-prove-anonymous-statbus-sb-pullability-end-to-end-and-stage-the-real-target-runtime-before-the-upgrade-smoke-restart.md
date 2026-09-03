---
id: STATBUS-345
title: >-
  sb-image-deployability: prove anonymous statbus-sb pullability end to end, and
  stage the real target runtime before the upgrade-smoke restart
status: In Progress
assignee: []
created_date: '2026-09-02 14:07'
updated_date: '2026-09-03 08:42'
labels:
  - release
  - test-harness
  - defect
dependencies: []
priority: high
type: bug
ordinal: 338000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rc.03's smoke failures exposed two false assumptions (RCA 2026-09-02, on the ticket in full via the foreman; retag chain and cleanup EXONERATED — the sb manifest existed and was authenticated-pulled at 12:44 UTC):
1. VISIBILITY, not absence: the statbus-sb GHCR package behaved as PRIVATE at incident time (new org packages default private; anonymous pulls denied), while every authenticated CI path — retag, seed, release check — stayed green. install.sh then collapsed the auth failure into 'no published statbus-sb image'. Anonymous access was repaired out-of-band during the RCA (HTTP 200 now); the durable fix is verification, below.
2. The upgrade smoke restarts a HEAD service without staging the real target runtime: the unit timed out mid PostgreSQL BuildKit build before READY — an immutable harness defect inside the rc.03 tag, independent of the image incident.

Fix (one landing):
1. Add sb to dockerServices (cli/internal/release/check.go): release check + stable preflight verify SIX manifests and fail when statbus-sb:<commit_short> is absent or non-public.
2. Public-deployability probes use an ANONYMOUS GHCR token even when GITHUB_TOKEN is set — unit test: credential-readable but anonymously-denied package FAILS.
3. Add images.sb to release-manifest.json — the artifact contract names the commit image.
4. images.yaml: after full-manifest creation AND exempt retag, verify the destination ANONYMOUSLY and compare source/destination index digests; seed depends on this postcondition; a private package fails loudly naming the package-settings remedy.
5. install.sh preserves and prints the docker-pull failure class (auth vs missing vs network) instead of one collapsed message.
6. Fix 0-happy-upgrade staging: prepare the exact target DB/runtime images and unit/config state BEFORE restarting the HEAD service, via the same primitive the real upgrade path uses; assert no Docker source build before READY and restart within the unit budget. (Overlaps STATBUS-339's fidelity work — coordinate, do not duplicate.)
7. Regression tests: six-image list, anonymous-vs-authenticated probe behavior, retag digest postcondition, upgrade-smoke staging.

Acceptance: on a clean uncredentialed VM, statbus-sb:<short> pulls anonymously; release check reports six images; a private sb package turns release check RED; both smokes green on the next RC.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-02 15:07
---
foreman (2026-09-02 afternoon): TRANSIENT-VS-DEFECT DISCIPLINE added to scope, from the King's 'handle transients sensibly to not be confused' + mizaru's research: all three of today's GitHub failures match documented intermittent platform classes (git anonymous-fetch auth-challenge — actions/checkout#2351, <1% sporadic, rerun succeeds; ghcr.io anonymous-pull denial — same-day independent reports of ghcr-only TLS/token failures from ~13:07Z; no declared GitHub Status incident in any window; NOBODY changed package visibility). Additional item: the harness's own external touchpoints (SSH to VMs — attempt 2 died on rc=255 mid-log-tail; docker/ghcr pulls; git fetches) get bounded retry WITH error-class reporting, so a platform blip costs a retry line in the log, not a red run and an investigation. The rerun path stays the backstop (gh run rerun --failed re-executes only failed jobs — proven today: install smoke went green on attempt 2 with zero rebuilds).
---

created: 2026-09-02 15:29
---
foreman (2026-09-02, King's design note): the rc=255 class has a precise fix because the harness ALREADY runs stages in detached tmux on the VM — the work survives connection loss; what died was the CONTROLLER's SSH log-tail loop (vm-bootstrap.sh:305 cur_lines read), which treated its own connection drop as scenario failure. Fix: the watch loop treats SSH exit 255 as reconnect-and-resume (the tmux session + /tmp/<session>.log are still on the VM to re-attach to), bounded reconnect attempts, and only a VM that is genuinely gone or a stage that genuinely failed reds the run. This is the transient-discipline item made concrete for the SSH touchpoint.
---

author: foreman
created: 2026-09-02 19:04
---
Landed in a18684a33. Venue-2 autopsy answer: the component that allowed rc.03's 57 silent minutes was _run_long_via_tmux's controller-side synchronous unbounded ssh command substitution (no per-probe timeout, no no-progress deadline; a live TCP connection with a wedged remote read answers keepalives forever). Now: every controller read bounded, rc=255/124 reconnect to same log offset (5 attempts / 30s, provider-state consulted before vm-gone), 5-min zero-progress dumps tmux pane + log tail + journalctl + docker ps BEFORE teardown, distinct failure classes (stalled-stage/overall-timeout/vm-gone/controller-probe-failed). Venue-1: release-baseline.sh selects newest stable below target from tag ledger (RC fallback), verified picking v2026.08.1 for rc.04; INSTALL_VERSION pin wins. Deployability items 1-5 done (six-manifest gate, anonymous-token probes with regression test, images.sb in manifest, verify-public-image.sh postcondition gating seed, install.sh failure classes). Item 6 (real-target staging) deferred to STATBUS-339 overlap. All tests green locally: go test, golangci-lint, actionlint, 3 new bash test suites.
---

author: foreman
created: 2026-09-03 08:42
---
In Progress (2026-09-03): rc.12's chain is this ticket's live proof-run — both smokes green, dev auto-canary completed, Norway human install completed 08:29:34Z. Remaining before stable: fleet's 4 storm-blocked scenarios (the all-night GitHub 401 storm outlived even the widened retry windows) + the arc suite at the rc.12 commit. Deployability items 1-5 landed a18684a33 and PROVEN: the six-image anonymous gate ran on every rc since .04 and release check shows all six at 2309f6e1. Item 6 remains deferred to 339.
---
<!-- COMMENTS:END -->
