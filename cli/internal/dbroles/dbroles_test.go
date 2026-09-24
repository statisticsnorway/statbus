package dbroles

import (
	"context"
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"testing"
)

// RFC 7677 section 3: user "user", password "pencil". The server signature and
// client proof prove scramKeys derives StoredKey/ServerKey exactly as a SCRAM
// server does, independently of this package's own verifier formatting.
func TestScramKeysMatchRFC7677(t *testing.T) {
	salt, _ := base64.StdEncoding.DecodeString("W22ZaJ0SNY7soEsUEjb6gQ==")
	storedKey, serverKey, err := scramKeys("pencil", salt, 4096)
	if err != nil {
		t.Fatal(err)
	}
	const nonce = "rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0"
	authMessage := "n=user,r=rOprNGfwEbeRWgbNEkqO," +
		"r=" + nonce + ",s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096," +
		"c=biws,r=" + nonce
	mac := func(key []byte, msg string) []byte {
		h := hmac.New(sha256.New, key)
		h.Write([]byte(msg))
		return h.Sum(nil)
	}
	if got := base64.StdEncoding.EncodeToString(mac(serverKey, authMessage)); got != "6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=" {
		t.Fatalf("server signature = %s", got)
	}
	// ClientProof = ClientKey XOR ClientSignature; recover ClientKey from the
	// RFC's proof and check that SHA-256(ClientKey) == StoredKey.
	proof, _ := base64.StdEncoding.DecodeString("dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")
	sig := mac(storedKey, authMessage)
	clientKey := make([]byte, len(proof))
	for i := range proof {
		clientKey[i] = proof[i] ^ sig[i]
	}
	sum := sha256.Sum256(clientKey)
	if !hmac.Equal(sum[:], storedKey) {
		t.Fatal("StoredKey does not match the RFC 7677 client proof")
	}
}

func scramVerifier(t *testing.T, password string) string {
	t.Helper()
	salt := []byte("0123456789abcdef")
	storedKey, serverKey, err := scramKeys(password, salt, 4096)
	if err != nil {
		t.Fatal(err)
	}
	enc := base64.StdEncoding.EncodeToString
	return fmt.Sprintf("SCRAM-SHA-256$4096:%s$%s:%s", enc(salt), enc(storedKey), enc(serverKey))
}

func TestVerifierMatches(t *testing.T) {
	v := scramVerifier(t, "Secret123")
	if !VerifierMatches(v, "authenticator", "Secret123") {
		t.Fatal("scram verifier should match its own password")
	}
	if VerifierMatches(v, "authenticator", "Secret124") {
		t.Fatal("scram verifier matched a different password")
	}
	sum := md5.Sum([]byte("pw" + "bob"))
	md5v := "md5" + hex.EncodeToString(sum[:])
	if !VerifierMatches(md5v, "bob", "pw") || VerifierMatches(md5v, "alice", "pw") {
		t.Fatal("md5 verifier handling is wrong")
	}
	for _, bad := range []string{"", "plain", "SCRAM-SHA-256$x:y$z", "SCRAM-SHA-256$4096:!!$a:b"} {
		if VerifierMatches(bad, "u", "p") {
			t.Fatalf("malformed verifier %q matched", bad)
		}
	}
}

func testEnv() MapEnv {
	return MapEnv{
		"POSTGRES_ADMIN_USER":             "postgres",
		"POSTGRES_ADMIN_PASSWORD":         "AdminPw",
		"POSTGRES_APP_USER":               "statbus_local",
		"POSTGRES_APP_PASSWORD":           "AppPw",
		"POSTGRES_AUTHENTICATOR_PASSWORD": "AuthPw",
		"POSTGRES_NOTIFY_USER":            "statbus_notify_local",
		"POSTGRES_NOTIFY_PASSWORD":        "NotifyPw",
	}
}

func TestTargetFromEnvListsEveryInitDbLoginRole(t *testing.T) {
	tg, err := TargetFromEnv(testEnv())
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, r := range tg.Roles {
		names = append(names, r.Name+"="+r.PasswordKey)
	}
	want := "postgres=POSTGRES_ADMIN_PASSWORD statbus_local=POSTGRES_APP_PASSWORD authenticator=POSTGRES_AUTHENTICATOR_PASSWORD statbus_notify_local=POSTGRES_NOTIFY_PASSWORD"
	if got := strings.Join(names, " "); got != want {
		t.Fatalf("roles = %s\nwant %s", got, want)
	}
	if tg.AdminUser != "postgres" || tg.AdminDB != "postgres" {
		t.Fatalf("admin route = %s/%s", tg.AdminUser, tg.AdminDB)
	}
	env := testEnv()
	delete(env, "POSTGRES_AUTHENTICATOR_PASSWORD")
	if _, err := TargetFromEnv(env); err == nil || !strings.Contains(err.Error(), "POSTGRES_AUTHENTICATOR_PASSWORD") {
		t.Fatalf("missing password not named: %v", err)
	}
}

// fakeDB emulates the db container: it answers the verifier query from its
// stored passwords and applies ALTER ROLE statements.
type fakeDB struct {
	t        *testing.T
	stored   map[string]string // role -> plaintext the DB "holds"
	calls    []string
	failNext error
}

