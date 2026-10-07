---
id: STATBUS-455
title: >-
  admin Upgrades page: show the serving release as one running card, lift it out
  of History, and replace History counts with Applied/Superseded/Skipped pills
status: Done
assignee: []
created_date: '2026-10-07 10:15'
updated_date: '2026-10-07 12:21'
labels:
  - ui
  - upgrades
  - frontend
dependencies: []
priority: high
ordinal: 386200
---

## Status: OWNER DECIDED 2026-10-07 (all design questions answered; implement, do not re-litigate)

Owner reviewed the current page live (`https://demo.statbus.org/admin/upgrades`,
Demo on `v2026.10.0-rc.20` `bce5bf39b73fcb87ee55900fab927c36872e23c0`) and approved
the design below point by point. Design discussion and the approved ASCII layout:
`tmp/upgrades-page-serving-card-plan-20261007.md` and the chat transcript.

## Zoom out: the problem

The page's top area is loose debug text and the one fact an operator wants — *what is
running, and did its install work* — is buried.

Observed live on Demo, 2026-10-07 10:00 UTC:

- `Last install invocation: 6.10.2026, 10:30:49 (log: tmp/install-logs/v2026.10.0-rc.16-20261006T083000Z.log)`
  — an old `./sb install` stamp (the rc.16 run), displayed as if it were current.
- `Currently responding app: v2026.10.0-rc.20 bce5bf39b73fcb87ee55900fab927c36872e23c0`
  — a raw banner, no heading/card, full 40-char SHA inline.
- `18 applied · 37 superseded` / `History` / `Superseded` — collapsed; the freshly
  completed rc.20 row is inside it, invisible.
- When Demo was on `stable`, no rc.20 was offered at all and the page gave no
  explanation (separate, already-documented channel-policy UX gap — NOT this task).

Prior read-only investigations (still authoritative for the source paths):
`tmp/norway-completion-card-investigation-20261007.md`,
`tmp/norway-identity-banner-investigation-20261007.md`,
`tmp/demo-rc20-visibility-investigation-20261007.md`.

## Decisions (owner-approved, final)

- **A. Layout.** Keep the History section and everything below it exactly as-is in
  shape. Split the currently-running row OUT of History into its own card lifted to
  the top. Remove the two loose text lines at the top (identity + install invocation).
- **B. Serving key.** Key the card on the **exact-SHA match** of the responding
  artifact against the ledger (`commit_sha=eq.${artifactSHA}`), NOT on
  "newest completed row". In the ordinary case they are the same row, so the result
  is the same as today. They differ after a rollback, where only the exact-SHA rule
  remains truthful (see example below). This does NOT change any existing
  `currentUpgrade` consumer.
- **C. No duplication.** The running row is **excluded from History by the UI** —
  it appears once, in the lifted card.
- **D. Install-invocation line.** Move it INSIDE the lifted card, as a disclosure
  labelled `Installs`. Do not delete the underlying `system_info` keys.
- **(a) Pills.** History's header text loses its counts and becomes just `History`,
  still collapsible, with pill filters: **Applied** (active by default),
  **Superseded**, **Skipped**. `Applied` = `state === 'completed'` only.
  `Skipped` = `skipped` + `dismissed`. (Today's `18 applied` mislabels every
  non-superseded row as "applied", including skipped/dismissed — that is a bug.)

### B in one picture

```
serving SHA = bce5bf39 (rc.20), newest completed = #227495 rc.20 bce5bf39
  → exact-SHA and newest-completed agree (same as now)

after a rollback: serving SHA = 7e92d115 (rc.16), newest completed = rc.20
  → exact-SHA card  = rc.16   (true: that is what answers the browser)
  → newest-completed = rc.20  (false: it is not running)
```

## Approved layout (owner-reviewed)

```
                    Software Upgrades
               Manage StatBus software updates

   Channel: prerelease   Last checked: 7.10.2026, 11:51:44
   Disk: 177G free                          [ ⟳ Schedule check ]

┌──────────────────────────────────────────────────────────────────────┐
│ v2026.10.0-rc.20  (bce5bf39)  [pre-release]              [ Running ] │
│ Serving now · #227495                                                │
│ Committed: 7.10.2026 · Scheduled: 11:50:28 · ✅ Completed: 11:51:32   │
│ ▸ Details      full SHA bce5bf39b73fcb87ee55900fab927c36872e23c0     │
│ ▸ Installs     last ./sb install invocation: 6.10.2026, 10:30:49     │
│                (log: tmp/install-logs/v2026.10.0-rc.16-…log)         │
│ ▾ Log   [ 50 lines ]   (open by default)                             │
│ ▸ Changelog                                                          │
└──────────────────────────────────────────────────────────────────────┘

   (only when a newer release is offered — unchanged from today:)

┌──────────────────────────────────────────────────────────────────────┐
│ v2026.10.1 (abc12345) [release] Recommended          [ Available ]   │
│ [ ⬇ Upgrade Now ]   [ ⏭ Skip ]                                       │
└──────────────────────────────────────────────────────────────────────┘

▾ History                                    (Applied) (Superseded) (Skipped)
   ┌────────────────────────────────────────────────────────────────┐
   │ v2026.09.0 (d53731ec) [release]            [ Completed ]        │   ← rc.20 NOT here
   │ …more applied entries…                                         │
   └────────────────────────────────────────────────────────────────┘
```

