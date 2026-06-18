---
id: STATBUS-086
title: >-
  upgrade-cli-verbs: check/list/register/schedule (retire apply+discover) —
  schedule fail-fasts on unregistered; tests drive the real web path
status: To Do
assignee: []
created_date: '2026-06-18 11:42'
updated_date: '2026-06-18 12:50'
labels:
  - upgrade
  - cli
  - naming
  - install-recovery
  - test-fidelity
  - architect-plan
  - king-ratified
dependencies: []
references:
  - cli/cmd/upgrade.go
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/commit.go
  - test/install-recovery/lib/
  - doc/upgrade-timeline.md
  - AGENTS.md
priority: high
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DESIGN (King-ratified 2026-06-18, architect). Rename the upgrade CLI verbs so each is self-describing and NONE implies the CLI does the upgrade work — the service does. Retire `apply` (misnomer: it only queues + pokes) and `discover` (folded). The operator/client/web-UI surface becomes exactly: check, list, register, schedule. The service runs the work.

TWO LOAD-BEARING PRINCIPLES (King, absolute):
1) SCHEDULE REQUIRES REGISTER — you cannot schedule a target whose row does not exist. Attempting it is an ACTIONABLE FAIL-FAST error that names the fix: "Commit/version X is not registered — run `./sb upgrade register X` first." NO insert-if-missing (today's `apply` did that — removed).
2) ONE RUN MECHANISM = THE REAL WEB PATH — the only way an upgrade runs is: write/update the public.upgrade row -> DB trigger upgrade_notify_daemon_trigger fires NOTIFY upgrade_apply (service.go:3408) -> the service detects it and runs executeScheduled. No alternate/bypass/synchronous-CLI path, no hand-fabricated row. Tests MUST drive via register+schedule (the real code), exercising the exact production path — never fabricate_scheduled_upgrade_row.

VERB TABLE (new -> meaning -> backed by today):
- check -> reach GitHub, show releases, and register what it finds -> check (FetchReleases) + the register step.
- register <target> -> record a target (release tag OR commit, git-resolved) as a candidate (state='available'); the service then prepares it (image pull + verifyArtifacts status, service.go:1101+). Prerequisite for schedule. -> discovery's INSERT (service.go:2930/3147) + apply's insert-if-missing.
- schedule <target> -> promote an ALREADY-REGISTERED candidate -> 'scheduled'; the DB trigger NOTIFYs; the service runs it. FAIL-FAST if not registered. -> schedule (UPDATE available->scheduled, upgrade.go:127).
- list -> show registered candidates + status -> list (upgrade.go:102).
- service -> the daemon that watches for scheduled rows and runs them (name kept; King: imperfect but fine) -> unchanged.
RETIRE: apply (upgrade.go:160) + discover (upgrade.go:82). Realizes the King's "apply->schedule, schedule->register": the verb that queues-for-execution is now `schedule`; the verb that records-a-candidate is now `register`.

IMPLEMENTATION:
- register <target>: resolveUpgradeTarget (commit.go:274 — git-resolves tag/short/full-SHA; WIDEN CLI validation to accept a full 40-hex SHA, today IsCommitShort=8-char only) -> upsert a state='available' row (commit_sha, committed_at, commit_version, commit_tags, summary, has_migrations) -> NOTIFY upgrade_check so the service starts prep at once. EXTRACT one shared upsertCandidate(commit_sha, meta, state) helper so register AND discovery insert via ONE path (the literal single-insert-path the King asked for).
- schedule <target>: resolveUpgradeTarget -> find row by commit_sha -> if ABSENT: FAIL-FAST actionable error (principle 1) -> if present: UPDATE state='scheduled', scheduled_at=now(), reset the other lifecycle timestamps (so a completed/failed/rolled_back row can re-run); upgrade_notify_daemon_trigger fires NOTIFY upgrade_apply. Carry --recreate from apply onto schedule. NO insert.
- check: FetchReleases (GitHub) -> register each via upsertCandidate -> print. Subsumes discover's manual-poll role; the service still auto-discovers on its poll using the SAME register path.
- scheduleImmediate (service.go:3381, reached via NOTIFY upgrade_apply): align with principle 1 — review its current insert-if-missing upsert. Lean: require register-first uniformly (one rule for operator + service), so a NOTIFY for an unregistered commit is a loud no-op rather than a silent insert. CONFIRM with the King before changing the autonomous-discovery path.
- Retire apply + discover; regroup upgradeCmd help: "Look: check, list | Request (you ask; the service performs): register, schedule | Run: service."
- HARNESS (principle 2): replace fabricate_scheduled_upgrade_row with `./sb upgrade register <commit>` + `./sb upgrade schedule <commit>` across install-recovery scenarios — kills the wrong-topology fabrication bug class (STATBUS-067). Box must `git fetch` the commit first so rev-parse resolves it.
- SWEEP all callers/docs of apply/discover: AGENTS.md, doc/upgrade-timeline.md, ops scripts, deploy workflows (apply-latest), README. Clean break — every call site in one change (internal-code discipline).

