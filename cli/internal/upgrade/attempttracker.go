package upgrade

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// AttemptRecord tracks attempts for a single decision.
type AttemptRecord struct {
	Decision    string    `json:"decision"`
	Attempts    int       `json:"attempts"`
	LastTS      time.Time `json:"last_ts"`
	LastOutcome string    `json:"last_outcome"`
	LastDetail  string    `json:"last_detail"`
}

// AttemptTracker records per-decision attempt counts in tmp/attempt-tracker/.
// On N consecutive same-outcome failures, signals the caller to abandon.
type AttemptTracker struct {
	projDir string
	max     int // default 3
}

// NewAttemptTracker creates a tracker in projDir/tmp/attempt-tracker/.
func NewAttemptTracker(projDir string, max int) *AttemptTracker {
	if max <= 0 {
		max = 3
	}
	return &AttemptTracker{projDir: projDir, max: max}
}

// recordFilePath returns the path to the state file for a decision.
func (t *AttemptTracker) recordFilePath(decision string) string {
	// Sanitize decision for filename: replace / and : with -
	slug := strings.ReplaceAll(strings.ReplaceAll(decision, "/", "-"), ":", "-")
	return filepath.Join(t.projDir, "tmp", "attempt-tracker", slug+".json")
}

// Record increments the attempt count for a decision. If the outcome matches
// the last recorded outcome and we've hit max consecutive attempts, returns
// (shouldAbandon=true, attempts). Otherwise returns (false, newCount).
func (t *AttemptTracker) Record(decision, outcome, detail string) (shouldAbandon bool, attempts int) {
	recPath := t.recordFilePath(decision)

	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(recPath), 0755); err != nil {
		// Silent fail on mkdir — don't let attempt tracking crash the upgrade
		return false, 1
	}

	// Load current record if it exists
	var rec AttemptRecord
	data, err := os.ReadFile(recPath)
	if err == nil {
		_ = json.Unmarshal(data, &rec)
	}

	// If outcome differs, reset counter
	if rec.LastOutcome != outcome {
		rec = AttemptRecord{
			Decision:    decision,
			Attempts:    1,
			LastTS:      time.Now(),
			LastOutcome: outcome,
			LastDetail:  detail,
		}
	} else {
		// Same outcome: increment
		rec.Attempts++
		rec.LastTS = time.Now()
		rec.LastDetail = detail
	}

	// Write back to disk
	if b, err := json.MarshalIndent(&rec, "", "  "); err == nil {
		_ = os.WriteFile(recPath, b, 0644)
	}

	// Check if we've hit the limit
	if rec.Attempts >= t.max {
		return true, rec.Attempts
	}
	return false, rec.Attempts
}

// Clear resets the attempt counter for a decision (call on success).
func (t *AttemptTracker) Clear(decision string) {
	recPath := t.recordFilePath(decision)
	_ = os.Remove(recPath)
}
