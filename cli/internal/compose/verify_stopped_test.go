package compose

import (
	"errors"
	"strings"
	"testing"
	"time"
)

// TestNotStoppedFrom_Classification is STATBUS-187's fail-closed allow-list
// table: a service passes only when absent from ps output or in state
// exited/created/dead. Any other state — including ones docker doesn't
// document today — fails, named with its observed state.
func TestNotStoppedFrom_Classification(t *testing.T) {
	cases := []struct {
		name     string
		statuses []PsEntry
		services []string
		want     []string
	}{
		{
			name:     "running_fails",
			statuses: []PsEntry{{Service: "db", State: "running"}},
			services: []string{"db"},
			want:     []string{"db (running)"},
		},
		{
			name:     "restarting_fails",
			statuses: []PsEntry{{Service: "db", State: "restarting"}},
			services: []string{"db"},
			want:     []string{"db (restarting)"},
		},
		{
			name:     "paused_fails",
			statuses: []PsEntry{{Service: "db", State: "paused"}},
			services: []string{"db"},
			want:     []string{"db (paused)"},
		},
		{
			name:     "unknown_future_state_fails",
			statuses: []PsEntry{{Service: "db", State: "some-new-docker-state"}},
			services: []string{"db"},
			want:     []string{"db (some-new-docker-state)"},
		},
		{
			name:     "exited_passes",
			statuses: []PsEntry{{Service: "db", State: "exited"}},
			services: []string{"db"},
			want:     nil,
		},
		{
			name:     "created_passes",
			statuses: []PsEntry{{Service: "db", State: "created"}},
			services: []string{"db"},
			want:     nil,
		},
		{
			name:     "dead_passes",
			statuses: []PsEntry{{Service: "db", State: "dead"}},
			services: []string{"db"},
			want:     nil,
		},
		{
			name:     "absent_from_ps_output_passes",
			statuses: nil,
			services: []string{"db"},
			want:     nil,
		},
		{
			name: "multiple_services_only_stragglers_named",
			statuses: []PsEntry{
				{Service: "app", State: "exited"},
				{Service: "worker", State: "restarting"},
				{Service: "rest", State: "exited"},
				{Service: "db", State: "running"},
			},
			services: []string{"app", "worker", "rest", "db"},
			want:     []string{"worker (restarting)", "db (running)"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := notStoppedFrom(tc.statuses, tc.services)
			if len(got) != len(tc.want) {
				t.Fatalf("notStoppedFrom() = %v, want %v", got, tc.want)
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Errorf("notStoppedFrom()[%d] = %q, want %q", i, got[i], tc.want[i])
				}
			}
		})
	}
}

// TestNotStoppedFrom_ViaParsePsJSON exercises the classification through
// the real parsing layer — raw `docker compose ps -a --format json` NDJSON
// fixtures, as docker actually emits them — rather than hand-built PsEntry
// structs, so the parse-then-classify pipeline is covered end to end
// without needing a real docker daemon.
func TestNotStoppedFrom_ViaParsePsJSON(t *testing.T) {
	cases := []struct {
		name string
		json string
		want []string
	}{
		{
			name: "all_stopped_passes",
			json: strings.Join([]string{
				`{"Service":"app","State":"exited","Image":"x"}`,
				`{"Service":"worker","State":"created","Image":"x"}`,
				`{"Service":"rest","State":"dead","Image":"x"}`,
			}, "\n"),
			want: nil,
		},
		{
			name: "restarting_and_paused_fail_named",
			json: strings.Join([]string{
				`{"Service":"app","State":"exited","Image":"x"}`,
				`{"Service":"worker","State":"restarting","Image":"x"}`,
				`{"Service":"db","State":"paused","Image":"x"}`,
			}, "\n"),
			want: []string{"worker (restarting)", "db (paused)"},
		},
		{
			name: "removing_state_fails",
			json: `{"Service":"db","State":"removing","Image":"x"}`,
			want: []string{"db (removing)"},
		},
	}
	services := []string{"app", "worker", "rest", "db"}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			statuses, err := ParsePsJSON([]byte(tc.json))
			if err != nil {
				t.Fatalf("ParsePsJSON: %v", err)
			}
			got := notStoppedFrom(statuses, services)
			if len(got) != len(tc.want) {
				t.Fatalf("notStoppedFrom() = %v, want %v", got, tc.want)
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Errorf("notStoppedFrom()[%d] = %q, want %q", i, got[i], tc.want[i])
				}
			}
		})
	}
}

// TestVerifyStopped_StragglerClearsWithinBudget: a service reported running
// on the first probe and exited on the second must pass — the bounded
// re-check exists precisely to ride out a SIGTERM grace period like this.
func TestVerifyStopped_StragglerClearsWithinBudget(t *testing.T) {
	calls := 0
	probe := func() ([]PsEntry, error) {
		calls++
		if calls == 1 {
			return []PsEntry{{Service: "db", State: "running"}}, nil
		}
		return []PsEntry{{Service: "db", State: "exited"}}, nil
	}
	err := verifyStopped(probe, []string{"db"}, time.Second, time.Millisecond)
	if err != nil {
		t.Fatalf("verifyStopped() = %v, want nil (straggler should clear within budget)", err)
	}
	if calls < 2 {
		t.Errorf("probe called %d times, want at least 2 (must re-check, not trust the first snapshot)", calls)
	}
}

// TestVerifyStopped_BudgetExhausted: a service that never clears must fail
// once budget is exhausted, naming the service and its observed state —
// never poll unboundedly.
func TestVerifyStopped_BudgetExhausted(t *testing.T) {
	probe := func() ([]PsEntry, error) {
		return []PsEntry{{Service: "db", State: "restarting"}}, nil
	}
	start := time.Now()
	err := verifyStopped(probe, []string{"db"}, 20*time.Millisecond, 5*time.Millisecond)
	elapsed := time.Since(start)
	if err == nil {
		t.Fatal("verifyStopped() = nil, want an error (service never clears)")
	}
	if !strings.Contains(err.Error(), "db (restarting)") {
		t.Errorf("error %q does not name the straggler and its state", err.Error())
	}
	if elapsed > time.Second {
		t.Errorf("verifyStopped took %v, want it to give up promptly at budget exhaustion", elapsed)
	}
}

// TestVerifyStopped_ProbeError: a docker/parse error from the probe must
// propagate immediately, not be retried into a misleading "still running"
// message.
func TestVerifyStopped_ProbeError(t *testing.T) {
	wantErr := errors.New("docker daemon down")
	probe := func() ([]PsEntry, error) { return nil, wantErr }
	err := verifyStopped(probe, []string{"db"}, time.Second, time.Millisecond)
	if err == nil || !errors.Is(err, wantErr) {
		t.Fatalf("verifyStopped() = %v, want wrapped %v", err, wantErr)
	}
}
