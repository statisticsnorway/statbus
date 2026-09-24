// Package dbroles keeps the database's login-role passwords equal to the
// passwords in the generated .env (which come from .env.credentials).
//
// postgres/init-db.sh sets those passwords exactly once, when the database
// volume is first initialised. If .env.credentials is regenerated while the
// volume survives (for example after ~/statbus was removed and the one install
// command was run again), .env and the database disagree. PostgREST then
// restart-loops on `password authentication failed for user "authenticator"`
// and the upgrade service never connects. Seed and migrations still succeed
// because they run over the container's local socket, where the admin user is
// trusted (postgres/pg_hba.conf line 1).
//
// This package uses that same local-socket route to read the stored password
// verifiers, compare them with .env in Go, and re-apply any that differ. The
// comparison never sends a password anywhere, and the ALTER ROLE statements
// travel on psql's stdin, never on a command line.
package dbroles

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/md5"
	"crypto/pbkdf2"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// Role is one login role whose password .env owns.
type Role struct {
	Name        string // role name in the database
	PasswordKey string // .env key that holds its password
	Password    string
}

// Target is everything needed to reach the database over the local socket and
// to know which passwords it should hold.
type Target struct {
	AdminUser string // superuser trusted on the local socket
	AdminDB   string // maintenance database (never the app database, whose read-only window must not matter)
	Roles     []Role
}

// Env is the subset of dotenv.File the loader needs; tests pass a map.
type Env interface {
	Get(key string) (string, bool)
}

// MapEnv adapts a map to Env.
type MapEnv map[string]string

// Get implements Env.
func (m MapEnv) Get(key string) (string, bool) {
	v, ok := m[key]
	return v, ok
}

// TargetFromEnv lists every login role postgres/init-db.sh creates with a
// password, and the .env key that owns it:
//   - POSTGRES_ADMIN_USER (upstream entrypoint's POSTGRES_USER/POSTGRES_PASSWORD)
//   - POSTGRES_APP_USER   (init-db.sh "app user + database")
//   - authenticator       (init-db.sh "authentication roles", PostgREST's login)
//   - POSTGRES_NOTIFY_USER (init-db.sh "notify reader role + user")
func TargetFromEnv(env Env) (Target, error) {
	get := func(key, fallback string) string {
		if v, ok := env.Get(key); ok && v != "" {
			return v
		}
		return fallback
	}
	t := Target{
		AdminUser: get("POSTGRES_ADMIN_USER", "postgres"),
		AdminDB:   get("POSTGRES_ADMIN_DB", "postgres"),
	}
	specs := []struct{ userKey, fixedName, passwordKey string }{
		{"POSTGRES_ADMIN_USER", "", "POSTGRES_ADMIN_PASSWORD"},
		{"POSTGRES_APP_USER", "", "POSTGRES_APP_PASSWORD"},
		{"", "authenticator", "POSTGRES_AUTHENTICATOR_PASSWORD"},
		{"POSTGRES_NOTIFY_USER", "", "POSTGRES_NOTIFY_PASSWORD"},
	}
	var missing []string
	for _, s := range specs {
		name := s.fixedName
		if s.userKey != "" {
			name = get(s.userKey, "")
			if name == "" && s.userKey == "POSTGRES_ADMIN_USER" {
				name = "postgres"
			}
			if name == "" {
				missing = append(missing, s.userKey)
				continue
			}
		}
		pw := get(s.passwordKey, "")
		if pw == "" {
			missing = append(missing, s.passwordKey)
			continue
		}
		t.Roles = append(t.Roles, Role{Name: name, PasswordKey: s.passwordKey, Password: pw})
	}
	if len(missing) > 0 {
		return Target{}, fmt.Errorf("the generated .env is missing %s; regenerate it with ./sb config generate", strings.Join(missing, ", "))
	}
	return t, nil
}

// LoadTarget reads projDir/.env.
func LoadTarget(projDir string) (Target, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return Target{}, err
	}
	return TargetFromEnv(f)
}

// Mismatch names a role whose stored password differs from .env.
type Mismatch struct {
	Role   string
	Reason string // "differs", "missing role", "no password set"
}

func (m Mismatch) String() string { return m.Role + " (" + m.Reason + ")" }

