package config

// RestartClass names WHAT must restart for a generated .env key's change to
// take effect (STATBUS-332). Declared AT THE KEY'S OWN GENERATION SITE — see
// envWriter below — never in a separate key→service table: a separate table
// restates knowledge the generator already has, and the two records drift
// silently, in the worst direction — a key gets added, the table entry is
// forgotten, and that key's changes never take effect while .env says they
// do (architect's ruling, 2026-08-31).
type RestartClass string

const (
	// RestartNone — this key changes nothing any running process reads at
	// startup; regenerating .env is the whole act. Also used for keys with
	// no verified runtime consumer at all (dead legacy .env.example
	// carryovers, or values read FRESH on every use rather than cached —
	// e.g. the upgrade daemon's callback/contact readers, which call
	// dotenv.Load(".env") themselves at the moment they're needed).
	RestartNone RestartClass = "none"
	// RestartProxyRestart — the Caddy container (compose service "proxy")
	// must restart. NAMED for the actual cost: a full `docker compose
	// restart proxy` (reusing cert.go's own precedent for cert rotation),
	// not a graceful reload — there is no signal-based reload mechanism in
	// this codebase tonight (architect's ruling, 2026-08-31). A graceful
	// reload is the better eventual form; landing it should rename this
	// constant, because the cost changes with it.
	RestartProxyRestart RestartClass = "proxy-restart"
	// RestartApp — the Next.js app container (compose service "app").
	RestartApp RestartClass = "app"
	// RestartWorker — the Crystal CLI worker container (compose service
	// "worker"). Its OWN class, never folded under "app": folding it either
	// over-restarts app for a worker-only change (losing the minimal-
	// restart property that justified detect-what-changed) or leaves a
	// worker-only key's change silently unapplied (this ticket's own
	// failure mode) — architect's ruling, 2026-08-31.
	RestartWorker RestartClass = "worker"
	// RestartRest — the PostgREST container (compose service "rest").
	RestartRest RestartClass = "rest"
	// RestartDB — the database container (compose service "db"). The
	// heaviest class: a full `docker compose restart db` drops every live
	// connection. Used for keys Postgres (or its start-postgres.sh
	// entrypoint / postgresql.conf templating) reads only at container
	// start — credentials, memory tuning, resource limits.
	RestartDB RestartClass = "db"
	// RestartUpgradeDaemon — the host-level systemd unit
	// (statbus-upgrade@<user>.service), NOT a docker compose service.
	// Reuses restartUpgradeService (cli/cmd/install_upgrade.go) —
	// best-effort, silent no-op off Linux or when the unit isn't active.
	// Used for keys Service.loadConfig()/loadTrustedSigners() cache once at
	// daemon startup.
	RestartUpgradeDaemon RestartClass = "upgrade-daemon"
)

// AllRestartClasses lists every class for human-readable rendering
// (completeness-test failure messages) ONLY — never consulted as an
// alternate source of truth for classification.
var AllRestartClasses = []RestartClass{
	RestartNone, RestartProxyRestart, RestartApp, RestartWorker, RestartRest, RestartDB, RestartUpgradeDaemon,
}

// envKeyClasses accumulates the restart-class declaration made at each
// key's own write site during one generateEnvContent call — the SET a key
// belongs to (STATBUS-332: several real keys are consumed by more than one
// service; DEBUG alone reaches app, worker, db, AND the Caddy template).
//
// This is NOT itself the "separate table" the ruling forbids: it is
// POPULATED by the same write calls that decide each key's VALUE (kv/setKV
// below), in the same function, in the same commit, by the same author who
// is already looking at that key's consumers to write its value correctly.
// A hand-authored, independently-maintained list would be the thing being
// avoided; this is that list's declarations captured as a side effect of
// the writes themselves.
type envKeyClasses struct {
	m map[string][]RestartClass
}

func newEnvKeyClasses() *envKeyClasses {
	return &envKeyClasses{m: map[string][]RestartClass{}}
}

func (c *envKeyClasses) declare(key string, classes ...RestartClass) {
	c.m[key] = classes
}

// declareIfAbsent is for the .env.example pass-through block only: it
// classifies every key that reaches the generated .env verbatim from
// .env.example WITHOUT ever being written by a setKV/declare call in Go
// (STATBUS-332's completeness test would otherwise fail on ~34 dead legacy
// Supabase-stack keys — Kong, Studio, Logflare, imgproxy, mailer, SMTP,
// pooler, GOTRUE anon/phone/JWT-expiry settings — verified by grep to have
// NO consumer in any of this repo's compose files, so RestartNone is not a
// default-by-omission, it is the classification of confirmed-dead carryover
// keys). It must NEVER win over an explicit declare() for a key this
// function's own code also writes a real value for (e.g. JWT_SECRET,
// POSTGRES_PASSWORD, memory-tuning keys are BOTH in .env.example AND set via
// setKV with their real class) — hence "if absent", not an overwrite.
//
// INVARIANT this file's own code must keep: RestartNone is passed ONLY
// here. Every OTHER "no restart needed" declaration — ADMINISTRATOR_CONTACT,
// UPGRADE_CALLBACK, STATBUS_URL, SERVICE_ROLE_KEY, DASHBOARD_USERNAME, ... —
// calls declare(key) with ZERO classes (an empty slice), never
// declare(key, RestartNone). TestBatchClassifiedKeysHaveZeroComposeConsumers
// (restart_class_test.go) uses "classes == [RestartNone]" as the exact,
// unambiguous signal that a key came through THIS function, to scope its
// zero-consumers claim to the batch alone — some empty-slice keys have a
// LIVE consumer that reads .env fresh at point-of-use rather than caching
// it, and that claim would be false for them. Keep this invariant true, or
// re-scope that test alongside whatever replaces it.
func (c *envKeyClasses) declareIfAbsent(key string, class RestartClass) {
	if _, exists := c.m[key]; exists {
		return
	}
	c.m[key] = []RestartClass{class}
}

// Classes returns the plain map, for callers outside this package (the
// install diff step) and for the completeness test.
func (c *envKeyClasses) Classes() map[string][]RestartClass {
	return c.m
}
