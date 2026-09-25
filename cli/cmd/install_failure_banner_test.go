package cmd

import (
	"os"
	"strings"
	"testing"
)

func TestSuccessfulInstallClearsBanner(t *testing.T) {
	body, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	source := string(body)
	if !strings.Contains(source, "stampInstallInvocationTracking(conn, logRelPath, installDir)") {
		t.Fatal("successful install does not stamp invocation tracking")
	}
	start := strings.Index(source, "func stampInstallInvocationTracking(")
	if start < 0 {
		t.Fatal("install stamp function missing")
	}
	end := strings.Index(source[start:], "\nfunc runInstallRetention(")
	if end < 0 {
		t.Fatal("install stamp function boundary missing")
	}
	stamp := source[start : start+end]
	for _, key := range []string{"install_last_error", "install_last_error_at", "install_last_bundle_path"} {
		if !strings.Contains(stamp, "('"+key+"', '')") {
			t.Errorf("successful install does not clear %s", key)
		}
	}
}
