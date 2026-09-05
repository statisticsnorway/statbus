package release

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// SensitivePathsFile is the one checked-in list of rules that are genuinely
// broad across every paid scenario home. Scenario-specific ownership and
// controller rules are added by this package from the full Scenario value.
const SensitivePathsFile = "ops/release/upgrade-sensitive-paths.txt"

// SensitivityReason is the stable explanation attached to every invalidating
// changed path. These values are operator-facing API and must remain stable.
type SensitivityReason string

const (
	ReasonBoxPayload         SensitivityReason = "box payload"
	ReasonSharedController   SensitivityReason = "shared controller"
	ReasonOwnScenario        SensitivityReason = "own scenario"
	ReasonSharedHarnessInput SensitivityReason = "shared harness input"
	ReasonProofInterpreter   SensitivityReason = "proof interpreter"
)

// SensitiveChange is one repository-relative changed path and the reason that
// change invalidates evidence for a particular Scenario.
type SensitiveChange struct {
	Path   string
	Reason SensitivityReason
}

func (c SensitiveChange) String() string {
	return fmt.Sprintf("%s — %s", c.Path, c.Reason)
}

type sensitivityMatchKind string

const (
	matchExact     sensitivityMatchKind = "exact"
	matchDirectory sensitivityMatchKind = "directory"
	matchPrefix    sensitivityMatchKind = "prefix"
)

type sensitivityRule struct {
	Kind   sensitivityMatchKind
	Path   string
	Reason SensitivityReason
}

