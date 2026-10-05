package upgrade

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	statbusconfig "github.com/statisticsnorway/statbus/cli/internal/config"
)

func prepareLegacyConfigFixture(t *testing.T, release string) (string, []byte, []byte) {
	t.Helper()
	dir := t.TempDir()
	fixtureDir := filepath.Join("..", "config", "testdata", "legacy-config", release)
	for _, name := range []string{".env.config", ".env.credentials"} {
		contents, err := os.ReadFile(filepath.Join(fixtureDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, name), contents, 0600); err != nil {
			t.Fatal(err)
		}
	}
	repoRoot := filepath.Join("..", "..", "..")
	example, err := os.ReadFile(filepath.Join(repoRoot, ".env.example"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".env.example"), example, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.CopyFS(filepath.Join(dir, "caddy", "templates"), os.DirFS(filepath.Join(repoRoot, "caddy", "templates"))); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "ops", "maintenance"), 0755); err != nil {
		t.Fatal(err)
	}
	configBefore, err := os.ReadFile(filepath.Join(dir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	credentialsBefore, err := os.ReadFile(filepath.Join(dir, ".env.credentials"))
	if err != nil {
		t.Fatal(err)
	}
	return dir, configBefore, credentialsBefore
}

func TestOperatorConfigSnapshotRestoresLegacyPlacementAfterTargetMigration(t *testing.T) {
	for _, release := range []string{"v2026.08.0", "v2026.09.0", "v2026.09.2"} {
		t.Run(release, func(t *testing.T) {
			projDir, configBefore, credentialsBefore := prepareLegacyConfigFixture(t, release)
			backupPath := filepath.Join(t.TempDir(), backupSyncingName)
			if err := os.Mkdir(backupPath, 0700); err != nil {
				t.Fatal(err)
			}
			if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
				t.Fatal(err)
			}
			if err := statbusconfig.GenerateForInstallInDir(projDir, false); err != nil {
				t.Fatal(err)
			}
			migratedConfig, err := os.ReadFile(filepath.Join(projDir, ".env.config"))
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(string(migratedConfig), "SLACK_TOKEN=fixture-slack_token") || strings.Contains(string(migratedConfig), "SEQ_API_KEY=fixture-seq_api_key") {
				t.Fatalf("target migration did not move legacy tokens: %s", migratedConfig)
			}
			if err := restoreOperatorConfig(projDir, backupPath); err != nil {
				t.Fatal(err)
			}
			assertFileBytes(t, filepath.Join(projDir, ".env.config"), configBefore)
			assertFileBytes(t, filepath.Join(projDir, ".env.credentials"), credentialsBefore)
			credentialsInfo, err := os.Stat(filepath.Join(projDir, ".env.credentials"))
			if err != nil {
				t.Fatal(err)
			}
			if got := credentialsInfo.Mode().Perm(); got != 0600 {
				t.Fatalf("credentials mode = %o, want 600", got)
			}
		})
	}
}

func TestOperatorConfigSnapshotRestoresAbsentFiles(t *testing.T) {
	projDir := t.TempDir()
	backupPath := filepath.Join(t.TempDir(), backupActiveName)
	if err := os.Mkdir(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".env.config", ".env.credentials"} {
		if err := os.WriteFile(filepath.Join(projDir, name), []byte("target-era\n"), 0644); err != nil {
			t.Fatal(err)
		}
	}
	if err := restoreOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".env.config", ".env.credentials"} {
		if _, err := os.Stat(filepath.Join(projDir, name)); !os.IsNotExist(err) {
			t.Fatalf("%s exists after absence restore: %v", name, err)
		}
	}
}

