// Package upgrade contains recovery invariants and their executable proofs.
//
// Compose-up authority threat model: this gate proves the absence of accidental
// compose-up authority in recovery code. A well-intentioned change that
// reintroduces docker compose up on a failure branch must fail CI. It does not
// defend against deliberate in-module subversion through unsafe, go:linkname,
// or reflection over process-local state. Such code is equivalent to editing the
// wrapper itself, and Go provides no in-process capability-security boundary.
// Reviewers evaluate this gate against that contract. The resolved launcher set
// is os/exec.Command, os/exec.CommandContext, os.StartProcess, syscall.Exec,
// syscall.ForkExec, os/exec.Cmd composite literals, and every generic upgrade
// runner that reaches commandContext. Launcher function values are forbidden.
// Every constant production launch is pinned by enclosing function, launcher
// kind, and executable; stale combinations fail. commandContext has no runtime
// executable policy: it preserves git's invocation-scoped config and routes
// docker through the Compose wrapper. Its dynamic internal forwarding edges are
// exact-count pinned, while every reviewed caller supplies a constant executable.
// Tools may receive dynamic path/SHA arguments. Raw launch arguments may not
// smuggle docker/docker-compose/podman/compose authority; typed upgrade-runner
// docker calls are safe because commandContext sends them through the Compose
// parser. Mediators require constant, authority-free arguments except the
// exact-count-pinned user/configuration facilities below. The three dynamic
// syscall.Exec handoffs are adjacent-marker and exact-count pinned.
// Enumeration method: use gopls references on os/exec.Command and CommandContext,
// exec.Cmd literals, os.StartProcess, syscall.Exec/ForkExec, and upgrade runCommand* wrappers.
// Re-run that enumeration whenever this test names a new site.
package upgrade

import (
	"fmt"
	"go/ast"
	"go/constant"
	"go/token"
	"go/types"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"
	"unicode"

	"golang.org/x/tools/go/packages"
)

