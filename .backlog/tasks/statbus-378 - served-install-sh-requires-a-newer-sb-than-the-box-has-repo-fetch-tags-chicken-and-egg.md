---
id: STATBUS-378
title: >-
  Served install.sh requires a newer sb than the box has (repo-fetch --tags
  chicken-and-egg)
status: To Do
assignee: []
created_date: '2026-09-19 10:43'
updated_date: '2026-09-19 10:43'
labels:
  - install
  - recovery
  - release
  - cli
  - compatibility
  - harness
dependencies: []
references:
  - 9e57c1722
  - 7244856d5
priority: medium
type: bug
ordinal: 1
---

## Incident (2026-09-19)

On an rc.18 box, the rescue bootstrap for rc.19 failed:

    bash install.sh --version v2026.09.1-rc.19
    Error: unknown flag: --tags ... sb repo-fetch

The served master `install.sh` at `9e57c1722` invokes the box's existing
`./sb repo-fetch --tags` before it downloads or installs the new target binary.
rc.18's `repo-fetch` predates the `--tags` option. The script therefore requires
the capability it is supposed to deliver, creating a bootstrap
chicken-and-egg failure precisely on the old boxes that need rescue.

## Compatibility invariant

The served `install.sh` is an external compatibility surface. Before it has
installed the target `sb`, it may depend only on behavior available in the
**oldest supported installed release**.

It must not assume that the box binary accepts newer commands, flags, output
formats, config fields, or recovery semantics. Adding a feature to `sb` and
immediately calling it from the served script is unsafe until every supported
source release already has that feature.

For tag discovery, either:

1. Fetch tags with plain Git during the compatibility-sensitive bootstrap
   phase; or
2. Probe `./sb repo-fetch --help` and use `repo-fetch --tags` only when the
   installed binary advertises that exact flag, with a plain-Git fallback.

The probe itself must be compatible with the oldest supported binary and must
not mistake command failure, localized/noisy output, or an unrelated `--tags`
string for support.

## Required proof boundary

The release/install harness must exercise rescue bootstrap **from the previous
stable release**, using the served target `install.sh` and the previous
release's on-disk `sb`. A test that runs the target script with the target
binary does not cover this defect.

The scenario should retain enough evidence to identify:

- source release and source `sb` version;
- exact served `install.sh` revision or target version;
- commands executed before the target binary is installed;
- tag-fetch path selected by capability detection;
- target binary installation and final service readiness.

## Done when

1. `install.sh` performs target tag discovery without requiring any `sb`
   command or flag newer than the oldest supported installed release.
2. If `repo-fetch --tags` remains an optimization, the script probes support
   before invocation and has a tested plain-Git fallback.
3. A static or executable compatibility check inventories every pre-download
   `./sb` invocation in `install.sh` and rejects dependencies newer than the
   declared oldest supported release.
4. The install-recovery harness boots the previous stable release, preserves
   its old on-disk binary, runs the served rescue bootstrap for the candidate,
   and reaches the candidate successfully.
5. The harness includes a source binary whose `repo-fetch` rejects `--tags` and
   proves that the fallback path fetches the requested version.
6. Failure output distinguishes an unsupported old-binary capability from Git,
   network, authentication, and missing-tag failures.
7. Release documentation states the served-script compatibility invariant and
   identifies the oldest supported source release used by the harness.
