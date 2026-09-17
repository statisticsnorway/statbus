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

// cliProductionSources is deliberately broader than the compose-exec scope.
// UpCapability is opaque but its constructor is exported so the upgrade package
// can use it. Therefore the mint allowlist must inventory the whole CLI, not just
// the two packages whose docker-compose process construction is centralized.
func cliProductionSources(t *testing.T) map[string][]byte {
	t.Helper()
	cliDir := thisRepoFile(t, "cli")
	sources := make(map[string][]byte)
	err := filepath.WalkDir(cliDir, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		name := entry.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			return nil
		}
		rel, err := filepath.Rel(cliDir, path)
		if err != nil {
			return err
		}
		source, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		sources[filepath.ToSlash(rel)] = source
		return nil
	})
	if err != nil {
		t.Fatalf("inventory CLI production sources: %v", err)
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
// call-graph reachability. It inventories the "up" literal at its construction
// site, including slice elements and variables later invoked through a function
// value. That second layer prevents interface/alias/data-flow dispatch from
// hiding a newly introduced compose-up from the recovery closure walker.
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
	// Runtime authority lives in dockerComposeCommand's final-argv capability check;
	// composeRuntimeGuardViolation separately pins every capability mint and exec
	// chokepoint. Exact counts still make visible drift loud.
	want := map[string]int{
		"compose/compose.go:dockerComposeCommand":        1,
		"compose/compose.go:RestartAndWait":              1,
		"compose/compose.go:ResumeClients":               1,
		"compose/compose.go:Start":                       1,
		"upgrade/service.go:abortFailedPreBackupStop":    1,
		"upgrade/service.go:applyNewSbUpgrading":         1,
		"upgrade/service.go:completeInProgressUpgrade":   1,
		"upgrade/service.go:startSourceApplicationStack": 1,
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

func astParents(root ast.Node) map[ast.Node]ast.Node {
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

func enclosingFunctionKey(file string, node ast.Node, parents map[ast.Node]ast.Node) string {
	for current := node; current != nil; current = parents[current] {
		if fn, ok := current.(*ast.FuncDecl); ok {
			return file + ":" + fn.Name.Name
		}
	}
	return file + ":<package>"
}

func namesType(expr ast.Expr, name string) bool {
	switch typed := expr.(type) {
	case *ast.Ident:
		return typed.Name == name
	case *ast.SelectorExpr:
		return typed.Sel.Name == name
	case *ast.StarExpr:
		return namesType(typed.X, name)
	default:
		return false
	}
}

func directCallForIdentifier(ident *ast.Ident, parents map[ast.Node]ast.Node) (*ast.CallExpr, bool) {
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

func staticStringExpr(expr ast.Expr, values map[string]string) (string, bool) {
	switch value := expr.(type) {
	case *ast.BasicLit:
		if value.Kind != token.STRING {
			return "", false
		}
		unquoted, err := strconv.Unquote(value.Value)
		return unquoted, err == nil
	case *ast.Ident:
		resolved, ok := values[value.Name]
		return resolved, ok
	case *ast.ParenExpr:
		return staticStringExpr(value.X, values)
	case *ast.BinaryExpr:
		if value.Op != token.ADD {
			return "", false
		}
		left, leftOK := staticStringExpr(value.X, values)
		right, rightOK := staticStringExpr(value.Y, values)
		return left + right, leftOK && rightOK
	default:
		return "", false
	}
}

func functionStaticStrings(fn *ast.FuncDecl) map[string]string {
	values := make(map[string]string)
	ast.Inspect(fn.Body, func(node ast.Node) bool {
		switch assignment := node.(type) {
		case *ast.AssignStmt:
			for i, lhs := range assignment.Lhs {
				if i >= len(assignment.Rhs) {
					continue
				}
				ident, ok := lhs.(*ast.Ident)
				if !ok {
					continue
				}
				if value, ok := staticStringExpr(assignment.Rhs[i], values); ok {
					values[ident.Name] = value
				} else {
					delete(values, ident.Name)
				}
			}
		case *ast.ValueSpec:
			for i, ident := range assignment.Names {
				if i >= len(assignment.Values) {
					continue
				}
				if value, ok := staticStringExpr(assignment.Values[i], values); ok {
					values[ident.Name] = value
				}
			}
		}
		return true
	})
	return values
}

func firstStaticString(expr ast.Expr, stringsByName map[string]string, slicesByName map[string]string) (string, bool) {
	if value, ok := staticStringExpr(expr, stringsByName); ok {
		return value, true
	}
	switch value := expr.(type) {
	case *ast.Ident:
		first, ok := slicesByName[value.Name]
		return first, ok
	case *ast.CompositeLit:
		if len(value.Elts) == 0 {
			return "", false
		}
		return staticStringExpr(value.Elts[0], stringsByName)
	case *ast.CallExpr:
		ident, ok := value.Fun.(*ast.Ident)
		if !ok || ident.Name != "append" || len(value.Args) == 0 {
			return "", false
		}
		if first, ok := firstStaticString(value.Args[0], stringsByName, slicesByName); ok {
			return first, true
		}
		if len(value.Args) > 1 {
			return staticStringExpr(value.Args[1], stringsByName)
		}
	}
	return "", false
}

func functionStaticSliceFirsts(fn *ast.FuncDecl, stringsByName map[string]string) map[string]string {
	values := make(map[string]string)
	ast.Inspect(fn.Body, func(node ast.Node) bool {
		switch assignment := node.(type) {
		case *ast.AssignStmt:
			for i, lhs := range assignment.Lhs {
				if i >= len(assignment.Rhs) {
					continue
				}
				ident, ok := lhs.(*ast.Ident)
				if !ok {
					continue
				}
				if value, ok := firstStaticString(assignment.Rhs[i], stringsByName, values); ok {
					values[ident.Name] = value
				} else {
					delete(values, ident.Name)
				}
			}
		case *ast.ValueSpec:
			for i, ident := range assignment.Names {
				if i >= len(assignment.Values) {
					continue
				}
				if value, ok := firstStaticString(assignment.Values[i], stringsByName, values); ok {
					values[ident.Name] = value
				}
			}
		}
		return true
	})
	return values
}

func callsComposeCommand(node ast.Node) bool {
	found := false
	ast.Inspect(node, func(child ast.Node) bool {
		call, ok := child.(*ast.CallExpr)
		if !ok {
			return true
		}
		selector, ok := call.Fun.(*ast.SelectorExpr)
		if !ok || (selector.Sel.Name != "CommandContext" && selector.Sel.Name != "CommandContextWithUp") {
			return true
		}
		receiver, ok := selector.X.(*ast.Ident)
		if ok && receiver.Name == "compose" {
			found = true
			return false
		}
		return true
	})
	return found
}

func composeRuntimeGuardViolation(sources map[string][]byte) error {
	wantMints := map[string]int{
		"cmd/db.go:dockerComposeStart":                            1,
		"cmd/install.go:composeApplyServiceDefault":               1,
		"cmd/install.go:runStartServices":                         1,
		"internal/compose/compose.go:RestartAndWait":              1,
		"internal/compose/compose.go:ResumeClients":               1,
		"internal/compose/compose.go:Start":                       1,
		"internal/upgrade/exec.go:EnsureDBUp":                     1,
		"internal/upgrade/service.go:abortFailedPreBackupStop":    1,
		"internal/upgrade/service.go:applyNewSbUpgrading":         2,
		"internal/upgrade/service.go:completeInProgressUpgrade":   1,
		"internal/upgrade/service.go:startSourceApplicationStack": 1,
	}
	gotMints := make(map[string]int)
	capabilityConstructions := 0
	nonceReferences := make(map[string]int)

	for file, source := range sources {
		fset := token.NewFileSet()
		parsed, err := parser.ParseFile(fset, file, source, 0)
		if err != nil {
			return fmt.Errorf("parse %s: %w", file, err)
		}
		parents := astParents(parsed)

		ast.Inspect(parsed, func(node ast.Node) bool {
			if err != nil || node == nil {
				return err == nil
			}
			key := enclosingFunctionKey(file, node, parents)
			switch typed := node.(type) {
			case *ast.CompositeLit:
				if namesType(typed.Type, "upCapability") {
					capabilityConstructions++
					if key != "internal/compose/compose.go:MintUpCapability" {
						err = fmt.Errorf("unallowlisted upCapability composite construction at %s:%d (%s)", file, fset.Position(typed.Pos()).Line, key)
						return false
					}
				}
			case *ast.ValueSpec:
				if typed.Type != nil && namesType(typed.Type, "upCapability") {
					err = fmt.Errorf("upCapability var declaration bypasses minting at %s:%d (%s)", file, fset.Position(typed.Pos()).Line, key)
					return false
				}
			case *ast.CallExpr:
				if ident, ok := typed.Fun.(*ast.Ident); ok && ident.Name == "new" && len(typed.Args) == 1 && namesType(typed.Args[0], "upCapability") {
					err = fmt.Errorf("upCapability new() construction bypasses minting at %s:%d (%s)", file, fset.Position(typed.Pos()).Line, key)
					return false
				}
				if selector, ok := typed.Fun.(*ast.SelectorExpr); ok {
					receiver, receiverOK := selector.X.(*ast.Ident)
					if receiverOK && receiver.Name == "exec" && (selector.Sel.Name == "Command" || selector.Sel.Name == "CommandContext") {
						commandArg := 0
						if selector.Sel.Name == "CommandContext" {
							commandArg = 1
						}
						if len(typed.Args) > commandArg+1 {
							executable, executableKnown := staticStringExpr(typed.Args[commandArg], nil)
							firstArg, firstKnown := staticStringExpr(typed.Args[commandArg+1], nil)
							if executableKnown && executable == "docker" && firstKnown && firstArg == "compose" && key != "internal/compose/compose.go:dockerComposeCommand" {
								err = fmt.Errorf("raw docker compose exec bypasses shared wrapper at %s:%d (%s)", file, fset.Position(typed.Pos()).Line, key)
								return false
							}
						}
					}
				}
			case *ast.Ident:
				if typed.Name == "MintUpCapability" {
					if fn, ok := parents[typed].(*ast.FuncDecl); ok && fn.Name == typed && key == "internal/compose/compose.go:MintUpCapability" {
						return true
					}
					call, direct := directCallForIdentifier(typed, parents)
					if !direct {
						err = fmt.Errorf("MintUpCapability is referenced outside a direct call at %s:%d (%s)", file, fset.Position(typed.Pos()).Line, key)
						return false
					}
					gotMints[key]++
					if _, allowed := wantMints[key]; !allowed {
						err = fmt.Errorf("unallowlisted compose-up capability mint at %s:%d (%s)", file, fset.Position(call.Pos()).Line, key)
						return false
					}
				}
				if typed.Name == "upCapabilityNonce" {
					if valueSpec, ok := parents[typed].(*ast.ValueSpec); ok {
						for _, name := range valueSpec.Names {
							if name == typed {
								return true
							}
						}
					}
					if key != "internal/compose/compose.go:MintUpCapability" && key != "internal/compose/compose.go:dockerComposeCommand" {
						err = fmt.Errorf("upCapabilityNonce referenced outside mint/check boundary at %s:%d (%s)", file, fset.Position(typed.Pos()).Line, key)
						return false
					}
					nonceReferences[key]++
				}
			case *ast.SelectorExpr:
				receiver, receiverOK := typed.X.(*ast.Ident)
				if receiverOK && receiver.Name == "exec" && (typed.Sel.Name == "Command" || typed.Sel.Name == "CommandContext") {
					if call, ok := parents[typed].(*ast.CallExpr); !ok || call.Fun != typed {
						err = fmt.Errorf("raw exec constructor is aliased instead of called directly at %s:%d (%s)", file, fset.Position(typed.Pos()).Line, key)
						return false
					}
				}
			}
			return err == nil
		})
		if err != nil {
			return err
		}

		for _, decl := range parsed.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			key := file + ":" + fn.Name.Name
			stringsByName := functionStaticStrings(fn)
			slicesByName := functionStaticSliceFirsts(fn, stringsByName)
			ast.Inspect(fn.Body, func(node ast.Node) bool {
				if err != nil {
					return false
				}
				call, ok := node.(*ast.CallExpr)
				if !ok {
					return true
				}
				selector, ok := call.Fun.(*ast.SelectorExpr)
				if !ok || (selector.Sel.Name != "Command" && selector.Sel.Name != "CommandContext") {
					return true
				}
				receiver, ok := selector.X.(*ast.Ident)
				if !ok || receiver.Name != "exec" {
					return true
				}
				commandArg := 0
				if selector.Sel.Name == "CommandContext" {
					commandArg = 1
				}
				if len(call.Args) <= commandArg {
					return true
				}

				if key == "internal/compose/compose.go:dockerComposeCommand" {
					if executable, ok := staticStringExpr(call.Args[commandArg], stringsByName); !ok || executable != "docker" {
						err = fmt.Errorf("dockerComposeCommand no longer constructs docker directly at %s:%d", file, fset.Position(call.Pos()).Line)
					}
					return false
				}
				if key == "internal/upgrade/exec.go:commandContextWithComposeUp" {
					if ident, ok := call.Args[commandArg].(*ast.Ident); !ok || ident.Name != "name" {
						err = fmt.Errorf("upgrade compose-aware command factory raw executable is no longer its inspected name parameter at %s:%d", file, fset.Position(call.Pos()).Line)
					} else if !callsComposeCommand(fn.Body) || !exactStringLiteral(fn.Body, "docker") || !exactStringLiteral(fn.Body, "compose") {
						err = fmt.Errorf("upgrade command factory lost docker-compose wrapper delegation at %s:%d", file, fset.Position(fn.Pos()).Line)
					}
					return false
				}
				if key == "cmd/install.go:commandContextDir" {
					if ident, ok := call.Args[commandArg].(*ast.Ident); !ok || ident.Name != "name" {
						err = fmt.Errorf("cmd compose-aware command factory raw executable is no longer its inspected name parameter at %s:%d", file, fset.Position(call.Pos()).Line)
					} else if !callsComposeCommand(fn.Body) || !exactStringLiteral(fn.Body, "docker") || !exactStringLiteral(fn.Body, "compose") {
						err = fmt.Errorf("cmd command factory lost docker-compose wrapper delegation at %s:%d", file, fset.Position(fn.Pos()).Line)
					}
					return false
				}
				if key == "internal/migrate/migrate.go:CommandContext" {
					if ident, ok := call.Args[commandArg].(*ast.Ident); !ok || ident.Name != "name" {
						err = fmt.Errorf("migrate compose-aware command factory raw executable is no longer its inspected name parameter at %s:%d", file, fset.Position(call.Pos()).Line)
					} else if !callsComposeCommand(fn.Body) || !exactStringLiteral(fn.Body, "docker") || !exactStringLiteral(fn.Body, "compose") {
						err = fmt.Errorf("migrate command factory lost docker-compose wrapper delegation at %s:%d", file, fset.Position(fn.Pos()).Line)
					}
					return false
				}

				executable, executableKnown := staticStringExpr(call.Args[commandArg], stringsByName)
				if !executableKnown || executable != "docker" {
					return true
				}
				if len(call.Args) <= commandArg+1 {
					err = fmt.Errorf("raw docker exec has unverifiable argv at %s:%d (%s)", file, fset.Position(call.Pos()).Line, key)
					return false
				}
				firstArg, firstKnown := firstStaticString(call.Args[commandArg+1], stringsByName, slicesByName)
				if !firstKnown {
					err = fmt.Errorf("raw docker exec has dynamically unverifiable first argv at %s:%d (%s)", file, fset.Position(call.Pos()).Line, key)
					return false
				}
				if firstArg == "compose" {
					err = fmt.Errorf("raw docker compose exec bypasses shared wrapper at %s:%d (%s)", file, fset.Position(call.Pos()).Line, key)
					return false
				}
				return true
			})
			if err != nil {
				return err
			}
		}
	}

	if capabilityConstructions != 1 {
		return fmt.Errorf("upCapability construction count = %d, want constructor-only 1", capabilityConstructions)
	}
	wantNonceReferences := map[string]int{
		"internal/compose/compose.go:MintUpCapability":     1,
		"internal/compose/compose.go:dockerComposeCommand": 1,
	}
	if fmt.Sprint(nonceReferences) != fmt.Sprint(wantNonceReferences) {
		return fmt.Errorf("upCapabilityNonce reference inventory = %v, want %v", nonceReferences, wantNonceReferences)
	}
	if fmt.Sprint(gotMints) != fmt.Sprint(wantMints) {
		return fmt.Errorf("compose-up capability mint inventory = %v, want %v", gotMints, wantMints)
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

func TestComposeRuntimeGuardHasNoExecBypassAndOnlyAllowlistedMints(t *testing.T) {
	if err := composeRuntimeGuardViolation(cliProductionSources(t)); err != nil {
		t.Fatal(err)
	}
}

func TestDynamicComposeUpThroughFuncValueIsRejectedAtRuntime(t *testing.T) {
	verb := "u" + "p"
	args := []string{"compose", verb, "-d", "app"}
	runner := runCommandOutput
	_, err := runner(t.TempDir(), "docker", args...)
	if err == nil || !strings.Contains(err.Error(), "requires an explicit capability") {
		t.Fatalf("dynamic func-value compose-up = %v, want runtime capability refusal", err)
	}
}

func TestComposeCapabilityMintMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	serviceKey := "internal/upgrade/service.go"
	mutation := `

func unauthorizedComposeUpCapabilityMutation() compose.UpCapability {
	return compose.MintUpCapability()
}
`
	sources[serviceKey] = append(append([]byte(nil), sources[serviceKey]...), []byte(mutation)...)
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "unallowlisted compose-up capability mint") || !strings.Contains(err.Error(), "unauthorizedComposeUpCapabilityMutation") {
		t.Fatalf("capability mint mutation survived AST allowlist: %v", err)
	}
}

func TestComposeExecBypassMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	serviceKey := "internal/upgrade/service.go"
	mutation := `

func unauthorizedDynamicComposeExecMutation(ctx context.Context) *exec.Cmd {
	return exec.CommandContext(ctx, "dock"+"er", "compose", "u"+"p", "-d", "app")
}
`
	sources[serviceKey] = append(append([]byte(nil), sources[serviceKey]...), []byte(mutation)...)
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "raw docker compose exec bypasses shared wrapper") || !strings.Contains(err.Error(), "unauthorizedDynamicComposeExecMutation") {
		t.Fatalf("expression-built raw compose exec mutation survived AST chokepoint guard: %v", err)
	}
}

func TestComposeCapabilityConstructionMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	composeKey := "internal/compose/compose.go"
	mutation := `

func forgedZeroValueUpCapabilityMutation() UpCapability {
	return upCapability{}
}
`
	sources[composeKey] = append(append([]byte(nil), sources[composeKey]...), []byte(mutation)...)
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "unallowlisted upCapability composite construction") || !strings.Contains(err.Error(), "forgedZeroValueUpCapabilityMutation") {
		t.Fatalf("zero-value capability construction mutation survived AST guard: %v", err)
	}
}

func TestComposeCapabilityMintAliasMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	serviceKey := "internal/upgrade/service.go"
	mutation := `

func aliasedComposeUpMintMutation() {
	mint := compose.MintUpCapability
	_ = mint
}
`
	sources[serviceKey] = append(append([]byte(nil), sources[serviceKey]...), []byte(mutation)...)
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "MintUpCapability is referenced outside a direct call") || !strings.Contains(err.Error(), "aliasedComposeUpMintMutation") {
		t.Fatalf("capability mint alias mutation survived AST guard: %v", err)
	}
}

func TestComposeCapabilityNonceLeakMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	composeKey := "internal/compose/compose.go"
	mutation := `

func leakedComposeUpNonceMutation() uint64 {
	return upCapabilityNonce
}
`
	sources[composeKey] = append(append([]byte(nil), sources[composeKey]...), []byte(mutation)...)
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "upCapabilityNonce referenced outside mint/check boundary") || !strings.Contains(err.Error(), "leakedComposeUpNonceMutation") {
		t.Fatalf("capability nonce leak mutation survived AST guard: %v", err)
	}
}

func TestInstallRawComposeBypassMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	installKey := "cmd/install.go"
	mutation := `

func rawInstallComposeUpMutation() *exec.Cmd {
	return exec.Command("docker", "compose", "up", "-d", "app")
}
`
	sources[installKey] = append(append([]byte(nil), sources[installKey]...), []byte(mutation)...)
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "raw docker compose exec bypasses shared wrapper") || !strings.Contains(err.Error(), "rawInstallComposeUpMutation") {
		t.Fatalf("install raw compose bypass mutation survived AST guard: %v", err)
	}
}

func TestNewHelperPackageRawComposeBypassMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	sources["internal/rawcompose/raw.go"] = []byte(`package rawcompose

import "os/exec"

func Run() *exec.Cmd {
	binary := "dock" + "er"
	verb := "com" + "pose"
	return exec.Command(binary, verb, "up", "-d", "app")
}
`)
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "raw docker compose exec bypasses shared wrapper") || !strings.Contains(err.Error(), "internal/rawcompose/raw.go:Run") {
		t.Fatalf("new helper-package raw compose bypass mutation survived AST guard: %v", err)
	}
}

func TestMigrateCommandFactoryWrapperBypassMutationIsRejected(t *testing.T) {
	sources := cliProductionSources(t)
	migrateKey := "internal/migrate/migrate.go"
	original := string(sources[migrateKey])
	needle := "return compose.CommandContext(ctx, projDir, args[1:]...)"
	mutation := "return exec.CommandContext(ctx, name, args...), nil"
	if !strings.Contains(original, needle) {
		t.Fatalf("migrate command factory mutation needle is stale: %q", needle)
	}
	sources[migrateKey] = []byte(strings.Replace(original, needle, mutation, 1))
	err := composeRuntimeGuardViolation(sources)
	if err == nil || !strings.Contains(err.Error(), "migrate command factory lost docker-compose wrapper delegation") {
		t.Fatalf("migrate command factory bypass mutation survived AST guard: %v", err)
	}
}
