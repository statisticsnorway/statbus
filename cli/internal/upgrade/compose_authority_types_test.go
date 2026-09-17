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
// are forbidden; construction is exact-site allowlisted; executables are
// compile-time constants except three pinned existing syscall.Exec handoffs; and
// raw docker/docker-compose constants are confined to internal/compose. Shell
// executables require constant, docker/compose-free arguments. The only dynamic
// shell calls are the exact-count-pinned pre-existing user/configuration command
// facilities named below, never generic recovery command construction.
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

// These existing syscall.Exec handoffs replace the current process with a path
// resolved from the already-selected psql or sb binary. Their dynamic paths are
// public behavior, so the exception is exact by launcher and enclosing site.
// Every other covered launcher still requires a compile-time executable.
var allowedDynamicSyscallExecHandoffs = map[string]bool{
	"cmd/psql.go:psqlCmd.RunE":                       true,
	"internal/freshness/rebuild.go:RebuildAndReexec": true,
	"internal/upgrade/service.go:executeUpgrade":     true,
}

// These are pre-existing, explicit user/configuration command facilities rather
// than source-authored recovery commands. Their exact shell executable and site
// are pinned so an added dynamic shell call, even in the same function, changes
// the inventory and fails. All other shell arguments must be compile-time
// constants and must not contain docker/compose tokens.
var allowedIntentionalDynamicShellCalls = map[string]int{
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

func authorityShellExecutable(executable string) bool {
	switch executable {
	case "sh", "bash", "zsh", "dash", "/bin/sh", "/usr/bin/env":
		return true
	default:
		return false
	}
}

func authorityContainsDockerComposeToken(argument string) bool {
	tokens := strings.FieldsFunc(argument, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_'
	})
	for _, token := range tokens {
		if strings.EqualFold(token, "docker") || strings.EqualFold(token, "compose") {
			return true
		}
	}
	return false
}

func authorityProcessLaunchViolations(launch authorityProcessLaunch, key, packagePath string, line int, info *types.Info, gotIntentionalDynamicShellCalls map[string]int) []string {
	var violations []string
	if !allowedProcessLaunchFunctions[key] {
		violations = append(violations, fmt.Sprintf("unallowlisted %s construction at %s:%d", launch.kind, key, line))
	}
	executable, executableConstant := authorityConstantString(info, launch.executable)
	dynamicHandoff := launch.kind == "syscall.Exec" && allowedDynamicSyscallExecHandoffs[key]
	if !executableConstant {
		if !dynamicHandoff {
			violations = append(violations, fmt.Sprintf("dynamic %s executable at %s:%d", launch.kind, key, line))
		}
		return violations
	}
	if (executable == "docker" || executable == "docker-compose") && packagePath != composePackagePath {
		violations = append(violations, fmt.Sprintf("raw %s process launch outside compose wrapper at %s:%d", executable, key, line))
	}
	if !authorityShellExecutable(executable) {
		return violations
	}
	hasDynamicArgument := !launch.argsKnown
	for _, argumentExpression := range launch.arguments {
		argument, ok := authorityConstantString(info, argumentExpression)
		if !ok {
			hasDynamicArgument = true
			continue
		}
		if authorityContainsDockerComposeToken(argument) {
			violations = append(violations, fmt.Sprintf("shell argument contains docker/compose authority for %s at %s:%d", executable, key, line))
		}
	}
	if hasDynamicArgument {
		allowanceKey := key + "|" + executable
		if _, allowed := allowedIntentionalDynamicShellCalls[allowanceKey]; allowed {
			gotIntentionalDynamicShellCalls[allowanceKey]++
		} else {
			violations = append(violations, fmt.Sprintf("dynamic shell argument for %s at %s:%d", executable, key, line))
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
	gotIntentionalDynamicShellCalls := make(map[string]int)
	var violations []string

	for _, goos := range gooses {
		files, err := loadTypedAuthorityPackages(cliDir, goos, overlay)
		if err != nil {
			return err
		}
		for _, typedFile := range files {
			loadedFiles[typedFile.path] = true
			parents := authorityParents(typedFile.file)
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
				if seenProcessLaunch[location] {
					return true
				}
				seenProcessLaunch[location] = true
				key := authorityEnclosingFunction(typedFile.path, launcherNode, parents)
				violations = append(violations, authorityProcessLaunchViolations(launch, key, typedFile.pkg.PkgPath, position.Line, info, gotIntentionalDynamicShellCalls)...)
				return true
			})
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
	for key, want := range allowedIntentionalDynamicShellCalls {
		if gotIntentionalDynamicShellCalls[key] != want {
			violations = append(violations, fmt.Sprintf("intentional dynamic shell call inventory at %s = %d, want %d", key, gotIntentionalDynamicShellCalls[key], want))
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
	if err == nil || !strings.Contains(err.Error(), "shell argument contains docker/compose authority") {
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
	if err == nil || !strings.Contains(err.Error(), "shell argument contains docker/compose authority") {
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

func TestTypedComposeAuthorityRejectsDynamicShellArgument(t *testing.T) {
	cliDir := thisRepoFile(t, "cli")
	overlay := authorityOverlay(t, cliDir, "internal/compose/compose.go", func(source string) string {
		anchor := "func dockerComposeCommand(ctx context.Context, projDir string, args ...string) (*exec.Cmd, error) {\n"
		return strings.Replace(source, anchor, anchor+"\t_ = exec.Command(\"sh\", \"-c\", os.Getenv(\"PAYLOAD\"))\n", 1)
	})
	err := typedAuthorityViolation(cliDir, overlay)
	if err == nil || !strings.Contains(err.Error(), "dynamic shell argument") {
		t.Fatalf("dynamic shell argument mutation survived: %v", err)
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
