---
id: STATBUS-487
title: >-
  A bare box with no reachable Docker fails the install with an
  unmeasurable-disk message instead of naming Docker as the prerequisite
status: In Progress
assignee: []
created_date: '2026-10-13 12:17'
updated_date: '2026-10-13 13:29'
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
- [x] #1 Before any other work (before downloading, checkout or any state change), the install preflight verifies all three: the Docker CLI exists, the daemon answers, and the invoking user may use it. Checked by tests that stub each failure and assert the refusal happens first.
- [x] #2 Each of the three causes gets its own plain sentence naming the exact remedy and the exact rerun command: Docker absent -> install it (the documented path), daemon stopped -> start it, user not permitted -> add the user to the docker group and log in again. Checked by asserting each message, and by the absence of the generic sentence for these cases.
- [x] #3 The unmeasurable-disk refusal can no longer be the first thing an operator sees when the real cause is Docker: the observed Uganda line is pinned as a regression test. Checked by cli/internal/diskpolicy tests plus an install.sh message test.
- [x] #4 The design decision is recorded in the ticket and in the code: either install.sh installs Docker itself the way ops/setup-ubuntu-lts.sh does, or it refuses with instructions and the message points at the documented prerequisite step. Checked by the decision text plus whichever implementation follows.
- [ ] #5 The operator-facing result is observed, not asserted: the next real run on the Uganda box either installs or prints a remedy naming Docker. Checked by pasting that output into the ticket.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The red-then-green pair is recorded: the preflight absent/failing before the change, and the new refusals after it.
- [x] #2 The ticket says what was decided about installing Docker versus refusing, and why.
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

2026-10-13 FIX d5f7b6503 (install: name the Docker cause before any work).

DECISION (AC#4, DoD#2): REFUSE with instructions, do NOT install Docker from install.sh. install.sh runs as the unprivileged install user, and both installing Docker and joining the docker group need root and then a NEW login session, which one install run cannot provide; ops/setup-ubuntu-lts.sh (doc/setup-ubuntu-lts.md) already does it with the OS hardening StatBus expects. The same decision is in code comments at install.sh (DOCKER PREFLIGHT block) and cli/internal/diskpolicy/policy.go (DockerSetupGuide).

WHAT CHANGED:
- install.sh: statbus_docker_preflight runs right after the banner, before release lookup (curl), clone/fetch (git), binary download and any ~/statbus state. It checks the CLI exists, then runs docker info as this user, and classifies: absent / daemon stopped / user not permitted. Unknown failures print Docker's own words, never a guessed remedy.
- The three sentences (identical in shell and Go):
  * Docker is not installed. StatBus needs Docker before it can install: run the server setup script as root, which installs it (https://github.com/statisticsnorway/statbus/blob/master/doc/setup-ubuntu-lts.md), then run the same install command again: <rerun>
  * Docker is installed but its service is not running. Start it with sudo systemctl enable --now docker, then run the same install command again: <rerun>
  * The user statbus may not use Docker (Docker said: permission denied while trying to connect to the docker API at unix:///var/run/docker.sock). If getent group docker does not list statbus, run sudo usermod -aG docker statbus. Then log out and log in again so id -nG lists docker, and run the same install command again: <rerun>
  The third names both steps in order and how to tell stale-session from non-member (getent vs id -nG), and quotes the daemon's words reduced to a fixed shape.
- cli/internal/diskpolicy.DockerRoot now returns those same sentences when ./sb meets the cause later (rescue path); the generic 'Docker root unavailable' line remains only for unrecognised failures.
- install.sh exit-78 allow-list: one new FULL-LINE anchored bucket for the three sentences (charset-limited user, fixed-shape quote, exact rerun at end-of-line), placed before the disk-unmeasurable bucket. Existing anchors untouched.

RED (before the fix; tmp/487-red-*.log):
  --- FAIL: TestDockerRootNamesTheUgandaPermissionCause: the Uganda permission cause is still masked by the disk sentence: "cannot check disk space at Docker storage: Docker root unavailable"
  --- FAIL: TestDockerRootNamesAStoppedDaemon / TestDockerRootNamesAMissingDocker: ... Docker root unavailable
  --- FAIL: TestInstallShRefusesEachDockerCauseBeforeAnyWork/docker_absent: output still carries "is required but not installed"
  --- FAIL: .../daemon_stopped and .../user_not_permitted_(Uganda): work started before the Docker refusal: "curl -sL https://api.github.com/repos/statisticsnorway/statbus/releases/latest"
  --- FAIL: TestExit78AllowlistCarriesDockerSentences/{absent,stopped,denied}: Docker sentence did not cross the boundary
GREEN (after): all of the above PASS, plus TestDockerRootUnavailableFailsClosed, TestDockerRootKeepsGenericLineForUnknownFailure, TestInstallShDockerPreflightLetsAWorkingDockerThrough, TestExit78AllowlistMatchesRealGoSentences (all 9 existing subcases). go test ./cmd ./internal/diskpolicy ./internal/upgrade ok; test/install/{install-git-errors,install-git-fetch-compatibility,install-pull-failure}-test.sh rc=0; shellcheck -S warning install.sh clean.

The install.sh tests run the REAL script end to end with stub docker/git/curl and assert: exact sentence printed, no 'Docker root unavailable', no git/curl call recorded, ~/statbus not created.

AC#5 stays open: needs the next real run on the Uganda box (owner).

CI for d5f7b6503 (job level): its own Go Test run 38402262627 was CANCELLED (superseded by bbeefa563, which contains d5f7b6503). On bbeefa563: Go Test 38402510153 'cli go test ./...' success + golangci-lint success; app build & lint 38402510344 build-app success; Harness Selftest 38402510198 success. On d5f7b6503 itself: Images 38402262707 success, Harness Selftest 38402262886 success, CodeQL success. Fast Tests (pg_regress) cancelled on every SHA since by newer pushes in the same concurrency group (38402819859, 38403121002, 38403771288); this change touches no SQL. AC#5 open (Uganda box rerun).
<!-- SECTION:NOTES:END -->