// Compare is the pure verdict: storedVerifiers maps role name to
// pg_authid.rolpassword ("" when NULL); a role absent from the map does not
// exist. Result is sorted by role name.
func Compare(t Target, storedVerifiers map[string]string) []Mismatch {
	var out []Mismatch
	for _, r := range t.Roles {
		stored, exists := storedVerifiers[r.Name]
		switch {
		case !exists:
			out = append(out, Mismatch{Role: r.Name, Reason: "missing role"})
		case stored == "":
			out = append(out, Mismatch{Role: r.Name, Reason: "no password set"})
		case !VerifierMatches(stored, r.Name, r.Password):
			out = append(out, Mismatch{Role: r.Name, Reason: "differs"})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Role < out[j].Role })
	return out
}

// VerifierMatches reports whether a pg_authid.rolpassword value was derived
// from password. It understands the two formats PostgreSQL stores:
// SCRAM-SHA-256$<iter>:<salt>$<StoredKey>:<ServerKey> (RFC 5802/7677) and the
// legacy "md5" + md5(password || username). Anything else never matches, so an
// unknown format leads to a re-apply rather than a false "agrees".
func VerifierMatches(stored, username, password string) bool {
	if strings.HasPrefix(stored, "md5") && len(stored) == 35 {
		sum := md5.Sum([]byte(password + username))
		return hmac.Equal([]byte(stored[3:]), []byte(hex.EncodeToString(sum[:])))
	}
	rest, ok := strings.CutPrefix(stored, "SCRAM-SHA-256$")
	if !ok {
		return false
	}
	iterSalt, keys, ok := strings.Cut(rest, "$")
	if !ok {
		return false
	}
	iterText, saltB64, ok := strings.Cut(iterSalt, ":")
	if !ok {
		return false
	}
	storedKeyB64, serverKeyB64, ok := strings.Cut(keys, ":")
	if !ok {
		return false
	}
	iter, err := strconv.Atoi(iterText)
	if err != nil || iter <= 0 {
		return false
	}
	salt, err := base64.StdEncoding.DecodeString(saltB64)
	if err != nil {
		return false
	}
	wantStored, err := base64.StdEncoding.DecodeString(storedKeyB64)
	if err != nil {
		return false
	}
	wantServer, err := base64.StdEncoding.DecodeString(serverKeyB64)
	if err != nil {
		return false
	}
	gotStored, gotServer, err := scramKeys(password, salt, iter)
	if err != nil {
		return false
	}
	return hmac.Equal(gotStored, wantStored) && hmac.Equal(gotServer, wantServer)
}

// scramKeys derives StoredKey and ServerKey. The generated passwords are ASCII
// letters and digits, for which SASLprep is the identity, so the password bytes
// are used as-is (PostgreSQL does the same when SASLprep leaves them unchanged).
func scramKeys(password string, salt []byte, iter int) (storedKey, serverKey []byte, err error) {
	salted, err := pbkdf2.Key(sha256.New, password, salt, iter, sha256.Size)
	if err != nil {
		return nil, nil, err
	}
	mac := func(key []byte, msg string) []byte {
		h := hmac.New(sha256.New, key)
		h.Write([]byte(msg))
		return h.Sum(nil)
	}
	clientKey := mac(salted, "Client Key")
	sum := sha256.Sum256(clientKey)
	return sum[:], mac(salted, "Server Key"), nil
}

