---
id: STATBUS-525
title: >-
  www.statbus.org: a static site with its own small Go program, deployed as
  releases; first job build status
status: To Do
assignee: []
created_date: '2026-10-21 21:19'
labels:
  - web
  - release
  - niue
dependencies: []
priority: medium
type: feature
ordinal: 451204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
www.statbus.org is a static site with one small Go program behind it, the site's own backend. Its first job is to publish build status, so boxes and the admin page can show "pending", "building" or "failed" for real. Later dynamic jobs go into the same program.

### Zoom out
- **Why a backend:** a box that cannot find a release's images only knows "not there". Only GitHub knows whether the build has not started, is running or failed, and boxes must not call the GitHub API (rate limits and tokens; removed in STATBUS-302). One place on our side asks GitHub for everyone and publishes the answer.
- **Why redesign the site's deploy at the same time:** the site is deployed by a script that lives only on niue (`/home/statbus_www/deploy.sh`), which does `git pull` into `~/statbus-web` and `rsync`s the whole checkout into `~/public_html`. So repo files are served: on 2026-10-21 `CLAUDE.md`, `patcepgadmin.txt` and `api/testforupgrade.php` (as source text) all answered 200. Adding a program to that setup would add a second deploy path. A clean design replaces both with one.
- **Principles agreed with the owner (2026-10-21):**
  - The repo is the site program. `public/` holds the pieces served as files. There is no separate "api" or "backend" folder.
  - Static files are served first. Anything without a static file goes to the program. If the program is down, the static site still works.
  - Local development runs the same program and needs nothing else.
  - A deploy installs an immutable release built by CI. No git checkout, `git pull`, `rsync` or hand-kept script on the server.
  - The program never trusts what is posted to it: a POST is only a nudge to look something up.

Design discussion: the owner and dolphin, 2026-10-20 and 2026-10-21, recorded in this ticket. Status-endpoint background: `tmp/lxd-gate-design.md` ("Option 1").

### Zoom in: the repo (`statisticsnorway/statbus-web`)
```
statbus-web/
  go.mod, go.sum        module statbus-web, Go standard library only
  main.go               the program: flags, listener, routes, start (small)
  internal/site/        static file if one exists, otherwise a handler
  internal/builds/      build status
  public/               the static site (moved with git mv, history kept)
  deploy/               Caddyfile.www, statbus-web.socket, statbus-web.service
  .github/workflows/deploy.yml
  README.md, CLAUDE.md, .gitignore
```
- **Go layout:**
  - Go compiles one folder at a time, and a `package main` folder becomes one program named after the folder, or after the module at the root. This repo is one program, so `main.go` sits at the root and `go build` gives `statbus-web`. A `cmd/` folder is the convention for repos with several programs; add `cmd/<name>/` only when a second program appears.
  - Code lives in `internal/<area>/`, which the compiler lets only this module import. Go ignores `public/` (no Go files).
- **`public/`:**
  - Everything served: `index.html`, `Overview/`, `Background/`, `Countries/`, `Contact/`, `Documentation/`, `Demo/`, `Energy/`, `Terms_and_privacy/`, `charts/`, `tools/`, `files/`, `images/`, `assets/`, `common.js`, `common_hc.js`, `Stats.css`, `progress.html`, `roadmap.html`, `Statbus.mp3`.
  - It is moved with `git mv` in a commit of its own, with no other change, so `git log --follow` and blame keep the history.
  - Not moved into `public/`: `README.md`, `CLAUDE.md`, `.gitignore`, `.github/`, the working notes (`jorgens_kladd.txt`, `patcepgadmin.txt`, `verify.R`, `Rplots.pdf`, `testtoken.py`), and `api/` (the PHP endpoint belongs to eriksberg.no; keep it outside `public/`, for example under `eriksberg/`).
  - `CLAUDE.md` and `README.md` are updated for the new layout, local development and deploy.
- **Local development:**
  - `go run .` serves `public/` and the handlers on one port (`-listen :8080` by default).
  - `miniserve public` or `python3 -m http.server -d public` still work for editing pages only.
  - `go test ./...` from the root runs every test with no network (GitHub answers are recorded).

### Zoom in: `internal/site` (the routing rule)
- For a request path, try in order `{path}`, `{path}.html`, `{path}/index.html` under `public/`. The first existing regular file is served; otherwise the request goes to the handlers. This matches the Caddy rule below, so local and production behave alike.
- Paths are cleaned (`path.Clean("/" + p)`) so no request can leave `public/`.
- The rule is written twice (Go and Caddy). Go tests pin the Go side; the Caddy block is reviewed in the same repo.
- Dynamic paths never have a static file of the same name. They live under folder names the site does not use, starting with `/builds/` and `/health`.

### Zoom in: `internal/builds` (build status)
- **Nudge:** `POST /builds/<commit>/check`.
  - `<commit>` must be 40 lowercase hex characters, otherwise 400.
  - The body is ignored. The program then asks the GitHub API itself, with a read-only token, for the `images.yaml` (and later `release.yaml`) runs and jobs of that commit.
  - At most one lookup per commit every 5 s; a burst of nudges collapses into one lookup. A nudge for a commit GitHub does not know costs one lookup and stores nothing.
  - Answers 202 at once; the lookup runs in the background.
