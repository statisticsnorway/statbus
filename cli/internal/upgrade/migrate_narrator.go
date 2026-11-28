package upgrade

import (
	"strings"
	"sync"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// migrateStillRunningInterval is how often the progress page hears about a
// migration or extension update that is still running, matching the backup
// step's "Still backing up database" cadence (exec.go).
const migrateStillRunningInterval = 30 * time.Second

// migrateNarratorTickInterval is how often the caller polls Tick; finer than
// migrateStillRunningInterval so the still-running line lands close to each
// 30 s mark of the step's own elapsed time.
const migrateNarratorTickInterval = 5 * time.Second

// migrateNarrator turns the `./sb migrate up` child's stdout into the main
// narration (M lines) the maintenance page shows. The child prints each step as
// a start line ending " ..." and a result line "... ok (<time>)" or
// "... failed after <time>" (migrate.go runUp, extensions.go); the narrator
// writes the start and the result as M lines and, while one step runs, an M
// still-running line every migrateStillRunningInterval. The O lines carry the
// full child output unchanged; this is the operator-facing summary of it.
type migrateNarrator struct {
	mu    sync.Mutex
	write func(format string, args ...interface{})
	now   func() time.Time

	running   string // display name of the running step, "" when idle
	startedAt time.Time
	nextStill time.Duration
}

func newMigrateNarrator(write func(format string, args ...interface{}), now func() time.Time) *migrateNarrator {
	return &migrateNarrator{write: write, now: now}
}

// PendingCount writes the start line of the whole migrate step.
func (n *migrateNarrator) PendingCount(count int) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.write("Applying database migrations: %d pending ...", count)
}

// Line consumes one child stdout line.
func (n *migrateNarrator) Line(line string) {
	line = strings.TrimSpace(line)
	if count, ok := migrate.ParsePendingCountReport(line); ok {
		n.PendingCount(count)
		return
	}
	n.mu.Lock()
	defer n.mu.Unlock()
	if rest, ok := strings.CutPrefix(line, "[migrate] Applying "); ok {
		file, result, done := splitStepResult(rest)
		if file == "" {
			return
		}
		if done {
			n.write("Applying migration %s ... %s", file, result)
			n.running = ""
			return
		}
		n.write("Applying migration %s ...", file)
		n.start(file)
		return
	}
	if rest, ok := strings.CutPrefix(line, "[migrate] Extension "); ok {
		name, _, _ := strings.Cut(rest, ":")
		if _, _, done := splitStepResult(rest); done {
			n.running = ""
		} else if strings.HasSuffix(rest, " ...") {
			n.start("extension " + name)
		}
		n.write("Extension %s", rest)
	}
}

// Tick writes a still-running line when the running step has passed its next
// 30 s mark. Silent when nothing runs.
func (n *migrateNarrator) Tick() {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.running == "" {
		return
	}
	elapsed := n.now().Sub(n.startedAt)
	if elapsed < n.nextStill {
		return
	}
	n.write("Still applying %s (%s) ...", n.running, elapsed.Truncate(time.Second))
	for n.nextStill <= elapsed {
		n.nextStill += migrateStillRunningInterval
	}
}

func (n *migrateNarrator) start(name string) {
	n.running = name
	n.startedAt = n.now()
	n.nextStill = migrateStillRunningInterval
}

// splitStepResult splits "<subject> ... ok (<t>)" / "<subject> ... failed after <t>"
// into subject and result. A bare start line "<subject> ..." returns done=false.
func splitStepResult(s string) (subject, result string, done bool) {
	if subj, res, found := strings.Cut(s, " ... "); found {
		if strings.HasPrefix(res, "ok") || strings.HasPrefix(res, "failed") {
			return subj, res, true
		}
	}
	return strings.TrimSuffix(s, " ..."), "", false
}

// runNarratorTicker calls n.Tick every migrateNarratorTickInterval until done
// closes.
func runNarratorTicker(n *migrateNarrator, done <-chan struct{}) {
	t := time.NewTicker(migrateNarratorTickInterval)
	defer t.Stop()
	for {
		select {
		case <-done:
			return
		case <-t.C:
			n.Tick()
		}
	}
}
