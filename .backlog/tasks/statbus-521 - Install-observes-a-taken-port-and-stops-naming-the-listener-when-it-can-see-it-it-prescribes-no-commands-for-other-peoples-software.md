---
id: STATBUS-521
title: >-
  Install observes a taken port and stops, naming the listener when it can see
  it; it prescribes no commands for other people's software
status: Done
assignee: []
created_date: 2026-10-20 19:41
updated_date: '2026-10-28T01:09:00Z'
labels:
  - install
  - operator
dependencies: []
priority: high
type: enhancement
ordinal: 447204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When a port StatBus needs is taken, install says which port, names the program holding it when it can see one, and stops without changing anything. We take responsibility for what is ours (StatBus needs this port) and hand the operator what they need to take responsibility for theirs.

### Zoom out
Owner, 2026-10-20: we do not know what runs on someone else's machine. A hardcoded guess (apache2/nginx/caddy) and a prescribed command (`sudo systemctl disable --now <name>`, `sudo kill $(sudo lsof ...)`) can take down a site the operator needs, or hit the wrong program. Install observes and stops; the operator decides.

### Zoom in
- **Today** (cli/cmd/install_ports.go): occupiedPortOwner tries bind, then ss, then a hardcoded systemd unit list (apache2, nginx, caddy), then `ss -ltnp`, then `sudo -n ss -ltnp`. portConflictGuidance chooses one of three remedies: systemctl disable, kill via lsof, or 'find the listener with ss'. The ownership-probe failure adds 'Docker service ownership could not be checked'. install.sh carries two allowlist regexes (around lines 970 and 1076) matching each shape exactly.
- **The new message, one shape:** 'Port <n> is in use by <program> (when ss names it; otherwise: another program). StatBus needs this port. Stop that program or move it to another port, then run the same install command again: <rerun>'. 'Your answers are saved.' stays where it applies today.
- **Kept:** naming the listener when `ss -ltnp` or `sudo -n ss -ltnp` shows it, as a plain observation (owner: yes). The safe-name filter (^[A-Za-z0-9_-]{1,64}$) stays, so an odd name becomes 'another program'.
- **Removed:** the hardcoded unit list, the systemctl-show LoadState probe, both prescribed commands, and the matching branches of both install.sh regexes.
- **Also decided here (STATBUS-393 AC3, owner 2026-10-20):** instead of a real-box partial-start scenario, a Go test feeds the service-state parser (currentServiceProblems / probeServiceStatuses, which read `docker compose ps -a --format json`) a real captured output with a stopped and a restarting service, so the parse is pinned against Docker's actual format.

### Closing review
- **Memory:** none. **Documentation:** the comment on the port check states the rule. **Cleanup:** remove dead remedy helpers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A taken port stops install with one message: the port, the listener's program name when ss shows it (else 'another program'), that StatBus needs the port, and the rerun command. No systemctl, kill or lsof command is printed, and nothing is changed
- [x] #2 The hardcoded apache2/nginx/caddy check and the LoadState probe are removed; the listener name comes only from ss output, filtered by the existing safe-name pattern
- [x] #3 install.sh's two allowlist regexes match exactly the new message shape (with and without 'Your answers are saved.'), and the existing allowlist tests (install_detection_test.go, install_failure_cause_test.go) assert the new shapes
- [x] #4 4-install-port-80-taken.sh asserts the outcome: install exited non-zero, no StatBus container exists, and the printed rerun command, run after Apache is stopped, completes the install. It no longer greps for a prescribed command
- [x] #5 A Go test feeds the service-state parser a real captured 'docker compose ps -a --format json' output with a stopped and a restarting service and asserts the parsed states (STATBUS-393 AC3 middle way)
- [x] #6 Go tests, golangci-lint, ./dev.sh test-harness and the install.sh tests pass, and CI passes
- [x] #7 The port check reads every port it checks, and the address each is bound to (HTTP, HTTPS, app, API, API admin, database local and TLS), from the generated .env (CADDY_HTTP_PORT, CADDY_HTTPS_PORT, the *_BIND_ADDRESS lines, CADDY_DB_PORT, CADDY_DB_TLS_PORT) instead of its own copy of the port plan; a test asserts that for each mode the checked list equals the ports the generated settings publish
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Added 2026-10-20 (owner)
- **HTTPS and both database ports are already checked** (selectedInstallPorts covers all seven per slot; standalone uses 80/443/5431/5432). But the check keeps its own hardcoded copy of the port plan (3000+offset*10, plus the standalone overrides). The new criterion makes it read the generated settings, so the check cannot drift from what the services bind.

