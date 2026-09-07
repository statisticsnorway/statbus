package upgrade

import (
	"context"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestRollbackFinishingPhaseIsTargetBinaryRecovery(t *testing.T) {
	flag := &UpgradeFlag{Holder: HolderService, CommitSHA: "abc", Phase: PhaseRollbackFinishing}
	if !flag.IsServiceNewSbRecovery() {
		t.Fatal("rollback_finishing must preserve the target recovery binary")
	}
}

func TestRollbackFinishingMarkerFollowsPendingCommitAndPrecedesCleanup(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) restoreAndFinalize(")
	pending := strings.Index(body, "rollback_finish_pending_at = now()")
	phase := strings.Index(body, "PhaseRollbackFinishing")
	finalize := strings.Index(body, "d.finalizePendingRollback(")
	publish := strings.LastIndex(body, "d.restoreBinary(")
	if pending < 0 || phase < pending || finalize < phase || publish < finalize {
		t.Fatalf("rollback finishing order must be pending < cleanup marker < final row/marker < binary publish, got %d < %d < %d < %d", pending, phase, finalize, publish)
	}
}

func TestFinalizePendingRollbackCommitsBeforeMarkerRemoval(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) finalizePendingRollback(")
	commit := strings.Index(body, "tx.Commit(ctx)")
	clear := strings.Index(body, "d.clearRollbackFinishFlag(id)")
	if commit < 0 || clear < 0 || commit > clear {
		t.Fatalf("final row must commit before cleanup marker removal: commit=%d clear=%d", commit, clear)
	}
}

func TestReleasedOldBinarySQLPreparesAgainstRollbackSchemaFloor(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to prepare released daemon SQL against the live floored schema")
	}
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
			// fmt.Sprintf and psql-variable literals are templates, not SQL bytes
			// submitted by the released binary. The instantiated statements are
			// captured at their non-template call sites.
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
		// Protocol-level Parse accepts every statement form the released daemon
		// executes, including CALL. SQL PREPARE's grammar excludes CALL even though
		// PostgreSQL's extended-query protocol can parse it without execution.
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
