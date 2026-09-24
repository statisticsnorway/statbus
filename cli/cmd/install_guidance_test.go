package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLaptopModeDefault(t *testing.T) {
	root := t.TempDir()
	if installIsLaptopAt(root) {
		t.Fatal("server classified as laptop")
	}
	if err := os.Mkdir(filepath.Join(root, "BAT0"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "BAT0", "type"), []byte("Battery\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if !installIsLaptopAt(root) {
		t.Fatal("battery-backed laptop not detected")
	}
}
