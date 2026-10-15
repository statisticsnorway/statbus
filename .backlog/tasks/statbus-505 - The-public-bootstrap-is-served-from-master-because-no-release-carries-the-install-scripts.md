---
id: STATBUS-505
title: >-
  The public bootstrap is served from master because no release carries the
  install scripts
status: Done
assignee: []
created_date: '2026-10-13 15:39'
updated_date: '2026-10-15 19:39'
labels:
  - release
  - docs
  - cloud
dependencies: []
priority: medium
type: bug
ordinal: 431204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 by the owner hint (the Caddyfile on niue). statbus.org is routed by Caddy on niue, and its block reads: handle /install.sh redirects 302 to https://raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/install.sh; handle /uninstall.sh does the same for uninstall.sh. So the bootstrap every operator runs is the MASTER branch, which is the same shape as STATBUS-488 (a prepare script from master) and the last place that bypasses the rule that only a named release candidate reaches an installation.

WHY IT IS LIKE THAT, grounded: a release publishes only sb binaries, checksums.txt and release-manifest.json (cli/internal/release/check.go requiredAssets), and .github/workflows/release.yaml uploads no scripts. There is therefore no tagged install.sh for the redirect to point at, and releases/latest/download/install.sh would 404.

OPTIONS: (A) keep master deliberately, recorded as THE one documented bootstrap exception; (B) publish install.sh, uninstall.sh and the prepare script as release assets and point the redirects at releases/latest/download/, so the bootstrap is the tagged artifact and statbus.org/setup.sh can exist as the one-command prepare the owner asked for (STATBUS-504); (C) serve a small resolving snippet from the domain. Coordinator recommendation: B, and it is the owner decision because it changes the release workflow and a production Caddyfile on niue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The decision is recorded: either the bootstrap exception is documented as deliberate, or the scripts become release assets and the redirects move to the tagged artifact.
- [x] #2 If the scripts become release assets: a release carries them, the redirect targets are updated on niue, and fetching statbus.org/install.sh can no longer serve code from a branch. Checked by the asset list of a real release and by the redirect target.
- [x] #3 Whether or not this changes, STATBUS-504 answer records how preparation becomes one command, consistently with STATBUS-488 release matching.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-13. The Caddyfile on niue is outside this repository (caddy/templates only renders slot deployments), so any change there is a production edit requiring the owner go and a caddy reload.

2026-10-13: STATBUS-504 (a statbus.org/setup.sh) is folded into this ticket - same decision, tracked once. So the single question here is: (A) keep master deliberately as the documented bootstrap exception, or (B) publish install.sh, uninstall.sh and the prepare script as release assets and point the Caddy redirects at releases/latest/download/, which makes both commands one-liners and removes the last master dependency from the operator path, or (C) serve a resolving snippet from the domain. Coordinator recommendation: B.

OWNER DECISION 2026-10-13: option B. The shortcuts always serve the LATEST RELEASE; master is reachable on GitHub for anyone who deliberately wants unreleased code.

STEP 1 DONE (this commit): .github/workflows/release.yaml now stages install.sh, uninstall.sh and ops/setup-ubuntu-lts.sh into dist/ and passes them to gh release create, so every future release carries them as assets. Safe against the release verification: cli/internal/release/check.go CheckAssets builds its result list from requiredAssets and only asks whether each REQUIRED asset is present, so extra assets are allowed (checked, not assumed).

SEQUENCING, and this is why the redirects are NOT flipped yet: until a release actually carries those assets, releases/latest/download/install.sh does not exist, so pointing statbus.org at it now would 404 the public installer for everyone. Order: (2) at the next release, verify the asset list carries the three scripts (gh release view <tag> --json assets); (3) THEN, with the owner go, edit the Caddyfile on niue: /install.sh and /uninstall.sh to releases/latest/download/<name>, and add a /setup.sh handle for the prepare script; validate and reload, then verify each shortcut with curl -I; (4) update the README and docs to the one-line shortcuts, keeping the pinned two-line form for a specific version.

NOT DONE, deliberately: the install scripts are not added to checksums.txt (that file covers the sb binaries, generated in the build-binaries job). Note for a later pass if we want the verifier to cover the scripts too.

