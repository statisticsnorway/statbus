package config

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

var envKeyLineRE = regexp.MustCompile(`(?m)^([A-Za-z_][A-Za-z0-9_]*)=`)

// TestGenerateEnvContent_EveryKeyHasARestartClass is STATBUS-332's AC#4
// completeness test: every key that ends up in the generated .env must
// carry a restart-class declaration made at ITS OWN write site (setKV /
// classes.declare / declareIfAbsent) — a new key added without one must
// fail HERE, never silently ship with no restart class and therefore never
// actually apply (this ticket's own failure mode: install's diff step
// would see the key change but have nothing telling it what to restart).
//
// The enumeration is DERIVED from the generator's real output, never a
// hand-authored list of "the keys I remember" — that hand list is exactly
// the parallel table the architect's ruling forbids (2026-08-31).
func TestGenerateEnvContent_EveryKeyHasARestartClass(t *testing.T) {
	projDir := t.TempDir()

	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	repoRoot := filepath.Join(filepath.Dir(thisFile), "..", "..", "..")
	realExample, err := os.ReadFile(filepath.Join(repoRoot, ".env.example"))
	if err != nil {
		t.Fatalf("read repo .env.example: %v", err)
	}
	// The REAL .env.example, not a minimal fixture: the property this test
	// protects is specifically about the ~34 dead legacy Supabase-stack keys
	// that pass through verbatim from THAT file (see declareIfAbsent's doc
	// comment) — a synthetic minimal example would trivially "pass" by never
	// containing them, proving nothing about the real generated .env.
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), realExample, 0644); err != nil {
		t.Fatal(err)
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}
	derived := computeDerived(cfg)
	dbMem, err := computeDbMemory("4G")
	if err != nil {
		t.Fatal(err)
	}

	out, classes, err := generateEnvContent(&Credentials{}, cfg, derived, dbMem, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent: %v", err)
	}

	seen := map[string]bool{}
	var missing []string
	for _, m := range envKeyLineRE.FindAllStringSubmatch(out, -1) {
		key := m[1]
		if seen[key] {
			continue
		}
		seen[key] = true
		// Existence in the map is the completeness property, NOT a non-empty
		// slice: classes.declare("KEY") with zero classes is the established,
		// intentional way to record "explicitly no restart needed" (many
		// call sites read "no verified consumer" / "read fresh, never
		// cached" and declare zero classes on purpose) — that must count as
		// covered. Only a key ABSENT from the map was never looked at.
		if _, declared := classes[key]; !declared {
			missing = append(missing, key)
		}
	}
	if len(seen) == 0 {
		t.Fatal("no KEY=value lines found in generated .env — the extraction regex or the generator itself is broken")
	}

	if len(missing) > 0 {
		sort.Strings(missing)
		t.Errorf("generated .env has %d key(s) with NO declared restart class:\n  %s\n\n"+
			"install's config-diff step cannot know what to restart for these — a change to any of "+
			"them would silently never take effect. Declare each at its own write site in "+
			"generateEnvContent (setKV / classes.declare). If it is a confirmed-dead .env.example "+
			"carryover with no runtime consumer, declareIfAbsent should already have covered it via "+
			"example.Keys() — check the key actually appears there.",
			len(missing), strings.Join(missing, "\n  "))
	}
}

// TestUpgradeChannelChangeClassifiesAsUpgradeDaemon_STATBUS332 is AC#3: a
// mode change moves the DERIVED UPGRADE_CHANNEL value (STATBUS-307 — see
// TestModeChangeMovesOnlyUndeclaredBoxes for the derivation itself), and
// that changed value must be classified RestartUpgradeDaemon so install's
// diff step (cli/cmd) actually restarts the daemon for it. This test fixes
// cfg.UpgradeChannel directly (the two values ResolveUpgradeChannel would
// derive for two different CADDY_DEPLOYMENT_MODE inputs) rather than
// re-deriving it — the derivation itself is proven elsewhere
// (upgrade_channel_test.go); this proves generateEnvContent (a) actually
// writes a different UPGRADE_CHANNEL line for a different input, so a real
// before/after .env diff would catch it, and (b) declares that key
// RestartUpgradeDaemon, not RestartNone or an empty set.
func TestUpgradeChannelChangeClassifiesAsUpgradeDaemon_STATBUS332(t *testing.T) {
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0644); err != nil {
		t.Fatal(err)
	}

	cfgFor := func(channel string) *ConfigEnv {
		return &ConfigEnv{
			DeploymentSlotCode:       "local",
			DeploymentSlotName:       "local",
			DeploymentSlotPortOffset: "1",
			CaddyDeploymentMode:      "development",
			SiteDomain:               "local.statbus.org",
			StatbusURL:               "http://localhost:3010",
			BrowserAPIURL:            "http://local.statbus.org:3010",
			UpgradeChannel:           channel,
		}
	}

	cfgStable := cfgFor("stable")
	derivedStable := computeDerived(cfgStable)
	outStable, classesStable, err := generateEnvContent(&Credentials{}, cfgStable, derivedStable, &DbMemory{}, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent(stable): %v", err)
	}

	cfgPrerelease := cfgFor("prerelease")
	derivedPrerelease := computeDerived(cfgPrerelease)
	outPrerelease, classesPrerelease, err := generateEnvContent(&Credentials{}, cfgPrerelease, derivedPrerelease, &DbMemory{}, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent(prerelease): %v", err)
	}

	stableVal, ok := dotenv.FromString(outStable).Get("UPGRADE_CHANNEL")
	if !ok {
		t.Fatal("UPGRADE_CHANNEL missing from generated .env (stable)")
	}
	prereleaseVal, ok := dotenv.FromString(outPrerelease).Get("UPGRADE_CHANNEL")
	if !ok {
		t.Fatal("UPGRADE_CHANNEL missing from generated .env (prerelease)")
	}
	if stableVal == prereleaseVal {
		t.Fatalf("UPGRADE_CHANNEL did not change (%q both times) — a real .env diff would see nothing here, defeating this test's premise", stableVal)
	}
	if stableVal != "stable" || prereleaseVal != "prerelease" {
		t.Fatalf("UPGRADE_CHANNEL=%q / %q — expected the cfg.UpgradeChannel value to pass through generateEnvContent verbatim", stableVal, prereleaseVal)
	}

	for _, classes := range []map[string][]RestartClass{classesStable, classesPrerelease} {
		found := false
		for _, c := range classes["UPGRADE_CHANNEL"] {
			if c == RestartUpgradeDaemon {
				found = true
			}
		}
		if !found {
			t.Errorf("UPGRADE_CHANNEL classified as %v, want to include RestartUpgradeDaemon — a mode-driven channel change would silently never restart the daemon that reads it", classes["UPGRADE_CHANNEL"])
		}
	}
}

