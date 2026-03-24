# Pipeline Progress Notifications

Real-time progress tracking for the derive pipeline, from database to UI.

## First Principles

### The structured concurrency tree IS the source of truth

The worker uses structured concurrency. Each `collect_changes` pre-spawns an entire task tree:

```
collect_changes                          depth 0, serial children
├── derive_units_phase                   depth 1, serial children
│   ├── derive_statistical_unit          depth 2, concurrent children
│   │   └── statistical_unit_refresh_batch × N    depth 3, leaves
│   └── statistical_unit_flush_staging   depth 2, leaf
└── derive_reports_phase                 depth 1, serial children
    ├── derive_statistical_history        depth 2, concurrent children
    │   └── derive_statistical_history_period × N  depth 3, leaves
    ├── statistical_history_reduce        depth 2, leaf
    ├── derive_statistical_unit_facet     depth 2, concurrent children
    │   └── derive_statistical_unit_facet_partition × N  depth 3, leaves
    ├── statistical_unit_facet_reduce     depth 2, leaf
    ├── derive_statistical_history_facet  depth 2, concurrent children
    │   └── derive_statistical_history_facet_period × N  depth 3, leaves
    └── statistical_history_facet_reduce  depth 2, leaf
```

Task states: `pending` → `processing` → `waiting` → `completed` (or `failed`).

- **pending**: Created but not yet picked up
- **processing**: Handler executing
- **waiting**: Handler finished, children running
- **completed**: Task and all descendants done

### The UI shows two phases

| UI Phase | "Statistical Units" | "Reports" |
|----------|-------------------|-----------|
| Tree root | `derive_units_phase` | `derive_reports_phase` |
| Includes | collect_changes (prequel) | facets, history, reduce steps |
| Lifecycle | active → complete → hidden | pending → active → complete → hidden |

### Four design principles

**1. Phase activity comes from the phase root's state — not child enumeration.**

Don't scan for specific child commands. The phase root (`derive_units_phase`, `derive_reports_phase`) encodes the entire phase's lifecycle via its state. Adding new pipeline steps never requires updating the progress function.

**2. Progress is derived by walking the tree (parent_id relationships).**

- **Step** = deepest `processing`/`waiting` task in the phase subtree (max 3 levels)
- **Total/completed** = children of the deepest active concurrent parent
- **Effective counts** = `info` field on the depth-2 child that computed them (persists after completion)

Only three structural command names are needed: `collect_changes`, `derive_units_phase`, `derive_reports_phase`. Everything else is found by `parent_id`.

**3. Show both what's running AND what's pending.**

A pending phase is queued work — not idle. The UI shows it with effective counts and "Pending..." so the user knows what's coming. Don't send idle signals for pending phases.

**4. Prefer the running pipeline over queued ones.**

Multiple `collect_changes` can exist (one running, one pending). Always report progress for the running one (`processing`/`waiting` first, then `pending` by `id DESC`).

## Pipeline lifecycle (state-by-state)

Each state shows what the database reports and what the UI displays.

### 1. `collect_changes` pending (queued, no children)

```
collect_changes: pending
```

