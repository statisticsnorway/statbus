package installinput

import (
	"encoding/csv"
	"os"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// noHostZone makes suggestions independent of the machine running the tests.
func noHostZone(t *testing.T) {
	t.Helper()
	old := HostTimeZone
	HostTimeZone = func() (string, string) { return "", "" }
	t.Cleanup(func() { HostTimeZone = old })
}

// scripted answers questions by label suffix; "" presses Enter. It records
// every label and the default each question offered.
type scripted struct {
	answers   map[string][]string
	labels    []string
	fallbacks map[string][]string
}

func (s *scripted) prompt(label, fallback string) string {
	s.labels = append(s.labels, label)
	if s.fallbacks == nil {
		s.fallbacks = map[string][]string{}
	}
	for suffix, queue := range s.answers {
		if strings.HasSuffix(label, "\n  "+suffix) || label == "  "+suffix {
			s.fallbacks[suffix] = append(s.fallbacks[suffix], fallback)
			if len(queue) == 0 {
				return fallback
			}
			s.answers[suffix] = queue[1:]
			if queue[0] == "" {
				return fallback
			}
			return queue[0]
		}
	}
	panic("unexpected question: " + label)
}

func get(t *testing.T, content, key string) string {
	t.Helper()
	v, _ := dotenv.FromString(content).Get(key)
	return v
}

// The installer's country list IS the database's country seed; a country the
// database knows is a country the installer recognises, and vice versa.
func TestCountryTableMatchesSeed(t *testing.T) {
	f, err := os.Open("../../../dbseed/country/country_codes.csv")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	rows, err := csv.NewReader(f).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	rows = rows[1:]
	if len(rows) != len(countryTable) {
		t.Fatalf("seed has %d countries, installer table %d: regenerate countries_table.go", len(rows), len(countryTable))
	}
	for i, r := range rows {
		if [3]string{r[0], r[1], r[2]} != countryTable[i] {
			t.Errorf("row %d: seed %v, table %v", i, r[:3], countryTable[i])
		}
	}
}

// STATBUS-466: the unattended recipe describes a country installation. It
// must show country values, never the development StatBus/local.
func TestRecipeShowsCountryValuesNotDevelopmentValues(t *testing.T) {
	recipe := Requirement()
	for _, want := range []string{
		"CADDY_DEPLOYMENT_MODE=standalone  # Deployment mode",
		"SITE_DOMAIN=example.org  # Domain name",
		"DEPLOYMENT_SLOT_NAME=Norway  # Country name",
		"DEPLOYMENT_SLOT_CODE=no  # Country code",
	} {
		if !strings.Contains(recipe, want) {
			t.Errorf("recipe lacks %q:\n%s", want, recipe)
		}
	}
	for _, dev := range []string{"=StatBus", "=local", "local.statbus.org"} {
		if strings.Contains(recipe, dev) {
			t.Errorf("recipe shows development value %q:\n%s", dev, recipe)
		}
	}
	// The recipe, taken literally, is a valid answer file with no advice.
	var lines []string
	for _, line := range strings.Split(recipe, "\n") {
		if strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "  export ") && strings.Contains(line, "=") && strings.Contains(line, "  # ") && !strings.Contains(line, "TLS_") {
			lines = append(lines, strings.TrimSpace(strings.SplitN(line, "  # ", 2)[0]))
		}
	}
	content := strings.Join(lines, "\n") + "\n"
	a, err := parse(content, "")
	if err != nil {
		t.Fatalf("recipe is not a valid answer file: %v\n%s", err, content)
	}
	if advice := AnswerAdvice(get(t, a.Config, "CADDY_DEPLOYMENT_MODE"), get(t, a.Config, "DEPLOYMENT_SLOT_NAME"), get(t, a.Config, "DEPLOYMENT_SLOT_CODE")); advice != "" {
		t.Errorf("recipe values draw advice: %s", advice)
	}
}

// Standalone, operator types country-shaped answers.
func TestStandaloneCountryAnswers(t *testing.T) {
	noHostZone(t)
	s := &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {""},
		"Domain name":     {"statbus.example.org"},
		CountryNamePrompt: {"Ethiopia"},
		CountryCodePrompt: {"et"},
	}}
	content := Ask(s.prompt)
	if get(t, content, "DEPLOYMENT_SLOT_NAME") != "Ethiopia" || get(t, content, "DEPLOYMENT_SLOT_CODE") != "et" {
		t.Fatalf("answers not kept:\n%s", content)
	}
	if got := s.fallbacks[CountryCodePrompt][0]; got != "et" {
		t.Errorf("code default after naming Ethiopia = %q, want et", got)
	}
}

