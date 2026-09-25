package cmd

import (
	"io"
	"os"
	"strings"
	"testing"
)

func TestPasswordMismatchRetriesWithoutDisclosure(t *testing.T) {
	answers := []string{"first-secret", "different-secret", "matching-secret", "matching-secret"}
	i := 0
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldStdout := os.Stdout
	os.Stdout = writer
	defer func() { os.Stdout = oldStdout }()
	value, err := askAdministratorPassword(func(label string) (string, error) {
		// Simulate the visible portion of a prompt while supplying secrets from
		// a fake input reader. Neither a retry nor success may disclose them.
		_, _ = io.WriteString(os.Stdout, label)
		answer := answers[i]
		i++
		return answer, nil
	})
	_ = writer.Close()
	output, readErr := io.ReadAll(reader)
	_ = reader.Close()
	if readErr != nil {
		t.Fatal(readErr)
	}
	for _, secret := range answers {
		if strings.Contains(string(output), secret) {
			t.Fatalf("administrator password disclosed in captured output")
		}
	}
	if err != nil || value != "matching-secret" || i != 4 {
		t.Fatalf("retry failed, err=%v, reads=%d", err, i)
	}
}

func TestAdministratorPasswordPipeRefusesBeforePrompt(t *testing.T) {
	stdin, input, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = stdin.Close() }()
	defer func() { _ = input.Close() }()
	stdout, output, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = stdout.Close() }()
	oldStdin, oldStdout := os.Stdin, os.Stdout
	os.Stdin, os.Stdout = stdin, output
	defer func() { os.Stdin, os.Stdout = oldStdin, oldStdout }()
	_, err = readAdministratorPassword("  Password (typing is hidden): ")
	_ = output.Close()
	printed, readErr := io.ReadAll(stdout)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if err == nil || len(printed) != 0 {
		t.Fatalf("non-TTY password read must fail before prompting; err=%v, output=%q", err, printed)
	}
}

// The install-recovery scenario runs this interaction against the released
// binary; this fixture also permits a local Expect PTY check without Docker.
func TestAdministratorPasswordPTYFixture(t *testing.T) {
	if os.Getenv("STATBUS_TEST_ADMIN_PTY") != "1" {
		t.Skip("requires an Expect PTY")
	}
	value, err := askAdministratorPassword(readAdministratorPassword)
	if err != nil || value != "test-install-password-2026" {
		t.Fatalf("private administrator password input failed: %v", err)
	}
}
