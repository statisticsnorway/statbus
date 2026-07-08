package migrate

import "testing"

// STATBUS-145 slice 2 — countPendingAbove is the floor arithmetic for the
// flagless boot's loud line: how many migrations sit ABOVE the daemon floor and
// are unapplied (the real upgrade delta, deferred to the guarded pipeline).
func TestCountPendingAbove(t *testing.T) {
	const floor int64 = 100
	migs := []*MigrationFile{
		{Version: 50}, {Version: 100}, {Version: 150}, {Version: 200}, {Version: 250},
	}
	cases := []struct {
		name    string
		applied map[int64]bool
		want    int
	}{
		{"nothing applied → only the 3 above the floor count", map[int64]bool{}, 3},
		{"delta fully applied → floor no-op path (0)", map[int64]bool{150: true, 200: true, 250: true}, 0},
		{"below-floor unapplied does NOT count", map[int64]bool{50: false, 150: true, 200: true, 250: true}, 0},
		{"at-floor version is not 'above' (strict >)", map[int64]bool{100: false, 150: true, 200: true, 250: true}, 0},
		{"partial delta applied → remaining above-floor count", map[int64]bool{150: true}, 2},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := countPendingAbove(migs, tc.applied, floor); got != tc.want {
				t.Errorf("countPendingAbove = %d, want %d", got, tc.want)
			}
		})
	}
}

// TestHasPendingAboveAtFloorHead pins the ship-safe property: with the floor at
// the newest migration (today's reality), nothing is above it, so a flagless boot
// defers no delta and the loud line never fires — boot-to-floor == boot-to-HEAD.
func TestCountPendingAbove_FloorAtHead(t *testing.T) {
	migs := []*MigrationFile{{Version: 1}, {Version: 2}, {Version: DaemonSchemaFloor}}
	if got := countPendingAbove(migs, map[int64]bool{}, DaemonSchemaFloor); got != 0 {
		t.Errorf("with the floor at HEAD, nothing is above it; countPendingAbove = %d, want 0", got)
	}
}
