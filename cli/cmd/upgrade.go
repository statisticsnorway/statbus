package cmd

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/syslog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/selfupdate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// resolveOperator returns the operator name STATBUS-317 records for a
// state-transition verb (schedule, dismiss, apply, apply-latest): the
// --operator flag if given, otherwise an interactive prompt IF AND ONLY IF
// a terminal is present, otherwise empty (the trigger then records
// actor_source='absent' — the honest answer, not a failure).
//
// TRAP (architect, verbatim): "a naive prompt would wedge the deploy path.
// The CI door is ./sb upgrade apply <sha> over sshdo, entirely
// non-interactive. A prompt that blocks there hangs the automatic canary
// forever. The TTY test is not politeness; it is what keeps this from
// breaking the chain." isTerminal() (cli/cmd/psql.go) is the ONLY thing
// standing between this prompt and that hang — every call site MUST go
// through this function rather than prompting directly, so the check can
// never be forgotten at one of them.
func resolveOperator(flagValue string) string {
	if flagValue != "" {
		return flagValue
	}
	if !isTerminal() {
		return ""
	}
	fmt.Print("Operator name, for the audit log (Enter to skip): ")
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	return strings.TrimSpace(line)
}

// runUpgradePsql runs a SQL string using psql with connection args from .env.
func runUpgradePsql(sql string, extraArgs ...string) ([]byte, error) {
	projDir := migrate.PsqlProjectDir()
	psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
	if err != nil {
		return nil, err
	}
	args := append(prefix, extraArgs...)
	// SQL goes via stdin so psql's variable-substitution preprocessor runs.
	// `-c` bypasses the preprocessor and sends the string literally to the
	// server, which fails on :'var' with "syntax error at or near ':'".
	c := exec.Command(psqlPath, args...)
	c.Env = env
	c.Dir = projDir
	c.Stdin = strings.NewReader(sql)
	return c.CombinedOutput()
}

var upgradeCmd = &cobra.Command{
	Use:   "upgrade",
	Short: "Manage software upgrades",
	Long: `Manage the upgrade service and software releases.

Look:
  check       Fetch GitHub releases and register what it finds
  list        Show registered candidates and their status

Install (you ask; the service performs the work):
  apply       Install EXACTLY this version — register + schedule in one command
  apply-latest Install whichever version is newest on this box's channel

Compose it yourself, when you want the steps apart:
  register    Record a release tag or commit as a candidate (state=available)
  schedule    Queue an ALREADY-REGISTERED candidate to run (fails if not registered)
  dismiss     Mark a candidate as never to be offered or installed automatically

Run:
  service     Run the upgrade service (long-running, typically via systemd)`,
}

var upgradeCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Fetch GitHub releases and register them as candidates",
	Long: `Fetches releases from GitHub, prints them, and registers each release
newer than the running version as an upgrade candidate (state='available')
through the same path discovery uses. Subsumes the old 'discover' verb — the
service still auto-discovers on its own poll using the same register path.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// STATBUS-308: an operator running `check` by hand is often doing so
		// BECAUSE automatic checking appears to have stopped. If the box cannot
		// follow its channel at all, say so before showing results that would
		// otherwise look reassuring.
		announceUnitFloor()
		return newUpgradeService(config.ProjectDir()).RunCheck(context.Background())
	},
}

var upgradeRegisterCmd = &cobra.Command{
	Use:   "register <target>",
	Short: "Record a release tag or commit as an upgrade candidate",
	Long: `Record a target as an upgrade candidate (state='available') and poke the
upgrade service to prepare it (pull images, verify build artifacts).

The target is a release tag, an 8-char commit_short, OR a full 40-char commit
SHA — git-resolved to the canonical commit. register is the prerequisite for
schedule: you cannot schedule a target whose candidate row does not exist.
Once the service reports the candidate ready, run
'./sb upgrade schedule <target>' to queue it.

Examples:
  sb upgrade register v2026.03.1
  sb upgrade register abc1234f
  sb upgrade register 1e5b5434d25a8b1efca94901fc0a9d4ddb2f64f5`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		return newUpgradeService(config.ProjectDir()).RunRegister(context.Background(), args[0])
	},
}

var upgradeApplyCmd = &cobra.Command{
	Use:   "apply <target>",
	Short: "Install exactly this version on this box",
	Long: `Install EXACTLY the named version — the whole operation in one command.

This is the general verb for "put this version on this box". It registers the
target if the box does not already know it, then schedules it; the upgrade
service does the rest, inside its usual backup / migrate / health-check /
rollback-on-failure envelope.

The target is a release tag, an 8-character commit_short, or a full 40-character
commit SHA — the same vocabulary register, schedule and dismiss accept.

It installs WHAT YOU NAMED, and nothing else. Use it whenever the version
matters — a rollback to a known-good release, reproducing a report against one
specific build, or driving a box to the exact candidate under test. If instead
you want whichever version is newest on this box's channel, that is the
apply-latest subcommand.

