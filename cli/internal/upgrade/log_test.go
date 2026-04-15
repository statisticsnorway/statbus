package upgrade

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

// TestLogUpgradeRow_EmitsRawJSON verifies that logUpgradeRow prints raw JSON
// (starts with '{', contains '"state":') and does NOT double-quote it via %q.
func TestLogUpgradeRow_EmitsRawJSON(t *testing.T) {
	// Capture stdout
	orig := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = w

	logUpgradeRow("test-label", `{"id":42,"state":"completed"}`)

	w.Close()
	os.Stdout = orig

	var buf bytes.Buffer
	buf.ReadFrom(r)
	output := buf.String()

	// Must contain raw JSON opening brace — not an escaped \"{
	if !strings.Contains(output, `{"id":`) {
		t.Errorf("expected raw JSON opening brace, got: %q", output)
	}
	// Must not contain the escaped form produced by %%q
	if strings.Contains(output, `\"{`) {
		t.Errorf("output contains %%q-style double-escaping; expected %%s: %q", output)
	}
	// Must contain the label in the expected bracket format
	if !strings.Contains(output, "[test-label]") {
		t.Errorf("expected label in output, got: %q", output)
	}
}
