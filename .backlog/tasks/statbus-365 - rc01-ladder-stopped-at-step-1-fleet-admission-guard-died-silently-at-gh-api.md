---
id: STATBUS-365
title: >-
  rc.01 ladder stopped at step 1: fleet admission guard (admit.sh) died silently
  at gh api on its first real run, orchestrator mislabelled it SUPERSEDED
status: In Progress
assignee: []
created_date: '2026-09-07 21:03'
updated_date: '2026-09-15 13:10'
labels:
  - ci
  - release
  - fail-fast
dependencies: []
priority: high
type: bug
ordinal: 2
---

## What happened

`v2026.09.1-rc.01` (`b6d810493`) was tagged at 20:47. Release Fleet
Orchestrator run 34160749022 dispatched Test Smoke run 34160818299. Its
first step, `orchestrator-fleet-admission/admit.sh` (added 09-04 in
`4284eeca2`, STATBUS-350, never exercised on a real RC until now), exited 1
after 0.9 s **without printing any of its own `::error` lines**. Under
`set -euo pipefail` that means the `gh api repos/.../actions/runs/<id>` call
itself failed (token is the workflow `GITHUB_TOKEN` with `actions: read`).
The orchestrator then stopped the chain and its summary job says
"SUPERSEDED — stopped for a newer candidate", which is false: no newer
candidate exists.

Run locally against the same (now completed) parent, the script prints its
reason correctly, so the script logic is fine; the failure is the API call
in the runner's context.

## Work

1. Find the real cause from the run logs (`gh run view 34160818299 --log`,
   job "Select smoke scenarios"), reproduce as closely as possible with a
   workflow-scoped token, and fix it. Candidates: `gh` not authenticated via
   `GH_TOKEN` in a composite action, `actions: read` insufficient for
   `GET /actions/runs/{id}` on this repo, `jq -e` exit on a field shape.
2. `admit.sh` must fail loudly: capture `gh api` stderr and HTTP status and
   print them before exiting. A guard that refuses without saying why is a
   guard nobody can fix at 21:00 on release night.
3. The orchestrator must not call a child failure "SUPERSEDED" unless it
   actually observed a newer tag. Failure for the child's own reasons is
   "FAILED at step N" with the child run URL.
4. Tests: a unit test for the admission decision that runs the script
   against a recorded parent JSON (in_progress, completed, wrong sha, wrong
   path), asserting both exit code and the printed reason; `actionlint`.
5. Adversarial review by a different session, then the coordinator cuts
   rc.02 from the fix commit and the ladder re-runs.

## Done when

Test Smoke for the next RC passes admission and prints
`Admitted orchestrated paid run: ...`; the orchestrator's summary names the
real outcome. Both observed in `gh run view` output, recorded here.

## Status (2026-09-14 09:46): In Progress

Fix landed `9ced4480f` (guppy). What is certain: admit.sh now prints gh exit code, HTTP status and stderr before refusing; the orchestrator verdict job only says SUPERSEDED when it observed a newer tag, otherwise FAILED at step N with the child URL and exits 1. Tests run the script against recorded parent JSON.

What is not known: the actual cause of rc.01's `gh api` failure. The old script discarded the response; guppy verified GH_TOKEN injection and `actions: read` are correct on paper. Only a real run tells.

Owner ruling 2026-09-14: skip the full adversarial review; the ladder is the test. Coordinator checked the one bypass risk: the two test seams (`STATBUS_ADMISSION_PARENT_JSON_FILE`, `STATBUS_ADMISSION_TEST_MODE`) are referenced only by admit.sh and the Go test, no workflow sets them. Header/body split verified by hand on a sample response. Done when rc.02's Test Smoke prints `Admitted orchestrated paid run`, or refuses with a printed reason that we then fix.

## rc.02 (2026-09-14 11:21, `f51f2510c`): refused again, same shape

Test Smoke run 34837856470: admit.sh exited 1 after 0.8 s with NO output,
even though the tag carries the loud version (`9ced4480f`). So the failure is
in the lines BEFORE the guarded `gh api` block: run-id empty check, regex
check, `mktemp`. The `env:` block in the log shows both `ORCHESTRATOR_RUN_ID`
and `GH_TOKEN` arriving. Locally under the runner's exact shell flags
(`bash --noprofile --norc -e -o pipefail`) with a user token the script reaches
`gh api`, gets 200, and refuses only because the parent is now completed.

Half of 365 is proven: the orchestrator's verdict job (34837756831) said
"Fleet verdict — superseded or failed: failure", not SUPERSEDED.

