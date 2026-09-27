package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestServiceFailureWithJournal(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "journalctl")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nprintf '%s\\n' \"$*\"\nprintf '%s\\n' 'service root cause'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, tc := range []struct {
		name string
		user bool
		want string
	}{{"user", true, "--user -u statbus-upgrade@statbus.service -n 40 --no-pager"}, {"system", false, "-u statbus-upgrade@statbus.service -n 40 --no-pager"}} {
		t.Run(tc.name, func(t *testing.T) {
			cause := errors.New("start timed out")
			err := serviceFailureWithJournal("enable service", "statbus-upgrade@statbus.service", tc.user, cause)
			if !errors.Is(err, cause) || !strings.Contains(err.Error(), tc.want) || !strings.Contains(err.Error(), "service root cause") {
				t.Fatalf("missing journal or cause: %v", err)
			}
		})
	}
}
