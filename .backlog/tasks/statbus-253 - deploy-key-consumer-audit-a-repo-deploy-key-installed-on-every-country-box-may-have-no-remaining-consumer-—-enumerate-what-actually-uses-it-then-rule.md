---
id: STATBUS-253
title: >-
  deploy-key-consumer-audit: a repo deploy key installed on every country box
  may have no remaining consumer — enumerate what actually uses it, then rule
status: To Do
assignee: []
created_date: '2026-08-19 10:27'
updated_date: '2026-08-19 10:34'
labels:
  - ops
  - security
dependencies: []
priority: medium
type: chore
ordinal: 246000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The instance-creation script installs GitHub-sourced public keys into each country box's authorized_keys (GITHUB_DEPLOY_KEYS). The stated purpose — "gives the deploy-to-* workflow ssh ability" — is gone: under the approved topology a country slot has no deploy-to workflow, and the canary gate SSHes with the operator's own key, not a repo deploy key. If nothing else consumes it, this is a standing CI credential on live NSO production installations with nothing that uses it.

FILED FROM the architect's 251 review (his own named miss): the design's orphan check asked whether the script creates GitHub-side objects and answered "checked, none" — the wrong question. The right question is whether the authorized_keys entry installed ON THE BOX still has a consumer.

NOT ESTABLISHED: that the key is dead. There may be a consumer not yet found — which is why this is an enumeration-then-ruling, not a removal order. "An unnecessary standing credential on a production statistical office box" gets one deliberate answer, never inheritance by default.

DISTINCT AND UNAFFECTED: runbook step 6's "Generate SSH deployment key for GitHub" — that is the box's own key for cloning the private repo, legitimate and out of scope.

THE WORK: enumerate every consumer of the GITHUB_DEPLOY_KEYS-installed authorized_keys entries — CI workflows that ssh to slots, ops scripts, the upgrade service's own paths, anything in .github/ and ops/ that authenticates to a box. Deliverable: the enumeration pinned here with each consumer named (or "none found, searched X/Y/Z"), then the architect rules keep-or-remove. Any removal ships via the ruled mechanism, never a manual write.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-19 10:33
---
ENUMERATION part 1/2 (read-only; no box touched). DIRECT ANSWER: the repo's registered deploy key is NOT dead — it is actively consumed today by at least 8 workflows to reach niue country boxes AND the niue host-admin account, via the repo secret `secrets.SSH_KEY`. This is expected/correct for et/jo/ma/tcc/ug/dev (STATBUS-244a's own transitional note says their deploy-to-X.yaml files remain live until Wave D1); it is NOT expected for demo, whose deploy-to-demo.yaml is already deleted — see the orphan finding in part 2.

IDENTITY EVIDENCE tying `secrets.SSH_KEY` to a SPECIFIC registered deploy key (I cannot read the secret's value directly — this is the strongest evidence obtainable from the repo side alone):
- `gh repo deploy-key list` shows exactly ONE read-write key, titled `https://github.com/statisticsnorway/statbus`, fingerprint material `AAAAC3NzaC1lZDI1NTE5AAAAIAdpqAWRoDDKDa7neWpTLe+coEYYSkhzw2znSJ3E6XjD`. Every other registered deploy key is read-only and titled per-box (statbus_dev/ma/tcc/ug/et/jo/demo/norway/test@<host>) — those are boxes' OWN clone keys (runbook step 6, confirmed out of scope by this ticket's own text).
- That exact same key material is hardcoded in `ops/create-new-statbus-installation.sh`'s `DEPLOY_KEY` variable.
- `ops/create-new-statbus-installation.sh`'s `GITHUB_DEPLOY_KEYS` defaults to `statisticsnorway/statbus`, and `ops/setup-ubuntu-lts-24.sh` defaults identically (line 292/367) — both install it via `populate_authorized_keys`/`fetch_source()`, which fetches `https://github.com/<source>.keys` and installs EVERY returned key VERBATIM, unrestricted (no `command=` prefix — confirmed by reading the exact `printf '%s # %s\n'` write in both scripts).
- `.github/workflows/master-to-dev.yaml:16` uses `secrets.SSH_KEY` as `actions/checkout@v3`'s `ssh-key:` input, then line 19 does `git push --force origin HEAD:ops/cloud/deploy/dev` — this REQUIRES write access to the repo itself. Only the one read-write deploy key found above could do this; a read-only key would fail this push outright.

