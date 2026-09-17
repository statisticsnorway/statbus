package upgrade

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"sort"
	"strconv"
	"strings"
	"testing"
)

type serviceMethodInfo struct {
	body             string
	rawBody          string
	calls            []string
	composeUp        bool
	composeUpOffsets []int
}

func upgradeServiceMethodBodies(t *testing.T) map[string]serviceMethodInfo {
	t.Helper()
	return upgradeServiceMethodBodiesFromSources(t, packageGoSources(t))
}

func upgradeServiceMethodBodiesFromSources(t *testing.T, sources map[string][]byte) map[string]serviceMethodInfo {
	t.Helper()
	bodies := make(map[string]serviceMethodInfo)
	for _, file := range []string{"service.go", "exec.go"} {
		sourceBytes := sources[file]
		source := string(sourceBytes)
		fset := token.NewFileSet()
		parsed, err := parser.ParseFile(fset, file, sourceBytes, 0)
		if err != nil {
			t.Fatalf("parse %s: %v", file, err)
		}
		for _, decl := range parsed.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Recv == nil || fn.Body == nil || len(fn.Recv.List) != 1 {
				continue
			}
			recv, ok := fn.Recv.List[0].Type.(*ast.StarExpr)
			if !ok {
				continue
			}
			recvName, ok := recv.X.(*ast.Ident)
			if !ok || recvName.Name != "Service" {
				continue
			}

			name := fn.Name.Name
			body := extractFuncBody(t, source, "func (d *Service) "+name+"(")
			fnStart := fset.Position(fn.Pos()).Offset
			fnEnd := fset.Position(fn.End()).Offset
			info := serviceMethodInfo{body: body, rawBody: source[fnStart:fnEnd]}
			ast.Inspect(fn.Body, func(node ast.Node) bool {
				call, ok := node.(*ast.CallExpr)
				if !ok {
					return true
				}
				if selector, ok := call.Fun.(*ast.SelectorExpr); ok {
					if receiver, ok := selector.X.(*ast.Ident); ok && receiver.Name == "d" {
						info.calls = append(info.calls, selector.Sel.Name)
					}
				}
				var literals []string
				ast.Inspect(call, func(child ast.Node) bool {
					literal, ok := child.(*ast.BasicLit)
					if !ok || literal.Kind != token.STRING {
						return true
					}
					value, unquoteErr := strconv.Unquote(literal.Value)
					if unquoteErr == nil {
						literals = append(literals, value)
					}
					return true
				})
				for i := 0; i+1 < len(literals); i++ {
					if literals[i] == "compose" && literals[i+1] == "up" {
						info.composeUp = true
						info.composeUpOffsets = append(info.composeUpOffsets, fset.Position(call.Pos()).Offset-fnStart)
					}
				}
				return true
			})
			if prior, exists := bodies[name]; exists && prior.body != body {
				t.Fatalf("duplicate Service method %s has different bodies", name)
			}
			bodies[name] = info
		}
	}
	return bodies
}

