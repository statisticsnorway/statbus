package dotenv

import (
	"os"
	"path/filepath"
	"testing"
)

func withTempFile(t *testing.T, content string, fn func(path string)) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, ".env-test")
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	fn(path)
}

func TestLoadEmptyFile(t *testing.T) {
	withTempFile(t, "", func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		if len(f.Parse()) != 0 {
			t.Error("expected empty parse result")
		}
	})
}

func TestLoadBasicKeyValuePairs(t *testing.T) {
	content := "KEY1=value1\nKEY2=value2"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		assertGet(t, f, "KEY1", "value1")
		assertGet(t, f, "KEY2", "value2")
	})
}

func TestPreservesComments(t *testing.T) {
	content := "# This is a comment\nKEY1=value1\n# Another comment\nKEY2=value2"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		if f.lines[0].kind != kindComment {
			t.Errorf("line 0: expected comment, got %v", f.lines[0].kind)
		}
		if f.lines[2].kind != kindComment {
			t.Errorf("line 2: expected comment, got %v", f.lines[2].kind)
		}
	})
}

func TestPreservesBlankLines(t *testing.T) {
	content := "KEY1=value1\n\nKEY2=value2"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		if f.lines[1].kind != kindBlank {
			t.Errorf("line 1: expected blank, got %v", f.lines[1].kind)
		}
	})
}

func TestHandlesInlineComments(t *testing.T) {
	content := "KEY=value # inline comment"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		l := f.lines[0]
		if l.key != "KEY" {
			t.Errorf("key = %q, want KEY", l.key)
		}
		if l.value != "value" {
			t.Errorf("value = %q, want value", l.value)
		}
		if l.inlineComment != " # inline comment" {
			t.Errorf("inlineComment = %q, want %q", l.inlineComment, " # inline comment")
		}
	})
}

func TestHandlesInlineCommentsWithLotsOfSpace(t *testing.T) {
	content := "KEY=value                  # inline comment"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		l := f.lines[0]
		if l.key != "KEY" {
			t.Errorf("key = %q, want KEY", l.key)
		}
		if l.value != "value" {
			t.Errorf("value = %q, want value", l.value)
		}
		if l.inlineComment != "                  # inline comment" {
			t.Errorf("inlineComment = %q, want %q", l.inlineComment, "                  # inline comment")
		}
	})
}

func TestSetAddsNewKeyValue(t *testing.T) {
	withTempFile(t, "", func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		f.Set("NEW_KEY", "new_value")
		assertGet(t, f, "NEW_KEY", "new_value")
	})
}

func TestSetUpdatesExistingKeyValue(t *testing.T) {
	withTempFile(t, "EXISTING=old_value", func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		f.Set("EXISTING", "new_value")
		assertGet(t, f, "EXISTING", "new_value")
	})
}

func TestSetDefaultWithPlusPrefix(t *testing.T) {
	withTempFile(t, "EXISTING=old_value", func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		// Existing key: + prefix should not overwrite
		f.Set("EXISTING", "+default_value")
		assertGet(t, f, "EXISTING", "old_value")

		// New key: + prefix should set the default
		f.Set("NEW_KEY", "+default_value")
		assertGet(t, f, "NEW_KEY", "default_value")
	})
}

func TestParseReturnsAllWhenNoKeysSpecified(t *testing.T) {
	content := "KEY1=value1\nKEY2=value2"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		parsed := f.Parse()
		if parsed["KEY1"] != "value1" || parsed["KEY2"] != "value2" {
			t.Errorf("Parse() = %v", parsed)
		}
	})
}

func TestParseReturnsOnlySpecifiedKeys(t *testing.T) {
	content := "KEY1=value1\nKEY2=value2\nKEY3=value3"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		parsed := f.Parse("KEY1", "KEY3")
		if parsed["KEY1"] != "value1" {
			t.Errorf("KEY1 = %q, want value1", parsed["KEY1"])
		}
		if parsed["KEY3"] != "value3" {
			t.Errorf("KEY3 = %q, want value3", parsed["KEY3"])
		}
		if _, ok := parsed["KEY2"]; ok {
			t.Error("KEY2 should not be in result")
		}
	})
}

func TestExportSetsEnvVars(t *testing.T) {
	content := "EXPORT_TEST_GO=test_value"
	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		f.Export()
		if got := os.Getenv("EXPORT_TEST_GO"); got != "test_value" {
			t.Errorf("ENV EXPORT_TEST_GO = %q, want test_value", got)
		}
	})
}

func TestGenerateNewKey(t *testing.T) {
	withTempFile(t, "", func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		val, err := f.Generate("TIMESTAMP", func() (string, error) {
			return "test_time", nil
		})
		if err != nil {
			t.Fatal(err)
		}
		if val != "test_time" {
			t.Errorf("Generate returned %q, want test_time", val)
		}
		assertGet(t, f, "TIMESTAMP", "test_time")
	})
}

