# Demo repair card — v2026.10.0-rc.12 (STATBUS-436 AC#6)

**Box:** demo (`statbus_demo@niue.statbus.org`, https://demo.statbus.org)
**Candidate:** v2026.10.0-rc.12 (commit `7ec86ac2b`)
**Run by:** the owner, personally (owner decision 2026-10-01). Agents prepared this card and the rehearsal; they do not run the live repair.

## Why demo needs this

Demo runs v2026.09.2. Its upgrade service falsely refuses v2026.09.3 because Docker lost demo's image labels: Compose shows the containers as `sha256:…` image IDs, and the old code reads that as "mixed versions". While the loop is active it retries about every 2 seconds (~1,800 attempts per hour), and each attempt briefly sends visitors to the maintenance page.

State observed read-only on 2026-10-02 15:22 UTC:
- checkout and binary `fe4a769a` (v2026.09.2); daemon PID 1457701, NRestarts 0
- row 25829 (v2026.09.3) `failed`, with the false "mixed tags" error
- the loop ran 02:24–11:49 UTC, then went quiet; it restarts on later triggers
- containers untouched for 8 days; data intact

The old service cannot repair itself. The fixed code has to arrive through the installer.

## What was rehearsed first

The STATBUS-436 proof `CANDIDATE_PATH=operator` ran **exactly this command's path** on a guest that reproduces demo:
- real v2026.09.2 install
- image labels removed, so Compose shows `sha256:…`
- the old daemon observed looping on the same false refusal

It then ran the version-pinned installer with the loop still running, plus cloud.sh's post-steps.

**Result: PASS** (2026-10-02 16:37–16:57 UTC, Hetzner guest, rc.12 commit 7ec86ac2):
- the old v2026.09.2 daemon logged 3 exact false refusals ("mixed tags", digest-shaped) in one process, with NRestarts unchanged
- the installer completed 18/18 with the loop still running. The old daemon's one attempt during the install was refused with "another ./sb install is already running", and that row was then superseded.
- final state:
  - checkout `7ec86ac2`, on-disk binary `v2026.10.0-rc.12`
  - the resident daemon executable is `~/statbus/sb`
  - db/app/worker/proxy run `:7ec86ac2`
  - data counts unchanged (126 statistical units, 23 legal units, 50 establishments, 1430 history rows)
  - health 200 at each of 4 checks spaced 65 s apart, with no daemon restarts
  - the v2026.09.3 row is `superseded`, with zero refusals and zero re-attempts after the install

One difference from demo: on the guest the rc.12 ledger row itself ended `superseded`, not `completed`. Likely cause (inferred from source; the guest was deleted before its ledger history could be read): the guest follows the prerelease channel, so the old daemon had already discovered rc.12. When v2026.09.3 was scheduled, the 09.2-era tier rule (lower tier = older, since removed by STATBUS-435) retired that row, and the installer never rewrites a terminal row. Demo follows `stable` and had **no** rc.12 row (checked 2026-10-02 17:00 UTC), so on demo the install should write a fresh `completed` row. If it shows `superseded` instead, record that, but it does not mean the repair failed. Tracked as STATBUS-442. Log: `tmp/436-operator-rc12.PASS.log` in the run worktree.

## The command (from your laptop, in the statbus checkout)

```bash
./cloud.sh install demo v2026.10.0-rc.12
```

**Do not stop demo's upgrade service first.** cloud.sh deliberately never stops it: a stop sends SIGTERM, and an in-flight upgrade answers SIGTERM with a rollback. The installer holds the upgrade lock, and the old service's own attempts during the install are refused safely ("another ./sb install is already running").

## What you should see

1. `Checking release artifacts for v2026.10.0-rc.12 are ready...` → ready.
2. The installer runs its 18 steps. In **Settings**, expect "Moved SLACK_TOKEN … from .env.config to .env.credentials". In **Migrations**, expect exactly two applied: `20260923202403` (statbus_382…) and `20261001163000` (statbus_435…).
3. `Installation complete!`, then `Superseded N older release(s)` (N ≥ 1). That line is the one that ends the loop: the stuck v2026.09.3 row is retired.
4. `Submitting final upgrade daemon restart`, then cloud.sh's `Regenerating config and restarting app...` and `--- demo install complete ---`.

*What I actually saw:*

## Checks afterwards (spread over at least 10 minutes, several scheduler ticks)

As `statbus_demo` on niue (`ssh statbus_demo@niue.statbus.org`):

```bash
cd statbus
./sb --version                                   # expect v2026.10.0-rc.12 (commit 7ec86ac2)
git rev-parse --short HEAD                       # expect 7ec86ac2
systemctl --user show statbus-upgrade@statbus_demo -p ActiveState,MainPID,NRestarts
readlink -f /proc/$(systemctl --user show statbus-upgrade@statbus_demo -p MainPID --value)/exe   # expect …/statbus/sb
echo "SELECT id, commit_version, state FROM public.upgrade WHERE commit_version IN ('v2026.09.3','v2026.10.0-rc.12') ORDER BY id;" | ./sb psql
#   expect v2026.09.3 → superseded, v2026.10.0-rc.12 → completed
journalctl --user -u statbus-upgrade@statbus_demo --since '-15 min' | grep -cE 'Could not record immutable source image|Executing upgrade to v2026.09.3'   # expect 0
docker compose ps --format '{{.Service}} {{.Image}}'   # expect …:7ec86ac2 for app/db/proxy/worker
```

From anywhere: `curl -sI https://demo.statbus.org/ | head -1` gives a 200 or a redirect to /login, never the maintenance page. Check it several times over the window. A single 200 is not proof.

*What I actually saw (with times):*

## If it does not go as described

- **Installer stops with "An upgrade is already running":** the old loop held the lock at that instant. Wait 30 seconds and run the same command again. The rehearsal retries the same way.
- **Installer fails at Migrations or later:** record the full output. Demo's data is backed up nightly (`~/statbus/dbdumps/demo_*.pg_dump`, latest 2026-10-02 13:06). Do not hand-edit the database. File it as a deviation.
- **The loop continues after a "complete" install** (journal still shows the refusal): that contradicts the rehearsal. Record it and stop.

Any deviation is a ticket, not your mistake.
