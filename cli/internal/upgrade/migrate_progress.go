package upgrade

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

type filteredLineWriter struct {
	mu     sync.Mutex
	dst    io.Writer
	filter func(string) bool
	buf    []byte
}

func newFilteredLineWriter(dst io.Writer, filter func(string) bool) *filteredLineWriter {
	return &filteredLineWriter{dst: dst, filter: filter}
}

func (w *filteredLineWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, b := range p {
		if b == '\n' {
			if err := w.emit(); err != nil {
				return 0, err
			}
			continue
		}
		w.buf = append(w.buf, b)
	}
	return len(p), nil
}

func (w *filteredLineWriter) Flush() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if len(w.buf) == 0 {
		return nil
	}
	return w.emit()
}

func (w *filteredLineWriter) emit() error {
	line := string(w.buf)
	w.buf = w.buf[:0]
	if w.filter != nil && w.filter(line) {
		return nil
	}
	_, err := fmt.Fprintln(w.dst, line)
	return err
}

func envOverride(key, value string) []string {
	prefix := key + "="
	env := make([]string, 0, len(os.Environ())+1)
	for _, entry := range os.Environ() {
		if !strings.HasPrefix(entry, prefix) {
			env = append(env, entry)
		}
	}
	return append(env, prefix+value)
}

// runMigrateUpToLog is the ordinary streaming migrate subprocess plus one tiny
// machine-readable datum. The marker is consumed before stdout reaches the O
// stream, then returned to the parent for the single M-line summary.
func runMigrateUpToLog(dir string, timeout time.Duration, logWriter io.Writer, onAdvance func(), name string, args ...string) (int, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir
	cmd.Env = envOverride(migrate.PendingCountReportEnv, "1")

	outW := NewPrefixWriter("O", "migrate", logWriter, onAdvance)
	errW := NewPrefixWriter("E", "migrate", logWriter, onAdvance)
	pendingCount := 0
	countSeen := false
	stdout := newFilteredLineWriter(io.MultiWriter(os.Stdout, outW), func(line string) bool {
		count, ok := migrate.ParsePendingCountReport(line)
		if !ok {
			return false
		}
		pendingCount = count
		countSeen = true
		if onAdvance != nil {
			onAdvance()
		}
		return true
	})
	cmd.Stdout = stdout
	cmd.Stderr = io.MultiWriter(os.Stderr, errW)
	prepareCmd(cmd)

	err := cmd.Run()
	flushErr := stdout.Flush()
	outW.Flush()
	errW.Flush()
	if ctx.Err() == context.DeadlineExceeded {
		return 0, fmt.Errorf("%s %v after %s: %w", name, args, timeout, ErrCommandTimeout)
	}
	if err != nil {
		return 0, err
	}
	if flushErr != nil {
		return 0, fmt.Errorf("flush migrate output: %w", flushErr)
	}
	if !countSeen {
		return 0, fmt.Errorf("migrate subprocess did not report its pending count")
	}
	return pendingCount, nil
}
