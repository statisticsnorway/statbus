package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// ─────────────────────────────────────────────────────────────────────────────
// STATBUS-116 AC#1 Step 3 — `sb db seed build`: the in-stage seed-build
// orchestrator. Replaces the 3 inline Dockerfile calls (create-db; migrate up
// --target seed; dump) with ONE subcommand that owns the decision + both paths.
//
// The incremental path = the full path + ONE optional restore step:
//   CreateSeedDb → [restore prior IF incremental] → migrate up --target seed → dump
// The migrate + dump are IDENTICAL in both branches; the restored ledger makes
// `migrate up` apply only the delta. So the full path stays byte-for-byte today's.
//
// IN-CODE GATES (STATBUS-116; the external SEED_INCREMENTAL_ENABLED flag was
// retired once two green oracles proved these — a same-commit build must not
// build differently based on mutable side-channel state). Incremental runs ONLY
// when ALL hold:
//   (1) a prior seed is injected (empty context ⇒ nil prior ⇒ full), AND
//   (2) SeedBuildDecision approves (AC#2 migrations-fingerprint gate), AND
//   (3) the depth cap is not reached.
// Any gate failing ⇒ full from-empty rebuild, byte-identical to the pre-AC#1
// 3-call sequence. Plus two runtime backstops proven on real VMs: a stale
// restored base surfaces ErrStaleRestoredMigration → full fallback (Part C), and
// DumpSeed's publish gate refuses to publish an inconsistent seed (Part B).
// Kill-switch = ordinary git revert of the enabling commit.
// ─────────────────────────────────────────────────────────────────────────────

// MaxIncrementalDepth caps how many incremental builds may chain off a full
// baseline before a fresh full rebuild is forced — the bound that stops drift
// accumulating across a chain (the AC#3 enforcement cadence builds on this).
// depth 0 = full baseline; an incremental build records prior depth + 1.
//
// N=5 for the first-enable period (STATBUS-116 D4, King-ruled): a full baseline
// every 5th consecutive incremental costs ~2min per 5 builds — cheap insurance
// while the feature is young. Raise it later once incremental is boring/proven.
// This is the drift bound: with releases reusing the pre-tag master-push seed
// (no release-specific full-rebuild is possible — the seed is built at
// master-push before any v* tag exists), the depth cap is the PRIMARY guarantee
// that any published seed is at most N-1 incrementals from a from-empty full.
const MaxIncrementalDepth = 5

// priorSeedDir (relative to projDir) is where the Dockerfile mounts the injected
// prior-seed build-context. The DEFAULT context is EMPTY: no seed.json there ⇒ no
// prior ⇒ full rebuild — the inert default that keeps this slice off.
const priorSeedDir = ".prior-seed"

var seedBuildCommit string

