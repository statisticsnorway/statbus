---
id: STATBUS-557
title: >-
  New installs default to DB_MEM_LIMIT=8G, matching the documented 8 GB per
  instance
status: To Do
assignee: []
created_date: '2026-11-01T15:00:00Z'
updated_date: '2026-11-01T15:01:00Z'
labels: []
dependencies: []
type: enhancement
ordinal: 480204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
doc/CLOUD.md recommends 8 GB per instance and doc/DEPLOYMENT.md asks for 16 GB of server RAM, but cli/internal/config/config.go:504 defaults DB_MEM_LIMIT to 4G, and postgres/docker-compose.yml falls back to 4G (mem_limit, shm_size, mem_reservation). Owner, 2026-11-01: default to 8G. Development may set less to save RAM, accepting slower runs; running small sometimes is useful to catch memory blow-ups. gen() writes the default into .env.config only on the first generate, so existing boxes keep their value and only new installs change. Since STATBUS-555 (f4f6c98cb) the derived postgres memory settings actually reach the container, so this limit now governs shared_buffers and work_mem.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fresh ./sb config generate writes DB_MEM_LIMIT=8G into .env.config (test extends config_test.go)
- [ ] #2 An existing .env.config DB_MEM_LIMIT is left unchanged by config generate
- [ ] #3 postgres/docker-compose.yml has no 4G memory fallback that disagrees with the generated value
<!-- AC:END -->
