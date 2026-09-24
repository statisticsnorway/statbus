---
id: STATBUS-396
title: >-
  git errors carry git's own stderr, redacted
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 16:44'
labels:
  - cli
  - error-handling
  - security
dependencies: []
references:
  - next/git-stderr
priority: medium
type: task
ordinal: 86
---

## Description

Git-related failures should preserve git's own stderr so operators receive the
actual failure context, while secrets and sensitive values are redacted.

## 2026-09-24 status

Branch `next/git-stderr` is under review. Next step: complete review, merge the
redacted stderr handling, and verify representative git failure paths do not
leak sensitive values.