const (
	composePackagePath = "github.com/statisticsnorway/statbus/cli/internal/compose"
	execPackagePath    = "os/exec"
	osPackagePath      = "os"
	syscallPackagePath = "syscall"
	upgradePackagePath = "github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

type typedAuthorityPackage struct {
	pkg  *packages.Package
	file *ast.File
	path string
}

type approvedLaunch struct {
	Count  int
	Reason string
}

var allowedComposeUpCalls = map[string]approvedLaunch{
	"cmd/db.go:dockerComposeStart":                                       {Count: 1, Reason: "operator database workflow starts the requested compose services through compose.Up"},
	"cmd/install.go:composeApplyServiceDefault":                          {Count: 1, Reason: "install applies the configured default service set through compose.Up"},
	"cmd/install.go:runInstall":                                          {Count: 1, Reason: "install starts the full application stack through compose.Up"},
	"cmd/install.go:runStartServices":                                    {Count: 1, Reason: "install step starts its declared services through compose.Up"},
	"cmd/service.go:startServices":                                       {Count: 1, Reason: "operator service start command delegates to the compose.Up chokepoint"},
	"cmd/service_restart.go:restartServices":                             {Count: 1, Reason: "operator service restart brings services back through compose.Up"},
	"internal/upgrade/exec.go:EnsureDBUp":                                {Count: 1, Reason: "upgrade database preparation starts only the database services through compose.Up"},
	"internal/upgrade/service.go:abortFailedPreBackupStop":               {Count: 1, Reason: "pre-backup abort restores the source services through compose.Up"},
	"internal/upgrade/service.go:applyNewSbUpgrading":                    {Count: 2, Reason: "upgrade transition starts the target database and application stacks through compose.Up"},
	"internal/upgrade/service.go:completeInProgressUpgrade":              {Count: 1, Reason: "successful upgrade completion starts the target application stack through compose.Up"},
	"internal/upgrade/service.go:convergeParkedServingTierToCurrentTree": {Count: 1, Reason: "a successor claim against a displaced park reconciles the serving tier to the current tree before capturing its source baseline"},
	"internal/upgrade/service.go:startSourceApplicationStack":            {Count: 1, Reason: "recovery restores the verified source application stack through compose.Up"},
}

// Filled with the exact production process inventory as
// enclosing-function|launcher-kind|executable. A new site, a different tool at
// an existing site, or rerouting a tool through another launcher all fail until
// the specific combination is reviewed.
var allowedProcessLaunches = map[string]approvedLaunch{
	"cmd/db.go:backupCreateCmd.RunE|os/exec|tar":                                                      {Count: 1, Reason: "backupCreateCmd packages the selected dump and metadata files into the operator-requested tar archive"},
	"cmd/db.go:backupRestoreCmd.RunE|os/exec|tar":                                                     {Count: 1, Reason: "backupRestoreCmd extracts the selected StatBus backup archive before restoring its database payload"},
	"cmd/db.go:dbDownloadCmd.RunE|os/exec|ssh":                                                        {Count: 2, Reason: "dbDownloadCmd uses SSH to validate the remote StatBus checkout and stream the requested database dump"},
	"cmd/db.go:restoreRemote|os/exec|scp":                                                             {Count: 1, Reason: "restoreRemote uses scp to place the local dump archive in the remote host's restore staging path"},
	"cmd/db.go:restoreRemote|os/exec|ssh":                                                             {Count: 3, Reason: "restoreRemote uses SSH to check remote prerequisites, prepare the staging directory, and invoke the remote restore"},
	"cmd/db_with_seed_lock.go:withSeedLockCmd.RunE|os/exec|/usr/bin/env":                              {Count: 1, Reason: "withSeedLockCmd uses env to execute the operator-selected command while the database seed lock is held"},
	"cmd/dotenv.go:dotenvGenerateCmd.RunE|os/exec|sh":                                                 {Count: 1, Reason: "dotenvGenerateCmd sends the configured dotenv generator fragment to sh because the setting is explicitly shell syntax"},
	"cmd/install.go:checkSignersDone|os/exec|git":                                                     {Count: 1, Reason: "checkSignersDone runs git verify-commit to prove HEAD was signed by a configured trusted signer"},
	"cmd/install.go:commandContextDir|os/exec|./sb":                                                   {Count: 1, Reason: "commandContextDir constructs the project-local sb invocation used by install steps that re-enter the CLI"},
	"cmd/install.go:commandContextDir|os/exec|git":                                                    {Count: 1, Reason: "commandContextDir constructs project-scoped Git commands while preserving install's invocation-specific Git configuration"},
	"cmd/install.go:commandContextDir|os/exec|loginctl":                                               {Count: 1, Reason: "commandContextDir constructs the loginctl invocation used to enable lingering for the installing user"},
	"cmd/install.go:commandContextDir|os/exec|systemctl":                                              {Count: 1, Reason: "commandContextDir constructs user-systemd commands used by install service setup and repair steps"},
	"cmd/install.go:gitHeadInfo|upgrade.RunCommandOutput|git":                                         {Count: 2, Reason: "gitHeadInfo reads HEAD's commit SHA and commit timestamp so install-state detection identifies the exact checkout"},
	"cmd/install.go:runGenerateEnv|upgrade.RunCommandOutput|git":                                      {Count: 1, Reason: "runGenerateEnv reads the current branch name so generated deployment configuration records its source branch"},
	"cmd/install.go:runInstallCallback|os/exec|sh":                                                    {Count: 1, Reason: "runInstallCallback executes the administrator-configured post-install callback as the documented shell command"},
	"cmd/install.go:runInstallService|os/exec|systemctl":                                              {Count: 3, Reason: "runInstallService queries active, failed-result, and boot-enabled systemd states to drive and verify user-unit reconciliation"},
	"cmd/install.go:runRootInstall|os/exec|systemctl":                                                 {Count: 1, Reason: "runRootInstall queries is-enabled after root service setup to prove the upgrade unit will start on boot"},
	"cmd/install_upgrade.go:restartUpgradeService|os/exec|systemctl":                                  {Count: 2, Reason: "restartUpgradeService checks that the upgrade unit is active and restarts it to load the newly installed binary"},
	"cmd/install_upgrade.go:stopRestartUpgradeUnit|os/exec|systemctl":                                 {Count: 7, Reason: "stopRestartUpgradeUnit inspects, stops, resets, reenables, and restarts the upgrade unit during crash takeover"},
	"cmd/install_upgrade.go:upgradeUnitCrashLooping|os/exec|systemctl":                                {Count: 1, Reason: "upgradeUnitCrashLooping reads systemd unit properties to distinguish a live upgrade from a restart loop"},
	"cmd/release/release.go:checkMigrationImmutability|upgrade.RunCommandOutput|git":                  {Count: 2, Reason: "checkMigrationImmutability diffs migration paths from the predecessor tag and checks tag ancestry before offering history diagnostics"},
	"cmd/release/release.go:checkPrereleaseWorkflowGate|upgrade.RunCommandOutput|git":                 {Count: 1, Reason: "checkPrereleaseWorkflowGate resolves HEAD so the workflow oracle is queried for the exact release commit"},
	"cmd/release/release.go:checkWorkingTreeClean|upgrade.RunCommandOutput|git":                       {Count: 1, Reason: "checkWorkingTreeClean asks Git status for staged, unstaged, and untracked release-checkout paths so every dirty file can be reported"},
	"cmd/release/release.go:findExemptRide|upgrade.RunCommandOutput|git":                              {Count: 2, Reason: "findExemptRide reads workflow-dispatch commits and ancestry to prove an exemption run covers the current tip"},
	"cmd/release/release.go:noSameKindTagAtHEAD|upgrade.RunCommandOutput|git":                         {Count: 1, Reason: "noSameKindTagAtHEAD lists tags pointing at HEAD to prevent a duplicate prerelease or stable tag on one commit"},
	"cmd/release/release.go:preflightChecks|upgrade.RunCommandOutput|git":                             {Count: 15, Reason: "preflightChecks uses Git branch, fetch, ancestry, signature, and diff queries to validate the exact release checkout"},
	"cmd/release/release.go:releaseListCmd.RunE|upgrade.RunCommandOutput|git":                         {Count: 1, Reason: "releaseListCmd asks Git for version-sorted StatBus tags displayed by the release listing command"},
	"cmd/release/release.go:releasePrereleaseCmd.RunE|upgrade.RunCommandOutput|git":                   {Count: 4, Reason: "releasePrereleaseCmd inspects existing RC tags, creates the signed annotated candidate tag, and pushes that tag"},
	"cmd/release/release.go:releaseStableCmd.RunE|upgrade.RunCommandOutput|git":                       {Count: 7, Reason: "releaseStableCmd verifies candidate tags, creates the signed stable tag, and pushes the resulting release reference"},
	"cmd/release/release.go:runGoCLIBuild|os/exec|go":                                                 {Count: 1, Reason: "runGoCLIBuild invokes the host Go compiler in cli to prove release sources build outside the upgrade command runner"},
	"cmd/release/release_canary.go:runCanaryProbe|os/exec|ssh":                                        {Count: 1, Reason: "runCanaryProbe uses SSH to run the read-only release observation probe on the designated canary host"},
	"cmd/release/release_covered.go:resolveCommitish|upgrade.RunCommandOutput|git":                    {Count: 1, Reason: "resolveCommitish peels a user-supplied tag or revision to the commit used by release coverage evaluation"},
	"cmd/release/release_drift_ci_escape.go:driftCoveredByWorkflowGreen|upgrade.RunCommandOutput|git": {Count: 1, Reason: "driftCoveredByWorkflowGreen resolves local HEAD before accepting CI evidence for migration-stamp drift"},
	"cmd/release/release_sshdoers_drift.go:readLiveSshdoersHash|os/exec|ssh":                          {Count: 1, Reason: "readLiveSshdoersHash hashes the live canary's ssh-doers script over SSH for release drift comparison"},
	"cmd/release/release_verify.go:assertStableMatchesLatestRC|upgrade.RunCommandOutput|git":          {Count: 1, Reason: "assertStableMatchesLatestRC compares peeled tag commits so stable cannot differ from the latest release candidate"},
	"cmd/release/release_verify.go:compareMigrationsForTag|upgrade.RunCommandOutput|git":              {Count: 1, Reason: "compareMigrationsForTag asks Git for migration changes between the predecessor and proposed release tag"},
	"cmd/release/release_verify.go:dispatchRefForMasterTip|upgrade.RunCommandOutput|git":              {Count: 1, Reason: "dispatchRefForMasterTip resolves origin/master to bind workflow dispatch evidence to the remote release tip"},
	"cmd/release/release_verify.go:listStablePatchesForPrefix|upgrade.RunCommandOutput|git":           {Count: 1, Reason: "listStablePatchesForPrefix lists matching stable tags so verification can enforce patch-order progression"},
	"cmd/release/release_verify.go:tagIsAncestorOfHEAD|upgrade.RunCommandOutput|git":                  {Count: 3, Reason: "tagIsAncestorOfHEAD runs merge-base checks used to prove release tags lie on the current history"},
	"cmd/release/release_verify.go:tagIsAnnotated|upgrade.RunCommandOutput|git":                       {Count: 1, Reason: "tagIsAnnotated queries the tag object's type to reject lightweight release tags"},
	"cmd/release/release_verify.go:tagMessageSubject|upgrade.RunCommandOutput|git":                    {Count: 1, Reason: "tagMessageSubject reads the annotated tag subject for the release-message contract"},
	"cmd/release/release_verify.go:tagTargetCommit|upgrade.RunCommandOutput|git":                      {Count: 1, Reason: "tagTargetCommit peels the release tag to the commit whose artifacts and ancestry are verified"},
	"cmd/release/release_verify.go:verifyCommonTagShape|upgrade.RunCommandOutput|git":                 {Count: 1, Reason: "verifyCommonTagShape uses git verify-tag to validate the release tag's cryptographic signature"},
	"cmd/repo_fetch.go:repoFetchCmd.RunE|upgrade.RunCommandOutput|git":                                {Count: 1, Reason: "repoFetchCmd runs the requested origin fetch or remote update for the local StatBus repository"},
	"cmd/seed.go:DumpSeed|upgrade.RunCommandOutput|git":                                               {Count: 2, Reason: "DumpSeed records HEAD and repository dirtiness so a generated seed identifies its exact source state"},
	"cmd/seed.go:extractSeedFromImage|upgrade.RunCommandOutput|docker":                                {Count: 3, Reason: "extractSeedFromImage creates a temporary image container, copies out the seed archive, and removes that container"},
	"cmd/seed.go:resolveSeedCommitShort|upgrade.RunCommandOutput|git":                                 {Count: 1, Reason: "resolveSeedCommitShort abbreviates HEAD for the seed image tag and provenance metadata"},
	"cmd/seed.go:seedFetchCmd.RunE|upgrade.RunCommandOutput|docker":                                   {Count: 1, Reason: "seedFetchCmd pulls the selected published seed image before extracting its database seed"},
	"cmd/seed_ancestor.go:gitFirstParentAncestors|upgrade.RunCommandOutput|git":                       {Count: 1, Reason: "gitFirstParentAncestors enumerates first-parent commits used to search backward for an eligible seed image"},
	"cmd/seed_ancestor.go:seedImagePublished|upgrade.RunCommandOutput|docker":                         {Count: 1, Reason: "seedImagePublished inspects the registry manifest to test whether a commit's seed image exists"},
	"cmd/seed_verify.go:deriveEligibilityFromGit|upgrade.RunCommandOutput|git":                        {Count: 2, Reason: "deriveEligibilityFromGit fetches history and diffs migrations since the seed commit to decide reuse eligibility"},
	"cmd/seed_verify.go:gitHasCommit|upgrade.RunCommandOutput|git":                                    {Count: 1, Reason: "gitHasCommit asks Git's object database whether the seed provenance commit is locally available"},
	"cmd/service_restart.go:restartServices|os/exec|systemctl":                                        {Count: 1, Reason: "restartServices checks whether the upgrade unit is active before coordinating a safe operator restart"},
	"cmd/test.go:testCmd.RunE|os/exec|./dev.sh":                                                       {Count: 1, Reason: "testCmd delegates the requested development test selector to the repository's dev.sh test harness"},
	"cmd/types.go:checkTypesStampGuard|upgrade.RunCommandOutput|git":                                  {Count: 4, Reason: "checkTypesStampGuard resolves HEAD, migration dirtiness, ancestry, and changed paths before trusting generated types"},
	"cmd/types.go:typesGenerateCmd.RunE|upgrade.RunCommandOutput|git":                                 {Count: 1, Reason: "typesGenerateCmd records the current commit in the generated database-types freshness stamp"},
	"cmd/upgrade.go:sshKeyFingerprint|os/exec|ssh-keygen":                                             {Count: 1, Reason: "sshKeyFingerprint derives the public-key fingerprint shown when registering a trusted upgrade signer"},
	"cmd/upgrade.go:trustKeyVerifyCmd.RunE|os/exec|git":                                               {Count: 1, Reason: "trustKeyVerifyCmd runs git verify-commit against the candidate key to prove it signs the named commit"},
	"cmd/upgrade.go:upgradeApplyLatestCmd.RunE|upgrade.RunCommandOutput|git":                          {Count: 2, Reason: "upgradeApplyLatestCmd fetches release tags and lists them by version to select the newest candidate"},
	"internal/compose/compose.go:DockerCommandContext|os/exec|docker":                                 {Count: 1, Reason: "DockerCommandContext launches validated non-up Docker commands after rejecting compose-up authority"},
	"internal/compose/compose.go:Up|os/exec|docker":                                                   {Count: 1, Reason: "compose.Up launches the sole typed docker compose up path after parsing its restricted arguments"},
	"internal/compose/compose.go:dockerComposeCommand|os/exec|docker":                                 {Count: 1, Reason: "dockerComposeCommand constructs validated docker compose subcommands other than the dedicated up path"},
	"internal/config/config.go:computeDerived|os/exec|git":                                            {Count: 2, Reason: "computeDerived reads the checkout's branch and revision to populate generated deployment metadata"},
	"internal/config/config.go:generateJWT|os/exec|node":                                              {Count: 1, Reason: "generateJWT runs the repository JWT generator with Node because the signing implementation is JavaScript"},
	"internal/freshness/check.go:CommittedDrift|os/exec|git":                                          {Count: 1, Reason: "CommittedDrift diffs the embedded binary commit against the checkout to identify committed source changes"},
	"internal/freshness/check.go:isStale|os/exec|git":                                                 {Count: 1, Reason: "isStale resolves HEAD so binary freshness can compare the built revision with the active checkout"},
	"internal/freshness/check.go:probeCommittedDrift|os/exec|git":                                     {Count: 1, Reason: "probeCommittedDrift inspects changed paths between revisions to decide whether a stale binary is affected"},
	"internal/freshness/rebuild.go:headCommit|os/exec|git":                                            {Count: 1, Reason: "headCommit resolves the checkout revision stamped into a freshly rebuilt sb binary"},
	"internal/migrate/migrate.go:CommandContext|os/exec|pg_dump":                                      {Count: 1, Reason: "migrate CommandContext constructs pg_dump when the selected migration operation creates a database backup"},
	"internal/migrate/migrate.go:CommandContext|os/exec|pg_restore":                                   {Count: 1, Reason: "migrate CommandContext constructs pg_restore when the selected migration operation restores a database archive"},
	"internal/migrate/migrate.go:CommandContext|os/exec|psql":                                         {Count: 1, Reason: "migrate CommandContext constructs psql for SQL migrations and database inspection operations"},
	"internal/migrate/migrate.go:maybeRebuildTestTemplate|os/exec|./dev.sh":                           {Count: 1, Reason: "maybeRebuildTestTemplate invokes dev.sh to rebuild the test template after migrations change its schema"},
	"internal/release/box_closure.go:deriveBoxCommandClosure|os/exec|go":                              {Count: 1, Reason: "deriveBoxCommandClosure runs go list to compute the packages reachable by binaries shipped to installations"},
	"internal/release/box_closure.go:extractTree|os/exec|git":                                         {Count: 1, Reason: "box-closure extractTree streams the requested Git tree without checking it out into the working directory"},
	"internal/release/box_closure.go:extractTree|os/exec|tar":                                         {Count: 1, Reason: "box-closure extractTree unpacks the streamed Git archive into an isolated analysis directory"},
	"internal/release/box_closure.go:goListModulePath|os/exec|go":                                     {Count: 1, Reason: "goListModulePath asks Go for the extracted tree's module path before closure analysis"},
	"internal/release/harness_validation.go:ValidateHarnessDomainAt|os/exec|bash":                     {Count: 1, Reason: "ValidateHarnessDomainAt runs the extracted install-recovery shell validators against the candidate tree"},
	"internal/release/harness_validation.go:extractHarnessTree|os/exec|git":                           {Count: 1, Reason: "extractHarnessTree archives the candidate's install-recovery harness directly from its Git tree"},
	"internal/release/harness_validation.go:extractHarnessTree|os/exec|tar":                           {Count: 1, Reason: "extractHarnessTree unpacks the candidate harness archive into a temporary validation directory"},
	"internal/release/github_auth.go:GitHubAuth|os/exec|gh":                                           {Count: 1, Reason: "GitHubAuth asks the installed GitHub CLI for the operator's existing API token when GITHUB_TOKEN is unset"},
	"internal/release/immutability.go:FileIsDirty|os/exec|git":                                        {Count: 2, Reason: "FileIsDirty checks both index and worktree diffs for the named released file"},
	"internal/release/immutability.go:MigrationExistsInTag|os/exec|git":                               {Count: 1, Reason: "MigrationExistsInTag probes the tag tree for the exact migration path under review"},
	"internal/release/immutability.go:MigrationInReleasedTag|os/exec|git":                             {Count: 1, Reason: "MigrationInReleasedTag searches released tag trees to identify whether a migration is already immutable"},
	"internal/release/immutability.go:ReleaseTagsNewestFirst|os/exec|git":                             {Count: 1, Reason: "ReleaseTagsNewestFirst lists version-sorted release tags for immutability history inspection"},
	"internal/release/immutability.go:migrationUpBlobHashInTag|os/exec|git":                           {Count: 3, Reason: "migrationUpBlobHashInTag resolves and hashes the migration blob stored in a particular release tag"},
	"internal/release/predecessor.go:CurrentImmutabilityBaselineTag|os/exec|git":                      {Count: 1, Reason: "CurrentImmutabilityBaselineTag describes tags at HEAD to select the release baseline for local checks"},
	"internal/release/predecessor.go:FindLatestStableTagBeforePrefix|os/exec|git":                     {Count: 1, Reason: "FindLatestStableTagBeforePrefix lists stable tags before a release series to locate its predecessor"},
	"internal/release/predecessor.go:ListRCNumbersForPatch|os/exec|git":                               {Count: 1, Reason: "ListRCNumbersForPatch lists matching candidate tags so the next RC number is monotonic"},
	"internal/release/predecessor.go:TagExistsLocally|os/exec|git":                                    {Count: 1, Reason: "TagExistsLocally verifies that a predecessor tag object exists before release comparison"},
	"internal/release/scenario.go:runGit|os/exec|git":                                                 {Count: 1, Reason: "release scenario runGit creates and inspects disposable repository histories used by scenario evaluation"},
	"internal/release/seed_lineage.go:gitOutput|os/exec|git":                                          {Count: 1, Reason: "seed lineage guard reads first-parent commits and migration trees from the local release repository"},
	"internal/release/sensitivity.go:DiffSensitiveChanges|os/exec|git":                                {Count: 1, Reason: "DiffSensitiveChanges lists changed paths between revisions to classify release-sensitive edits"},
	"internal/sbimage/sbimage.go:run|os/exec|git":                                                     {Count: 1, Reason: "sbimage run extracts versioned CLI sources from Git when building or inspecting an sb image"},
	"internal/selfupdate/selfupdate.go:ReplaceBinaryOnDisk|os/exec|/usr/bin/env":                      {Count: 1, Reason: "ReplaceBinaryOnDisk uses env to locate and invoke install for an atomic permission-preserving binary replacement"},
	"internal/unitfloor/unitfloor.go:isActiveSystemd|os/exec|systemctl":                               {Count: 1, Reason: "isActiveSystemd asks the user service manager whether the named unit is currently active"},
	"internal/upgrade/bundle.go:WriteBundleSections|upgrade.bundleCommandBody|docker":                 {Count: 2, Reason: "WriteBundleSections collects container inventory and logs for the upgrade diagnostic bundle"},
	"internal/upgrade/bundle.go:WriteBundleSections|upgrade.bundleCommandBody|git":                    {Count: 1, Reason: "WriteBundleSections records repository status and revision details in the upgrade diagnostic bundle"},
	"internal/upgrade/bundle.go:bundleJournalctlBody|os/exec|journalctl":                              {Count: 1, Reason: "bundleJournalctlBody captures recent upgrade-unit journal entries for post-failure diagnosis"},
	"internal/upgrade/containers.go:containersAtFlagTarget|upgrade.commandContext|docker":             {Count: 1, Reason: "containersAtFlagTarget inspects running container labels to compare them with the upgrade flag target"},
	"internal/upgrade/exec.go:backupDatabase|upgrade.runCommandToLog|docker":                          {Count: 1, Reason: "backupDatabase runs pg_dump inside the database container and streams its output to the upgrade log"},
	"internal/upgrade/exec.go:proxyContainerID|upgrade.commandContext|docker":                         {Count: 1, Reason: "proxyContainerID queries Docker for the database proxy container selected by the deployment labels"},
	"internal/upgrade/exec.go:proxyContainerMissing|upgrade.commandContext|docker":                    {Count: 1, Reason: "proxyContainerMissing inspects container state to confirm the database proxy is absent before recovery"},
	"internal/upgrade/exec.go:pullImagesForCommitShort|upgrade.commandContext|docker":                 {Count: 1, Reason: "pullImagesForCommitShort pulls the image set tagged for the candidate commit before cutover"},
	"internal/upgrade/exec.go:restoreDatabase|upgrade.runCommandToLog|docker":                         {Count: 1, Reason: "restoreDatabase runs pg_restore inside the database container from the retained upgrade backup"},
	"internal/upgrade/exec.go:runInstallFixup|os/exec|./sb":                                           {Count: 1, Reason: "runInstallFixup invokes the target sb install repair step after recovery prepares the checkout"},
	"internal/upgrade/exec.go:startDatabaseAndItsProxy|upgrade.runCommandOutput|docker":               {Count: 2, Reason: "startDatabaseAndItsProxy starts the database and proxy compose services needed for migration and health checks"},
	"internal/upgrade/exec.go:verifyRecoveryClientsStopped|upgrade.commandContext|docker":             {Count: 1, Reason: "verifyRecoveryClientsStopped lists deployment containers to prove application clients are quiesced"},
	"internal/upgrade/exec.go:waitForDBHealth|upgrade.runCommandOutput|docker":                        {Count: 1, Reason: "waitForDBHealth inspects database container health until the target reports ready"},
	"internal/upgrade/github.go:DiscoverTagsViaGit|upgrade.runCommandOutputTimeoutEnv|git":            {Count: 1, Reason: "DiscoverTagsViaGit fetches release refs with bounded credentials and timeout handling"},
	"internal/upgrade/github.go:DiscoverTagsViaGit|upgrade.runCommandOutput|git":                      {Count: 1, Reason: "DiscoverTagsViaGit lists fetched version tags to construct upgrade candidates without the API"},
	"internal/upgrade/migrate_oom_probe.go:dbLogTail|upgrade.commandContext|docker":                   {Count: 1, Reason: "dbLogTail reads the database container's recent logs after a suspected migration OOM"},
	"internal/upgrade/migrate_oom_probe.go:inspectDBContainerState|upgrade.commandContext|docker":     {Count: 2, Reason: "inspectDBContainerState reads database state and OOM flags from Docker inspection output"},
	"internal/upgrade/migrate_progress.go:runMigrateUpToLog|upgrade.commandContext|./sb":              {Count: 1, Reason: "runMigrateUpToLog launches sb migrate up while streaming progress into the durable upgrade log"},
	"internal/upgrade/recovery_backoff.go:commitObjectPresent|upgrade.runCommandOutput|git":           {Count: 1, Reason: "commitObjectPresent probes the local object database before deciding whether recovery must fetch"},
	"internal/upgrade/recovery_backoff.go:fetchWithStallDetection|upgrade.runCommandToLogCtx|git":     {Count: 1, Reason: "fetchWithStallDetection runs the recovery fetch under cancellation and progress logging"},
	"internal/upgrade/refspec.go:NormalizeOriginURL|os/exec|git":                                      {Count: 2, Reason: "NormalizeOriginURL reads and canonicalizes the repository's origin URL for safe refspec repair"},
	"internal/upgrade/refspec.go:NormalizeRefspecs|os/exec|git":                                       {Count: 2, Reason: "NormalizeRefspecs inspects and rewrites origin fetch specifications to the expected release layout"},
	"internal/upgrade/refspec.go:isGitRepo|os/exec|git":                                               {Count: 1, Reason: "isGitRepo uses rev-parse to confirm the target directory is a usable Git work tree"},
	"internal/upgrade/service.go:ReattemptRestore|upgrade.runCommand|docker":                          {Count: 1, Reason: "ReattemptRestore stops target containers before replaying a retained database restore"},
	"internal/upgrade/service.go:RevParse|upgrade.runCommandOutput|git":                               {Count: 1, Reason: "RevParse resolves upgrade revisions to full commit IDs used by service state transitions"},
	"internal/upgrade/service.go:Run|upgrade.runCommandOutput|./sb":                                   {Count: 1, Reason: "upgrade service Run asks sb for generated configuration needed before claiming scheduled work"},
	"internal/upgrade/service.go:Run|upgrade.runCommandOutput|git":                                    {Count: 1, Reason: "upgrade service Run reads repository state used to reconcile scheduled and on-disk versions"},
	"internal/upgrade/service.go:Run|upgrade.runCommandToLogCapture|./sb":                             {Count: 1, Reason: "upgrade service Run executes the claimed sb upgrade path while capturing its operator diagnostics"},
	"internal/upgrade/service.go:TagsAtCommit|upgrade.runCommandOutput|git":                           {Count: 1, Reason: "TagsAtCommit lists release tags pointing at a commit to identify its candidate version"},
	"internal/upgrade/service.go:applyClaimObligationSchemaFloor|upgrade.runCommandToLogCapture|./sb": {Count: 1, Reason: "applyClaimObligationSchemaFloor runs the bounded daemon-floor migrate so a claim can record the convergence obligation before displacing a park on a predecessor schema"},
	"internal/upgrade/service.go:applyNewSbUpgrading|upgrade.runCommandToLogCapture|docker":           {Count: 1, Reason: "applyNewSbUpgrading captures target image pull and compose preparation output during cutover"},
	"internal/upgrade/service.go:applyNewSbUpgrading|upgrade.runCommandToLog|./dev.sh":                {Count: 1, Reason: "applyNewSbUpgrading runs the repository database recreation helper when an explicit recreate upgrade requires it"},
	"internal/upgrade/service.go:applyNewSbUpgrading|upgrade.runCommandToLog|./sb":                    {Count: 1, Reason: "applyNewSbUpgrading runs target migration and configuration commands through the newly installed sb"},
	"internal/upgrade/service.go:applyNewSbUpgrading|upgrade.runCommand|git":                          {Count: 1, Reason: "applyNewSbUpgrading checks out the verified target commit before starting target services"},
	"internal/upgrade/service.go:captureContainerLogs|upgrade.commandContext|docker":                  {Count: 1, Reason: "captureContainerLogs collects the failing target containers' output for rollback diagnostics"},
	"internal/upgrade/service.go:commitMeta|upgrade.runCommandOutput|git":                             {Count: 2, Reason: "commitMeta reads the target commit's timestamp and subject for upgrade history and notifications"},
	"internal/upgrade/service.go:convergeUnchangedSourceServices|upgrade.runCommandToLog|./sb":        {Count: 1, Reason: "convergeUnchangedSourceServices asks source sb to restore unchanged services after an interrupted transition"},
	"internal/upgrade/service.go:dockerContainerImageID|upgrade.commandContext|docker":                {Count: 1, Reason: "dockerContainerImageID inspects a named container's immutable image ID for source-target comparison"},
	"internal/upgrade/service.go:dockerImageReferenceID|upgrade.commandContext|docker":                {Count: 1, Reason: "dockerImageReferenceID read-only inspects a restored source-model image reference when a pre-capture release has no surviving serving containers"},
	"internal/upgrade/service.go:ensureCommitLocal|upgrade.runCommandOutputTimeoutEnv|git":            {Count: 1, Reason: "ensureCommitLocal fetches the requested commit with bounded authentication when it is absent locally"},
	"internal/upgrade/service.go:executeUpgrade|os/exec|systemctl":                                    {Count: 1, Reason: "executeUpgrade resets the systemd failure and restart counter so takeover detection counts only the newly dispatched upgrade"},
	"internal/upgrade/service.go:executeUpgrade|upgrade.runCommandOutput|git":                         {Count: 3, Reason: "executeUpgrade resolves and checks target repository state before swapping to the new sb binary"},
	"internal/upgrade/service.go:executeUpgrade|upgrade.runCommand|docker":                            {Count: 2, Reason: "executeUpgrade inspects and copies the candidate sb binary from its verified image container"},
	"internal/upgrade/service.go:loadTrustedSigners|os/exec|ssh-keygen":                               {Count: 1, Reason: "loadTrustedSigners derives fingerprints from configured SSH public keys for signature policy matching"},
	"internal/upgrade/service.go:loadTrustedSigners|upgrade.runCommand|git":                           {Count: 1, Reason: "loadTrustedSigners points Git's SSH signature verifier at the generated allowed-signers file"},
	"internal/upgrade/service.go:migrationMaxInGitTree|upgrade.runCommandOutput|git":                  {Count: 1, Reason: "migrationMaxInGitTree lists migration files at a revision to derive that tree's schema floor"},
	"internal/upgrade/service.go:procureSbFromImage|upgrade.runCommandOutput|git":                     {Count: 1, Reason: "procureSbFromImage resolves the target commit to the eight-character tag used by the statbus-sb image"},
	"internal/upgrade/service.go:reapplyRollbackDaemonSchemaFloor|upgrade.runCommandToLog|./sb":       {Count: 1, Reason: "reapplyRollbackDaemonSchemaFloor uses source sb to restore the schema floor required by rollback services"},
	"internal/upgrade/service.go:resolveGitRestoreTarget|upgrade.runCommandOutput|git":                {Count: 2, Reason: "resolveGitRestoreTarget inspects current and source revisions to choose the safe post-rollback checkout"},
	"internal/upgrade/service.go:restoreAndFinalize|upgrade.runCommandToLog|./sb.old":                 {Count: 1, Reason: "restoreAndFinalize uses the preserved source sb binary to restore the backup and finalize rollback state"},
	"internal/upgrade/service.go:restoreGitStateFn|upgrade.runCommandOutput|git":                      {Count: 1, Reason: "restoreGitStateFn reads current repository state before restoring the recorded source revision"},
	"internal/upgrade/service.go:restoreGitStateFn|upgrade.runCommandToLog|git":                       {Count: 1, Reason: "restoreGitStateFn checks out and cleans back to the recorded source commit during rollback"},
	"internal/upgrade/service.go:restoreSourceServices|upgrade.runCommandToLog|./sb":                  {Count: 1, Reason: "restoreSourceServices invokes source sb to bring the pre-upgrade service set back online"},
	"internal/upgrade/service.go:resumeNewSb|upgrade.runCommandOutput|git":                            {Count: 1, Reason: "resumeNewSb verifies the checkout still matches the target commit before resuming a parked upgrade"},
	"internal/upgrade/service.go:rollback|upgrade.runCommand|docker":                                  {Count: 1, Reason: "rollback stops and removes target containers before restoring source data and services"},
	"internal/upgrade/service.go:runCallback|os/exec|sh":                                              {Count: 1, Reason: "runCallback executes the administrator-configured post-upgrade notification command as shell syntax"},
	"internal/upgrade/service.go:sbAlreadyAtCommit|upgrade.runCommandOutput|./sb":                     {Count: 1, Reason: "sbAlreadyAtCommit queries the installed binary's build stamp to avoid replacing it with the same commit"},
	"internal/upgrade/service.go:selfUpdate|upgrade.runCommandOutput|git":                             {Count: 1, Reason: "selfUpdate lists commits ahead of the release manifest so edge checkouts are not downgraded"},
	"internal/upgrade/service.go:sourceServingContainerEntries|upgrade.commandContext|docker":         {Count: 1, Reason: "sourceServingContainerEntries lists source application containers and their image identities for recovery"},
	"internal/upgrade/service.go:sourceServingExpectedImageReferences|upgrade.commandContext|docker":  {Count: 1, Reason: "sourceServingExpectedImageReferences renders source compose image references from the recorded checkout"},
	"internal/upgrade/service.go:sourceServingExpectedImageReferences|upgrade.runCommandOutput|git":   {Count: 1, Reason: "sourceServingExpectedImageReferences verifies the source checkout revision used to render expected images"},
	"internal/upgrade/service.go:stopAndVerifyRecoveryClients|upgrade.runCommand|docker":              {Count: 1, Reason: "stopAndVerifyRecoveryClients stops application clients before database recovery and then verifies quiescence"},
	"internal/upgrade/service.go:verifyArtifacts|upgrade.runCommandOutput|docker":                     {Count: 1, Reason: "verifyArtifacts inspects candidate image manifests and labels before allowing upgrade execution"},
	"internal/upgrade/service.go:verifyArtifacts|upgrade.runCommandOutput|git":                        {Count: 1, Reason: "verifyArtifacts resolves candidate source metadata used to cross-check the published images"},
	"internal/upgrade/service.go:verifyBinaryObservedState|upgrade.runCommandOutput|git":              {Count: 2, Reason: "verifyBinaryObservedState compares the running binary stamp with repository commits during recovery classification"},
	"internal/upgrade/service.go:verifyCommitSignature|upgrade.runCommandOutput|git":                  {Count: 1, Reason: "verifyCommitSignature runs Git signature verification for the exact candidate commit"},
}

type authorityProcessWrapperSpec struct {
	executableArg int
	argumentsFrom int
}

// These wrappers all reach commandContext and therefore carry process-launch
// authority. The gate resolves them by function object, exactly as it resolves
// os/exec itself, so every caller must present a statically reviewed executable.
var authorityProcessWrappers = map[string]authorityProcessWrapperSpec{
	"RunCommandOutput":           {executableArg: 1, argumentsFrom: 2},
	"commandContext":             {executableArg: 2, argumentsFrom: 3},
	"runCommand":                 {executableArg: 1, argumentsFrom: 2},
	"runCommandOutput":           {executableArg: 1, argumentsFrom: 2},
	"runCommandOutputTimeout":    {executableArg: 2, argumentsFrom: 3},
	"runCommandOutputTimeoutEnv": {executableArg: 3, argumentsFrom: 4},
	"runCommandToLog":            {executableArg: 5, argumentsFrom: 6},
	"runCommandToLogCapture":     {executableArg: 5, argumentsFrom: 6},
	"runCommandToLogCtx":         {executableArg: 5, argumentsFrom: 6},
	"runCommandWithTimeout":      {executableArg: 2, argumentsFrom: 3},
	"bundleCommandBody":          {executableArg: 2, argumentsFrom: 3},
}

// Dynamic executables are forbidden at reviewed call sites. These are the
// exact internal forwarding edges which merely preserve an executable that the
// gate separately validates at each wrapper's callers.
var allowedDynamicProcessForwarders = map[string]approvedLaunch{
	"internal/upgrade/bundle.go:bundleCommandBody|upgrade.commandContext":                 {Count: 1, Reason: "bundleCommandBody forwards a reviewed bundle executable into commandContext while preserving section-specific arguments"},
	"internal/upgrade/exec.go:RunCommandOutput|upgrade.runCommandOutput":                  {Count: 1, Reason: "RunCommandOutput forwards its public constant executable to the output-capturing runner"},
	"internal/upgrade/exec.go:commandContext|os/exec":                                     {Count: 1, Reason: "commandContext performs the final os/exec construction after applying Git arguments or Docker validation"},
	"internal/upgrade/exec.go:runCommand|upgrade.runCommandWithTimeout":                   {Count: 1, Reason: "runCommand forwards the selected executable to the timeout-enforced command runner"},
	"internal/upgrade/exec.go:runCommandOutput|upgrade.runCommandOutputTimeout":           {Count: 1, Reason: "runCommandOutput forwards the executable to the output runner with the default timeout"},
	"internal/upgrade/exec.go:runCommandOutputTimeout|upgrade.runCommandOutputTimeoutEnv": {Count: 1, Reason: "runCommandOutputTimeout forwards the executable while supplying the inherited environment"},
	"internal/upgrade/exec.go:runCommandOutputTimeoutEnv|upgrade.commandContext":          {Count: 1, Reason: "runCommandOutputTimeoutEnv constructs the validated command before applying timeout and environment"},
	"internal/upgrade/exec.go:runCommandToLog|upgrade.runCommandToLogCtx":                 {Count: 1, Reason: "runCommandToLog forwards the executable into the context-aware durable logging runner"},
	"internal/upgrade/exec.go:runCommandToLogCapture|upgrade.commandContext":              {Count: 1, Reason: "runCommandToLogCapture constructs the validated command whose combined output is captured in logs"},
	"internal/upgrade/exec.go:runCommandToLogCtx|upgrade.commandContext":                  {Count: 1, Reason: "runCommandToLogCtx constructs the validated command attached to the caller's cancellation context"},
	"internal/upgrade/exec.go:runCommandWithTimeout|upgrade.commandContext":               {Count: 1, Reason: "runCommandWithTimeout constructs the validated command governed by the requested timeout"},
}

type authorityExecutableClass string

const (
	authorityTool     authorityExecutableClass = "tool"
	authorityMediator authorityExecutableClass = "mediator"
)

// This is the complete type-resolved production executable inventory. Entries
// are semantic classes, not a blocklist: an unknown executable fails closed, and
// every entry must retain at least one production use so stale authority cannot
// silently accumulate.
var allowedProcessExecutables = map[string]authorityExecutableClass{
	"./dev.sh":     authorityTool,
	"./sb":         authorityTool,
	"./sb.old":     authorityTool,
	"/usr/bin/env": authorityMediator,
	"bash":         authorityMediator,
	"docker":       authorityTool,
	"git":          authorityTool,
	"gh":           authorityTool,
	"go":           authorityTool,
	"journalctl":   authorityTool,
	"loginctl":     authorityTool,
	"node":         authorityTool,
	"pg_dump":      authorityTool,
	"pg_restore":   authorityTool,
	"psql":         authorityTool,
	"scp":          authorityTool,
	"sh":           authorityMediator,
	"ssh":          authorityTool,
	"ssh-keygen":   authorityTool,
	"systemctl":    authorityTool,
	"tar":          authorityTool,
}

const pinnedReexecMarker = "authority:pinned-reexec"

// These existing syscall.Exec handoffs replace the current process with a path
// resolved from the already-selected psql or sb binary. Each exception requires
// the marker on the immediately preceding line and exactly one call in the named
// file/function. A second call in the function does not inherit the exception.
var allowedDynamicSyscallExecHandoffs = map[string]approvedLaunch{
	"cmd/psql.go:psqlCmd.RunE":                       {Count: 1, Reason: "psql command hands the process to the resolved database client binary"},
	"internal/freshness/rebuild.go:RebuildAndReexec": {Count: 1, Reason: "freshness rebuild hands the process to the newly rebuilt sb binary"},
	"internal/upgrade/service.go:executeUpgrade":     {Count: 1, Reason: "recovery re-exec handoff after binary swap"},
}

// These are pre-existing, explicit user/configuration command facilities rather
// than source-authored recovery commands. Their exact mediator executable and
// site are pinned so an added dynamic mediator call, even in the same function,
// changes the inventory and fails. All other mediator arguments must be
// compile-time constants and must not contain authority tokens.
var allowedIntentionalDynamicMediatorCalls = map[string]approvedLaunch{
	"cmd/db_with_seed_lock.go:withSeedLockCmd.RunE|/usr/bin/env":         {Count: 1, Reason: "operator seed-lock command intentionally executes the user-selected command via env"},
	"cmd/dotenv.go:dotenvGenerateCmd.RunE|sh":                            {Count: 1, Reason: "dotenv generation intentionally runs the configured shell fragment"},
	"cmd/install.go:runInstallCallback|sh":                               {Count: 1, Reason: "install completion intentionally runs the configured callback shell command"},
	"internal/selfupdate/selfupdate.go:ReplaceBinaryOnDisk|/usr/bin/env": {Count: 1, Reason: "self-update intentionally invokes the platform install utility via env"},
	"internal/upgrade/service.go:runCallback|sh":                         {Count: 1, Reason: "upgrade completion intentionally runs the configured callback shell command"},
}

type authorityProcessLaunch struct {
	kind       string
	executable ast.Expr
	arguments  []ast.Expr
	argsKnown  bool
}

func authorityCallProcessLaunch(call *ast.CallExpr, info *types.Info) (authorityProcessLaunch, bool) {
	function := calledFunctionObject(call, info)
	if function == nil || function.Pkg() == nil {
		return authorityProcessLaunch{}, false
	}
	argumentSlice := func(index int) ([]ast.Expr, bool) {
		if len(call.Args) <= index {
			return nil, false
		}
		literal, ok := call.Args[index].(*ast.CompositeLit)
		if !ok {
			return nil, false
		}
		arguments := append([]ast.Expr(nil), literal.Elts...)
		return arguments, true
	}

	switch function.Pkg().Path() {
	case execPackagePath:
		switch function.Name() {
		case "Command":
			if len(call.Args) == 0 {
				return authorityProcessLaunch{kind: "os/exec", argsKnown: true}, true
			}
			return authorityProcessLaunch{kind: "os/exec", executable: call.Args[0], arguments: call.Args[1:], argsKnown: call.Ellipsis == token.NoPos}, true
		case "CommandContext":
			if len(call.Args) <= 1 {
				return authorityProcessLaunch{kind: "os/exec", argsKnown: true}, true
			}
			return authorityProcessLaunch{kind: "os/exec", executable: call.Args[1], arguments: call.Args[2:], argsKnown: call.Ellipsis == token.NoPos}, true
		}
	case osPackagePath:
		if function.Name() == "StartProcess" {
			launch := authorityProcessLaunch{kind: "os.StartProcess"}
			if len(call.Args) != 0 {
				launch.executable = call.Args[0]
			}
			launch.arguments, launch.argsKnown = argumentSlice(1)
			return launch, true
		}
	case syscallPackagePath:
		if function.Name() == "Exec" || function.Name() == "ForkExec" {
			launch := authorityProcessLaunch{kind: "syscall." + function.Name()}
			if len(call.Args) != 0 {
				launch.executable = call.Args[0]
			}
			launch.arguments, launch.argsKnown = argumentSlice(1)
			return launch, true
		}
	case upgradePackagePath:
		spec, ok := authorityProcessWrappers[function.Name()]
		if !ok {
			return authorityProcessLaunch{}, false
		}
		launch := authorityProcessLaunch{kind: "upgrade." + function.Name(), argsKnown: call.Ellipsis == token.NoPos}
		if len(call.Args) > spec.executableArg {
			launch.executable = call.Args[spec.executableArg]
		}
		if len(call.Args) > spec.argumentsFrom {
			launch.arguments = call.Args[spec.argumentsFrom:]
		}
		return launch, true
	}
	return authorityProcessLaunch{}, false
}

func authorityExecCmdLiteral(literal *ast.CompositeLit, info *types.Info) (authorityProcessLaunch, bool) {
	typeOf := info.TypeOf(literal.Type)
	named, ok := typeOf.(*types.Named)
	if !ok || named.Obj().Pkg() == nil || named.Obj().Pkg().Path() != execPackagePath || named.Obj().Name() != "Cmd" {
		return authorityProcessLaunch{}, false
	}
	launch := authorityProcessLaunch{kind: "os/exec.Cmd literal"}
	for _, element := range literal.Elts {
		field, ok := element.(*ast.KeyValueExpr)
		if !ok {
			continue
		}
		name, ok := field.Key.(*ast.Ident)
		if !ok {
			continue
		}
		switch name.Name {
		case "Path":
			launch.executable = field.Value
		case "Args":
			arguments, ok := field.Value.(*ast.CompositeLit)
			if !ok {
				continue
			}
			launch.argsKnown = true
			launch.arguments = append(launch.arguments, arguments.Elts...)
		}
	}
	return launch, true
}

func authorityConstantString(info *types.Info, expression ast.Expr) (string, bool) {
	if expression == nil {
		return "", false
	}
	value := info.Types[expression].Value
	if value == nil || value.Kind() != constant.String {
		return "", false
	}
	return constant.StringVal(value), true
}

func authorityContainsComposeAuthorityToken(argument string) bool {
	tokens := strings.FieldsFunc(argument, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_'
	})
	for _, token := range tokens {
		switch strings.ToLower(token) {
		case "docker", "docker-compose", "podman", "compose":
			return true
		}
	}
	return false
}