// Standalone, operator presses Enter on everything after the domain. With a
// real signal the defaults are a country's; never StatBus or local.
func TestStandalonePressEnterUsesRealSignals(t *testing.T) {
	for _, tc := range []struct {
		name, domain, zone, zoneCountry, wantName, wantCode string
	}{
		{"slot-style first label", "no.statbus.org", "", "", "Norway", "no"},
		{"country top-level domain", "statbus.ssb.no", "", "", "Norway", "no"},
		{"first label beats the zone", "ug.statbus.org", "Europe/Oslo", "NO", "Uganda", "ug"},
		{"host time zone", "statbus.example.org", "Africa/Addis_Ababa", "ET", "Ethiopia", "et"},
		{"generic ccTLD is not a country", "statbus.example.io", "Asia/Amman", "JO", "Jordan", "jo"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			old := HostTimeZone
			HostTimeZone = func() (string, string) { return tc.zone, tc.zoneCountry }
			t.Cleanup(func() { HostTimeZone = old })
			s := &scripted{answers: map[string][]string{
				"Deployment mode (development/standalone/private)": {""},
				"Domain name":     {tc.domain},
				CountryNamePrompt: {""},
				CountryCodePrompt: {""},
			}}
			content, err := Validate(Ask(s.prompt))
			if err != nil {
				t.Fatal(err)
			}
			if get(t, content, "CADDY_DEPLOYMENT_MODE") != "standalone" ||
				get(t, content, "DEPLOYMENT_SLOT_NAME") != tc.wantName || get(t, content, "DEPLOYMENT_SLOT_CODE") != tc.wantCode {
				t.Fatalf("got:\n%s", content)
			}
			if tc.zone != "" && tc.wantCode == strings.ToLower(tc.zoneCountry) &&
				!strings.Contains(strings.Join(s.labels, "\n"), "Suggested from this computer's time zone "+tc.zone) {
				t.Errorf("zone reason not shown:\n%s", strings.Join(s.labels, "\n"))
			}
		})
	}
}

// Standalone with no signal at all: entry is required. Pressing Enter is
// re-asked and, if the operator never answers, the install refuses naming
// the key; it never falls back to StatBus/local.
func TestStandalonePressEnterWithoutSignalRequiresEntry(t *testing.T) {
	noHostZone(t)
	s := &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {""},
		"Domain name":     {"statbus.example.org"},
		CountryNamePrompt: {"", "", ""},
		CountryCodePrompt: {"", "", ""},
	}}
	content := Ask(s.prompt)
	for _, f := range s.fallbacks[CountryNamePrompt] {
		if f != "" {
			t.Fatalf("name offered %q without a signal", f)
		}
	}
	if len(s.fallbacks[CountryNamePrompt]) != askAttempts || len(s.fallbacks[CountryCodePrompt]) != askAttempts {
		t.Fatalf("empty answers must be re-asked: %v", s.fallbacks)
	}
	if strings.Contains(content, "StatBus") || strings.Contains(content, "=local") {
		t.Fatalf("development value leaked:\n%s", content)
	}
	if _, err := Validate(content); err == nil || !strings.Contains(err.Error(), "DEPLOYMENT_SLOT_NAME (Country name)") {
		t.Fatalf("want refusal naming the country, got %v", err)
	}
	if !strings.Contains(strings.Join(s.labels, "\n"), "Please type the country name people will see, for example Norway.") {
		t.Error("re-ask does not explain")
	}
}

// Private (our cloud country slots) is a country installation too.
func TestPrivateAsksForTheCountry(t *testing.T) {
	noHostZone(t)
	s := &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {"private"},
		"Domain name":     {"ma.statbus.org"},
		CountryNamePrompt: {""},
		CountryCodePrompt: {""},
	}}
	content := Ask(s.prompt)
	if get(t, content, "DEPLOYMENT_SLOT_NAME") != "Morocco" || get(t, content, "DEPLOYMENT_SLOT_CODE") != "ma" {
		t.Fatalf("got:\n%s", content)
	}
}

// Development keeps its permissive questions and invented defaults.
func TestDevelopmentInventsNameAndCode(t *testing.T) {
	noHostZone(t)
	for _, tc := range []struct{ domain, code string }{
		{"local.statbus.org", "local"},
		{"dev.statbus.org", "dev"},
		{"my-laptop.example", "local"}, // an unusable first label falls back, never aborts
	} {
		s := &scripted{answers: map[string][]string{
			"Deployment mode (development/standalone/private)": {"development"},
			"Domain name":         {tc.domain},
			DevelopmentNamePrompt: {""},
			DevelopmentCodePrompt: {""},
		}}
		content, err := Validate(Ask(s.prompt))
		if err != nil {
			t.Fatal(err)
		}
		if get(t, content, "DEPLOYMENT_SLOT_NAME") != "StatBus" || get(t, content, "DEPLOYMENT_SLOT_CODE") != tc.code {
			t.Fatalf("%s: got\n%s", tc.domain, content)
		}
		all := strings.Join(s.labels, "\n")
		if strings.Contains(all, CountryNamePrompt) || !strings.Contains(all, "A development installation may invent one.") {
			t.Errorf("development questions wrong:\n%s", all)
		}
	}
	// A typed invented code is kept as typed, with no country advice.
	s := &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {"development"},
		"Domain name":         {"local.statbus.org"},
		DevelopmentNamePrompt: {"Sandbox"},
		DevelopmentCodePrompt: {"sandbox1"},
	}}
	content := Ask(s.prompt)
	if get(t, content, "DEPLOYMENT_SLOT_CODE") != "sandbox1" || len(s.fallbacks[DevelopmentCodePrompt]) != 1 {
		t.Fatalf("got\n%s %v", content, s.fallbacks)
	}
}