ARCHITECT DECISIONS (override welcome): (a) register pokes the service (NOTIFY upgrade_check) for immediate prep — YES; (b) keep `list` (cheap; UI + harness read it) — YES; (c) keep `service` name — YES (King OK).

DEPENDS/RELATES: STATBUS-071 (branch-arc framework — its test driver uses register+schedule); STATBUS-010 (the stale sha-HEXHEX validator message lives in the same `schedule` validation being rewritten — fold its fix in).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI verbs are exactly check/list/register/schedule/service; apply + discover removed with all call sites updated (clean break, no shims)
- [ ] #2 register <target> accepts a release tag, an 8-char commit_short, AND a full 40-hex SHA; git-resolves it; upserts state='available'; pokes the service to prepare; register and discovery insert through ONE shared upsertCandidate helper
- [ ] #3 schedule <unregistered-target> exits non-zero with an actionable error naming the fix ('run `./sb upgrade register X` first') — no insert-if-missing
- [ ] #4 schedule <registered-target> promotes the row to 'scheduled' (resetting lifecycle so completed/failed can re-run), the DB trigger fires NOTIFY, the service runs it; --recreate carried over from apply
- [ ] #5 check fetches GitHub releases AND registers them via the same upsertCandidate path
- [ ] #6 the ONLY run path is write-row -> trigger -> service (no bypass/synchronous CLI); the harness fabricate_scheduled_upgrade_row is replaced by register+schedule and no hand-rolled scheduled-row INSERT remains in tests
- [ ] #7 help text regrouped (Look / Request / Run); AGENTS.md + doc/upgrade-timeline.md + deploy workflows + ops scripts carry no stale apply/discover references
- [ ] #8 end-to-end VM proof: register -> status reaches ready -> schedule -> service runs -> worker_status/upgrade_changed callback -> row completed; AND schedule-unregistered -> actionable error + non-zero exit
- [ ] #9 scheduleImmediate (the NOTIFY upgrade_apply handler, service.go:3381) requires-register uniformly — its insert-if-missing upsert is REMOVED; a NOTIFY for an unregistered commit is a loud actionable no-op (matching schedule's fail-fast); NO registerAndScheduleImmediately verb exists; since the CLI `schedule` now does the scheduling, the handler is renamed to an execute/react name or folded into executeScheduled
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RESOLVED — the open scheduleImmediate question (King, 2026-06-18): OPTION A, UNIFORM. `schedule` means 'queue an ALREADY-REGISTERED target' EVERYWHERE — the CLI verb AND the service-side handler. So scheduleImmediate (service.go:3381, the NOTIFY upgrade_apply handler) must ALSO require-register: REMOVE its insert-if-missing upsert. A NOTIFY upgrade_apply for an unregistered commit becomes a loud, actionable no-op (same fail-fast semantics as `schedule`), never a silent insert.

NO `registerAndScheduleImmediately` verb — REJECTED on the design's own logic: a one-shot register+schedule would queue a target BEFORE it is prepared (images pulled / verifyArtifacts status reaches ready), which is exactly what the register→schedule split exists to prevent. No legitimate caller wants schedule-before-prepared: apply-latest = schedule the already-discovered latest; a brand-new release = register → wait for ready → schedule. So the combined behavior is REMOVED, not renamed.

NAME: because the CLI `schedule` now performs the actual scheduling (sets the row → trigger → NOTIFY), the service-side function no longer schedules — it REACTS to a scheduled-row notification (supersede older + hand to execution; it currently only sets 'scheduled' + supersedes, guarded against a NOTIFY loop by WHERE state!='scheduled', and does NOT execute inline). Rename scheduleImmediate → an execute/react name (e.g. onScheduledNotify) OR fold into executeScheduled (service.go:3487). Engineer's call at build.

SEQUENCING: this RESOLVES the design (no remaining open question on 086); the CODE BUILD stays PHASE 2 (post-rc.04) per the foreman's sequencing — scheduleImmediate is in the rc.04 code and must not be touched until rc.04 is tagged.
<!-- SECTION:NOTES:END -->
