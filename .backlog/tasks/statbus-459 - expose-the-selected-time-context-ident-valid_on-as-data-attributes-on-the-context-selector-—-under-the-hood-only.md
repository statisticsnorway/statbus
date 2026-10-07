---
id: STATBUS-459
title: >-
  expose the selected time context (ident + valid_on) as data attributes on the
  context selector — under the hood only
status: In Progress
assignee:
  - '@calf'
created_date: '2026-10-07 12:50'
updated_date: '2026-10-07 12:51'
labels:
  - app
  - devx
dependencies: []
priority: low
ordinal: 386204
---

## Why (owner decision 2026-10-07)

Answering "which time context is this box showing?" currently needs an authenticated
session and a database read: `time_context` returns `42501 permission denied` to anon,
and the only visible signal is the human text of the chip (`2023 (Data)`). That cost a
round trip during STATBUS-458.

Owner scope decision, explicitly: **under the hood only**. No visible text change, no
tooltip, no title attribute, no layout or styling change. The tooltip and the visible
"as of <date>" wording were considered and rejected.

## Change

`app/src/components/time-context-selector.tsx` — the trigger element that currently
renders the context chip (e.g. `2023 (Data)`) also carries:

```html
data-time-context-ident="<selectedTimeContext.ident>"
data-time-context-valid-on="<selectedTimeContext.valid_on as ISO date>"
```

- Derived from the **selected time context value the label already comes from**, in the
  same render, so a client-side context switch updates the attributes. Not from
  `window.__STATBUS_CONFIG__` (server-injected at boot, stale after a switch).
- Null-safe: with no selected context, both attributes are simply absent.

## Acceptance

- [ ] The chip element carries both attributes for the selected context, and only those
      two are added.
- [ ] Switching the context updates them without a reload.
- [ ] No visible, layout, style or behaviour change; no `title` attribute is introduced.
- [ ] A render test seeds a time context and asserts both attributes; a second case with
      no selected context asserts neither is present.
- [ ] `cd app && pnpm run lint && pnpm run tsc && pnpm run test` green.

## Out of scope (and must not be touched)

- The dashboard's estimated-vs-exact count behaviour and the `2023 (Data)` label/value
  question — that is STATBUS-458.
- Any new endpoint, any schema change, any change to how contexts are computed.

## Note for the reporter

Once this lands, the 458 investigation can read the exact context (`ident`, `valid_on`)
straight from the DOM in a logged-in browser, instead of asking for a database read.
