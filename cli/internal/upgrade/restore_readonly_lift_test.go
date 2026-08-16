package upgrade

import (
	"strings"
	"testing"
)

// TestClearStaleReadOnlyWindow_ReattemptExclusion_STATBUS209 (ARM A): the ownership-gated
// backstop preserves the git-restore-fail ABORT hold — it must NOT clear the read-only window
// while a restore-reattemptable row (state='failed' with a retained backup_path) is pending,
// because that replay's own restore→lift owns the window. This exclusion is PINNED so a future
// cleanup can't strip it (the ABORT hold protects a broken volume until the human-gated replay).
// RED before ARM A (the old backstop guarded only no-flag + no-in_progress, so it would have
// cleared the hold).
func TestClearStaleReadOnlyWindow_ReattemptExclusion_STATBUS209(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) clearStaleReadOnlyWindow(")

	// The exclusion query + its early-return must PRECEDE the windowOff clear.
	exclIdx := strings.Index(body, "state = 'failed' AND backup_path IS NOT NULL")
	clearIdx := strings.Index(body, "terminalExec(windowOffSQL)")
	if exclIdx < 0 {
		t.Error("ARM A: clearStaleReadOnlyWindow must exclude a restore-reattemptable row (state='failed' AND backup_path IS NOT NULL) — the ABORT hold's protection is preserved until the replay's own lift")
	}
	if clearIdx < 0 || (exclIdx >= 0 && exclIdx > clearIdx) {
		t.Errorf("ARM A: the reattempt-pending exclusion must PRECEDE the windowOff clear (exclusion@%d, clear@%d)", exclIdx, clearIdx)
	}
	// The existing ownership guards remain (no flag, no in_progress) — defence-in-depth intact.
	for _, want := range []string{"ReadFlagFile(", "state = 'in_progress'", "pg_db_role_setting"} {
		if !strings.Contains(body, want) {
			t.Errorf("ARM A: clearStaleReadOnlyWindow lost its existing guard %q — the ownership gate must stay intact", want)
		}
	}

	// The exported ARM A entrypoint exists and delegates to the same backstop (so the install
	// ladder invokes ONE backstop, not a replica).
	wrapper := extractFuncBody(t, src, "func (d *Service) ClearStaleReadOnlyWindowIfUnowned(")
	if !strings.Contains(wrapper, "d.clearStaleReadOnlyWindow(ctx)") {
		t.Error("ARM A: ClearStaleReadOnlyWindowIfUnowned must delegate to clearStaleReadOnlyWindow — reuse the boot backstop, never replicate it")
	}
}
