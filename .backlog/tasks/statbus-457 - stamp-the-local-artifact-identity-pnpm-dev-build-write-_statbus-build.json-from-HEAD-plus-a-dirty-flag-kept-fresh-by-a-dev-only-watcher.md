---
id: STATBUS-457
title: >-
  stamp the local artifact identity: pnpm dev/build write _statbus-build.json
  from HEAD plus a dirty flag, kept fresh by a dev-only watcher
status: In Progress
assignee:
  - '@macaque'
created_date: '2026-10-07 11:20'
updated_date: '2026-10-07 13:07'
labels:
  - cli
  - frontend
  - devx
dependencies: []
priority: medium
ordinal: 386202
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star

`public/_statbus-build.json` answers one question: which commit is this artifact built from? Only image publication answered it, so every local run reported `unknown` and both the footer and the admin serving card (STATBUS-455) degraded on a development box. Locally the honest answer is the working tree's commit plus whether it has been modified.

## What was done

- `app/scripts/stamp-app-build.mjs` keeps `--image <sha>` precedence and now falls back to the git HEAD of the `app/` subtree: `{"commit_sha":"<40-hex>","dirty":true|false}`, with dirty decided by `git status --porcelain -- .` (untracked files count). No git work tree yields `{"commit_sha":null}`. The content computation is shared with the watcher.
- `pnpm run dev` starts `app/scripts/watch-app-build.mjs` beside the dev server: it stamps once, polls HEAD and git status every ~5s, writes only on change, and exits with the dev server. It is not imported by anything under `app/src/`.
- `public/_statbus-build.json` is in `app/.dockerignore`, and the Dockerfile still stamps with `--image` before the build, so a dev-written file can never become a published identity.
- `app/src/lib/app-build.test.ts` covers clean HEAD, dirty tracked, dirty untracked, `--image` precedence, non-git, and one-shot == watcher content. Behaviour is noted in `doc/DEVELOPMENT.md`.

## How you know it is done

The stamp script run in a dirty `app/` writes the commit with `dirty:true`; the one-shot and the watcher agree; `pnpm run dev` keeps the file current while the tree changes; the app gates are green; the image path still takes `--image`.

## Out of scope

- No dynamic identity route, no polling added inside the app, no new dependency.
- `scripts/stamp-if-clean.sh` and the release-gate stamps were not touched.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `pnpm run build` in a clean `app/` writes `{"commit_sha":"<HEAD>","dirty":false}`.
- [x] #2 `pnpm run build` with an uncommitted `app/` change writes
      `{"commit_sha":"<HEAD>","dirty":true}`, including when the only change is a new
      **untracked** file.
- [x] #3 `node scripts/stamp-app-build.mjs --image <40-hex>` still writes exactly the
      image SHA and wins over any local state; invalid/missing `--image` → `null`.
- [x] #4 Outside a git work tree the script writes `{"commit_sha":null}` and exits 0.
- [x] #5 `pnpm run dev` writes the stamp at start; committing, switching branch, or
      editing a file updates it within ~10s without restarting the dev server, and
      the running page reflects it within ~30s or on focus.
- [x] #6 The watcher is not referenced from any file under `app/src/`.
- [x] #7 `public/_statbus-build.json` is in `.dockerignore`; the Dockerfile still stamps
      with `--image` before `next build`.
- [x] #8 `app/src/lib/app-build.test.ts` (and any new script test) covers: clean → HEAD,
      dirty tracked → flag, dirty untracked → flag, `--image` precedence, non-git →
      null, and that the one-shot output equals the watcher's computed content.
- [x] #9 `cd app && pnpm run lint && pnpm run tsc && pnpm run test` green.
- [x] #10 Note in `doc/DEVELOPMENT.md` (or the script header) that local identity is
      HEAD + dirty flag, that the dev watcher keeps it fresh, and that images always
      use the checkout SHA.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
REOPENED 2026-10-07: CI proved this ticket's work incomplete. app build & lint run 37624277184 failed 6 of 6 git-dependent tests in src/lib/app-build.test.ts with spawnSync git ENOENT: the app CI image has no git binary at all. The tests pass locally only because the developer machine has git. Required fix: make the tests hermetic (put a fake git executable on PATH and script its rev-parse HEAD / status --porcelain responses) rather than skipping them, so they run in CI and still pin HEAD, dirty, --image precedence and the no-git case.
<!-- SECTION:NOTES:END -->

