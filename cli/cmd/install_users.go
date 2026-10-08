package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
	"github.com/statisticsnorway/statbus/cli/internal/installinput"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// STATBUS-464: principled user provisioning. Every install says which users
// file it used (or that it asked), how many accounts resulted, and never
// finishes silently with a supplied file unused or with nobody able to sign in.
//
// Sources, strongest first:
//  1. STATBUS_USERS_FILE, explicit. Unreadable or invalid is a hard error.
//  2. A file the operator already placed: the project's .users.yml (the
//     legacy location) or the operator-home input file ~/statbus.users.yml
//     (STATBUS-437's documented, visible input convention). Detected and
//     announced, never silently ignored.
//  3. The interactive first-administrator questions, only with a terminal.
//
// Two supplied files that disagree are a contradiction, refused rather than
// silently preferring one. An explicit path beats a detected home file, which
// is then named as not used.

// operatorUsersFileName is the ONE name for the operator-home users file. The
// interactive first-administrator path writes it and the detection path reads
// it, so the next install finds what this one created.
const operatorUsersFileName = "statbus.users.yml"

func operatorUsersFilePath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("cannot locate the home directory for %s: %w", operatorUsersFileName, err)
	}
	return filepath.Join(home, operatorUsersFileName), nil
}

type usersSourceKind int

const (
	usersFromPrompt usersSourceKind = iota
	usersFromExplicit
	usersFromDetected
	usersFromProject
)

type usersSource struct {
	kind  usersSourceKind
	path  string
	data  []byte
	users []userEntry
	// ignoredPath is a detected home file that an explicit path overrode.
	ignoredPath string
}

func (s usersSource) isFile() bool { return s.kind != usersFromPrompt }

func usersRerunSuffix() string {
	return "then run the same install command again: " + diskpolicy.RerunCommand()
}

func readUsersFile(path string, explicit bool) ([]byte, []userEntry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if explicit {
			return nil, nil, fmt.Errorf("STATBUS_USERS_FILE %s cannot be read. Check the path and its permissions, %s", path, usersRerunSuffix())
		}
		return nil, nil, fmt.Errorf("the users file %s cannot be read. Check its permissions, %s", path, usersRerunSuffix())
	}
	users, err := parseUsersYAML(string(data))
	if err != nil {
		reason := "an entry is missing email, display_name or password"
		if len(strings.TrimSpace(stripUsersComments(string(data)))) == 0 || strings.Contains(err.Error(), "no users found") {
			reason = "it lists no users"
		}
		return nil, nil, fmt.Errorf("the users file %s cannot be used: %s. Correct it, %s", path, reason, usersRerunSuffix())
	}
	return data, users, nil
}

func stripUsersComments(s string) string {
	var b strings.Builder
	for _, line := range strings.Split(s, "\n") {
		if t := strings.TrimSpace(line); t != "" && !strings.HasPrefix(t, "#") {
			b.WriteString(t)
		}
	}
	return b.String()
}

// sameUsers compares by meaning (the parsed entries), so formatting and
// comments do not make two equal files contradict each other.
func sameUsers(a, b []userEntry) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if !strings.EqualFold(a[i].email, b[i].email) || a[i].displayName != b[i].displayName || a[i].password != b[i].password || a[i].role != b[i].role {
			return false
		}
	}
	return true
}

func usersConflict(first, second string) error {
	return fmt.Errorf("the users files %s and %s list different users. Keep one, or make them identical, %s", first, second, usersRerunSuffix())
}

