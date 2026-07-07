package upgrade

import "testing"

// TestIsServiceForwardRecovery pins the single predicate that decides whether a
// flag represents an in-flight, service-held FORWARD recovery (post_swap /
// resuming). Three callers depend on it — Service.Run's and runCrashRecovery's
// recovery-boot checkout gates, and stalenessGuard's self-heal carve-out
// (STATBUS-065). The truth table is load-bearing:
//   - a false NEGATIVE on a real forward recovery would let stalenessGuard run
//     `make` on a toolchain-less tagged-release host → crash loop;
//   - a false POSITIVE (esp. on PreSwap, which rolls back) would defer a
//     genuinely-stale binary's rebuild AND let a rolling-back tree advance.
func TestIsServiceForwardRecovery(t *testing.T) {
	const sha = "0123456789abcdef0123456789abcdef01234567"
	cases := []struct {
		name string
		flag *UpgradeFlag
		want bool
	}{
		{"service + post_swap → resume forward", &UpgradeFlag{Holder: HolderService, CommitSHA: sha, Phase: PhaseNewSbSwapped}, true},
		{"service + resuming → resume forward", &UpgradeFlag{Holder: HolderService, CommitSHA: sha, Phase: PhaseNewSbUpgrading}, true},
		{"service + pre_swap → rolls back, tree stays source", &UpgradeFlag{Holder: HolderService, CommitSHA: sha, Phase: PhaseOldSbUpgrading}, false},
		{"install-held → no forward resume", &UpgradeFlag{Holder: HolderInstall, CommitSHA: sha, Phase: PhaseNewSbSwapped}, false},
		{"empty CommitSHA → no target to check out", &UpgradeFlag{Holder: HolderService, CommitSHA: "", Phase: PhaseNewSbSwapped}, false},
		{"empty Holder (legacy) → not the forward fast-path", &UpgradeFlag{Holder: "", CommitSHA: sha, Phase: PhaseNewSbSwapped}, false},
		{"nil flag (no flag file present)", nil, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.flag.IsServiceForwardRecovery(); got != tc.want {
				t.Errorf("IsServiceForwardRecovery() = %v, want %v", got, tc.want)
			}
		})
	}
}
