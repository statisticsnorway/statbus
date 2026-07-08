package upgrade

import (
	"strings"
	"testing"
	"time"
)

// STATBUS-096 slice 3 — the OS-kill (OOM) evidence probe's PURE classifier.
// Conjunctive + positive-match-only: named data is emitted ONLY when a structured
// kill signature AND the PostgreSQL crash constant both positively match; any
// under-match degrades to "" (leniency — the reason is unchanged, disposition
// never affected).

// TestPgCrashConstantVerbatim pins the version-pinned image's authored constant —
// a drift here silently blinds the probe.
func TestPgCrashConstantVerbatim(t *testing.T) {
	if pgCrashSignal9 != "terminated by signal 9" {
		t.Errorf("pgCrashSignal9 = %q, want %q (PostgreSQL-authored constant)", pgCrashSignal9, "terminated by signal 9")
	}
}

func TestClassifyMigrateOOMEvidence(t *testing.T) {
	const v = "v2026.07.0"
	logKill := "2026-07-08 ... LOG: server process (PID 42) was terminated by signal 9: Killed\n... terminating any other active server processes"
	logClean := "2026-07-08 ... LOG: database system is ready to accept connections"
	logSigterm := "2026-07-08 ... LOG: received fast shutdown request\n... server process ... was terminated by signal 15"

	cases := []struct {
		name string
		st   dbContainerState
		log  string
		// want: substrings that MUST be present; wantEmpty: expect "".
		want      []string
		notWant   []string
		wantEmpty bool
	}{
		{
			name: "OOMKilled + crash log → combined causal",
			st:   dbContainerState{OOMKilled: true, ExitCode: 137}, log: logKill,
			want: []string{"OOMKilled", "likely exceeds this box's memory", pgCrashSignal9, "migration " + v},
		},
		{
			name: "OOMKilled ALONE → causal (no log needed — the rare-cooccurrence case)",
			st:   dbContainerState{OOMKilled: true}, log: logClean,
			want:    []string{"OOMKilled", "likely exceeds this box's memory"},
			notWant: []string{pgCrashSignal9},
		},
		{
			name: "log constant ALONE → factual, NO memory claim (backend SIGKILL, postmaster survived)",
			st:   dbContainerState{ExitCode: 0}, log: logKill,
			want:    []string{pgCrashSignal9, "killed by the OS"},
			notWant: []string{"OOMKilled", "exceeds this box's memory"},
		},
		{
			name: "exit 137 ALONE → factual, NO cause (137 can be an innocent grace-kill)",
			st:   dbContainerState{ExitCode: 137}, log: logClean,
			want:    []string{"exited 137", "SIGKILLed"},
			notWant: []string{"OOMKilled", "exceeds this box's memory"},
		},
		{
			name: "SIGTERM (signal 15), no OOM, exit 143 → no affirmative leg → empty",
			st:   dbContainerState{ExitCode: 143}, log: logSigterm, wantEmpty: true,
		},
		{
			name: "graceful stop, clean log → empty",
			st:   dbContainerState{ExitCode: 0}, log: logClean, wantEmpty: true,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := classifyMigrateOOMEvidence(tc.st, tc.log, v, time.Time{})
			if tc.wantEmpty {
				if got != "" {
					t.Fatalf("expected empty, got: %q", got)
				}
				return
			}
			if got == "" {
				t.Fatalf("expected an affirmative note, got empty")
			}
			for _, w := range tc.want {
				if !strings.Contains(got, w) {
					t.Errorf("note missing %q in:\n%s", w, got)
				}
			}
			for _, nw := range tc.notWant {
				if strings.Contains(got, nw) {
					t.Errorf("note must NOT claim %q (leg-precise wording) in:\n%s", nw, got)
				}
			}
		})
	}
}

// TestClassifyMigrateOOM_RestartedDuringMigration pins the StartedAt-vs-migrate
// corroboration on the structured (137) leg: a db that (re)started AFTER the
// migrate began adds the "restarted during the migration" datum. Clean log so the
// 137 leg (not the log leg) is exercised.
func TestClassifyMigrateOOM_RestartedDuringMigration(t *testing.T) {
	migrateStart := time.Date(2026, 7, 8, 12, 0, 0, 0, time.UTC)
	after := migrateStart.Add(30 * time.Second)
	cleanLog := "LOG: database system is ready to accept connections"

	got := classifyMigrateOOMEvidence(dbContainerState{ExitCode: 137, StartedAt: after}, cleanLog, "v1", migrateStart)
	if !strings.Contains(got, "restarted during the migration") {
		t.Errorf("a StartedAt after the migrate start must add the restart datum; got: %s", got)
	}
	// A StartedAt BEFORE the migrate (the db is still down, never restarted) must
	// NOT claim a restart.
	before := migrateStart.Add(-time.Hour)
	got2 := classifyMigrateOOMEvidence(dbContainerState{ExitCode: 137, StartedAt: before}, cleanLog, "v1", migrateStart)
	if strings.Contains(got2, "restarted during the migration") {
		t.Errorf("a StartedAt before the migrate must NOT claim a restart; got: %s", got2)
	}
}
