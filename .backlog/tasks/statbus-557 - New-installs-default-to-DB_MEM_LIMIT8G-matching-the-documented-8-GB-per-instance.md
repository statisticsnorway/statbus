---
id: STATBUS-557
title: >-
  The installer sizes the database's memory from the host: most of RAM when
  standalone, a bounded share in development and cloud
status: To Do
assignee: []
created_date: '2026-11-01T15:00:00Z'
updated_date: '2026-11-01T15:26:00Z'
labels: []
dependencies: []
type: enhancement
ordinal: 480204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner, 2026-11-01. The goal: a standalone install uses most, but not all, of the host's memory for the database, leaving enough for the OS and the other containers so the box stays up. Development and cloud slots share a box with other things, so they get a bounded share; development may deliberately run small to catch memory blow-ups, at the cost of speed. The value adapts: the installer's Settings step measures the host's memory and derives DB_MEM_LIMIT each time it runs, so after a resize, re-running ./sb install adjusts it, and it reports what it detected and what it allocated. An explicit DB_MEM_LIMIT in .env.config stays the operator's override.
Today: cli/internal/config/config.go:504 writes DB_MEM_LIMIT=4G into .env.config once; nothing measures the host; postgres/docker-compose.yml falls back to 4G. Since STATBUS-555 (f4f6c98cb) the derived postgres settings actually reach the container, so this value now governs shared_buffers and work_mem. Docs: doc/CLOUD.md (8 GB per instance), doc/DEPLOYMENT.md (16 GB server minimum).
Open for design: the share per CADDY_DEPLOYMENT_MODE (standalone / private / development), the headroom kept for OS and other containers, how to tell an operator override from a previously derived value, and how macOS dev measures memory available to Docker rather than to the host.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ./sb install on a standalone host sets the database memory limit from the host's measured memory, keeping headroom, and prints the detected and allocated amounts
- [ ] #2 Development and cloud slots get a bounded share; development can be set lower on purpose
- [ ] #3 Re-running ./sb install after the host's memory changes re-derives the limit; an explicit operator value in .env.config is kept
- [ ] #4 A test covers the derivation for each mode and for a resize
<!-- AC:END -->