func TestForwardCompletionKeepsMigratedConfig(t *testing.T) {
	projDir, configBefore, _ := prepareLegacyConfigFixture(t, "v2026.09.2")
	backupPath := filepath.Join(t.TempDir(), backupActiveName)
	if err := os.Mkdir(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	if err := statbusconfig.GenerateForInstallInDir(projDir, false); err != nil {
		t.Fatal(err)
	}
	configAfter, err := os.ReadFile(filepath.Join(projDir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Equal(configAfter, configBefore) {
		t.Fatal("forward completion restored the legacy config instead of keeping migrated placement")
	}
	if strings.Contains(string(configAfter), "SLACK_TOKEN=fixture-slack_token") || strings.Contains(string(configAfter), "SEQ_API_KEY=fixture-seq_api_key") {
		t.Fatalf("forward completion retained legacy token placement: %s", configAfter)
	}
	if _, err := os.Stat(operatorConfigSnapshotPath(backupPath)); err != nil {
		t.Fatalf("forward completion must leave the snapshot with its database backup lifecycle: %v", err)
	}
}

func TestNewSnapshotReplacesStaleOperatorConfig(t *testing.T) {
	backupPath := filepath.Join(t.TempDir(), backupSyncingName)
	if err := os.Mkdir(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	staleDir := operatorConfigSnapshotPath(backupPath)
	if err := os.Mkdir(staleDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staleDir, "env.credentials.present"), []byte("SLACK_TOKEN=stale\n"), 0600); err != nil {
		t.Fatal(err)
	}
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.config"), []byte("SITE_DOMAIN=fresh.example\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(staleDir, "env.credentials.present")); !os.IsNotExist(err) {
		t.Fatalf("stale credentials survived replacement: %v", err)
	}
	if err := restoreOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	assertFileBytes(t, filepath.Join(projDir, ".env.config"), []byte("SITE_DOMAIN=fresh.example\n"))
}

func TestSourceReturnOperatorConfigSnapshotDegradesWithoutBlocking(t *testing.T) {
	source := string(packageGoSources(t)["service.go"])
	for name, body := range map[string]string{
		"restoreSourceServices": extractFuncBody(t, source, "func (d *Service) restoreSourceServices("),
		"restoreAndFinalize":    extractFuncBody(t, source, "func (d *Service) restoreAndFinalize("),
	} {
		if !strings.Contains(body, "d.restoreOperatorConfigForSourceReturn(backupPath, progress)") {
			t.Fatalf("%s does not route operator-config restoration through the nonblocking source-return policy", name)
		}
	}

	cases := []struct {
		name           string
		prepareBackup  func(*testing.T, string)
		wantDiagnostic string
	}{
		{
			name:           "old backup without snapshot directory",
			prepareBackup:  func(*testing.T, string) {},
			wantDiagnostic: "OPERATOR_CONFIG_SNAPSHOT_UNAVAILABLE_OLD_BACKUP",
		},
		{
			name: "missing FORMAT",
			prepareBackup: func(t *testing.T, backupPath string) {
				t.Helper()
				snapshotPath := operatorConfigSnapshotPath(backupPath)
				if err := os.Mkdir(snapshotPath, 0700); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(snapshotPath, "env.config.absent"), nil, 0600); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(snapshotPath, "env.credentials.absent"), nil, 0600); err != nil {
					t.Fatal(err)
				}
			},
			wantDiagnostic: "OPERATOR_CONFIG_SNAPSHOT_DEGRADED",
		},
		{
			name: "ambiguous config presence",
			prepareBackup: func(t *testing.T, backupPath string) {
				t.Helper()
				snapshotPath := operatorConfigSnapshotPath(backupPath)
				if err := os.Mkdir(snapshotPath, 0700); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(snapshotPath, "FORMAT"), []byte(operatorConfigSnapshotFormat), 0600); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(snapshotPath, "env.credentials.absent"), nil, 0600); err != nil {
					t.Fatal(err)
				}
			},
			wantDiagnostic: "OPERATOR_CONFIG_SNAPSHOT_DEGRADED",
		},
	}
	for _, chokepoint := range []string{"restoreAndFinalize tail", "restoreSourceServices park"} {
		for _, tc := range cases {
			t.Run(chokepoint+"/"+tc.name, func(t *testing.T) {
				projDir := t.TempDir()
				backupPath := filepath.Join(t.TempDir(), backupActiveName)
				if err := os.Mkdir(backupPath, 0700); err != nil {
					t.Fatal(err)
				}
				configCurrent := []byte("SITE_DOMAIN=current.example\n")
				credentialsCurrent := []byte("SLACK_TOKEN=current\n")
				if err := os.WriteFile(filepath.Join(projDir, ".env.config"), configCurrent, 0644); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(projDir, ".env.credentials"), credentialsCurrent, 0600); err != nil {
					t.Fatal(err)
				}
				tc.prepareBackup(t, backupPath)

				d := &Service{projDir: projDir}
				output := captureOperatorConfigOutput(t, func() {
					d.restoreOperatorConfigForSourceReturn(backupPath, nil)
				})
				if !strings.Contains(output, tc.wantDiagnostic) || !strings.Contains(output, backupPath) {
					t.Fatalf("diagnostic = %q, want %q and backup path %q", output, tc.wantDiagnostic, backupPath)
				}
				assertFileBytes(t, filepath.Join(projDir, ".env.config"), configCurrent)
				assertFileBytes(t, filepath.Join(projDir, ".env.credentials"), credentialsCurrent)
			})
		}
	}
}

