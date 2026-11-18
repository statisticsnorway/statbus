package config

import (
	"fmt"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// DevHttpsKey is the one address choice a development checkout records in
// .env.config: whether the browser uses the slot's Caddy over https (true,
// the default) or plain http (false). Everything else about a development
// slot's addresses follows from SITE_DOMAIN and DEPLOYMENT_SLOT_PORT_OFFSET,
// so it is derived on every generate and never stored (STATBUS-631). Stored
// addresses went stale: a copied checkout kept another slot's port, or the
// docker-only http://proxy:80, and the dev server failed in ways that took a
// fresh diagnosis each time.
//
// https is the default because the development Caddy serves HTTP/2, which
// browsers use only over TLS, so many tabs share one connection. It needs
// Caddy's local certificate trusted once per machine (./dev.sh https trust).
// ./dev.sh https on|off sets this key.
const DevHttpsKey = "DEV_HTTPS"

// devAddressKeys are the addresses a development checkout derives. Older
// checkouts stored them in .env.config, where gen() kept them forever.
var devAddressKeys = []string{"STATBUS_URL", "BROWSER_REST_URL", "SERVER_REST_URL"}

type devAddresses struct{ statbus, browser, server string }

// slotCaddyPorts are the slot's own Caddy ports outside standalone, where
// Caddy owns 80 and 443: 3000 + offset*10 for http and the next one for https.
func slotCaddyPorts(offset int) (httpPort, httpsPort int) {
	httpPort = 3000 + offset*10
	return httpPort, httpPort + 1
}

// resolveDevAddresses derives a development slot's addresses from its domain,
// its Caddy ports and DEV_HTTPS, writing DEV_HTTPS into f when absent so the
// choice is visible where it is changed. It mutates f; the caller saves.
//
// The browser and the upgrade callback (STATBUS_URL) use the address a person
// opens. The host dev server's own server-side calls (SERVER_REST_URL) always
// use plain http on the slot's Caddy: Node does not trust Caddy's local
// certificate authority, so an https address there fails every request.
func resolveDevAddresses(f *dotenv.File, siteDomain string, httpPort, httpsPort int) (devAddresses, string, error) {
	notice := migrateStoredDevAddresses(f)

	raw, declared := f.Get(DevHttpsKey)
	value := strings.TrimSpace(raw)
	if !declared {
		value = "true"
		f.Set(DevHttpsKey, value)
	}
	plainHTTP := fmt.Sprintf("http://%s:%d", siteDomain, httpPort)
	var browser string
	switch value {
	case "true":
		browser = fmt.Sprintf("https://%s:%d", siteDomain, httpsPort)
	case "false":
		browser = plainHTTP
	default:
		return devAddresses{}, "", newRefusal(fmt.Sprintf(
			"%s=%q in .env.config is not true or false.\n"+
				"  true: the browser uses https://%s:%d (the slot's Caddy, HTTP/2).\n"+
				"  false: it uses %s.\n"+
				"  Set it with ./dev.sh https on or ./dev.sh https off.",
			DevHttpsKey, raw, siteDomain, httpsPort, plainHTTP))
	}
	return devAddresses{statbus: browser, browser: browser, server: plainHTTP}, notice, nil
}

// migrateStoredDevAddresses removes the addresses an older development
// checkout stored in .env.config, keeping the one choice they expressed: an
// https BROWSER_REST_URL meant https. A DEV_HTTPS already present wins.
// Returns a notice, empty when there was nothing to remove.
func migrateStoredDevAddresses(f *dotenv.File) string {
	var removed []string
	for _, key := range devAddressKeys {
		if v, ok := f.Get(key); ok {
			removed = append(removed, key+"="+v)
		}
	}
	if len(removed) == 0 {
		return ""
	}
	_, hasChoice := f.Get(DevHttpsKey)
	if browser, ok := f.Get("BROWSER_REST_URL"); ok && !hasChoice {
		f.Set(DevHttpsKey, fmt.Sprintf("%t", strings.HasPrefix(strings.TrimSpace(browser), "https://")))
	}
	for _, key := range devAddressKeys {
		f.Delete(key)
	}
	kept := ""
	if choice, ok := f.Get(DevHttpsKey); ok {
		kept = fmt.Sprintf(" The https choice is %s=%s.", DevHttpsKey, choice)
	}
	return fmt.Sprintf(
		"NOTE: removed %s from .env.config.\n"+
			"  A development slot derives its addresses from SITE_DOMAIN and its ports on every\n"+
			"  generate, so stored ones only go stale.%s\n",
		strings.Join(removed, ", "), kept)
}