Examples:
  sb upgrade apply v2026.08.1
  sb upgrade apply abc1234f
  sb upgrade apply --recreate v2026.08.1`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		recreate, _ := cmd.Flags().GetBool("recreate")
		ctx := context.Background()
		svc := newUpgradeService(config.ProjectDir())
		// STATBUS-317: apply has no --operator flag of its own (it is the CI
		// door — see resolveOperator's own TRAP comment) — an interactive
		// human still gets prompted; CI's non-interactive invocation gets
		// 'absent', correctly, because there is no TTY to prompt.
		if err := svc.RunApply(ctx, args[0], recreate, resolveOperator("")); err != nil {
			return err
		}
		// STATBUS-170/-260: emit the 40-hex commit this command actually acted
		// on, in the same greppable one-liner apply-latest uses.
		//
		// For apply-latest the emit TELLS the caller what it resolved, because
		// only the box knew. Here the caller already named the target, so the
		// emit exists to be CHECKED against that name — deploy-to-dev asserts
		// requested == deployed and fails loudly if they differ. Under
		// candidate-addressing they can only differ if something resolved a
		// target other than the one asked for, which is exactly the defect this
		// work removes, so it must be an error rather than a quiet preference
		// for whichever value is at hand.
		sha, rerr := svc.ResolveToCommit(ctx, args[0])
		if rerr != nil {
			// Non-fatal: the install IS scheduled, and failing here would report
			// a failure for an operation that succeeded. But say it plainly —
			// the caller's equality guard has nothing to compare and must know
			// that rather than infer agreement from silence.
			fmt.Fprintf(os.Stderr, "warn: could not resolve %s to a commit — deployed_commit line omitted; any caller checking requested-vs-deployed cannot verify this run: %v\n", args[0], rerr)
			return nil
		}
		fmt.Println(deployedCommitLine(string(sha)))
		return nil
	},
}

var upgradeDismissCmd = &cobra.Command{
	Use:   "dismiss <target>",
	Short: "Mark a candidate as dismissed so it is never offered or installed automatically",
	Long: `Mark an upgrade candidate DISMISSED — the deliberate "not this one".

A dismissed candidate is never offered and never installed automatically: every
automatic path selects rows in state 'available' or 'scheduled', and a dismissed
row is in neither. The decision is recorded on the row itself, so it survives
restarts and is visible in 'sb upgrade list' and in the admin UI.

The target is a release tag, an 8-char commit_short, or a full 40-char commit
SHA — the same vocabulary 'register' and 'schedule' accept.

Dismissing a version this box has already COMPLETED is refused: it would not
uninstall anything. Dismissing a version with no candidate row is refused too —
a dismissal of nothing is a typo, not a no-op — and the existing rows are shown.

To take a dismissed candidate after all, schedule it explicitly.

Examples:
  sb upgrade dismiss v2026.08.1-rc.3
  sb upgrade dismiss abc1234f`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		operatorFlag, _ := cmd.Flags().GetString("operator")
		return newUpgradeService(config.ProjectDir()).RunDismiss(context.Background(), args[0], resolveOperator(operatorFlag))
	},
}

var upgradeListCmd = &cobra.Command{
	Use:   "list",
	Short: "List discovered upgrades from the database",
	RunE: func(cmd *cobra.Command, args []string) error {
		// STATBUS-308: a stale-looking list is the symptom operators actually
		// notice. Without this, the list looks merely uneventful — the demo box
		// showed exactly that for nine days.
		announceUnitFloor()
		sql := `SELECT commit_version AS version, summary,
			CASE
				WHEN completed_at IS NOT NULL THEN 'completed'
				-- ORDERING RULE (STATBUS-250): DECISION-STATES ABOVE
				-- HISTORY-STATES. A dismissal or a skip is a deliberate,
				-- terminal operator decision; scheduled/in-progress/failed are
				-- marks left by what the row DID earlier. A decision must
				-- outrank its own history, because the row keeps that history:
				-- a candidate that was scheduled, or that failed, and is THEN
				-- dismissed or skipped still carries scheduled_at or error. A
				-- decision branch placed below those renders the row as
				-- 'scheduled' or 'failed' and hides the operator's decision
				-- entirely — which is the same defect as having no branch at
				-- all, on exactly the rows an operator is most likely to act on.
				--
				-- Only 'completed' outranks a decision: a version the box
				-- actually HAS is a fact about the box, not a decision about a
				-- candidate.
				--
				-- WHY THE ORDER IS SOUND AND NOT MERELY LUCKY — two mechanisms
				-- holding each other up, so they say so. The case that would
				-- break this rendering is a row DISMISSED (or skipped) and then
				-- RE-SCHEDULED: it would still carry dismissed_at while being
				-- genuinely scheduled again, and this CASE would report the
				-- stale decision over the live intent. It cannot arise, because
				-- the re-arm NULLs those columns as part of promoting the
				-- candidate — promoteExistingCandidate (service.go:4724-4725)
				-- and RunSchedule (:5103-5104) both clear skipped_at and
				-- dismissed_at. A decision column is therefore only ever set
				-- while the decision still stands.
				--
				-- TRIPWIRE: if that NULLing is ever removed as tidy-up, this
				-- ordering silently starts lying about live rows — a
				-- re-scheduled candidate would display as dismissed. Whoever
				-- removes it must fix this CASE in the same change.
				--
				-- Two instances of one defect, fixed together rather than one
				-- at a time: 'dismissed' had NO branch and fell through to
				-- 'available' (a correct dismiss reading as a failed one in the
				-- very output the dev-reset script checks); 'skipped' HAD a
				-- branch but sat below scheduled/error and so hid a skip on any
				-- row with a history. Both are operator decisions and both
				-- belong here.
				WHEN dismissed_at IS NOT NULL THEN 'dismissed'
				WHEN skipped_at IS NOT NULL THEN 'skipped'
				WHEN error IS NOT NULL AND rolled_back_at IS NOT NULL THEN 'rolled back'
				WHEN error IS NOT NULL THEN 'failed'
				WHEN started_at IS NOT NULL THEN 'in progress'
				WHEN scheduled_at IS NOT NULL THEN 'scheduled'
				ELSE 'available'
			END AS status,
			discovered_at::date AS discovered,
			-- STATBUS-317: who made the transition that produced the status
			-- above. The log trigger fires only on an actual state (or
			-- park/unpark) change, and every write above that sets a
			-- decision/history column ALSO changes state in the same
			-- statement (dismiss sets state='dismissed' AND dismissed_at
			-- together; schedule sets state='scheduled' AND scheduled_at
			-- together) — so the log's newest row for this upgrade_id is
			-- guaranteed to be the one that produced the CASE result above,
			-- never a stale, unrelated entry. '(self-reported)' is spelled
			-- out rather than silently shown as a bare name: an operator
			-- reading this list needs to know a name came from --operator/
			-- a prompt, not from an authenticated session, before treating
			-- it as verified identity.
			COALESCE(
				latest_log.actor || CASE WHEN latest_log.actor_source = 'self-reported' THEN ' (self-reported)' ELSE '' END,
				'-'
			) AS who
		FROM public.upgrade u
		LEFT JOIN LATERAL (
			SELECT actor, actor_source
			FROM public.upgrade_state_log l
			WHERE l.upgrade_id = u.id
			ORDER BY l.id DESC
			LIMIT 1
		) latest_log ON true
		ORDER BY discovered_at DESC
		LIMIT 20;`

		out, err := runUpgradePsql(sql)
		_, _ = os.Stdout.Write(out) // best-effort; a stdout write failure here is unrecoverable anyway
		return err
	},
}

var upgradeScheduleCmd = &cobra.Command{
	Use:   "schedule <target>",
	Short: "Schedule an already-registered candidate to run",
	Long: `Promote an already-registered upgrade candidate to 'scheduled'. The
