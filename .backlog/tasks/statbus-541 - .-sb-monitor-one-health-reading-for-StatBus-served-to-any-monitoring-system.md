---
id: STATBUS-541
title: './sb monitor: one health reading for StatBus, served to any monitoring system'
status: In Progress
assignee: []
created_date: '2026-10-30T11:50:00Z'
updated_date: '2026-10-30T12:32:00Z'
labels:
  - monitoring
  - operations
dependencies: []
priority: medium
type: feature
ordinal: 467204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An NSO's monitoring knows whether StatBus itself is healthy, using one answer StatBus gives in a form any monitor can read, with nothing to build on their side.

### Zoom out
Monitoring systems connect to a host in two ways: a command run by an agent on the box (Zabbix agent, Nagios/Icinga plugins: exit code 0/1/2/3 plus a status line) or an HTTP URL they poll (Zabbix HTTP agent, Uptime Kuma, UptimeRobot). StatBus already judges its own health in the installer's final proof, ./sb ps, disk policy and the upgrader. Ready-made integration beats documentation: N NSOs writing their own checks gives N partial ones. The upgrader service already runs on every box under systemd with a periodic tick, and Caddy already serves files from ~/statbus/tmp (/upgrade-progress.log), including during maintenance. Owner decisions 2026-10-30: one final design (no staged versions), cached reading by default, /monitor public, no email for now.

### Zoom in
Field case: Uganda (statbus.ubos.org) runs Zabbix (agent 10050 from 10.10.10.253).
Design (approved):
1. Check engine: services (5 running, db healthy), api (PostgREST ready), site (SITE_DOMAIN answers over HTTPS; certificate days left), disk (diskpolicy), backups (age of newest in ~/statbus-backups), upgrader (unit active, no failed or parked upgrade), worker (failed tasks in the last hour; stuck). Fixed thresholds as commented constants. Status per check and overall: ok (exit 0), warning (1), critical (2), unknown (3), and upgrading (overall only, exit 1: a planned upgrade is visible but not an outage).
2. CLI: bare ./sb monitor prints help (what is checked, subcommands, one example per platform, and that text output plus exit codes is already a Nagios/Icinga plugin). ./sb monitor status [--live] [--format text|json]: text's first line is the Nagios-shaped summary (StatBus WARNING - disk 82% used), then one line per check; exit code is the worst status (0/1/2/3).
3. Cache by default: the upgrader runs the checks every 60 s and writes ~/statbus/tmp/monitor.json atomically with checked_at and version. status reads it; a reading older than 3 minutes is unknown. --live runs the checks now. No service running: status says so and runs live.
4. Public https://<site>/monitor: Caddy serves monitor.json from /statbus-tmp above the maintenance handler; 200 for ok/warning, 503 when a marker file says critical or unknown. Content has no secrets: status, time, version, fixed phrases with numbers; no paths, IPs, emails, user names or log text.
5. ./sb monitor template [zabbix|uptime]: bare lists the platforms. zabbix prints an importable template (items calling status --format json or polling /monitor, triggers on status and on a stale checked_at) and starts with a comment giving the one UserParameter line. uptime prints the URL and expected status for Uptime Kuma, UptimeRobot and similar.
6. During an upgrade the upgrader writes status upgrading into the reading, so pollers see a planned upgrade, not a failure.
Out of scope: Nagios template (the plugin contract is built in), Prometheus, email on change, IP allowlist.

### Closing review
- **Memory:** none. **Documentation:** ./sb monitor help text and the template headers are the documentation; one paragraph in the operator docs pointing at them. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cli tests pass for each check with OK, WARNING, CRITICAL fixtures (fake ps, HTTP, disk measurement, backup dir, unit state, worker tasks), and the overall status and exit code are the worst check
- [x] #2 ./sb monitor with no arguments prints the help; ./sb monitor status prints the Nagios-shaped first line and one line per check; --format json emits the pinned JSON shape
- [x] #3 The upgrader writes tmp/monitor.json every 60 s (atomic rename); status reads it by default, reports unknown when it is older than 3 minutes, and runs the checks live with --live or when no reading exists
- [ ] #4 Caddy serves /monitor publicly above the maintenance handler: 200 with the JSON for ok/warning/upgrading, 503 for critical/unknown; verified on a running instance, including during maintenance
- [x] #5 The public JSON contains no paths, addresses, emails, user names or log text (a test asserts the allowed fields and detail phrases)
- [ ] #6 ./sb monitor template zabbix prints a template that imports into Zabbix 7 without errors
- [x] #7 ./sb monitor template uptime prints the /monitor URL for this site and the expected HTTP status
- [ ] #8 During an upgrade the reading shows status upgrading (exit 1) and returns to ok afterwards, observed on a real upgrade run
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implementation (commits ea8242cbe engine+CLI, 19e3d3911 upgrader tick, 8b3f542c5 Caddy route, pushed to origin master).

