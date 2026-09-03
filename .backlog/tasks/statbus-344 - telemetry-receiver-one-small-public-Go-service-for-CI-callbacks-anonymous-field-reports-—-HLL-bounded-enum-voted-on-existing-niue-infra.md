---
id: STATBUS-344
title: >-
  telemetry-receiver: one small public Go service for CI callbacks + anonymous
  field reports — HLL-bounded, enum-voted, on existing niue infra
status: To Do
assignee: []
created_date: '2026-09-02 13:14'
updated_date: '2026-09-03 12:54'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 337000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING'S DIRECTION 2026-09-02 (supersedes and absorbs STATBUS-340 phone-home and STATBUS-343 ci-verdict-ledger — the 'underreach': one small specialized mechanism covering BOTH uses instead of contorting git refs, which structurally cannot take anonymous writes).

THE THING: a minimal Go web receiver (stdlib HTTP), publicly served via the EXISTING niue host Caddy (statbus_web already serves www.statbus.org there — one more SNI hostname/path + a systemd user unit in the established slot pattern; zero new infrastructure).

Faces:
- POST /ci — GitHub workflow_run webhook, HMAC-verified. Records {sha, workflow, conclusion, run_id, finished_at}.
- POST /report — ANONYMOUS box telemetry, no pre-registration: {version, channel, mode} + feature-usage votes from a FIXED ENUM baked into the binary (vote only for known things; unknown keys dropped at the door).
- GET — memory-speed queries: current verdict per sha+workflow; version/channel histogram (the 340 field directory, feeding the 339 fan); feature-usage estimates (what is used, what never).

GUARDRAILS (the design center): HLL for distinct-voter counts — ~KBs per counter at any scale, abuse-bounded (one IP moves an estimate once; botnets inflate linearly in distinct IPs only) and one-way (no IP is ever recoverable — the sovereignty/privacy answer: we structurally cannot know WHO, only HOW MANY). Finite votes per IP per window (LRU of (ip-hash,key)); per-IP token bucket; ~1KB payload cap; write-only-on-change; nothing received is ever reflected/served back verbatim; hourly state snapshot to one file, restart-cheap.

BOUNDARY: the release preflight's AUTHORITY stays GitHub — the receiver is a cache/telemetry plane; a lagging or compromised receiver must never green-light a cut. Boxes' opt-in stays a visible .env.config line (entry-way discipline); flag off = today's behavior exactly.

Deliverable this ticket: architect's full design (endpoint contract, state layout, HLL parameters, Caddy/unit wiring on niue, failure modes, what the preflight/watchers read and when they fall back to REST) for the King's ruling; build after the current release settles.

## Architect's design, 2026-09-02

The complete ruled design is appended to this ticket in numbered comments so it remains readable through one `backlog task view STATBUS-344` call. The design selects `https://telemetry.statbus.org/v1/`, a single statically linked Go process under the existing `statbus_web` account, and GitHub REST as the only release gate authority.

An expanded working mirror is at `tmp/statbus-344-telemetry-receiver-design.md`; the ticket and its binding addendum are authoritative if wording differs. A separate Backlog document was created before the King's second amendment and is obsolete: `designs/statbus-344-telemetry-receiver/doc-036 - STATBUS-344-telemetry-receiver-design.md`. The foreman may delete that document after confirming this ticket.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: Jcode architect
created: 2026-09-02 13:39
---
## Design 1/10: ruling, boundaries, and repo evidence

Build one public, dependency-free Go HTTP service with two write faces and three read faces. It is a cache and aggregate telemetry plane, not a source of truth. All routes are under `/v1`; unknown routes return `404`, wrong methods `405` with `Allow`, and successful JSON GETs use `application/json`, `Cache-Control: no-store`, and a generated request ID. POST responses have no body. Errors are short fixed phrases selected by server code, never decoder errors or received text.

Recommended origin: `https://telemetry.statbus.org`. A separate hostname gives an explicit privacy boundary, no www cookies, separate Caddy limits/log policy, and freedom to move the process without changing `/v1`. A path under www is technically possible but unnecessarily mixes a machine endpoint with the public site.

