---
id: STATBUS-161
title: >-
  init-incomplete-sentinel: a refused or killed init-db must not leave a
  healthy-restartable cluster — sentinel-gated wipe and re-init
status: Done
assignee:
  - engineer
created_date: '2026-07-12 03:35'
updated_date: '2026-07-12 04:24'
labels:
  - install
  - fail-fast
  - product
dependencies: []
references:
  - postgres/init-db.sh
  - STATBUS-151
priority: medium
ordinal: 162000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a database init that never completed cannot masquerade as a healthy cluster — every boot repeats the original loud failure until the cause is fixed, then first-boot-after succeeds automatically.
> STAGE: install robustness (NSO first-install path). FOUND: 2026-07-12, the STATBUS-151 investigation — the named 23:50 mechanism was exactly this chain: the [1/8] validation refuse aborted init-db before any role existed, the restart reported Healthy via "Skipping initialization", and the operator-facing symptom became a baffling pg_restore role error instead of the original actionable refuse.
> COMPLEXITY: engineer-small; the shape is architect-ruled (below).

THE GAP: postgres-image semantics — init-db runs only on an empty PGDATA; ANY abort (validation refuse, crash, OOM) leaves a partial PGDATA that the next container start treats as an existing cluster ("Skipping initialization") and reports HEALTHY. The one loud refuse scrolls away in docker logs; everything downstream fails weirdly (missing roles, missing schema). On an NSO box with a bad config at first install, the operator never sees the actionable message again.

RULED SHAPE (architect, 2026-07-12, from the 151 adjudication): an INIT-INCOMPLETE SENTINEL, not just cleanup. init-db writes .statbus-init-incomplete into PGDATA as its FIRST act on a fresh init and removes it as its LAST. The entrypoint's skip-initialization check treats a present sentinel as "previous init never completed" → wipe the partial cluster and re-run init from scratch — re-hitting the same refuse LOUDLY on every boot until the config is fixed, then succeeding automatically on the first boot after (init doing its job on an empty volume — not a standing self-heal). Two properties make this the right shape: (i) it covers the BROADER class for free — an init killed mid-way (crash, OOM) also leaves the sentinel and re-inits, closing every partial-init variant, not only the validation refuse; (ii) the destructive wipe is safety-gated BY CONSTRUCTION — the sentinel exists only in clusters this machinery created and never finished, so a pre-existing healthy PGDATA can never be wiped.

Origin: STATBUS-151 final adjudication; the 23:50 run (28983725043) is the live instance.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 init-db writes the sentinel first and removes it last; the entrypoint wipes and re-inits when the sentinel is present, repeating the original failure loudly every boot
- [x] #2 A deliberately-refused first init (bad config) shows the SAME actionable refuse on every subsequent boot, and succeeds automatically on the first boot after the config is fixed
- [x] #3 A pre-existing healthy PGDATA (no sentinel) is provably never wiped — the gate is the sentinel's presence, nothing else
- [x] #4 An init killed mid-way (not just refused) also re-inits via the same sentinel path
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED 980a3169e (2026-07-12), postgres/init-db.sh + postgres/start-postgres.sh, +56, architect SHIP as-built. The adjudicated sentinel shape fully realized on the confirmed wrapper geometry: init-db writes .statbus-init-incomplete as its genuine FIRST act (before the [1/8] validation — a refuse leaves it) and removes it as its LAST; our compose-entrypoint wrapper (start-postgres.sh, before the exec) wipes the partial cluster IFF sentinel-present AND non-empty PGDATA — find -mindepth 1 -delete, which the review noted is exactly right (preserves the mount point where rm -rf of the dir would break the volume) — letting the official entrypoint re-init and re-hit the SAME loud refuse every boot until the config is fixed, succeeding automatically on the first boot after (init on an empty volume, not a standing self-heal). Safety by construction: the sentinel exists only in clusters this machinery created and never finished; a hand-planted one is deliberate intent. The kill-during-initdb boundary is NAMED at the site as outside this class (no sentinel, but loud startup failure — never silent-healthy). FOUR LIVE LEGS on the real statbus-db image, isolated statbus161-* containers + throwaway volumes, dev DBs untouched: (a) bad config → [1/8] refuse repeats on every boot, never READY — the exact 151 chain killed; (b) fixed config → wipe → [8/8] → READY, sentinel gone, admin_user present; (c) healthy volume never wiped (end-to-end + direct wipe-logic test incl. the empty-PGDATA guard); (d) SIGKILL at [3/8] → wipe → clean re-init → READY (the broader partial-init class the sentinel was chosen to cover, proven not claimed). With this, the STATBUS-151 adjudication's product half is complete: on an NSO first install with a bad config, the operator sees the same actionable refuse on every boot until it is fixed — and nothing else.
<!-- SECTION:FINAL_SUMMARY:END -->
