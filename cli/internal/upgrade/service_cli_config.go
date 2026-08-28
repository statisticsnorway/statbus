package upgrade

// LoadConfigForCLI loads .env into this Service WITHOUT connecting to the
// database or loading trusted signers.
//
// WHY THIS EXISTS (STATBUS-311). loadConfig() had exactly two callers — Run()
// and LoadConfigAndConnect() — both on daemon/one-shot-recovery paths. Every
// CLI verb built its Service with NewService() and never loaded config at all,
// so d.channel stayed the zero value "". `./sb upgrade check` therefore filtered
// 200+ tags against the empty string, matched nothing, and reported:
//
//	Found 203 release tag(s), none matching channel "" — nothing to register
//
// Reproduced on a BORN-FRESH developer box whose .env carries
// UPGRADE_CHANNEL=local — so this was never about the converted-box shape it was
// first reported as. It is every CLI invocation, on every box, since the CLI
// path has never loaded the channel.
//
// `upgrade schedule` is affected too, more quietly: scheduleStep asks
// TagMatchesChannel(tag, d.channel) to decide whether a named target is
// off-channel, and against "" every target looks off-channel — so the
// STATBUS-291 announce fires on targets that are perfectly on-channel.
//
// WHY NOT LoadConfigAndConnect: it also connects, and RunCheck's runOneShot
// connects again on its own, so composing them would open two connection pairs
// and close one. The CLI needs the CONFIG, not a connection.
//
// WHY A SEPARATE FILE from service.go: none — the placement is purely
// mechanical (service.go was held by another agent's in-flight work when this
// was written). The method belongs to Service like any other; if service.go is
// ever tidied, this can move into it with no change in meaning.
func (d *Service) LoadConfigForCLI() error {
	return d.loadConfig()
}

// ChannelForTest exposes the resolved channel so tests can assert what a
// Service actually loaded rather than inferring it from behaviour that needs a
// network. Test-only by name so no production caller reaches for it.
func (d *Service) ChannelForTest() string {
	return d.channel
}
