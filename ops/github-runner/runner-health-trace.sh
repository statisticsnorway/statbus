#!/usr/bin/env bash
# runner-health-trace.sh — ONE-TIME diagnostic capture for STATBUS-069.
#
# PURPOSE: learn the niue self-hosted runner's ACTUAL log/process signatures so the
# health probe (runner-health.sh, layer b) pins its "GitHub-session-fresh" signal to
# OBSERVED behavior — not to a guessed line. The architect ruling was explicit: do
# NOT pin "Listening for Jobs" (emitted once per session → a healthy idle runner has
# no recent line = false OFFLINE; and _diag keeps writing during disconnect-retry
# loops = false HEALTHY). This capture surfaces the real idle cadence AND the
# disconnect/reconnect signature so the signal + window can be chosen from evidence.
#
# WHERE: run on niue as a user in the docker group (github-runner, or root).
# HOW:   bash runner-health-trace.sh 2>&1 | tee /tmp/runner-health-trace.out
#        then paste /tmp/runner-health-trace.out back to the engineer.
#
# ⚠️  DISRUPTIVE STEP: Part D disconnects the runner container from its network for
#     ~60s to record the disconnect signature, then reconnects it. During that window
#     the runner cannot receive jobs (CI briefly blind). It auto-reconnects; total
#     added blind time ≈ 80s. If a job is running RIGHT NOW, wait — Part D refuses
#     while Runner.Worker is alive (a job is executing). Parts A–C are read-only.
set -uo pipefail

C=gha-runner   # container_name from ops/github-runner/docker-compose.yml

line() { printf '\n===== %s =====\n' "$1"; }

line "A. container state (layer-a signal: is it running at all)"
docker inspect -f 'Running={{.State.Running}} Status={{.State.Status}} StartedAt={{.State.StartedAt}} RestartCount={{.RestartCount}}' "$C" \
  || { echo "docker inspect failed — is the container present / do you have docker access?"; exit 1; }

line "B. idle log cadence — what a (presumably healthy) runner writes over 30m"
echo "# reading 'docker logs $C --since 30m --timestamps' (tail 60):"
docker logs "$C" --since 30m --timestamps 2>&1 | tail -60
echo "# --- last 40 lines regardless of age (in case idle writes nothing in 30m): ---"
docker logs "$C" --timestamps 2>&1 | tail -40

line "C. runner internal state — Listener process + _diag heartbeat"
echo "# processes inside the container (Runner.Listener = connected long-poll; Runner.Worker = a job running):"
docker exec "$C" sh -c 'ps -eo pid,etime,args 2>/dev/null | grep -i "Runner\.\(Listener\|Worker\)" | grep -v grep' \
  || echo "(no Runner.Listener/Worker matched — note this)"
echo "# newest _diag logs (the listener writes connection/heartbeat here):"
docker exec "$C" sh -c 'ls -lat _diag/ 2>/dev/null | head -6; echo "---"; tail -30 "$(ls -t _diag/Runner_*.log 2>/dev/null | head -1)" 2>/dev/null' \
  || echo "(no _diag/Runner_*.log found — note this)"

line "D. DISCONNECT TEST (disruptive ~80s) — the offline/reconnect signature"
if docker exec "$C" sh -c 'ps -e 2>/dev/null | grep -q "Runner.Worker"'; then
  echo "SKIPPED: a job is running now (Runner.Worker alive). Re-run Part D when idle."
  exit 0
fi
net="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$C" | awk '{print $1}')"
echo "# container network: ${net:-<none>}"
if [ -z "${net:-}" ]; then echo "could not resolve network — skipping Part D"; exit 0; fi
echo "# disconnecting for 60s (runner goes offline to GitHub)..."
docker network disconnect "$net" "$C"
sleep 60
echo "# --- logs DURING the 60s disconnect (the OFFLINE signature to detect): ---"
docker logs "$C" --since 75s --timestamps 2>&1 | tail -40
echo "# reconnecting..."
docker network connect "$net" "$C"
sleep 25
echo "# --- logs AFTER reconnect (recovery signature): ---"
docker logs "$C" --since 30s --timestamps 2>&1 | tail -40
line "DONE — paste this whole output back."