func authorityPinnedReexecMarkerLines(file *ast.File, fset *token.FileSet) map[int]bool {
	markers := make(map[int]bool)
	for _, group := range file.Comments {
		for _, comment := range group.List {
			text := strings.TrimSpace(strings.TrimPrefix(comment.Text, "//"))
			if text == pinnedReexecMarker {
				markers[fset.Position(comment.End()).Line] = true
			}
		}
	}
	return markers
}

func authorityProcessLaunchViolations(launch authorityProcessLaunch, key, packagePath string, line int, info *types.Info, pinnedReexec bool, gotProcessLaunches, gotPinnedReexecHandoffs, gotIntentionalDynamicMediatorCalls, gotDynamicProcessForwarders, gotExecutableUses map[string]int) []string {
	var violations []string
	executable, executableConstant := authorityConstantString(info, launch.executable)
	_, handoffAllowed := allowedDynamicSyscallExecHandoffs[key]
	dynamicHandoff := launch.kind == "syscall.Exec" && handoffAllowed && pinnedReexec
	if !executableConstant {
		if dynamicHandoff {
			gotPinnedReexecHandoffs[key]++
		} else if forwarderKey := key + "|" + launch.kind; allowedDynamicProcessForwarders[forwarderKey].Count != 0 {
			gotDynamicProcessForwarders[forwarderKey]++
		} else {
			violations = append(violations, fmt.Sprintf("dynamic %s executable at %s:%d (no entry: new site, investigate and add with reason)", launch.kind, key, line))
		}
		return violations
	}
	class, executableAllowed := allowedProcessExecutables[executable]
	if !executableAllowed {
		violations = append(violations, fmt.Sprintf("unknown %s executable %q at %s:%d", launch.kind, executable, key, line))
		return violations
	}
	launchKey := key + "|" + launch.kind + "|" + executable
	gotProcessLaunches[launchKey]++
	if _, allowed := allowedProcessLaunches[launchKey]; !allowed {
		violations = append(violations, fmt.Sprintf("unallowlisted %s executable %q at %s:%d (no entry: new site, investigate and add with reason)", launch.kind, executable, key, line))
	}
	gotExecutableUses[executable]++
	throughUpgradeWrapper := strings.HasPrefix(launch.kind, "upgrade.")
	if (executable == "docker" || executable == "docker-compose") && packagePath != composePackagePath && !throughUpgradeWrapper {
		violations = append(violations, fmt.Sprintf("raw %s process launch outside compose wrapper at %s:%d", executable, key, line))
	}
	hasDynamicArgument := !launch.argsKnown
	for _, argumentExpression := range launch.arguments {
		argument, ok := authorityConstantString(info, argumentExpression)
		if !ok {
			hasDynamicArgument = true
			continue
		}
		if authorityContainsComposeAuthorityToken(argument) && (!throughUpgradeWrapper || executable != "docker") {
			violations = append(violations, fmt.Sprintf("%s argument contains docker/docker-compose/podman/compose authority for %s at %s:%d", class, executable, key, line))
		}
	}
	if class == authorityMediator && hasDynamicArgument {
		allowanceKey := key + "|" + executable
		if _, allowed := allowedIntentionalDynamicMediatorCalls[allowanceKey]; allowed {
			gotIntentionalDynamicMediatorCalls[allowanceKey]++
		} else {
			violations = append(violations, fmt.Sprintf("dynamic mediator argument for %s at %s:%d (no entry: new site, investigate and add with reason)", executable, key, line))
		}
	}
	return violations
}

