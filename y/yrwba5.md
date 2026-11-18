---
id: "yrwba5"
title: >-
  Import definitions derive a target value from source columns with an
  expression, so an office can map a register's flags to StatBus codes without a
  custom loader
state: "todo"
assignee: []
labels:
  - import
group: ""
rank: "00000000057l"
dependencies:
  - STATBUS-546
priority: medium
type: "feature"
origin: "backlog:STATBUS-601"
aliases: ["STATBUS-601"]
backlog_type: "feature"
created: "2026-11-09T21:24:00Z"
---

## Goal

### North Star

An office maps a register file to StatBus in the import definition alone, including values the file expresses differently, such as yes/no flags that together mean a status.

### Zoom out

A mapping today copies one source column, sets a fixed value, or uses now/default. A register that encodes status as several flags (BRREG: konkurs, underAvvikling, underTvangsavviklingEllerTvangsopplosning, with dates) needs code outside StatBus to produce a status code. Norway uses that bridge (STATBUS-600, owner decision 2026-11-09, option A) until this exists.

### Zoom in

Owner, 2026-11-09: the design must be flexible, close to an expression builder over the source columns, and likely comes after the import definition editor (STATBUS-546). Open design questions for the owner: the expression language and how it is kept safe (no arbitrary SQL from uploads), how an expression is edited and validated in the editor, whether status needs more codes than Active and Passive, and how the owner's business-activity status design fits. Not started; to be discussed before any code.

## Depends on
- e334k3

## Acceptance
- [ ] #1 [Owner] The expression model (what an expression can reference and compute, and how it stays safe) is decided and recorded with its consequence
- [ ] #2 An import definition can derive a target column from source columns by an expression, edited and validated in the definition editor
- [ ] #3 BRREG's status flags map to StatBus status codes through a definition expression, and STATBUS-600's loader bridge is removed