Repo evidence grounding the design:
* `doc/CLOUD.md` describes niue's one-public-IP SNI arrangement, per-user isolation, `statbus_web`, the host Caddy file at `/etc/caddy/Caddyfile`, explicit www/log blocks, and slot port allocation. This service follows that arrangement but is host-shared, not a country slot.
* `ops/statbus-upgrade.service` is the relevant user-systemd precedent.
* `cli/internal/config/config.go` contains the `.env.config` entry-way header and the visible upgrade configuration block.
* `cli/internal/upgrade/service.go` has startup discover/execute at about lines 2728-2741 and the six-hour tick tail at about 2776-2809; `cli/internal/upgrade/unit_floor.go` owns the six-hour default.
* `cli/internal/release/workflow_check.go` implements GitHub REST any-success semantics and the exercised-SHA marker required by workflow-run-triggered checks. `.github/workflows/release.yaml` contains the present preflight/release steps.
* Current enums are `local|stable|prerelease` in `cli/internal/config/upgrade_channel.go`, `development|private|standalone` in config validation, and import modes in `app/src/lib/database.types.ts`.

I attempted the permitted read-only check `ssh statbus_web@niue.statbus.org`; the key was rejected with `Permission denied (publickey)`. Deployment details below therefore use the documented CLOUD pattern and identify the one host-side confirmation required before landing.
---

author: Jcode architect
created: 2026-09-02 13:39
---
## Design 2/10: `POST /v1/ci`

Purpose: consume GitHub `workflow_run` webhooks and maintain a fast verdict cache.

Required headers: `Content-Type: application/json`, `X-GitHub-Event`, `X-GitHub-Delivery`, and `X-Hub-Signature-256: sha256=<64 lowercase hex>`. Read at most 256 KiB with `http.MaxBytesReader`; this face cannot honestly use the 1 KiB report cap because GitHub owns the event envelope. Compute HMAC-SHA256 over the exact raw body with the current webhook secret and compare in constant time before JSON decoding. During rotation, accept current or previous secret. Do not support SHA-1.

Only `X-GitHub-Event: workflow_run` mutates state. Other correctly signed events return `204`. Decode with unknown fields allowed because GitHub evolves payloads, but require this subset:
```json
{"action":"completed","repository":{"full_name":"statisticsnorway/statbus"},"workflow_run":{"id":123456,"workflow_id":987,"name":"Fast tests","head_sha":"40 lowercase hex","status":"completed","conclusion":"success","run_started_at":"RFC3339","updated_at":"RFC3339","html_url":"https://github.com/..."}}
```
Repository must equal the configured repository. SHA, IDs, configured workflow identity, timestamps, action, status, and a GitHub conclusion must validate. Store no event body, actor, branch, URL, or repository text. Map the configured workflow ID/name to a small canonical workflow key. For workflow-run-triggered checks, extract and validate the existing exercised-SHA marker using the same rules as `workflow_check.go`; key the verdict by the exercised commit, not merely the workflow wrapper's `head_sha`.

Reducer: per `(sha, workflow)`, remember `success_seen`, latest terminal conclusion, latest run ID, completion time, and update time. Match existing release semantics: any qualifying successful run makes the cached verdict `success`; later redelivery of an older failure cannot downgrade it. Until success, the newest terminal run by `(updated_at, run_id)` is current. A newer success updates metadata but not meaning.

Replay/redelivery: keep a 20,000-entry delivery-ID LRU for 7 days to make exact redeliveries cheap, but correctness does not depend on it. The verdict reducer is idempotent and monotonic. GitHub does not automatically redeliver failed deliveries; an administrator can manually redeliver, commonly with the same delivery ID. Therefore clients must tolerate a missed event and use REST fallback.

Responses: `204` accepted, duplicate, irrelevant action, or irrelevant signed event; `400` malformed required data; `401` missing/bad signature; `403` wrong repository; `413` oversized; `415` wrong media type; `429` rate limited; `500` only unexpected internal failure. No response echoes a delivery ID, SHA, workflow, or body bytes.
---