// resolveUsersSource decides which users input this install uses. It is pure
// with respect to the database and is called both by the fresh-install
// preflight and by the Administrator step, so they can never disagree.
func resolveUsersSource(dir string) (usersSource, error) {
	homePath, err := operatorUsersFilePath()
	if err != nil {
		return usersSource{}, err
	}
	projectPath := filepath.Join(dir, ".users.yml")

	var home, project *usersSource
	if _, statErr := os.Stat(homePath); statErr == nil {
		data, users, readErr := readUsersFile(homePath, false)
		if readErr != nil {
			return usersSource{}, readErr
		}
		home = &usersSource{kind: usersFromDetected, path: homePath, data: data, users: users}
	} else if !os.IsNotExist(statErr) {
		return usersSource{}, fmt.Errorf("the users file %s cannot be read. Check its permissions, %s", homePath, usersRerunSuffix())
	}
	if _, statErr := os.Stat(projectPath); statErr == nil {
		data, users, readErr := readUsersFile(projectPath, false)
		if readErr != nil {
			return usersSource{}, readErr
		}
		project = &usersSource{kind: usersFromProject, path: projectPath, data: data, users: users}
	} else if !os.IsNotExist(statErr) {
		return usersSource{}, fmt.Errorf("the users file %s cannot be read. Check its permissions, %s", projectPath, usersRerunSuffix())
	}

	if explicitPath := os.Getenv(installinput.UsersFile); explicitPath != "" {
		if abs, absErr := filepath.Abs(explicitPath); absErr == nil {
			explicitPath = abs
		}
		data, users, readErr := readUsersFile(explicitPath, true)
		if readErr != nil {
			return usersSource{}, readErr
		}
		// A pre-placed project file is the operator's own explicit input too;
		// it must agree. (After this install copies the explicit file in, a
		// rerun finds them identical.)
		if project != nil && explicitPath != projectPath && !sameUsers(users, project.users) {
			return usersSource{}, usersConflict(explicitPath, projectPath)
		}
		src := usersSource{kind: usersFromExplicit, path: explicitPath, data: data, users: users}
		if home != nil && explicitPath != homePath && !sameUsers(users, home.users) {
			src.ignoredPath = homePath
		}
		return src, nil
	}
	switch {
	case home != nil && project != nil:
		if !sameUsers(home.users, project.users) {
			return usersSource{}, usersConflict(homePath, projectPath)
		}
		return *home, nil
	case home != nil:
		return *home, nil
	case project != nil:
		return *project, nil
	}
	return usersSource{kind: usersFromPrompt}, nil
}

func installCanAsk() bool { return !nonInteractive && stdinIsTerminal() }

func missingUsersRefusal() error {
	homePath, err := operatorUsersFilePath()
	if err != nil {
		return err
	}
	return installPreflightRefusal(fmt.Sprintf("No users file was found and this run cannot ask for the first administrator. Set STATBUS_USERS_FILE to your users file, or place it at %s, %s", homePath, usersRerunSuffix()))
}

// validateUsersInput is the fresh-install preflight: a supplied file that is
// unreadable, empty or contradicted refuses before anything is changed, and an
// unattended run with no users at all refuses instead of finishing with nobody
// able to sign in.
func validateUsersInput(dir string) error {
	src, err := resolveUsersSource(dir)
	if err != nil {
		return err
	}
	if !src.isFile() && !installCanAsk() {
		return missingUsersRefusal()
	}
	return nil
}

// importUsersSourceIntoProject copies the chosen file into the installation
// as .users.yml (the live copy ./sb users create and db restore read).
func importUsersSourceIntoProject(dir string, src usersSource) error {
	if !src.isFile() || src.kind == usersFromProject {
		return nil
	}
	return os.WriteFile(filepath.Join(dir, ".users.yml"), src.data, 0600)
}

func announceUsersSource(src usersSource) {
	switch src.kind {
	case usersFromExplicit:
		fmt.Printf("  Using STATBUS_USERS_FILE %s with %d users.\n", src.path, len(src.users))
		if src.ignoredPath != "" {
			fmt.Printf("  Not using %s: STATBUS_USERS_FILE was given explicitly and takes precedence.\n", src.ignoredPath)
		}
	case usersFromDetected:
		fmt.Printf("  Found %s with %d users; using it.\n", src.path, len(src.users))
	case usersFromProject:
		fmt.Printf("  Found %s with %d users; using it.\n", src.path, len(src.users))
	}
}

