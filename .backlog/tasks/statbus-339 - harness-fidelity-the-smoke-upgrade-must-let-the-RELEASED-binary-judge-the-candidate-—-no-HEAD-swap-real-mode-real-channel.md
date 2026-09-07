---
id: STATBUS-339
title: >-
  harness-fidelity: the smoke upgrade must let the RELEASED binary judge the
  candidate — no HEAD swap, real mode, real channel
status: To Do
assignee: []
created_date: '2026-09-02 11:20'
updated_date: '2026-09-07 10:04'
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
## Review correction (2026-09-06/07): standalone mode is out of scope here

Sol's review (`tmp/STATBUS-035-339-review/REPORT.md`) showed H2 as written
cannot run: standalone mode means ports 80/443 and an automatic public ACME
certificate, and a harness VM named `statbus-test.local` has neither public
DNS nor a way to obtain one, so the first health probe fails before the
upgrade runs. Norway did not fail on TLS or ports; it failed on who judged
whom. So `0-happy-upgrade` keeps development mode and takes only the
prerelease channel (the actual Norway hop). The shape axis code stays for a
future scenario that can supply a certificate. That certificate capability is
STATBUS-358; an HTTPS-only-egress scenario (the Albania network shape) is
STATBUS-357. H2 in this ticket is therefore satisfied by the channel half
only, deliberately.

## Why these two tickets are one piece of work

Both change what the install-recovery harness installs on a fresh VM before it
exercises an upgrade, and both are proven by the same thing: one full paid
harness run that is green at the new shape. Doing them separately would buy
that run twice. So: 035 is the rebaseline (what the VM starts from), 339 is
the honesty of the hop (who judges the upgrade). One implementer, one review,
one paid run, two tickets closed.

## Ground truth (2026-09-06)

- Current stable is `v2026.09.0`; newest candidate `v2026.09.0-rc.14`. There
  is no `v2026.05.*` or `v2026.07.*` box anywhere in the fleet.
- `0-happy-install` and `0-happy-upgrade` already pick their baseline
  dynamically via `select_release_baseline_from_repo` in
  `test/install-recovery/lib/release-baseline.sh` (newest release below the
  target). They are NOT the problem.
- Seven scenarios still hard-pin an extinct baseline as their default:
  `1-boot-advisory-too-early`, `1-boot-flag-stale-handoff`,
  `1-boot-startup-timeout`, `5-install-drifted-unit-reconciled` (v2026.05.4);
  `1-boot-concurrent-install`, `5-install-seed-on-populated` (v2026.05.2);
  `3-postswap-worker-ddl-deadlock` (v2026.07.0-rc.05).
- `test/install-recovery/lib/wedge-helpers.sh` (~line 528) synthesises the
  crash state that v2026.05.2's `executeUpgrade` left behind. That shape is
  extinct: no released binary produces it any more.
- `test/install-recovery/lib/vm-bootstrap.sh` (~line 1160) adds the
  `origin/db-seed` refspec so a pre-retirement release binary's git-branch
  seed can find it. Only binaries older than `v2026.05.6-rc.03` fetch it.
- `0-happy-upgrade` installs the dynamic baseline, then `upload_sb_to_vm`
  COPIES HEAD's `sb` over the installed binary (line ~149) and registers
  HEAD's SHA (line ~188), so HEAD judges HEAD. The Norway rc.02 incident was
  a released binary judging a new candidate, which this never exercises.
- Every harness VM today is `CADDY_DEPLOYMENT_MODE=development` with
  `UPGRADE_CHANNEL=stable` (vm-bootstrap.sh ~703, ~736). Rune is
  standalone + prerelease; no scenario has that shape.

## Work (339 half: who judges the hop)

### H1. The smoke upgrade installs the previous release and does not swap in HEAD

`0-happy-upgrade` (and the arc baseline pattern in `lib/arc-helpers.sh`
where it shares the mechanism): install the dynamic baseline via
`install.sh` exactly as an operator would; do NOT run `upload_sb_to_vm`
before scheduling; register and schedule the **tagged** target candidate
(the RC tag at HEAD when the run is a tag push; a raw SHA is refused for
this scenario with a message saying why), so the RELEASED binary's preswap
judges it. HEAD's code is exercised as the TARGET (its per-commit image and
binary already exist), never as the judge.

