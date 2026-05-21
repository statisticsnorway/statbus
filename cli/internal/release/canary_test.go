package release

import (
	"strings"
	"testing"
)

func TestParseSkipLabels_Empty(t *testing.T) {
	cases := []string{"", "   ", "\t\n", ",", "  ,  ,  "}
	for _, in := range cases {
		got := ParseSkipLabels(in)
		if len(got) != 0 {
			t.Errorf("input %q: expected empty map, got %v", in, got)
		}
	}
}

func TestParseSkipLabels_Single(t *testing.T) {
	got := ParseSkipLabels("dev")
	if len(got) != 1 || !got["dev"] {
		t.Errorf("expected {dev:true}, got %v", got)
	}
}

func TestParseSkipLabels_Multi(t *testing.T) {
	got := ParseSkipLabels("dev,no")
	if len(got) != 2 || !got["dev"] || !got["no"] {
		t.Errorf("expected {dev,no}, got %v", got)
	}
}

func TestParseSkipLabels_Whitespace(t *testing.T) {
	got := ParseSkipLabels("  dev  ,  no  ")
	if !got["dev"] || !got["no"] {
		t.Errorf("whitespace not trimmed: got %v", got)
	}
}

func TestParseSkipLabels_LowercaseNormalised(t *testing.T) {
	got := ParseSkipLabels("DEV,No")
	if !got["dev"] || !got["no"] {
		t.Errorf("expected case normalization to lowercase; got %v", got)
	}
	if got["DEV"] || got["No"] {
		t.Errorf("uppercase keys leaked into map: %v", got)
	}
}

func TestParseSkipLabels_Duplicates(t *testing.T) {
	got := ParseSkipLabels("dev,dev,DEV")
	if len(got) != 1 || !got["dev"] {
		t.Errorf("expected single entry after dedupe, got %v", got)
	}
}

func TestParseSkipLabels_TrailingComma(t *testing.T) {
	got := ParseSkipLabels("dev,no,")
	if !got["dev"] || !got["no"] {
		t.Errorf("trailing comma broke parse: got %v", got)
	}
	if got[""] {
		t.Errorf("empty label leaked into map: %v", got)
	}
}

func TestSkipCanaryEnvVar_Constant(t *testing.T) {
	want := "STATBUS_SKIP_CANARY"
	if SkipCanaryEnvVar != want {
		t.Errorf("SkipCanaryEnvVar = %q, want %q", SkipCanaryEnvVar, want)
	}
}

func TestFormatSkipLabelsLog(t *testing.T) {
	got := FormatSkipLabelsLog(SkipCanaryEnvVar, "dev")
	if !strings.Contains(got, "dev") {
		t.Errorf("label missing from log line: %q", got)
	}
	if !strings.Contains(got, SkipCanaryEnvVar) {
		t.Errorf("env-var name missing from log line: %q", got)
	}
	if !strings.HasPrefix(got, "    ") {
		t.Errorf("expected indented (4-space) output, got %q", got)
	}
}