var safeScenarioName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]*$`)

// LoadSensitivityPolicy reads the broad checked-in policy. Each non-comment
// line has the documented form:
//
//	exact | box payload | install.sh
//	directory | box payload | cli
//	prefix | box payload | docker-compose.
//
// Exact matches one repository-relative path. Directory matches the named
// directory itself and descendants at a slash boundary. Prefix is anchored at
// the repository root. No matcher performs substring containment.
func loadSensitivityPolicy(projDir string) ([]sensitivityRule, error) {
	data, err := os.ReadFile(filepath.Join(projDir, SensitivePathsFile))
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", SensitivePathsFile, err)
	}

	var rules []sensitivityRule
	for lineNo, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Split(line, "|")
		if len(parts) != 3 {
			return nil, fmt.Errorf("%s:%d: want 'exact|directory|prefix | reason | repository-relative path'", SensitivePathsFile, lineNo+1)
		}
		rule := sensitivityRule{
			Kind:   sensitivityMatchKind(strings.TrimSpace(parts[0])),
			Reason: SensitivityReason(strings.TrimSpace(parts[1])),
			Path:   strings.TrimSpace(parts[2]),
		}
		if err := validateSensitivityRule(rule); err != nil {
			return nil, fmt.Errorf("%s:%d: %w", SensitivePathsFile, lineNo+1, err)
		}
		rules = append(rules, rule)
	}
	if len(rules) == 0 {
		return nil, fmt.Errorf("%s lists no rules — refusing an empty sensitivity policy, which would call every change safe", SensitivePathsFile)
	}
	return rules, nil
}

// ValidateSensitivityPolicy fails before a coverage walk can accidentally
// treat a malformed or empty optimizer policy as a safe answer.
func ValidateSensitivityPolicy(projDir string) error {
	_, err := loadSensitivityPolicy(projDir)
	return err
}

func validateSensitivityRule(rule sensitivityRule) error {
	switch rule.Kind {
	case matchExact, matchDirectory, matchPrefix:
	default:
		return fmt.Errorf("unknown matcher %q", rule.Kind)
	}
	if !validSensitivityReason(rule.Reason) {
		return fmt.Errorf("unknown reason %q", rule.Reason)
	}
	if err := validateRepoRelativePath(rule.Path); err != nil {
		return err
	}
	if rule.Kind == matchDirectory && strings.HasSuffix(rule.Path, "/") {
		return fmt.Errorf("directory rule %q must omit the trailing slash", rule.Path)
	}
	return nil
}

func validSensitivityReason(reason SensitivityReason) bool {
	switch reason {
	case ReasonBoxPayload, ReasonSharedController, ReasonOwnScenario, ReasonSharedHarnessInput, ReasonProofInterpreter:
		return true
	default:
		return false
	}
}

func validateRepoRelativePath(repoPath string) error {
	if repoPath == "" {
		return fmt.Errorf("path is empty")
	}
	if strings.ContainsRune(repoPath, '\x00') {
		return fmt.Errorf("path contains NUL")
	}
	if filepath.IsAbs(repoPath) || strings.HasPrefix(repoPath, "./") || strings.HasPrefix(repoPath, "../") {
		return fmt.Errorf("path %q is not repository-relative", repoPath)
	}
	if path.Clean(repoPath) != repoPath {
		return fmt.Errorf("path %q is not clean repository-relative form", repoPath)
	}
	return nil
}

func validateSensitivityScenario(scenario Scenario) error {
	if !safeScenarioName.MatchString(scenario.Name) {
		return fmt.Errorf("unsafe scenario name %q", scenario.Name)
	}
	switch scenario.Home {
	case WorkflowFleet, WorkflowArcs:
		return nil
	case WorkflowSmoke:
		for _, known := range SmokeDomain().Scenarios {
			if scenario == known {
				return nil
			}
		}
		return fmt.Errorf("%q is not in the fixed %s domain", scenario.Name, WorkflowSmoke)
	default:
		return fmt.Errorf("unsupported scenario home %q", scenario.Home)
	}
}

func ruleMatches(rule sensitivityRule, changedPath string) bool {
	switch rule.Kind {
	case matchExact:
		return changedPath == rule.Path
	case matchDirectory:
		return changedPath == rule.Path || strings.HasPrefix(changedPath, rule.Path+"/")
	case matchPrefix:
		return strings.HasPrefix(changedPath, rule.Path)
	default:
		return false
	}
}

func reasonPriority(reason SensitivityReason) int {
	switch reason {
	case ReasonProofInterpreter:
		return 5
	case ReasonOwnScenario:
		return 4
	case ReasonSharedHarnessInput:
		return 3
	case ReasonSharedController:
		return 2
	case ReasonBoxPayload:
		return 1
	default:
		return 0
	}
}

func scenarioSensitivityRules(scenario Scenario) ([]sensitivityRule, error) {
	if err := validateSensitivityScenario(scenario); err != nil {
		return nil, err
	}

	var ownPath string
	var rules []sensitivityRule
	switch scenario.Home {
	case WorkflowFleet:
		ownPath = "test/install-recovery/scenarios/" + scenario.Name + ".sh"
		rules = append(rules,
			sensitivityRule{Kind: matchExact, Path: ".github/workflows/install-recovery-harness.yaml", Reason: ReasonSharedController},
			sensitivityRule{Kind: matchExact, Path: "test/install-recovery/run.sh", Reason: ReasonSharedController},
		)
	case WorkflowArcs:
		ownPath = "test/install-recovery/arcs/" + scenario.Name + "-arc.sh"
		rules = append(rules,
			sensitivityRule{Kind: matchExact, Path: ".github/workflows/upgrade-arc-harness.yaml", Reason: ReasonSharedController},
			sensitivityRule{Kind: matchExact, Path: "test/install-recovery/run.sh", Reason: ReasonSharedController},
		)
		if scenario.Name == "failing" || scenario.Name == "deploy-status-proof" {
			rules = append(rules, sensitivityRule{Kind: matchExact, Path: "ops/ci-deploy-status.sh", Reason: ReasonSharedHarnessInput})
		}
		if scenario.Name == "deploy-status-proof" {
			rules = append(rules,
				sensitivityRule{Kind: matchExact, Path: "ops/niue/sshdo", Reason: ReasonSharedHarnessInput},
				sensitivityRule{Kind: matchExact, Path: "ops/niue/sshdoers", Reason: ReasonSharedHarnessInput},
			)
		}
	case WorkflowSmoke:
		ownPath = "test/install-recovery/scenarios/" + scenario.Name + ".sh"
		rules = append(rules,
			sensitivityRule{Kind: matchExact, Path: ".github/workflows/test-smoke.yaml", Reason: ReasonSharedController},
			// test-smoke's select job runs the runner's authoritative domain
			// validation before any paid matrix job, so the runner controls
			// smoke too.
			sensitivityRule{Kind: matchExact, Path: "test/install-recovery/run.sh", Reason: ReasonSharedController},
		)
	}
	rules = append(rules, sensitivityRule{Kind: matchExact, Path: ownPath, Reason: ReasonOwnScenario})
	rules = append(rules, happyPathCompatibilityRules(scenario.Name)...)
	return dedupeSensitivityRules(rules), nil
}

// happyPathCompatibilityRules makes the STATBUS-350 evidence union sound. The
// two happy-path slugs may inherit a mark produced by ANY of their historical
// producers (WorkflowsRunningScenario in evidence.go), so every producer's
// wrapper and every consumer's wrapper must invalidate that inheritance,
// regardless of which home is asking. Deleted legacy workflow files are listed
// too: a diff that resurrects or edits one is a wrapper change.
func happyPathCompatibilityRules(name string) []sensitivityRule {
	if happyPathCompatibilityWorkflows(name) == nil {
		return nil
	}
	var rules []sensitivityRule
	for _, w := range append([]string{WorkflowTestSmoke, WorkflowInstallRecoveryHarness}, happyPathCompatibilityWorkflows(name)...) {
		rules = append(rules, sensitivityRule{Kind: matchExact, Path: ".github/workflows/" + w, Reason: ReasonSharedController})
	}
	rules = append(rules, sensitivityRule{Kind: matchExact, Path: "test/install-recovery/run.sh", Reason: ReasonSharedController})
	return rules
}

func dedupeSensitivityRules(rules []sensitivityRule) []sensitivityRule {
	seen := make(map[sensitivityRule]struct{}, len(rules))
	out := rules[:0]
	for _, rule := range rules {
		if _, ok := seen[rule]; ok {
			continue
		}
		seen[rule] = struct{}{}
		out = append(out, rule)
	}
	return out
}

// MatchSensitivePath classifies one repository-relative path for the full
// scenario identity. It returns at most one, most-specific stable reason.
func MatchSensitivePath(projDir string, scenario Scenario, changedPath string) (SensitiveChange, bool, error) {
	if err := validateRepoRelativePath(changedPath); err != nil {
		return SensitiveChange{}, false, err
	}
	broad, err := loadSensitivityPolicy(projDir)
	if err != nil {
		return SensitiveChange{}, false, err
	}
	specific, err := scenarioSensitivityRules(scenario)
	if err != nil {
		return SensitiveChange{}, false, err
	}

	best := SensitiveChange{}
	bestPriority := 0
	bestRuleLength := -1
	for _, rule := range append(broad, specific...) {
		if !ruleMatches(rule, changedPath) {
			continue
		}
		priority := reasonPriority(rule.Reason)
		if priority > bestPriority || (priority == bestPriority && len(rule.Path) > bestRuleLength) {
			best = SensitiveChange{Path: changedPath, Reason: rule.Reason}
			bestPriority = priority
			bestRuleLength = len(rule.Path)
		}
	}
	return best, bestPriority != 0, nil
}

// DiffSensitiveChanges returns every changed path that invalidates evidence for
// scenario. Renames are disabled so a sensitive old name and a new safe name
// both remain visible. NUL framing preserves every valid Git filename.
func DiffSensitiveChanges(projDir, fromRef, toRef string, scenario Scenario) ([]SensitiveChange, error) {
	if err := validateSensitivityScenario(scenario); err != nil {
		return nil, err
	}
	cmd := exec.Command("git", "diff", "--no-renames", "--name-only", "-z", fromRef+".."+toRef, "--")
	cmd.Dir = projDir
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("git diff %s..%s: %w: %s", fromRef, toRef, err, strings.TrimSpace(stderr.String()))
	}
	if len(out) == 0 {
		return nil, nil
	}
	if out[len(out)-1] != 0 {
		return nil, fmt.Errorf("git diff %s..%s returned malformed non-NUL-terminated path output", fromRef, toRef)
	}

	parts := bytes.Split(out[:len(out)-1], []byte{0})
	changes := make([]SensitiveChange, 0, len(parts))
	seen := make(map[SensitiveChange]struct{})
	for _, raw := range parts {
		if len(raw) == 0 {
			return nil, fmt.Errorf("git diff %s..%s returned an empty changed path", fromRef, toRef)
		}
		changedPath := string(raw)
		change, matched, matchErr := MatchSensitivePath(projDir, scenario, changedPath)
		if matchErr != nil {
			return nil, fmt.Errorf("classify changed path %q: %w", changedPath, matchErr)
		}
		if !matched {
			continue
		}
		if _, ok := seen[change]; ok {
			continue
		}
		seen[change] = struct{}{}
		changes = append(changes, change)
	}
	sort.Slice(changes, func(i, j int) bool {
		if changes[i].Path == changes[j].Path {
			return changes[i].Reason < changes[j].Reason
		}
		return changes[i].Path < changes[j].Path
	})
	return changes, nil
}