database trigger then notifies the upgrade service, which runs it.

The target is a release tag, an 8-char commit_short, or a full 40-char commit
SHA — whichever you registered (git-resolved to the canonical commit). FAILS
FAST if the target is not registered: run './sb upgrade register <target>'
first.

Use --recreate to delete and recreate the database from scratch instead of
running migrations. Destructive — dev/demo servers only.

Examples:
  sb upgrade schedule v2026.03.1
  sb upgrade schedule abc1234f
  sb upgrade schedule v2026.03.1 --recreate`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		// STATBUS-308: scheduling depends on the service to execute it. Queueing
		// work for a service that is missing or stopped would sit "scheduled"
		// forever with nothing saying why — the silent wedge again. Warn, but do
		// not refuse: the row is still legitimate, and it runs the moment the
		// operator repairs the box with ./sb install.
		announceUnitFloor()
		operatorFlag, _ := cmd.Flags().GetString("operator")
		return newUpgradeService(config.ProjectDir()).RunSchedule(context.Background(), args[0], recreateFlag, resolveOperator(operatorFlag))
	},
}

var (
	recreateFlag bool
)

// deployedCommitLine formats the STATBUS-170 green-means-converged emit: a stable,
// greppable one-liner naming the exact 40-hex commit apply-latest resolved for
// deployment. The deploy workflow greps `^deployed_commit=<40hex>$` to learn what to
// poll. Keep this format and that regex in lockstep — guarded by
// TestDeployedCommitLine_WorkflowGrepContract.
func deployedCommitLine(commit string) string {
	return "deployed_commit=" + commit
}

var upgradeApplyLatestCmd = &cobra.Command{
	Use:   "apply-latest",
	Short: "Discover and apply the latest available version",
	Long: `Fetches tags via git, finds the latest version matching the
configured channel (stable/prerelease), and tells the upgrade service
to upgrade to it immediately.

