---
id: STATBUS-463
title: >-
  statbus.org shorthand /uninstall.sh returns 404 while /install.sh works: add
  the missing redirect and guard the documented URLs
status: To Do
assignee: []
created_date: '2026-10-08 11:53'
labels:
  - docs
  - ops
dependencies: []
priority: high
ordinal: 390204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: every script URL our documentation tells an operator to pipe into a shell actually returns the script, and a check keeps it that way, so we never again publish a dead shorthand.

THE DEFECT (verified 2026-10-08, coordinator). The two hosted shorthands do not behave alike:
* https://statbus.org/install.sh -> 302 -> https://raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/install.sh -> 200.
* https://statbus.org/uninstall.sh -> 302 -> https://www.statbus.org/uninstall.sh -> 404.
The install shorthand has an explicit redirect rule; the uninstall one has none, so it falls through to the generic apex-to-www redirect and 404s on the www host. doc/DEPLOYMENT.md advertised the broken one (line 7 of the uninstall section); that reference was corrected the same day to the verified raw.githubusercontent URL.

WHERE THE FIX LIVES. Not in the statbus-web working tree. That repo is deployed by pushing to master, which SSHes to niue.statbus.org as statbus_www and runs ./deploy.sh, and that script lives ON THE SERVER (statbus-web/CLAUDE.md, Deploy section). The tree contains no _redirects, netlify.toml, CNAME, .htaccess, vercel.json or any *.conf, and no *.sh files, so the shorthand rules are host-side web configuration. The fix is therefore a redirect rule added wherever install.sh is redirected today: add the mirror rule for /uninstall.sh (for example a 302 to https://raw.githubusercontent.com/statisticsnorway/statbus/master/uninstall.sh), or serve the file from the site itself.

OBSERVATION FOR WHOEVER APPLIES THE RULE: the working install shorthand redirects to the MASTER copy of the script, not to a released tag, so the shorthand always runs master's installer. That appears intentional given the installer accepts --version and --channel, but the rule for uninstall.sh must make the same deliberate choice rather than copying it by accident.

WHY IT MATTERS: the uninstall instructions are exactly the ones an operator runs when removing an installation, and a piped shell command that 404s looks like a broken product rather than a broken web rule. It was found from the field, not by us.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 https://statbus.org/uninstall.sh returns the uninstall script to a piped shell (via a redirect rule mirroring install.sh, or by serving the file), verified with curl following redirects.
- [ ] #2 Both documented shorthand URLs, install.sh and uninstall.sh, are verified to return 200 end to end, and the verification is a check we can repeat so a documented script URL can never silently 404 again.
- [ ] #3 The redirect rule for uninstall.sh makes an explicit choice about which revision it serves (master, mirroring install.sh, or a pinned release), and that choice is stated where the rules live.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 doc/DEPLOYMENT.md contains only script URLs that have been verified, and the field-reported 404 is recorded as the reason the check exists.
<!-- DOD:END -->