func authorityParents(root ast.Node) map[ast.Node]ast.Node {
	parents := make(map[ast.Node]ast.Node)
	var stack []ast.Node
	ast.Inspect(root, func(node ast.Node) bool {
		if node == nil {
			stack = stack[:len(stack)-1]
			return true
		}
		if len(stack) != 0 {
			parents[node] = stack[len(stack)-1]
		}
		stack = append(stack, node)
		return true
	})
	return parents
}

func authorityEnclosingFunction(file string, node ast.Node, parents map[ast.Node]ast.Node) string {
	insideFuncLiteral := false
	fieldName := "func"
	for current := node; current != nil; current = parents[current] {
		if fn, ok := current.(*ast.FuncDecl); ok {
			return file + ":" + fn.Name.Name
		}
		if _, ok := current.(*ast.FuncLit); ok {
			insideFuncLiteral = true
		}
		if insideFuncLiteral {
			if keyValue, ok := current.(*ast.KeyValueExpr); ok {
				if ident, ok := keyValue.Key.(*ast.Ident); ok {
					fieldName = ident.Name
				}
			}
			if spec, ok := current.(*ast.ValueSpec); ok && len(spec.Names) != 0 {
				return file + ":" + spec.Names[0].Name + "." + fieldName
			}
		}
	}
	return file + ":<package>"
}

