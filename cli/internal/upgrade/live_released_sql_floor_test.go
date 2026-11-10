//go:build livedb

package upgrade

import (
	"context"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestReleasedOldBinarySQLPreparesAgainstRollbackSchemaFloor(t *testing.T) {
	const releasedTag = "v2026.09.0-rc.14"
	projDir := findProjDir(t)
	pathsOut, err := exec.Command("git", "-C", projDir, "grep", "-l", "-E", "public\\.upgrade|upgrade_state_log|db\\.migration", releasedTag, "--", "cli/internal/upgrade/*.go", "cli/internal/migrate/*.go").Output()
	if err != nil {
		t.Fatalf("list released Go files containing daemon relations: %v", err)
	}
	statements := map[string]struct{}{}
	// A released statement is often built from literals and package string
	// constants joined with +, e.g. "UPDATE ... $2"+terminalBackupPathSQL+" WHERE
	// id = $3"+upgradeRowReturning. The statement the released binary sends is the
	// whole concatenation, so a constant-only + expression is evaluated and
	// prepared as one; a single fragment of it is not a statement (pg_safeupdate
	// refuses an UPDATE fragment that stops before its WHERE).
	type releasedFile struct {
		path string
		file *ast.File
	}
	var files []releasedFile
	constsByPackage := map[string]map[string]string{}
	for _, taggedPath := range strings.Fields(string(pathsOut)) {
		path := strings.TrimPrefix(taggedPath, releasedTag+":")
		if strings.HasSuffix(path, "_test.go") {
			continue
		}
		source, showErr := exec.Command("git", "-C", projDir, "show", releasedTag+":"+path).Output()
		if showErr != nil {
			t.Fatalf("read released source %s: %v", path, showErr)
		}
		file, parseErr := parser.ParseFile(token.NewFileSet(), path, source, 0)
		if parseErr != nil {
			t.Fatalf("parse released source %s: %v", path, parseErr)
		}
		files = append(files, releasedFile{path: path, file: file})
	}
	for _, rf := range files {
		pkg := filepath.Dir(rf.path)
		if constsByPackage[pkg] == nil {
			constsByPackage[pkg] = map[string]string{}
		}
		for _, decl := range rf.file.Decls {
			gen, ok := decl.(*ast.GenDecl)
			if !ok || gen.Tok != token.CONST {
				continue
			}
			for _, spec := range gen.Specs {
				vs := spec.(*ast.ValueSpec)
				for i, name := range vs.Names {
					if i < len(vs.Values) {
						if lit, ok := vs.Values[i].(*ast.BasicLit); ok && lit.Kind == token.STRING {
							if value, err := strconv.Unquote(lit.Value); err == nil {
								constsByPackage[pkg][name.Name] = value
							}
						}
					}
				}
			}
		}
	}
	for _, rf := range files {
		path, file, consts := rf.path, rf.file, constsByPackage[filepath.Dir(rf.path)]
		var constString func(ast.Expr) (string, bool)
		constString = func(expr ast.Expr) (string, bool) {
			switch e := expr.(type) {
			case *ast.BasicLit:
				if e.Kind != token.STRING {
					return "", false
				}
				value, err := strconv.Unquote(e.Value)
				return value, err == nil
			case *ast.Ident:
				value, ok := consts[e.Name]
				return value, ok
			case *ast.ParenExpr:
				return constString(e.X)
			case *ast.BinaryExpr:
				if e.Op != token.ADD {
					return "", false
				}
				left, okLeft := constString(e.X)
				right, okRight := constString(e.Y)
				return left + right, okLeft && okRight
			}
			return "", false
		}
		ast.Inspect(file, func(node ast.Node) bool {
			var value string
			switch n := node.(type) {
			case *ast.BinaryExpr:
				whole, ok := constString(n)
				if !ok {
					return true
				}
				value = whole
			case *ast.BasicLit:
				if n.Kind != token.STRING {
					return true
				}
				unquoted, unquoteErr := strconv.Unquote(n.Value)
				if unquoteErr != nil {
					t.Fatalf("unquote released SQL literal in %s: %v", path, unquoteErr)
				}
				value = unquoted
			default:
				return true
			}
			trimmed := strings.TrimSpace(value)
			upper := strings.ToUpper(trimmed)
			if !strings.Contains(trimmed, "public.upgrade") && !strings.Contains(trimmed, "upgrade_state_log") && !strings.Contains(trimmed, "db.migration") {
				return true
			}
			if strings.Contains(trimmed, "%") || strings.Contains(trimmed, ":'") || strings.Contains(trimmed, ":version") || trimmed == "INSERT INTO public.upgrade" || trimmed == "UPDATE public.upgrade" {
				return true
			}
			if strings.HasPrefix(upper, "SELECT ") || strings.HasPrefix(upper, "INSERT ") || strings.HasPrefix(upper, "UPDATE ") || strings.HasPrefix(upper, "DELETE ") || strings.HasPrefix(upper, "CALL ") || strings.HasPrefix(upper, "WITH ") {
				statements[trimmed] = struct{}{}
			}
			// A whole constant concatenation is the statement; its pieces are not.
			_, isConcat := node.(*ast.BinaryExpr)
			return !isConcat
		})
	}
	if len(statements) == 0 {
		t.Fatal("released SQL extraction found no daemon statements")
	}

	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("connect live floored database: %v", err)
	}
	defer d.Close()
	var floorRecorded bool
	if err := d.queryConn.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM db.migration WHERE version = 20260907120000)").Scan(&floorRecorded); err != nil || !floorRecorded {
		t.Fatalf("live database is not migrated through rollback daemon floor 20260907120000: recorded=%v err=%v", floorRecorded, err)
	}

	ordered := make([]string, 0, len(statements))
	for statement := range statements {
		ordered = append(ordered, statement)
	}
	sort.Strings(ordered)
	for i, statement := range ordered {
		name := fmt.Sprintf("statbus_released_rc14_%d", i)
		if _, err := d.queryConn.Prepare(ctx, name, statement); err != nil {
			t.Errorf("released statement %d did not prepare:\n%s\nerror: %v", i+1, statement, err)
			continue
		}
		if err := d.queryConn.Deallocate(ctx, name); err != nil {
			t.Fatalf("deallocate released statement %d: %v", i+1, err)
		}
	}
	t.Logf("prepared %d released SQL statements from %s", len(ordered), releasedTag)
}
