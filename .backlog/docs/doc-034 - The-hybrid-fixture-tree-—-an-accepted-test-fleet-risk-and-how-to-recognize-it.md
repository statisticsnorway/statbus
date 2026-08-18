---
id: doc-034
title: The hybrid fixture tree — an accepted test-fleet risk and how to recognize it
type: other
created_date: '2026-08-18 20:20'
---
## Purpose

This records an accepted, unguarded risk in the install-recovery test fleet, so that when its failure eventually fires it is recognized in minutes instead of triaged from scratch. It affects only test infrastructure — production boxes never see fixture branches.

## The situation

Since STATBUS-236's remedy (Shape A, landed 65fa3fd09, 2026-08-18), the arc harness's fixture branches align their `.github/workflows/` content with the default branch before pushing — required, because the harness token cannot push a workflow tree that differs from master (GitHub's rule (T), measured empirically by the STATBUS-236 probe, run 32165178946).

That makes every fixture branch a HYBRID: `gh workflow run --ref <fixture-branch>` executes the workflow file FROM that ref, so the fixture image build runs MASTER's CI definitions against the RC's scripts and product tree.

## When it bites

Only when master's CI grows a dependency on a file the candidate's tree lacks — i.e. someone lands a master workflow change expecting a new checked-in file while an RC cut earlier is still in its test cycle. Example of the class: master's images.yaml hard-fails without ops/release/ci-exempt-paths.txt (rc.04's tree had it, so it never fired). The window recurs briefly in every RC cycle; it does not depend on anyone installing or re-testing old releases.

## Why there is deliberately NO guard (architect ruling, STATBUS-236)

The failure mode is a LOUD CI failure — a file master's CI expects is simply absent — never a silent wrong verdict. A guard would have to enumerate every file master's CI might read from an arbitrary older tree: unbounded, brittle, and it would rot faster than the thing it guards.

## What to do when it fires

A fixture image build failing with a missing-file error on an RC is THIS, not an infrastructure fault. Check what file master's CI newly expects and when that expectation landed relative to the RC's cut. The remedy is judged fresh — usually cutting a newer RC, never teaching master's CI about old trees.

## Provenance

STATBUS-236 (mechanism, probe, remedy) and STATBUS-238 (this record, originally a task — converted to this doc 2026-08-18 at the King's direction so a permanent design property does not sit as an open task).
