---
id: STATBUS-440
title: harness process-log-registration lint fails on 3-postswap-mid-tx-kill.sh:89
status: To Do
priority: low
---

## Issue

`./dev.sh test-harness` fails on clean master (c893c1f02 and 4f2fad7d5,
Darwin local) with:

  FAIL: unregistered harness process logs:
    scenarios/3-postswap-mid-tx-kill.sh:89: .log is not registered near its process launch
    scenarios/3-postswap-mid-tx-kill.sh:89: log redirection is not registered

## Evidence

Reproduced on a clean checkout (git stash → fail → git stash pop), so it is not
caused by the rc.07 fleet-assertion repairs. The scenario is not in the default
fleet catalogue (it did not run in the rc.07 fleet), which is why the red lint
did not gate anything. Unknown whether Darwin-local-only or genuine master
breakage; harness-selftest.yaml in CI is green, so possibly
environment-specific (the local run builds sb from source on Darwin).

## Principled fix

Register the launched process's log per the harness contract
(harness_register_log near the launch), or establish why the lint misfires on
this launch shape and teach the lint the pattern. First reproduce on Linux to
rule out a Darwin artifact.
