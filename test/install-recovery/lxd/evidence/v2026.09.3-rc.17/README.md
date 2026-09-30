# Upgrade-arc parity, LXD vs Hetzner, candidate v2026.09.3-rc.17 (STATBUS-425 M3b)

Hetzner reference: run 36509925405 (42 jobs listed, 41 executed, 35 arcs,
all executed jobs green; "Refuse zero-arc run" skipped). Its arc bytes are
at ebe058af. `rollback-pair-terminal` and `restore-broke-reattempt` were also
rerun on Hetzner on 2026-09-29 as run 36578946172 (both green).

LXD: `test/install-recovery/lxd/run-arcs.sh v2026.09.3-rc.17`, box
65.108.241.95, LXD_PARALLEL=6. The full run took 1h12m49s. The retests
used the `--arc` filter.

## Files

- `final-comparison.tsv`: one row per arc (35 rows), with the Hetzner
  verdict, the final LXD verdict, the LXD run that produced it, and the
  cause of any difference.
- `lxd-arcs-*.comparison.tsv`: the raw driver TSV of each LXD run, as
  written.
  - `114842` is the full 35-arc run.
  - `131413`, `133700`, `144023` and `150305` are retests.
- `verdict-lines.tsv`: each arc log's own PASS/FAIL/✗ lines per run.
- `../v2026.09.3-rc.16/`: c-rollback-resurrection on rc.16 with the final
  R1 code.

## Result: 33/35 matching verdicts, not yet identical-byte parity

`match=yes` in the final TSV means the observed verdicts agree. It does
not establish that both backends ran identical arc bytes. Three rows
compare LXD final bytes with Hetzner pre-change bytes:
`c-rollback-resurrection`, `worker-wedge-mid-derive`, and `working`.
Their TSV cause fields mark this distinction explicitly. The LXD fixes
were exercised live, but these reference runs do not prove same-byte
parity for the changed arcs.

Differences in the full run and how each was resolved:

| arc | full-run red | root cause | resolution |
|---|---|---|---|
| c-rollback-resurrection | FAIL | The run used arc code from before the R1 hang fixes (069527732, fa7c17dbb). | Final code: rc.17 PASS (131413, `.Created` 13:27:53 is before `rolled_back_at`). rc.16 RED (rc.16-135759, `.Created` 14:09:18 is 31 s after `rolled_back_at` 14:08:47). |
| postswap-health-park | FAIL | Infra: Docker Hub timeout pulling `postgrest/postgrest:v14.14`. | PASS on retest (131413). |
| working | FAIL_NO_PASS_LINE | The arc printed `PASS (PARTIAL):`, not `PASS:`. | Fixed in 83b3b3b84. PASS (150305). |
| worker-wedge-mid-derive | FAIL, 2/2 | Class (c), timing. See below. | Fixed in 7edb2f275. PASS (133700). |
| rollback-pair-terminal, restore-broke-reattempt | FAIL, 4/4 runs | Class (b): LXD exposes a real product behaviour. See below. | Not changed. Reported. |

### worker-wedge-mid-derive (class c)

The arc stops the worker with `docker compose stop -t 0` while the
worker's derive statement waits on a held lock. It then releases the lock.

The worker's Postgres backend stays alive until its next
`client_connection_check_interval` tick (5 s). If the lock is released
before that tick, the waiting statement gets the lock and commits the task.

On LXD, SSH round trips are fast:
- SIGKILL at 13:23:19.47;
- the lock was released about 2 s later;
- backend 1933's `process_tasks` finished at 13:23:21.36 (3015 ms);
- result: 0 abandoned rows.

On Hetzner, about 3.5 s passed between the stop and the release, so the
tick landed first.

The fix: the arc now keeps the lock until `abandoned_processing_count() >= 1`
(Postgres has observed the dead client), and only then releases it.

### rollback-pair-terminal and restore-broke-reattempt (class b)

After the 4th `./sb install`, B's `failed` terminal row becomes `superseded`
on LXD. It stays `failed` on Hetzner.