author: Jcode architect
created: 2026-09-02 13:39
---
## Design 3/10: `POST /v1/report`

Purpose: accept explicitly opted-in, anonymous, coarse installation reports. Exact v1 request:
```json
{
  "schema":"statbus.report/v1",
  "feature_schema":"2026.09",
  "version":"v2026.09.0",
  "channel":"stable",
  "mode":"private",
  "features":["import.legal_unit","reports.statistical_units"]
}
```
Use `http.MaxBytesReader` with an exact 1024-byte body limit. Require JSON object, UTF-8, `application/json`, one value only, and no unknown top-level fields. Bounds: schema <=32 bytes and exact; feature schema `YYYY.MM`; version 1-48 ASCII characters and strict StatBus release/candidate grammar; at most 16 unique feature keys; each key <=64 ASCII characters. Channel is exactly `local|stable|prerelease`; mode exactly `development|private|standalone`.

Initial `2026.09` feature enum:
* `import.legal_unit`
* `import.establishment_formal`
* `import.establishment_informal`
* `import.generic_unit`
* `import.legal_relationship`
* `reports.statistical_units`

Enums version with the product, not with whatever receiver happens to be newest. Keep manifests in one shared Go source/package in this repository. Both the reporter and receiver compile them. A release family `2026.09` sends only its `2026.09` keys. The receiver build carries an accept-list for the current and previous 11 feature schemas. The release process deploys a receiver that knows a candidate schema before that candidate can report. For an unknown feature schema, accept and count the base version/channel/mode dimensions but drop all feature votes. For a known schema, silently drop unknown feature keys at the door. Never create a map key from received feature text. This gives forward-safe delivery without unbounded cardinality.

Each valid request adds one monthly pseudonymous voter to HLL counters for total, version, channel, mode, their useful combinations, and each known feature present. Features are coarse booleans only. The client computes them from known local state and sends no counts, names, identifiers, domains, users, countries, data values, or free text.

Responses: `204` whether HLL registers changed, the daily finite-vote LRU suppressed the vote, or unknown features were dropped. `400` malformed base fields; `413` oversized; `415` wrong media type; `429` rate limit. Fixed empty responses prevent probing the enum or reflecting bytes. `TELEMETRY_REPORTING=false` means no probes, no DNS lookup, and no network request.
---

author: Jcode architect
created: 2026-09-02 13:39
---
## Design 4/10: read faces

### `GET /v1/ci/verdict?sha=<40hex>&workflow=<canonical>`
`200`:
```json
{"api":"v1","sha":"...","workflow":"fast-tests","verdict":"success","success_seen":true,"run_id":123456,"finished_at":"2026-09-02T12:00:00Z","observed_at":"2026-09-02T12:00:02Z","expires_at":"2026-12-31T12:00:02Z"}
```
Verdict is `success|failure|cancelled|timed_out|action_required|neutral|skipped|stale`; normalize GitHub's terminal set. `404` means no retained observation, with a fixed `{"api":"v1","error":"not_found"}`. Invalid parameters are `400`. A configured `workflow=all-release` form may return the finite required-workflow catalog and each cached verdict, but it must not invent an aggregate green if any item is absent.

### `GET /v1/report/histogram?month=2026-09&group=version,channel,mode`
Allow current month and previous two completed/current monthly epochs only. `group` is an allow-listed choice, not arbitrary columns: `version`, `channel`, `mode`, `version,channel`, or `version,channel,mode`. `200`:
```json
{"api":"v1","month":"2026-09","measure":"approx_distinct_network_voters","relative_standard_error":0.008125,"generated_at":"...","groups":[{"version":"v2026.09.0","channel":"stable","mode":"private","estimate":37}]}
```
Rows are sorted by estimate then fixed key, limited to the bounded stored groups, and include an `other` version bucket. Empty known epochs return `200` with `groups:[]`; unavailable epochs return `404`.

