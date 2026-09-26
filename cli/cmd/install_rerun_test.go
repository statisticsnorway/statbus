package cmd

import (
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
)

// The wrapper constructs the saved command before prerequisites or downloads.
func TestRerunCommandPreservesInvocationOptions(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		env  []string
		want []string
	}{
		{"stable", nil, nil, []string{"curl -fsSL https://statbus.org/install.sh | bash"}},
		{"prerelease", []string{"--channel", "prerelease"}, nil, []string{"--channel prerelease"}},
		{"unattended prerelease", []string{"--channel", "prerelease", "--non-interactive"}, []string{"STATBUS_ENV_CONFIG=/tmp/answers.env", "STATBUS_USERS_FILE=/tmp/users.yml"}, []string{"--channel prerelease", "--non-interactive", "STATBUS_ENV_CONFIG=/tmp/answers.env", "STATBUS_USERS_FILE=/tmp/users.yml"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			// Source the argument parsing prefix, stopping immediately after the command
			// is exported so this test needs neither network nor root privileges.
			source, err := os.ReadFile(thisRepoFile(t, "install.sh"))
			if err != nil {
				t.Fatal(err)
			}
			marker := "export STATBUS_INSTALL_RERUN_COMMAND\n"
			prefix, _, ok := strings.Cut(string(source), marker)
			if !ok {
				t.Fatal("rerun export missing")
			}
			script := prefix + marker + "printf '%s' \"$STATBUS_INSTALL_RERUN_COMMAND\"\n"
			command := exec.Command("bash", append([]string{"-s", "--"}, tc.args...)...)
			command.Stdin = strings.NewReader(script)
			command.Env = append(os.Environ(), tc.env...)
			output, err := command.CombinedOutput()
			if err != nil {
				t.Fatalf("wrapper parsing: %v: %s", err, output)
			}
			got := string(output)
			if !strings.HasPrefix(got, "curl -fsSL https://statbus.org/install.sh | ") || strings.Contains(got, "./sb install") {
				t.Errorf("not directory independent: %q", got)
			}
			for _, part := range tc.want {
				if !strings.Contains(got, part) {
					t.Errorf("%q missing %q", got, part)
				}
			}
			t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", got)
			if diskpolicy.RerunCommand() != got {
				t.Errorf("Go installer did not print saved command")
			}
		})
	}
}
