package cmd

import (
	"os"
	"path/filepath"
	"strings"
)

// A battery-backed Linux host is a practical local-development default.
// A server or VM without a battery retains the standalone default.
func installIsLaptop() bool {
	return installIsLaptopAt("/sys/class/power_supply")
}

func installIsLaptopAt(path string) bool {
	entries, err := os.ReadDir(path)
	if err != nil {
		return false
	}
	for _, entry := range entries {
		if !strings.HasPrefix(strings.ToUpper(entry.Name()), "BAT") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(path, entry.Name(), "type"))
		if err == nil && strings.TrimSpace(string(data)) == "Battery" {
			return true
		}
	}
	return false
}