func TestOperatorConfigSnapshotRejectsInvalidLayoutBeforeMutation(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*testing.T, string)
	}{
		{name: "missing FORMAT", mutate: func(t *testing.T, path string) { mustRemove(t, filepath.Join(path, "FORMAT")) }},
		{name: "FORMAT trailing space", mutate: func(t *testing.T, path string) {
			mustWriteFile(t, filepath.Join(path, "FORMAT"), []byte("statbus-operator-config-snapshot v2 \n"))
		}},
		{name: "FORMAT v1", mutate: func(t *testing.T, path string) {
			mustWriteFile(t, filepath.Join(path, "FORMAT"), []byte("statbus-operator-config-snapshot v1\n"))
		}},
		{name: "FORMAT empty", mutate: func(t *testing.T, path string) { mustWriteFile(t, filepath.Join(path, "FORMAT"), nil) }},
		{name: "both present and absent", mutate: func(t *testing.T, path string) {
			mustWriteFile(t, filepath.Join(path, "env.config.present"), []byte("snapshot\n"))
		}},
		{name: "neither present nor absent", mutate: func(t *testing.T, path string) { mustRemove(t, filepath.Join(path, "env.config.absent")) }},
		{name: "absent marker non-empty", mutate: func(t *testing.T, path string) {
			mustWriteFile(t, filepath.Join(path, "env.config.absent"), []byte("not empty"))
		}},
		{name: "present entry is directory", mutate: func(t *testing.T, path string) {
			mustRemove(t, filepath.Join(path, "env.config.absent"))
			if err := os.Mkdir(filepath.Join(path, "env.config.present"), 0700); err != nil {
				t.Fatal(err)
			}
		}},
		{name: "present entry is symlink", mutate: func(t *testing.T, path string) {
			mustRemove(t, filepath.Join(path, "env.config.absent"))
			target := filepath.Join(t.TempDir(), "payload")
			mustWriteFile(t, target, []byte("snapshot\n"))
			if err := os.Symlink(target, filepath.Join(path, "env.config.present")); err != nil {
				t.Fatal(err)
			}
		}},
		{name: "unknown extra entry", mutate: func(t *testing.T, path string) { mustWriteFile(t, filepath.Join(path, "unexpected"), nil) }},
		{name: "case-variant extra entry", mutate: func(t *testing.T, path string) {
			mustWriteFile(t, filepath.Join(path, "ENV.CONFIG.ABSENT"), nil)
			entries, err := os.ReadDir(path)
			if err != nil {
				t.Fatal(err)
			}
			seenLower := false
			seenUpper := false
			for _, entry := range entries {
				seenLower = seenLower || entry.Name() == "env.config.absent"
				seenUpper = seenUpper || entry.Name() == "ENV.CONFIG.ABSENT"
			}
			if !seenLower || !seenUpper {
				t.Skip("filesystem cannot represent case-variant sibling names")
			}
		}},
		{name: "old JSON manifest", mutate: func(t *testing.T, path string) {
			manifest := `{"version":1,"env_config":{"Present":false},"env_credentials":{"present":false}}`
			mustWriteFile(t, filepath.Join(path, "manifest.json"), []byte(manifest))
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			projDir := t.TempDir()
			backupPath := filepath.Join(t.TempDir(), backupActiveName)
			snapshotPath := operatorConfigSnapshotPath(backupPath)
			writeAbsentOperatorConfigSnapshot(t, snapshotPath)
			tc.mutate(t, snapshotPath)

			configCurrent := []byte("SITE_DOMAIN=current.example\n")
			credentialsCurrent := []byte("SLACK_TOKEN=current\n")
			mustWriteFile(t, filepath.Join(projDir, ".env.config"), configCurrent)
			mustWriteFile(t, filepath.Join(projDir, ".env.credentials"), credentialsCurrent)

			d := &Service{projDir: projDir}
			output := captureOperatorConfigOutput(t, func() {
				d.restoreOperatorConfigForSourceReturn(backupPath, nil)
			})
			if !strings.Contains(output, "OPERATOR_CONFIG_SNAPSHOT_DEGRADED") {
				t.Fatalf("diagnostic = %q, want degraded diagnostic", output)
			}
			assertFileBytes(t, filepath.Join(projDir, ".env.config"), configCurrent)
			assertFileBytes(t, filepath.Join(projDir, ".env.credentials"), credentialsCurrent)
		})
	}
}

