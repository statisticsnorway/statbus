package upgrade

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
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

type composeUpConstruction struct {
	file     string
	function string
	line     int
}

func composeUpProductionSources(t *testing.T) map[string][]byte {
	t.Helper()
	sources := make(map[string][]byte)
	for name, source := range packageGoSources(t) {
		sources[filepath.ToSlash(filepath.Join("upgrade", name))] = source
	}
	composeDir := thisRepoFile(t, "cli/internal/compose")
	entries, err := os.ReadDir(composeDir)
	if err != nil {
		t.Fatalf("list compose production sources: %v", err)
	}
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		source, err := os.ReadFile(filepath.Join(composeDir, name))
		if err != nil {
			t.Fatalf("read compose production source %s: %v", name, err)
		}
		sources[filepath.ToSlash(filepath.Join("compose", name))] = source
	}
	return sources
}

func exactStringLiteral(node ast.Node, want string) bool {
	found := false
	ast.Inspect(node, func(child ast.Node) bool {
		literal, ok := child.(*ast.BasicLit)
		if !ok || literal.Kind != token.STRING {
			return true
		}
		value, err := strconv.Unquote(literal.Value)
		if err == nil && value == want {
			found = true
			return false
		}
		return true
	})
	return found
}

// composeUpConstructionsFromSources is deliberately independent of Service
// call-graph reachability. It inventories statically visible compose-up literals
// as defense in depth. The type-resolved authority gate is the complete control:
// callers cannot supply the subcommand, generic Compose execution rejects it,
// and compose.Up may only be used as a direct call at allowlisted sites.
func composeUpConstructionsFromSources(t *testing.T, sources map[string][]byte) []composeUpConstruction {
	t.Helper()
	var constructions []composeUpConstruction
	for file, source := range sources {
		fset := token.NewFileSet()
		parsed, err := parser.ParseFile(fset, file, source, 0)
		if err != nil {
			t.Fatalf("parse %s: %v", file, err)
		}
		isComposePackage := strings.HasPrefix(file, "compose/")
		for _, decl := range parsed.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			fnHasCompose := exactStringLiteral(fn.Body, "compose")
			var ancestors []ast.Node
			ast.Inspect(fn.Body, func(node ast.Node) bool {
				if node == nil {
					ancestors = ancestors[:len(ancestors)-1]
					return true
				}
				literal, isLiteral := node.(*ast.BasicLit)
				if isLiteral && literal.Kind == token.STRING {
					value, unquoteErr := strconv.Unquote(literal.Value)
					if unquoteErr == nil && value == "up" {
						isComposeUp := isComposePackage
						variableBuilt := false
						directVariableValue := true
						for i := len(ancestors) - 1; !isComposeUp && i >= 0; i-- {
							switch ancestor := ancestors[i].(type) {
							case *ast.CallExpr:
								if ident, ok := ancestor.Fun.(*ast.Ident); ok && ident.Name == "append" {
									variableBuilt = true
								} else {
									directVariableValue = false
								}
								isComposeUp = exactStringLiteral(ancestor, "compose")
							case *ast.CompositeLit:
								variableBuilt = true
								isComposeUp = exactStringLiteral(ancestor, "compose")
							case *ast.AssignStmt, *ast.ValueSpec:
								// Variable-built args may add "compose" in a separate
								// assignment and reach execution through an interface,
								// receiver alias, or function value. Deliberately do not
								// depend on the executor's identifier.
								isComposeUp = exactStringLiteral(ancestor, "compose") || ((variableBuilt || directVariableValue) && fnHasCompose)
							}
						}
						if isComposeUp {
							constructions = append(constructions, composeUpConstruction{
								file:     file,
								function: fn.Name.Name,
								line:     fset.Position(literal.Pos()).Line,
							})
						}
					}
				}
				ancestors = append(ancestors, node)
				return true
			})
		}
	}
	sort.Slice(constructions, func(i, j int) bool {
		if constructions[i].file != constructions[j].file {
			return constructions[i].file < constructions[j].file
		}
		if constructions[i].function != constructions[j].function {
			return constructions[i].function < constructions[j].function
		}
		return constructions[i].line < constructions[j].line
	})
	return constructions
}