Diagnosis pass: `5115d9714` adds `set -x` plus a "reached" echo with tool
paths and `gh --version` at the top of admit.sh. rc.03 is cut from it purely
to read that trace; admission runs before any VM, so it costs nothing. The
trace comes out again with the real fix (rc.04).

## Side finding (11:39): `release check` is unauthenticated unless GITHUB_TOKEN is set

Polling `./sb release check` every 30 s exhausted GitHub's anonymous 60/h
limit; the gate then reported every workflow as "GitHub API error HTTP 403".
`githubAuthHeader()` (`cli/internal/release/check.go:332`) reads only
`GITHUB_TOKEN`; it does not fall back to `gh auth token`. Workaround used:
`GITHUB_TOKEN=$(gh auth token) ./sb release check`. Filed as STATBUS-368.

## Root cause (rc.03 trace + rc.04 warning, 2026-09-14)

The line was `git fetch --tags --quiet origin` in admit.sh, after the
`gh api` block. git's reason, printed by the rc.04 fix:

    ! [rejected] v2026.09.1-rc.04 -> v2026.09.1-rc.04  (would clobber existing tag)

actions/checkout (fetch-depth 0) already fetched every tag with
`+refs/tags/*:refs/tags/*`. A second `git fetch --tags` then asks git to
write the candidate's own tag again; git refuses to overwrite an existing
tag ref, exits 1, and `--quiet` + `set -e` discarded the message. It was
never auth, network, or the runner image; it failed deterministically on
every RC since the guard was added (`4284eeca2`, 09-04) and would have
failed forever. The orchestrator's own joints never hit it: its decide job
does not fetch, and its later joints fetch with `|| true`.

Fix `c1b8d4dab`: the trace is removed; the fetch is guarded, prints git's
reason as a `::warning`, and admission decides on the tags the checkout
already holds (a complete set at fetch-depth 0). rc.04 (`c1b8d4dab`):
Test Smoke 34840110574 printed `Admitted orchestrated paid run: parent=
34840001592 candidate=v2026.09.1-rc.04` and dispatched both smoke VMs.

Done-when for this ticket is met at rc.04 admission. Ticket closes with the
batch when the ladder is green.

Cost of the silent line: rc.01, rc.02, rc.03 (three cuts, no VM time).

## Release checkpoint: 2026-09-15 13:05 UTC

The original admission defect is repaired and admission passed on rc.08 and
rc.09. This ticket remains In Progress only for the agreed whole-ladder
closeout, not because its original defect remains unfixed.

rc.09's concurrent-install recovery proof failed. The resulting product
lock-lifetime repair and harness repairs are on master at `510c76e4c` and
`1271dc98d`; details and evidence are in STATBUS-369. The attempted rc.10
pre-cut Go run `34970946642` failed before any tag was created: the new
offline-test step interrupted required checkout-to-admission adjacency.

Cricket independently approved scratch follow-up `1c0bbe83e488205bd4ca7cf1b0fa0d92852a628e`:
move the unchanged test step after admission, still before Go setup/build
and paid resources. The existing STATBUS-350 guard fails old and passes new;
the full release Go package and affected harness suites passed. No guard
was weakened. Root is landing this follow-up with this checkpoint, then
pushing and observing exact-commit CI and authenticated `release check`
before cutting rc.10. The published-candidate ladder supplies acceptance;
a manual VM pass is not a pre-cut prerequisite. Norway/promotion remain
the owner's, and the post-release batch remains deferred.

## rc.10 published (2026-09-15 13:09 UTC)

The reviewed workflow correction landed as `bd45f25ce`. Its Images
`34972873710`, Go Test `34972873773`, and app `34972873755` runs passed;
authenticated `release check` and `release prerelease` then passed.
`v2026.09.1-rc.10` was pushed at exact commit
`bd45f25ce309ac7c40e758ec17ecd73ba6f661af`. The release ladder is now running
under orchestrator `34973239226`. This is publication, not a green-ladder
claim. Next: observe the actual candidate rungs and fix only observed reds.
Publication evidence is in `tmp/rc10-cut.log` and `tmp/rc10-published-tag.txt`.

## rc.11 cut (2026-09-15 18:24 UTC)

rc.10's recovery ladder completed with the coverage-aware parent-only retry
(`gh run rerun 34973239226 --failed`) dispatching exactly the one cloud-failed
scenario, preserving the 12 passed proofs — direct observed validation of the
admission guard + covered-subset path. Its 35-arc run then produced six harness
failures (3 assertion drifts, 1 STATBUS-354 step drift, 2 floor-arc lineage
wirings), all fixed on master; rc.11 (`5e51741d1`) now carries them and is
running the ladder. The admission-guard root cause from this ticket has not
recurred.
