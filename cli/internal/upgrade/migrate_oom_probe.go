package upgrade

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// pgCrashSignal9 is the PostgreSQL-authored postmaster log line emitted when a
// server process is SIGKILLed — the kernel OOM-killer, or any external kill -9.
// PostgreSQL's actual line is `server process (PID N) was terminated by signal
// 9: Killed`; this substring matches it. Same authorship tier as the
// strerror(ENOSPC) discipline (STATBUS-046 doc-021): a version-pinned image's own
// constant, matched POSITIVELY only — absence is never evidence of the opposite.
// Unit tests pin this verbatim string.
const pgCrashSignal9 = "terminated by signal 9"

// dbContainerState is the STRUCTURED subset of `docker inspect .State` the OOM
// evidence probe reads. No text classification — numeric/boolean fields only.
type dbContainerState struct {
	Running   bool
	Dead      bool
	OOMKilled bool
	ExitCode  int
	StartedAt time.Time
}

// classifyMigrateOOMEvidence is the PURE, docker-free core (STATBUS-096 slice 3):
// given the db container's structured state, a db-log tail, the migration display
// name, and the migrate start time, it returns the NAMED-DATA suffix for the
// failure/park/rollback reason — or "" when there is no affirmative kill
// signature.
//
// PER-LEG, POSITIVE-MATCH-ONLY (architect's adversarial trace): the two evidence
// legs describe DIFFERENT physical kill shapes that rarely co-occur, so ANDing
// them would fire in almost no real case. Instead EACH leg affirms ONLY its own
// observed fact, and we NEVER claim more than the observed leg supports:
//   - OOMKilled=true → CAUSAL: the kernel OOM-killer set it, so "likely exceeds
//     this box's memory". (Combined with the log line when both are present.)
//   - the log crash constant alone → FACTUAL: a backend was SIGKILLed (a
//     postmaster-authored line), no memory claim (the postmaster survived to log
//     it — the OOM of a child, or an external kill).
//   - ExitCode 137 ALONE → FACTUAL only, NO cause: 137 can be an innocent
//     docker/compose grace-kill; the operator judges.
// The probe NEVER changes disposition — it only enriches the reason — so a
// leg-precise note is honest and a no-match ("") is simply the unchanged reason.
func classifyMigrateOOMEvidence(st dbContainerState, dbLogTail, displayName string, migrateStart time.Time) string {
	logSig := strings.Contains(dbLogTail, pgCrashSignal9)
	during := ""
	if !migrateStart.IsZero() && st.StartedAt.After(migrateStart) {
		during = " (the db restarted during the migration)"
	}
	switch {
	case st.OOMKilled && logSig:
		return fmt.Sprintf(" — the database was killed by the OS while migration %s ran — it likely exceeds this box's memory (docker reports the db container OOMKilled; the postmaster logged %q)%s",
			displayName, pgCrashSignal9, during)
	case st.OOMKilled:
		return fmt.Sprintf(" — the database was killed by the OS while migration %s ran: docker reports the db container OOMKilled — it likely exceeds this box's memory%s",
			displayName, during)
	case logSig:
		return fmt.Sprintf(" — during migration %s the postmaster reported a server process %q — a database backend was killed by the OS",
			displayName, pgCrashSignal9)
	case st.ExitCode == 137:
		return fmt.Sprintf(" — the db container exited 137 (SIGKILLed) during migration %s%s",
			displayName, during)
	default:
		return ""
	}
}

// probeMigrateOOMEvidence is the BEST-EFFORT wrapper: it inspects the db
// container's structured state and scans a bounded db-log tail, then calls the
// pure classifier. Every failure path (docker unavailable, container gone,
// unparseable output) returns "" — the probe's own failure NEVER changes the
// disposition (leniency). Bounded so it cannot stall the failure path.
func probeMigrateOOMEvidence(ctx context.Context, projDir, displayName string, migrateStart time.Time) string {
	pctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	st, ok := inspectDBContainerState(pctx, projDir)
	if !ok {
		return ""
	}
	return classifyMigrateOOMEvidence(st, dbLogTail(pctx, projDir, 200), displayName, migrateStart)
}

// inspectDBContainerState reads `docker inspect .State` for the db service's
// container (via `docker compose ps --all --quiet db` — --all so a stopped/killed
// container is still found). Returns ok=false on any docker/parse failure.
func inspectDBContainerState(ctx context.Context, projDir string) (dbContainerState, bool) {
	var st dbContainerState
	idCmd := exec.CommandContext(ctx, "docker", "compose", "ps", "--all", "--quiet", "db")
	idCmd.Dir = projDir
	idOut, err := idCmd.Output()
	if err != nil {
		return st, false
	}
	id := strings.TrimSpace(string(idOut))
	if i := strings.IndexByte(id, '\n'); i >= 0 {
		id = strings.TrimSpace(id[:i]) // first container if several
	}
	if id == "" {
		return st, false
	}
	inspCmd := exec.CommandContext(ctx, "docker", "inspect", "--format", "{{json .State}}", id)
	inspCmd.Dir = projDir
	inspOut, err := inspCmd.Output()
	if err != nil {
		return st, false
	}
	var raw struct {
		Running   bool   `json:"Running"`
		Dead      bool   `json:"Dead"`
		OOMKilled bool   `json:"OOMKilled"`
		ExitCode  int    `json:"ExitCode"`
		StartedAt string `json:"StartedAt"`
	}
	if err := json.Unmarshal(inspOut, &raw); err != nil {
		return st, false
	}
	st.Running, st.Dead, st.OOMKilled, st.ExitCode = raw.Running, raw.Dead, raw.OOMKilled, raw.ExitCode
	if t, perr := time.Parse(time.RFC3339Nano, raw.StartedAt); perr == nil {
		st.StartedAt = t
	}
	return st, true
}

// dbLogTail returns the last `lines` of the db service's docker logs, or "" on
// failure (the classifier then finds no log signature → leniency).
func dbLogTail(ctx context.Context, projDir string, lines int) string {
	cmd := exec.CommandContext(ctx, "docker", "compose", "logs",
		"--tail", fmt.Sprintf("%d", lines), "--no-color", "db")
	cmd.Dir = projDir
	out, err := cmd.CombinedOutput()
	if err != nil && len(out) == 0 {
		return ""
	}
	return string(out)
}