## Evidence 2026-10-20 (commit 9ba8f4696, pushed to master)

- AC1/AC2: portConflictGuidance is one shape ('Port <n> is in use by <program>. StatBus needs this port. Stop that program or move it to another port.'); occupiedPortOwner = bind, ss -ltn confirm, ss -ltnp, sudo -n ss -ltnp. Hardcoded apache2/nginx/caddy list, LoadState probe, systemctl/kill/lsof remedies removed. The 'Docker service ownership could not be checked' variant is KEPT: it is an observation about our own check (install could not confirm the listener is not StatBus's own), not a prescription, and it changes what the refusal means.
- AC3: install.sh lines 970/977 (exit-78 bucket) and 1076 (INSTALL_CAUSE) match exactly the new shape, full-line anchored. TestExit78AllowlistMatchesRealGoSentences drives real Go sentences through install.sh's branch; TestInstallCauseAndFixMatchShellAllowlist greps the real ERE.
- AC5: cli/cmd/testdata/docker-compose-ps-stopped-restarting.json is a verbatim capture from a real Docker (Compose v5.6.0, throwaway project: 'true' exited, 'false' restart:always crash-looping); TestParseServiceStatusesRealDockerCapture asserts exited + restarting states and servicesNotRunning problems.
- AC7: config.PlannedHostPorts/PlannedHostPortsInDir (cli/internal/config/host_ports.go) derive the seven bindings from computeDerived, the same computation that writes .env; TestPlannedHostPortsMatchGeneratedEnv generates a real .env per mode (development/private/standalone) and asserts equality with the parsed *_BIND_ADDRESS and port keys. No step reorder (owner decision: check stays after Configuration).
- Red/green: tmp/521-red.log (failures on old code), tmp/521-green.log (all pass after).
- Also updated with rabbit's approval: fresh-installer-test.sh (admits new shape, rejects retired remedy shapes incl. the old systemctl line -> generic step line) and scenario 5 phase a (outcome assertions, no sudo command). Scenario 4 prints the operator-facing refusal line and rerun command.
- AC4: scenario 4 rewired to outcome checks; harness-tested (bash -n, fresh-installer-test locally, ./dev.sh test-harness); LXD fleet run not executed here.
- Checks: gofmt clean, golangci-lint 0 issues, go test ./cmd/ ./internal/config/ ok, ./dev.sh test-harness exit 0, bash -n install.sh ok, fresh-installer-test.sh all PASS locally.

### Review 2026-10-20 (rabbit)
- Diff 9ba8f4696 + 805c1b101 read. One refusal: `Port <n> is in use by <program|another program>. StatBus needs this port. Stop that program or move it to another port.`, then the saved-answers rerun line. The systemd unit list and the systemctl/kill/lsof remedies are gone. The ports come from `config.PlannedHostPortsInDir`, the computation that writes .env (AC7, option C).
- Scenario 4 prints the line the operator saw and the rerun command, then reruns. Scenario 5 phase a asserts install exits non-zero, names port 80's listener and starts no StatBus services. Phase c is untouched.
- Red `tmp/521-red.log`, green `tmp/521-green.log`. CI green on 882769b57 (Fast Tests, CodeQL, Images, Harness Selftest).
- Remaining: AC4 in the next candidate's LXD fleet.

AC4 real LXD evidence: rc.03 LXD Fork Fleet run 40608110641 comparison reports 4-install-port-80-taken PASS (rc=0, 216s). The scenario's non-zero refusal, absent StatBus containers and successful rerun after Apache stops all passed. The fleet's two unrelated fixture failures do not change this individual green result.
<!-- SECTION:NOTES:END -->