The comment block at lines ~149-156 that justifies the swap must be
replaced by one that states which binary judges and which is judged.

### H2. One scenario runs rune's shape

Add the shape axis to the harness bootstrap (`vm-bootstrap.sh`): a scenario
can request `CADDY_DEPLOYMENT_MODE=standalone` and
`UPGRADE_CHANNEL=prerelease`. Exactly ONE existing scenario (the happy
upgrade is the natural choice, since that is the hop Norway performs) runs
that shape by default. Do not multiply scenarios; the shape rides the
rebaseline.

### H3. The harness can inject a returned preswap fetch error

STATBUS-338 covers the regression test; this ticket only ensures the
harness has a switch (env var read by the scenario, honoured on the VM) to
make the target's preswap `git fetch` RETURN an error (not be killed), on
the real cross-version hop from H1. One scenario exercises it or a
documented `--print-selected`-visible variant does.

### H4. Keep one HEAD-judges-HEAD scenario, named for what it is

Exactly one scenario keeps the binary swap on purpose (it catches
target-side breakage before any candidate exists). Rename or re-comment it
so nobody mistakes it for the cross-version proof. Its header states:
"judge = HEAD, judged = HEAD, deliberately."

## Acceptance (339)

1. `0-happy-upgrade` proves {previous release binary} judging {tagged
   candidate} with no HEAD binary swap; the scenario header states judge and
   judged.
2. `0-happy-upgrade` runs the prerelease channel by default in development
   mode (the standalone half is out of scope here, see the review correction
   above; certificates are STATBUS-358).
3. The harness can inject a returned preswap fetch error on the real hop.
4. Exactly one HEAD-judges-HEAD scenario remains, named as such.
5. The full harness is green at the new shape on a real RC tag (the shared
   paid run with 035).

## Evidence (pre-paid-run, 2026-09-07, HEAD e5d392a22)

| acceptance | evidence |
|---|---|
| 1 judge/judged, no HEAD swap | Sol round 2 HIGH 1 ACCEPTED: `0-happy-upgrade` header states judge = released baseline binary, judged = tagged candidate; no `stage-head` swap on the hop |
| 2 prerelease by default | bootstrap renders `CADDY_DEPLOYMENT_MODE=development`, `UPGRADE_CHANNEL=prerelease`; the service's tag classifier maps `v*-rc.N` to prerelease so the candidate is on-channel (Sol round 2) |
| 3 returned preswap fetch error on the real hop | `arcs/preswap-fetch-returned-error-arc.sh` + `TestLivePreswapFetchReturnedErrorRealSite_STATBUS339`; Sol round 3 ACCEPT at e5d392a22 on all four oracles: exact `error` prose, `scheduled_at IS NULL`, `SHOW default_transaction_read_only`=off plus a real CREATE+INSERT write, byte-identical backup-root listing before/after (`ed2ac1fd7`) |
| 4 exactly one HEAD-judges-HEAD scenario | Sol: H4 single deliberate HEAD-labelled scenario intact |
| 5 full harness green on a real RC tag | PENDING: the shared paid run (owner approval required) |

Review trail: `tmp/STATBUS-035-339-review/REPORT.md` (Sol: initial REJECT, r2 REJECT on HIGH 2, r3 ACCEPT).

## Non-goals

Further fidelity ideas (real DNS, real TLS, real NSO data volumes) are
comments here, not scope. STATBUS-338's own regression test is not
re-implemented.

## Original description (verbatim)

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

created: 2026-09-02 11:28
---
King ratifies the fan design with N=3 (2026-09-02): the harness proves each of the THREE last releases jumps DIRECTLY to the new candidate — three independent single hops (e.g. v2026.08.0→candidate, v2026.08.1→candidate, and the next release back or forward as the ledger moves). Three by the one-two-three rule: enough sources to catch a source-version-specific judge defect, small enough to stay cheap; each red names its source version. Combined with comment #1's algorithmic selection, the three are computed from the tag ledger at run time, never pinned.
---
<!-- COMMENTS:END -->