Red/green (tmp/test-541-red.log, tmp/test-541-green.log):
- RED: go test ./internal/monitor failed with 'directory not found' (package did not exist).
- GREEN: go test ./... -count=1 passes every package except cmd/release TestRealRepo_NotShallow_STATBUS239, which fails only because this shared checkout is a shallow clone (git rev-parse --is-shallow-repository = true) and has an unrelated dirty untracked migration; it is environment-only and unrelated to this change. go vet ./... exits 0 (tmp/test-541-vet.log).

Checks: cli/internal/monitor with probe seams (compose ps, PostgREST /ready, site TLS answer + certificate days, diskpolicy, backups dir, systemctl is-active + upgrade table, worker tasks). Table tests cover OK/WARNING/CRITICAL/UNKNOWN fixtures per check, overall = worst, exit codes 0/1/2/3, Nagios-shaped text, pinned public JSON fields and fixed detail phrases.

Live on local dev stack: ./sb monitor status --live => exit 2 (StatBus CRITICAL - backups ...; services 2/5, API not ready, certificate 0 days, disk 46 GB free, worker 0/0), matching the actual local state (tmp/test-541-live.log, tmp/test-541-live.json). JSON contained no paths/addresses/user names.

Cache: tmp/monitor.json + monitor.status written by atomic temp+rename; monitor.critical exists only for critical/unknown. Upgrader now has a 60 s ticker, a single-flight non-blocking refresh goroutine, and writes status upgrading (exit 1) during executeUpgrade, then a fresh normal reading on return. Tests cover atomic write, marker transitions, stale >3 min -> unknown, no cache -> live, upgrading reading and late-normal-overwrite prevention.

Caddy: /monitor added above @maintenance in private, standalone and development templates; maintenance matcher excludes it; marker matched root-relative as 'file monitor.critical'. Rendered all three templates and 'caddy adapt' exited 0 in the running statbus-local-proxy container. A scratch Caddy container serving the same route answered 200 with the JSON, 503 with the same body when monitor.critical existed, and 200 again after it was removed (tmp/monitor-caddy/). AC4 live-instance verification is left to the coordinator.

Zabbix: template parses as YAML (gopkg.in/yaml.v3 test pins master item statbus.monitor + 9 dependent items + 4 triggers including checked_at >300 s); CLI output also parses with PyYAML. It has NOT been imported into a real Zabbix 7, so AC6 stays unchecked per instructions. AC8 (real upgrade) left to the coordinator.

CI: exact SHA 8b3f542c556d4ebb990709e5f130146d138ba560 (runs listed in follow-up note after completion).

CI results (all on final SHA 44940b9cf0a5f543f4fdd3415df5ed7df40ba85f, which contains every STATBUS-541 commit):
- Go Test 41054480374 success; app build & lint 41054480292 success; Harness Selftest 41054480529 success; Images 41054480283 success; CodeQL 41054480933 success; Notify cloud services 41054480269 success.
- The first run on 44940b9cf was cancelled by a newer master commit from another agent (6693a33, STATBUS-542); rerun via 'gh run rerun' completed green on the exact SHA.

Intermediate red runs diagnosed:
- 8b3f542c5 Go Test 41053114528 failed: (a) golangci-lint errcheck on explicit fmt writes in cmd/monitor.go and os.Remove in cache.go; (b) TestAstraClosureManifestRetryMustRetainConvergence and TestNewCandidateInheritsBoxConvergenceAfterManifestRetry were perturbed by the post-upgrade monitor refresh goroutine probing the synthetic Docker transcript. Fixed by checking outputs (0c511a012/44940b9cf) and by gating the immediate post-upgrade refresh on runningAsService (0c511a012); one-shot callers have no ticker and must not leave a probe goroutine behind. Both tests then passed locally and in the final Go Test.

Final local run: go test ./... -count=1 (tmp/test-541-green.log) passes every package except cmd/release TestRealRepo_NotShallow_STATBUS239, which fails only because this shared checkout is shallow (CI's full clone passes it: final Go Test green). go vet ./... and golangci-lint run ./... are clean.

Commits: ea8242cbe (engine+CLI), 19e3d3911 (upgrader tick), 8b3f542c5 (Caddy route), 0c511a012 (one-shot refresh gate), 44940b9cf (lint fixes).
<!-- SECTION:NOTES:END -->
