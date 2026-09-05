package releasecmd

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-352 policy closure, enforced by the compiler's own import graph.
//
// The point of extracting cmd/release is that "did this change touch what
// runs on a box?" becomes answerable by import direction instead of by a
// blanket "everything under cli/ is box payload". That is only true while
// these edges hold, so each is pinned here and a violation is a red test,
// not a code-review hope.

const modulePrefix = "github.com/statisticsnorway/statbus/cli/"

func goListDeps(t *testing.T, pkg string) map[string]bool {
	t.Helper()
	cmd := exec.Command("go", "list", "-deps", pkg)
	cmd.Dir = filepath.Join(thisRepoFile(t, "cli"))
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("go list -deps %s: %v\n%s", pkg, err, out)
	}
	deps := map[string]bool{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		deps[strings.TrimSpace(line)] = true
	}
	return deps
}

func TestArchitecture_OrdinaryCmdNeverReachesReleaseEngine_STATBUS352(t *testing.T) {
	deps := goListDeps(t, "./cmd")
	for _, forbidden := range []string{modulePrefix + "cmd/release", modulePrefix + "internal/release"} {
		if deps[forbidden] {
			t.Errorf("cmd reaches %s (directly or transitively) — the box-command policy closure is broken; a box-payload change and a release-tooling change can no longer be told apart", forbidden)
		}
	}
}

func TestArchitecture_MigrationCodeNeverImportsReleaseEngine_STATBUS352(t *testing.T) {
	deps := goListDeps(t, "./internal/migrate")
	if deps[modulePrefix+"internal/release"] {
		t.Fatal("internal/migrate imports internal/release again; the four release questions must stay injected through migrate.ReleaseProbes (STATBUS-352 C2)")
	}
}

func TestArchitecture_ReleaseCommandPackageHasNoInit_STATBUS352(t *testing.T) {
	dir := thisRepoFile(t, "cli/cmd/release")
	fset := token.NewFileSet()
	pkgs, err := parser.ParseDir(fset, dir, func(fi os.FileInfo) bool { return !strings.HasSuffix(fi.Name(), "_test.go") }, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, pkg := range pkgs {
		for file, f := range pkg.Files {
			for _, decl := range f.Decls {
				fn, ok := decl.(*ast.FuncDecl)
				if ok && fn.Recv == nil && fn.Name.Name == "init" {
					t.Errorf("%s declares init(); release commands must be composed explicitly by main.go via Command()", file)
				}
			}
		}
	}
}

func TestArchitecture_CompositionIsExplicitAtTheEntrypoint_STATBUS352(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/main.go"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"cmd.Mount(releasecmd.Command())", "migrate.ReleaseProbe = releasecmd.MigrateProbes()"} {
		if !strings.Contains(string(src), want) {
			t.Errorf("cli/main.go no longer contains %q; command composition and probe wiring must stay explicit at the process entrypoint", want)
		}
	}
	// The wiring must happen BEFORE Execute, or the first migrate command
	// would refuse with "release probes are not wired".
	s := string(src)
	if strings.Index(s, "migrate.ReleaseProbe =") > strings.Index(s, "cmd.Execute()") {
		t.Error("main.go wires migrate.ReleaseProbe after cmd.Execute(); it must be set first")
	}
}

// The seam cmd exposes to cmd/release must stay small and named. Growing it
// is how "a few accessors" becomes "cmd's internals are public".
func TestArchitecture_CmdSeamStaysSmall_STATBUS352(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/cmd/release_seam.go"))
	if err != nil {
		t.Fatal(err)
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "release_seam.go", src, 0)
	if err != nil {
		t.Fatal(err)
	}
	var exported []string
	for _, decl := range f.Decls {
		if fn, ok := decl.(*ast.FuncDecl); ok && fn.Name.IsExported() {
			exported = append(exported, fn.Name.Name)
		}
	}
	if strings.Join(exported, ",") != "Verbose,Mount" {
		t.Fatalf("cmd/release_seam.go exports %v; the seam is exactly Verbose and Mount — widen it only with a recorded ruling", exported)
	}
}
