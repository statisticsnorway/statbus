---
id: STATBUS-366
title: >-
  release check: run every prerelease gate, tag nothing, write nothing; prerelease = check + tag
status: Done
assignee: []
created_date: '2026-09-14 10:14'
updated_date: '2026-09-14 12:56'
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

## Ruling (owner, 2026-09-14 11:08): the word `check` means "can I cut"

`release check` already exists: it verifies a CUT tag's artifacts are all
published (binaries, images, workflow). That is a `verify-*` job and moves
next to `verify-tag` and `verify-images`:

- existing `release check` -> `release verify-artifacts`, same flags
  (`--tag`, `--channel`), same output. No alias kept: an alias would leave
  the old meaning reachable under the new word.
- new `release check` = the pre-cut gate described above.

Callers of the old name that must follow the rename (grep `release check`):
`cloud.sh:624,640`, `cli/cmd/root.go:303` (the read-only allowlist),
`cli/cmd/release/release.go:1942` (hint text),
`cli/cmd/release/release_verify.go:420` (doc comment),
`cli/internal/upgrade/github.go:233`, `cli/internal/release/release_workflow.go:12`
(comments), `test/cloud-registry-test.sh:45,169`. The go-test.yaml comment
"release checker" is fine as prose.

Done-when adds: `./sb release verify-artifacts --tag v2026.09.1-rc.01`
prints the same table the old `check` printed on 2026-09-14 10:53;
`./cloud.sh` status/observe paths that call it still work (run
`test/cloud-registry-test.sh`).

## Evidence and completion (2026-09-14 12:56)

Landed `f51f2510c` (check + verify-artifacts rename) and `2b3cf5ed2` (stale-template escape consulted only when stale). Independent Luna review (mizaru) ACCEPT, no findings: `tmp/STATBUS-366-review.md`.

| done-when | evidence |
|---|---|
| check runs the full table, exits 0 on green, tags nothing, writes nothing | two consecutive `./sb release check` runs with `ls -la tmp/` diffed: no new file; `git tag` count unchanged (232) |
| check and prerelease share one preflight | same function, `checkOnly` flag; reviewer confirmed no check exists in one only |
| red HEAD: same diagnosis as prerelease, exit 1 | observed 2026-09-14 11:15 (three pending workflows) and 11:39 (403) |
| verify-artifacts byte-identical to old check | run on `--tag v2026.09.1-rc.01`, reviewer compared |
| callers updated | cloud.sh, root.go allowlist, hint text, comments; `test/cloud-registry-test.sh` PASS |

Used in anger the same day: rc.02, rc.03 and rc.04 were cut by the coordinator's poller on `release check` green, and the gate found the anonymous-auth 403 (STATBUS-368).
