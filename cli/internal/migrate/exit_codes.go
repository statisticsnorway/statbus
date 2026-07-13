package migrate

import (
	"errors"
	"os/exec"
)

// STATBUS-046 slice 2 (architect Q5) — the `sb migrate up` FAILURE-CLASS EXIT-CODE
// CONTRACT. This is the SHARED surface between the producer (`sb migrate up`,
// which maps psql's documented exit semantics to these codes) and the consumer
// (upgrade.applyNewSbUpgrading, which reads ONLY the exit code via
// exec.ExitError.ExitCode() — never the stderr text — to classify a Phase-3
// migrate failure as A/B/C). Text-as-DATA (a stderr tail in the park reason) is
// fine; text-as-CLASSIFIER is the doc-022-banned thing this contract removes.
//
// Mechanism (architect-verified): `migrate up` shells psql per file with
// ON_ERROR_STOP=on, so it holds no PgError — instead it reads psql's DOCUMENTED
// exit codes (https://www.postgresql.org/docs/current/app-psql.html §Exit Status):
//
//	psql exit 1 = psql's own fatal error        → migrate ExitUnclassified (1)
//	psql exit 2 = connection lost / not opened   → migrate ExitUnclassified (1) [transient/A]
//	psql exit 3 = script error (ON_ERROR_STOP)   → migrate ExitDeterministic (20) [B]
//
// and, for the resource case, the SQLSTATE class 53 (insufficient_resources,
// e.g. 53100 disk full) read from psql's documented VERBOSITY=verbose SQLSTATE
// field → migrate ExitResource (22) [C].
//
// Contract:
//
//	0  = success
//	1  = UNCLASSIFIED — every unmapped failure; the honest fallback → unknown → A
//	     (death-budget + same-step-twice bounded). Cobra's default exit for a
//	     non-nil RunE error is also 1, so an unhandled error degrades safely here.
//	20 = DETERMINISTIC — a migration's SQL failed (psql exit 3) → B, park-on-first.
//	22 = RESOURCE — SQLSTATE class 53 (insufficient_resources) → C, park-on-first.
//
// The two consumers eventually: this same contract is the substrate the deferred
// STATBUS-109 forward-step classifier was waiting for — one mechanism.
const (
	ExitSuccess       = 0
	ExitUnclassified  = 1
	ExitDeterministic = 20
	ExitResource      = 22
)

// ClassifyUpErr maps an error returned by migrate.Up (the "sb migrate up"
// entry point) to the process-exit-code contract above. runUp wraps
// runPsqlFile's raw *exec.ExitError with fmt.Errorf's %w, so errors.As sees
// through that wrap to psql's own exit code — the DOCUMENTED signal
// (postgresql.org app-psql §Exit Status): exit 3 under ON_ERROR_STOP means a
// migration's SQL failed deterministically.
//
// Every other case degrades to the honest ExitUnclassified fallback: nil
// (success — callers should not reach here on the nil path, but it's handled
// for completeness), a non-ExitError failure (migration file wouldn't open,
// advisory-lock acquisition failed, content-hash immutability violation,
// etc.), or any other psql exit code (1 = psql's own fatal error, 2 =
// connection lost/not opened — both transient/A, not a structural SQL
// failure).
//
// TODO(STATBUS-046 22): RESOURCE (SQLSTATE class 53, e.g. 53100 disk full)
// needs psql's documented VERBOSITY=verbose SQLSTATE field, read inside the
// psql-invoking component (runPsqlFile) — not derivable from the exit code
// alone, so it can't live in this pure classifier as-is. Deferred: the
// architect ruled exit-3→20 alone is acceptable for slice 2 (B and C both
// park-on-first; only the operator-facing wording differs).
func ClassifyUpErr(err error) int {
	if err == nil {
		return ExitSuccess
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) && exitErr.ExitCode() == 3 {
		return ExitDeterministic
	}
	return ExitUnclassified
}
