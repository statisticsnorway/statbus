package cmd

import (
	"bytes"
	"os"
)

// sameFileContent reports whether two files hold identical bytes. It answers
// "does the upgrader's running program equal the ./sb on disk?" for
// `sb upgrader status` (observeUpgrader).
func sameFileContent(a, b string) (bool, error) {
	ab, err := os.ReadFile(a)
	if err != nil {
		return false, err
	}
	bb, err := os.ReadFile(b)
	if err != nil {
		return false, err
	}
	return bytes.Equal(ab, bb), nil
}
