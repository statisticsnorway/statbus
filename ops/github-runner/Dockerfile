# statbus-gha-runner — a containerized GitHub Actions self-hosted runner for the
# workflows that SSH into niue (the upgrade poke to the cloud slots, pg_regress).
# It runs those jobs FROM niue instead of from a GitHub-hosted Azure runner, whose
# IP ranges intermittently sit on niue's CrowdSec community blocklist and get their
# SSH dropped — so our own CI can't reach our own box. Moving the SSH *client* onto
# the box sidesteps the public SSH gate entirely; the box's SSH protection stays
# fully enforced for the outside world. Design: doc-026 (STATBUS-069).
#
# The base image deliberately tracks :latest rather than a digest pin (doc-026
# delta 3): the runner self-updates in place anyway (GitHub refuses connections
# from old runner versions), so a digest would pin nothing that matters; the weekly
# gha-runner-upgrade.timer recreate is the deliberate refresh. Supply-chain pinning
# lives where the third-party risk actually is — marketplace ACTIONS pinned to
# commit SHAs in the workflows (doc-026 delta 4).
FROM ghcr.io/actions/actions-runner:latest

# The stock runner image is minimal. Our niue-bound jobs only SSH — so we add just
# the SSH client + TLS roots. Extend this list ONLY when a job proves the need
# (doc-026 §1). NB: our jobs must use raw `ssh` run steps, NOT a Docker-based
# marketplace action (e.g. appleboy/ssh-action) — this runner has no docker socket
# by design (doc-026 §2), so a Docker container action cannot run here. openssh-client
# is exactly what makes the raw-ssh path work.
USER root
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-client ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh

# Pre-create EVERY volume mountpoint OWNED BY the non-root `runner` user, BEFORE
# `USER runner` (doc-026 gotcha 7a): a named volume initialized from the image
# inherits the mountpoint's ownership; a mountpoint left root-owned makes the
# volume root-owned, and the non-root runner then cannot write it — which on the
# prior art produced an "already configured" restart loop plus an
# UnauthorizedAccessException in _work. runner's uid/gid in this image is 1001.
RUN chmod 0755 /entrypoint.sh \
 && mkdir -p /runner-state /home/runner/_work \
 && chown runner:runner /runner-state /home/runner/_work

USER runner
ENTRYPOINT ["/entrypoint.sh"]
