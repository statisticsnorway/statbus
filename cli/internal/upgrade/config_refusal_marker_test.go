package upgrade

import (
	"testing"
	"time"
)

// STATBUS-298: the config-refusal marker is a REPORT of what the last start
// concluded, never a second record of intent — these tests pin the
// properties that make that true: absent by default, present after a
// refusal, gone after a clear, and round-trips the message verbatim.

func TestConfigRefusalMarker_AbsentByDefault(t *testing.T) {
	dir := t.TempDir()
	marker, err := ReadConfigRefusalMarker(dir)
	if err != nil {
		t.Fatalf("unexpected error reading an absent marker: %v", err)
	}
	if marker != nil {
		t.Errorf("expected nil marker on a fresh project dir, got %+v", marker)
	}
}

func TestConfigRefusalMarker_WriteThenRead(t *testing.T) {
	dir := t.TempDir()
	const msg = "UPGRADE_ROLE=production and UPGRADE_CHANNEL=prerelease are both declared in .env.config — remove UPGRADE_CHANNEL"
	before := time.Now().UTC()
	writeConfigRefusalMarker(dir, msg)
	after := time.Now().UTC()

	marker, err := ReadConfigRefusalMarker(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if marker == nil {
		t.Fatal("expected a marker after writeConfigRefusalMarker, got nil")
	}
	if marker.Message != msg {
		t.Errorf("Message = %q, want %q", marker.Message, msg)
	}
	if marker.RefusedAt.Before(before) || marker.RefusedAt.After(after) {
		t.Errorf("RefusedAt = %v, want between %v and %v", marker.RefusedAt, before, after)
	}
}

func TestConfigRefusalMarker_ClearRemovesIt(t *testing.T) {
	dir := t.TempDir()
	writeConfigRefusalMarker(dir, "some refusal")

	if marker, err := ReadConfigRefusalMarker(dir); err != nil || marker == nil {
		t.Fatalf("setup: expected a marker to be present before clearing, got marker=%v err=%v", marker, err)
	}

	ClearConfigRefusalMarker(dir)

	marker, err := ReadConfigRefusalMarker(dir)
	if err != nil {
		t.Fatalf("unexpected error after clear: %v", err)
	}
	if marker != nil {
		t.Errorf("expected nil marker after ClearConfigRefusalMarker, got %+v", marker)
	}
}

// TestConfigRefusalMarker_ClearOnAbsentIsSilent pins that clearing an
// already-absent marker (the common case: every OTHER successful start)
// is a silent no-op, not an error surfaced to the operator — the marker's
// job is only to report a refusal that happened, never to demand one.
func TestConfigRefusalMarker_ClearOnAbsentIsSilent(t *testing.T) {
	dir := t.TempDir()
	// No panic, no error return (the function is void) — this test's only
	// job is to confirm calling it on a project with no marker doesn't blow
	// up. os.IsNotExist inside ClearConfigRefusalMarker must absorb this.
	ClearConfigRefusalMarker(dir)

	marker, err := ReadConfigRefusalMarker(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if marker != nil {
		t.Errorf("expected nil marker, got %+v", marker)
	}
}

// TestConfigRefusalMarker_PathMirrorsFlagFilePattern confirms the marker
// lives under tmp/ alongside the existing upgrade-in-progress flag, per the
// architect's ruling ("alongside the existing tmp/upgrade-in-progress.json
// pattern") — not some new top-level location a future cleanup sweep might
// miss.
func TestConfigRefusalMarker_PathMirrorsFlagFilePattern(t *testing.T) {
	dir := "/some/project/dir"
	got := configRefusalMarkerPath(dir)
	want := dir + "/tmp/config-refused.json"
	if got != want {
		t.Errorf("configRefusalMarkerPath(%q) = %q, want %q", dir, got, want)
	}
}
