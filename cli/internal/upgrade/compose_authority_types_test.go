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
// syscall.ForkExec, and os/exec.Cmd composite literals. Launcher function values
// are forbidden; construction is exact-site allowlisted; and every constant
// executable must belong to the closed tool/mediator table below. Tools may
// receive dynamic path/SHA arguments, but no constant argument may carry a
// docker/docker-compose/podman/compose token. Mediators require constant,
// authority-free arguments except the exact-count-pinned pre-existing
// user/configuration facilities below. Docker itself is confined to the Compose
// wrapper. The three dynamic syscall.Exec handoffs are adjacent-marker and
// exact-count pinned; every other covered launcher requires a constant executable.
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
)

type typedAuthorityPackage struct {
	pkg  *packages.Package
	file *ast.File
	path string
}

var allowedComposeUpCalls = map[string]int{
	"cmd/db.go:dockerComposeStart":                            1,
	"cmd/install.go:composeApplyServiceDefault":               1,
	"cmd/install.go:runInstall":                               1,
	"cmd/install.go:runStartServices":                         1,
	"cmd/service.go:startServices":                            1,
	"cmd/service_restart.go:restartServices":                  1,
	"internal/upgrade/exec.go:EnsureDBUp":                     1,
	"internal/upgrade/service.go:abortFailedPreBackupStop":    1,
	"internal/upgrade/service.go:applyNewSbUpgrading":         2,
	"internal/upgrade/service.go:completeInProgressUpgrade":   1,
	"internal/upgrade/service.go:startSourceApplicationStack": 1,
}

