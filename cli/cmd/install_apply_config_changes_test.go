package cmd

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strconv"
	"strings"
	"testing"
)

// TestNoStepAfterApplyConfigChangesRegeneratesEnv is STATBUS-332's REQUIRED
// structural pin (architect's ruling, 2026-08-31): the whole diff-and-restart
// design depends on ".env" not changing again between the comparison-point
// snapshot taken before the step loop and the "Apply config changes" step
// that diffs against it. That is true TODAY only by inspection — nothing
// stops a future step inserted after "Apply config changes" from calling
// `sb config generate` (or config.Generate / generateEnvContent in-process)
// and silently invalidating the diff this step already computed and acted
// on. This pin fails the moment that happens, rather than a rewritten .env
// going unrestarted-for on some future box.
//
// Source-text scan bounded to each step's OWN run-function body via the AST
// (no seam, no live install) — the same genre as this session's other
// body-inspection pins (STATBUS-252's TestEvidenceMemoKeysExcludeScenario,
// STATBUS-321's funcBodiesContaining). The fingerprint is the substring
// "generate": every real regeneration path — the `"config", "generate"`
// subprocess args runCreateCreds/runGenerateEnv use, config.Generate, and
// generateEnvContent — contains it, and none of the 8 steps currently
// positioned after "Apply config changes" (Backup ownership, Database
// sessions, Seed, Migrations, JWT secret, Users, Trusted signers, Upgrade
// service) do.
func TestNoStepAfterApplyConfigChangesRegeneratesEnv(t *testing.T) {
	path := thisRepoFile(t, "cli/cmd/install.go")
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, path, src, 0)
	if err != nil {
		t.Fatalf("parse install.go: %v", err)
	}

	// Index top-level func declarations by name, for resolving a step's run
	// field when it is a plain identifier (every step but "Apply config
	// changes" itself, whose check/run are inline closures).
	funcsByName := map[string]*ast.FuncDecl{}
	for _, decl := range f.Decls {
		if fn, ok := decl.(*ast.FuncDecl); ok && fn.Recv == nil {
			funcsByName[fn.Name.Name] = fn
		}
	}

	var stepsLit *ast.CompositeLit
	ast.Inspect(f, func(n ast.Node) bool {
		fn, ok := n.(*ast.FuncDecl)
		if !ok || fn.Name.Name != "runInstall" {
			return true
		}
		ast.Inspect(fn.Body, func(n2 ast.Node) bool {
			assign, ok := n2.(*ast.AssignStmt)
			if !ok || len(assign.Lhs) != 1 {
				return true
			}
			id, ok := assign.Lhs[0].(*ast.Ident)
			if !ok || id.Name != "steps" || len(assign.Rhs) != 1 {
				return true
			}
			cl, ok := assign.Rhs[0].(*ast.CompositeLit)
			if !ok {
				return true
			}
			at, ok := cl.Type.(*ast.ArrayType)
			if !ok {
				return true
			}
			elt, ok := at.Elt.(*ast.Ident)
			if !ok || elt.Name != "step" {
				return true
			}
			stepsLit = cl
			return false
		})
		return false
	})
	if stepsLit == nil {
		t.Fatal(`could not find "steps := []step{...}" in runInstall — if the step table was restructured, this pin must follow it; the property it protects has not stopped mattering`)
	}

	type stepEntry struct {
		name string
		run  ast.Expr
	}
	var entries []stepEntry
	for _, el := range stepsLit.Elts {
		row, ok := el.(*ast.CompositeLit)
		if !ok || len(row.Elts) != 3 {
			t.Fatalf("unexpected step entry shape (want 3 unkeyed fields: name, check, run): %#v", el)
		}
		nameLit, ok := row.Elts[0].(*ast.BasicLit)
		if !ok || nameLit.Kind != token.STRING {
			t.Fatalf("step entry's first field is not a string literal: %#v", row.Elts[0])
		}
		name, err := strconv.Unquote(nameLit.Value)
		if err != nil {
			t.Fatalf("unquote step name %s: %v", nameLit.Value, err)
		}
		entries = append(entries, stepEntry{name: name, run: row.Elts[2]})
	}

	anchorIdx := -1
	for i, e := range entries {
		if e.name == "Apply config changes" {
			anchorIdx = i
			break
		}
	}
	if anchorIdx == -1 {
		t.Fatal(`step "Apply config changes" not found — if it was renamed, this pin must follow it`)
	}
	if anchorIdx == len(entries)-1 {
		t.Fatal(`"Apply config changes" is the last step — nothing downstream to check; if steps were reordered, re-verify this pin still protects something`)
	}

	bodyText := func(e ast.Expr) (string, bool) {
		switch v := e.(type) {
		case *ast.Ident:
			fn, ok := funcsByName[v.Name]
			if !ok || fn.Body == nil {
				return "", false
			}
			start := fset.Position(fn.Body.Lbrace).Offset
			end := fset.Position(fn.Body.Rbrace).Offset
			return string(src[start:end]), true
		case *ast.FuncLit:
			start := fset.Position(v.Body.Lbrace).Offset
			end := fset.Position(v.Body.Rbrace).Offset
			return string(src[start:end]), true
		default:
			return "", false
		}
	}

	for _, e := range entries[anchorIdx+1:] {
		body, ok := bodyText(e.run)
		if !ok {
			t.Errorf("step %q: could not resolve its run function's body to scan it — a new kind of run-field expression was introduced; extend bodyText or move this step before the comparison point", e.name)
			continue
		}
		if strings.Contains(strings.ToLower(body), "generate") {
			t.Errorf(`step %q (positioned AFTER "Apply config changes") mentions "generate" in its run function's body.

The diff-and-restart design depends on .env not changing again after the
"Apply config changes" step diffs it against the pre-loop snapshot. A step
here that regenerates .env (sb config generate / config.Generate /
generateEnvContent) would silently invalidate that diff — a real config
change could land in .env with nothing left in the step table to notice and
restart for it.

Move the regeneration before "Apply config changes", or move this step
before it, whichever preserves the DDL quiesce ordering and this diff's
correctness.`, e.name)
		}
	}
}
