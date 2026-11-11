---
id: STATBUS-621
title: A certificate of ability states what a person has done on the StatBus they use
status: To Do
assignee: []
created_date: '2026-11-11T13:03:00Z'
labels:
  - app
  - training
dependencies: []
priority: low
ordinal: 534204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A certificate that proves ability, not attendance: it states what this person has actually done on this StatBus (created an import job, imported units, reviewed units, and so on), drawn from the system's own records.

## Zoom out
2026-11-11: Erik Søberg made a course certificate generator, www.statbus.org/Documentation/course_certificate.html (repo statbus-web). After a short exam the user pastes an API key; the page decodes the key and prints its display_name with today's date. It proves the person holds a key on some StatBus, not what they did there. The name comes from the key's claims, fixed when the key was created; STATBUS-617 shows that name in the API key dialog and offers Recreate when the profile name has changed.

## Zoom in (owner's end game, to design together)
- The certificate lists the milestones the person reached on this machine, read from the database: e.g. created an import job, completed an import with N units, reviewed (approved or rejected) a job's rows, edited a unit, used a time frame.
- Issued by the StatBus instance itself (its domain and the dates), so it can be checked against that instance.
- Which milestones, how they are verified, and whether the instance signs the certificate are open questions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Agrees the milestones and how the certificate is issued and checked, after a walk-through. The answer is recorded in this ticket's notes and becomes the build plan.
<!-- AC:END -->
