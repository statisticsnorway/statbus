---
id: STATBUS-020
title: >-
  restrict-agent-test-realign: rewrite test-restrict-agent-spawn.sh to statbus
  roles + rules
status: To Do
assignee: []
created_date: '2026-06-09 16:58'
updated_date: '2026-07-03 10:45'
labels:
  - tooling
  - not-install-upgrade
dependencies: []
priority: low
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
test-restrict-agent-spawn.sh is an unadapted upstream copy. After repairing its fixture injection (commit ad14ad5a0) and the real caller-ID crash bug it surfaced, it sits at 33/41. The remaining 8 failures are assertion desyncs: the test asserts an upstream intern/scout role model and rules the statbus hook never implemented — e.g. interns may spawn agents (statbus: only the foreman spawns -> DENY), `test-intern` runs `./dev.sh test` (statbus: only `tester`), `./sb types generate` / `./dev.sh generate-doc-db` are gated (statbus has no such rule), and team-lead/foreman is denied `./sb release` (statbus: foreman MAY release).

Work: realign the test's roster + transcripts + assertions to statbus's actual roster (foreman/team-lead, engineer, architect, mechanic, operator, tester) and the hook's actual rules (Rule 1 only-foreman-spawns; Rule 4 tester-only `./dev.sh test`; Rule 5 foreman-only `./sb release prerelease`; Rule 6 operator/tester cannot commit/push). The hook itself is correct — this is test-quality only.

NOT blocking: the real caller-ID crash bug (the hook was silently crashing -> not enforcing for identified callers) is already fixed in ad14ad5a0; route-alias's sibling fixture desync is fixed in a027cf437.
<!-- SECTION:DESCRIPTION:END -->
