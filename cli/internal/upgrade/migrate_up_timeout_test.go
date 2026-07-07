package upgrade

import (
	"testing"
	"time"
)

// STATBUS-095 AC#2 — the migrate ceiling is env-overridable to a short value so
// the ceiling arc triggers the same real kill path in seconds instead of waiting
// 12 hours. resolveMigrateUpTimeout reads STATBUS_MIGRATE_UP_TIMEOUT (a Go
// duration), defaults to 12h when unset/unparseable, and floor-guards a
// too-small override so a fat-finger can't fire the ceiling mid-migration.
func TestResolveMigrateUpTimeout(t *testing.T) {
	for _, tc := range []struct {
		name string
		set  bool // whether to set the env var at all
		env  string
		want time.Duration
	}{
		{"unset → 12h default", false, "", migrateUpTimeoutDefault},
		{"empty → 12h default", true, "", migrateUpTimeoutDefault},
		{"20s → 20s (the arc's short ceiling)", true, "20s", 20 * time.Second},
		{"6h → 6h (a raised-but-under-12h override)", true, "6h", 6 * time.Hour},
		{"12h explicit → 12h", true, "12h", 12 * time.Hour},
		{"exactly the floor (5s) → 5s", true, "5s", migrateUpTimeoutFloor},
		{"below floor (1s) → clamped to floor", true, "1s", migrateUpTimeoutFloor},
		{"zero → clamped to floor", true, "0s", migrateUpTimeoutFloor},
		{"unparseable → 12h default", true, "not-a-duration", migrateUpTimeoutDefault},
		{"bare number (no unit) → 12h default", true, "300", migrateUpTimeoutDefault},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if tc.set {
				t.Setenv("STATBUS_MIGRATE_UP_TIMEOUT", tc.env)
			} else {
				// Guarantee the var is absent even if the ambient env has it.
				t.Setenv("STATBUS_MIGRATE_UP_TIMEOUT", "")
			}
			if got := resolveMigrateUpTimeout(); got != tc.want {
				t.Errorf("resolveMigrateUpTimeout() with env=%q = %s, want %s", tc.env, got, tc.want)
			}
		})
	}
}

// TestMigrateUpTimeoutDefaultIsTwelveHours pins the STATBUS-095 King requirement:
// the ceiling default is 12 hours (the raise from the prior 30m — AC#4's
// reconciliation item). A drift here silently shortens every upgrade-path
// migration's allowance.
func TestMigrateUpTimeoutDefaultIsTwelveHours(t *testing.T) {
	if migrateUpTimeoutDefault != 12*time.Hour {
		t.Errorf("migrateUpTimeoutDefault = %s, want 12h (STATBUS-095 King requirement)", migrateUpTimeoutDefault)
	}
}
