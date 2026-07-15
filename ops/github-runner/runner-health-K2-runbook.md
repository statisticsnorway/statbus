# K2 runbook — provision the runner-health canary probe (STATBUS-069)

**One session, ~5 minutes, on niue as root.** This is the King's second touchpoint (K2).
Every byte below was reviewed and committed beforehand — **nothing is composed in the
session** (STATBUS-167 one-session discipline). It installs the three artifacts the
hosted `runner-online` canary depends on:

1. the **probe script**, root-owned at a non-checkout path;
2. a **dedicated keypair** (private half → repo secret, public half → `github-runner`'s
   authorized_keys, forced through sshdo);
3. one **sshdoers allowlist line** (that key may run exactly the probe, nothing else).

> **TEMPLATE status (STATBUS-069 AC#1).** The *structure* below is final. The one thing
> not yet frozen is the **contents of `runner-health.sh`** — layer (b) is calibrated from
> K1's trace paste in AC#3/S5. Run the FINAL committed copy at K2; the steps do not change.

---

## Why the probe script must be root-owned and NOT run from the git checkout

`github-runner` has docker access, which is root-equivalent on the shared box. If the
probed command lived in a git checkout, anyone with master-push could rewrite it and have
it executed with that access. So the standing command is installed **root-owned at
`/usr/local/sbin/statbus-runner-health`** — same trust class as sshdo/sshdoers, kept
current by re-provisioning from a reviewed commit, never by `git pull`. (Running the
read-only **trace** from a checkout at K1 is fine — the King reads what he runs and is the
human in control; this custody rule is only about the *unattended* CI-invoked command.)

---

## Preconditions

- Root shell on niue.
- A checkout of the **reviewed commit** readable somewhere (note its SHA) — used only as
  the byte source and for the visual diff. Example: `REPO=~statbus_dev/statbus` (or a fresh
  `git clone` + `git checkout <reviewed-sha>`). This checkout is NOT where the script runs from.
- `gh` authenticated for `statisticsnorway/statbus` (for `gh secret set`), or use the
  GitHub UI to set the secret.

```bash
REPO=~statbus_dev/statbus          # adjust to the readable reviewed checkout
SRC="$REPO/ops/github-runner/runner-health.sh"
```

---

## Steps

### 1. Install the probe script root-owned, then diff to prove it is byte-identical

```bash
install -o root -g root -m 0755 "$SRC" /usr/local/sbin/statbus-runner-health
diff "$SRC" /usr/local/sbin/statbus-runner-health && echo "OK: byte-identical to the reviewed copy"
```

Root-owned + non-checkout path means `github-runner`'s docker access cannot rewrite it.
The `diff` is the visual confirmation there was no tampering.

### 2. Mint the dedicated probe keypair (ed25519, no passphrase — it is a CI secret)

```bash
umask 077
ssh-keygen -t ed25519 -N '' -C 'runner-health-probe statbus-069' -f /tmp/runner-health-key
```

### 3. Authorize the PUBLIC half on `github-runner`, forced through sshdo

The `command="…"` prefix is **per-key**: it restricts ONLY this key, so `github-runner`'s
other keys (if any) are untouched. The sshdo binary lives at **`/usr/local/bin/sshdo`** on
niue (root-verified — every slot key uses exactly that path). Confirm the path only:

```bash
# CONFIRM the sshdo PATH matches the prefix below (expect .../usr/local/bin/sshdo...).
# Do NOT copy the whole live line — the fleet's slot keys are BARE (command="…sshdo"
# with no restrictions); this probe key is hardened on purpose (architect ruling: the
# no-* options are free protection for the most-exposed key class, a repo-secret key).
grep -o 'command="[^"]*sshdo[^"]*"' /home/statbus_demo/.ssh/authorized_keys | head -1
```

Canonical hardened prefix — use these bytes verbatim (the path is already correct; the
grep above only confirms it):

```bash
prefix='command="/usr/local/bin/sshdo",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc'

install -d -o github-runner -g github-runner -m 700 /home/github-runner/.ssh
printf '%s %s\n' "$prefix" "$(cat /tmp/runner-health-key.pub)" >> /home/github-runner/.ssh/authorized_keys
chown github-runner:github-runner /home/github-runner/.ssh/authorized_keys
chmod 600 /home/github-runner/.ssh/authorized_keys
```

### 4. Add the one sshdoers allowlist line

That key may run exactly the probe, nothing else. Place it in the CI section of
`/etc/sshdoers`, next to the `ci-notify.sh` entries:

```bash
echo 'github-runner: /usr/local/sbin/statbus-runner-health' >> /etc/sshdoers
```

### 5. Smoke-test the full SSH path BEFORE destroying the private key

Prove the key + sshdo + script agree end to end. sshdo must PERMIT the probe and REFUSE
anything else:

```bash
# permitted — expect the probe's one-line verdict and its exit code:
ssh -i /tmp/runner-health-key -o StrictHostKeyChecking=accept-new \
    github-runner@localhost /usr/local/sbin/statbus-runner-health; echo "probe exit=$?"

# refused — sshdo must reject a non-allowlisted command. Grep for the EXACT string
# sshdo emits ('not in allowlist'); a bare `|| echo OK` would false-pass on a mere
# transport failure (host down, key wrong) that never reached sshdo at all.
if ssh -i /tmp/runner-health-key -o StrictHostKeyChecking=accept-new \
       github-runner@localhost id 2>&1 | grep -q 'not in allowlist'; then
  echo "OK: sshdo refused a non-allowlisted command"
else
  echo "FAIL: expected 'not in allowlist' — do NOT proceed; sshdo did not gate this key"
fi
```

(If `localhost` is not the right hostname for the box's sshd, use `niue.statbus.org`.)

### 6. Publish the PRIVATE half as the repo secret and SHRED the local copy

```bash
gh secret set RUNNER_HEALTH_SSH_KEY --repo statisticsnorway/statbus < /tmp/runner-health-key
shred -u /tmp/runner-health-key /tmp/runner-health-key.pub
```

The private key now exists only as the GitHub secret (same custody class as the deploy
key) — revocable server-side any time by removing the authorized_keys line; no expiry
lifecycle, no personal access token.

---

## Done → hand back to the engineer

The canary is NOT wired yet. The engineer re-adds the `runner-online` job (self-hosted
legs `needs:` it) in AC#5; the foreman pushes; that push is the oracle — a green canary
gating the self-hosted legs closes the canary half of STATBUS-069.

## Rollback (any time)

```bash
sed -i '\#github-runner: /usr/local/sbin/statbus-runner-health#d' /etc/sshdoers
# remove the probe key line from /home/github-runner/.ssh/authorized_keys (by its comment)
rm -f /usr/local/sbin/statbus-runner-health
gh secret delete RUNNER_HEALTH_SSH_KEY --repo statisticsnorway/statbus
```

The hosted CI path keeps working throughout; only the liveness canary is affected.