### `GET /v1/report/features?month=2026-09&feature_schema=2026.09`
`200`:
```json
{"api":"v1","month":"2026-09","feature_schema":"2026.09","measure":"approx_distinct_network_voters","relative_standard_error":0.008125,"generated_at":"...","eligible_estimate":42,"features":[{"key":"import.legal_unit","estimate":28},{"key":"import.generic_unit","estimate":0}]}
```
Return every key in the fixed manifest, including zero, so “what is never used” is visible without accepting arbitrary query keys. Optional channel/mode filters are validated enums and use only predeclared counters. Invalid filters are `400`; unknown schema/month `404`.

`GET /v1/health` returns only `200 {"status":"ok","api":"v1"}` after state load, otherwise `503`. GET bodies contain only normalized allow-listed dimensions and computed estimates. They never contain IP hashes, delivery IDs, webhook bytes, report bytes, headers, or arbitrary submitted strings. Cap every GET response at 256 KiB.
---

author: Jcode architect
created: 2026-09-02 13:39
---
## Design 5/10: in-memory state and bounds

Use one `State` guarded by a short-held `sync.RWMutex`, or an owner goroutine if benchmarks show simpler contention. HTTP handlers validate and hash before entering the critical section. State contains:
* HLL monthly epochs for current month plus previous two months.
* A 65,536-entry LRU/TTL set of `(daily_ip_token, vote_key)`, TTL 26 hours.
* A 16,384-entry per-IP token-bucket LRU, idle TTL 2 hours.
* A 50,000-entry CI verdict map keyed by fixed-size SHA plus canonical workflow.
* A 20,000-entry delivery-ID LRU, TTL 7 days.
* Dirty generation, last snapshot generation/time, and fixed manifests/catalogs.

HLL uses precision `p=14`, hence `m=2^14=16,384` one-byte registers, about 16 KiB per counter. Standard relative error is `1.04/sqrt(m)=0.008125`, about 0.81%. That is materially below the uncertainty caused by NAT, carrier gateways, DHCP, VPNs, and one installation using several egress addresses. A smaller `p=12` would save little operationally while doubling error to about 1.6%; larger precision is not justified. Implement standard 64-bit hashing, rank, small-range correction, and estimator tests against deterministic streams.

The unit estimated is distinct public source-IP pseudonyms per calendar month, not installations or people. NAT can undercount many boxes as one; address changes can overcount one box; report it as an estimate, never as an exact installed base.

Derive domain-separated tokens with HMAC-SHA256 over canonical `netip.Addr`: monthly token for HLL (`hll|YYYY-MM|ip`), daily token for finite voting (`vote|YYYY-MM-DD|ip`), and short-lived rate token (`rate|UTC-day|ip`). The secret is local receiver configuration, not snapshotted. Store only truncated 128-bit HMAC outputs in transient maps and hash those again for HLL. Raw IPs never enter state or logs.

Bound version cardinality to 64 observed release strings per month; new values after that merge into `other`. Channels, modes, feature schemas, features, group combinations, and workflows come only from compiled catalogs. Keep at most 12 feature-schema manifests. With three epochs, 64 versions, fixed combinations, and <=16 features/schema, the conservative dense HLL ceiling is about 23 MiB. CI retention is 120 days, with oldest `finished_at` eviction whenever 50,000 keys is reached. These hard caps make request-driven storage exhaustion impossible. They also keep a full state snapshot below a validated 64 MiB uncompressed ceiling.
---

author: Jcode architect
created: 2026-09-02 13:42
---
## Design 6/10: binding no-reflection correction, guardrails, and snapshots

Binding clarification to Designs 3 and 5: never retain a report's arbitrary `version` string as a bucket label. The receiver carries a compiled release catalog alongside feature manifests. Exact known releases/candidates map to their compiled canonical labels; a syntactically valid but unknown version maps to `other`. The “64 versions” ceiling is 64 compiled catalog entries per epoch, not first-writer-created labels. Thus GET can emit only server-owned labels. Likewise, request errors never include field values or decoder text. Structured CI numbers/times are parsed and re-encoded; no raw body or arbitrary GitHub string is retained or served.