// A code that is not a country code warns but never blocks; Enter keeps it.
func TestCountryCodeWarningHasExplainedEscapeHatch(t *testing.T) {
	noHostZone(t)
	s := &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {""},
		"Domain name":     {"no.statbus.org"},
		CountryNamePrompt: {""},
		CountryCodePrompt: {"test", ""},
	}}
	content := Ask(s.prompt)
	if get(t, content, "DEPLOYMENT_SLOT_CODE") != "test" {
		t.Fatalf("deliberate test code not kept:\n%s", content)
	}
	all := strings.Join(s.labels, "\n")
	for _, want := range []string{`"test" is not a country code`, "For a deliberate test installation, press Enter to keep test."} {
		if !strings.Contains(all, want) {
			t.Errorf("missing %q:\n%s", want, all)
		}
	}
	// Another country's code is called out; typing the right one fixes it.
	s = &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {""},
		"Domain name":     {"no.statbus.org"},
		CountryNamePrompt: {""},
		CountryCodePrompt: {"se", "no"},
	}}
	content = Ask(s.prompt)
	if get(t, content, "DEPLOYMENT_SLOT_CODE") != "no" || !strings.Contains(strings.Join(s.labels, "\n"), `"se" is the country code of Sweden, not Norway.`) {
		t.Fatalf("got\n%s\n%s", content, strings.Join(s.labels, "\n"))
	}
	// A malformed code is refused and re-asked, never written.
	s = &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {""},
		"Domain name":     {"no.statbus.org"},
		CountryNamePrompt: {""},
		CountryCodePrompt: {"No Way", ""},
	}}
	content = Ask(s.prompt)
	if get(t, content, "DEPLOYMENT_SLOT_CODE") != "no" || !strings.Contains(strings.Join(s.labels, "\n"), "no way cannot be used: the code must be lowercase letters") {
		t.Fatalf("got\n%s\n%s", content, strings.Join(s.labels, "\n"))
	}
}

func TestModeQuestionReasksUnknownAnswers(t *testing.T) {
	noHostZone(t)
	s := &scripted{answers: map[string][]string{
		"Deployment mode (development/standalone/private)": {"public", "Private"},
		"Domain name":     {"jo.statbus.org"},
		CountryNamePrompt: {""},
		CountryCodePrompt: {""},
	}}
	content := Ask(s.prompt)
	if get(t, content, "CADDY_DEPLOYMENT_MODE") != "private" {
		t.Fatalf("got\n%s", content)
	}
}

func TestUnattendedAnswerAdviceAndRefusals(t *testing.T) {
	for _, tc := range []struct {
		mode, name, code string
		advises          bool
	}{
		{"standalone", "Norway", "no", false},
		{"standalone", "Norway", "nor", false},
		{"private", "Install Test", "test", true},
		{"standalone", "Norway", "se", true},
		{"development", "StatBus", "local", false},
	} {
		advice := AnswerAdvice(tc.mode, tc.name, tc.code)
		if (advice != "") != tc.advises {
			t.Errorf("%+v: advice %q", tc, advice)
		}
		if advice != "" && !strings.Contains(advice, "Continuing with") {
			t.Errorf("advice must say the install continues: %q", advice)
		}
	}
	base := "CADDY_DEPLOYMENT_MODE=standalone\nSITE_DOMAIN=statbus.ssb.no\nDEPLOYMENT_SLOT_NAME=Norway\n"
	if _, err := Validate(base + "DEPLOYMENT_SLOT_CODE=No-Way\n"); err == nil || !strings.Contains(err.Error(), "DEPLOYMENT_SLOT_CODE=No-Way must be lowercase") {
		t.Errorf("malformed code: %v", err)
	}
	if _, err := Validate(strings.Replace(base, "standalone", "public", 1) + "DEPLOYMENT_SLOT_CODE=no\n"); err == nil || !strings.Contains(err.Error(), "is not development, standalone or private") {
		t.Errorf("unknown mode: %v", err)
	}
}

func TestZoneCountry(t *testing.T) {
	tab := "# comment\nNO\t+5955+01045\tEurope/Oslo\nET\t+0902+03842\tAfrica/Addis_Ababa\n"
	if zoneCountry(tab, "Europe/Oslo") != "NO" || zoneCountry(tab, "UTC") != "" || zoneCountry(tab, "Etc/UTC") != "" {
		t.Fatal("zone lookup")
	}
}