func (f *fakeDB) run(_ context.Context, _ Target, stdin string) (string, error) {
	f.calls = append(f.calls, stdin)
	if f.failNext != nil {
		err := f.failNext
		f.failNext = nil
		return "", err
	}
	if strings.HasPrefix(stdin, "SELECT rolname") {
		var b strings.Builder
		for name, pw := range f.stored {
			if !strings.Contains(stdin, "'"+name+"'") {
				continue
			}
			fmt.Fprintf(&b, "%s|%s\n", name, scramVerifier(f.t, pw))
		}
		return b.String(), nil
	}
	for _, line := range strings.Split(stdin, "\n") {
		rest, ok := strings.CutPrefix(line, "ALTER ROLE \"")
		if !ok {
			continue
		}
		name, pwPart, _ := strings.Cut(rest, "\" PASSWORD '")
		f.stored[name] = strings.TrimSuffix(pwPart, "';")
	}
	return "", nil
}

func TestSyncIsNoOpWhenPasswordsAgree(t *testing.T) {
	tg, _ := TargetFromEnv(testEnv())
	db := &fakeDB{t: t, stored: map[string]string{
		"postgres": "AdminPw", "statbus_local": "AppPw", "authenticator": "AuthPw", "statbus_notify_local": "NotifyPw",
	}}
	changed, err := Sync(context.Background(), tg, db.run)
	if err != nil || len(changed) != 0 {
		t.Fatalf("Sync = %v, %v", changed, err)
	}
	if len(db.calls) != 1 {
		t.Fatalf("expected only the read query, got %d calls", len(db.calls))
	}
}

// The Finland shape: a surviving volume holds the old passwords, .env holds new ones.
func TestSyncReappliesOrphanedVolumePasswords(t *testing.T) {
	tg, _ := TargetFromEnv(testEnv())
	db := &fakeDB{t: t, stored: map[string]string{
		"postgres": "OldAdmin", "statbus_local": "AppPw", "authenticator": "OldAuth", "statbus_notify_local": "OldNotify",
	}}
	changed, err := Sync(context.Background(), tg, db.run)
	if err != nil {
		t.Fatal(err)
	}
	if got := RoleNames(changed); got != "authenticator, postgres, statbus_notify_local" {
		t.Fatalf("changed = %s", got)
	}
	if db.stored["authenticator"] != "AuthPw" || db.stored["postgres"] != "AdminPw" || db.stored["statbus_notify_local"] != "NotifyPw" {
		t.Fatalf("stored after sync = %v", db.stored)
	}
	alter := db.calls[1]
	if strings.Contains(alter, "statbus_local\"") && strings.Contains(alter, "AppPw") {
		t.Fatal("an agreeing role was re-applied")
	}
	if !strings.HasPrefix(alter, "BEGIN READ WRITE;") || !strings.HasSuffix(alter, "COMMIT;\n") {
		t.Fatalf("ALTER script not one read-write transaction:\n%s", alter)
	}
	if len(db.calls) != 3 {
		t.Fatalf("expected read, alter, read-back; got %d calls", len(db.calls))
	}
}

func TestSyncRefusesMissingRole(t *testing.T) {
	tg, _ := TargetFromEnv(testEnv())
	db := &fakeDB{t: t, stored: map[string]string{"postgres": "AdminPw", "statbus_local": "AppPw", "statbus_notify_local": "NotifyPw"}}
	if _, err := Sync(context.Background(), tg, db.run); err == nil || !strings.Contains(err.Error(), "authenticator") {
		t.Fatalf("missing role error = %v", err)
	}
}

func TestSyncSurfacesPsqlFailure(t *testing.T) {
	tg, _ := TargetFromEnv(testEnv())
	db := &fakeDB{t: t, stored: map[string]string{}, failNext: errors.New("container not running")}
	if _, err := Sync(context.Background(), tg, db.run); err == nil || !strings.Contains(err.Error(), "container not running") {
		t.Fatalf("err = %v", err)
	}
}

func TestSyncSQLQuotes(t *testing.T) {
	got := SyncSQL([]Role{{Name: `we"ird`, Password: "it's"}})
	if !strings.Contains(got, `ALTER ROLE "we""ird" PASSWORD 'it''s';`) {
		t.Fatalf("quoting wrong:\n%s", got)
	}
}

func TestParseVerifiers(t *testing.T) {
	m, err := ParseVerifiers("authenticator|SCRAM-SHA-256$x\npostgres|\n\n")
	if err != nil || m["authenticator"] != "SCRAM-SHA-256$x" || m["postgres"] != "" || len(m) != 2 {
		t.Fatalf("ParseVerifiers = %v %v", m, err)
	}
	if _, err := ParseVerifiers("garbage"); err == nil {
		t.Fatal("expected error")
	}
}

// A verifier PostgreSQL 18 (the statbus-db image) wrote for
// CREATE ROLE authenticator LOGIN PASSWORD 'Ab3xYz9QwErTy'.
func TestVerifierMatchesRealPostgres18(t *testing.T) {
	const pg18 = "SCRAM-SHA-256$4096:1hSUqDXZMScCCCMyxvik5A==$z35ZtV/G++ImaLisjer2Hlda1uKW6xuAUIUJ+GwyEAg=:YfcCQwAJDQHFSyff/ZAxUyEB8F+Y7hs8d8PVysfq77w="
	if !VerifierMatches(pg18, "authenticator", "Ab3xYz9QwErTy") {
		t.Fatal("real PostgreSQL verifier does not match its password")
	}
	if VerifierMatches(pg18, "authenticator", "Ab3xYz9QwErTz") {
		t.Fatal("real PostgreSQL verifier matched a different password")
	}
}