Token buckets, using the transient keyed IP token and a monotonic clock:
* `/v1/report`: 1 token/minute, burst 4.
* `/v1/ci`: 120 tokens/minute, burst 240. The HMAC and repository restriction remain the real authorization.
* all GETs combined: 60 tokens/minute, burst 120.
When the 16,384 bucket cap is full, evict the least recently used bucket, which can only make limiting temporarily more permissive. Add server-wide connection, header, and concurrency limits; `ReadHeaderTimeout=5s`, body read deadline 10s, write timeout 10s, idle timeout 30s, and at most 128 concurrent handlers. Caddy also applies a conservative request-body ceiling, but Go enforces route-specific limits.

Finite voting uses the 65,536-entry `(daily_ip_token, server-owned vote key)` LRU for 26 hours. One accepted IP can touch each base/feature key once per UTC day. HLL monthly idempotence is the cardinality guarantee; the daily LRU prevents repeated CPU and dirty writes. If it evicts early under attack, another add of the same HLL value still cannot increase a register unless it truly raises that register.

Write-only-on-change is literal: mark state dirty only when an HLL register increases or a CI reducer changes durable fields. Duplicates, lower HLL ranks, unknown votes, and old CI runs return `204` without advancing the dirty generation or writing disk.

One canonical snapshot: `%h/.local/state/statbus-telemetry/state-v1.json.gz`. Gzip JSON contains `format_version`, `created_at`, `generation`, fixed catalog hashes, three epoch names with base64 register arrays, and bounded CI verdict records. It excludes raw IPs, HMAC IP tokens, token buckets, finite-vote LRU, delivery-ID LRU, and secrets. Validate format, catalog compatibility, month bounds, counter count/register length, CI field grammar, and a 64 MiB uncompressed limit before publishing state.

Every hour, and only if dirty generation differs, serialize a consistent copy, write a same-directory temporary file mode 0600, `fsync`, rename atomically over the canonical file, then sync the directory. SIGTERM gets one bounded final flush. On missing, truncated, corrupt, oversized, or incompatible state, log a fixed reason and start empty; never partially load. A crash may lose at most the changes since the last hourly snapshot. Losing up to one hour of approximate reports and CI cache is acceptable because reporters retry on later ticks and GitHub REST remains authoritative. The transient LRUs intentionally start empty.
---

author: Jcode architect
created: 2026-09-02 13:42
---
## Design 7/10: real client IP and Caddy trust boundary

The Go process listens only on `127.0.0.1:3117` and rejects a request whose TCP peer is not loopback. It trusts exactly one `X-Forwarded-For` address only because the peer is the local niue Caddy. It parses that header with `net/netip`, rejects lists, ports, zones, invalid/mapped ambiguity, and canonicalizes IPv4/IPv6 before HMAC.

The dedicated Caddy site must overwrite, not append to, the client-supplied header:
```caddy
telemetry.statbus.org {
    encode gzip
    reverse_proxy 127.0.0.1:3117 {
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto https
        header_up Host {host}
    }
}
```
Caddy terminates public TLS directly on niue. Its `{remote_host}` is therefore the TCP peer, so an Internet client sending `X-Forwarded-For: 1.2.3.4` cannot choose the identity used by rate limits or HLL. Before reload, verify the generated/adapted Caddy JSON really replaces the inbound header and test a spoofed request end to end. If a CDN or another reverse proxy is ever placed in front, this assumption becomes false: configure Caddy's trusted proxy CIDRs and client-IP parsing explicitly, then still send one normalized value upstream. Do not make Go trust a chain.

Do not enable access logging for this hostname. Caddy's existing www logging must not be inherited into this block. The service logs route, status class, duration bucket, and fixed reason codes only, never remote address, forwarded headers, query strings, request bodies, SHAs, versions, delivery IDs, or secrets. Metrics, if later added, are fixed counters only. The network stack necessarily holds the peer address while a request is handled; the application immediately converts it to a keyed one-way token and never stores or writes the address.

Secrets live in `%h/.config/statbus-telemetry-receiver.env`, mode 0600: current/previous GitHub webhook secrets and an independent random 32-byte IP-HMAC secret. Domain separation prevents cross-window/cross-purpose linkability. HLL snapshots contain only register maxima, so neither a snapshot nor a GET response contains values that can be reversed to addresses.
---

