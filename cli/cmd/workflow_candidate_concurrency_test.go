package cmd

import (
	"strings"
	"testing"
)

// STATBUS-415: candidate A must not share the cancel group with later master B.
func TestFastTestsCandidateConcurrency_STATBUS415(t *testing.T) {
	body := readWorkflowFile(t, "fast-tests.yaml")
	for _, want := range []string{
		"tags: ['v*-rc.*']",
		"git tag --points-at \"$EXERCISED_SHA\"",
		"-rc\\.[0-9]+$",
		"needs: classify",
		"needs.classify.outputs.candidate == 'true'",
		"format('fast-tests-rc-{0}', github.event_name == 'workflow_run' && github.event.workflow_run.head_sha || github.sha)",
		"'fast-tests-master'",
		"format('fast-tests-{0}', github.ref)",
		"cancel-in-progress: true",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("Fast Tests missing candidate/master concurrency contract %q", want)
		}
	}
	if strings.Contains(body, "\nconcurrency:") {
		t.Error("workflow-level concurrency cancels candidates before tag classification")
	}
}
