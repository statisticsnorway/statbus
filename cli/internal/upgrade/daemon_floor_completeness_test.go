package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// namedFloorExclusions: schema-qualified identifiers that appear in the daemon
// package's non-test .go but are NOT part of the daemon's live SQL surface — each
// carrying its self-consistency reason (STATBUS-145). The floor schema is
// internally self-consistent (floor-era triggers fire on floor-era tables), so
// the floor guards ONLY against the daemon's Go SQL-referencing a relation the
// floor schema lacks. Identifiers the daemon never SQL-references are excluded
// here rather than added to migrate.DaemonRelationNames.
var namedFloorExclusions = map[string]string{
	"public.docker_images_status_type": "doc-comment-only (image_claim_gate.go): the daemon never casts to it qualified in a query; the build-status column it types lives on public.upgrade (in-set), so a floor-era daemon is self-consistent",
	"db.go":                            "a source-filename reference in a comment (exec.go: 'cmd/db.go'), not a schema relation",
}

// TestDaemonFloorRelationSetIsComplete closes the class of gap the architect's
// package-wide sweep caught (the set had been enumerated from service.go alone,
// missing exec.go's retention relations). It scans EVERY non-test .go in the
// daemon package for schema-qualified identifiers and asserts each distinct one is
// either in migrate.DaemonRelationNames (the floor set) or in namedFloorExclusions
// (with a reason). A new daemon relation added anywhere in the package therefore
// cannot be silently omitted from the floor — this test fails until it is placed.
func TestDaemonFloorRelationSetIsComplete(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	pkgDir := filepath.Dir(thisFile)

	entries, err := os.ReadDir(pkgDir)
	if err != nil {
		t.Fatalf("read package dir %s: %v", pkgDir, err)
	}

	inSet := make(map[string]bool, len(migrate.DaemonRelationNames))
	for _, r := range migrate.DaemonRelationNames {
		inSet[r] = true
	}

	// Greedy so `public.upgrade_supersede_older` matches whole, not `public.upgrade`.
	re := regexp.MustCompile(`\b(public|db)\.[a-z_]+`)
	unplaced := map[string]map[string]bool{} // identifier -> set of files

	scanned := 0
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		scanned++
		body, err := os.ReadFile(filepath.Join(pkgDir, name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		for _, id := range re.FindAllString(string(body), -1) {
			if inSet[id] {
				continue
			}
			if _, ok := namedFloorExclusions[id]; ok {
				continue
			}
			if unplaced[id] == nil {
				unplaced[id] = map[string]bool{}
			}
			unplaced[id][name] = true
		}
	}
	if scanned == 0 {
		t.Fatalf("no non-test .go scanned under %s — package-dir resolution is wrong", pkgDir)
	}
	if len(unplaced) > 0 {
		ids := make([]string, 0, len(unplaced))
		for id := range unplaced {
			ids = append(ids, id)
		}
		sort.Strings(ids)
		var b strings.Builder
		for _, id := range ids {
			files := make([]string, 0, len(unplaced[id]))
			for f := range unplaced[id] {
				files = append(files, f)
			}
			sort.Strings(files)
			fmt.Fprintf(&b, "\n  %s (in %s) — add it to migrate.DaemonRelationNames (if the daemon SQL-references it) or to namedFloorExclusions with its self-consistency reason",
				id, strings.Join(files, ", "))
		}
		t.Fatalf("STATBUS-145 floor completeness: %d schema-qualified identifier(s) in the daemon package are neither in the floor set nor named-excluded:%s", len(unplaced), b.String())
	}
}