author: Jcode architect
created: 2026-09-02 13:42
---
## Design 8/10: niue deployment and update story

DNS adds `telemetry.statbus.org` to niue's existing public address. The host administrator adds the explicit SNI block to `/etc/caddy/Caddyfile`, validates with Caddy, and reloads. Use `3117` only after checking the live listener table because the read-only SSH key was unavailable; the architectural rule is a documented, loopback-only, host-shared port outside every slot's `base+0..6` range. No Docker container, database, new VM, or cloud service is introduced.

Run as the established `statbus_web` Unix account with a user unit such as `%h/.config/systemd/user/statbus-telemetry-receiver.service`:
```ini
[Unit]
Description=StatBus public telemetry and CI receiver
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=%h/.config/statbus-telemetry-receiver.env
ExecStart=%h/.local/bin/statbus-telemetry-receiver -listen 127.0.0.1:3117
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.local/state/statbus-telemetry
MemoryMax=192M
TasksMax=64

[Install]
WantedBy=default.target
```
Confirm which hardening directives the niue user manager supports, create the state directory mode 0700, enable lingering as already done for durable user services, then `systemctl --user enable --now`. Health checks target loopback and public TLS. Alert only on sustained health failure or restart loop.

Source belongs in this repository so protocol, feature enums, release catalog, reporter, and product release remain reviewably synchronized. Recommended layout: `cli/cmd/statbus-telemetry-receiver/`, `cli/internal/telemetryreceiver/`, and a small shared `cli/internal/telemetryschema/`. This is a sibling command in the existing Go module, not a separate repository and not embedded in `sb`'s long-running upgrade process.

The existing release workflow builds reproducible static Linux assets for the supported niue architecture, publishes SHA-256 checksums, and can add this tiny binary to the same named candidate/release artifacts. A deliberate deploy step downloads the named asset, verifies checksum, installs to a versioned path, atomically switches `%h/.local/bin/statbus-telemetry-receiver`, restarts the unit, checks `/v1/health`, and retains one previous binary for manual rollback. It never deploys master. There is no self-update.

For a new product feature schema or exact version label, land the shared manifest first and deploy the candidate receiver before installations on that candidate can report. Old receivers safely count base dimensions as `other` and drop unknown features, so ordering mistakes degrade information rather than create keys or fail boxes. Snapshot catalog hashes permit additive manifests; incompatible state starts empty rather than guessing.
---

author: Jcode architect
created: 2026-09-02 13:42
---
## Design 9/10: client reporter, webhook ownership, and release consumers

Add this visible `.env.config` entry-way block through `cli/internal/config/config.go`, default false:
```text
# Anonymous aggregate telemetry (default: off).
# When enabled, StatBus sends its release version, upgrade channel, deployment
# mode, and yes/no votes from a published fixed feature list to Statistics Norway.
# It sends no registry data, names, counts, users, country, domain, or box ID.
# The receiver uses the network address only transiently for abuse limiting and
# approximate distinct counts; it stores no address.
TELEMETRY_REPORTING=false
```
Document the same plain statement in operator installation/upgrade docs. `false` returns before local feature probes, URL construction, DNS, or goroutine creation, preserving today's behavior exactly.

When enabled, the upgrade service launches a single-flight, best-effort report with a 3-second total timeout and no immediate retry: (1) after startup discover/execute has reached a settled installed state at `cli/internal/upgrade/service.go` around 2728-2741, and (2) at the tail of each successful six-hour tick around 2776-2809, after candidate checking/execution. If an inline upgrade restarts the process, the new process reports its final version. Reporting never delays, fails, parks, or changes an upgrade. Later normal ticks are the retry mechanism.

The reporter obtains version, configured channel, and deployment mode from existing validated configuration. Each feature key has a reviewed pure Boolean detector backed by durable local state. Send “ever observed here” only where that fact is reliable; send no row counts or timestamps. Do not invent a vote for features without a trustworthy local signal. Deduplicate and sort keys before JSON encoding. Use only the fixed `https://telemetry.statbus.org/v1/report` URL in production, with a test override unavailable from public config.