Ledger dump from LXD run 144023 (commit c128ea335), after the 4th dispatch:

```
HEAD ebe058af, tags: v2026.09.3 v2026.09.3-rc.17
id 1 ebe058af completed  release commit_tags {v2026.09.3}
id 2 29986056 superseded commit  superseded_at 14:49:52
```

The mechanism:

1. The candidate commit ebe058af was promoted to stable (`v2026.09.3`,
   created 2026-09-29 07:14 UTC).
2. On LXD, the daemon's `git fetch --tags --prune-tags` succeeds.
   `discover()` then tags A's row `v2026.09.3` and raises it to
   `release_status='release'` (the enrich UPDATE for ebe058af is the only
   one that is absent from the "matched 0 rows" list). The pruner then drops
   A's pseudo-tag `ebe058af`.
3. The PreSwap rollback leaves HEAD at A. The 4th install's
   `runInstallSupersede(A)` calls `upgrade_supersede_older`. That supersedes
   every `failed` row of lower `release_status`, which includes B, a
   `commit` row.
4. Hetzner logs record the following failed tag fetch 21 times across
   eight jobs of 36509925405:
   ```
   git fetch --tags: could not reach the StatBus repository on github.com
   fatal: could not read Username for 'https://github.com': terminal prompts disabled
   ```
   The logs of the two disputed arcs contain no daemon journal or discovery
   output, including rerun 36578946172 and its artifacts. Failed discovery
   and an unchanged `commit` classification for A in those two arcs are
   therefore an inference, not a directly captured observation.
   `cross-version-rename-handoff` did record successful discovery
   (275 tags), so the evidence does not support "every Hetzner VM failed".
   The daemon's accompanying diagnosis says this is not an authentication
   problem and identifies anonymous GitHub rate limiting from a shared
   outbound IP as a common cause. The raw Git error alone does not prove
   that diagnosis for these two arcs.

### Chronology and classification, not different kinds of Git objects

Both A and B are Git commits. A=ebe058af was committed at 00:30:59 UTC on
29 September and has both rc.17 and stable v2026.09.3 tags. Stable promotion
was around 07:14 UTC. The test created B=29986056 at 14:40:27 UTC, after
promotion; B has no RC or stable tag. The ledger records B superseded at
14:49:52 UTC. Promotion did not occur between B's creation and failure.

The database classifications `commit`, `prerelease`, and `release` describe
recognized release metadata, not mutually exclusive Git object types.
The current procedure ranks classification before version/date and
includes `failed` rows. Consequently the already-installed stable A can
supersede newer untagged B even though no newer code was installed.
The row is retained with a changed state; it is not deleted.

This is directly observed product behaviour, not yet a ruling that the
behaviour is a product defect. STATBUS-435 records the open contract
question. A normal unpromoted-candidate run is expected from the code to
avoid the same enrichment on the stable channel, but that is an inference
until exercised, not a substitute for controlling discovery in the arcs.
Both backends need a controlled or asserted discovery outcome so a network
failure cannot select the terminal-state expectation.

A correction to the first fix (8a57d5b5a): it was a real fidelity bug. LXD
installed the candidate through the historical-release path and recorded
`v2026.09.3`, where Hetzner records `ebe058af`. After the fix, both record
`ebe058af`. But that was not the whole cause: A is promoted to `release` by
discovery afterwards regardless.

## Historical-base fidelity gap

The candidate identity fix does not yet align historical bases. LXD logs
record `v2026.07.0-rc.05` and `v2026.09.0` through a release-install path;
Hetzner's two-argument path records per-commit identities `730b5001` and
`d53731ec`. Their metadata classifications differ even where verdicts
currently match. STATBUS-425 records alignment as M4/M5 work because the
supersede procedure ranks that metadata. No complete fidelity claim is
made by this comparison.

These qualifications address C2/C3 of the independent review
`tmp/review-425-m3b.md` (30 September follow-through). Raw per-run TSVs and
verdict lines remain unchanged.