// Filled with the exact existing process-construction functions. A new process
// launcher of any covered kind must be reviewed and added deliberately.
var allowedProcessLaunchFunctions = map[string]bool{
	"cmd/db.go:backupCreateCmd.RunE":                                  true,
	"cmd/db.go:backupRestoreCmd.RunE":                                 true,
	"cmd/db.go:dbDownloadCmd.RunE":                                    true,
	"cmd/db.go:restoreRemote":                                         true,
	"cmd/db_with_seed_lock.go:withSeedLockCmd.RunE":                   true,
	"cmd/dotenv.go:dotenvGenerateCmd.RunE":                            true,
	"cmd/install.go:checkSignersDone":                                 true,
	"cmd/install.go:commandContextDir":                                true,
	"cmd/install.go:runInstallCallback":                               true,
	"cmd/install.go:runInstallService":                                true,
	"cmd/install.go:runRootInstall":                                   true,
	"cmd/install_upgrade.go:restartUpgradeService":                    true,
	"cmd/install_upgrade.go:stopRestartUpgradeUnit":                   true,
	"cmd/install_upgrade.go:upgradeUnitCrashLooping":                  true,
	"cmd/release/release_canary.go:runCanaryProbe":                    true,
	"cmd/release/release_sshdoers_drift.go:readLiveSshdoersHash":      true,
	"cmd/service_restart.go:restartServices":                          true,
	"cmd/test.go:testCmd.RunE":                                        true,
	"cmd/upgrade.go:sshKeyFingerprint":                                true,
	"cmd/upgrade.go:trustKeyVerifyCmd.RunE":                           true,
	"internal/compose/compose.go:DockerCommandContext":                true,
	"internal/compose/compose.go:Up":                                  true,
	"internal/compose/compose.go:dockerComposeCommand":                true,
	"internal/config/config.go:computeDerived":                        true,
	"internal/config/config.go:generateJWT":                           true,
	"internal/freshness/check.go:CommittedDrift":                      true,
	"internal/freshness/check.go:isStale":                             true,
	"internal/freshness/check.go:probeCommittedDrift":                 true,
	"internal/freshness/rebuild.go:headCommit":                        true,
	"internal/migrate/migrate.go:CommandContext":                      true,
	"internal/migrate/migrate.go:maybeRebuildTestTemplate":            true,
	"internal/release/box_closure.go:deriveBoxCommandClosure":         true,
	"internal/release/box_closure.go:extractTree":                     true,
	"internal/release/box_closure.go:goListModulePath":                true,
	"internal/release/harness_validation.go:ValidateHarnessDomainAt":  true,
	"internal/release/harness_validation.go:extractHarnessTree":       true,
	"internal/release/immutability.go:FileIsDirty":                    true,
	"internal/release/immutability.go:MigrationExistsInTag":           true,
	"internal/release/immutability.go:MigrationInReleasedTag":         true,
	"internal/release/immutability.go:ReleaseTagsNewestFirst":         true,
	"internal/release/immutability.go:migrationUpBlobHashInTag":       true,
	"internal/release/predecessor.go:CurrentImmutabilityBaselineTag":  true,
	"internal/release/predecessor.go:FindLatestStableTagBeforePrefix": true,
	"internal/release/predecessor.go:ListRCNumbersForPatch":           true,
	"internal/release/predecessor.go:TagExistsLocally":                true,
	"internal/release/scenario.go:runGit":                             true,
	"internal/release/sensitivity.go:DiffSensitiveChanges":            true,
	"internal/sbimage/sbimage.go:run":                                 true,
	"internal/selfupdate/selfupdate.go:ReplaceBinaryOnDisk":           true,
	"internal/unitfloor/unitfloor.go:isActiveSystemd":                 true,
	"internal/upgrade/bundle.go:bundleJournalctlBody":                 true,
	"internal/upgrade/exec.go:commandContext":                         true,
	"internal/upgrade/exec.go:runInstallFixup":                        true,
	"internal/upgrade/refspec.go:NormalizeOriginURL":                  true,
	"internal/upgrade/refspec.go:NormalizeRefspecs":                   true,
	"internal/upgrade/refspec.go:isGitRepo":                           true,
	"internal/upgrade/service.go:executeUpgrade":                      true,
	"internal/upgrade/service.go:loadTrustedSigners":                  true,
	"internal/upgrade/service.go:runCallback":                         true,
	"cmd/psql.go:psqlCmd.RunE":                                        true,
	"internal/freshness/rebuild.go:RebuildAndReexec":                  true,
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
	"/usr/bin/env": authorityMediator,
	"bash":         authorityMediator,
	"docker":       authorityTool,
	"git":          authorityTool,
	"go":           authorityTool,
	"journalctl":   authorityTool,
	"loginctl":     authorityTool,
	"node":         authorityTool,
	"pg_dump":      authorityTool,
	"pg_restore":   authorityTool,
	"psql":         authorityTool,
	"rsync":        authorityTool,
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
var allowedDynamicSyscallExecHandoffs = map[string]int{
	"cmd/psql.go:psqlCmd.RunE":                       1,
	"internal/freshness/rebuild.go:RebuildAndReexec": 1,
	"internal/upgrade/service.go:executeUpgrade":     1,
}

// These are pre-existing, explicit user/configuration command facilities rather
// than source-authored recovery commands. Their exact mediator executable and
// site are pinned so an added dynamic mediator call, even in the same function,
// changes the inventory and fails. All other mediator arguments must be
// compile-time constants and must not contain authority tokens.
var allowedIntentionalDynamicMediatorCalls = map[string]int{
	"cmd/db_with_seed_lock.go:withSeedLockCmd.RunE|/usr/bin/env":         1,
	"cmd/dotenv.go:dotenvGenerateCmd.RunE|sh":                            1,
	"cmd/install.go:runInstallCallback|sh":                               1,
	"internal/selfupdate/selfupdate.go:ReplaceBinaryOnDisk|/usr/bin/env": 1,
	"internal/upgrade/service.go:runCallback|sh":                         1,
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

func authorityProcessLaunchViolations(launch authorityProcessLaunch, key, packagePath string, line int, info *types.Info, pinnedReexec bool, gotPinnedReexecHandoffs, gotIntentionalDynamicMediatorCalls, gotExecutableUses map[string]int) []string {
	var violations []string
	if !allowedProcessLaunchFunctions[key] {
		violations = append(violations, fmt.Sprintf("unallowlisted %s construction at %s:%d", launch.kind, key, line))
	}
	executable, executableConstant := authorityConstantString(info, launch.executable)
	_, handoffAllowed := allowedDynamicSyscallExecHandoffs[key]
	dynamicHandoff := launch.kind == "syscall.Exec" && handoffAllowed && pinnedReexec
	if !executableConstant {
		if dynamicHandoff {
			gotPinnedReexecHandoffs[key]++
		} else {
			violations = append(violations, fmt.Sprintf("dynamic %s executable at %s:%d", launch.kind, key, line))
		}
		return violations
	}
	class, executableAllowed := allowedProcessExecutables[executable]
	if !executableAllowed {
		violations = append(violations, fmt.Sprintf("unknown %s executable %q at %s:%d", launch.kind, executable, key, line))
		return violations
	}
	gotExecutableUses[executable]++
	if (executable == "docker" || executable == "docker-compose") && packagePath != composePackagePath {
		violations = append(violations, fmt.Sprintf("raw %s process launch outside compose wrapper at %s:%d", executable, key, line))
	}
	hasDynamicArgument := !launch.argsKnown
	for _, argumentExpression := range launch.arguments {
		argument, ok := authorityConstantString(info, argumentExpression)
		if !ok {
			hasDynamicArgument = true
			continue
		}
		if authorityContainsComposeAuthorityToken(argument) {
			violations = append(violations, fmt.Sprintf("%s argument contains docker/docker-compose/podman/compose authority for %s at %s:%d", class, executable, key, line))
		}
	}
	if class == authorityMediator && hasDynamicArgument {
		allowanceKey := key + "|" + executable
		if _, allowed := allowedIntentionalDynamicMediatorCalls[allowanceKey]; allowed {
			gotIntentionalDynamicMediatorCalls[allowanceKey]++
		} else {
			violations = append(violations, fmt.Sprintf("dynamic mediator argument for %s at %s:%d", executable, key, line))
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
	seenUpUse := make(map[string]bool)
	seenProcessLaunch := make(map[string]bool)
	seenPinnedReexecMarkers := make(map[string]bool)
	usedPinnedReexecMarkers := make(map[string]bool)
	gotPinnedReexecHandoffs := make(map[string]int)
	gotIntentionalDynamicMediatorCalls := make(map[string]int)
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
				violations = append(violations, authorityProcessLaunchViolations(launch, key, typedFile.pkg.PkgPath, position.Line, info, pinnedReexec, gotPinnedReexecHandoffs, gotIntentionalDynamicMediatorCalls, gotExecutableUses)...)
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
	for key, want := range allowedComposeUpCalls {
		if gotUpCalls[key] != want {
			violations = append(violations, fmt.Sprintf("compose.Up call inventory at %s = %d, want %d", key, gotUpCalls[key], want))
		}
	}
	for key, want := range allowedIntentionalDynamicMediatorCalls {
		if gotIntentionalDynamicMediatorCalls[key] != want {
			violations = append(violations, fmt.Sprintf("intentional dynamic mediator call inventory at %s = %d, want %d", key, gotIntentionalDynamicMediatorCalls[key], want))
		}
	}
	for key, want := range allowedDynamicSyscallExecHandoffs {
		if gotPinnedReexecHandoffs[key] != want {
			violations = append(violations, fmt.Sprintf("pinned dynamic syscall.Exec inventory at %s = %d, want %d", key, gotPinnedReexecHandoffs[key], want))
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
		if err == nil || !strings.Contains(err.Error(), "unallowlisted os/exec construction") || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
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
		if err == nil || !strings.Contains(err.Error(), "unallowlisted os/exec construction") || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
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
		if err == nil || !strings.Contains(err.Error(), "unallowlisted syscall.ForkExec construction") || !strings.Contains(err.Error(), "raw docker process launch outside compose wrapper") {
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