A Statistics Norway GitHub repository administrator registers one active webhook for `workflow_run` only, payload URL `https://telemetry.statbus.org/v1/ci`, content type JSON, and a random >=32-byte secret. Store it only in GitHub's webhook configuration and the niue 0600 environment file. Rotate by installing `current=new, previous=old` on the receiver, updating GitHub, verifying a signed delivery/health, waiting through the manual-redelivery risk window, then removing old. If rotation goes wrong, CI cache misses are harmless and REST still gates.

`./sb release` preflight may read `/v1/ci/verdict` as a fast hint and diagnostic, but MUST always confirm every required workflow against GitHub REST using the existing `workflow_check.go` semantics before cutting or publishing anything. Cache green can only trigger an earlier REST check; it can never satisfy a gate. Cache red/missing cannot permanently block: watchers poll REST periodically and at their deadline. Receiver unavailable, stale, compromised, or disagreeing means REST wins. If GitHub REST is unavailable or inconclusive, fail closed exactly as today. The version/channel and feature GET faces feed advisory dashboards such as STATBUS-339 only; they authorize nothing.
---

author: Jcode architect
created: 2026-09-02 13:42
---
## Design 10/10: failures, privacy statement, estimate, and phased landing

| Failure or abuse | Defined behavior |
|---|---|
| Receiver down or DNS/TLS failure | Boxes abandon within 3 seconds and say nothing; next six-hour tick may try again. Release preflight/watchers go directly to GitHub REST. |
| niue down | Same as receiver down. No box or release operation depends on telemetry availability. |
| Missed GitHub webhook | Cache remains missing/stale; periodic REST polling finds the authoritative run. An admin may manually redeliver. |
| Snapshot/HLL state lost or corrupt | Start empty. At most the retained three-month estimates and cached CI history are lost; no operational state is lost. Current reports rebuild estimates and REST covers CI. |
| Crash between snapshots | Lose at most one hour of accepted changes. This is acceptable for estimates/cache. |
| Webhook secret mismatch/rotation | `/ci` returns fixed `401`; health remains up; current+previous overlap repairs without downtime; REST continues to gate. |
| Spoofed X-Forwarded-For | Caddy overwrites it; Go accepts the header only from loopback. End-to-end spoof test is a deployment gate. |
| One noisy address | Burst 4 then 1 report/minute. Daily finite votes suppress work and monthly HLL means it can add at most one estimated voter to any counter. |
| Botnet with N distinct public IPs | It can inflate any chosen monthly estimate by at most approximately N, subject to HLL error. One report can touch at most 16 feature counters, so total useful feature touches are <=16N per month; repeated requests do not multiply a counter. This is the unavoidable bound without box identity or pre-registration. |
| Version/key cardinality attack | Unknown versions become `other`; unknown feature/schema/query keys never allocate state. All other dimensions are compiled enums. |
| Storage exhaustion attempt | HLL epochs/counters are fixed (~23 MiB dense), CI 50,000/120 days, vote LRU 65,536, rate LRU 16,384, delivery LRU 20,000, snapshot <=64 MiB uncompressed, and bodies/responses/concurrency are capped. Request volume cannot grow disk or maps beyond those limits. |
| Receiver compromised and says green | Preflight's mandatory GitHub REST verification rejects the false hint. Receiver credentials have no GitHub API write/token authority. |

Plain privacy statement for an NSO: telemetry is off unless an operator turns it on. When on, a box sends only its StatBus release, release channel, deployment mode, and yes/no entries from a published list of product features. It sends no statistical data, organization/person names, row counts, users, country code, hostname, domain, database identifiers, or persistent installation identifier. The server necessarily sees the network source while receiving a packet, but immediately converts it with a secret one-way HMAC and does not log or store the address. Published numbers are approximate counts of network-source voters; NAT may merge boxes and changing addresses may split one box. This is anonymous aggregate evidence, not an inventory.

What this is not: no pre-registration, accounts, API keys, per-box identity, cookies, fingerprint, IP database, customer portal, support beacon, remote control, update channel, release authority, durable event ledger, raw analytics lake, or customer-facing feature. It cannot answer which institution uses a feature.