Honest edge states (must render, must not be hidden):

```
no matching exact-SHA row:
  ┌ v2026.10.0-rc.20 (unknown name)  [ Running ]                    ┐
  │ Serving now · no matching install record                        │
  └─────────────────────────────────────────────────────────────────┘

row exists but not completed (scheduled / in_progress / failed / rolled_back):
  card shows the row's REAL state badge — never relabelled "Running"
```

## Exact source (HEAD `bce5bf39b73fcb87ee55900fab927c36872e23c0`)

File: `app/src/app/admin/upgrades/page.tsx` (1515 lines).

- 236-243 `fetcher`; 245-263 `systemInfoFetcher` (keep; the fresh-install-failure
  banner still needs `install_last_*` + `filterStaleInstallFailure`).
- 284-294 the components of the running card already exist:
  `artifactSHA`, `runningIdentity`, exact-SHA `useSWR` (`select=*,display_name,display_state&commit_sha=eq.${artifactSHA}`,
  30s + on focus), and `currentUpgrade = currentAppRow(artifactSHA, currentRows)`.
- 301-324 the capped list (`order=committed_at.desc&limit=100`) — History source.
- 403-419 `install_last_at` / `install_last_log_relative_file_path` derivation
  (these become the `Installs` disclosure).
- 685-699 the loose `Last install invocation` paragraph — DELETE (content moves into
  the card).
- 701-704 the loose identity banner — DELETE (content moves into the card).
- 739-764 bucketing (`history` / `available` / `actionable`) — the running row must be
  excluded from `history` here.
- 767-796 the available/current comparisons — unchanged.
- 808-820 `historyRest`, `filteredHistory`, `appliedCount`, `supersededCount` — replace
  with the three pill-filtered sets; today's `appliedCount`/`supersededCount` are only
  used by the header text being removed.
- 822-866 `renderCard`; 872-892 `topSection`; 899-944 the two `Collapsible`s.
- 952-999 `UpgradeLogViewer`; its `defaultOpen` is passed at 1332-1338
  (`!!u.error || !!u.rolled_back_at`) — the lifted card must pass `defaultOpen`.
- 1079-1250 `UpgradeCard` header/meta; 1254-1271 meta row; 1332-1350 log + changelog.
- 218-235 `StateBadge`; `upgradeStateLabel`/`installedAsLabel` imports at 12-19.

Helpers: `app/src/app/admin/upgrades/current-app.ts` (`currentAppRow`,
`newerThanCurrentApp`), `upgrade-ordering.ts`. Tests already present:
`current-app.test.ts`, `upgrade-ordering.test.ts`, `upgrade-schedule.test.ts`,
`install-failure-banner*.test.ts`. **There is no page/render test today.**

Optional small fix (do it, it is 2 lines and it is the same complaint):
`app/src/atoms/running-identity.ts:17-35` clears the resolved label before re-fetching
on every 30s refresh, so a healthy page can flash `unknown <full sha>`. Keep the last
PROVEN label until a new one is proven; never keep an unproven one.

## Acceptance criteria (final, after owner review 2026-10-07; superseded wording kept in the closing note)

- [x] A single card at the top shows the release matching the responding artifact SHA
      (`bce5bf39…`): display name, short SHA, real state badge, id and
      Committed/Scheduled/Completed inside it.
- [x] The full 40-char SHA is shown inline under a bolded `Commit:` label; the raw
      loose banner is gone. (Owner 2026-10-07: a single line must not be collapsed —
      the `Details` disclosure this AC originally asked for was replaced.)
- [x] The last `./sb install` invocation time and log path are shown inline under a
      bolded `Last ./sb install invocation:` label; the loose paragraph is gone.
- [x] The card's log is open by default; changelog remains collapsed.
- [x] The running row does not also appear in History (excluded by the UI).
- [x] No unique exact-SHA row → the card still renders with "no matching install
      record"; a non-completed row shows its true state, never "Running".
- [x] History header is exactly `History` (no counts), still collapsible, with one
      pill per badge word: `Completed` (default active) / `Superseded` / `Skipped` /
      `Dismissed`; each pill selects exactly the rows whose card carries that word.
      (Owner 2026-10-07: the original `Applied` label and the skipped+dismissed union
      both asked the reader to translate between pill and card.)
- [x] While the exact-SHA query is in flight the card shows a loading/unknown state
      instead of disappearing.
- [x] Nothing about the upgrade pipeline, ledger, migrations, REST or SQL changed.

## Constraints / rules

- Frontend rules (`.claude/rules/frontend.md`, `AGENTS.md`): `useGuardedEffect` for any
  new effect, small independent atoms, `@/` absolute imports, named exports, no
  `any` (`pnpm run lint` fails on it).
- Validate with `cd app && pnpm run lint && pnpm run tsc && pnpm run test`.
- Add render tests for the new page behavior; do not rely on `current-app.test.ts`
  alone (it only covers matching).
- Do NOT touch Demo or any live box, do not run installs/upgrades/SSH/DB, do not
  change config or channels.
- Commit with a `ui:`/`upgrades:` prefix when done; leave `.backlog/tasks/statbus-448`
  and `.yarn/` (pre-existing local dirt) alone.
