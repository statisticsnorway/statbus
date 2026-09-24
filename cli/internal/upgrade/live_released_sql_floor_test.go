//go:build livedb

package upgrade

import (
	"context"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os/exec"
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
		ast.Inspect(file, func(node ast.Node) bool {
			literal, ok := node.(*ast.BasicLit)
			if !ok || literal.Kind != token.STRING {
				return true
			}
			value, unquoteErr := strconv.Unquote(literal.Value)
			if unquoteErr != nil {
				t.Fatalf("unquote released SQL literal in %s: %v", path, unquoteErr)
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
			return true
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
