package config

import (
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// STATBUS-404 AC3: changing only the display name changes the keys the app
// reads (compose passes DEPLOYMENT_SLOT_NAME to the app as
// PUBLIC_DEPLOYMENT_SLOT_NAME, rendered per request by app/src/app/layout.tsx),
// so the declared restart classes of the changed keys are exactly the app.
func TestDisplayNameChangeRestartsOnlyTheApp_STATBUS404(t *testing.T) {
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	generate := func(name string) (*dotenv.File, map[string][]RestartClass) {
		cfg := &ConfigEnv{
			DeploymentSlotCode:       "ug",
			DeploymentSlotName:       name,
			DeploymentSlotPortOffset: "1",
			CaddyDeploymentMode:      "standalone",
			SiteDomain:               "statbus.example.org",
			StatbusURL:               "https://statbus.example.org",
			BrowserAPIURL:            "https://statbus.example.org",
		}
		out, classes, err := generateEnvContent(&Credentials{}, cfg, computeDerived(cfg), &DbMemory{}, projDir)
		if err != nil {
			t.Fatalf("generateEnvContent(%q): %v", name, err)
		}
		return dotenv.FromString(out), classes
	}
	before, _ := generate("Uganda")
	after, classes := generate("Uganda Bureau of Statistics")

	var changed []string
	for _, key := range after.Keys() {
		a, _ := after.Get(key)
		b, _ := before.Get(key)
		if a != b {
			changed = append(changed, key)
		}
	}
	sort.Strings(changed)
	if name, _ := after.Get("DEPLOYMENT_SLOT_NAME"); name != "Uganda Bureau of Statistics" {
		t.Fatalf("DEPLOYMENT_SLOT_NAME = %q after the change (changed keys %q)", name, changed)
	}

	got := map[RestartClass]bool{}
	for _, key := range changed {
		for _, c := range classes[key] {
			got[c] = true
		}
	}
	if want := map[RestartClass]bool{RestartApp: true}; !reflect.DeepEqual(got, want) {
		t.Errorf("restart classes for a display-name change (changed keys %q) = %v, want exactly {RestartApp}", changed, got)
	}
}

// Every generated key that a compose file interpolates reaches a container, so
// a change to it must restart that container: its declared restart classes are
// not empty. (The reverse holds for TestBatchClassifiedKeysHaveZeroComposeConsumers:
// a dead pass-through key has no compose consumer.)
func TestComposeInterpolatedKeysRestartTheirConsumer_STATBUS404(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	repoRoot := filepath.Join(filepath.Dir(thisFile), "..", "..", "..")
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env.example"), []byte("# minimal example\n"), 0o644); err != nil {
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
	_, classes, err := generateEnvContent(&Credentials{}, cfg, computeDerived(cfg), &DbMemory{}, projDir)
	if err != nil {
		t.Fatalf("generateEnvContent: %v", err)
	}

	composeFiles, err := filepath.Glob(filepath.Join(repoRoot, "docker-compose*.yml"))
	if err != nil || len(composeFiles) == 0 {
		t.Fatalf("no docker-compose*.yml at the repository root (%v)", err)
	}
	interpolated := map[string][]string{}
	ref := regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)`)
	for _, f := range composeFiles {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		for _, m := range ref.FindAllStringSubmatch(string(data), -1) {
			interpolated[m[1]] = append(interpolated[m[1]], filepath.Base(f))
		}
	}

	checked := 0
	for key, files := range interpolated {
		declared, generated := classes[key]
		if !generated {
			continue // not a generated key (an operator shell variable such as VERBOSE)
		}
		checked++
		if len(declared) == 0 {
			t.Errorf("%s is interpolated by %v but declares no restart class: a changed value would never reach the container", key, files)
		}
	}
	if checked == 0 {
		t.Fatal("no compose-interpolated key is generated: the scan found nothing to check")
	}
}
