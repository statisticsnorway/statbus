package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCheckUsersDone_ReconcilesOnlyWhenUsersYMLMatchesMarker(t *testing.T) {
	dir := t.TempDir()
	usersPath := filepath.Join(dir, ".users.yml")
	if err := os.WriteFile(usersPath, []byte("- email: one@example.com\n"), 0600); err != nil {
		t.Fatal(err)
	}

	if checkUsersDone(dir) {
		t.Fatal("checkUsersDone = true without a successful reconciliation marker; want false")
	}
	if err := recordUsersYMLHash(dir); err != nil {
		t.Fatalf("recordUsersYMLHash: %v", err)
	}
	if !checkUsersDone(dir) {
		t.Fatal("checkUsersDone = false for unchanged .users.yml and matching marker; want true")
	}

	if err := os.WriteFile(usersPath, []byte("- email: two@example.com\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if checkUsersDone(dir) {
		t.Fatal("checkUsersDone = true after .users.yml changed; want false so install reapplies users")
	}
}

func TestCheckUsersDone_AbsentUsersYMLIsNoOp(t *testing.T) {
	if !checkUsersDone(t.TempDir()) {
		t.Fatal("checkUsersDone = false when .users.yml is absent; want true no-op")
	}
}

func TestRunCreateUsers_RecordsMarkerOnlyAfterSuccessfulUpsert(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".users.yml"), []byte("users: configured\n"), 0600); err != nil {
		t.Fatal(err)
	}

	original := runUsersCreateCommand
	t.Cleanup(func() { runUsersCreateCommand = original })
	var calls int
	runUsersCreateCommand = func(gotDir string) error {
		calls++
		if gotDir != dir {
			t.Fatalf("runUsersCreateCommand dir = %q, want %q", gotDir, dir)
		}
		return nil
	}

	if err := runCreateUsers(dir); err != nil {
		t.Fatalf("runCreateUsers: %v", err)
	}
	if calls != 1 {
		t.Fatalf("runUsersCreateCommand calls = %d, want 1", calls)
	}
	if !checkUsersDone(dir) {
		t.Fatal("checkUsersDone = false after successful users create and marker write; want true")
	}

	if err := os.Remove(filepath.Join(dir, usersYMLHashFile)); err != nil {
		t.Fatal(err)
	}
	runUsersCreateCommand = func(string) error { return os.ErrPermission }
	if err := runCreateUsers(dir); err == nil {
		t.Fatal("runCreateUsers succeeded after users command failure; want error")
	}
	if checkUsersDone(dir) {
		t.Fatal("checkUsersDone = true after users command failure without a marker; want false so install retries")
	}
}
