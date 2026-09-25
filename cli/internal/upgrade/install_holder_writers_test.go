package upgrade

import (
	"go/ast"
	"go/parser"
	"go/token"
	"path/filepath"
	"runtime"
	"testing"
)

// Keep every production install-held marker writer auditable. The PID is for
// the operator message only; it must never replace the flock liveness check.
func TestAllInstallHeldMarkerWritersStampOwner(t *testing.T) {
	_, testFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("locate test directory")
	}
	count := 0
	for _, name := range []string{"service.go", "restart.go", "start_guard.go"} {
		fset := token.NewFileSet()
		file, err := parser.ParseFile(fset, filepath.Join(filepath.Dir(testFile), name), nil, 0)
		if err != nil {
			t.Fatal(err)
		}
		ast.Inspect(file, func(n ast.Node) bool {
			lit, ok := n.(*ast.CompositeLit)
			if !ok {
				return true
			}
			typ, ok := lit.Type.(*ast.Ident)
			if !ok || typ.Name != "UpgradeFlag" {
				return true
			}
			fields := map[string]ast.Expr{}
			for _, elt := range lit.Elts {
				kv, ok := elt.(*ast.KeyValueExpr)
				if !ok {
					continue
				}
				if key, ok := kv.Key.(*ast.Ident); ok {
					fields[key.Name] = kv.Value
				}
			}
			holder, ok := fields["Holder"].(*ast.Ident)
			if !ok || holder.Name != "HolderInstall" {
				return true
			}
			count++
			pid, ok := fields["PID"].(*ast.CallExpr)
			if !ok || len(pid.Args) != 0 {
				t.Errorf("%s: install-held flag must stamp os.Getpid()", fset.Position(lit.Pos()))
			} else if fn, ok := pid.Fun.(*ast.SelectorExpr); !ok || fn.Sel.Name != "Getpid" {
				t.Errorf("%s: install-held flag must stamp os.Getpid()", fset.Position(lit.Pos()))
			}
			if _, ok := fields["StartedAt"]; !ok {
				t.Errorf("%s: install-held flag lacks start time", fset.Position(lit.Pos()))
			}
			return true
		})
	}
	if count != 6 {
		t.Errorf("found %d install-held production marker writers, want 6; audit newly added or removed writers", count)
	}
}
