package upgrade

import (
	"context"
	"fmt"
	"io"
	"os"
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
// stream and returned to the parent. narrate (nil-able, ProgressLog.Write)
// receives the M lines the migrate narrator derives from the child's stdout:
// the pending count before the first migration, each migration's start and
// result, and a still-running line every 30 s.
func runMigrateUpToLog(dir string, timeout time.Duration, logWriter io.Writer, onAdvance func(), narrate func(string, ...interface{}), args ...string) (int, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd, buildErr := commandContext(ctx, dir, "./sb", args...)
	if buildErr != nil {
		return 0, buildErr
	}
	cmd.Env = envOverride(migrate.PendingCountReportEnv, "1")

	outW := NewPrefixWriter("O", "migrate", logWriter, onAdvance)
	errW := NewPrefixWriter("E", "migrate", logWriter, onAdvance)
	pendingCount := 0
	countSeen := false
	var narrator *migrateNarrator
	if narrate != nil {
		narrator = newMigrateNarrator(narrate, time.Now)
	}
	stdout := narratingStdout(outW, narrator, func(count int) {
		pendingCount = count
		countSeen = true
		if onAdvance != nil {
			onAdvance()
		}
	})
	cmd.Stdout = stdout
	cmd.Stderr = io.MultiWriter(os.Stderr, errW)
	prepareCmd(cmd)

	tickDone := make(chan struct{})
	if narrator != nil {
		go runNarratorTicker(narrator, tickDone)
	}
	err := cmd.Run()
	close(tickDone)
	flushErr := stdout.Flush()
	outW.Flush()
	errW.Flush()
	if ctx.Err() == context.DeadlineExceeded {
		return 0, fmt.Errorf("./sb %v after %s: %w", args, timeout, ErrCommandTimeout)
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

// narratingStdout returns the migrate child's stdout writer for the upgrade's
// progress log: every line reaches the journal (os.Stdout) and the O stream
// (outW) unchanged, except the pending-count datum, and the narrator turns the
// step lines into M lines (migrate_narrator.go). A nil narrator only filters.
func narratingStdout(outW io.Writer, narrator *migrateNarrator, onCount func(int)) *filteredLineWriter {
	return newFilteredLineWriter(io.MultiWriter(os.Stdout, outW), func(line string) bool {
		if narrator != nil {
			narrator.Line(line)
		}
		count, ok := migrate.ParsePendingCountReport(line)
		if ok && onCount != nil {
			onCount(count)
		}
		return ok
	})
}

// runMigrateFloorNarrated is the boot/claim floor migrate (`./sb migrate up
// --to <floor>`) with its step lines narrated as M lines on progress, so a slow
// extension update or floor migration during a recovery boot shows on the
// maintenance page. Returns the stderr tail like runCommandToLogCapture. A nil
// progress narrates to the journal only (ProgressLog.Write is nil-safe).
func runMigrateFloorNarrated(dir string, timeout time.Duration, progress *ProgressLog, source string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd, buildErr := commandContext(ctx, dir, "./sb", args...)
	if buildErr != nil {
		return "", buildErr
	}
	tail := &tailBuffer{max: 4096}
	outW := NewPrefixWriter("O", source, progress.File(), progress.bump)
	errW := NewPrefixWriter("E", source, progress.File(), progress.bump)
	var narrator *migrateNarrator
	if progress != nil {
		narrator = newMigrateNarrator(progress.Write, time.Now)
	}
	stdout := narratingStdout(outW, narrator, nil)
	cmd.Stdout = stdout
	cmd.Stderr = io.MultiWriter(os.Stderr, errW, tail)
	prepareCmd(cmd)
	tickDone := make(chan struct{})
	if narrator != nil {
		go runNarratorTicker(narrator, tickDone)
	}
	err := cmd.Run()
	close(tickDone)
	_ = stdout.Flush()
	outW.Flush()
	errW.Flush()
	if ctx.Err() == context.DeadlineExceeded {
		return tail.String(), fmt.Errorf("./sb %v after %s: %w", args, timeout, ErrCommandTimeout)
	}
	return tail.String(), err
}
