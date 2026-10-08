package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/installinput"
)

// STATBUS-464 user provisioning, one test per case of the ticket's matrix.
// Each test isolates HOME (the operator-home location) and replaces the
// database seams with an in-memory account table, so the observable result
// (what was announced, what was created, what was refused) is asserted.

const usersFixtureContent = "- display_name: Fixture Admin\n  email: fixture-admin@example.org\n  password: fixture-secret-1\n  role: admin_user\n"

const twoUsersContent = "# operator file\n- display_name: Ada Admin\n  email: ada@example.org\n  password: ada-secret\n  role: admin_user\n- display_name: Reg User\n  email: reg@example.org\n  password: reg-secret\n"

func usersFixture(t *testing.T, dir string) string {
	t.Helper()
	path := filepath.Join(dir, "users.yml")
	if err := os.WriteFile(path, []byte(usersFixtureContent), 0600); err != nil {
		t.Fatal(err)
	}
	return path
}

type fakeAccounts struct {
	emails  map[string]bool
	created []userEntry
}

// provisioningFixture: isolated HOME and project dir, an empty account table,
// interactive-or-not chosen per test, and no STATBUS_USERS_FILE.
func provisioningFixture(t *testing.T, interactive bool) (home, dir string, accounts *fakeAccounts) {
	t.Helper()
	home = t.TempDir()
	dir = t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv(installinput.UsersFile, "")
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", "curl -fsSL https://statbus.org/install.sh | bash")
	accounts = &fakeAccounts{emails: map[string]bool{}}
	oldCount, oldExisting, oldCreate := countInstallUsers, existingInstallUserEmails, createInstallUsers
	oldNonInteractive, oldTerminal := nonInteractive, stdinIsTerminal
	t.Cleanup(func() {
		countInstallUsers, existingInstallUserEmails, createInstallUsers = oldCount, oldExisting, oldCreate
		nonInteractive, stdinIsTerminal = oldNonInteractive, oldTerminal
	})
	countInstallUsers = func(string) (int, error) { return len(accounts.emails), nil }
	existingInstallUserEmails = func(_ string, emails []string) (map[string]bool, error) {
		found := map[string]bool{}
		for _, e := range emails {
			if accounts.emails[strings.ToLower(e)] {
				found[strings.ToLower(e)] = true
			}
		}
		return found, nil
	}
	createInstallUsers = func(_ string, users []userEntry) error {
		for _, u := range users {
			accounts.emails[strings.ToLower(u.email)] = true
			accounts.created = append(accounts.created, u)
		}
		return nil
	}
	nonInteractive = !interactive
	stdinIsTerminal = func() bool { return interactive }
	return home, dir, accounts
}

func writeUsersFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

// Case 1: explicit readable file, unattended. Used, copied, announced with
// its path and count; never prompts.
func TestUsersCase1ExplicitFileIsUsedAndReported(t *testing.T) {
	_, dir, accounts := provisioningFixture(t, false)
	explicit := filepath.Join(t.TempDir(), "my-users.yml")
	writeUsersFile(t, explicit, twoUsersContent)
	t.Setenv(installinput.UsersFile, explicit)

	if err := validateUsersInput(dir); err != nil {
		t.Fatalf("preflight refused a valid explicit file: %v", err)
	}
	var err error
	out := captureStdout(t, func() { err = runCreateUsers(dir) })
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"  Using STATBUS_USERS_FILE " + explicit + " with 2 users.",
		"  Created 2 users from " + explicit + "; 0 already existed and were left unchanged.",
	} {
		if !strings.Contains(out, want+"\n") {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, "Email") || strings.Contains(out, "first administrator") {
		t.Errorf("explicit file still prompted:\n%s", out)
	}
	if strings.Contains(out, "ada-secret") {
		t.Fatalf("password printed:\n%s", out)
	}
	copied, err := os.ReadFile(filepath.Join(dir, ".users.yml"))
	if err != nil || string(copied) != twoUsersContent {
		t.Fatalf("explicit file not copied into the project: %q %v", copied, err)
	}
	if st, _ := os.Stat(filepath.Join(dir, ".users.yml")); st.Mode().Perm() != 0600 {
		t.Fatalf(".users.yml mode %v", st.Mode())
	}
	if len(accounts.created) != 2 {
		t.Fatalf("created %d users, want 2", len(accounts.created))
	}
	if !checkUsersDone(dir) {
		t.Fatal("step not done after creating every explicit user")
	}
}