Used by deploy workflows — all logic is server-side, no workflow
file changes needed.`,
	// apply-latest is the deploy-workflow target. If the binary is stale
	// (e.g. a prior upgrade rolled back leaving cli/ ahead of the binary),
	// stalenessGuard rebuilds + re-execs instead of hard-failing. See
	// cli/cmd/root.go.
	Annotations: map[string]string{"selfheal": "true"},
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// 1. Load channel from .env
		envPath := filepath.Join(projDir, ".env")
		f, err := dotenv.Load(envPath)
		if err != nil {
			return fmt.Errorf("load .env: %w", err)
		}
		channel := "stable"
		if v, ok := f.Get("UPGRADE_CHANNEL"); ok {
			channel = v
		}

		// STATBUS-325: bring remote.origin.fetch to canonical before any fetch.
		// A box born from the shallow-clone bootstrap has ONLY a tag pin and no
		// wildcard, so the fetch below cannot see branches at all; a box that has
		// been rescued repeatedly has duplicate db-seed lines. Both are rewritten
		// exactly here.
		//
		// UNDER THE UPGRADE MUTEX (STATBUS-323's constraint). Unlike the install
		// call site, this one is a plain CLI command: the upgrade service may be
		// concurrently active, and `git config` mutates repository state. Writing
		// the refspec while a service upgrade manipulates the same repo would
		// reintroduce on the upgrade path exactly the race 323 closed on the
		// bootstrap path.
		//
		// CONTENTION IS NOT AN ERROR. If an upgrade holds the mutex we say so and
		// carry on unnormalized — never abort. Aborting would convert a config
		// tidy-up into a failed upgrade, and if the refspec really is unusable the
		// fetch below fails with its own accurate message. The report exists so
		// the two correlate in the log rather than leaving a bare fetch error with
		// no explanation beside it.
		if lock, lerr := upgrade.AcquireInstallFlag(projDir, "operator:refspec-normalize"); lerr != nil {
			fmt.Printf("Skipping refspec normalization: the upgrade mutex is held (%v).\n", lerr)
			fmt.Println("  Continuing — if the fetch below fails on a missing branch, re-run this after the upgrade finishes.")
		} else {
			nerr := upgrade.NormalizeRefspecs(projDir)
			upgrade.ReleaseInstallFlag(lock)
			if nerr != nil {
				fmt.Printf("Could not normalize remote.origin.fetch: %v\n", nerr)
				fmt.Println("  Continuing — the fetch below will report accurately if the refspec is unusable.")
			}
		}

		var latestVersion string

		// (The edge branch that stood here is retired with the channel — King,
		// 2026-08-19. It resolved origin/master's HEAD commit-short and applied
		// it, which is what "track every master commit" meant in practice.
		// Applying a SPECIFIC commit is unaffected: `./sb upgrade register
		// <commit_short>` then `schedule` takes exactly that target, deliberately,
		// which is the part worth keeping. Continuously following master
		// unattended is the part that retires.)
		// Stable or prerelease: the latest tag the channel admits.
		if fetchOut, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "--tags", "--quiet"); err != nil {
			return fmt.Errorf("git fetch --tags: %w\n  output: %s", err, strings.TrimSpace(fetchOut))
		}
		tagsOutput, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", "v*", "--sort=-version:refname")
		if err != nil {
			return fmt.Errorf("git tag -l: %w", err)
		}
		tags := strings.Split(strings.TrimSpace(tagsOutput), "\n")
		for _, tag := range tags {
			tag = strings.TrimSpace(tag)
			if tag == "" {
				continue
			}
			if channel == "stable" && strings.Contains(tag, "-") {
				// Stable: skip pre-release tags (contain "-")
				continue
			}
			latestVersion = tag
			break
		}
		if latestVersion == "" {
			return fmt.Errorf("no matching version found for channel %q", channel)
		}

		// ValidateVersion answers "is this a release tag" only (rc.63
		// canonical-naming cleanup). Edge channel produces an 8-char
		// commit_short instead — accept either shape.
		if !upgrade.ValidateVersion(latestVersion) && !upgrade.IsCommitShort(latestVersion) {
			return fmt.Errorf("discovered version %q does not pass validation (expected release tag or 8-char commit_short)", latestVersion)
		}

		fmt.Printf("Channel %s: latest version is %s\n", channel, latestVersion)

		// Resolve the latest's commit via the SAME git-authoritative resolver the
		// scheduling path uses (STATBUS-169 skip-check fold: the LAST tag-as-selector
		// site — the old psql `ANY(commit_tags)` lookup — moves onto ResolveToCommit
		// so there is ONE resolution shape for every tag→commit read). Resolve ONCE and
		// reuse for the deployed_commit emit (below) and the already-at-target skip.
		svc := newUpgradeService(projDir)
		var resolvedCommit string
		if resolved, rerr := svc.ResolveToCommit(context.Background(), latestVersion); rerr == nil {
			resolvedCommit = string(resolved)
			// STATBUS-170 (green-means-converged): emit what WILL be deployed as a
			// stable, greppable one-liner. The deploy workflow captures this and polls
			// ci-deploy-status.sh by the EXACT deployed commit — correct on every
			// channel (apply-latest resolves a tag on prerelease/stable, master HEAD on
			// edge), which the workflow cannot know on its own. A resolve error omits
			// the line; the workflow's absent-line fallback (the two-phase 127 genre)
			// degrades to poke-only green + one loud notice, self-expiring as the fleet
			// upgrades. Keep this on its own line and prefix-stable for the grep.
			fmt.Println(deployedCommitLine(resolvedCommit))
		} else {
			fmt.Fprintf(os.Stderr, "warn: could not resolve %s to a commit — deployed_commit line omitted (poll degrades to poke-only): %v\n", latestVersion, rerr)
		}

		// Skip when this box is already CONVERGED at the latest. Without a skip,
		// apply-latest unconditionally flips state='scheduled', the
		// upgrade_notify_daemon_trigger fires NOTIFY upgrade_apply, and the service
		// runs a full no-op upgrade pipeline (stop containers, backup, exit-42,
		// restart, applyNewSbUpgrading) for nothing.
		//
		// The decision is decideApplyLatest's (below) — it is a pure function so the
		// parked-at-target case can be pinned without a box. Convergence is a
		// property of the ROW, not of the running binary: see that function's
		// comment for why reading the binary alone told a human "nothing to apply"
		// while the box sat parked and dark (STATBUS-226).
		rowState := applyLatestRowState(context.Background(), svc, resolvedCommit)
		switch verdict := decideApplyLatest(latestVersion, resolvedCommit, commit, rowState); verdict.Action {
		case applyLatestSkip:
			fmt.Println(verdict.Message)
			return nil
		case applyLatestRefuse:
			return fmt.Errorf("%s", verdict.Message)
		}
		// applyLatestProceed falls through to register + schedule below.

		// Route through the REAL mechanism (STATBUS-086): register the latest
		// as a candidate, then schedule it. This is RACE-PROOF — register
		// upserts the row, so schedule always finds it. The old insert-if-missing
		// UPDATE+NOTIFY silently no-op'd when it lost the deploy-before-discovery
		// race (UPDATE 0 rows → NOTIFY → onScheduledNotify require-register
		// no-op → deploy didn't upgrade, and the "will apply next cycle" message
		// lied). register→schedule completes the clean break and keeps deploys
		// deployable. recreateFlag is carried by RunSchedule.
		if err := svc.RunRegister(context.Background(), latestVersion); err != nil {
			return fmt.Errorf("apply-latest register %s: %w", latestVersion, err)
		}
		// STATBUS-317: apply-latest is the deploy-workflow target (its own
		// docstring: "Used by deploy workflows... no workflow file changes
		// needed") — the archetypal CI door. resolveOperator("") is TTY-gated
		// (see its own TRAP comment), so an automated invocation here
		// correctly records 'absent' and never blocks.
		if err := svc.RunSchedule(context.Background(), latestVersion, recreateFlag, resolveOperator("")); err != nil {
			return fmt.Errorf("apply-latest schedule %s: %w", latestVersion, err)
		}

		if w, err := syslog.New(syslog.LOG_INFO, "statbus-upgrade"); err == nil {
			_ = w.Info(fmt.Sprintf("upgrade apply-latest: registered + scheduled %s (channel=%s, recreate=%v)", latestVersion, channel, recreateFlag)) // best-effort syslog note
			_ = w.Close()
		}

		return nil
	},
}

