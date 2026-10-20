# sb behaves by how it was built (STATBUS-392 redesign)

Agreed with the owner on 2026-10-20. This replaces the earlier `--no-build` design.

## The problem we are solving

A StatBus installation is one of two kinds:

- **A release install** (dev, demo, Norway, the country boxes, a country's laptop test). It runs the images
  we published for its version. What runs there must be exactly what we tested and released.
- **A developer's source build.** It builds images from the code on disk, so a code change shows up
  after `./sb start`.

In September (Finland triage) `./sb start` forced `--build` whenever the site was in development mode,
so a release install could rebuild from source. We fixed that by forcing `--no-build` and guessing the
kind of install from the `VERSION` line in `.env`. On review that was the wrong fix:

- **It tested flag strings,** not outcomes. A proposed real-box timing test would have tested Docker
  Compose, not our code.
- **It answered "which kind of install is this?" in its own private way,** rather than from what the
  binary already knows.

## What Compose does on its own

All our services declare both `image:` and `build:`. Checked locally (tmp/392-compose):

| Image on the box | plain `up -d` | `up -d --no-build` |
|---|---|---|
| present | uses it | uses it |
| absent | pulls; if the pull fails, builds | pulls; if the pull fails, stops ("No such image") |

## The design

### 1. One source of truth: the binary's build identity

The `sb` binary carries the version it was built with:

- `v2026.10.3-rc.01` (a tag) means a **release build**
- `v2026.10.3-23-g34cd535ea` (a commit between tags) means a **source build**

One function answers "release build or source build?", and every command that cares uses it: start,
restart, and command visibility.

**Why not `CADDY_DEPLOYMENT_MODE`:** that setting says how the site is *served* (ports, TLS, proxy),
not how its images are made. A country testing a release on a laptop in development mode is still a
release install. Using the build identity also lets a developer exercise release behaviour locally by
running a release binary.

### 2. Start and restart follow the kind of build

- **Source build:** `docker compose up -d --build`. Code changes are built and started.
- **Release build:**
  1. **A cheap local check** (no network): do this version's images exist on the box?
  2. **All present** (the normal case): start with `--no-build`.
  3. **Any missing:** this only happens after a deliberate `docker image prune` or a disk clean-up. Print
     "Images for v… were missing locally (removed by a prune?); pulling them, then starting", pull,
     then start with `--no-build`.
  4. **The pull fails:** stop with the remedy: check the network and run the command again, or build
     locally with `./sb build`.

Install and upgrade already work this way: they pull first, verify, and then start with `--no-build`.
So **a running release stack always means the images were pulled**, and never that they were built
quietly.

### 3. Commands grouped by purpose; developer commands kept out of the way on release builds

- `./sb --help` lists commands under two headings:
  - **Operations:** install, start, stop, restart, logs, ps, psql, db, users, upgrade, config, cert,
    support, uninstall
  - **Development:** build, release, test, types, migrate, assert-db-*
- **On a release build** the Development group is hidden from the list.
  - The help ends with: "Development commands are hidden on a release install; `./sb help --all` lists
    them."
  - `./sb help --all` lists every command.
  - **A hidden command still runs, and its own help still works** (`./sb migrate --help`). Cobra does
    this by design. Hidden means out of the way, not removed, because support sometimes needs them.

sb has no grouping or mode-dependent visibility today (checked: no cobra `AddGroup`/`GroupID` anywhere).

### 4. What we test: outcomes, not flags

- **Clean LXD install and clean upgrade:** after the run, every StatBus service image on the box carries
  a `ghcr.io/...@sha256:...` registry digest, read from Docker's own image record. A pulled image has
  one; a locally built image has none.
- **Go tests:** the image check and its three cases (present, missing then pulled, pull failed); the help
  output on a release build and on a source build; `help --all`.
- **No timing test on a real box** (old AC4, withdrawn by the owner).

## Removed

- `startBuildsFromSource` (the `VERSION`-string guess) and its tests
- the forced `--no-build` / `--build` decision in start and restart, replaced by the above

## Ticket

STATBUS-392, criteria 1 to 6. Earlier criteria 1 to 3 (the `--no-build` design) are superseded; their
commits (05a4fe9dd, e622a4f9a) stay in history.