BEFORE-STATE captured 2026-10-13 from OUTSIDE, before any change (this is the other half of the evidence for step 3, so there is a before and after pair):

  curl -sI https://statbus.org/install.sh    -> 302, location: https://raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/install.sh
  curl -sI https://statbus.org/uninstall.sh  -> 302, location: https://raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/uninstall.sh
  curl -sI https://statbus.org/setup.sh      -> 302, location: https://www.statbus.org/setup.sh  -> which is 404 (verified)

SMALL DISCOVERY worth recording: there is NO setup.sh handler on niue at all. `grep -n setup.sh /etc/caddy/Caddyfile` finds nothing; what answers /setup.sh is the statbus.org block catch-all `redir https://www.statbus.org{uri} 302`, and the www host is a static file server (root /home/statbus_www/public_html, file_server with try_files) which has no setup.sh. So that path 404s by accident today, not by design - anyone who guessed the natural shortcut got a broken page.

WHAT STEP 3 THEREFORE IS, exactly: in the statbus.org block, replace the two raw-master `handle` redirect targets with https://github.com/statisticsnorway/statbus/releases/latest/download/<name> for install.sh and uninstall.sh, and ADD a `handle /setup.sh` for setup-ubuntu-lts.sh pointing at the same latest-download form. Then `caddy validate` and reload, and re-run the three curl -I checks above to record the after-state.

BEFORE-STATE RECORDED 2026-10-13 (read-only, no host change made). statbus.org/install.sh and /uninstall.sh both 302 to raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/<script> - i.e. MASTER, the exact thing the only-a-named-candidate rule forbids. statbus.org/setup.sh 302s to www.statbus.org/setup.sh, which is a 404, so that shortcut serves no script at all today. TARGET: https://github.com/statisticsnorway/statbus/releases/latest/download/<script> (asset publishing added at .github/workflows/release.yaml:204-282 by 7e8253a46). NOT YET AVAILABLE: those three asset URLs 404 right now - the latest release is v2026.10.0 (2026-10-07, before 7e8253a46) and publishes only checksums.txt, release-manifest.json and the four sb-* binaries. HENCE the flip must wait for a release cut after 7e8253a46; flipping today would 404 the installer for operators. Full before-state saved at tmp/505-shortcut-before-state.txt.

### Step 2 verified (2026-10-15, after v2026.10.1 stable)
`releases/latest` is v2026.10.1. `releases/latest/download/{install.sh,uninstall.sh,setup-ubuntu-lts.sh}` all 200; the served install.sh is byte-identical to `git show v2026.10.1:install.sh`. Shortcuts still point at master (unchanged from the before-state).

### Step 3: the edit on niue (needs root; devops has no passwordless sudo)
In `/etc/caddy/Caddyfile`, block `statbus.org {` (line 201):
```
	handle /install.sh {
		redir https://github.com/statisticsnorway/statbus/releases/latest/download/install.sh 302
	}
	handle /uninstall.sh {
		redir https://github.com/statisticsnorway/statbus/releases/latest/download/uninstall.sh 302
	}
	handle /setup.sh {
		redir https://github.com/statisticsnorway/statbus/releases/latest/download/setup-ubuntu-lts.sh 302
	}
```
Then `sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy`.

### Step 4: check from outside
`curl -sI https://statbus.org/{install,uninstall,setup}.sh` each 302 to releases/latest/download/<asset>, and following it returns 200.

### Step 3-4 done (2026-10-15, owner granted root)
Backup /etc/caddy/Caddyfile.bak-505-20261015T193855Z. Exact-text edit (tmp/505-caddy-edit.py, refuses unless the block matches the before-state): install.sh and uninstall.sh now redirect to releases/latest/download/<name>, and /setup.sh is a new handler to releases/latest/download/setup-ubuntu-lts.sh. `caddy validate` ok, `systemctl reload caddy` active.
After, from outside: statbus.org/install.sh, /uninstall.sh and /setup.sh each 302 to releases/latest/download and return 200 with content byte-identical to v2026.10.1:install.sh, :uninstall.sh and :ops/setup-ubuntu-lts.sh. statbus.org/ still redirects to www (catch-all unchanged). No shortcut serves a branch any more.
AC3 (one-command preparation): `curl -fsSL https://statbus.org/setup.sh | ...` now exists and serves the released setup script, matching the release that install.sh installs.
<!-- SECTION:NOTES:END -->