func TestGenerateExistingKey(t *testing.T) {
	withTempFile(t, "TIMESTAMP=existing_time", func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		val, err := f.Generate("TIMESTAMP", func() (string, error) {
			return "new_time", nil
		})
		if err != nil {
			t.Fatal(err)
		}
		if val != "existing_time" {
			t.Errorf("Generate returned %q, want existing_time", val)
		}
	})
}

func TestRoundtripPreservesFormatting(t *testing.T) {
	content := `# Header comment

# Another comment
   # Indented comment
EMPTY=
SPACES=   spaced   value   # With trailing comment
QUOTES="quoted value"
ESCAPED=escaped\"quote
NEWLINES=multi\nline
KEY=value # inline comment
DUPE=first
DUPE=second # second one wins
=invalid_no_key
invalid_no_equals
   INDENTED=value`

	withTempFile(t, content, func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}

		// Verify specific aspects
		if f.lines[0].kind != kindComment {
			t.Error("line 0 should be comment")
		}
		if f.lines[1].kind != kindBlank {
			t.Error("line 1 should be blank")
		}

		// EMPTY=
		empty := f.lines[4]
		if empty.key != "EMPTY" || empty.value != "" {
			t.Errorf("EMPTY: key=%q value=%q", empty.key, empty.value)
		}

		// SPACES with inline comment
		spaces := f.lines[5]
		if spaces.key != "SPACES" || spaces.value != "   spaced   value" {
			t.Errorf("SPACES: key=%q value=%q", spaces.key, spaces.value)
		}
		if spaces.inlineComment != "   # With trailing comment" {
			t.Errorf("SPACES inline comment = %q", spaces.inlineComment)
		}

		// QUOTES
		quotes := f.lines[6]
		if quotes.key != "QUOTES" || quotes.value != "quoted value" || quotes.quote != '"' {
			t.Errorf("QUOTES: key=%q value=%q quote=%c", quotes.key, quotes.value, quotes.quote)
		}

		// ESCAPED
		escaped := f.lines[7]
		if escaped.key != "ESCAPED" || escaped.value != `escaped\"quote` {
			t.Errorf("ESCAPED: key=%q value=%q", escaped.key, escaped.value)
		}

		// KEY with inline comment
		inline := f.lines[9]
		if inline.key != "KEY" || inline.value != "value" || inline.inlineComment != " # inline comment" {
			t.Errorf("KEY: key=%q value=%q comment=%q", inline.key, inline.value, inline.inlineComment)
		}

		// Duplicate handling: last wins
		val, ok := f.Get("DUPE")
		if !ok || val != "second" {
			t.Errorf("DUPE = %q, want second", val)
		}

		// Save and reload
		if err := f.Save(); err != nil {
			t.Fatal(err)
		}
		reloaded, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}

		if reloaded.String() != content {
			t.Errorf("roundtrip mismatch:\n--- got ---\n%s\n--- want ---\n%s", reloaded.String(), content)
		}
	})
}

func TestLoadNonexistentFile(t *testing.T) {
	f, err := Load("/tmp/nonexistent-dotenv-test-file")
	if err != nil {
		t.Fatal("should not error on missing file")
	}
	if len(f.Parse()) != 0 {
		t.Error("expected empty parse")
	}
}

func TestFromString(t *testing.T) {
	f := FromString("KEY=value\nOTHER=123")
	assertGet(t, f, "KEY", "value")
	assertGet(t, f, "OTHER", "123")
}

func TestSaveAndReload(t *testing.T) {
	withTempFile(t, "KEY=value", func(path string) {
		f, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		f.Set("KEY", "new_value")
		if err := f.Save(); err != nil {
			t.Fatal(err)
		}

		reloaded, err := Load(path)
		if err != nil {
			t.Fatal(err)
		}
		assertGet(t, reloaded, "KEY", "new_value")
	})
}

func TestSaveFromStringErrors(t *testing.T) {
	f := FromString("KEY=value")
	if err := f.Save(); err == nil {
		t.Error("Save from string should error")
	}
}

func TestKeys(t *testing.T) {
	f := FromString("B=2\nA=1\nC=3")
	keys := f.Keys()
	if len(keys) != 3 || keys[0] != "B" || keys[1] != "A" || keys[2] != "C" {
		t.Errorf("Keys() = %v, want [B A C]", keys)
	}
}

func TestDelete(t *testing.T) {
	f := FromString("A=1\nB=2\nC=3")
	if !f.Delete("B") {
		t.Error("Delete should return true for existing key")
	}
	if _, ok := f.Get("B"); ok {
		t.Error("B should be gone after Delete")
	}
	if f.Delete("NONEXISTENT") {
		t.Error("Delete should return false for nonexistent key")
	}
}

// assertGet is a test helper that checks Get returns the expected value.
func assertGet(t *testing.T, f *File, key, want string) {
	t.Helper()
	got, ok := f.Get(key)
	if !ok {
		t.Errorf("Get(%q): key not found", key)
		return
	}
	if got != want {
		t.Errorf("Get(%q) = %q, want %q", key, got, want)
	}
}