func composeUpConstructionViolation(constructions []composeUpConstruction) error {
	// This literal inventory remains defense in depth for statically visible sites.
	// Runtime authority lives in dockerComposeCommand's strict subcommand parser and
	// the type-resolved whole-CLI compose.Up/exec gate. Exact counts still make the
	// only literal insertion point loud.
	want := map[string]int{
		"compose/compose.go:Up":                   2,
		"compose/compose.go:dockerComposeCommand": 1,
	}
	got := make(map[string]int)
	for _, construction := range constructions {
		key := construction.file + ":" + construction.function
		got[key]++
		if _, ok := want[key]; !ok {
			return fmt.Errorf("unallowlisted compose-up construction at %s:%d (%s)", construction.file, construction.line, construction.function)
		}
	}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		return fmt.Errorf("compose-up construction inventory = %v, want %v", got, want)
	}
	return nil
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
					if receiver, ok := selector.X.(*ast.Ident); ok {
						if receiver.Name == "d" {
							info.calls = append(info.calls, selector.Sel.Name)
						}
						if receiver.Name == "compose" && selector.Sel.Name == "Up" {
							info.composeUp = true
							info.composeUpOffsets = append(info.composeUpOffsets, fset.Position(call.Pos()).Offset-fnStart)
						}
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
	wantReachedUps := []string{"applyNewSbUpgrading", "completeInProgressUpgrade", "convergeParkedServingTierToCurrentTree", "startSourceApplicationStack"}
	if fmt.Sprint(reachedUps) != fmt.Sprint(wantReachedUps) {
		return fmt.Errorf("recovery entry/failure closure reaches compose-up functions %v; want only forward continuation, durable displaced-park convergence, flagless AtTarget serve-proof, and era-verified source recreation %v", reachedUps, wantReachedUps)
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
	upIdx := strings.Index(boundary, "compose.Up(")
	postDeriveIdx := strings.Index(boundary, "deriveServingEra(postEntries, expected, sourceTag)")
	postSourceIdx := strings.Index(boundary, "postEra != ServingEraSource")
	if deriveIdx < 0 || targetIdx < deriveIdx || upIdx < targetIdx || postDeriveIdx < upIdx || postSourceIdx < postDeriveIdx {
		t.Fatalf("typed source convergence order must be derive -> Target case -> compose up -> rederive -> require Source; derive=%d target=%d up=%d postDerive=%d postSource=%d", deriveIdx, targetIdx, upIdx, postDeriveIdx, postSourceIdx)
	}
	parkedSuccessor := bodies["convergeParkedServingTierToCurrentTree"].body
	for _, required := range []string{"--no-build", "--no-deps", "targetServingContainerEntries", "servingTierRunning", "d.healthCheck("} {
		if !strings.Contains(parkedSuccessor, required) {
			t.Fatalf("durable displaced-park convergence authority/postcondition is missing %q", required)
		}
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
	fullStackUpIdx := strings.Index(complete, "compose.Up(")
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

func TestEveryComposeUpConstructionIsSyntacticallyAllowlisted(t *testing.T) {
	constructions := composeUpConstructionsFromSources(t, composeUpProductionSources(t))
	if err := composeUpConstructionViolation(constructions); err != nil {
		t.Fatal(err)
	}
}

func TestComposeUpConstructionInventoryCatchesFuncValueMutation(t *testing.T) {
	sources := composeUpProductionSources(t)
	serviceKey := "upgrade/service.go"
	mutation := `

func composeUpViaFuncValueMutation(d *Service) error {
	verb := "up"
	args := []string{"compose", verb, "-d", "app"}
	runner := runCommand
	return runner(d.projDir, "docker", args...)
}
`
	sources[serviceKey] = append(append([]byte(nil), sources[serviceKey]...), []byte(mutation)...)
	constructions := composeUpConstructionsFromSources(t, sources)
	err := composeUpConstructionViolation(constructions)
	if err == nil || !strings.Contains(err.Error(), "unallowlisted compose-up construction") || !strings.Contains(err.Error(), "composeUpViaFuncValueMutation") {
		t.Fatalf("func-value compose-up mutation survived syntactic inventory: %v", err)
	}
}