// newUpgradeService builds a Service for the current binary, deriving the
// service version (a git-checkout-able ref) from the ldflags. Shared by the
// `service` daemon and the one-shot verbs (register / schedule / check).
func newUpgradeService(projDir string) *upgrade.Service {
	// Derive serviceVersion — a valid git ref the service can git-checkout.
	// version is cmd.version: git-describe output verbatim, which carries the
	// leading "v" (the canonical CommitVersion form). Rules (priority order):
	//   1. "dev" ldflag   → 8-char commit_short or "dev" (skips downgrade guard)
	//   2. Has "v" prefix → use as-is (v-bearing CalVer from git describe / release.yaml)
	//   3. Anything else  → 8-char commit_short or "dev". Covers the bare
	//      abbreviated SHA `git describe --always` emits when no tag is
	//      reachable; downgrade guard treats it as an unversioned local build.
	//
	// No v-strip/re-prepend dance (STATBUS-064): the value already carries the
	// "v" everywhere, so there is no v-less CalVer form to re-prepend onto.
	// No "sha-" prefix anywhere (rc.63 canonical naming).
	var serviceVersion string
	switch {
	case version == "dev":
		if commit != "unknown" {
			serviceVersion = upgrade.ShortForDisplay(commit)
		} else {
			serviceVersion = "dev"
		}
	case strings.HasPrefix(version, "v"):
		serviceVersion = version
	default:
		// Non-v ldflag (bare --always SHA, stray tag, hand-built binary) — treat as local build.
		if commit != "unknown" {
			serviceVersion = upgrade.ShortForDisplay(commit)
		} else {
			serviceVersion = "dev"
		}
	}
	d := upgrade.NewService(projDir, verbose, serviceVersion, commit)
	// Unit name for the per-dispatch NRestarts reset (STATBUS-039 review
	// finding 2) — derivable only here in cmd; internal/upgrade must not
	// guess it.
	d.SetUnitInstance(serviceInstance(projDir))

	// LOAD THE CONFIG (STATBUS-311). Without this every CLI verb ran with
	// d.channel == "", because loadConfig had only ever been called from Run()
	// and LoadConfigAndConnect() — both daemon-side. `./sb upgrade check` then
	// filtered every release tag against the empty string and reported
	// "none matching channel """, registering nothing; `upgrade schedule`
	// announced perfectly on-channel targets as off-channel.
	//
	// Here rather than inside each verb: the channel is a property of the box,
	// so a Service built for this box should have it. Doing it per-verb is how
	// the next verb gets forgotten.
	//
	// A FAILURE IS LOUD, NEVER SILENT. The whole defect was an empty channel
	// nobody was told about; falling back quietly would reproduce it. Note that
	// a .env MISSING the key is already handled inside loadConfig, which warns
	// and assumes "stable" — this branch is for a .env that cannot be read at
	// all, which on a developer machine simply means there is no box here.
	if err := d.LoadConfigForCLI(); err != nil {
		fmt.Fprintf(os.Stderr,
			"WARN: could not read .env in %s (%v).\n"+
				"Commands that depend on this box's upgrade channel (check, schedule) will\n"+
				"behave as if no channel is set and may match nothing. Run `./sb config generate`.\n",
			projDir, err)
	}
	return d
}

var upgradeServiceRunE = func(cmd *cobra.Command, args []string) error {
	return newUpgradeService(config.ProjectDir()).Run(context.Background())
}