// Case 2: explicit path missing, unreadable or empty is a hard error naming
// the path, never a fall-through to the prompt.
func TestUsersCase2ExplicitFileProblemsAreHardErrors(t *testing.T) {
	_, dir, _ := provisioningFixture(t, true) // interactive: a prompt WOULD be possible
	missing := filepath.Join(t.TempDir(), "absent.yml")
	empty := filepath.Join(t.TempDir(), "empty.yml")
	writeUsersFile(t, empty, "# nothing here\n")
	incomplete := filepath.Join(t.TempDir(), "incomplete.yml")
	writeUsersFile(t, incomplete, "- email: x@example.org\n")
	for name, tc := range map[string]struct{ path, want string }{
		"missing":    {missing, "STATBUS_USERS_FILE " + missing + " cannot be read."},
		"empty":      {empty, "the users file " + empty + " cannot be used: it lists no users."},
		"incomplete": {incomplete, "the users file " + incomplete + " cannot be used: an entry is missing email, display_name or password."},
	} {
		t.Run(name, func(t *testing.T) {
			t.Setenv(installinput.UsersFile, tc.path)
			err := validateUsersInput(dir)
			if err == nil || !strings.HasPrefix(err.Error(), tc.want) {
				t.Fatalf("got %v, want prefix %q", err, tc.want)
			}
			var runErr error
			out := captureStdout(t, func() { runErr = runCreateUsers(dir) })
			if runErr == nil || strings.Contains(out, "Email") {
				t.Fatalf("step fell back to the prompt: err=%v out=%s", runErr, out)
			}
		})
	}
}

// Case 3: the field case. No explicit path, a file at ~/statbus.users.yml:
// detected, announced, copied in and used, unattended included.
func TestUsersCase3DetectedHomeFileIsAnnouncedAndUsed(t *testing.T) {
	home, dir, accounts := provisioningFixture(t, false)
	homeFile := filepath.Join(home, "statbus.users.yml")
	writeUsersFile(t, homeFile, twoUsersContent)

	if err := validateUsersInput(dir); err != nil {
		t.Fatalf("unattended preflight refused although a users file is present: %v", err)
	}
	if err := importUsersSourceIntoProject(dir, mustResolve(t, dir)); err != nil {
		t.Fatal(err)
	}
	var err error
	out := captureStdout(t, func() { err = runCreateUsers(dir) })
	if err != nil {
		t.Fatal(err)
	}
	want := "  Found " + homeFile + " with 2 users; using it.\n"
	if !strings.Contains(out, want) {
		t.Fatalf("detected file not announced, want %q in:\n%s", want, out)
	}
	if len(accounts.created) != 2 {
		t.Fatalf("detected file's users not created: %d", len(accounts.created))
	}
	copied, _ := os.ReadFile(filepath.Join(dir, ".users.yml"))
	if string(copied) != twoUsersContent {
		t.Fatalf("detected file not copied into the project: %q", copied)
	}
}

func mustResolve(t *testing.T, dir string) usersSource {
	t.Helper()
	src, err := resolveUsersSource(dir)
	if err != nil {
		t.Fatal(err)
	}
	return src
}

// Case 3 (legacy location): a pre-placed project .users.yml is announced too.
func TestUsersCase3DetectedProjectFileIsAnnounced(t *testing.T) {
	_, dir, _ := provisioningFixture(t, false)
	writeUsersFile(t, filepath.Join(dir, ".users.yml"), usersFixtureContent)
	out := captureStdout(t, func() {
		if err := runCreateUsers(dir); err != nil {
			t.Error(err)
		}
	})
	if !strings.Contains(out, "  Found "+filepath.Join(dir, ".users.yml")+" with 1 users; using it.\n") {
		t.Fatalf("project file not announced:\n%s", out)
	}
}