- **Answer:** `GET /builds/<commit>`, JSON, `Cache-Control: public, max-age=30`, `Access-Control-Allow-Origin: *` (read by admin pages on any box). Format, version 1, documented in `README.md`:
  ```json
  {"schema":"statbus.builds/v1","commit":"<40 hex>","updated":"2026-10-21T13:20:00Z",
   "run":38819807364,
   "images":{"app":"published","db":"building","worker":"queued","proxy":"published","sb":"published","seed":"queued"}}
  ```
  - Image states: `queued` (run started, job not yet running), `building` (job running), `published` (job succeeded), `failed` (job failed or cancelled).
  - An unknown commit answers 404. Readers treat any answer other than 200, or an `updated` older than 5 minutes, as unknown.
- **Mapping jobs to images:** by the `images.yaml` job and matrix names (`build (app, …)` + `manifest (app)`, `retag (app)`, `seed`). An image is `published` only when its last job (manifest, retag or seed) succeeded. A job the mapping does not know is logged, never dropped silently.
- **Reruns:** the newest run attempt for the commit wins.
- **Keeping fresh without nudges:** at start, and once a minute for commits not yet fully published or failed, the program looks them up again. A lost nudge only delays an update.
- **State:** in memory, saved hourly to one file (write temp, fsync, rename) and loaded at start; entries older than 30 days are dropped. Losing the file loses nothing that GitHub cannot answer again.
- **`GET /health`:** 200 `{"status":"ok"}` once started.
- **What it never does:** decide that a release is ready. "Ready" for a box comes only from the registry or the release manifest (STATBUS-522). This answer only explains why something is not ready yet.

### Zoom in: the listener
- The program accepts a listener passed by systemd (socket activation: `LISTEN_FDS`, about 10 lines, no library), or `-listen <addr>` for a TCP port. Locally it uses the port.
- On niue the design uses a Unix socket, `/run/statbus-web/statbus-web.sock`, created by `statbus-web.socket` with owner `statbus_www`, group `caddy`, mode `0660`:
  - only Caddy can connect, and no port needs to be allocated among niue's slot ports;
  - systemd holds the socket across restarts, so a deploy does not drop requests;
  - Caddy supports it directly: `reverse_proxy unix//run/statbus-web/statbus-web.sock`.
- Socket activation works best as a system unit, so `statbus-web.service` lives in `/etc/systemd/system/` with `User=statbus_www` (no linger needed). Hardening: `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=read-only` with `ReadWritePaths=/home/statbus_www/state`, `PrivateTmp=yes`, `EnvironmentFile=/home/statbus_www/.config/statbus-web/env`.
- The owner may still choose a fixed loopback port instead; the program supports both, so the choice only changes `deploy/`.

### Zoom in: niue
```
/home/statbus_www/
  releases/<commit>/            statbus-web binary + public/, never changed after upload
  current -> releases/<commit>  the live release
  state/                        the program's hourly state file
  .config/statbus-web/env       0600: GITHUB_TOKEN (read-only, Actions read on statisticsnorway/statbus)
```
- **Caddy `www.statbus.org` block,** reviewed as `deploy/Caddyfile.www` and imported by niue's `/etc/caddy/Caddyfile`:
  ```caddy
  www.statbus.org {
  	root * /home/statbus_www/current/public
  	encode zstd gzip
  	@static file {path} {path}.html {path}/index.html
  	handle @static {
  		try_files {path} {path}.html {path}/index.html
  		file_server
  	}
  	handle {
  		reverse_proxy unix//run/statbus-web/statbus-web.sock
  	}
  }
  ```
  The `statbus.org` block (redirects for `install.sh`, `uninstall.sh`, `setup.sh`, everything else to www) is unchanged.
- **The host Caddyfile itself** is hand-edited on niue and not version-controlled. This ticket brings only the www block under review; the deploy refuses to continue when niue's copy of `Caddyfile.www` differs from the release's.

### Zoom in: deploy (`.github/workflows/deploy.yml`, on a push to master)
1. `go vet ./...`, `go test ./...`, then build a static Linux amd64 binary (`CGO_ENABLED=0`).
2. Pack `statbus-web` + `public/` into `statbus-web-<commit>.tar.gz`.
3. Stream it over SSH as `statbus_www` into `releases/<commit>/` (through a reviewed `sshdoers` door or a key restricted to that command).
4. Activate: `releases/<commit>/statbus-web activate`, which repoints `current` atomically (symlink to a temp name, then rename), restarts `statbus-web.service`, checks `/health` through the socket, and points `current` back and restarts if the check fails within 10 s.
5. Keep the five newest releases; delete older ones. A rollback is the same activate on an older release.
6. Post the Slack notice from the workflow with a GitHub secret, so niue holds no Slack token.