// TestBatchClassifiedKeysHaveZeroComposeConsumers is the architect's
// required pin on the declareIfAbsent batch's OWN claim (2026-08-31): every
// key it classifies RestartNone — the ~34 dead legacy Supabase-stack keys
// that reach the generated .env verbatim from .env.example, never touched
// by any explicit setKV/declare call — must have ZERO consumers in any
// compose file. The day one of those keys comes alive (a docker-compose.yml
// edit starts interpolating it) is the only day this needs to catch
// anything, and it must catch it then, not stay green forever on a claim
// nobody re-checks.
//
// SCOPED TO THE BATCH ONLY, not every RestartNone/empty-class key — see
// declareIfAbsent's invariant comment (restart_class.go): a key's classes
// slice being exactly [RestartNone] is the unambiguous signal it came
// through this function, because RestartNone is passed nowhere else in
// this file. Widening the scope to every empty-class key would be WRONG:
// several of them (ADMINISTRATOR_CONTACT, UPGRADE_CALLBACK, STATBUS_URL,
// ...) have a live consumer that reads .env fresh at point-of-use rather
// than caching it — "zero consumers" is false for those, by design, and a
// test asserting it over all of them would fire on correct code.
func TestBatchClassifiedKeysHaveZeroComposeConsumers(t *testing.T) {
	projDir := t.TempDir()

	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	repoRoot := filepath.Join(filepath.Dir(thisFile), "..", "..", "..")
	realExample, err := os.ReadFile(filepath.Join(repoRoot, ".env.example"))
	if err != nil {
		t.Fatalf("read repo .env.example: %v", err)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), realExample, 0644); err != nil {
		t.Fatal(err)
	}

	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:      "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}
	derived := computeDerived(cfg)
	dbMem, err := computeDbMemory("4G")
	if err != nil {
		t.Fatal(err)
	}
	_, classes, err := generateEnvContent(&Credentials{}, cfg, derived, dbMem, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent: %v", err)
	}

	var batch []string
	for key, cls := range classes {
		if len(cls) == 1 && cls[0] == RestartNone {
			batch = append(batch, key)
		}
	}
	sort.Strings(batch)
	if len(batch) == 0 {
		t.Fatal("no batch-classified ([RestartNone]) keys found — either declareIfAbsent stopped firing, .env.example lost every pass-through key, or the invariant declareIfAbsent's doc comment describes no longer holds; this pin has nothing to check and that is itself a regression")
	}

	// "Any compose file" — globbed, not hand-listed, for the same reason
	// CaddyConfigFiles is a single source of truth rather than a second list:
	// a hand-maintained file list drifts the day a new compose file is added.
	var composeFiles []string
	if err := filepath.WalkDir(repoRoot, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if d.Name() == "node_modules" || d.Name() == ".git" {
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if strings.HasPrefix(name, "docker-compose") && strings.HasSuffix(name, ".yml") {
			composeFiles = append(composeFiles, path)
		}
		return nil
	}); err != nil {
		t.Fatalf("walk repo for compose files: %v", err)
	}
	if len(composeFiles) == 0 {
		t.Fatal("found no docker-compose*.yml files at all — the walk itself is broken, not proving anything about consumers")
	}

	composeContent := make(map[string]string, len(composeFiles))
	for _, f := range composeFiles {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		composeContent[f] = string(data)
	}

	for _, key := range batch {
		needle := "${" + key
		for f, content := range composeContent {
			if strings.Contains(content, needle) {
				rel, _ := filepath.Rel(repoRoot, f)
				t.Errorf("batch-classified key %s (RestartNone, .env.example pass-through) is now interpolated in %s — "+
					"it has come alive and needs a REAL restart-class declaration at its own write site, not the dead-carryover batch",
					key, rel)
			}
		}
	}
}
