package release

import (
	"fmt"
	"strings"
)

// SkipCanaryEnvVar names the environment variable that suspends individual
// canary slots during `./sb release stable` preflight. Operators set this
// only when the canary is unavailable for legitimate reasons (slot down for
// maintenance, deploy mechanism broken, etc.) — the normal flow is to wait
// for the canary to deploy + complete, then cut stable.
//
// Format: comma-separated slot labels.
//
//	STATBUS_SKIP_CANARY=dev
//	STATBUS_SKIP_CANARY=dev,no
//
// Bypass is per-slot, not per-cut, so an operator must reapply it
// consciously for each affected slot.
const SkipCanaryEnvVar = "STATBUS_SKIP_CANARY"

// ParseSkipLabels parses the value of STATBUS_SKIP_CANARY (or any other
// label-list env var with the same shape).
//
// Empty/whitespace-only input returns an empty map and no error (no
// bypass requested — the standard case).
//
// Labels are lowercased + trimmed; duplicates collapse into the set.
// Empty entries between commas are silently ignored (a trailing comma is
// a tolerable typo). No validation against a known-labels list — that's
// the caller's job since the valid labels depend on the gate.
func ParseSkipLabels(envValue string) map[string]bool {
	out := make(map[string]bool)
	for _, part := range strings.Split(envValue, ",") {
		label := strings.ToLower(strings.TrimSpace(part))
		if label == "" {
			continue
		}
		out[label] = true
	}
	return out
}

// FormatSkipLabelsLog returns the per-label log line for an active skip,
// shared by every gate using STATBUS_SKIP_CANARY so the output stays
// uniform across slots and across gate types.
func FormatSkipLabelsLog(envVar, label string) string {
	return fmt.Sprintf("    ⟳ Skipping canary check for %s (%s)", label, envVar)
}
