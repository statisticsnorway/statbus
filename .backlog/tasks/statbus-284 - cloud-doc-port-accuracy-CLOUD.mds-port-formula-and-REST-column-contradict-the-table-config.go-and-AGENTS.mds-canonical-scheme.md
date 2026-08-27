---
id: STATBUS-284
title: >-
  cloud-doc-port-accuracy: CLOUD.md's port formula and REST column contradict
  the table, config.go, and AGENTS.md's canonical scheme
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-27 17:02'
updated_date: '2026-08-27 19:46'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-27 19:40
---
**RULING: the REST column means the INTERNAL PostgREST port, at offset +3.**

The table is titled *Port Allocation* and its job is to record which host ports each slot occupies on a multi-tenant box. Under that purpose the answer is forced:

- **As the internal port (+3)** the column carries information — a distinct port allocated to a real service, which is what an allocation table is for.
- **As the external endpoint** it is not a port at all. External REST is a *path* (`https://<slot>.statbus.org/rest`) served over the main HTTPS port. Writing that as a port number produces a column that duplicates HTTPS and implies a separate external REST port exists. It does not.

So: **REST = 3000 + (OFFSET × 10) + 3.** The external access path belongs in prose beneath the table, not in a port column.

Authority: `cli/internal/config/config.go:519` (`postgrestPort := portOffset + 3`), matching AGENTS.md's scheme (offset 1 → 3013 rest).

## STOP — the formula block has TWO errors, and re-deriving all ten rows from it as written would CORRUPT currently-correct rows

The brief says the mechanic re-derives every row from the corrected formula. **The formula block must be fully corrected first, because one of its lines is wrong in a direction the table is right about.** The two defects are not the same shape:

| Line | Formula says | Table says | Which is wrong |
|---|---|---|---|
| `DB_PORT` | `+ 14` → 3024 for offset 1 | **3014** | **the FORMULA** — table is correct, leave those values alone |
| `REST_PORT` | `+ 1` → 3011 | 3011 | **BOTH** — every value in the column changes |

Re-deriving DB from the written formula would turn a correct `3014` into `3024` across all ten rows. **Correct the block first, then derive.**

## The corrected block, from `config.go:516-525` verbatim

```
HTTP       = 3000 + (OFFSET * 10)
HTTPS      = 3000 + (OFFSET * 10) + 1
APP        = 3000 + (OFFSET * 10) + 2
REST       = 3000 + (OFFSET * 10) + 3
DB         = 3000 + (OFFSET * 10) + 4
DB_TLS     = 3000 + (OFFSET * 10) + 5
REST_ADMIN = 3000 + (OFFSET * 10) + 6
```

The doc currently documents four of the seven. Adding APP, DB_TLS and REST_ADMIN is optional for this ticket, but if the table exists to prevent port collisions on a shared host then **omitting three of the seven ports each slot occupies is a larger defect than the one filed** — a slot allocated from this table can still collide on +2, +5 or +6. Scope call for the foreman; the four-column fix is correct on its own.

**Expected REST column after the fix: 3013, 3023, 3033, 3043, 3053, 3063, 3073, 3083, … (OFFSET × 10 + 3003).** Every DB value stays exactly as it is.

One caveat to carry: `config.go` overrides http/https/db in `standalone` mode. This table documents niue, which is `private`, so the formula applies as written — but it must not be copied into a standalone-box doc unqualified.
---
<!-- COMMENTS:END -->