var upgradeServiceCmd = &cobra.Command{
	Use:   "service",
	Short: "Run the upgrade service (long-running process)",
	Long: `Starts the upgrade service which:
  - Polls GitHub Releases for new versions
  - Pre-downloads Docker images
  - Listens for NOTIFY upgrade_check and upgrade_apply
  - Executes scheduled upgrades with backup and rollback

Typically run via systemd (ops/statbus-upgrade.service).`,
	// systemd entrypoint. If a previous upgrade rolled back leaving cli/
	// ahead of the binary, stalenessGuard rebuilds + re-execs instead of
	// crash-looping the service. See cli/cmd/root.go.
	Annotations: map[string]string{"selfheal": "true"},
	RunE:        upgradeServiceRunE,
}

// selfVerifyExpectCommit is bound to `upgrade self-verify --expect-commit`. When
// set (by selfupdate.ReplaceBinaryOnDisk's step 3b), self-verify asserts THIS
// binary's embedded commit equals the named upgrade target. See STATBUS-171.
var selfVerifyExpectCommit string

var upgradeSelfVerifyCmd = &cobra.Command{
	Use:    "self-verify",
	Short:  "Verify the binary can boot and embeds the expected target commit (used during self-update)",
	Hidden: true,
	// STATBUS-171: guard-exempt, exactly like the `committed-drift` probe. This
	// command runs mid-upgrade INSIDE the freshly-procured target binary, while
	// STATBUS-060 deliberately leaves the worktree at the SOURCE commit until the
	// recovery boot. A worktree-relative stalenessGuard here would ALWAYS —
	// correctly, per its own binary-matches-worktree contract — judge the target
	// binary "stale" and abort the swap (BINARY_REPLACE_FAILED; dev row 331014).
	// That is a category error: the question at this site is not "does the binary
	// match the worktree" but "is the binary we just wrote the TARGET we intended",
	// which --expect-commit answers below. stalenessGuard's contract stays the
	// right check at DAEMON BOOT (post-recovery-checkout, HEAD=target) — that
	// coverage is untouched; only this mid-upgrade call site is exempted.
	Annotations: map[string]string{"freshness_probe": "true"},
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("sb version: %s\n", rootCmd.Version)
		if err := selfVerifyIdentity(string(commitSHA), selfVerifyExpectCommit); err != nil {
			return err
		}
		fmt.Println("Self-verify: OK")
		return nil
	},
}

// selfVerifyIdentity is the pure core of `upgrade self-verify --expect-commit`
// (STATBUS-171). It confirms a freshly-procured binary whose EMBEDDED build commit
// is `embedded` is the intended upgrade target `expect` — comparing against the
// TARGET, never the worktree. Under STATBUS-060 the worktree is deliberately left
// at the SOURCE commit during the swap, so a worktree-relative check here is a
// category error that fails every tag-identified upgrade.
//
//   - expect == "":   boot-only self-verify (legacy caller); no identity assertion.
//   - embedded == "": unidentifiable binary (no ldflags) with a target demanded →
//     hard fail; we cannot confirm it is the target.
//   - otherwise: prefix-both-ways match (short-vs-full SHA), mirroring the manifest
//     anti-tamper check (the adjacent 060 fix in service.go executeUpgrade).
func selfVerifyIdentity(embedded, expect string) error {
	if expect == "" {
		return nil
	}
	if embedded == "" {
		return fmt.Errorf("self-verify: this binary has no reliable commit identity (built without ldflags) — cannot confirm it is the upgrade target %s",
			upgrade.ShortForDisplay(expect))
	}
	if !strings.HasPrefix(embedded, expect) && !strings.HasPrefix(expect, embedded) {
		return fmt.Errorf("self-verify: procured binary embeds commit %s but the upgrade target is %s — wrong or mis-built artifact",
			upgrade.ShortForDisplay(embedded), upgrade.ShortForDisplay(expect))
	}
	return nil
}

var upgradeSelfRollbackCmd = &cobra.Command{
	Use:    "self-rollback",
	Short:  "Roll back to the previous binary",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		sbPath := projDir + "/sb"
		if err := selfupdate.Rollback(sbPath); err != nil {
			return err
		}
		fmt.Println("Rolled back to previous binary")
		return nil
	},
}

// sshKeyFingerprint returns the fingerprint for an SSH public key string.
func sshKeyFingerprint(key string) string {
	cmd := exec.Command("ssh-keygen", "-l", "-f", "/dev/stdin")
	cmd.Stdin = strings.NewReader(key)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "unknown fingerprint"
	}
	return strings.TrimSpace(string(out))
}

// gitHubSigningKey represents one entry from the GitHub SSH signing keys API.
type gitHubSigningKey struct {
	Key string `json:"key"`
}

// fetchGitHubKeys fetches SSH public keys for a GitHub user. It tries the
// signing keys API first (correct for commit verification), falling back to
// the authentication keys endpoint for backward compatibility. Returns the
// keys and whether they came from the signing keys endpoint.
func fetchGitHubKeys(username string) (keys []string, signing bool, err error) {
	// Try signing keys first — these are what git uses for commit verification.
	sigURL := fmt.Sprintf("https://api.github.com/users/%s/ssh_signing_keys", username)
	if sk, fetchErr := fetchGitHubSigningKeys(sigURL); fetchErr == nil && len(sk) > 0 {
		return sk, true, nil
	}

	// Fall back to authentication keys (plain-text, one per line).
	authURL := fmt.Sprintf("https://github.com/%s.keys", username)
	ak, fetchErr := fetchGitHubAuthKeys(authURL, username)
	if fetchErr != nil {
		return nil, false, fetchErr
	}
	return ak, false, nil
}

