---
id: STATBUS-211
title: >-
  crollback-fixed-seed-build: the fixed-fixture branch's seed image build dies
  on the deliberately-failing migration it was supposed to fix
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-16 22:30'
updated_date: '2026-08-16 22:45'
labels:
  - install-recovery
  - release
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
  - test/install-recovery/arcs/c-rollback-resurrection-arc.sh
  - .github/workflows/images.yaml
priority: low
ordinal: 211000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every fixture branch the arc construct step creates yields a buildable seed image; the "fixed" branch of the c-rollback lineage migrates clean by definition (it IS the fix release).
> FOUND: overnight arc triage 2026-08-17, rc.01 fleet. Images run 31970569830 (workflow_dispatch on test/upgrade-arc-crollback-fixed-migration-31970534502) FAILED in the seed-builder stage: `migrate seed db up: migration 20260714100530 (20260714100530_upgrade_arc_3.up.sql) failed: exit status 3 — ERROR: upgrade-arc failing fixture: deliberate migration failure (STATBUS-071 d)`. The sibling fixture branches (crollback-migration, codeonly, healthpark, healthpark-fixed) all built green in the same window.

THE CONTRADICTION: the crollback-FIXED branch is the fix release for the C-class rollback lineage — its defining property is that the deliberately-failing migration is repaired/replaced. Its seed build dying on exactly that deliberate failure means either (a) the construct step failed to actually fix/replace upgrade_arc_3 on that branch (construct defect), or (b) the crollback-fixed lineage intentionally keeps the failing migration at some position and the seed builder should not run (or should skip) for this fixture class (seed-build/fixture interaction defect). Determine which from the construct step's code (upgrade-arc-harness.yaml construct job + its fixture scripts) and the branch's actual bytes (the test/* branches are torn down post-run — reconstruct via the construct code, or from the next run's branches).

CONSUMER IMPACT: c-rollback-resurrection consumes CROLLBACK_C — this run it died on capacity (208) before pulling the image, so the missing image was masked. At rc.02, with capacity fixed, c-rollback-resurrection (and any other CROLLBACK_C consumer, e.g. arcs whose lineage displaces C) will hit this deterministically unless fixed first. Cross-check: was this image build green at the last full-suite arc success (2026-07-28 run 30372633117)? If yes, find what changed since (seed-builder behavior, construct, or migration numbering).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cause established from construct code + branch bytes: construct defect vs seed-build/fixture-class interaction, with the July-28 green cross-check answered
- [ ] #2 Fix architect-ruled and landed: the crollback-fixed branch's seed image builds green (or the seed build correctly skips the fixture class, ruled deliberately)
- [ ] #3 c-rollback-resurrection green at an RC tag
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-16 22:42
---
TRACE pt.1/2 — AC#1 cause, established from construct code + branch bytes.

CAUSE: seed-build/fixture-class interaction defect (ticket's option b), NOT a construct defect. Read test/install-recovery/lib/upgrade-target.sh's own doc comments (lines 88-95, construct_upgrade_target's crollback spec): "C: B + a NEW FAILING V3 (RAISES EXCEPTION). C displaces the parked B at claim... then V3 RAISEs → the daemon rolls C back onto B → C terminal 'rolled_back'" — crollback's C branch carrying a PERMANENTLY, INTENTIONALLY failing migration is the ENTIRE POINT of the lineage ("C-rollback" = C rolls back). construct built EXACTLY what it's supposed to. There is no construct bug to fix.

JULY-28 CROSS-CHECK — PREMISE CORRECTED: run 30372633117 is NOT the full-suite arc success it was cited as. Verified via `gh run view 30372633117 --json jobs`: only 6 jobs total, ONE arc scenario ("postswap-converged-selfheal"); its own Discover job log literally says "Discovered 1 arc(s) for the matrix". c-rollback-resurrection never ran in this run — its "success" conclusion says nothing about the image issue. The TRUE full-suite runs (verified by job count, ~36-37 jobs matching the 31-arc matrix + overhead) are 31970534502 (today, 37 jobs) and 30755799405 (2026-08-02, 36 jobs). Redid the cross-check against those:
- 2026-08-02 (30755799405): crollback-fixed's own Images run (30755828325) FAILED — SAME error signature (`migrate seed db up: migration 20260714100530 (20260714100530_upgrade_arc_3.up.sql) failed: exit status 3 — ERROR: upgrade-arc failing fixture: deliberate migration failure (STATBUS-071 d)`, byte-identical to today's 31970569830 and to July-28's own 30372710426). This is NOT a new regression — it has existed since at least July 28, likely since crollback was added.
- CRITICAL: despite the identical seed failure being present on 2026-08-02, c-rollback-resurrection's OWN job on that run PASSED (conclusion: success, verified via `gh run view 30755799405 --json jobs`). Today it failed, but I pulled its job log (95222617661) directly: the ONLY error is `hcloud: server limit reached (resource_limit_exceeded, ...)` at VM-CREATION time — pure STATBUS-208 capacity, matching the ticket's own "masked by capacity" framing exactly. It never reached the point of touching CROLLBACK_C's image at all, this run or any other.
---

author: mechanic
created: 2026-08-16 22:42
---
TRACE pt.2/2 — WHY the arc tolerates the broken seed, and where the actual defect lives.

Read c-rollback-resurrection-arc.sh + arc-helpers.sh's arc_prepare_box/arc_to in full. B and C are driven ENTIRELY through the REAL, LIVE upgrade daemon already running on the bootstrapped VM: `git fetch origin $branch && git cat-file -e $sha` then `./sb upgrade register $sha` / `./sb upgrade schedule $sha` (arc-helpers.sh:133,136,143) — the daemon applies migration .sql files straight from the git tree against the live Postgres. NEITHER B NOR C ever pulls a Docker image. Only A (the base) uses install_statbus_at_sha, which pulls the SB BINARY image (ghcr.io/.../statbus-sb:<short>) — not "seed". The "seed" artifact (images.yaml, a SEPARATE job, `needs: [describe, manifest]`, unconditional for every branch — a pre-migrated DB snapshot for FAST-STARTUP scenarios elsewhere) is never consumed by any arc's B/C leg at all.

Confirmed structurally too: upgrade-arc-harness.yaml's image-wait step (the ONLY gate before any arc runs) polls `services="app worker db proxy sb"` (line ~361) — never "seed". And the actual Images run's own job list for crollback-fixed (31970569830) shows ALL FIVE of those services (both amd64+arm64, plus every manifest) succeeded — ONLY the independent "seed" job failed. image-wait therefore never notices or gates on this failure, for any lineage.

NOT CROLLBACK-SPECIFIC: checked the "failing" lineage's own B branch (test/upgrade-arc-failing-migration-31970534502, which ALSO carries a deliberately-RAISING migration by design per upgrade-target.sh's doc) — same exact signature: all 5 services + manifests green, only "seed" red (run 31970559640). failing's OWN "-fixed" C branch (which per the doc REPLACES the broken migration with the working one) builds a clean seed (run 31970560884, success). So this is a GENERAL pattern: ANY fixture branch whose HEAD commit carries a by-design-permanently-unappliable migration will always fail images.yaml's "seed" job, regardless of lineage — confirms the architect's stated principle exactly ("a fixture branch carrying a deliberately-broken migration must NEVER be required to produce a runnable seed").

WHERE THE DEFECT ACTUALLY LIVES: images.yaml's `seed:` job (line 137) — unconditional, no scoping to skip test/upgrade-arc-* fixture branches or branches known to carry a by-design-unappliable migration. This is OUTSIDE my file grant for 211 (upgrade-arc-harness.yaml + fixture-construct scripts) — flagging per the dispatch's own "if so, report first (engineer coordination needed)" caveat, same treatment as vm-bootstrap.sh would get. STOPPING HERE, not building, per the trace-first instruction.

CORRECTED PRACTICAL IMPACT (materially different from the ticket's framing): this is NOT currently a functional blocker — no arc consumes the seed artifact for B/C, image-wait doesn't gate on it, and c-rollback-resurrection has ALREADY empirically passed (2026-08-02) with this exact same failure present. It IS a standing, permanently-red Images job for every by-design-broken-migration fixture branch (crollback-fixed, failing-migration, and presumably any future lineage with the same property) — real noise that costs triage attention (this ticket's own origin), but not the deterministic rc.02 blocker the overnight framing assumed. Fix-shape options for the architect, not built: (a) scope images.yaml's seed job to skip test/upgrade-arc-* branches entirely; (b) skip it specifically for branches/commits known to carry an intentionally-unappliable migration (needs a signal from construct); (c) leave it building but treat/document the red as expected+harmless for these branches (lowest-risk, no workflow behavior change). Oracles not yet run (no build to verify) — will apply bash -n/shellcheck/actionlint once a fix is ruled and scoped to files I can own.
---

author: architect
created: 2026-08-16 22:43
---
FIX-SHAPE RULING (architect, overnight): (a) — scope images.yaml's seed job to SKIP all test/upgrade-arc-* branches, with two conditions. First, the skip is LOUD, never silent: the job-level `if:` carries an in-place comment naming this ticket and the no-consumer evidence (the arcs drive B/C via git-fetch + the live daemon; image-wait polls the five per-commit images app/worker/db/proxy/sb and never seed — so ONLY the seed job is unconsumed on fixture branches; the other image jobs MUST keep running there, they are consumed). Second, the classifier is the branch-name prefix, total over the fixture class — (b) is rejected because 'known-broken-migration branches' is a drifting classification (the working lineage's seed is equally unconsumed; scoping by consumption, not by brokenness, is the stable rule). (c) is rejected outright: a permanently-red job everyone learns to ignore trains exactly the blindness the strict-gating doctrine forbids.

RATIFIED from the trace: priority HIGH → LOW (noise, not a blocker — the 2026-08-02 evidence that c-rollback-resurrection passed WITH the identical seed failure present is decisive); rc.02 does NOT wait on this — c-rollback's criterion closes at rc.02 via the 208 fix alone. Builder: mechanic, images.yaml added to his grant, one job condition.

PREMISE CORRECTIONS ACCEPTED, both: the foreman's deterministic-blocker claim and MY OWN guidance's citation of the July-28 run as a full-suite green (it was a one-arc subset — the mechanic's job-count verification is precisely the jobs-not-labels discipline 199 just codified, applied by hand before the gate exists to do it). Verify-premises-at-writing-time hit both of us; the stop-and-report was right.
---

author: mechanic
created: 2026-08-16 22:45
---
BUILT per comment #3's ruling (option a) — images.yaml is now in my grant, used it.

FILE:LINE: .github/workflows/images.yaml, the `seed:` job (~line 137). Added `if: ${{ !startsWith(github.ref_name, 'test/upgrade-arc-') }}` right before `needs: [describe, manifest]`, plus an in-place comment block naming STATBUS-211, the by-design-unappliable-migration reasoning, and the no-consumer evidence from the trace (comments #1-2) — loud, not silent: the job still appears in every run, shown as skipped, never vanishes from the job list.

WHY `github.ref_name` and not `github.ref`: verified directly against the ACTUAL captured webhook payload from the failing run (31970569830, already in my trace) — `"github_ref_name": "test/upgrade-arc-crollback-fixed-migration-31970534502"` (no refs/heads/ prefix) for a workflow_dispatch trigger. Confirmed this is the correct, uniform field for BOTH of images.yaml's triggers (`push: branches: [master]` and bare `workflow_dispatch`, checked its actual `on:` block) — GitHub resolves ref_name from whatever ref the run checked out in both cases, master pushes always resolve to "master" (never matching the test/upgrade-arc- prefix), fixture-branch dispatches always resolve to the exact branch name (starts with the prefix). Cross-checked the prefix is comprehensive against every fixture branch name in my trace (ceiling/codeonly/crollback/failing/healthpark/oom/working × migration/fixed-migration) — all 14 shapes start with `test/upgrade-arc-`, none missed.

SCOPE CHECK: confirmed nothing else in the workflow `needs:`s the seed job (grep, zero matches) — it's a leaf job, so skipping it has no cascade effect on any other job. Confirmed nothing outside images.yaml checks the OVERALL Images workflow conclusion for these branches (grep across upgrade-arc-harness.yaml, install-recovery-harness.yaml, and every harness lib script) — image-wait polls ghcr manifests directly (`app worker db proxy sb`), so the fix's actual effect is exactly what was wanted: these fixture-branch Images runs will now conclude green (seed shown skipped, not failed) instead of permanently red, with zero behavior change to anything that actually gates on them.

Oracles: actionlint clean except 2 PRE-EXISTING `config-inline` deprecation warnings (docker/setup-buildx-action), confirmed identical against the git-show-HEAD baseline (same 2 findings, just at shifted line numbers matching my +25-line insertion) — zero new findings from this change.

File list for this build: .github/workflows/images.yaml only. Frozen; report going to the foreman via SendMessage.
---
<!-- COMMENTS:END -->
