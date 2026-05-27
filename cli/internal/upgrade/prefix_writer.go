package upgrade

import (
	"fmt"
	"io"
	"sync"
	"time"
)

// PrefixWriter is a line-buffered io.Writer that prepends a log code, source
// name, and HH:MM:SS timestamp to each complete line before writing to dst.
// Format: `<code> <source> HH:MM:SS <content>\n`
//
// Each newline-terminated line is emitted via a single dst.Write call, which
// the kernel serialises on a shared file — safe for concurrent writers.
type PrefixWriter struct {
	mu     sync.Mutex
	dst    io.Writer
	code   string // "O" or "E"
	source string // e.g. "migrate", "git", "docker-compose"
	buf    []byte
	// onLine, if non-nil, fires once per completed (newline-terminated or
	// flushed) line. The #3 progress-gated watchdog (plan
	// upgrade-resume-structural-whole.md) passes ProgressLog.bump here so every
	// line of a subprocess's output (docker pull layer lines, rsync file lines,
	// the tar's --checkpoint echoes) advances lastAdvanceAt — proving the step
	// is progressing. nil for non-tracked callers (git, rollback paths).
	onLine func()
}

// NewPrefixWriter returns a PrefixWriter with the given code and source. onLine
// (nil-able) fires once per completed line — see the struct field doc.
func NewPrefixWriter(code, source string, dst io.Writer, onLine func()) *PrefixWriter {
	return &PrefixWriter{code: code, source: source, dst: dst, onLine: onLine}
}

func (w *PrefixWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, b := range p {
		if b == '\n' {
			line := fmt.Sprintf("%s %s %s %s\n", w.code, w.source, time.Now().Format("15:04:05"), string(w.buf))
			w.buf = w.buf[:0]
			w.dst.Write([]byte(line)) //nolint:errcheck
			if w.onLine != nil {
				w.onLine()
			}
		} else {
			w.buf = append(w.buf, b)
		}
	}
	return len(p), nil
}

// Flush emits any buffered content that did not end with a newline.
// Call after the subprocess exits to capture truncated last lines.
func (w *PrefixWriter) Flush() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if len(w.buf) > 0 {
		line := fmt.Sprintf("%s %s %s %s\n", w.code, w.source, time.Now().Format("15:04:05"), string(w.buf))
		w.buf = w.buf[:0]
		w.dst.Write([]byte(line)) //nolint:errcheck
		if w.onLine != nil {
			w.onLine()
		}
	}
}
