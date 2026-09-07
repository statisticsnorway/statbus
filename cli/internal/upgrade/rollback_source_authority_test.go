package upgrade

import (
	"strings"
	"testing"
)

func TestRollbackSourceServicesStartAfterFloorWithTargetBinaryCanonical(t *testing.T) {
	source := readUpgradeServiceSource(t)
	body := extractFuncBody(t, source, "func (d *Service) restoreAndFinalize(")
	order := []struct {
		name string
		text string
	}{
		{"snapshot restore", "d.restoreRollbackSnapshotWithTargetAssets("},
		{"DB-only start", "d.startRollbackDatabaseOnly("},
		{"floor migrate", "d.reapplyRollbackDaemonSchemaFloor("},
		{"source checkout", "d.restoreGitState("},
		{"source config", "filepath.Join(projDir, \"sb.old\")"},
		{"source services", "\"rollback-docker-up\""},
		{"pending write", "rollback_finish_pending_at = now()"},
	}
	last := -1
	for _, step := range order {
		idx := strings.Index(body, step.text)
		if idx < 0 {
			t.Fatalf("restoreAndFinalize missing %s (%q)", step.name, step.text)
		}
		if idx <= last {
			t.Fatalf("%s is out of order: %d <= %d", step.name, idx, last)
		}
		last = idx
	}
}

func TestRollbackConfigGenerationUsesSourceBinaryExplicitly(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) restoreAndFinalize(")
	if !strings.Contains(body, "filepath.Join(projDir, \"sb.old\"), \"config\", \"generate\"") {
		t.Fatal("rollback config generation must explicitly use source-era sb.old")
	}
	floor := strings.Index(body, "d.reapplyRollbackDaemonSchemaFloor(")
	publish := strings.Index(body, "d.restoreBinary(")
	if publish >= 0 && publish < floor {
		t.Fatal("source binary must not be published before daemon floor replay")
	}
}