func calledFunctionObject(call *ast.CallExpr, info *types.Info) *types.Func {
	switch fun := call.Fun.(type) {
	case *ast.Ident:
		object, _ := info.Uses[fun].(*types.Func)
		return object
	case *ast.SelectorExpr:
		object, _ := info.Uses[fun.Sel].(*types.Func)
		return object
	default:
		return nil
	}
}

func directCallForObjectUse(ident *ast.Ident, parents map[ast.Node]ast.Node) (*ast.CallExpr, bool) {
	parent := parents[ident]
	if call, ok := parent.(*ast.CallExpr); ok && call.Fun == ident {
		return call, true
	}
	selector, ok := parent.(*ast.SelectorExpr)
	if !ok || selector.Sel != ident {
		return nil, false
	}
	call, ok := parents[selector].(*ast.CallExpr)
	return call, ok && call.Fun == selector
}

func authorityProcessFunctionKind(function *types.Func) (string, bool) {
	if function == nil || function.Pkg() == nil {
		return "", false
	}
	switch function.Pkg().Path() {
	case execPackagePath:
		if function.Name() == "Command" || function.Name() == "CommandContext" {
			return "os/exec." + function.Name(), true
		}
	case osPackagePath:
		if function.Name() == "StartProcess" {
			return "os.StartProcess", true
		}
	case syscallPackagePath:
		if function.Name() == "Exec" || function.Name() == "ForkExec" {
			return "syscall." + function.Name(), true
		}
	case upgradePackagePath:
		if _, ok := authorityProcessWrappers[function.Name()]; ok {
			return "upgrade." + function.Name(), true
		}
	}
	return "", false
}

