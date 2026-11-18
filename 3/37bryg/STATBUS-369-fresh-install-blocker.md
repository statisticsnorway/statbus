# STATBUS-369: fresh smoke installation blocked by config placement

Status: **Historical finding, resolved on this branch after owner approval.**

The final follow-up replaces the initial home-filename prototype with explicit
STATBUS_ENV_CONFIG / STATBUS_USERS_FILE inputs and Go-owned strict validation.
The line references and checks below describe the pre-fix investigation, not
the current installer. Happy-upgrade retains the approved v2026.09.0 baseline
exception until the first stable carrying the new seam.

Inspected `install.sh` in full on df6727be4 plus the rebased wyvern changes.
Neither smoke cell has yet been converted to the required FRESH path. The
inherited happy-install helper still pre-clones and therefore exercises RESCUE.
Its offline tests do not prove the owner's fresh-install claim. No workaround
or product change has been made.

## Exact branch and missing seam

Line numbers below refer to `install.sh` at this revision:

- Lines 89-100 accept only `--version`, `--channel`, `--commit`, and
  `--trust-github-user` (plus rejection of the removed `--prerelease`). Despite
  the comment at 70-71, arbitrary flags are not forwarded. `--non-interactive`
  and `--config` both print `Unknown option` and exit 1 before prerequisites.
  `--trust-github-user jhf` is explicitly forwarded at line 98.
- Line 294 unconditionally sets `STATBUS_DIR="${HOME}/statbus"`. No external
  config file, config directory, or config-copy hook is consumed by this script.
- Lines 580-618 select RESCUE when `~/statbus/.git` is a directory. Thus the
  inherited helper's pre-clone selects RESCUE, irrespective of an empty VM.
- Lines 619-622 select FRESH otherwise and call `statbus_git_clone`.
- Crucially, lines 497-500 REMOVE an existing destination without `.git`
  before invoking git clone. Pre-placing `.env.config` and `.users.yml` in
  `~/statbus` without a repository does not select RESCUE. It selects FRESH
  and deletes those files. This is more severe than a nonempty-clone refusal.
- Lines 632-648 finish checkout, move the binary, change directory and release
  the mutex. No configuration import happens between clone and line 654,
  which calls `./sb install $SB_INSTALL_ARGS`.

The downstream product corroborates the blocker: `cli/cmd/install.go:266-273`
infers non-interactive mode from non-character-device stdin. Its config creation
at lines 1207-1216 looks for the installation directory's `.env.config` and
refuses creation in non-interactive mode, instructing the operator to pre-create
that same file. There is no supported placement seam in this bootstrap flow.
Omitting the unsupported flag does not fix the missing configuration.

No seam was used. Pre-cloning, replacing git/curl with wrappers, racing a copy
against the clone, or launching `./sb install` separately would evade the claim.
A supported product config import/preservation contract is needed before the
harness can implement these two non-interactive FRESH smoke cells faithfully.

## Required claims remain unchanged

1. Happy-install ships the candidate's install.sh as a file onto an empty,
   prepared box, then installs the explicit candidate tag through FRESH.
2. Happy-upgrade ships the same script and uses FRESH with no version argument.
   The installed stable release must agree with both GitHub `/releases/latest`
   and `select_release_baseline_from_repo`, with both values printed on mismatch.
   Only then may the existing schedule-to-candidate steps run.

The release-ladder rows and scenario headers were not changed to claim these
unimplemented behaviors. Candidate-specific fresh-install coverage from the
second inherited commit is retained. Baseline-selection coverage still requires
review when the blocked smoke implementation resumes.

## This continuation's validation

- Rebase onto df6727be4 completed. The single vm-bootstrap conflict retained
  the master's fail-loud config copies and the inherited install command choice.
- `bash -n install.sh test/install-recovery/lib/vm-bootstrap.sh`: PASS.
- `git diff --check`: PASS.
- `bash install.sh --non-interactive`: `Unknown option: --non-interactive`, exit 1.
- `bash install.sh --config /tmp/env-config`: `Unknown option: --config`, exit 1.
- Rebased commits have valid signing output.

Raw check output: scratch `tmp/STATBUS-369-blocker-checks.log`.
Harness tests, discovery (`--print-selected`, `--list`), shellcheck delta and Go
release tests were NOT rerun in this continuation: the explicit product-finding
stop was reached before implementation. The prior handoff's test results are
historical only, not validation of the required new shape. No Docker, database,
VM, push, amend, or main-working-tree modification was performed.

## Assertions requiring a real VM after the product blocker is resolved

- Both prepared boxes actually take FRESH with the candidate's shipped script,
  its own clone and release-asset download, and readable intended config/users.
- Candidate `sb --version` equals candidate tag plus short SHA.
- Newest unfiltered `public.upgrade` row equals tag|full SHA|completed.
- No-version installation autonomously chooses GitHub latest stable and agrees
  with the repository baseline selector at observation time.
- Existing schedule-to-candidate upgrade completes with the intended identity.
- Health, step 9, upgrade-service completion and active systemd service checks.
- Published assets/images are available and install successfully without builds.

Mocked or syntax tests cannot establish any of these on-box assertions.
