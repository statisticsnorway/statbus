---
id: STATBUS-339
title: >-
  harness-fidelity: the smoke upgrade must let the RELEASED binary judge the
  candidate — no HEAD swap, real mode, real channel
status: To Do
assignee: []
created_date: '2026-09-02 11:20'
updated_date: '2026-09-02 11:26'
labels:
  - test-harness
  - release
  - upgrade
dependencies: []
priority: high
type: enhancement
ordinal: 332000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Norway rc.02 incident proved the smoke test does not run what real boxes run (RCA 2026-09-02).

THE GAP, the King's own words: 0-happy-upgrade installs v2026.05.2 but then COPIES HEAD's sb binary in and restarts onto it before scheduling — so HEAD judges HEAD. It never exercises the released source binary judging the new release, which is exactly the hop every real box performs. And this is unnecessary: we have automated per-commit builds of every push, existing precisely so the real code path can be exercised.

Fix — make the harness install what a real box would run, at every seam:
1. 0-happy-upgrade (and the arc baseline pattern): install the actual PREVIOUS RELEASE (v2026.08.1 stable, or the newest release/candidate below the target) via install.sh exactly as an operator would; do NOT swap in HEAD's binary; register/schedule the TAGGED target candidate (not a raw SHA) so the released binary's preswap judges it — the Norway hop. HEAD's own code is exercised as the TARGET (its images/binary exist from the per-commit builds), not as the judge.
2. Add the missing shape axes: at least one scenario runs standalone mode + prerelease channel (rune's shape — today every harness VM is development/stable); the shape should ride the rebaseline (STATBUS-035) rather than multiply scenarios.
3. Add the missing failure axis: a RETURNED (not kill) fetch/transport error injected in preswap — covered concretely by STATBUS-338's regression test; this ticket ensures the harness can inject it on the real cross-version hop.
4. Keep one HEAD-judges-HEAD scenario deliberately (it catches target-side breakage before a candidate exists) — renamed/commented so nobody mistakes it for the cross-version proof.

Discussion open with the King: how much closer can the tests get to the real deal overall — this ticket carries the concrete first slice (real source binary, real mode/channel, real tagged target), further fidelity ideas land as comments here.

Acceptance: the smoke upgrade proves {previous release binary} → {tagged candidate} with no HEAD binary swap; one scenario runs standalone+prerelease; the harness can inject a returned preswap fetch error; scenario docs state which binary judges and which is judged; harness green at the new shape on a real rc tag.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-09-02 11:26
---
King's design refinements (2026-09-02 discussion, foreman-recorded):

1. ALGORITHMIC BASELINE, never hard-coded: the harness selects the upgrade-from version the way a real box would — the newest released tag below the target on the relevant channel (same question discovery answers; git tag --sort=-version:refname, released shape filter, first below target). Every promotion then moves the baseline automatically; the v2026.05.2 pin drift class ends.

2. FAN OF SINGLE HOPS, not a sequential chain: coverage for distant sources is one hop from EACH of the last N releases (e.g. 08.0→candidate, 08.1→candidate; N small, 2-3). Each hop independent — a red names its source version; no broken intermediate blocks the matrix. This is what real boxes do: a box that slept through releases jumps ONCE.

3. SEQUENTIAL WALK-THE-CHAIN ARC: CONSIDERED AND REJECTED (the King's own conclusion). Walking A→B→C→candidate assumes every intermediate hop is sound, but releases are often cut BECAUSE a hop was broken — the chain would re-litigate settled incidents on every run (e.g. the 08.1-rc.01→09.0-rc.02 transient is permanent history). No real box travels through intermediates; the upgrade contract is any-supported-release → target in one hop; migrations compose linearly regardless of which binary applies them. Do not re-propose.
---
<!-- COMMENTS:END -->
