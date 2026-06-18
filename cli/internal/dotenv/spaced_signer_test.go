package dotenv

import "testing"

// Reproduces the STATBUS-071 arc trust-injection round-trip: a spaced SSH pubkey
// value stored via Set → String (what `./sb dotenv set` writes) → re-parsed (what
// config-gen and loadTrustedSigners read). If the value mangles, the ephemeral key
// never lands in allowed_signers and verifyCommitSignature fails "not for arc".
func TestSpacedTrustedSignerRoundTrip(t *testing.T) {
	key := "UPGRADE_TRUSTED_SIGNER_arc"
	val := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILabcDEF123plus+slash/eq="

	// (1) Parse a written-unquoted line — exactly what config-gen emits to .env
	// and what loadTrustedSigners' dotenv.Load reads back.
	f := FromString(key + "=" + val)
	got, ok := f.Get(key)
	if !ok {
		t.Fatalf("key not found")
	}
	if got != val {
		t.Fatalf("PARSE MANGLED unquoted spaced value:\n got = %q\n want = %q", got, val)
	}
	t.Logf("(1) parse-unquoted OK: %q", got)

	// (2) Set + String round-trip — the `./sb dotenv set` write path.
	f2 := FromString("# header\nFOO=bar\n")
	f2.Set(key, val)
	rendered := f2.String()
	t.Logf("(2) rendered file:\n%s", rendered)
	f3 := FromString(rendered)
	got3, _ := f3.Get(key)
	if got3 != val {
		t.Fatalf("SET ROUNDTRIP MANGLED:\n got = %q\n want = %q", got3, val)
	}
	t.Logf("(2) set-roundtrip OK: %q", got3)

	// (3) config-gen's exact emit form: fmt.Sprintf("%s=%s", key, v) re-parsed.
	line := key + "=" + got // got is what cfgFile.Get returned
	f4 := FromString(line)
	got4, _ := f4.Get(key)
	if got4 != val {
		t.Fatalf("CONFIG-GEN EMIT MANGLED:\n got = %q\n want = %q", got4, val)
	}
	// And the final allowed_signers line loadTrustedSigners builds:
	t.Logf("(3) allowed_signers line would be: %q", "arc "+got4)
}