### Zoom in: switchover
1. **Repo, one PR:** the `git mv` commit; the program, `deploy/` and the workflow; `api/` and notes moved outside `public/`; docs updated. Merging changes nothing on niue, because the old deploy hook is removed in the same PR and the new workflow needs the niue setup first.
2. **niue, once, with the owner's go-ahead:** install `statbus-web.socket` and `.service`, create `releases/`, `state/` and the env file, run the first deploy, add the `import` of `Caddyfile.www` replacing the old www block, `caddy validate`, reload.
3. **Checks:** main pages (`/`, `/Overview/`, `/Documentation/`, `/Demo/`) answer 200; `/CLAUDE.md`, `/README.md`, `/patcepgadmin.txt` and `/api/testforupgrade.php` answer 404; `/health` answers 200; with the service stopped, the main pages still answer 200 and `/builds/<commit>` answers 502.
4. **After a week without trouble:** delete `~/statbus-web`, `~/public_html` and `~/deploy.sh`.

### Zoom in: the StatBus side
- **Nudges:** `images.yaml` ends each image job with `curl -fsS -m 10 -X POST https://www.statbus.org/builds/${GITHUB_SHA}/check || true` (the `|| true` keeps a down site from failing a build). `release.yaml` does the same when it publishes the manifest.
- **Admin page:** for an upgrade row whose images are not ready, the browser fetches `https://www.statbus.org/builds/<commit>` and shows "building", "build failed" or "queued", with the time of the answer. Any other answer, a network error or a stale `updated` shows what the box itself knows (STATBUS-522's words). No database change, and the upgrade service never reads it.

### Zoom in: secrets
- **Slack token in `~/deploy.sh`:** readable by accounts on niue only, not public. The new deploy posts from the workflow, and the file is deleted at step 4.
- **JWT in `testtoken.py`:** one user's key for dev.statbus.org in a plotting example, in an internal repo, not served. Replace it with a placeholder.

### Zoom in: later
STATBUS-344's endpoints (CI verdicts, anonymous box reports) are candidates to become further handlers in this program, under its own paths; that changes 344's earlier choice of the statbus repo and its own subdomain, so it is an owner decision below.

### Closing review
- **Memory:** none needed.
- **Documentation:** `README.md` and `CLAUDE.md` in statbus-web describe the layout, local development, the JSON format and the deploy; `doc/CLOUD.md` in statbus describes the www block and the service on niue.
- **Cleanup:** the old deploy hook, `~/statbus-web`, `~/public_html` and `~/deploy.sh` on niue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 In statbus-web, move every served file into public/ with git mv in a commit of its own; git log --follow public/index.html shows history before the move
- [ ] #2 Add main.go and internal/site; Go tests show a request is served from public/ for {path}, {path}.html and {path}/index.html, goes to the handlers otherwise, and cannot leave public/
- [ ] #3 Add internal/builds; Go tests with recorded GitHub answers show queued, building, published and failed per image, with the newest rerun winning
- [ ] #4 Go tests show a job the mapping does not know is logged and its image left unchanged, a burst of nudges for one commit makes one GitHub lookup, and a commit that is not 40 lowercase hex answers 400
- [ ] #5 A Go test shows the saved state is loaded after a restart and entries older than 30 days are dropped
- [ ] #6 Add the systemd listener and -listen; a Go test shows the program serves on a listener passed through LISTEN_FDS and on a TCP port
- [ ] #7 Add deploy/ (Caddyfile.www, statbus-web.socket, statbus-web.service) and the deploy workflow that builds the tarball, uploads to releases/<commit>/, activates with a health check and rolls back on failure; a deploy of a release whose health check fails leaves the previous release live
- [ ] #8 Update README.md and CLAUDE.md in statbus-web for the layout, local development, the JSON format and the deploy, and doc/CLOUD.md in statbus for the www block and the service
- [ ] #9 Switch niue over and record in Implementation Notes: main pages answer 200; /CLAUDE.md, /README.md, /patcepgadmin.txt and /api/testforupgrade.php answer 404; /health answers 200; with the service stopped the main pages answer 200
- [ ] #10 Make images.yaml and release.yaml nudge /builds/<commit>/check; for the next push to master, /builds/<commit> moves from queued to building to published within a minute of each job, recorded in Implementation Notes
- [ ] #11 Make the admin upgrades page show queued, building or build failed from /builds/<commit> for a row whose images are not ready, and the box's own words when the answer is missing or stale; app tests cover each case
- [ ] #12 Delete ~/statbus-web, ~/public_html and ~/deploy.sh on niue a week after the switchover; ls of /home/statbus_www shows only releases/, current, state/ and .config/ besides dotfiles
- [ ] #13 Replace the token in testtoken.py with a placeholder; the file has no string starting with eyJ
- [ ] #14 [Owner] Choose a Unix socket or a fixed loopback port on niue, and record it in Implementation Notes; the socket keeps deploy/ as written, a port changes the socket unit into a port in the service and Caddyfile.www
- [ ] #15 [Owner] Decide whether STATBUS-344's endpoints move into this program and repo, and record it in Implementation Notes; yes adds a dependency from 344 on this ticket and rewrites 344's location, no leaves 344 as designed
- [ ] #16 [Owner] Give the go-ahead for the niue switchover (criterion 9) and record it in Implementation Notes before that step runs
<!-- AC:END -->