func TestOperatorConfigSnapshotExplicitAbsenceRemovesTargetCreatedFiles(t *testing.T) {
	projDir := t.TempDir()
	backupPath := filepath.Join(t.TempDir(), backupActiveName)
	snapshotPath := operatorConfigSnapshotPath(backupPath)
	writeAbsentOperatorConfigSnapshot(t, snapshotPath)
	for _, name := range []string{".env.config", ".env.credentials"} {
		if err := os.WriteFile(filepath.Join(projDir, name), []byte("target-created\n"), 0600); err != nil {
			t.Fatal(err)
		}
	}

	if err := restoreOperatorConfig(projDir, backupPath); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{".env.config", ".env.credentials"} {
		if _, err := os.Stat(filepath.Join(projDir, name)); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("%s exists after explicit absence restore: %v", name, err)
		}
	}
}

func TestOperatorConfigSnapshotWriterReaderRoundTrip(t *testing.T) {
	for _, tc := range []struct {
		name               string
		configPresent      bool
		credentialsPresent bool
	}{
		{name: "both present", configPresent: true, credentialsPresent: true},
		{name: "config present credentials absent", configPresent: true},
		{name: "config absent credentials present", credentialsPresent: true},
		{name: "both absent"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			projDir := t.TempDir()
			backupPath := filepath.Join(t.TempDir(), backupActiveName)
			if err := os.Mkdir(backupPath, 0700); err != nil {
				t.Fatal(err)
			}
			want := map[string][]byte{
				".env.config":      []byte("SITE_DOMAIN=roundtrip.example\n# exact bytes\n"),
				".env.credentials": []byte("SLACK_TOKEN=roundtrip-secret\n"),
			}
			presence := map[string]bool{
				".env.config":      tc.configPresent,
				".env.credentials": tc.credentialsPresent,
			}
			for name, present := range presence {
				if present {
					mustWriteFile(t, filepath.Join(projDir, name), want[name])
				}
			}
			if err := snapshotOperatorConfig(projDir, backupPath); err != nil {
				t.Fatal(err)
			}
			snapshotPath := operatorConfigSnapshotPath(backupPath)
			assertFileBytes(t, filepath.Join(snapshotPath, "FORMAT"), []byte(operatorConfigSnapshotFormat))
			snapshotInfo, err := os.Stat(snapshotPath)
			if err != nil {
				t.Fatal(err)
			}
			if got := snapshotInfo.Mode().Perm(); got != 0700 {
				t.Fatalf("snapshot directory mode = %o, want 700", got)
			}
			wantEntries := map[string]bool{
				"FORMAT": true,
			}
			for name, present := range presence {
				base := name[1:]
				suffix := ".absent"
				if present {
					suffix = ".present"
				}
				wantEntries[base+suffix] = true
			}
			entries, err := os.ReadDir(snapshotPath)
			if err != nil {
				t.Fatal(err)
			}
			if len(entries) != len(wantEntries) {
				t.Fatalf("snapshot entries = %v, want exactly %v", entries, wantEntries)
			}
			for _, entry := range entries {
				if !wantEntries[entry.Name()] {
					t.Fatalf("unexpected snapshot entry %q", entry.Name())
				}
				info, err := os.Lstat(filepath.Join(snapshotPath, entry.Name()))
				if err != nil {
					t.Fatal(err)
				}
				if !info.Mode().IsRegular() || info.Mode().Perm() != 0600 {
					t.Fatalf("snapshot entry %s mode = %v, want regular 0600", entry.Name(), info.Mode())
				}
			}
			for name := range presence {
				mustWriteFile(t, filepath.Join(projDir, name), []byte("target-era\n"))
			}
			if err := restoreOperatorConfig(projDir, backupPath); err != nil {
				t.Fatal(err)
			}
			for name, present := range presence {
				path := filepath.Join(projDir, name)
				if !present {
					if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
						t.Fatalf("%s exists after absence restore: %v", name, err)
					}
					continue
				}
				assertFileBytes(t, path, want[name])
				info, err := os.Stat(path)
				if err != nil {
					t.Fatal(err)
				}
				if got := info.Mode().Perm(); got != 0600 {
					t.Fatalf("%s mode = %o, want 600", name, got)
				}
			}
		})
	}
}

