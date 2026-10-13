---
id: STATBUS-487
title: >-
  A bare box with no reachable Docker fails the install with an
  unmeasurable-disk message instead of naming Docker as the prerequisite
status: In Progress
assignee: []
created_date: '2026-10-13 12:17'
updated_date: '2026-10-13 12:19'
labels:
  - install
  - fidelity
  - uganda
dependencies: []
priority: high
type: bug
ordinal: 413204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 on a real operator installation in UGANDA (owner's remote box), which could not install at all. This is the last blocker of that installation and the only one still standing.

OBSERVED (verbatim, the operator ran `curl -fsSL https://statbus.org/install.sh | bash`):
  Latest stable release: v2026.10.0
  Updating existing installation...
  Installed program: sb version v2026.10.0 (commit bce5bf39)
  Checking out v2026.10.0... (long tag fetch) HEAD is now at bce5bf39b
  Preparing a new StatBus installation.
  cannot check disk space at Docker storage: Docker root unavailable
  <prompt returns; nothing installs>

WHAT IT MEANS, grounded:
- cli/internal/diskpolicy/policy.go:82-99 (DockerRoot) runs `docker info --format '{{.DockerRootDir}}'` in the project directory and REFUSES TO GUESS. It raises "cannot check disk space at Docker storage: Docker root unavailable" when the command cannot be started, when its output is empty, or when the reported path is not a directory.
- install.sh:922-923 matches that line and prints it, then stops. The disk-space preflight never runs, so the install makes no progress.
- install.sh does NOT install Docker: the curl installer assumes it is present. ops/setup-ubuntu-lts.sh:1005-1027 is what installs and starts docker-ce plus the compose/buildx plugins and verifies both.

THE GAP: three different operator situations - Docker not installed, the daemon not running, the install user not permitted on the socket (not in the docker group, the usual state immediately after installing Docker) - all produce that one sentence, which names none of them and offers no remedy. An operator following the published instructions on a fresh Ubuntu box is left to read the source to learn that Docker was the missing prerequisite.

NORTH STAR: a fresh Ubuntu box whose Docker is absent, stopped or unreachable refuses the install BEFORE it does any work, with one plain sentence naming Docker, the exact remedy for that specific cause, and the exact rerun command - and the disk-space measurement runs only once Docker can actually answer.

RELATED: STATBUS-376 (a third-party operator installs from the published instructions alone) is the parent concern; this is a live instance of it. STATBUS-422 is the Finland field report of the same shape for a different step. STATBUS-474 was the owner's previous real-guest run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Before any other work (before downloading, checkout or any state change), the install preflight verifies all three: the Docker CLI exists, the daemon answers, and the invoking user may use it. Checked by tests that stub each failure and assert the refusal happens first.
- [ ] #2 Each of the three causes gets its own plain sentence naming the exact remedy and the exact rerun command: Docker absent -> install it (the documented path), daemon stopped -> start it, user not permitted -> add the user to the docker group and log in again. Checked by asserting each message, and by the absence of the generic sentence for these cases.
- [ ] #3 The unmeasurable-disk refusal can no longer be the first thing an operator sees when the real cause is Docker: the observed Uganda line is pinned as a regression test. Checked by cli/internal/diskpolicy tests plus an install.sh message test.
- [ ] #4 The design decision is recorded in the ticket and in the code: either install.sh installs Docker itself the way ops/setup-ubuntu-lts.sh does, or it refuses with instructions and the message points at the documented prerequisite step. Checked by the decision text plus whichever implementation follows.
- [ ] #5 The operator-facing result is observed, not asserted: the next real run on the Uganda box either installs or prints a remedy naming Docker. Checked by pasting that output into the ticket.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The red-then-green pair is recorded: the preflight absent/failing before the change, and the new refusals after it.
- [ ] #2 The ticket says what was decided about installing Docker versus refusing, and why.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-13 from the owner's live Uganda installation, which is otherwise ready. Immediate operator-side diagnosis sent to the owner: check `command -v docker`, `docker info --format {{.DockerRootDir}}` as the install user, `systemctl is-active docker` and `groups`; the three outcomes map to the three causes. Owner instruction: report the issue, ticket it, and assign an agent.

2026-10-13 LIVE EVIDENCE from the Uganda box, confirming WHICH of the three causes it is (operator ran the coordinator's diagnostic commands):

  $ command -v docker && docker info --format '{{.DockerRootDir}}' ; echo "rc=$?"
  /usr/bin/docker
  permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
  rc=1
  $ systemctl is-active docker
  active
  $ groups
  statbus adm cdrom sudo dip plugdev users lpadmin lxd

So: Docker is INSTALLED, the daemon is RUNNING, and the install user is NOT PERMITTED on the socket. The installer could have said precisely that, and instead said "cannot check disk space at Docker storage: Docker root unavailable".

Two refinements the fix needs, both visible in this evidence:
1. The remedy has an order. "Log in again" alone is wrong when the account is not a member yet, and "add the user to the docker group" alone does nothing until a new session. The message must name both steps in order, and tell the operator how to find out which one they are in, e.g. `id -nG` or `getent group docker` (a stale session and a non-member look identical from `groups` in the current shell).
2. The refusal should quote the daemon's own words when it has them ("permission denied while trying to connect to the docker API at unix:///var/run/docker.sock"), reduced to the single anchored line the install-log boundary permits, rather than swallowing them behind the disk-space sentence.
<!-- SECTION:NOTES:END -->