// Database seams, replaced in tests.
var (
	countInstallUsers = func(dir string) (int, error) {
		out, err := runInstallSQL(dir, `SELECT count(*) FROM auth."user";`)
		if err != nil {
			return 0, err
		}
		lines := strings.Fields(out)
		if len(lines) == 0 {
			return 0, fmt.Errorf("user count query returned nothing")
		}
		return strconv.Atoi(lines[len(lines)-1])
	}
	existingInstallUserEmails = func(dir string, emails []string) (map[string]bool, error) {
		found := make(map[string]bool)
		if len(emails) == 0 {
			return found, nil
		}
		quoted := make([]string, len(emails))
		for i, e := range emails {
			quoted[i] = pgQuote(e)
		}
		out, err := runInstallSQL(dir, `SELECT lower(email::text) FROM auth."user" WHERE email IN (`+strings.Join(quoted, ", ")+`);`)
		if err != nil {
			return nil, err
		}
		for _, line := range strings.Split(out, "\n") {
			if line = strings.TrimSpace(line); line != "" {
				found[line] = true
			}
		}
		return found, nil
	}
	createInstallUsers = func(dir string, users []userEntry) error {
		if err := ensureJWTSecret(dir); err != nil {
			return err
		}
		var sql strings.Builder
		for _, u := range users {
			fmt.Fprintf(&sql, "SELECT * FROM public.user_create(p_display_name => %s, p_email => %s, p_statbus_role => %s, p_password => %s);\n",
				pgQuote(u.displayName), pgQuote(u.email), pgQuote(u.role), pgQuote(u.password))
		}
		psqlArgs, env, err := migrate.PsqlArgs(dir)
		if err != nil {
			return err
		}
		return runPsqlSQL(dir, psqlArgs, env, sql.String())
	}
)

func missingFileUsers(dir string, users []userEntry) ([]userEntry, error) {
	emails := make([]string, len(users))
	for i, u := range users {
		emails[i] = u.email
	}
	found, err := existingInstallUserEmails(dir, emails)
	if err != nil {
		return nil, err
	}
	var missing []userEntry
	for _, u := range users {
		if !found[strings.ToLower(u.email)] {
			missing = append(missing, u)
		}
	}
	return missing, nil
}

// persistInteractiveAdministrator records the typed administrator in the
// operator-home users file (mode 0600, STATBUS-437) and the installation's
// .users.yml, so the next install reuses it instead of asking again and the
// identity survives a fresh checkout. The password is written only to these
// sanctioned files, never to the terminal or a log.
func persistInteractiveAdministrator(dir string, admin userEntry) error {
	homePath, err := operatorUsersFilePath()
	if err != nil {
		return err
	}
	content := "# Written by the StatBus installer after the first administrator was created.\n# A later install reuses this file instead of asking again. Keep it private.\n" + usersYAMLEntry(admin)
	if roundTrip, err := parseUsersYAML(content); err != nil || !sameUsers(roundTrip, []userEntry{admin}) {
		return fmt.Errorf("the administrator was created, but its details cannot be saved in %s; create that file by hand so a later install reuses them", homePath)
	}
	for _, path := range []string{homePath, filepath.Join(dir, ".users.yml")} {
		f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			if errors.Is(err, os.ErrExist) {
				return fmt.Errorf("the administrator was created, but %s appeared during installation and was not overwritten", path)
			}
			return fmt.Errorf("the administrator was created, but %s could not be written", path)
		}
		_, writeErr := f.WriteString(content)
		closeErr := f.Close()
		if writeErr != nil || closeErr != nil {
			return fmt.Errorf("the administrator was created, but %s could not be written", path)
		}
	}
	fmt.Printf("  Saved the administrator to %s (mode 0600) so a later install reuses it.\n", homePath)
	return nil
}

// reportInstallUsers is the end-of-install statement about sign-in. It runs
// after the final serving check, so an install that ends with nobody able to
// sign in, or with a supplied file's users absent, says so last and loudly.
func reportInstallUsers(dir string) {
	fix := fmt.Sprintf("Place the users file at %s, then run: cd %s && ./sb users create", filepath.Join(dir, ".users.yml"), dir)
	count, err := countInstallUsers(dir)
	if err != nil {
		fmt.Printf("⚠ USERS: the user accounts could not be counted, so sign-in is unverified. %s\n", fix)
		return
	}
	fmt.Printf("User accounts: %d\n", count)
	if count == 0 {
		fmt.Printf("⚠ USERS: no user account exists, so nobody can sign in. %s\n", fix)
		return
	}
	src, err := resolveUsersSource(dir)
	if err != nil {
		fmt.Printf("⚠ USERS: %v\n", err)
		return
	}
	if !src.isFile() {
		return
	}
	missing, err := missingFileUsers(dir, src.users)
	if err != nil {
		fmt.Printf("⚠ USERS: the accounts in %s could not be checked. %s\n", src.path, fix)
		return
	}
	if len(missing) > 0 {
		fmt.Printf("⚠ USERS: %s lists %d users but %d of them do not exist. %s\n", src.path, len(src.users), len(missing), fix)
	}
}