func recoveryComposeUpViolation(bodies map[string]serviceMethodInfo) error {
	roots := []string{
		"completeInProgressUpgrade",
		"recoverFromFlag",
		"newSbUpgradingFailure",
		"parkForDeterministicFailure",
		"recoveryRollback",
		"rollback",
		"restoreAndFinalize",
		"holdRollbackSchemaFloorFailure",
		"holdRollbackRestoreFailure",
		"holdRollbackClientsLive",
	}
	reachable, reachErr := reachableServiceMethodsWithoutTestFailure(bodies, roots)
	if reachErr != nil {
		return reachErr
	}
	if len(bodies["recoverFromFlag"].composeUpOffsets) != 0 {
		return fmt.Errorf("recoverFromFlag contains a direct untyped compose-up")
	}
	complete := bodies["completeInProgressUpgrade"]
	targetTailIdx := strings.Index(complete.rawBody, `restoreTargetSHA := ""`)
	if targetTailIdx < 0 {
		return fmt.Errorf("completeInProgressUpgrade has no AtTarget tail marker")
	}
	for _, upOffset := range complete.composeUpOffsets {
		if upOffset < targetTailIdx {
			return fmt.Errorf("completeInProgressUpgrade has a failure-reachable compose-up before its AtTarget tail")
		}
	}

	var reachedUps []string
	for name := range reachable {
		if bodies[name].composeUp {
			reachedUps = append(reachedUps, name)
		}
	}
	sort.Strings(reachedUps)
	wantReachedUps := []string{"applyNewSbUpgrading", "completeInProgressUpgrade", "startSourceApplicationStack"}
	if fmt.Sprint(reachedUps) != fmt.Sprint(wantReachedUps) {
		return fmt.Errorf("recovery entry/failure closure reaches compose-up functions %v; want only forward continuation, flagless AtTarget serve-proof, and era-verified source recreation %v", reachedUps, wantReachedUps)
	}

	// completeInProgressUpgrade is an entry root with a Behind rollback branch
	// and a disjoint AtTarget serve-proof tail. Its one direct compose-up is legal
	// only after the AtTarget tail begins. Any compose-up planted in the rollback
	// error/success branch is therefore failure-reachable and must fail this gate.
	if len(complete.composeUpOffsets) != 1 {
		return fmt.Errorf("completeInProgressUpgrade has %d direct compose-up calls; want exactly its one AtTarget serve-proof call", len(complete.composeUpOffsets))
	}
	return nil
}

func reachableServiceMethodsWithoutTestFailure(bodies map[string]serviceMethodInfo, roots []string) (map[string]bool, error) {
	reachable := make(map[string]bool)
	queue := append([]string(nil), roots...)
	for len(queue) != 0 {
		name := queue[0]
		queue = queue[1:]
		if reachable[name] {
			continue
		}
		info, ok := bodies[name]
		if !ok {
			return nil, fmt.Errorf("recovery reachability root/callee %s has no parsed Service method body", name)
		}
		reachable[name] = true
		for _, callee := range info.calls {
			if _, known := bodies[callee]; known && !reachable[callee] {
				queue = append(queue, callee)
			}
		}
	}
	return reachable, nil
}