// fetchGitHubSigningKeys queries the GitHub API for SSH signing keys.
// Returns (nil, nil) when the endpoint succeeds but the user has no signing keys.
func fetchGitHubSigningKeys(url string) ([]string, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "statbus-cli")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch signing keys from %s: %w", url, err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("status %d from %s", resp.StatusCode, url)
	}

	var entries []gitHubSigningKey
	if err := json.NewDecoder(resp.Body).Decode(&entries); err != nil {
		return nil, fmt.Errorf("decode signing keys JSON: %w", err)
	}

	var keys []string
	for _, e := range entries {
		if k := strings.TrimSpace(e.Key); k != "" {
			keys = append(keys, k)
		}
	}
	return keys, nil
}

// fetchGitHubAuthKeys fetches the plain-text SSH authentication keys for a GitHub user.
func fetchGitHubAuthKeys(url, username string) ([]string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("fetch keys from %s: %w", url, err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode == 404 {
		return nil, fmt.Errorf("GitHub user %q not found (404 from %s)", username, url)
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("unexpected status %d from %s", resp.StatusCode, url)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	var keys []string
	scanner := bufio.NewScanner(strings.NewReader(string(body)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line != "" {
			keys = append(keys, line)
		}
	}

	if len(keys) == 0 {
		return nil, fmt.Errorf("no SSH keys found for github.com/%s", username)
	}

	return keys, nil
}

// trustSignerInteractive fetches keys for a GitHub user, displays them, prompts for
// confirmation, and stores the key in the given dotenv file. Returns true if a key was trusted.
func trustSignerInteractive(username string, f *dotenv.File, reader *bufio.Reader) (bool, error) {
	fmt.Printf("\nFetching SSH keys from GitHub for %s...\n", username)
	keys, signing, err := fetchGitHubKeys(username)
	if err != nil {
		return false, err
	}

	if signing {
		fmt.Printf("Found %d signing key(s) for github.com/%s:\n", len(keys), username)
	} else {
		fmt.Printf("Found %d auth key(s) for github.com/%s (no signing keys configured — consider adding at github.com/settings/keys):\n", len(keys), username)
	}
	for _, key := range keys {
		fingerprint := sshKeyFingerprint(key)
		fmt.Printf("  %s\n", fingerprint)
	}

	fmt.Printf("\nTrust key(s) from github.com/%s? [Y/n] ", username)
	answer, _ := reader.ReadString('\n')
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer == "n" || answer == "no" {
		return false, nil
	}

	envKey := trustedSignerPrefix + username
	f.Set(envKey, keys[0])
	if err := f.Save(); err != nil {
		return false, fmt.Errorf("save .env.config: %w", err)
	}

	fmt.Printf("Added %s to .env.config\n", envKey)
	if len(keys) > 1 {
		fmt.Printf("Note: only the first key was stored. Add others manually if needed.\n")
	}
	return true, nil
}

// trustedSignerPrefix is the env key prefix for trusted signers.
const trustedSignerPrefix = "UPGRADE_TRUSTED_SIGNER_"

var trustKeyCmd = &cobra.Command{
	Use:   "trust-key",
	Short: "Manage trusted commit signing keys",
	Long: `Manage SSH public keys trusted for verifying commit signatures.

Keys are stored as UPGRADE_TRUSTED_SIGNER_<name> in .env.config.
The upgrade service uses these to verify commits before applying upgrades.`,
}

var trustKeyListCmd = &cobra.Command{
	Use:   "list",
	Short: "List configured trusted signing keys",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		found := false
		for _, key := range f.Keys() {
			if !strings.HasPrefix(key, trustedSignerPrefix) {
				continue
			}
			name := strings.TrimPrefix(key, trustedSignerPrefix)
			val, _ := f.Get(key)
			fingerprint := sshKeyFingerprint(val)
			fmt.Printf("  %s: %s\n", name, fingerprint)
			found = true
		}

		if !found {
			fmt.Println("No trusted signers configured.")
			fmt.Println("Add one with: ./sb upgrade trust-key add <github-username>")
		}
		return nil
	},
}

var trustKeyAddYes bool

var trustKeyAddCmd = &cobra.Command{
	Use:   "add <github-username>",
	Short: "Add trusted signing keys from a GitHub user",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		username := args[0]

		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		if trustKeyAddYes {
			return trustSignerNonInteractive(username, f)
		}

		reader := bufio.NewReader(os.Stdin)
		trusted, err := trustSignerInteractive(username, f, reader)
		if err != nil {
			return err
		}
		if !trusted {
			fmt.Println("Cancelled.")
		}
		return nil
	},
}

// trustSignerNonInteractive fetches keys and trusts the first one without
// prompting. Used by --yes flag for scripted / AI-driven installs.
func trustSignerNonInteractive(username string, f *dotenv.File) error {
	fmt.Printf("Fetching SSH keys from GitHub for %s...\n", username)
	keys, signing, err := fetchGitHubKeys(username)
	if err != nil {
		return err
	}
	if signing {
		fmt.Printf("Found %d signing key(s) for github.com/%s:\n", len(keys), username)
	} else {
		fmt.Printf("Found %d auth key(s) for github.com/%s (no signing keys configured — consider adding at github.com/settings/keys):\n", len(keys), username)
	}
	for _, key := range keys {
		fmt.Printf("  %s\n", sshKeyFingerprint(key))
	}

	envKey := trustedSignerPrefix + username
	f.Set(envKey, keys[0])
	if err := f.Save(); err != nil {
		return fmt.Errorf("save .env.config: %w", err)
	}
	fmt.Printf("Added %s to .env.config (--yes, no prompt)\n", envKey)
	return nil
}

var trustKeyRemoveCmd = &cobra.Command{
	Use:   "remove <name>",
	Short: "Remove a trusted signing key",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		name := args[0]
		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		envKey := trustedSignerPrefix + name
		if !f.Delete(envKey) {
			return fmt.Errorf("no trusted signer named %q found in .env.config", name)
		}

		if err := f.Save(); err != nil {
			return fmt.Errorf("save .env.config: %w", err)
		}

		fmt.Printf("Removed %s from .env.config\n", envKey)
		return nil
	},
}