func collectPackageErrors(pkgs []*packages.Package) []string {
	seen := make(map[string]bool)
	var errors []string
	var visit func(*packages.Package)
	visit = func(pkg *packages.Package) {
		if pkg == nil || seen[pkg.ID] {
			return
		}
		seen[pkg.ID] = true
		for _, pkgErr := range pkg.Errors {
			errors = append(errors, pkgErr.Error())
		}
		for _, imported := range pkg.Imports {
			visit(imported)
		}
	}
	for _, pkg := range pkgs {
		visit(pkg)
	}
	sort.Strings(errors)
	return errors
}

func loadTypedAuthorityPackages(cliDir, goos string, overlay map[string][]byte) ([]typedAuthorityPackage, error) {
	env := append([]string{}, os.Environ()...)
	env = append(env, "GOOS="+goos, "CGO_ENABLED=0")
	config := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles |
			packages.NeedSyntax | packages.NeedTypes | packages.NeedTypesInfo |
			packages.NeedDeps | packages.NeedImports | packages.NeedModule,
		Dir:     cliDir,
		Env:     env,
		Overlay: overlay,
	}
	pkgs, err := packages.Load(config, "./...")
	if err != nil {
		return nil, fmt.Errorf("load CLI packages for GOOS=%s: %w", goos, err)
	}
	if pkgErrors := collectPackageErrors(pkgs); len(pkgErrors) != 0 {
		return nil, fmt.Errorf("type-check CLI packages for GOOS=%s:\n%s", goos, strings.Join(pkgErrors, "\n"))
	}
	var result []typedAuthorityPackage
	for _, pkg := range pkgs {
		for i, file := range pkg.Syntax {
			filename := pkg.CompiledGoFiles[i]
			rel, relErr := filepath.Rel(cliDir, filename)
			if relErr != nil {
				return nil, relErr
			}
			result = append(result, typedAuthorityPackage{pkg: pkg, file: file, path: filepath.ToSlash(rel)})
		}
	}
	return result, nil
}

func productionGoFiles(cliDir string) (map[string]bool, error) {
	files := make(map[string]bool)
	err := filepath.WalkDir(cliDir, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") || strings.HasSuffix(entry.Name(), "_test.go") {
			return nil
		}
		rel, err := filepath.Rel(cliDir, path)
		if err != nil {
			return err
		}
		files[filepath.ToSlash(rel)] = true
		return nil
	})
	return files, err
}

