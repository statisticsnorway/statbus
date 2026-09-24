---
id: STATBUS-396
title: 'Git failures show the operator git''s own error message, with secrets redacted'
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 14:53'
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

When a git command fails, the operator sees git's own error message, with
tokens and other secrets replaced by a redaction marker.

## Done when

- Representative git failures (auth, missing ref, network) show git's message.
- A failure with a credential in the URL shows the message with the credential
  redacted.

## 2026-09-24 status

Branch `next/git-stderr` is under review. Next step: complete review, merge the
redacted stderr handling, and verify representative git failure paths do not
leak sensitive values.