// sqlLiteral quotes s as a SQL string literal.
func sqlLiteral(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

// sqlIdent quotes s as a SQL identifier.
func sqlIdent(s string) string { return `"` + strings.ReplaceAll(s, `"`, `""`) + `"` }

// VerifierQuery reads the stored verifier of every target role. Output is one
// "name|verifier" line per existing role.
func VerifierQuery(t Target) string {
	names := make([]string, 0, len(t.Roles))
	for _, r := range t.Roles {
		names = append(names, sqlLiteral(r.Name))
	}
	return "SELECT rolname, COALESCE(rolpassword, '') FROM pg_catalog.pg_authid WHERE rolname IN (" +
		strings.Join(names, ", ") + ") ORDER BY rolname;\n"
}

// ParseVerifiers parses VerifierQuery's `psql -A -t -F '|'` output.
func ParseVerifiers(out string) (map[string]string, error) {
	res := make(map[string]string)
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimRight(line, "\r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		name, verifier, ok := strings.Cut(line, "|")
		if !ok {
			return nil, fmt.Errorf("unexpected role verifier line (no separator)")
		}
		res[name] = verifier
	}
	return res, nil
}

// SyncSQL is the ALTER ROLE script for the given roles, in one read-write
// transaction. It fails loudly (ON_ERROR_STOP) if a role does not exist: a
// missing role means init-db.sh did not finish, which start-postgres.sh's
// sentinel already handles, and must not be papered over here.
func SyncSQL(roles []Role) string {
	var b strings.Builder
	b.WriteString("BEGIN READ WRITE;\n")
	for _, r := range roles {
		fmt.Fprintf(&b, "ALTER ROLE %s PASSWORD %s;\n", sqlIdent(r.Name), sqlLiteral(r.Password))
	}
	b.WriteString("COMMIT;\n")
	return b.String()
}

// Runner runs psql inside the db container with stdin and returns stdout.
// The production runner is DockerPsql; tests substitute a fake.
type Runner func(ctx context.Context, t Target, stdin string) (string, error)

// DockerPsql runs `docker compose exec -T db psql -U <admin> -d <admindb>` in
// projDir: the container's local socket, where the admin user is trusted, so it
// works while TCP password authentication is split. Only non-secret flags are
// on the command line; the SQL (and any password in it) is on stdin.
func DockerPsql(projDir string) Runner {
	return func(ctx context.Context, t Target, stdin string) (string, error) {
		cmd, err := compose.CommandContext(ctx, projDir,
			"exec", "-T", "db", "psql", "-X", "-q", "-A", "-t", "-F", "|",
			"-v", "ON_ERROR_STOP=1", "-U", t.AdminUser, "-d", t.AdminDB)
		if err != nil {
			return "", err
		}
		cmd.Stdin = strings.NewReader(stdin)
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("psql in the db container: %w (%s)", err, strings.TrimSpace(stderr.String()))
		}
		return stdout.String(), nil
	}
}

// Check returns the roles whose stored password differs from .env.
func Check(ctx context.Context, t Target, run Runner) ([]Mismatch, error) {
	out, err := run(ctx, t, VerifierQuery(t))
	if err != nil {
		return nil, fmt.Errorf("read database role passwords: %w", err)
	}
	stored, err := ParseVerifiers(out)
	if err != nil {
		return nil, err
	}
	return Compare(t, stored), nil
}

// Sync makes every role password equal to .env. It re-applies only the roles
// that differ, then reads the verifiers back and fails if any still differ.
// Returns the roles it changed (empty on a box where everything agreed).
func Sync(ctx context.Context, t Target, run Runner) ([]Mismatch, error) {
	mismatches, err := Check(ctx, t, run)
	if err != nil {
		return nil, err
	}
	if len(mismatches) == 0 {
		return nil, nil
	}
	byName := make(map[string]Role, len(t.Roles))
	for _, r := range t.Roles {
		byName[r.Name] = r
	}
	var toFix []Role
	for _, m := range mismatches {
		if m.Reason == "missing role" {
			return nil, fmt.Errorf("database role %s does not exist; the database was not fully initialised", m.Role)
		}
		toFix = append(toFix, byName[m.Role])
	}
	if _, err := run(ctx, t, SyncSQL(toFix)); err != nil {
		return nil, fmt.Errorf("set database role passwords: %w", err)
	}
	after, err := Check(ctx, t, run)
	if err != nil {
		return nil, err
	}
	if len(after) > 0 {
		return nil, fmt.Errorf("database role passwords still differ from .env after updating them: %s", joinMismatches(after))
	}
	return mismatches, nil
}

// SyncProject is Sync for projDir with the production runner and a bounded
// timeout.
func SyncProject(ctx context.Context, projDir string) ([]Mismatch, error) {
	t, err := LoadTarget(projDir)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	return Sync(ctx, t, DockerPsql(projDir))
}

// CheckProject is Check for projDir with the production runner.
func CheckProject(ctx context.Context, projDir string) ([]Mismatch, error) {
	t, err := LoadTarget(projDir)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	return Check(ctx, t, DockerPsql(projDir))
}

// RoleNames lists the role names of mismatches for messages.
func RoleNames(ms []Mismatch) string {
	names := make([]string, 0, len(ms))
	for _, m := range ms {
		names = append(names, m.Role)
	}
	return strings.Join(names, ", ")
}

func joinMismatches(ms []Mismatch) string {
	parts := make([]string, 0, len(ms))
	for _, m := range ms {
		parts = append(parts, m.String())
	}
	return strings.Join(parts, ", ")
}
