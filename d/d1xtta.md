---
id: d1xtta
title: "mz.statbus.org: Mozambique gets its StatBus installation"
state: todo
type: chore
priority: "highest"
assignee: []
labels: []
group: ""
rank: "zzzzzzzv"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
Mozambique's statistical office has a StatBus at https://mz.statbus.org, installed by the standard path on the stable channel.

## Purpose
Owner 2026-11-22: set up mz.statbus.org for Mozambique. dev.statbus.org already holds Mozambique test imports (jobs 5 and 6 use a NUIT column, Mozambique's tax identifier).

## Principle
Installed exactly as every country is (./sb install, country code mz), following the Ghana installation (8fjct2); no hand steps outside the documented path.

## Details
Open for the owner: which host (niue cloud slot or a standalone server), who in Mozambique gets the first admin account, and which data files (NUIT identifiers, regions, activity standard) are loaded first. doc/CLOUD.md lists the cloud slots.

## Depends on

## Acceptance
- [ ] [Owner] Decides the host, the first admin user and the first data to load; recorded here
- [ ] https://mz.statbus.org answers with a working login on the stable channel, and ./sb upgrade list on the host shows the installed release; the output is recorded here
- [ ] The first agreed data load completes on mz with no failed job; the job ids and counts are recorded here
- [ ] [Owner] Decides whether mz.statbus.org starts from demo's Mozambique data (145 legal units, 10 establishments, 25 users) or from a fresh install with their files re-imported; recorded here

## Notes

2026-11-23 owner: the Mozambique cloud installation takes priority now. They are using demo.statbus.org today; their data there is checked before the install.

2026-11-23 (Rabbit) Their data on demo.statbus.org (read-only, tmp/slack-todos/demo-mz.log): demo is set up for Mozambique (settings country MZ; external idents nuit and nuel), runs v2026.11.6. Data: 145 legal units, 10 establishments, 145 enterprises, from 7 import jobs on 2026-10-30 by Mozambique users (anajosemoz: LU job 82 finished 144 rows, establishment jobs 84 and 86 finished 9 and 1; jobs 81 and 83 rejected; jobs 87 hermingardo.nhaz and 88 jorgemate36 still waiting_for_upload). Last unit edit 2026-11-11, none today so far. 25 users; in use today: jorgemate36 session last used 2026-11-23 09:41 UTC; geraldo.timbe2013 2026-11-22; intimanea 2026-11-18. Moving this data to mz.statbus.org (dump/restore of demo, or re-running their import files) is a decision for the install.
