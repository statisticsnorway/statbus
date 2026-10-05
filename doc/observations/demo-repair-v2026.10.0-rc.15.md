# Demo repair card: v2026.10.0-rc.15 (STATBUS-436 AC#6, STATBUS-447 AC#5)

> **DRAFT, not ready to run** until the rc.15 operator-path rehearsal below shows PASS and the rc.15 gate chain is green. Agents fill in the receipts and remove this banner.

**Box:** demo (`statbus_demo@niue.statbus.org`, https://demo.statbus.org)
**Candidate:** v2026.10.0-rc.15 (commit `ebc77c5f5`)
**Run by:** the owner, personally (owner decision 2026-10-01). Agents prepared this card and the rehearsal; they do not run the live repair.

## Why demo needs this

Demo runs v2026.09.2's upgrade service. It falsely refuses v2026.09.3 because Docker lost demo's image labels: Compose shows the containers as `sha256:…` image IDs, and the old code reads that as "mixed versions" (STATBUS-436). Each attempt briefly sends visitors to the maintenance page.

The first repair attempt (owner, 2026-10-05, `./cloud.sh install demo` resolving to rc.14) was refused with "An upgrade is already running". The cause was STATBUS-447: `install.sh` released the upgrade lock just before starting `./sb install`, and the looping daemon took it in that gap. rc.15 removes the gap. `install.sh` keeps the lock and hands it directly to `./sb install`, which adopts it only after proving it is the same lock (inode, held flock, holder, token).

State observed read-only on 2026-10-05 18:28 UTC:
- checkout and on-disk binary are rc.14 (`7ccc9da0`), left by the refused attempt
- the resident daemon (PID 3288378, active since 2026-10-03 13:38, NRestarts 0) still runs the old binary: `/proc/<pid>/exe` shows `…/statbus/sb (deleted)`
- row 25829 (v2026.09.3) is `in_progress`, with 463 state-log rows in the last 5 minutes (about 1.5 attempts per second at that moment)
- `.env.config` still holds `SLACK_TOKEN` and `SEQ_API_KEY` (the installer moves them to `.env.credentials`)
- database at migration `20260923084454`; containers and data untouched
- nightly dumps are current: `dbdumps/demo_20261005_133844.pg_dump`

The old service cannot repair itself. The fixed code has to arrive through the installer.

## What was rehearsed first

The STATBUS-436 proof `CANDIDATE_PATH=operator` runs **exactly this command's path** on a guest that reproduces demo:
- real v2026.09.2 install
- image labels removed, so Compose shows `sha256:…`
- the old daemon observed looping on the same false refusal

It then runs the version-pinned installer with the loop still running, plus cloud.sh's post-steps. Since rc.15 the rehearsal has **no retry**: a single installer run must succeed (STATBUS-447 AC#3).

**Result:** TBD (rc.15 run started 2026-10-05 18:27 UTC). Receipts are filled in from `tmp/436-operator-rc15.log` in the run worktree.

## The command (from your laptop, in the statbus checkout)

```bash
./cloud.sh install demo v2026.10.0-rc.15
```

**Do not stop demo's upgrade service first.** cloud.sh deliberately never stops it: a stop sends SIGTERM, and an in-flight upgrade answers SIGTERM with a rollback. The installer holds the upgrade lock without a gap. The old service's own attempts during the install are refused safely.

## What you should see

1. `Checking release artifacts for v2026.10.0-rc.15 are ready...` → ready.
2. The installer runs its steps:
   - In **Settings**, expect `Moved SEQ_API_KEY, SLACK_TOKEN from .env.config to .env.credentials.` (or the same two names in the other order).
   - In **Migrations**, expect exactly two applied: `20260923202403` (statbus_382…) and `20261001163000` (statbus_435…).
3. `Installation complete!`, then `Superseded N older release(s)` (N ≥ 1). That line ends the loop: the stuck v2026.09.3 row is retired.
4. `Submitting final upgrade daemon restart: …`, then cloud.sh's `Regenerating config and restarting app...` and `--- demo install complete ---`.

*What I actually saw:*

## Checks afterwards (spread over at least 10 minutes, several scheduler ticks)

As `statbus_demo` on niue (`ssh statbus_demo@niue.statbus.org`):

```bash
cd statbus
./sb --version                                   # expect v2026.10.0-rc.15 (commit ebc77c5f)
git rev-parse --short HEAD                       # expect ebc77c5f5
systemctl --user show statbus-upgrade@statbus_demo -p ActiveState,MainPID,NRestarts
readlink -f /proc/$(systemctl --user show statbus-upgrade@statbus_demo -p MainPID --value)/exe   # expect …/statbus/sb, NOT "(deleted)"
echo "SELECT id, commit_version, state FROM public.upgrade WHERE commit_version IN ('v2026.09.3','v2026.10.0-rc.15') ORDER BY id;" | ./sb psql
#   expect v2026.09.3 → superseded, v2026.10.0-rc.15 → completed
echo "SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id=25829 AND logged_at > now()-interval '10 min';" | ./sb psql   # expect 0
journalctl --user -u statbus-upgrade@statbus_demo --since '-15 min' | grep -cE 'Could not record immutable source image|Executing upgrade to v2026.09.3'   # expect 0
ls ~/statbus-maintenance/active                  # expect "No such file or directory", checked several times
docker compose ps --format '{{.Service}} {{.Image}}'   # expect …:ebc77c5f for app/db/proxy/worker
```

**The site must be usable, not just answer.** In a browser, open https://demo.statbus.org, log in and click through a few pages over the window. A page must load and stay; being bounced to the maintenance page at any point is a failure. An HTTP 200 or a redirect from `curl` is not proof on its own.

*What I actually saw (with times):*

## If it does not go as described

- **Installer stops with "An upgrade is already running. Wait for it to finish, then retry if needed.":** with rc.15 this should no longer happen against the looping daemon. Do **not** simply retry. Record the full output and the time, and stop: it means the STATBUS-447 handoff did not hold.
- **Installer fails at Migrations or later:** record the full output. Demo's data is backed up nightly (`~/statbus/dbdumps/demo_*.pg_dump`, latest 2026-10-05 13:38). Do not hand-edit the database. File it as a deviation.
- **The loop continues after a "complete" install** (journal still shows the refusal, or state-log rows for 25829 keep appearing): that contradicts the rehearsal. Record it and stop.
- **The v2026.10.0-rc.15 row shows `superseded` instead of `completed`:** record it. It does not by itself mean the repair failed (STATBUS-442).

Any deviation is a ticket, not your mistake.
