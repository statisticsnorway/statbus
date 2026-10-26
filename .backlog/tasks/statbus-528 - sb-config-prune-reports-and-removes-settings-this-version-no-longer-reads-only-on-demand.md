---
id: STATBUS-528
title: >-
  sb config prune reports and removes settings this version no longer reads,
  only on demand
status: To Do
assignee: []
created_date: '2026-10-26 15:09'
updated_date: '2026-10-26 15:10'
labels:
  - cli
  - config
  - cleanup
dependencies: []
priority: medium
type: enhancement
ordinal: 454204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An operator can ask `sb` which entries in `.env.config` and `.env.credentials` this version no longer reads, and can remove them deliberately. Install and config generation never remove them automatically.

### Zoom out
Long-lived installations accumulate settings from older versions. Most are harmless, but they make it hard to see what the box actually uses. A cleanup command reduces that clutter without turning harmless old settings into install failures. Secrets remain secret: a report may name a credential key, never print its value.

This came from STATBUS-431's discussion of a vague "complete and valid .env.config" requirement. That requirement was dropped: an existing installation is not re-questioned, and unknown old keys are not rejected. This ticket is only an on-demand inspection and cleanup tool.

### Zoom in
- Add `sb config prune`. With no flags it is read-only: it lists entries in `.env.config` and `.env.credentials` that the current build does not read, and says that nothing was changed. It does not print credential values.
- `sb config prune --apply` removes those entries after writing a timestamped backup beside each changed file, preserving file permissions. It prints the backup paths and the removed key names, never secret values. No other entries are rewritten.
- The comparison uses one registry of keys the current build reads, shared with the configuration code rather than a second hand-maintained list where practical. The wording is "not read by this version", not "invalid": an old key may be meaningful to an older version after a rollback.
- `.env` is generated output and is never pruned. `./sb config generate` remains the way to regenerate it.
- Neither `./sb install` nor `./sb config generate` invokes pruning. Old boxes change only when the operator asks.
- `doc/DEPLOYMENT.md` gets a short section with the read-only and apply forms.

### Closing review
- **Memory:** none needed; the behaviour lives in command help and the deployment guide.
- **Documentation:** command help plus `doc/DEPLOYMENT.md`.
- **Cleanup:** no automatic cleanup. Backups are retained for the operator.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `sb config prune` is read-only and lists keys not read by this version in both .env.config and .env.credentials; credential values never appear in output or logs; a test proves both
- [ ] #2 `sb config prune --apply` removes only the reported keys, writes a timestamped backup for each changed file, preserves permissions and prints backup paths; without --apply the files are byte-identical
- [ ] #3 Keys still read by the current build are kept, including optional settings and empty placeholders with a documented meaning; unit tests cover current keys, keys not read by this version, and secret values staying out of output
- [ ] #4 The generated .env is never edited, and neither install nor config generate invokes pruning; a code review confirms there is no automatic caller
- [ ] #5 Command help and doc/DEPLOYMENT.md explain read-only versus --apply, the backup, and that 'not read by this version' does not mean invalid on an older version
<!-- AC:END -->
