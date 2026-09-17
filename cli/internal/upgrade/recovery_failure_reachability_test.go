package upgrade

import (
	"go/ast"
	"go/parser"
	"go/token"
	"sort"
	"strconv"
	"strings"
	"testing"
)

type serviceMethodInfo struct {
	body      string
	calls     []string
	composeUp bool
}

func upgradeServiceMethodBodies(t *testing.T) map[string]serviceMethodInfo {
	t.Helper()
	bodies := make(map[string]serviceMethodInfo)
	for _, file := range []string{"service.go", "exec.go"} {
		sourceBytes := packageGoSources(t)[file]
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
			info := serviceMethodInfo{body: body}
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

func reachableServiceMethods(t *testing.T, bodies map[string]serviceMethodInfo, roots []string) map[string]bool {
	t.Helper()
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
			t.Fatalf("recovery reachability root/callee %s has no parsed Service method body", name)
		}
		reachable[name] = true
		for _, callee := range info.calls {
			if _, known := bodies[callee]; known && !reachable[callee] {
				queue = append(queue, callee)
			}
		}
	}
	return reachable
}

// TestRecoveryFailureClosureHasNoUngatedComposeUp is the recovery equivalent of
// STATBUS-352's workflow-ordering structural gate. It computes the real Service
// method closure from every rollback/recovery failure disposition and inspects
// every reachable function body. The sole compose-up exception is the typed
// source-stack boundary, whose Target era is derived from actual container image
// identities and whose postcondition is a freshly-derived Source era.
func TestRecoveryFailureClosureHasNoUngatedComposeUp(t *testing.T) {
	bodies := upgradeServiceMethodBodies(t)
	roots := []string{
		"newSbUpgradingFailure",
		"parkForDeterministicFailure",
		"recoveryRollback",
		"rollback",
		"restoreAndFinalize",
		"holdRollbackSchemaFloorFailure",
		"holdRollbackRestoreFailure",
		"holdRollbackClientsLive",
	}
	reachable := reachableServiceMethods(t, bodies, roots)

	var reachedUps []string
	for name := range reachable {
		if bodies[name].composeUp {
			reachedUps = append(reachedUps, name)
		}
	}
	sort.Strings(reachedUps)
	if len(reachedUps) != 1 || reachedUps[0] != "startSourceApplicationStack" {
		t.Fatalf("recovery failure closure reaches untyped compose-up functions %v; only startSourceApplicationStack is permitted", reachedUps)
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
