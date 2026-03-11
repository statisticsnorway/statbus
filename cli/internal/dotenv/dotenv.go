// Package dotenv provides a format-preserving .env file parser.
//
// It preserves comments, blank lines, leading whitespace, inline comments,
// and original line ordering — enabling safe round-trip read/modify/write
// without disturbing unrelated lines.
//
// Ported from the Crystal implementation in cli/src/dotenv.cr.
package dotenv

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

// lineKind distinguishes the types of lines in a .env file.
type lineKind int

const (
	kindBlank   lineKind = iota
	kindComment          // full-line comment (starts with #)
	kindInvalid          // malformed line preserved as-is
	kindKeyVal           // KEY=VALUE with optional whitespace/quote/inline comment
)

// line represents a single line in a .env file.
type line struct {
	kind              lineKind
	raw               string // original text (used for blank/comment/invalid)
	key               string
	value             string
	leadingWhitespace string
	inlineComment     string // includes leading spaces, e.g. " # comment"
	quote             byte   // 0, '"', or '\''
}

// String reconstructs the line for writing back to the file.
func (l *line) String() string {
	switch l.kind {
	case kindKeyVal:
		var val string
		if l.quote != 0 {
			val = string(l.quote) + l.value + string(l.quote)
		} else {
			val = l.value
		}
		return l.leadingWhitespace + l.key + "=" + val + l.inlineComment
	default:
		return l.raw
	}
}

// kvRegex matches: optional_whitespace KEY = VALUE optional_inline_comment
var kvRegex = regexp.MustCompile(`^(\s*)([^#=]+)=([^#]*?)(\s+#.*)?$`)

// parseLine classifies and parses a single .env line.
func parseLine(raw string) *line {
	trimmed := strings.TrimSpace(raw)

	if trimmed == "" {
		return &line{kind: kindBlank, raw: raw}
	}
	if strings.HasPrefix(trimmed, "#") {
		return &line{kind: kindComment, raw: raw}
	}

	m := kvRegex.FindStringSubmatch(raw)
	if m == nil {
		return &line{kind: kindInvalid, raw: raw}
	}

	ws := m[1]
	key := strings.TrimSpace(m[2])
	val := m[3]
	comment := m[4] // may be ""

	var q byte
	if len(val) >= 2 {
		first, last := val[0], val[len(val)-1]
		if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
			q = first
			val = val[1 : len(val)-1]
		}
	}

	return &line{
		kind:              kindKeyVal,
		key:               key,
		value:             val,
		leadingWhitespace: ws,
		inlineComment:     comment,
		quote:             q,
	}
}

// File represents a parsed .env file with format-preserving read/modify/write.
type File struct {
	lines   []*line
	mapping map[string]*line // key → most recent KeyValueLine
	path    string           // empty when parsed from string
	Verbose bool
}

// Load reads and parses a .env file from disk.
// If the file does not exist, an empty File is returned (no error).
func Load(path string) (*File, error) {
	f := &File{path: path, mapping: make(map[string]*line)}

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return f, nil
	}
	if err != nil {
		return nil, fmt.Errorf("dotenv: read %s: %w", path, err)
	}

	f.parseContent(string(data))
	return f, nil
}

// FromString parses .env content from a string (no file backing).
func FromString(content string) *File {
	f := &File{mapping: make(map[string]*line)}
	f.parseContent(content)
	return f
}

// parseContent splits content into lines and classifies each one.
func (f *File) parseContent(content string) {
	f.lines = nil
	f.mapping = make(map[string]*line)

	for _, raw := range strings.Split(content, "\n") {
		l := parseLine(raw)
		f.lines = append(f.lines, l)
		if l.kind == kindKeyVal {
			f.mapping[l.key] = l
		}
	}
}

// Get returns the value for key, or ("", false) if not found.
func (f *File) Get(key string) (string, bool) {
	l, ok := f.mapping[key]
	if !ok {
		return "", false
	}
	return l.value, true
}

// Set creates or updates a key-value pair.
// If value starts with "+", it's treated as a default — only set if key is absent.
func (f *File) Set(key, value string) {
	if strings.HasPrefix(value, "+") {
		defaultVal := value[1:]
		if _, exists := f.mapping[key]; exists {
			return // keep existing
		}
		value = defaultVal
	}

	if existing, ok := f.mapping[key]; ok {
		existing.value = value
		return
	}

	l := &line{
		kind:  kindKeyVal,
		key:   key,
		value: value,
	}
	f.lines = append(f.lines, l)
	f.mapping[key] = l
}

// Delete removes a key. Returns true if the key existed.
func (f *File) Delete(key string) bool {
	l, ok := f.mapping[key]
	if !ok {
		return false
	}
	delete(f.mapping, key)
	// Convert to an invalid line so it's removed from output but indices stay stable.
	l.kind = kindBlank
	l.raw = ""
	return true
}

// Parse returns key-value pairs. If keys is empty, returns all.
// If keys are specified, only those keys are returned.
func (f *File) Parse(keys ...string) map[string]string {
	result := make(map[string]string)
	if len(keys) == 0 {
		for k, l := range f.mapping {
			result[k] = l.value
		}
		return result
	}

	keySet := make(map[string]struct{}, len(keys))
	for _, k := range keys {
		keySet[k] = struct{}{}
	}
	for k, l := range f.mapping {
		if _, ok := keySet[k]; ok {
			result[k] = l.value
		}
	}
	return result
}

// Export sets all key-value pairs as OS environment variables.
func (f *File) Export() {
	for k, l := range f.mapping {
		os.Setenv(k, l.value)
	}
}

// Generate sets key to the result of fn() only if the key doesn't already exist.
// Returns the value (existing or newly generated).
func (f *File) Generate(key string, fn func() (string, error)) (string, error) {
	if l, ok := f.mapping[key]; ok {
		return l.value, nil
	}
	val, err := fn()
	if err != nil {
		return "", err
	}
	f.Set(key, val)
	return val, nil
}

// Puts appends a raw line to the file content and re-parses it.
func (f *File) Puts(raw string) {
	l := parseLine(raw)
	f.lines = append(f.lines, l)
	if l.kind == kindKeyVal {
		f.mapping[l.key] = l
	}
}

// String renders the full file content, preserving original formatting.
func (f *File) String() string {
	parts := make([]string, len(f.lines))
	for i, l := range f.lines {
		parts[i] = l.String()
	}
	return strings.Join(parts, "\n")
}

// Save writes the file content back to disk.
// Returns an error if the File was parsed from a string (no path).
func (f *File) Save() error {
	if f.path == "" {
		return fmt.Errorf("dotenv: cannot save — no file path (parsed from string)")
	}
	return os.WriteFile(f.path, []byte(f.String()), 0644)
}

// Path returns the file path, or "" if parsed from string.
func (f *File) Path() string {
	return f.path
}

// Keys returns all keys in insertion order.
func (f *File) Keys() []string {
	var keys []string
	seen := make(map[string]struct{})
	for _, l := range f.lines {
		if l.kind == kindKeyVal {
			if _, ok := seen[l.key]; !ok {
				keys = append(keys, l.key)
				seen[l.key] = struct{}{}
			}
		}
	}
	return keys
}
