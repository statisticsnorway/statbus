---
id: STATBUS-037
title: >-
  standalone-upgrade-footgun: `./standalone.sh upgrade help` force-applies an
  upgrade instead of showing help
status: To Do
assignee: []
created_date: '2026-06-12 08:21'
labels:
  - upgrade
  - operator-ux
  - safety
  - standalone
dependencies: []
references:
  - standalone.sh
  - cli/cmd/upgrade.go
priority: high
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OPERATOR-SAFETY FOOTGUN (King-hit live, 2026-06-12). The King ran `./standalone.sh upgrade help` expecting a help/overview screen. Instead it executed "Force all hosts to apply latest" and triggered a real upgrade dispatch to v2026.06.0-rc.01 on the only standalone host (rune/Norway).

WHAT HAPPENS (traced):
- standalone.sh dispatches on the first arg `upgrade` → cmd_upgrade() (standalone.sh:182-189) → SSHes `./sb upgrade apply-latest` to every host, prints "Forcing all hosts to apply latest..." then "scheduled". The trailing `help` arg is silently ignored; there is NO confirmation prompt.
- `./sb upgrade apply-latest` resolves the channel's latest (rune = prerelease → v2026.06.0-rc.01), runs the schedule UPDATE (0 rows — rc.01 not a pre-discovered row), then sends `NOTIFY upgrade_apply, 'v2026.06.0-rc.01'` regardless (upgrade.go:218-238).
- The upgrade service acts on the NOTIFY payload directly (service.go:1943-1963 → scheduleImmediate), so the apply is driven by the NOTIFY, not the 0-row UPDATE.

WHY IT MATTERS: a help/typo/unknown arg one keystroke from a real command triggers a consequential production upgrade with no confirmation. This is precisely the operator-safety class the campaign exists to close (the operator's sole actions must be safe; exploring `help` must never upgrade a host). It is a hard blocker for the external-standalone story (C5) — external operators will hit this exact footgun, unattended.

THE SAFE OVERVIEW ALREADY EXISTS: `./standalone.sh status` ("Show version on all standalone hosts", standalone.sh:72) — read-only.

FIX DIRECTION (for review, not prescribed): (1) `help` / `-h` / `--help` / unknown args show usage and exit WITHOUT side effects; (2) the force-apply path requires explicit confirmation (interactive y/N or an explicit `--yes`/`--force` flag) — never fires on a help/typo; (3) consider renaming the bare `upgrade` verb to remove the help-adjacency; (4) audit the same arg-parsing class across the other consequential subcommands (wipe, reimport — they self-label DESTRUCTIVE; confirm they prompt).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `./standalone.sh upgrade help` (and -h/--help/unknown args) prints usage and exits with NO apply/schedule/NOTIFY side effect
- [ ] #2 The force-apply path requires explicit confirmation (interactive y/N or an explicit flag); it cannot fire on a help/typo
- [ ] #3 Usage documents the read-only way to see state (`status`) as the overview command
- [ ] #4 The arg-parsing footgun class is audited across standalone.sh's other consequential subcommands (wipe, reimport, install)
<!-- AC:END -->