CONSUMER LIST (searched: `.github/workflows/*.yaml` for `ssh -i`, `ssh-key:`, `appleboy/ssh-action`, `webfactory/ssh-agent`, `scp `, every `secrets.*` name; `ops/*.sh` for `statbus_*@`/`niue.statbus.org`/`rune.statbus.org`):
- `deploy-to-{dev,et,jo,ma,tcc,ug}.yaml` (each :56/65/103/116, dev's own at :73/82/124/137) — `secrets.SSH_KEY` → `statbus_<slot>@niue.statbus.org`, runs `cd ~/statbus && ./sb upgrade apply-latest`.
- `notify-all-clouds.yaml:112/131` — `secrets.SSH_KEY` → matrix over `statbus_{dev,demo,tcc,ma,ug,et,jo}@niue.statbus.org` (line 102-108), runs `~/statbus/ops/ci-notify.sh`.
- `docker-maintenance.yaml:30/35` and `seq-logserver.yaml:30/35` — `secrets.SSH_KEY` → `devops@niue.statbus.org`. The workflow's OWN comment (docker-maintenance.yaml:26-28) states plainly: "devops is a free admin shell (bare authorized_keys, not n-gated)" — i.e. NOT sshdo-restricted, by design. This is the most privileged live consumer.
- `master-to-dev.yaml:16` — `secrets.SSH_KEY` → git push to the repo itself (not a box SSH at all, but the same credential).
- `pg_regress.yaml:63/115/135` — `secrets.SSH_KEY` → `statbus_test@niue.statbus.org`.

Continued in part 2/2 (sshdo cross-check, orphan finding, out-of-scope confirmations, one open question).
---

author: mechanic
created: 2026-08-19 10:34
---
ENUMERATION part 2/2 (continued from part 1).

SERVER-SIDE RESTRICTION, CROSS-CHECKED: `ops/niue/sshdoers` (checked into the repo) explicitly allowlists exactly two command shapes per statbus_{tcc,dev,demo,ma,ug,et,jo} user — `cd ~/statbus && ./sb upgrade apply-latest` and `~/statbus/ops/ci-notify.sh` — plus a third for statbus_test (pg_regress). `devops` has NO sshdoers entry (matches the workflow comment quoted in part 1 — confirmed by grep, zero hits for "devops" in the file).

ORPHAN FOUND (in scope for this ticket, not a removal — flagging only): `ops/niue/sshdoers:16` (`statbus_demo: cd ~/statbus && ./sb upgrade apply-latest`) has NO calling workflow left — `deploy-to-demo.yaml` was deleted in STATBUS-244a. `ops/niue/sshdoers:32` (`statbus_demo: ~/statbus/ops/ci-notify.sh`) is STILL live — `notify-all-clouds.yaml`'s matrix still includes `statbus_demo`. So demo's apply-latest sshdo rule is dead; its notify rule is not.

OUT OF SCOPE, CONFIRMED SEPARATE (searched and ruled out, not just skipped):
- `secrets.STATBUS_CI_SSH_PRIVATE_KEY` (install-recovery-harness.yaml, upgrade-arc-harness.yaml, test-install.yaml, test-upgrade.yaml) — a DIFFERENT dedicated key for ephemeral Hetzner CI VMs (`HCLOUD_SSH_KEY: statbus-ci`), never touches niue/rune or GITHUB_DEPLOY_KEYS at all.
- `secrets.RUNNER_HEALTH_SSH_KEY` (notify-all-clouds.yaml:62) — its own comment (line 33) states it is "a DEDICATED key (secret RUNNER_HEALTH_SSH_KEY, revocable server-side, no PAT" — explicitly NOT the deploy key.
- `ops/inspect-cloud-installations.sh:21` — bare `ssh "$user@niue.statbus.org"` with no `-i`/no secret reference at all — relies on the OPERATOR's own personal key (GITHUB_USERS mechanism), not GITHUB_DEPLOY_KEYS.
- Norway/rune-no: `ops/niue/sshdoers` is niue-specific; rune is a separate standalone host with no equivalent checked-in sshdoers file found (searched: `find . -iname sshdoers* -o -iname '*rune*sshdo*'`, no hits) — rune-no's own SSH consumer question is NOT answered by this enumeration and would need a separate pass if wanted.

ONE OPEN QUESTION I CANNOT RESOLVE FROM THE REPO ALONE (flagging, not guessing): sshdo supports two deployment modes — a per-key `command="sshdo"` prefix in authorized_keys, OR a global `ForceCommand /usr/bin/sshdo` in `sshd_config`'s `Match User` block (ops/niue/sshdo:61-66, its own usage doc). Since the GITHUB_DEPLOY_KEYS-fetched copy of the repo deploy key is installed WITHOUT any `command=` prefix (confirmed in part 1), if niue uses the per-key mode rather than sshd_config ForceCommand, that unrestricted copy could bypass sshdo's allowlist entirely for statbus_et/jo/ma/tcc/ug/dev/demo/test — same key, same account, just a different matching authorized_keys line. I have no way to check sshd_config from the repo; this would need one read-only operator command (e.g. `ssh devops@niue 'sudo sshd -T | grep -i forcecommand'`) to settle, same evidentiary bar as STATBUS-251's own channel-read ask. Not established either way — flagging for the architect's ruling, not asserting a hole.
---
<!-- COMMENTS:END -->