// TestRecoveryFailureClosureHasNoUngatedComposeUp is the recovery equivalent of
// STATBUS-352's workflow-ordering structural gate. It computes the real Service
// method closure from every rollback/recovery failure disposition plus the two
// top-level recovery entries. Forward continuation and the flagless AtTarget tail
// retain their existing compose-up calls behind branch-specific gates; the sole
// failure-disposition exception is the typed source-stack boundary, whose Target
// era is derived from actual container image identities and whose postcondition is
// a freshly-derived Source era.
func TestRecoveryFailureClosureHasNoUngatedComposeUp(t *testing.T) {
	bodies := upgradeServiceMethodBodies(t)
	if err := recoveryComposeUpViolation(bodies); err != nil {
		t.Fatal(err)
	}

	boundary := bodies["startSourceApplicationStack"].body
	deriveIdx := strings.Index(boundary, "deriveServingEra(entries, expected, sourceTag)")
	targetIdx := strings.Index(boundary, "case ServingEraTarget:")
	upIdx := strings.Index(boundary, `"compose", "up"`)
	postDeriveIdx := strings.Index(boundary, "deriveServingEra(postEntries, expected, sourceTag)")
	postSourceIdx := strings.Index(boundary, "postEra != ServingEraSource")
	if deriveIdx < 0 || targetIdx < deriveIdx || upIdx < targetIdx || postDeriveIdx < upIdx || postSourceIdx < postDeriveIdx {
		t.Fatalf("typed source convergence order must be derive -> Target case -> compose up -> rederive -> require Source; derive=%d target=%d up=%d postDerive=%d postSource=%d", deriveIdx, targetIdx, upIdx, postDeriveIdx, postSourceIdx)
	}

	// completeInProgressUpgrade contains both a Behind rollback branch and a
	// disjoint AtTarget serve-proof compose-up tail. Pin the branch terminators so
	// neither rollback success nor rollback failure can fall through into that tail.
	complete := bodies["completeInProgressUpgrade"].body
	rollbackIdx := strings.Index(complete, "if rollbackErr := d.rollback(")
	failureReturnIdx := strings.Index(complete, `return fmt.Errorf("completeInProgressUpgrade: rollback for upgrade`)
	targetTailIdx := strings.Index(complete, `restoreTargetSHA := ""`)
	branchTerminatorIdx := -1
	if rollbackIdx >= 0 && targetTailIdx > rollbackIdx {
		branchTerminatorIdx = strings.Index(complete[rollbackIdx:targetTailIdx], "\n\t\t}\n\t\treturn nil\n\t}")
	}
	if branchTerminatorIdx >= 0 && rollbackIdx >= 0 {
		branchTerminatorIdx += rollbackIdx
	}
	fullStackUpIdx := strings.Index(complete, `composeArgs := append([]string{"compose", "up"`)
	if rollbackIdx < 0 || failureReturnIdx < rollbackIdx || branchTerminatorIdx < failureReturnIdx || targetTailIdx < branchTerminatorIdx || fullStackUpIdx < targetTailIdx {
		t.Fatalf("flagless rollback branch must terminate on both failure and success before AtTarget compose up; rollback=%d failureReturn=%d branchTerminator=%d targetTail=%d up=%d", rollbackIdx, failureReturnIdx, branchTerminatorIdx, targetTailIdx, fullStackUpIdx)
	}
}

func TestRecoveryFailureReachabilityMutationsCatchNewEntryRoots(t *testing.T) {
	base := packageGoSources(t)
	tests := []struct {
		name       string
		needle     string
		mutation   string
		wantErrSub string
	}{
		{
			name:       "completeInProgressUpgrade rollback-error branch",
			needle:     `return fmt.Errorf("completeInProgressUpgrade: rollback for upgrade %d aborted; durable recovery marker retained: %w", id, rollbackErr)`,
			mutation:   `runCommand(d.projDir, "docker", "compose", "up", "-d", "app")` + "\n\t\t\t\t" + `return fmt.Errorf("completeInProgressUpgrade: rollback for upgrade %d aborted; durable recovery marker retained: %w", id, rollbackErr)`,
			wantErrSub: "failure-reachable compose-up",
		},
		{
			name:       "recoverFromFlag direct recovery-error branch",
			needle:     `return fmt.Errorf("acquire and revalidate rollback finishing marker: %w", lockErr)`,
			mutation:   `runCommand(d.projDir, "docker", "compose", "up", "-d", "app")` + "\n\t\t\t" + `return fmt.Errorf("acquire and revalidate rollback finishing marker: %w", lockErr)`,
			wantErrSub: "recoverFromFlag contains a direct untyped compose-up",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			mutated := make(map[string][]byte, len(base))
			for name, source := range base {
				mutated[name] = append([]byte(nil), source...)
			}
			serviceSource := string(mutated["service.go"])
			if !strings.Contains(serviceSource, tc.needle) {
				t.Fatalf("mutation needle is stale: %s", tc.needle)
			}
			mutated["service.go"] = []byte(strings.Replace(serviceSource, tc.needle, tc.mutation, 1))
			bodies := upgradeServiceMethodBodiesFromSources(t, mutated)
			err := recoveryComposeUpViolation(bodies)
			if err == nil || !strings.Contains(err.Error(), tc.wantErrSub) {
				t.Fatalf("mutation survived recovery reachability gate: err=%v, want %q", err, tc.wantErrSub)
			}
		})
	}
}
