---
id: d1xtta
title: "mz.statbus.org: Mozambique gets its StatBus installation"
state: "done"
type: chore
priority: "highest"
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzv"
created: 2026-11-23
updated: 2026-11-23
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
done_at: "2026-11-23T13:38"
---

## Goal
Mozambique's statistical office has a StatBus at https://mz.statbus.org, installed by the standard path on the stable channel.

## Purpose
Mozambique's statistical office has been trying StatBus on demo.statbus.org and needs its own installation, so its data and users stand apart from the shared demo.

## Principle
Installed exactly as every country is (./sb install, country code mz), following the Ghana installation (8fjct2); no hand steps outside the documented path.

## Details
Existing evidence: demo.statbus.org is set up for Mozambique (settings country MZ, external idents nuit and nuel) with their data and 25 users (notes 2026-11-23); dev.statbus.org holds Mozambique test imports (jobs 5 and 6, NUIT column). Host options: a niue cloud slot like mw (5x8w0h, the most recent cloud install: cloud.sh FLEET_REGISTRY entry, doc/CLOUD.md slot table, offset, DNS) or a standalone server like no (rune). Data options: start from demo's Mozambique data (dump of demo restored on mz, keeps users and units) or a fresh install with their import files run again.

## Depends on

## Acceptance
- [x] [Owner] Decides the host: a niue cloud slot (adds mz to cloud.sh FLEET_REGISTRY and doc/CLOUD.md with the next free offset, as mw was) or a standalone server (its own machine and DNS, as no on rune); recorded here
- [x] [Owner] Names the first admin user, the account the install creates; recorded off the board, with the date noted here
- [x] https://mz.statbus.org answers with a working login on the stable channel and runs the latest stable release, as ./cloud.sh status mz shows; the output is recorded here
- [x] [Owner] Decides whether mz starts from demo's Mozambique data (a dump of demo restored on mz: their 145 legal units, 10 establishments and 25 users carry over, demo is then reset) or from a fresh install (their import files run again on mz; users created anew); recorded here, and the data-load check follows it
- [ ] ~~The first agreed data load completes on mz with no failed job; the job ids and counts are recorded here~~ (not relevant: Owner 2026-11-23: the handover is complete; the first data load is the Mozambique team's work with Hedda, not this task's, rabbit, 2026-11-23)

## Notes

2026-11-23 owner: the Mozambique cloud installation takes priority now. They are using demo.statbus.org today; their data there is checked before the install.

2026-11-23 (Rabbit) Their data on demo.statbus.org (read-only, tmp/slack-todos/demo-mz.log): demo is set up for Mozambique (settings country MZ; external idents nuit and nuel), runs v2026.11.6. Data: 145 legal units, 10 establishments, 145 enterprises, from 7 import jobs on 2026-10-30 by Mozambique users (anajosemoz: LU job 82 finished 144 rows, establishment jobs 84 and 86 finished 9 and 1; jobs 81 and 83 rejected; jobs 87 hermingardo.nhaz and 88 jorgemate36 still waiting_for_upload). Last unit edit 2026-11-11, none today so far. 25 users; in use today: jorgemate36 session last used 2026-11-23 09:41 UTC; geraldo.timbe2013 2026-11-22; intimanea 2026-11-18. Moving this data to mz.statbus.org (dump/restore of demo, or re-running their import files) is a decision for the install.


2026-11-23 (Rabbit) mz.statbus.org is live. Cloud slot on niue, offset 13 (a1ace09b5, ee80f851b: cloud.sh registry, doc/CLOUD.md slot and port table, registry test). DNS: CNAME to niue.statbus.org. Created with ./cloud.sh create mz Mozambique v2026.11.6 (FLEET_TRUST_KEY_USER=jhf). Two faults in the create script found and fixed on the way: a comment's backticks ran on the operator's machine and broke the settings step (49962bf99, new test/create-installation-heredoc-test.sh in the harness workflow), and Seq/Slack keys written before install made install skip generating .env (f739ecc87, keys now set after install via sb dotenv set). Verified: https://mz.statbus.org has a valid certificate and the 'Mozambique Statbus' login; ./cloud.sh status mz shows v2026.11.6 (fc8a1d77) channel stable; containers app, worker, proxy, rest, db up (db healthy); upgrader service active; .env.credentials mode 600. Admin users: the owner's first admin plus Jørgen, Erik and Hedda, from .users.yml; a Playwright login as the first admin reached /getting-started. The first admin's demo password hash was copied by the owner's decision; Hedda updates .users.yml and tests her login. Fresh start: the Mozambique team sets it up through Getting started and Admin with Hedda.
check 1: Owner 2026-11-23: niue cloud slot, offset 13 (a1ace09b5)
check 2: Owner named the first admin 2026-11-23 (kept off the board); created from .users.yml
check 3: https://mz.statbus.org: valid certificate, login page 'Mozambique Statbus', Playwright login reached /getting-started; ./cloud.sh status mz: v2026.11.6 (fc8a1d77) stable
check 4: Owner 2026-11-23: fresh install; the team sets it up with Hedda; no data copied from demo
landed a1ace09 on master 2026-11-23: cloud: Mozambique gets the mz slot on niue (offset 13); the port table lists gh…
landed ee80f85 on master 2026-11-23: doc: CLOUD.md says offset 4 is unused, not next; the create script takes the…
landed 49962bf on master 2026-11-23: ops: slot creation's settings step runs on the box again; a comment's backticks…
landed f739ecc on master 2026-11-23: ops: slot creation sets the fleet's Seq and Slack keys after install, through sb…
2026-11-23 (Rabbit) CI on master 0e7de4599 (contains a1ace09b5, ee80f851b, 49962bf99, f739ecc87): Go Test, Harness Selftest (includes the new create-installation-heredoc-test), app build & lint, Images and Fast Tests all succeeded. f739ecc87 alone had failed Go Test because TestInstallationProvisionerWritesSecretsToCredentials_STATBUS361 still looked for the removed set_credential helper; 0e7de4599 updates that test.
## History
- 2026-11-23T12:52 todo -> doing/active (take)
- 2026-11-23T13:38 doing/active -> done (done); was doing_since: 2026-11-23T12:52