func typedAuthorityViolation(cliDir string, overlay map[string][]byte) error {
	gooses := []string{"linux", "darwin"}
	if runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
		gooses = append(gooses, runtime.GOOS)
	}
	loadedFiles := make(map[string]bool)
	gotUpCalls := make(map[string]int)
	gotProcessLaunches := make(map[string]int)
	seenUpUse := make(map[string]bool)
	seenProcessLaunch := make(map[string]bool)
	seenPinnedReexecMarkers := make(map[string]bool)
	usedPinnedReexecMarkers := make(map[string]bool)
	gotPinnedReexecHandoffs := make(map[string]int)
	gotIntentionalDynamicMediatorCalls := make(map[string]int)
	gotDynamicProcessForwarders := make(map[string]int)
	gotExecutableUses := make(map[string]int)
	var violations []string

	for _, goos := range gooses {
		files, err := loadTypedAuthorityPackages(cliDir, goos, overlay)
		if err != nil {
			return err
		}
		for _, typedFile := range files {
			loadedFiles[typedFile.path] = true
			parents := authorityParents(typedFile.file)
			pinnedReexecMarkers := authorityPinnedReexecMarkerLines(typedFile.file, typedFile.pkg.Fset)
			for markerLine := range pinnedReexecMarkers {
				seenPinnedReexecMarkers[fmt.Sprintf("%s:%d", typedFile.path, markerLine)] = true
			}
			info := typedFile.pkg.TypesInfo
			ast.Inspect(typedFile.file, func(node ast.Node) bool {
				if ident, ok := node.(*ast.Ident); ok {
					object, _ := info.Uses[ident].(*types.Func)
					position := typedFile.pkg.Fset.Position(ident.Pos())
					location := fmt.Sprintf("%s:%d:%d", typedFile.path, position.Line, position.Column)
					if object != nil && object.Pkg() != nil && object.Pkg().Path() == composePackagePath && object.Name() == "Up" && !seenUpUse[location] {
						seenUpUse[location] = true
						call, direct := directCallForObjectUse(ident, parents)
						key := authorityEnclosingFunction(typedFile.path, ident, parents)
						if !direct {
							violations = append(violations, fmt.Sprintf("compose.Up used as a value at %s", key))
						} else if _, allowed := allowedComposeUpCalls[key]; !allowed {
							violations = append(violations, fmt.Sprintf("unallowlisted direct compose.Up call at %s:%d", key, typedFile.pkg.Fset.Position(call.Pos()).Line))
						} else {
							gotUpCalls[key]++
						}
					}
					if kind, launcher := authorityProcessFunctionKind(object); launcher {
						if _, direct := directCallForObjectUse(ident, parents); !direct {
							key := authorityEnclosingFunction(typedFile.path, ident, parents)
							violations = append(violations, fmt.Sprintf("%s used as a value at %s", kind, key))
						}
					}
				}

				var launch authorityProcessLaunch
				var launcherNode ast.Node
				var found bool
				switch typedNode := node.(type) {
				case *ast.CallExpr:
					launch, found = authorityCallProcessLaunch(typedNode, info)
					launcherNode = typedNode
				case *ast.CompositeLit:
					launch, found = authorityExecCmdLiteral(typedNode, info)
					launcherNode = typedNode
				}
				if !found {
					return true
				}
				position := typedFile.pkg.Fset.Position(launcherNode.Pos())
				location := fmt.Sprintf("%s:%d:%d:%s", typedFile.path, position.Line, position.Column, launch.kind)
				key := authorityEnclosingFunction(typedFile.path, launcherNode, parents)
				markerLine := position.Line - 1
				pinnedReexec := pinnedReexecMarkers[markerLine]
				_, allowedPinnedFunction := allowedDynamicSyscallExecHandoffs[key]
				_, executableConstant := authorityConstantString(info, launch.executable)
				if pinnedReexec && launch.kind == "syscall.Exec" && allowedPinnedFunction && !executableConstant {
					usedPinnedReexecMarkers[fmt.Sprintf("%s:%d", typedFile.path, markerLine)] = true
				}
				if seenProcessLaunch[location] {
					return true
				}
				seenProcessLaunch[location] = true
				violations = append(violations, authorityProcessLaunchViolations(launch, key, typedFile.pkg.PkgPath, position.Line, info, pinnedReexec, gotProcessLaunches, gotPinnedReexecHandoffs, gotIntentionalDynamicMediatorCalls, gotDynamicProcessForwarders, gotExecutableUses)...)
				return true
			})
		}
	}
	for markerLocation := range seenPinnedReexecMarkers {
		if !usedPinnedReexecMarkers[markerLocation] {
			violations = append(violations, fmt.Sprintf("%s marker at %s is not adjacent to an allowed dynamic syscall.Exec handoff", pinnedReexecMarker, markerLocation))
		}
	}

	allFiles, err := productionGoFiles(cliDir)
	if err != nil {
		return err
	}
	for file := range allFiles {
		if !loadedFiles[file] {
			violations = append(violations, "production Go file was hidden from all typed package loads: "+file)
		}
	}
	approvedTables := []struct {
		name    string
		entries map[string]approvedLaunch
	}{
		{name: "compose.Up calls", entries: allowedComposeUpCalls},
		{name: "process launches", entries: allowedProcessLaunches},
		{name: "dynamic process forwarders", entries: allowedDynamicProcessForwarders},
		{name: "dynamic syscall.Exec handoffs", entries: allowedDynamicSyscallExecHandoffs},
		{name: "intentional dynamic mediator calls", entries: allowedIntentionalDynamicMediatorCalls},
	}
	for _, table := range approvedTables {
		for key, approval := range table.entries {
			if strings.TrimSpace(approval.Reason) == "" {
				violations = append(violations, fmt.Sprintf("%s allowlist entry %s has an empty approval reason", table.name, key))
			}
		}
	}
	for key, want := range allowedComposeUpCalls {
		if gotUpCalls[key] != want.Count {
			violations = append(violations, fmt.Sprintf("compose.Up call inventory at %s = %d, want %d; approved because: %s", key, gotUpCalls[key], want.Count, want.Reason))
		}
	}
	for key, want := range allowedProcessLaunches {
		if gotProcessLaunches[key] != want.Count {
			violations = append(violations, fmt.Sprintf("process launch inventory at %s = %d, want %d; approved because: %s", key, gotProcessLaunches[key], want.Count, want.Reason))
		}
	}
	for key, want := range allowedIntentionalDynamicMediatorCalls {
		if gotIntentionalDynamicMediatorCalls[key] != want.Count {
			violations = append(violations, fmt.Sprintf("intentional dynamic mediator call inventory at %s = %d, want %d; approved because: %s", key, gotIntentionalDynamicMediatorCalls[key], want.Count, want.Reason))
		}
	}
	for key, want := range allowedDynamicSyscallExecHandoffs {
		if gotPinnedReexecHandoffs[key] != want.Count {
			violations = append(violations, fmt.Sprintf("pinned dynamic syscall.Exec inventory at %s = %d, want %d; approved because: %s", key, gotPinnedReexecHandoffs[key], want.Count, want.Reason))
		}
	}
	for key, want := range allowedDynamicProcessForwarders {
		if gotDynamicProcessForwarders[key] != want.Count {
			violations = append(violations, fmt.Sprintf("dynamic process forwarder inventory at %s = %d, want %d; approved because: %s", key, gotDynamicProcessForwarders[key], want.Count, want.Reason))
		}
	}
	for executable, class := range allowedProcessExecutables {
		if class != authorityTool && class != authorityMediator {
			violations = append(violations, fmt.Sprintf("invalid executable class %q for allowlist entry %q", class, executable))
		}
		if gotExecutableUses[executable] == 0 {
			violations = append(violations, fmt.Sprintf("stale executable allowlist entry %q has zero production uses", executable))
		}
	}
	if len(violations) != 0 {
		sort.Strings(violations)
		return fmt.Errorf("typed compose authority gate:\n%s", strings.Join(violations, "\n"))
	}
	return nil
}

func TestTypedComposeAuthorityGate(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	if err := typedAuthorityViolation(cliDir, nil); err != nil {
		t.Fatal(err)
	}
}

func TestApprovedLaunchesHaveReasons(t *testing.T) {
	const maxSharedReasonSites = 1

	approvedTables := map[string]map[string]approvedLaunch{
		"compose.Up calls":                   allowedComposeUpCalls,
		"process launches":                   allowedProcessLaunches,
		"dynamic process forwarders":         allowedDynamicProcessForwarders,
		"dynamic syscall.Exec handoffs":      allowedDynamicSyscallExecHandoffs,
		"intentional dynamic mediator calls": allowedIntentionalDynamicMediatorCalls,
	}
	reasonSites := make(map[string][]string)
	boilerplatePatterns := []string{
		"is a version-control tool",
		"standard tool",
		"approved",
		"archive creation or extraction",
		"compose wrapper implementation",
		"database client selected by the migration layer",
		"docker request is routed by commandcontext",
		"exact tool and call site are pinned",
		"host service or journal operation",
		"intentional command mediator",
		"internal forwarding edge only",
		"remote operator transport or key verification",
		"repository inspection or controlled checkout/tag operation",
		"repository-local operational subprocess",
	}
	for tableName, entries := range approvedTables {
		for site, approval := range entries {
			reason := strings.TrimSpace(approval.Reason)
			if reason == "" {
				t.Errorf("%s allowlist entry %s has an empty approval reason", tableName, site)
				continue
			}
			qualifiedSite := tableName + ": " + site
			reasonSites[reason] = append(reasonSites[reason], qualifiedSite)
			lowerReason := strings.ToLower(reason)
			for _, pattern := range boilerplatePatterns {
				if strings.Contains(lowerReason, pattern) {
					t.Errorf("%s reason %q contains generic boilerplate %q", qualifiedSite, reason, pattern)
				}
			}
		}
	}
	for reason, sites := range reasonSites {
		if len(sites) <= maxSharedReasonSites {
			continue
		}
		sort.Strings(sites)
		t.Errorf("approval reason is shared by %d sites (maximum %d): %q\n  %s", len(sites), maxSharedReasonSites, reason, strings.Join(sites, "\n  "))
	}
}

func authorityOverlay(t *testing.T, cliDir, rel string, mutate func(string) string) map[string][]byte {
	t.Helper()
	path := filepath.Join(cliDir, filepath.FromSlash(rel))
	source, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return map[string][]byte{path: []byte(mutate(string(source)))}
}