// Case 4 + persistence (AC #9): interactive with no file asks, states what
// was created, saves ~/statbus.users.yml (0600) without printing the
// password, and the NEXT install detects it and does not ask again.
func TestUsersCase4InteractiveAdminIsCreatedSavedAndReused(t *testing.T) {
	home, dir, accounts := provisioningFixture(t, true)
	answers := map[string]string{"  Email": "first-admin@example.org", "  Name": `First O'Admin "Q"`}
	oldPrompt := administratorPrompt
	administratorPrompt = func(label, _ string) string { fmt.Printf("%s []: ", label); return answers[label] }
	t.Cleanup(func() { administratorPrompt = oldPrompt })
	password := `pa"ss'w\rd`
	oldAsk := askAdministratorPasswordFn
	askAdministratorPasswordFn = func() (string, error) { return password, nil }
	t.Cleanup(func() { askAdministratorPasswordFn = oldAsk })

	if err := validateUsersInput(dir); err != nil {
		t.Fatalf("interactive preflight with no file must allow the prompt: %v", err)
	}
	var err error
	out := captureStdout(t, func() { err = runCreateUsers(dir) })
	if err != nil {
		t.Fatal(err)
	}
	homeFile := filepath.Join(home, "statbus.users.yml")
	for _, want := range []string{
		"  Create the first administrator. Everyone else is invited from the web interface.",
		"  Created administrator first-admin@example.org.",
		"  Saved the administrator to " + homeFile + " (mode 0600) so a later install reuses it.",
	} {
		if !strings.Contains(out, want+"\n") {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, password) {
		t.Fatalf("password printed:\n%s", out)
	}
	if len(accounts.created) != 1 || accounts.created[0].role != "admin_user" {
		t.Fatalf("created %+v", accounts.created)
	}
	for _, path := range []string{homeFile, filepath.Join(dir, ".users.yml")} {
		st, err := os.Stat(path)
		if err != nil || st.Mode().Perm() != 0600 {
			t.Fatalf("%s not saved at 0600: %v %v", path, st, err)
		}
		data, _ := os.ReadFile(path)
		users, err := parseUsersYAML(string(data))
		if err != nil || len(users) != 1 || users[0] != (userEntry{email: "first-admin@example.org", displayName: `First O'Admin "Q"`, password: password, role: "admin_user"}) {
			t.Fatalf("%s does not round-trip the administrator: %+v %v", path, users, err)
		}
	}

	// The next install on a fresh checkout (project dir gone, home file kept),
	// unattended: it is detected, reused, and nothing is asked.
	nextDir := t.TempDir()
	nonInteractive = true
	stdinIsTerminal = func() bool { return false }
	accounts.emails = map[string]bool{}
	accounts.created = nil
	if err := validateUsersInput(nextDir); err != nil {
		t.Fatalf("next install did not find the saved administrator: %v", err)
	}
	out = captureStdout(t, func() { err = runCreateUsers(nextDir) })
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "  Found "+homeFile+" with 1 users; using it.\n") || strings.Contains(out, "Email") {
		t.Fatalf("next install did not reuse the saved file:\n%s", out)
	}
	if len(accounts.created) != 1 || accounts.created[0].password != password {
		t.Fatalf("reused administrator differs: %+v", accounts.created)
	}
}

// Case 5: unattended with nothing refuses with the exact remedy, both at
// preflight and at the step (defence in depth for a repair path).
func TestUsersCase5UnattendedWithoutUsersFailsFast(t *testing.T) {
	home, dir, _ := provisioningFixture(t, false)
	want := "No users file was found and this run cannot ask for the first administrator. Set STATBUS_USERS_FILE to your users file, or place it at " + filepath.Join(home, "statbus.users.yml") + ", then run the same install command again: curl -fsSL https://statbus.org/install.sh | bash"
	err := validateUsersInput(dir)
	if err == nil || err.Error() != want {
		t.Fatalf("preflight: got %v\nwant %s", err, want)
	}
	if ExitCode(err) != exitInstallPreflight {
		t.Fatalf("exit code %d, want preflight %d", ExitCode(err), exitInstallPreflight)
	}
	if err := runCreateUsers(dir); err == nil || err.Error() != want {
		t.Fatalf("step: got %v", err)
	}
	// A pipe without --non-interactive is equally unable to ask.
	nonInteractive = false
	if err := validateUsersInput(dir); err == nil || err.Error() != want {
		t.Fatalf("piped stdin: got %v", err)
	}
	// And the exact remedy crosses install.sh's exit-78 boundary verbatim.
	got := installShFailureTailIn(t, t.TempDir(), "curl -fsSL https://statbus.org/install.sh | bash", want+"\n", 78)
	if !strings.Contains(got, want) || strings.Contains(got, "Correct the settings") {
		t.Fatalf("install.sh did not show the users remedy:\n%s", got)
	}
}