var seedBuildCmd = &cobra.Command{
	Use:   "build",
	Short: "Build the seed DB (full, or incremental restore+delta) and dump it",
	Long: `Build the statbus_seed database and dump it to .db-seed/ (STATBUS-116 AC#1).

Full path: create empty seed DB -> migrate up --target seed -> dump.
Incremental: restore the injected prior seed, then apply only the delta
migrations before dumping. Incremental runs when a prior seed is injected AND
the migrations-fingerprint gate (SeedBuildDecision) approves AND the depth cap
is not reached; otherwise it falls back to a full rebuild.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runSeedBuild(config.ProjectDir(), seedBuildCommit)
	},
}

func runSeedBuild(projDir, commit string) error {
	verbose = true // build-log parity with the prior `sb migrate up --target seed --verbose`

	// Load the injected prior seed metadata. An empty context (the default) or a
	// pre-116 seed.json (no fingerprint) ⇒ nil ⇒ SeedBuildDecision returns full.
	var prior *seedMeta
	priorJSON := filepath.Join(projDir, priorSeedDir, "seed.json")
	if _, statErr := os.Stat(priorJSON); statErr == nil {
		m, err := loadSeedMetaFrom(priorJSON)
		if err != nil {
			return fmt.Errorf("load injected prior seed metadata: %w", err)
		}
		prior = m
	}

	// STAGE correctness-gate (AC#2): honor incremental only when the fingerprint
	// decision approves and the depth bound allows it.
	incremental, reason := SeedBuildDecision(prior, projDir)
	useIncremental, newDepth, capNote := resolveSeedPath(incremental, prior)
	if capNote != "" {
		reason = capNote
	}

	// STATBUS-526 extension gate: the incremental path restores the prior
	// dump's extension catalog rows verbatim into THIS image, so it is valid
	// only when both images install the same extension versions. sql_saga 1.3's
	// catalog guard refuses rows dumped under an older version ("restore old
	// sql_saga dumps per doc/upgrade.md"); compare identities before paying the
	// restore. A query failure degrades to full — full is always correct.
	if useIncremental {
		extVersions, extErr := currentExtensionVersions(projDir)
		if extErr != nil {
			extVersions = ""
		}
		if ok, extReason := seedExtensionDecision(prior, extVersions); !ok {
			useIncremental = false
			newDepth = 0
			reason = extReason
			if extErr != nil {
				reason = fmt.Sprintf("%s (query error: %v)", extReason, extErr)
			}
		}
	}

	// LOUD decision log — the operator/CI must always see which path ran and why.
	fmt.Printf("seed build: prior-present=%v decision-incremental=%v -> PATH=%s\n  reason: %s\n",
		prior != nil, incremental, seedPathLabel(useIncremental), reason)

	seedDbName, err := loadSeedDbName(projDir)
	if err != nil {
		return fmt.Errorf("resolve seed db name: %w", err)
	}

	// ── both branches: empty seed DB from template_statbus (fresh PGDATA in-stage) ──
	if err := CreateSeedDb(projDir); err != nil {
		return fmt.Errorf("create seed db: %w", err)
	}

	// ── incremental only: restore the injected prior seed dump ──
	if useIncremental {
		priorDump := filepath.Join(projDir, priorSeedDir, "seed.pg_dump")
		fmt.Printf("seed build: restoring prior seed %s into %s (depth %d -> %d)\n",
			priorDump, seedDbName, prior.IncrementalDepth, newDepth)
		if err := restoreSeedDump(projDir, seedDbName, priorDump); err != nil {
			// STATBUS-526 backstop: a prior dump can be unrestorable on this
			// image even when every gate passed (the gates compare recorded
			// identities; the restore is where an unforeseen incompatibility
			// actually surfaces). The single-transaction restore rolled back,
			// so discard the database and rebuild FULL from empty — always
			// correct, just slower. Mirrors the stale-restored-prior fallback
			// (STATBUS-116 Part C) below.
			fmt.Printf("seed build: prior seed restore FAILED (%v) — discarding it and rebuilding FULL from empty\n", err)
			if dropErr := migrate.ExecOnDB(projDir, "postgres",
				fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE);", pgQuoteIdent(seedDbName))); dropErr != nil {
				return fmt.Errorf("drop unrestorable restored seed db: %w", dropErr)
			}
			if err := CreateSeedDb(projDir); err != nil {
				return fmt.Errorf("recreate empty seed db for restore-failure fallback: %w", err)
			}
			useIncremental = false
			newDepth = 0
		}
	}

	// ── both branches: migrate the seed DB to head. The restored ledger (if any)
	//    makes this delta-only; from empty it applies all — identical code. ──
	if err := migrateNamedDb(projDir, seedDbName, 0); err != nil {
		// STATBUS-116 Part C: a stale RESTORED prior (its ledger content_hash
		// disagrees with the on-disk files) surfaces as ErrStaleRestoredMigration
		// under the seed-build channel — no git ran. Discard the restored base and
		// rebuild FULL from empty rather than fail the build. Self-heals if the
		// ancestor walk ever lands on an inconsistent seed.
		var stale *migrate.ErrStaleRestoredMigration
		if useIncremental && errors.As(err, &stale) {
			fmt.Printf("seed build: restored prior is STALE (%v) — discarding it and rebuilding FULL from empty\n", stale)
			if dropErr := migrate.ExecOnDB(projDir, "postgres",
				fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE);", pgQuoteIdent(seedDbName))); dropErr != nil {
				return fmt.Errorf("drop stale restored seed db: %w", dropErr)
			}
			if err := CreateSeedDb(projDir); err != nil {
				return fmt.Errorf("recreate empty seed db for full fallback: %w", err)
			}
			if err := migrateNamedDb(projDir, seedDbName, 0); err != nil {
				return fmt.Errorf("full-fallback migrate seed db up: %w", err)
			}
			newDepth = 0 // a from-empty full rebuild is a depth-0 baseline
		} else {
			return fmt.Errorf("migrate seed db up: %w", err)
		}
	}

	// ── both branches: dump + record the (bounded) incremental depth ──
	if _, err := DumpSeed(projDir, commit, newDepth); err != nil {
		return fmt.Errorf("dump seed: %w", err)
	}

	// Asserts mirrored from the prior inline Dockerfile step.
	for _, f := range []string{"seed.pg_dump", "seed.json"} {
		p := filepath.Join(projDir, ".db-seed", f)
		if fi, statErr := os.Stat(p); statErr != nil || fi.Size() == 0 {
			return fmt.Errorf("seed build produced no %s (%v)", p, statErr)
		}
	}

	// STATBUS-481: never publish a seed that cannot be restored, or whose
	// restore cannot be dumped and restored again. Fails the build loudly
	// here instead of surfacing later as a silent FULL_REPLAY fallback.
	if err := verifySeedRoundTrip(projDir, seedDbName); err != nil {
		return err
	}
	return nil
}

// resolveSeedPath is the PURE routing decision (no I/O): compose the AC#2
// fingerprint decision with the depth bound.
//   - useIncremental only if SeedBuildDecision said incremental AND a prior exists;
//   - forced back to full at the depth cap (newDepth 0, capNote set);
//   - otherwise newDepth = prior.IncrementalDepth + 1.
//
// Full always yields newDepth 0 (a fresh full baseline). prior is dereferenced
// only on the incremental branch, where SeedBuildDecision guarantees it non-nil.
func resolveSeedPath(incremental bool, prior *seedMeta) (useIncremental bool, newDepth int, capNote string) {
	if !incremental || prior == nil {
		return false, 0, ""
	}
	if prior.IncrementalDepth+1 >= MaxIncrementalDepth {
		return false, 0, fmt.Sprintf("incremental depth cap reached (prior depth %d + 1 >= %d) — forcing full baseline", prior.IncrementalDepth, MaxIncrementalDepth)
	}
	return true, prior.IncrementalDepth + 1, ""
}

func seedPathLabel(incremental bool) string {
	if incremental {
		return "INCREMENTAL (restore prior + delta-migrate)"
	}
	return "FULL (from empty)"
}

// currentExtensionVersions returns the image's extension identity: the sorted,
// comma-joined "name=default_version" list from pg_available_extensions — what
// CREATE EXTENSION installs on this image, independent of any database's
// extversion. Queries the maintenance DB (any DB sees the same filesystem);
// works under DOCKER_PSQL=0 in the hermetic seed-builder like DumpSeed does.
func currentExtensionVersions(projDir string) (string, error) {
	return migrate.QueryDB(projDir, "postgres",
		"SELECT string_agg(name || '=' || default_version, ',' ORDER BY name) FROM pg_available_extensions",
		"-t", "-A")
}

// seedExtensionDecision is the STATBUS-526 extension half of the incremental
// gate: restoring the prior seed's dump into the current image replays the
// prior image's extension catalog rows, valid only when both images install
// the same extension versions. Falls back to FULL on any uncertainty (a
// pre-526 seed.json lacking the field, or an unavailable current identity).
// Pure: unit-testable (TestSeedExtensionDecision_*).
func seedExtensionDecision(prior *seedMeta, current string) (ok bool, reason string) {
	if prior.ExtensionVersions == "" {
		return false, "prior seed predates extension-version recording (STATBUS-526) — full rebuild from empty"
	}
	if current == "" {
		return false, "current image's extension versions unavailable — full rebuild from empty"
	}
	if prior.ExtensionVersions != current {
		return false, fmt.Sprintf("extension versions changed since the prior seed (%s -> %s) — full rebuild from empty",
			prior.ExtensionVersions, current)
	}
	return true, ""
}

// restoreSeedDump pg_restores dumpPath into dbName using HOST pg_restore
// (migrate.PgRestoreCommand) — the in-stage-safe variant of restoreVerifyDB
// (which uses `docker compose exec`, unavailable in the build stage). Same atomic
// --single-transaction contract via runPgRestoreAtomic (fails loud on any error).
func restoreSeedDump(projDir, dbName, dumpPath string) error {
	f, err := os.Open(dumpPath)
	if err != nil {
		return fmt.Errorf("open prior seed dump %s: %w", dumpPath, err)
	}
	defer func() { _ = f.Close() }()
	pgRestorePath, prefix, env, err := migrate.PgRestoreCommand(projDir)
	if err != nil {
		return fmt.Errorf("resolve pg_restore: %w", err)
	}
	args := append(append([]string{}, prefix...),
		"-U", "postgres", "--clean", "--if-exists", "--no-owner", "--disable-triggers",
		"--single-transaction", "-d", dbName)
	cmd, buildErr := migrate.Command(projDir, pgRestorePath, args...)
	if buildErr != nil {
		return fmt.Errorf("construct seed build restore: %w", buildErr)
	}
	cmd.Env = env
	cmd.Stdin = f
	if err := runPgRestoreAtomic(cmd, "seed build restore prior"); err != nil {
		return err
	}
	// STATBUS-316: this restore's own completion point.
	return normalizeAllSequences(projDir, dbName)
}

// loadSeedMetaFrom reads and parses a seed.json at an arbitrary path (the
// projDir-relative loadSeedMeta's sibling, for the injected prior-seed context).
func loadSeedMetaFrom(jsonPath string) (*seedMeta, error) {
	data, err := os.ReadFile(jsonPath)
	if err != nil {
		return nil, fmt.Errorf("read seed.json: %w", err)
	}
	var meta seedMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, fmt.Errorf("parse seed.json: %w", err)
	}
	return &meta, nil
}

func init() {
	seedBuildCmd.Flags().StringVar(&seedBuildCommit, "commit", "",
		"commit SHA to stamp into seed.json (the hermetic build has no .git)")
	seedCmd.AddCommand(seedBuildCmd)
}
