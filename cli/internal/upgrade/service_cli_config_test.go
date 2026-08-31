package upgrade

import (
	"os"
	"path/filepath"
	"testing"
)

// STATBUS-311: a CLI-built Service must know this box's channel.
//
// The reported symptom was `./sb upgrade check` printing
//
//	Found 203 release tag(s), none matching channel "" — nothing to register
//
// on demo, the first CONVERTED box. The report framed it as the conversion
// path's file shape breaking channel sourcing, since Ghana — born fresh at the
// same release — discovered correctly.
//
// IT IS NOT ABOUT CONVERSION. Reproduced on a born-fresh developer box whose
// .env carries UPGRADE_CHANNEL=local: the same empty channel. loadConfig() had
// only ever been called from Run() and LoadConfigAndConnect(), both daemon-side,
// so every CLI verb ran with the zero value. Ghana's working discovery came
// from its DAEMON; demo's failing check came from the CLI. The discriminator
// was never converted-vs-born — it was CLI-vs-daemon.
//
// These pins therefore cover BOTH file shapes, so neither can regress and so
// the record shows the converted shape was never the problem.

func writeEnvFor311(t *testing.T, dir, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(content), 0644); err != nil {
		t.Fatalf("write .env: %v", err)
	}
}

func TestLoadConfigForCLIResolvesChannel_STATBUS311(t *testing.T) {
	cases := []struct {
		name string
		env  string
		want string
	}{
		{
			// demo's shape: the derived key preceded by the converter's
			// provenance comment. Named as a suspect in the original report,
			// and pinned here so the suspicion is closed rather than left open.
			//
			// STATBUS-307 ERA-ACCURATE FIXTURE, deliberately not updated: this is
			// the .env text a box in the field ACTUALLY HAS today, written by a
			// pre-307 binary. The parser must keep reading it correctly after the
			// mechanism that wrote it is gone — that is the whole point of the
			// case. Rewriting it to the new provenance comment would test only
			// boxes that have already regenerated, which are the ones least at
			// risk.
			name: "converted box — derived key under its provenance comment",
			env: "# Upgrade service configuration\n" +
				"# Derived from UPGRADE_ROLE=production — set the role in .env.config, not this key.\n" +
				"UPGRADE_CHANNEL=stable\n" +
				"UPGRADE_CHECK_INTERVAL=6h\n",
			want: "stable",
		},
		{
			// Ghana's shape, and this developer box's.
			name: "born-fresh box",
			env:  "UPGRADE_CHANNEL=local\nUPGRADE_CHECK_INTERVAL=6h\n",
			want: "local",
		},
		{
			// loadConfig's own documented fallback: absent key → "stable" plus a
			// loud warning. Asserted so the fallback stays a CHOICE and never
			// silently becomes the empty string this ticket is about.
			name: "key absent entirely — conservative fallback, never empty",
			env:  "UPGRADE_CHECK_INTERVAL=6h\n",
			want: "stable",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			writeEnvFor311(t, dir, c.env)

			d := NewService(dir, false, "dev", "unknown")
			if got := d.ChannelForTest(); got != "" {
				t.Fatalf("a freshly constructed Service already had channel %q — this test cannot "+
					"show that loading is what sets it", got)
			}
			if err := d.LoadConfigForCLI(); err != nil {
				t.Fatalf("LoadConfigForCLI: %v", err)
			}
			if got := d.ChannelForTest(); got != c.want {
				t.Errorf("channel = %q, want %q.\n"+
					"An empty channel matches NO release tag, so discovery silently finds nothing "+
					"and the box goes dark for future releases.", got, c.want)
			}
		})
	}
}

// TestChannelIsNeverSilentlyEmpty_STATBUS311 is the property that actually
// matters, stated directly: after loading, the channel is never "".
//
// Every other assertion here is about a particular file shape. This one holds
// for any shape at all — including ones nobody has thought of — because the
// failure mode is not "wrong channel", it is "empty channel", which matches
// nothing and reports nothing wrong.
func TestChannelIsNeverSilentlyEmpty_STATBUS311(t *testing.T) {
	for _, env := range []string{
		"",
		"# only a comment\n",
		"UNRELATED=1\n",
		"UPGRADE_CHANNEL=stable\n",
		// Era-accurate: a pre-307 .env still on disk. See the note above.
		"# Derived from UPGRADE_ROLE=canary — set the role in .env.config, not this key.\nUPGRADE_CHANNEL=prerelease\n",
	} {
		dir := t.TempDir()
		writeEnvFor311(t, dir, env)
		d := NewService(dir, false, "dev", "unknown")
		if err := d.LoadConfigForCLI(); err != nil {
			t.Fatalf("LoadConfigForCLI(%q): %v", env, err)
		}
		if d.ChannelForTest() == "" {
			t.Errorf("channel is EMPTY after loading .env %q — an empty channel matches no tag, "+
				"so the box discovers nothing while reporting success", env)
		}
	}
}