func withAuthorityMutationPackage(t *testing.T, cliDir, source string, check func(error)) {
	t.Helper()
	dir, err := os.MkdirTemp(filepath.Join(cliDir, "internal"), "authoritymutation")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	if err := os.WriteFile(filepath.Join(dir, "mutation.go"), []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	check(typedAuthorityViolation(cliDir, nil))
}

func TestTypedComposeAuthorityRejectsAssignedUpFunction(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/service.go", func(source string) string {
		return source + "\nvar assignedComposeUpMutation = compose.Up\n"
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "compose.Up used as a value") {
		t.Fatalf("assigned compose.Up mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsReflectedUpFunction(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/service.go", func(source string) string {
		source = strings.Replace(source, "\t\"os\"\n", "\t\"os\"\n\t\"reflect\"\n", 1)
		return source + "\nvar reflectedComposeUpMutation = reflect.ValueOf(compose.Up)\n"
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "compose.Up used as a value") {
		t.Fatalf("reflected compose.Up mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsAliasedExecImport(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	withAuthorityMutationPackage(t, cliDir, `package authoritymutation
import (
    "context"
    e "os/exec"
)
func Run(ctx context.Context) *e.Cmd {
    return e.CommandContext(ctx, "docker", "compose", "up", "-d", "app")
}
`, func(err error) {
		if err == nil || !strings.Contains(err.Error(), `unallowlisted os/exec executable "docker"`) || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
			t.Fatalf("aliased os/exec mutation survived: %v", err)
		}
	})
}

func TestTypedComposeAuthorityRejectsDotImportedExec(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	withAuthorityMutationPackage(t, cliDir, `package authoritymutation
import . "os/exec"
func Run() *Cmd {
    return Command("docker", "compose", "up", "-d", "app")
}
`, func(err error) {
		if err == nil || !strings.Contains(err.Error(), `unallowlisted os/exec executable "docker"`) || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
			t.Fatalf("dot-imported os/exec mutation survived: %v", err)
		}
	})
}

func TestTypedComposeAuthorityRejectsDynamicExecutable(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	withAuthorityMutationPackage(t, cliDir, `package authoritymutation
import (
    "os"
    "os/exec"
)
func Run() *exec.Cmd {
    return exec.Command(os.Getenv("DOCKER_BIN"), "compose", "up", "-d", "app")
}
`, func(err error) {
		if err == nil || !strings.Contains(err.Error(), "dynamic os/exec executable") {
			t.Fatalf("dynamic executable mutation survived: %v", err)
		}
	})
}

func TestTypedComposeAuthorityRejectsDynamicCommandWrapperExecutable(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "internal/upgrade/exec.go", func(source string) string {
		return source + "\nfunc authorityDynamicWrapperMutation(dir, name string) { _, _ = runCommandOutput(dir, name) }\n"
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "dynamic upgrade.runCommandOutput executable") {
		t.Fatalf("dynamic command-wrapper executable mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsUnknownCommandWrapperExecutable(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "internal/upgrade/exec.go", func(source string) string {
		return source + "\nfunc authorityUnknownWrapperMutation(dir string) { _, _ = runCommandOutput(dir, \"frobnicate\", \"status\") }\n"
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), `unknown upgrade.runCommandOutput executable "frobnicate"`) {
		t.Fatalf("unknown command-wrapper executable mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsShellPayloadInComposeWrapper(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "internal/compose/compose.go", func(source string) string {
		anchor := "func dockerComposeCommand(ctx context.Context, projDir string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"sh\", \"-c\", \"docker compose up\")\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "argument contains docker/docker-compose/podman/compose authority") {
		t.Fatalf("compose-wrapper shell mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsShellPayloadInInstallCommand(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/install.go", func(source string) string {
		anchor := "func commandContextDir(ctx context.Context, dir string, name string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"sh\", \"-c\", \"docker compose up\")\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "argument contains docker/docker-compose/podman/compose authority") {
		t.Fatalf("install shell mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsOSStartProcessDocker(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/install.go", func(source string) string {
		anchor := "func commandContextDir(ctx context.Context, dir string, name string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_, _ = os.StartProcess(\"docker\", []string{\"docker\", \"compose\", \"up\"}, &os.ProcAttr{})\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
		t.Fatalf("os.StartProcess docker mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsSyscallExecDocker(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/install.go", func(source string) string {
		anchor := "func commandContextDir(ctx context.Context, dir string, name string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = syscall.Exec(\"docker\", []string{\"docker\", \"compose\", \"up\"}, os.Environ())\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
		t.Fatalf("syscall.Exec docker mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsSyscallForkExecDocker(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	withAuthorityMutationPackage(t, cliDir, `package authoritymutation
import "syscall"
func Run() (int, error) {
    return syscall.ForkExec("docker", []string{"docker", "compose", "up"}, &syscall.ProcAttr{})
}
`, func(err error) {
		if err == nil || !strings.Contains(err.Error(), `unallowlisted syscall.ForkExec executable "docker"`) || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
			t.Fatalf("syscall.ForkExec docker mutation survived: %v", err)
		}
	})
}

func TestTypedComposeAuthorityRejectsExecCmdLiteralDocker(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	withAuthorityMutationPackage(t, cliDir, `package authoritymutation
import "os/exec"
func Run() *exec.Cmd {
    return &exec.Cmd{Path: "docker", Args: []string{"docker", "compose", "up"}}
}
`, func(err error) {
		if err == nil || !strings.Contains(err.Error(), "unallowlisted os/exec.Cmd literal") || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
			t.Fatalf("os/exec.Cmd literal docker mutation survived: %v", err)
		}
	})
}

func TestTypedComposeAuthorityRejectsDynamicMediatorArgumentInComposeWrapper(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "internal/compose/compose.go", func(source string) string {
		anchor := "func dockerComposeCommand(ctx context.Context, projDir string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"sh\", \"-c\", os.Getenv(\"PAYLOAD\"))\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "dynamic mediator argument") {
		t.Fatalf("dynamic mediator argument mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsUnknownExecutableMediators(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	tests := []struct {
		name       string
		executable string
		arguments  string
	}{
		{name: "env", executable: "env", arguments: `"docker", "compose", "up"`},
		{name: "xargs", executable: "xargs", arguments: `"docker", "compose", "up"`},
		{name: "nohup", executable: "nohup", arguments: `"docker", "compose", "up"`},
		{name: "sudo", executable: "sudo", arguments: `"docker", "compose", "up"`},
		{name: "podman", executable: "podman", arguments: `"compose", "up"`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			overlay := authorityOverlay(t, cliDir, "cmd/install.go", func(source string) string {
				anchor := "func commandContextDir(ctx context.Context, dir string, name string, args ...string) (*exec.Cmd, error) {\n"
				mutation := fmt.Sprintf("\t_ = exec.Command(%q, %s)\n", test.executable, test.arguments)
				return strings.Replace(source, anchor, anchor+mutation, 1)
			})
			err := typedAuthorityViolation(cliDir, overlay)
			want := fmt.Sprintf("unknown os/exec executable %q", test.executable)
			if err == nil || !strings.Contains(err.Error(), want) {
				t.Fatalf("%s mediator mutation survived: %v", test.executable, err)
			}
		})
	}
}

func TestTypedComposeAuthorityRejectsUnknownExecutable(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/install.go", func(source string) string {
		anchor := "func commandContextDir(ctx context.Context, dir string, name string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"frobnicate\", \"status\")\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), `unknown os/exec executable "frobnicate"`) {
		t.Fatalf("unknown executable mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsToolAuthorityArgument(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/install.go", func(source string) string {
		anchor := "func commandContextDir(ctx context.Context, dir string, name string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"git\", \"docker\")\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "tool argument contains docker/docker-compose/podman/compose authority for git") {
		t.Fatalf("tool authority-argument mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsDynamicMediatorArgument(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/install.go", func(source string) string {
		anchor := "func commandContextDir(ctx context.Context, dir string, name string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"bash\", \"-c\", os.Getenv(\"PAYLOAD\"))\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "dynamic mediator argument for bash") {
		t.Fatalf("dynamic mediator mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsStaleExecutableAllowlistEntry(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	const staleExecutable = "stale-authority-tool"
	allowedProcessExecutables[staleExecutable] = authorityTool
	t.Cleanup(func() { delete(allowedProcessExecutables, staleExecutable) })
	err := typedAuthorityViolation(cliDir, nil)
	if err == nil || !strings.Contains(err.Error(), `stale executable allowlist entry "stale-authority-tool" has zero production uses`) {
		t.Fatalf("stale executable allowlist mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsStaleProcessSiteAllowlistEntry(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	const staleSite = "internal/upgrade/stale.go:staleProcessSite|os/exec|go"
	allowedProcessLaunches[staleSite] = approvedLaunch{Count: 1, Reason: "test-only stale approval"}
	t.Cleanup(func() { delete(allowedProcessLaunches, staleSite) })
	err := typedAuthorityViolation(cliDir, nil)
	if err == nil || !strings.Contains(err.Error(), "process launch inventory at "+staleSite+" = 0, want 1") {
		t.Fatalf("stale process-site allowlist mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsSecondProcessLaunchAtAllowedSite(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/release/release.go", func(source string) string {
		anchor := "func runGoCLIBuild(projDir string) (string, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"go\", \"version\")\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "process launch inventory at cmd/release/release.go:runGoCLIBuild|os/exec|go = 2, want 1") {
		t.Fatalf("second process launch at allowlisted site survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsRoutingReleaseGoBuildThroughUpgradeRunner(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/release/release.go", func(source string) string {
		anchor := "func runGoCLIBuild(projDir string) (string, error) {\n"
		mutation := "\t_, _ = upgrade.RunCommandOutput(filepath.Join(projDir, \"cli\"), \"go\", \"version\")\n"
		return strings.Replace(source, anchor, anchor+mutation, 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), `unallowlisted upgrade.RunCommandOutput executable "go" at cmd/release/release.go:runGoCLIBuild`) {
		t.Fatalf("release Go build rerouted through upgrade runner survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsSecondDynamicSyscallExecInPinnedFunction(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "internal/upgrade/service.go", func(source string) string {
		anchor := "\t// authority:pinned-reexec\n\tif err := syscall.Exec(sbPath, os.Args, os.Environ()); err != nil {\n"
		mutation := "\t_ = syscall.Exec(sbPath, os.Args, os.Environ())\n"
		return strings.Replace(source, anchor, mutation+anchor, 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "dynamic syscall.Exec executable at internal/upgrade/service.go:executeUpgrade") {
		t.Fatalf("second dynamic syscall.Exec mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsMissingPinnedReexecMarker(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "cmd/psql.go", func(source string) string {
		return strings.Replace(source, "\t\t\t// authority:pinned-reexec\n", "", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "dynamic syscall.Exec executable at cmd/psql.go:psqlCmd.RunE") || !strings.Contains(err.Error(), "pinned dynamic syscall.Exec inventory at cmd/psql.go:psqlCmd.RunE = 0, want 1") {
		t.Fatalf("missing pinned re-exec marker mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsPinnedMarkerOnRogueCall(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "internal/upgrade/service.go", func(source string) string {
		anchor := "\t// authority:pinned-reexec\n\tif err := syscall.Exec(sbPath, os.Args, os.Environ()); err != nil {\n"
		mutation := "\t// authority:pinned-reexec\n\t_ = syscall.Exec(\"git\", []string{\"git\", \"status\"}, os.Environ())\n"
		return strings.Replace(source, anchor, mutation+anchor, 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "marker at internal/upgrade/service.go") || !strings.Contains(err.Error(), "is not adjacent to an allowed dynamic syscall.Exec handoff") {
		t.Fatalf("rogue pinned re-exec marker mutation survived: %v", err)
	}
}

func TestTypedComposeAuthorityRejectsAssignedProcessLauncher(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	withAuthorityMutationPackage(t, cliDir, `package authoritymutation
import "os"
var launch = os.StartProcess
`, func(err error) {
		if err == nil || !strings.Contains(err.Error(), "os.StartProcess used as a value") {
			t.Fatalf("assigned process launcher mutation survived: %v", err)
		}
	})
}

func TestTypedComposeAuthorityRejectsNewUpCallSite(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	withAuthorityMutationPackage(t, cliDir, `package authoritymutation
import (
    "context"
    "github.com/statisticsnorway/statbus/cli/internal/compose"
)
func Run() error {
    _, err := compose.Up(context.Background(), "", "-d", "app")
    return err
}
`, func(err error) {
		if err == nil || !strings.Contains(err.Error(), "unallowlisted direct compose.Up call") {
			t.Fatalf("new compose.Up call site survived: %v", err)
		}
	})
}