// Case 6: the end-of-install statement. Zero users and a supplied file whose
// users are absent both produce the loud warning with the fix command.
func TestUsersCase6EndStateWarnings(t *testing.T) {
	_, dir, accounts := provisioningFixture(t, false)
	fix := "Place the users file at " + filepath.Join(dir, ".users.yml") + ", then run: cd " + dir + " && ./sb users create"

	out := captureStdout(t, func() { reportInstallUsers(dir) })
	if !strings.Contains(out, "User accounts: 0\n") || !strings.Contains(out, "⚠ USERS: no user account exists, so nobody can sign in. "+fix+"\n") {
		t.Fatalf("zero-user end state not warned:\n%s", out)
	}

	writeUsersFile(t, filepath.Join(dir, ".users.yml"), twoUsersContent)
	accounts.emails["ada@example.org"] = true
	out = captureStdout(t, func() { reportInstallUsers(dir) })
	if !strings.Contains(out, "User accounts: 1\n") || !strings.Contains(out, "⚠ USERS: "+filepath.Join(dir, ".users.yml")+" lists 2 users but 1 of them do not exist. "+fix+"\n") {
		t.Fatalf("short file end state not warned:\n%s", out)
	}

	accounts.emails["reg@example.org"] = true
	out = captureStdout(t, func() { reportInstallUsers(dir) })
	if out != "User accounts: 2\n" {
		t.Fatalf("healthy end state should only report the count, got:\n%s", out)
	}
}

// Case 6, terminal boundary: the warning and the announcements reach the
// operator through install.sh's terminal filter.
func TestUsersLinesPassTheTerminalFilter(t *testing.T) {
	lines := []string{
		"  Using STATBUS_USERS_FILE /home/statbus/users.yml with 2 users.",
		"  Not using /home/statbus/statbus.users.yml: STATBUS_USERS_FILE was given explicitly and takes precedence.",
		"  Found /home/statbus/statbus.users.yml with 3 users; using it.",
		"  Created 3 users from /home/statbus/statbus.users.yml; 0 already existed and were left unchanged.",
		"  Create the first administrator. Everyone else is invited from the web interface.",
		"  Created administrator admin@example.org.",
		"  Saved the administrator to /home/statbus/statbus.users.yml (mode 0600) so a later install reuses it.",
		"User accounts: 0",
		"⚠ USERS: no user account exists, so nobody can sign in. Place the users file at /home/statbus/statbus/.users.yml, then run: cd /home/statbus/statbus && ./sb users create",
	}
	cmd := exec.Command("awk", "-f", "../../ops/install-terminal-output.awk")
	cmd.Stdin = strings.NewReader(strings.Join(lines, "\n") + "\n  password: leaked\n")
	got, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != strings.Join(lines, "\n")+"\n" {
		t.Fatalf("terminal filter:\n%s", got)
	}
}

