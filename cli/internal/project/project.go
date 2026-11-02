// Package project locates the StatBus checkout an invocation belongs to.
//
// It is separate from internal/config so Docker command construction
// (internal/compose) and configuration generation can both resolve the
// checkout without one importing the other.
package project

import (
	"os"
	"path/filepath"
)

// Dir walks up from cwd looking for the .statbus marker file. Falls back to
// cwd if not found.
func Dir() string {
	dir, err := os.Getwd()
	if err != nil {
		return "."
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, ".statbus")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	// Fall back to cwd
	cwd, _ := os.Getwd()
	return cwd
}
