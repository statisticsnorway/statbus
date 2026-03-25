package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var usersCmd = &cobra.Command{
	Use:   "users",
	Short: "Manage StatBus users",
}

var usersCreateCmd = &cobra.Command{
	Use:   "create",
	Short: "Create users from .users.yml",
	Long: `Reads .users.yml from the project directory and creates each user
via the public.user_create() database function.

Each entry in .users.yml should have:
  - email: user@example.com
  - display_name: User Name
  - password: secretpassword
  - role: admin_user | regular_user | restricted_user | external_user`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		usersFile := filepath.Join(projDir, ".users.yml")

		if _, err := os.Stat(usersFile); os.IsNotExist(err) {
			return fmt.Errorf(".users.yml not found in %s", projDir)
		}

		// Use psql to call user_create for each user
		// Parse YAML and generate SQL
		data, err := os.ReadFile(usersFile)
		if err != nil {
			return fmt.Errorf("read .users.yml: %w", err)
		}

		sql, err := usersYAMLToSQL(string(data))
		if err != nil {
			return err
		}

		psqlArgs, env, err := migrate.PsqlArgs(projDir)
		if err != nil {
			return err
		}

		return runPsqlSQL(projDir, psqlArgs, env, sql)
	},
}

// usersYAMLToSQL parses simple YAML user entries and generates SQL.
// Handles the basic format:
//
//	- email: user@example.com
//	  display_name: User Name
//	  password: secret
//	  role: admin_user
func usersYAMLToSQL(yaml string) (string, error) {
	type userEntry struct {
		email       string
		displayName string
		password    string
		role        string
	}

	var users []userEntry
	var current userEntry
	inEntry := false

	lines := splitLines(yaml)
	for _, line := range lines {
		trimmed := trimString(line)
		if trimmed == "" || trimmed[0] == '#' {
			continue
		}

		if len(trimmed) > 2 && trimmed[0] == '-' && trimmed[1] == ' ' {
			if inEntry {
				users = append(users, current)
			}
			current = userEntry{role: "regular_user"}
			inEntry = true
			trimmed = trimString(trimmed[2:])
		}

		key, val := parseYAMLKV(trimmed)
		switch key {
		case "email":
			current.email = val
		case "display_name":
			current.displayName = val
		case "password":
			current.password = val
		case "role":
			current.role = val
		}
	}
	if inEntry {
		users = append(users, current)
	}

	if len(users) == 0 {
		return "", fmt.Errorf("no users found in .users.yml")
	}

	var sql string
	for _, u := range users {
		if u.email == "" || u.displayName == "" || u.password == "" {
			return "", fmt.Errorf("user entry missing required fields (email, display_name, password)")
		}
		sql += fmt.Sprintf(
			"SELECT * FROM public.user_create(p_display_name => %s, p_email => %s, p_statbus_role => %s, p_password => %s);\n",
			pgQuote(u.displayName), pgQuote(u.email), pgQuote(u.role), pgQuote(u.password))
	}

	return sql, nil
}

func pgQuote(s string) string {
	// Escape single quotes by doubling them
	escaped := ""
	for _, c := range s {
		if c == '\'' {
			escaped += "''"
		} else {
			escaped += string(c)
		}
	}
	return "'" + escaped + "'"
}

func parseYAMLKV(line string) (string, string) {
	for i, c := range line {
		if c == ':' {
			key := trimString(line[:i])
			val := trimString(line[i+1:])
			// Strip quotes
			if len(val) >= 2 && ((val[0] == '"' && val[len(val)-1] == '"') || (val[0] == '\'' && val[len(val)-1] == '\'')) {
				val = val[1 : len(val)-1]
			}
			return key, val
		}
	}
	return line, ""
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

func trimString(s string) string {
	start := 0
	for start < len(s) && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r') {
		start++
	}
	end := len(s)
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
}

func runPsqlSQL(projDir string, psqlArgs []string, env []string, sql string) error {
	psqlPath, err := exec.LookPath("psql")
	if err != nil {
		return fmt.Errorf("psql not found: %w", err)
	}
	args := append(psqlArgs[1:], "-v", "ON_ERROR_STOP=on")
	cmd := exec.Command(psqlPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	cmd.Stdin = strings.NewReader(sql)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func init() {
	usersCmd.AddCommand(usersCreateCmd)
	rootCmd.AddCommand(usersCmd)
}