Ballpark: receiver 1,600-2,100 production Go LOC; reporter/config integration 250-400; tests 1,200-1,600; Caddy/unit/docs 100-200. Dependencies remain Go stdlib. Pure-function tests cover HLL rank/estimate/merge/serialization and statistical error, reducer ordering/idempotence, manifest validation, canonicalization, LRU/TTL, token bucket with fake clock, caps, and snapshot validation. `httptest` covers every route/code, exact HMAC bytes, current/previous secrets, redelivery, malformed/trailing JSON, size limits, enum dropping, no-reflection responses, GET ordering, and recovery. Add fuzzing, `go test -race`, corrupt/truncated snapshot tests, deterministic clock/RNG injection, and Caddy spoof/TLS smoke tests on niue staging.

Land in three independently safe phases: (1) receiver, snapshot, `/ci`, CI GET, deployment, and webhook while preflight remains unchanged; (2) `/report`, aggregate GETs, opt-in reporter, entry-way text, and privacy docs; (3) let preflight/watchers consult the cache for latency/diagnostics while retaining mandatory GitHub REST authority. Each phase can be rolled back without affecting installation or release correctness.
---

author: Jcode architect
created: 2026-09-02 13:43
---
## Binding consistency addendum: exact bounded counters and public aggregation

This addendum resolves two places where the compact ticket text otherwise implied more HLLs than the stated memory proof.

V1 stores only these report counters per month: total (1), exact known version plus `other` (65), channel (3), mode (3), version+channel including overflow (195), feature-schema respondents (12), and schema feature keys (12 x 16 = 192). That is 471 dense HLLs per epoch, 1,413 across three epochs, or 22.1 MiB of 16 KiB registers before small object overhead. Round the operational claim to about 23 MiB. Therefore:
* `/v1/report/histogram` supports only `group=version`, `channel`, `mode`, or `version,channel`. It does not support the previously illustrated `version,channel,mode` triple in v1.
* `/v1/report/features` has no channel/mode filters in v1. Adding segmented feature estimates would require a new API version and a fresh explicit memory bound.

HLL values are domain-separated per counter, not reused across counters:
`first64(HMAC-SHA256(IP_HASH_SECRET, "hll\x00" || month || "\x00" || counter_id || "\x00" || canonical_ip))`.
This prevents direct cross-counter correlation of register placement. The daily finite-vote and rate-limit tokens use separate domains. Raw addresses and these values are never snapshotted.

The compiled exact-version catalog is generated by the named release build from the current candidate plus the bounded public release-tag set, then embedded in the receiver artifact. It is not populated from report input. On deployment, the new binary merges only compiled labels with still-supported labels already named by its validated snapshot, capped at 64; unknown report versions become `other`. A clean rebuild can regenerate the same catalog from release metadata. This preserves exact version histograms without creating a public write/read string relay.

For public counts, use a uniform count object: exact empty is `{ "observed": false, "estimate": 0, "suppressed": false }`; estimates 1-4 are `{ "observed": true, "estimate": null, "suppressed": true }`; 5+ publish the rounded estimate. Feature output still includes every compiled key, so never-observed keys are visible. This small-cell rule is privacy hygiene, not a claim of statistical disclosure control, because source IP is only an approximate network voter.
---

author: foreman
created: 2026-09-03 12:54
---
KING APPROVED THE DESIGN (2026-09-03): 'queue the build. It's quite a big thing but it's also sensible to just do it because that's the only way to know what's going on.' Review directive attached: the work gets MULTIPLE REVIEW PASSES for minimality and relevance — foreman reviews each phase's diff with the explicit question 'is this minimal, is every piece relevant', beyond the normal correctness review. Build queued behind the v2026.09.0 promotion settling; lands in the architect's three independently-safe phases (1: receiver+snapshot+/ci+CI-GET+deploy+webhook, preflight untouched; 2: /report+aggregate GETs+opt-in reporter+entry-way text+privacy docs; 3: preflight/watchers may consult the cache, REST authority retained). Each phase: build → foreman correctness review → foreman minimality review → land → next.
---
<!-- COMMENTS:END -->