## Status: OWNER APPROVED 2026-10-07 (option (iii) + dev watcher). Implement as specified.

## Zoom out: why this exists

`public/_statbus-build.json` answers one question: *which commit is this artifact
built from?* Today only image publication answers it (`app/Dockerfile:31-32`:
`ARG COMMIT` → `node scripts/stamp-app-build.mjs --image "$COMMIT"`), so every local
run writes `{"commit_sha":null}` and the whole identity chain (footer version, and
the admin Upgrades "serving" card added in STATBUS-455) degrades to
`unknown` / "no matching install record" while developing.

Owner decision 2026-10-07, after reviewing the concrete per-option rendering:

- Local stamp = **HEAD plus a `dirty` flag** (option (iii)), never a bare
  unqualified HEAD while the tree is modified.
- `pnpm run dev` and `pnpm run build` both stamp; the **dev server keeps it
  current** without a restart.
- No dynamic route, no dev-only branch inside the app bundle.

## Requirements

### R1 — one implementation of the stamp

`app/scripts/stamp-app-build.mjs` keeps `--image <sha>` precedence (invalid/missing
→ `commit_sha: null`, unchanged) and gains the local fallback:

```
{ "commit_sha": "<40-hex HEAD>", "dirty": true|false }   // local
{ "commit_sha": "<40-hex>", "dirty": false }             // --image
{ "commit_sha": null }                                   // no git work tree
```

- `commit_sha` stays exactly 40 lowercase hex or `null`; `parseArtifactSHA` ignores
  extra keys, so the `dirty` flag is additive and cannot break existing readers.
- Dirty is decided by `git status --porcelain -- .` run from `app/` — **untracked
  files count**. (This differs deliberately from `scripts/stamp-if-clean.sh`, whose
  `git diff`-only rule feeds the release gate and stays as it is.)
- No git work tree (docker build, tarball) → `{"commit_sha":null}`.
- Extract the content computation so the one-shot script and the watcher share it.

### R2 — pnpm owns both entry points

- `pnpm run build` stamps once before `next build` (already does; keep `--image`
  precedence intact for the Dockerfile).
- `pnpm run dev` starts the watcher and the dev server together, e.g.
  `node scripts/watch-app-build.mjs & next dev --turbopack`.

### R3 — the dev-only watcher

New `app/scripts/watch-app-build.mjs`:

- writes the stamp once at start, then polls every ~5s;
- polls `git rev-parse HEAD` and `git status --porcelain -- .`;
- **writes only when the content changes**, and prints one line when it does,
  e.g. `stamp: d98bfb96 (+dirty)`;
- exits on SIGINT/SIGTERM with the dev server;
- is never imported by any app/Next code: it must not appear in the server or
  client bundle.

### R4 — production cannot be polluted

- The image keeps its authority: the Dockerfile stamps with `--image "$COMMIT"`
  before `next build`, so anything a dev session left behind is overwritten.
- Add `public/_statbus-build.json` to `.dockerignore` (it is generated and
  gitignored) so a dev-written file never even enters the build context.

### R5 — freshness end to end

Nothing else is needed: the identity atom already fetches `/_statbus-build.json`
with `cache: 'no-store'` on mount, every 30s and on window focus
(`app/src/atoms/running-identity.ts`), so a changed stamp shows up within ~30s or
immediately on focus. Do not add polling inside the app.

## Constraints and non-goals

- No change to `parseArtifactSHA`/`parseRunningIdentity` semantics, no change to the
  serving card's matching rule (still exact SHA), no schema or REST change.
- No dynamic identity route, no polling added to the app, no new npm dependency
  (polling beats a file-watcher dependency here).
- Do not modify `scripts/stamp-if-clean.sh` or `tmp/*-passed-sha` gating.
- Local code and tests only: no live boxes, installs, upgrades or config changes.
- Commit with a `devx:`/`ui:` prefix; leave `.backlog/tasks/statbus-448` and
  `.yarn/` alone.
