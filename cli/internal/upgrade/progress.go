package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// ProgressLog writes timestamped progress to a log file.
type ProgressLog struct {
	path string
	file *os.File
}

// NewProgressLog creates a progress log in projDir/tmp/.
func NewProgressLog(projDir string) *ProgressLog {
	dir := filepath.Join(projDir, "tmp")
	os.MkdirAll(dir, 0755)

	path := filepath.Join(dir, "upgrade-progress.log")
	f, err := os.Create(path)
	if err != nil {
		return &ProgressLog{path: path}
	}

	return &ProgressLog{path: path, file: f}
}

// Write appends a timestamped line.
func (p *ProgressLog) Write(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	line := fmt.Sprintf("[%s] %s\n", time.Now().Format("15:04:05"), msg)

	fmt.Print(line)

	if p.file != nil {
		p.file.WriteString(line)
		p.file.Sync()
	}
}

// Close closes the log file.
func (p *ProgressLog) Close() {
	if p.file != nil {
		p.file.Close()
	}
}
