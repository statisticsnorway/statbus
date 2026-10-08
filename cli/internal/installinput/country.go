package installinput

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// STATBUS-466: a StatBus installation that is not development serves one
// country. Its display name IS the country name and its code IS the country
// code (doc/CLOUD.md: no, pk, et, jo, ma, ug, ...). Development may invent
// both, which is what a local installation is for.

var (
	// slotCode is the hard rule every mode needs: the code names containers
	// (statbus-<code>-db), the database (statbus_<code>) and the subdomain.
	slotCode = regexp.MustCompile(`^[a-z][a-z0-9]{0,19}$`)
	// twoLetters is the shape of an ISO 3166 alpha-2 code in a domain label.
	twoLetters = regexp.MustCompile(`^[a-z]{2}$`)
)

const slotCodeShape = "lowercase letters and digits, starting with a letter, at most 20 characters"

// genericCCTLDs are country top-level domains widely sold as generic names
// (example.io is rarely a site of the British Indian Ocean Territory), so they
// never suggest a country.
var genericCCTLDs = map[string]bool{"ai": true, "co": true, "fm": true, "io": true, "me": true, "tv": true}

type country struct{ name, alpha2, alpha3 string }

// displayName drops the ISO list's trailing "(the)", so "Bahamas (the)" is
// shown as "Bahamas".
func displayName(isoName string) string {
	return strings.TrimSuffix(isoName, " (the)")
}

// lookupCountry finds a country by name (with or without "(the)"), alpha-2
// or alpha-3 code, ignoring case and surrounding space.
func lookupCountry(s string) (country, bool) {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" {
		return country{}, false
	}
	for _, c := range countryTable {
		if s == strings.ToLower(c[0]) || s == strings.ToLower(displayName(c[0])) ||
			s == strings.ToLower(c[1]) || s == strings.ToLower(c[2]) {
			return country{displayName(c[0]), strings.ToLower(c[1]), strings.ToLower(c[2])}, true
		}
	}
	return country{}, false
}

// HostTimeZone reports this computer's IANA time zone and its ISO country
// code, or empty strings when either is unknown (a cloud server set to UTC
// has no country). It is a variable so tests never depend on the host.
var HostTimeZone = hostTimeZone

func hostTimeZone() (zone, alpha2 string) {
	zone = os.Getenv("TZ")
	if zone == "" {
		target, err := filepath.EvalSymlinks("/etc/localtime")
		if err != nil {
			return "", ""
		}
		_, after, found := strings.Cut(target, "zoneinfo/")
		if !found {
			return "", ""
		}
		zone = after
	}
	data, err := os.ReadFile("/usr/share/zoneinfo/zone.tab")
	if err != nil {
		return zone, ""
	}
	return zone, zoneCountry(string(data), zone)
}

// zoneCountry looks a zone up in tzdata's zone.tab (country<TAB>coords<TAB>zone).
func zoneCountry(zoneTab, zone string) string {
	for _, line := range strings.Split(zoneTab, "\n") {
		cols := strings.Split(line, "\t")
		if len(cols) >= 3 && !strings.HasPrefix(line, "#") && cols[2] == zone {
			return cols[0]
		}
	}
	return ""
}

// SuggestCountry is the country a name question may offer as its default,
// with the reason shown to the operator. Only real signals count: the
// domain's first label (no.statbus.org, our own slot convention), then its
// country top-level domain (statbus.ssb.no), then this computer's time zone.
// Without one there is no suggestion and the operator must type the country.
func SuggestCountry(domain string) (name, reason string) {
	labels := strings.Split(strings.ToLower(strings.TrimSpace(domain)), ".")
	if len(labels) >= 2 {
		if first := labels[0]; twoLetters.MatchString(first) {
			if c, ok := lookupCountry(first); ok {
				return c.name, fmt.Sprintf("from the domain %s", domain)
			}
		}
		if tld := labels[len(labels)-1]; twoLetters.MatchString(tld) && !genericCCTLDs[tld] {
			if c, ok := lookupCountry(tld); ok {
				return c.name, fmt.Sprintf("from the domain %s", domain)
			}
		}
	}
	if zone, code := HostTimeZone(); code != "" {
		if c, ok := lookupCountry(code); ok {
			return c.name, fmt.Sprintf("from this computer's time zone %s", zone)
		}
	}
	return "", ""
}

// SuggestCountryCode is the default for the code question: the chosen
// country's own two-letter code, else a two-letter first domain label.
// Never the development value "local".
func SuggestCountryCode(countryName, domain string) string {
	if c, ok := lookupCountry(countryName); ok {
		return c.alpha2
	}
	first := strings.Split(strings.ToLower(domain), ".")[0]
	if strings.Contains(domain, ".") && twoLetters.MatchString(first) {
		return first
	}
	return ""
}

// CountryCodeAdvice is the non-blocking warning for a well-formed code that
// is not the country's code. Empty when the code is fine.
func CountryCodeAdvice(code, countryName string) string {
	named, nameKnown := lookupCountry(countryName)
	coded, codeKnown := lookupCountry(code)
	if codeKnown && len(code) <= 3 {
		if !nameKnown || named == coded {
			return ""
		}
		return fmt.Sprintf("%q is the country code of %s, not %s.", code, coded.name, named.name)
	}
	return fmt.Sprintf("%q is not a country code (two or three letters from ISO 3166, such as no for Norway).", code)
}

// AnswerAdvice reviews unattended answers for the same country rule the
// interactive questions apply, and returns a warning to print (or "").
// A deliberate test installation proceeds; the warning only makes the
// choice visible.
func AnswerAdvice(mode, countryName, code string) string {
	if mode == "development" {
		return ""
	}
	advice := CountryCodeAdvice(code, countryName)
	if advice == "" {
		return ""
	}
	return fmt.Sprintf("Note: DEPLOYMENT_SLOT_CODE=%s. %s A %s installation serves one country, so its code is normally that country's code. Continuing with %q as given.", code, advice, mode, code)
}