var trustKeyVerifyCmd = &cobra.Command{
	Use:   "verify",
	Short: "Verify the current HEAD commit signature against trusted keys",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		configPath := filepath.Join(projDir, ".env.config")
		f, err := dotenv.Load(configPath)
		if err != nil {
			return fmt.Errorf("load .env.config: %w", err)
		}

		// Collect trusted signers
		var signerLines []string
		for _, key := range f.Keys() {
			if !strings.HasPrefix(key, trustedSignerPrefix) {
				continue
			}
			name := strings.TrimPrefix(key, trustedSignerPrefix)
			val, _ := f.Get(key)
			// allowed_signers format: <principal> <key>
			signerLines = append(signerLines, fmt.Sprintf("%s %s", name, val))
		}

		if len(signerLines) == 0 {
			return fmt.Errorf("no trusted signers configured (UPGRADE_TRUSTED_SIGNER_*)")
		}

		// Write allowed-signers file
		allowedSignersPath := filepath.Join(projDir, "tmp", "allowed-signers")
		_ = os.MkdirAll(filepath.Join(projDir, "tmp"), 0755) // best-effort; the WriteFile right after surfaces any real failure
		if err := os.WriteFile(allowedSignersPath, []byte(strings.Join(signerLines, "\n")+"\n"), 0644); err != nil {
			return fmt.Errorf("write allowed-signers: %w", err)
		}

		// Verify HEAD
		verifyCmd := exec.Command("git", "-c",
			fmt.Sprintf("gpg.ssh.allowedSignersFile=%s", allowedSignersPath),
			"verify-commit", "HEAD")
		verifyCmd.Dir = projDir
		out, verifyErr := verifyCmd.CombinedOutput()
		fmt.Print(string(out))

		if verifyErr != nil {
			return fmt.Errorf("HEAD commit signature verification failed")
		}
		fmt.Println("HEAD commit signature is valid and trusted.")
		return nil
	},
}

func init() {
	upgradeScheduleCmd.Flags().BoolVar(&recreateFlag, "recreate", false, "delete and recreate database from scratch (destructive — dev/demo only)")
	upgradeApplyLatestCmd.Flags().BoolVar(&recreateFlag, "recreate", false, "delete and recreate database from scratch (destructive — dev/demo only)")
	// STATBUS-317: who made this transition. Absent + a TTY present ->
	// resolveOperator prompts; absent + no TTY (CI, e.g. apply over sshdo)
	// -> proceeds and records 'absent', never blocks.
	upgradeScheduleCmd.Flags().String("operator", "", "your name, for the audit log (prompted interactively if omitted and a terminal is present)")
	upgradeDismissCmd.Flags().String("operator", "", "your name, for the audit log (prompted interactively if omitted and a terminal is present)")

	trustKeyAddCmd.Flags().BoolVarP(&trustKeyAddYes, "yes", "y", false, "skip confirmation prompt (for scripted / AI-driven installs)")
	trustKeyCmd.AddCommand(trustKeyListCmd)
	trustKeyCmd.AddCommand(trustKeyAddCmd)
	trustKeyCmd.AddCommand(trustKeyRemoveCmd)
	trustKeyCmd.AddCommand(trustKeyVerifyCmd)

	upgradeCmd.AddCommand(upgradeCheckCmd)
	upgradeCmd.AddCommand(upgradeRegisterCmd)
	upgradeCmd.AddCommand(upgradeDismissCmd)
	upgradeCmd.AddCommand(upgradeListCmd)
	upgradeCmd.AddCommand(upgradeScheduleCmd)
	upgradeCmd.AddCommand(upgradeApplyLatestCmd)
	upgradeApplyCmd.Flags().Bool("recreate", false, "recreate the database from migrations instead of migrating it (DESTRUCTIVE)")
	upgradeCmd.AddCommand(upgradeApplyCmd)
	upgradeCmd.AddCommand(upgradeServiceCmd)
	upgradeSelfVerifyCmd.Flags().StringVar(&selfVerifyExpectCommit, "expect-commit", "",
		"assert this binary embeds the given target commit (used by the upgrade self-update; STATBUS-171)")
	upgradeCmd.AddCommand(upgradeSelfVerifyCmd)
	upgradeCmd.AddCommand(upgradeSelfRollbackCmd)
	upgradeCmd.AddCommand(trustKeyCmd)
	rootCmd.AddCommand(upgradeCmd)
}