func TestRestoreSourceServicesContinuesPastDegradedOperatorConfigSnapshot(t *testing.T) {
	for _, tc := range []struct {
		name            string
		prepareSnapshot bool
		wantDiagnostic  string
	}{
		{name: "old format backup", wantDiagnostic: "OPERATOR_CONFIG_SNAPSHOT_UNAVAILABLE_OLD_BACKUP"},
		{name: "invalid layout", prepareSnapshot: true, wantDiagnostic: "OPERATOR_CONFIG_SNAPSHOT_DEGRADED"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			testRestoreSourceServicesContinuesPastOperatorConfigSnapshot(t, tc.prepareSnapshot, tc.wantDiagnostic)
		})
	}
}

func testRestoreSourceServicesContinuesPastOperatorConfigSnapshot(t *testing.T, prepareSnapshot bool, wantDiagnostic string) {
	t.Helper()
	projDir := t.TempDir()
	runGit := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = projDir
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	runGit("init", "-q")
	runGit("config", "user.name", "STATBUS test")
	runGit("config", "user.email", "statbus-test@example.invalid")
	if err := os.WriteFile(filepath.Join(projDir, "tracked"), []byte("source\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runGit("add", "tracked")
	runGit("commit", "-q", "-m", "source")
	sourceSHA := runGit("rev-parse", "HEAD")

	configCurrent := []byte("SITE_DOMAIN=current.example\n")
	credentialsCurrent := []byte("SLACK_TOKEN=current\n")
	if err := os.WriteFile(filepath.Join(projDir, ".env.config"), configCurrent, 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".env.credentials"), credentialsCurrent, 0600); err != nil {
		t.Fatal(err)
	}
	backupPath := filepath.Join(t.TempDir(), backupActiveName)
	if err := os.MkdirAll(backupPath, 0700); err != nil {
		t.Fatal(err)
	}
	if prepareSnapshot {
		snapshotPath := operatorConfigSnapshotPath(backupPath)
		if err := os.MkdirAll(snapshotPath, 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(snapshotPath, "env.config.absent"), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}

	reachedStack := errors.New("reached source stack after config generation")
	configGenerateReached := false
	d := &Service{projDir: projDir}
	d.sourceConfigGenerateForTest = func() error {
		configGenerateReached = true
		return nil
	}
	d.startSourceApplicationStackForTest = func(context.Context, *ProgressLog) error {
		return reachedStack
	}
	progress := NewUpgradeLog(projDir, 444, "config-snapshot-test", time.Now().UTC())
	t.Cleanup(progress.Close)
	err := d.restoreSourceServices(context.Background(), sourceSHA, backupPath, progress)
	if !errors.Is(err, reachedStack) {
		t.Fatalf("restoreSourceServices error = %v, want proof it continued to source stack", err)
	}
	if !configGenerateReached {
		t.Fatal("source config generation seam was not reached")
	}
	logContents, err := os.ReadFile(progress.AbsPath())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(logContents), wantDiagnostic) {
		t.Fatalf("progress log lacks %s diagnostic:\n%s", wantDiagnostic, logContents)
	}
	assertFileBytes(t, filepath.Join(projDir, ".env.config"), configCurrent)
	assertFileBytes(t, filepath.Join(projDir, ".env.credentials"), credentialsCurrent)
}

func captureOperatorConfigOutput(t *testing.T, fn func()) string {
	t.Helper()
	original := os.Stdout
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = writer
	t.Cleanup(func() { os.Stdout = original })
	fn()
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	os.Stdout = original
	var output bytes.Buffer
	if _, err := output.ReadFrom(reader); err != nil {
		t.Fatal(err)
	}
	return output.String()
}

func assertFileBytes(t *testing.T, path string, want []byte) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("%s changed byte-exact contents\ngot:  %q\nwant: %q", path, got, want)
	}
}

func writeAbsentOperatorConfigSnapshot(t *testing.T, snapshotPath string) {
	t.Helper()
	if err := os.MkdirAll(snapshotPath, 0700); err != nil {
		t.Fatal(err)
	}
	mustWriteFile(t, filepath.Join(snapshotPath, "FORMAT"), []byte(operatorConfigSnapshotFormat))
	mustWriteFile(t, filepath.Join(snapshotPath, "env.config.absent"), nil)
	mustWriteFile(t, filepath.Join(snapshotPath, "env.credentials.absent"), nil)
}

func mustWriteFile(t *testing.T, path string, contents []byte) {
	t.Helper()
	if err := os.WriteFile(path, contents, 0600); err != nil {
		t.Fatal(err)
	}
}

func mustRemove(t *testing.T, path string) {
	t.Helper()
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
}