// Case 7: precedence and contradictions.
func TestUsersCase7ConflictsResolveExplicitly(t *testing.T) {
	t.Run("explicit beats detected home file, which is named as not used", func(t *testing.T) {
		home, dir, accounts := provisioningFixture(t, false)
		writeUsersFile(t, filepath.Join(home, "statbus.users.yml"), usersFixtureContent)
		explicit := filepath.Join(t.TempDir(), "explicit.yml")
		writeUsersFile(t, explicit, twoUsersContent)
		t.Setenv(installinput.UsersFile, explicit)
		out := captureStdout(t, func() {
			if err := runCreateUsers(dir); err != nil {
				t.Error(err)
			}
		})
		if !strings.Contains(out, "  Using STATBUS_USERS_FILE "+explicit+" with 2 users.\n") ||
			!strings.Contains(out, "  Not using "+filepath.Join(home, "statbus.users.yml")+": STATBUS_USERS_FILE was given explicitly and takes precedence.\n") {
			t.Fatalf("precedence not stated:\n%s", out)
		}
		if accounts.emails["fixture-admin@example.org"] {
			t.Fatal("overridden home file was applied")
		}
	})
	t.Run("detected file beats the prompt", func(t *testing.T) {
		home, dir, _ := provisioningFixture(t, true)
		writeUsersFile(t, filepath.Join(home, "statbus.users.yml"), usersFixtureContent)
		out := captureStdout(t, func() {
			if err := runCreateUsers(dir); err != nil {
				t.Error(err)
			}
		})
		if strings.Contains(out, "Email") || !strings.Contains(out, "using it.") {
			t.Fatalf("interactive run asked although a file was detected:\n%s", out)
		}
	})
	t.Run("explicit file contradicting a pre-placed project file is an error", func(t *testing.T) {
		_, dir, _ := provisioningFixture(t, false)
		writeUsersFile(t, filepath.Join(dir, ".users.yml"), usersFixtureContent)
		explicit := filepath.Join(t.TempDir(), "explicit.yml")
		writeUsersFile(t, explicit, twoUsersContent)
		t.Setenv(installinput.UsersFile, explicit)
		err := validateUsersInput(dir)
		want := "the users files " + explicit + " and " + filepath.Join(dir, ".users.yml") + " list different users."
		if err == nil || !strings.HasPrefix(err.Error(), want) {
			t.Fatalf("got %v, want prefix %q", err, want)
		}
		got := installShFailureTailIn(t, t.TempDir(), "curl -fsSL https://statbus.org/install.sh | bash", err.Error()+"\n", 78)
		if !strings.Contains(got, want) {
			t.Fatalf("contradiction did not reach the operator:\n%s", got)
		}
	})
	t.Run("detected home and project files that disagree are an error", func(t *testing.T) {
		home, dir, _ := provisioningFixture(t, false)
		writeUsersFile(t, filepath.Join(home, "statbus.users.yml"), usersFixtureContent)
		writeUsersFile(t, filepath.Join(dir, ".users.yml"), twoUsersContent)
		if err := validateUsersInput(dir); err == nil || !strings.Contains(err.Error(), "list different users") {
			t.Fatalf("got %v", err)
		}
	})
	t.Run("identical files by meaning are not a contradiction", func(t *testing.T) {
		home, dir, _ := provisioningFixture(t, false)
		writeUsersFile(t, filepath.Join(home, "statbus.users.yml"), "# home copy\n"+usersFixtureContent)
		writeUsersFile(t, filepath.Join(dir, ".users.yml"), usersFixtureContent)
		if err := validateUsersInput(dir); err != nil {
			t.Fatalf("equal files refused: %v", err)
		}
	})
}

// An established box (someone can sign in) with no explicit file is done:
// a detected file never resurrects an account an administrator deleted, and
// a later divergence between the copies cannot fail the upgrade service's
// post-upgrade install. An explicit file's missing entries are created.
func TestUsersEstablishedBoxStepSemantics(t *testing.T) {
	home, dir, accounts := provisioningFixture(t, false)
	accounts.emails["someone@example.org"] = true
	writeUsersFile(t, filepath.Join(home, "statbus.users.yml"), usersFixtureContent)
	writeUsersFile(t, filepath.Join(dir, ".users.yml"), twoUsersContent)
	if !checkUsersDone(dir) {
		t.Fatal("established box without explicit file re-ran the Administrator step")
	}
	explicit := filepath.Join(t.TempDir(), "explicit.yml")
	writeUsersFile(t, explicit, twoUsersContent)
	t.Setenv(installinput.UsersFile, explicit)
	if err := os.Remove(filepath.Join(home, "statbus.users.yml")); err != nil {
		t.Fatal(err)
	}
	if checkUsersDone(dir) {
		t.Fatal("explicit file with absent users was considered done")
	}
	out := captureStdout(t, func() {
		if err := runCreateUsers(dir); err != nil {
			t.Error(err)
		}
	})
	if !strings.Contains(out, "  Created 2 users from "+explicit+"; 0 already existed and were left unchanged.\n") {
		t.Fatalf("explicit file's missing users not created:\n%s", out)
	}
	if !checkUsersDone(dir) {
		t.Fatal("not done after creating them")
	}
}
