---
id: STATBUS-284
title: >-
  cloud-doc-port-accuracy: CLOUD.md's port formula and REST column contradict
  the table, config.go, and AGENTS.md's canonical scheme
status: To Do
assignee: []
created_date: '2026-08-27 17:02'
updated_date: '2026-08-27 17:02'
labels:
  - doc
  - cloud
dependencies: []
priority: low
type: bug
ordinal: 277000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the mechanic during the Ukraine row addition (2026-08-27), pre-existing across all rows: doc/CLOUD.md's Port Allocation section is internally inconsistent.

1. The prose formula (doc/CLOUD.md:313) states `DB_PORT = 3000 + (OFFSET * 10) + 14`, but every table row — and the actual computation in cli/internal/config/config.go, and AGENTS.md's canonical 7-port scheme — is `+4` (dev at offset 1 has DB=3014; the prose formula would give 3024, which is the reserved offset-2 slot's DB port). The `14` reads like a fossil of "3014 for slot 1" mistaken for a constant.
2. The table's REST column equals its HTTPS column in every row (e.g. dev 3011/3011), while AGENTS.md's canonical scheme puts rest at offset+3 (dev: 3013). Either the column means "the external REST endpoint" (path-based /rest routing over the main HTTPS port — in which case the column header and prose should SAY so), or it is stale drift from before path-based routing.

Neither is a runtime bug — ports are computed by config.go, not this markdown — but this is the runbook the next slot creation reads, and the Ukraine row deliberately matched its (possibly wrong) siblings for consistency rather than forking the pattern.

Fix shape: settle what the REST column means, correct the prose formula to the canonical scheme (cite AGENTS.md), and re-derive all ten rows from the formula so the table is provably consistent. Small, mechanical once the REST-column meaning is ruled; suits the mechanic with an architect one-line ruling.

WHAT IS ACHIEVED: the slot-creation runbook's port documentation agrees with the code that actually allocates ports, and the next country's operator cannot be misled by a fossil formula.
<!-- SECTION:DESCRIPTION:END -->
