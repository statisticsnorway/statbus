package cmd

import (
	"os"
	"strings"
	"testing"
)

func installScript(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(thisRepoFile(t, "install.sh"))
	if err != nil {
		t.Fatalf("read install.sh: %v", err)
	}
	return string(b)
}

// executableLines strips comments so compatibility prose does not count as an
// invocation. Only what the served script can execute belongs in the audit.
func executableLines(body string) []string {
	var out []string
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		out = append(out, line)
	}
	return out
}

func shellSBInvocation(line string) bool {
	trimmed := strings.TrimSpace(line)
	return strings.Contains(trimmed, "$(./sb ") ||
		strings.HasPrefix(trimmed, "./sb ") ||
		strings.Contains(trimmed, "; ./sb ") ||
		strings.Contains(trimmed, `"$STATBUS_DIR/sb" `) ||
		strings.Contains(trimmed, `"${STATBUS_DIR}/sb" `) ||
		strings.HasPrefix(trimmed, "sb ")
}

// STATBUS-378: served install.sh is a compatibility surface. Until the target
// binary has been placed, the executable already on the box is an old release,
// not a capability probe. Tag/commit discovery must therefore use plain git.
func TestBootstrapFetchNeverCallsTheBoxBinary(t *testing.T) {
	body := installScript(t)
	for _, line := range executableLines(body) {
		if strings.Contains(line, "repo-fetch") {
			t.Errorf("install.sh still executes repo-fetch through the box binary: %s", strings.TrimSpace(line))
		}
	}

	helperStart := strings.Index(body, "statbus_git_fetch() {")
	if helperStart == -1 {
		t.Fatal("no statbus_git_fetch helper")
	}
	helperTail := body[helperStart:]
	helperEnd := strings.Index(helperTail, "\n}\n")
	if helperEnd == -1 {
		t.Fatal("could not isolate statbus_git_fetch helper")
	}
	helper := helperTail[:helperEnd]
	if !strings.Contains(helper, `git -C "$STATBUS_DIR" fetch "$@"`) {
		t.Error("statbus_git_fetch must use plain git in the installation directory")
	}
	if strings.Contains(helper, "$STATBUS_DIR/sb") || strings.Contains(helper, "./sb") {
		t.Error("statbus_git_fetch must not inspect or invoke the installed box binary")
	}
}

// Inventory every executable ./sb call in install.sh. The only allowed command
// surfaces are version display after placement, target-binary install, and
// post-failure support reporting. Adding a new pre-placement dependency must
// update this explicit compatibility review rather than landing silently.
func TestAllSBInvocationsFollowTargetBinaryPlacement(t *testing.T) {
	body := installScript(t)
	want := map[string]int{
		`echo "Binary: $(./sb --version)"`:                                                           3,
		`(exec </dev/tty; ./sb install ${SB_INSTALL_ARGS[@]+"${SB_INSTALL_ARGS[@]}"})`:               1,
		`./sb install ${SB_INSTALL_ARGS[@]+"${SB_INSTALL_ARGS[@]}"}`:                                 1,
		`if bundle_path=$(./sb support gather --trigger=install 2>/tmp/sb-support-gather.err); then`: 1,
		`./sb support write-admin-ui-row \`:                                                          1,
	}
	got := make(map[string]int)
	for _, line := range executableLines(body) {
		if shellSBInvocation(line) {
			got[strings.TrimSpace(line)]++
		}
	}
	if len(got) != len(want) {
		t.Fatalf("install.sh ./sb invocation inventory changed:\n got: %#v\nwant: %#v", got, want)
	}
	for invocation, count := range want {
		if got[invocation] != count {
			t.Errorf("install.sh invocation %q count = %d, want %d", invocation, got[invocation], count)
		}
	}

	firstPlacement := strings.Index(body, `docker cp "${sb_cid}:/sb" "${STATBUS_DIR}/sb"`)
	firstInvocation := strings.Index(body, `$(./sb --version)`)
	if firstPlacement == -1 || firstInvocation == -1 || firstPlacement > firstInvocation {
		t.Error("the first ./sb invocation appears before the first target-binary placement")
	}

	for _, rescueShape := range []struct {
		placement  string
		invocation string
	}{
		{`mv "${HOME}/sb.tmp" "${STATBUS_DIR}/sb"`, `echo "Binary: $(./sb --version)"`},
	} {
		placement := strings.Index(body, rescueShape.placement)
		if placement == -1 {
			t.Fatalf("missing target-binary placement %q", rescueShape.placement)
		}
		invocation := strings.Index(body[placement:], rescueShape.invocation)
		if invocation == -1 {
			t.Fatalf("missing post-placement invocation %q", rescueShape.invocation)
		}
	}
}

func TestInstallerStatesTheBoxBinaryCompatibilityInvariant(t *testing.T) {
	body := installScript(t)
	for _, phrase := range []string{
		"may not use box-binary features newer than",
		"oldest supported installed release",
		"target binary takes over only",
		"AFTER its download/image extraction and atomic placement",
	} {
		if !strings.Contains(body, phrase) {
			t.Errorf("install.sh compatibility comment must contain %q", phrase)
		}
	}
}

// The retained legacy command stays read-only and hidden for compatibility with
// already-served installers which may still call it.
func TestRepoFetchIsRegisteredReadOnly(t *testing.T) {
	if !readOnlyCommandPaths["sb repo-fetch"] {
		t.Error(`"sb repo-fetch" is not in readOnlyCommandPaths`)
	}
}

func TestRepoFetchIsHidden(t *testing.T) {
	if !repoFetchCmd.Hidden {
		t.Error("repo-fetch must remain hidden")
	}
}
