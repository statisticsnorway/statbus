---
id: d1xtta
title: "mz.statbus.org: Mozambique gets its StatBus installation"
state: todo
type: chore
priority: "medium"
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

## Notes

2026-11-23 owner: the Mozambique cloud installation takes priority now. They are using demo.statbus.org today; their data there is checked before the install.
