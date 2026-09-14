---
id: STATBUS-366
title: >-
  release check: run every prerelease gate, tag nothing, write nothing; prerelease = check + tag
status: In Progress
assignee: []
created_date: '2026-09-14 10:14'
updated_date: '2026-09-14 10:14'
labels:
  - release
  - cli
dependencies: []
priority: high
type: task
---

## Why

Today the only way to run the release gates is `./sb release prerelease`,
which tags on success. So the person who can fix a red gate (coordinator,
worker) cannot run the gates without also being the person who cuts. On
2026-09-14 that cost three round trips: the owner ran prerelease, pasted the
output, the coordinator fixed, the owner ran again.

## Work

1. `./sb release check`: runs exactly the preflight `prerelease` runs, prints
   the same table, exits 1 on any red. Never tags, never pushes, never
   writes a stamp file (the CI-green branch of check 7 and the drift escape
   currently write `tmp/fast-test-passed-sha`; under `check` that write is
   skipped and the line says so). Safe to run repeatedly by anyone.
2. `prerelease` calls the same function, then tags. One code path, so what
   `check` says is what `prerelease` decides. `release stable`'s ride over
   prerelease gating is unchanged.
3. Tests: `check` on a tree with one red gate exits 1 and tags nothing;
   `check` on a green tree exits 0 and `git tag` is unchanged and no stamp
   file was created. Reuse the existing prerelease test harness.
4. Docs: `doc/release-ladder.md` names `check` as the step before asking the
   owner to cut.

## Done when

`./sb release check` at a green HEAD prints the full table and exits 0 with
no new tag and no new file under `tmp/`; at a red HEAD exits 1 with the same
diagnosis `prerelease` would print. Adversarial review by a different
session.
