package migrate

import "testing"

func TestCountPendingAtOrBelow(t *testing.T) {
	const floor int64 = 100
	migrations := []*MigrationFile{
		{Version: 50}, {Version: 100}, {Version: 150},
	}

	tests := []struct {
		name    string
		applied map[int64]bool
		want    int
	}{
		{name: "below and at floor count", applied: map[int64]bool{}, want: 2},
		{name: "version equal to floor counts", applied: map[int64]bool{50: true}, want: 1},
		{name: "version above floor does not count", applied: map[int64]bool{50: true, 100: true}, want: 0},
		{name: "applied versions do not count", applied: map[int64]bool{50: true, 100: true, 150: true}, want: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := countPendingAtOrBelow(migrations, tt.applied, floor); got != tt.want {
				t.Fatalf("countPendingAtOrBelow() = %d, want %d", got, tt.want)
			}
		})
	}
}
