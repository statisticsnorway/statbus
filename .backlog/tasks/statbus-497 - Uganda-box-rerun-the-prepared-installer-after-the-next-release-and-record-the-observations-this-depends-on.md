---
id: STATBUS-497
title: >-
  Uganda box: rerun the prepared installer after the next release and record the
  observations this depends on
status: In Progress
assignee: []
created_date: '2026-10-13 13:16'
updated_date: '2026-10-16 14:00'
labels:
  - install
  - uganda
  - release
dependencies: []
priority: high
type: task
ordinal: 423204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The Uganda installation becomes the real-box proof for three fixes that only a real box can confirm, so those fixes close on observation instead of on reasoning.

### Zoom out
Some acceptance criteria can only be met by watching the product on a real, unprepared machine: what a published instruction does in a real root login shell, what the home directory looks like after preparation, what an operator actually reads when Docker is missing. Uganda hit these problems first, and the owner will rerun the installer there after the next release. This ticket schedules that rerun and says exactly what to collect, so the dependent tickets each have a named source for their last criterion. It is a task, not a fix, so it stays open until the rerun is done.

### Zoom in
- **Origin, 2026-10-13:** filed on the owner's instruction so the Uganda rerun is tracked, not remembered.
- **What to collect on the rerun:**
  1. **STATBUS-492 criterion 1:** a transcript of the published preparation instruction running in a root login shell, showing the `HOME` in effect.
  2. **STATBUS-492 criterion 3:** an ownership inspection showing no root-owned file anywhere in the operator home after a fresh preparation.
  3. **STATBUS-487 criterion 5:** the install's operator output, verbatim, naming Docker and its remedy rather than the unmeasurable-disk sentence (only if Docker is unreachable on that box).
- **Where things stand:** STATBUS-487 and 492 are marked Done although those observation criteria are still unchecked; this ticket is where they will be satisfied. The release the rerun waits for is v2026.10.1 (stable, 2026-10-15) or later.
- **Related:** STATBUS-486 (removing the restore-time workaround) is part of the release path, not part of the rerun.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 STATBUS-492 criterion 1 is satisfied with a real transcript from the box: the preparation ran in a root login shell and the HOME in effect is recorded.
- [ ] #2 STATBUS-492 criterion 3 is satisfied with an ownership inspection from that box showing no root-owned file in the operator home.
- [ ] #3 STATBUS-487 criterion 5 is satisfied with the install output from that box, quoted verbatim, showing the Docker cause named with its remedy (or recorded as not applicable if Docker was reachable).
- [x] #4 Each dependent ticket names this ticket as the source of its observation.
- [x] #5 [Owner] Confirm v2026.10.1, or name a later release, as the release the Uganda rerun waits for, and record it in Implementation Notes. The confirmed release lets the rerun be scheduled; AC1-3 are filled from that run.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC4:** STATBUS-487 and STATBUS-492 each reference STATBUS-497 (checked 2026-10-15).
- **AC1-3:** open; they wait for the Uganda rerun.

### Release confirmed: v2026.10.2
The owner promoted v2026.10.2 on 2026-10-16. statbus.org/setup.sh and statbus.org/install.sh serve it, byte-identical to the tag.

### How to run it by hand and capture each criterion
From the release's own published instructions (ops/setup-ubuntu-lts.sh and install.sh headers at v2026.10.2):
1. **AC1, preparation.** `sudo -i` (a root login shell; plain sudo is refused). Print the home in effect with `echo "HOME=$HOME"`. Then `curl -fsSL https://statbus.org/setup.sh -o harden.sh && chmod +x harden.sh && ./harden.sh 2>&1 | tee /root/uganda-setup.log`. Keep the HOME line and the log.
2. **AC2, ownership.** After preparation: `find /home/statbus -xdev -user root`. Expected: no output.
3. **AC3, install.** As the statbus user: `curl -fsSL https://statbus.org/install.sh | bash 2>&1 | tee ~/uganda-install.log`. If Docker is unreachable, the output must name Docker and its remedy; otherwise AC3 is recorded as not applicable.
4. Paste the HOME line, the find output and the two logs back. The agent records them here and checks AC1-3.

### Also read after the install (feeds STATBUS-422 AC4)
- Open the box's login page and read the footer. It must say `Statbus version v2026.10.2`. A fresh install of a release containing 3df96b7bf is exactly what 422 AC4 asks to observe. Paste the footer line with the logs.
<!-- SECTION:NOTES:END -->