| | Units | Reports |
|-|-------|---------|
| active | true (pending collect_changes = queued units work) | — (doesn't exist) |
| step | `collect_changes` | — |
| UI shows | "Recording changes" | nothing |

### 2. `collect_changes` processing (handler spawning tree)

```
collect_changes: processing → spawns entire tree → transitions to waiting
```

| | Units | Reports |
|-|-------|---------|
| active | true | — (tree being spawned, not committed yet) |
| step | `collect_changes` | — |
| UI shows | "Recording changes" | nothing |

### 3. Tree spawned, `derive_units_phase` pending

```
collect_changes: waiting
├── derive_units_phase: pending
└── derive_reports_phase: pending
```

| | Units | Reports |
|-|-------|---------|
| active | true (phase root pending = not terminal) | pending: true |
| step | null (brief — serial fiber picks up immediately) | null |
| UI shows | "Starting..." | "Pending..." with effective counts |

### 4. `derive_units_phase` processing/waiting, batches running

```
collect_changes: waiting
├── derive_units_phase: waiting
│   ├── derive_statistical_unit: waiting (child_mode=concurrent)
│   │   ├── batch_1: completed
│   │   ├── batch_2: processing
│   │   └── batch_3: pending
│   └── statistical_unit_flush_staging: pending
└── derive_reports_phase: pending
```

| | Units | Reports |
|-|-------|---------|
| active | true | pending: true |
| step | `statistical_unit_refresh_batch` (deepest processing task) | null |
| total | 3 (children of concurrent parent) | 0 |
| completed | 1 | 0 |
| UI shows | "statistical_unit_refresh_batch 33%" | "Pending..." with counts |

### 5. Batches done, flush running

```
├── derive_units_phase: waiting
│   ├── derive_statistical_unit: completed
│   └── statistical_unit_flush_staging: processing
└── derive_reports_phase: pending
```

| | Units | Reports |
|-|-------|---------|
| active | true | pending: true |
| step | `statistical_unit_flush_staging` | null |
| total | 0 (no concurrent parent active) | 0 |
| UI shows | "Flushing staging data, Running..." | "Pending..." with counts |
| effective counts | from `derive_statistical_unit.info` (persists after completion) | same |

### 6. Units done, reports pending (gap bridged)

```
├── derive_units_phase: completed
└── derive_reports_phase: pending
```

| | Units | Reports |
|-|-------|---------|
| active | false | **true** (pending + units completed = gap bridge) |
| step | — | null |
| UI shows | hidden | "Starting..." |

The gap bridge: `derive_reports_phase` becomes active when `pending` AND `derive_units_phase` is `completed`. This prevents a "both idle" flash during the phase transition.

### 7. Reports running

```
├── derive_units_phase: completed
└── derive_reports_phase: waiting
    ├── derive_statistical_history: waiting (concurrent)
    │   ├── period_1: completed
    │   ├── period_2: processing
    │   └── ...
    ├── statistical_history_reduce: pending
    └── ...
```

| | Units | Reports |
|-|-------|---------|
| active | false | true |
| step | — | `derive_statistical_history_period` |
| total | — | N (period children) |
| UI shows | hidden | "derive_statistical_history_period 45%" |

### 8. All done

Both phases hidden. Idle signals sent.

## Implementation

### Three functions, one logic

All three implement identical phase detection:

| Function | Purpose | Called from |
|----------|---------|------------|
| `worker.notify_task_progress()` | Real-time SSE via `pg_notify` | `process_tasks` after each analytics task |
| `public.is_deriving_statistical_units()` | RPC for initial page load | Frontend on SSE connect |
| `public.is_deriving_reports()` | RPC for initial page load | Frontend on SSE connect |

### Algorithm (shared by all three)

```
1. Find pipeline root: most recent collect_changes NOT completed/failed
   - Prefer processing/waiting over pending (don't shadow running pipeline)

2. Find phase roots: direct children of pipeline root
   - derive_units_phase (by parent_id + command)
   - derive_reports_phase (by parent_id + command)

3. Determine phase activity:
   - Units active = pipeline is pending/processing
                    OR units phase root is NOT terminal (completed/failed)
   - Reports active = reports phase root is processing/waiting
                      OR (reports pending AND units completed) ← gap bridge

4. For each active/pending phase:
   a. Step: deepest processing/waiting task in subtree
      (check 3 levels: phase root, its children, its grandchildren via parent_id)
   b. Progress: find deepest concurrent parent (child_mode='concurrent')
      in processing/waiting state → count its children
   c. Effective counts: info field on depth-2 child with
      'effective_legal_unit_count' key (no state filter — persists after completion)

5. Idle signals: only send is_deriving_X: false when phase is
   truly done (completed/failed) or doesn't exist — NOT when pending
```

### Notification delivery mechanism

`pg_notify` is **transactional** — notifications deliver only on COMMIT. The `process_tasks` loop provides three commit points:

```
1. before_procedure + COMMIT  ← notification delivered before handler starts
2. handler executes
3. state update + COMMIT      ← handler result committed
4. parent completion + COMMIT
5. notify_task_progress + COMMIT  ← progress update delivered
```

`derive_units_phase` and `derive_reports_phase` have `before_procedure = 'worker.notify_task_progress'` in `command_registry`. This sends progress as soon as the phase starts processing (commit #1), not after the handler finishes (commit #5).

### Frontend data flow

```
Database                    Backend                 Frontend
────────                    ───────                 ────────
pg_notify('worker_status')  →  SSE stream  →  workerStatusAtom
                                              ├── isDerivingUnits (boolean)
                                              ├── isDerivingReports (boolean)
                                              ├── derivingUnits (PhaseStatus)
                                              └── derivingReports (PhaseStatus)

PhaseStatus = {
  active: boolean,     // phase root is processing/waiting
  pending: boolean,    // phase root is pending (queued)
  step: string | null, // current command name
  total: number,       // batch children count
  completed: number,   // completed batch children
  effective_*_count    // affected unit counts
}
```

The `isDerivingX` boolean controls the NavLink activity indicator. It's true when `active || pending`. The popover shows different content based on `active` vs `pending`:

- **active**: Progress bar with step name and batch counts
- **pending**: "Pending..." with effective counts (sets expectations)

### Key files

| File | Role |
|------|------|
| `worker.notify_task_progress()` | Sends real-time progress via pg_notify |
| `public.is_deriving_statistical_units()` | RPC for initial page load |
| `public.is_deriving_reports()` | RPC for initial page load |
| `worker.command_registry` | `before_procedure` for phase commands |
| `app/src/atoms/worker_status.ts` | Frontend state atoms (PhaseStatus, SSE handler) |
| `app/src/components/navbar.tsx` | Progress UI (NavLink, PhaseProgressPopover) |
| `app/src/app/api/sse/worker_status/route.ts` | SSE endpoint |
