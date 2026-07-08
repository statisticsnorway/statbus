package cmd

import (
	"errors"
	"testing"
)

// TestShouldRestartAfterFailedRecovery pins STATBUS-147's two required
// branches (ticket AC#1/#2): a re-park restarts the quiesced upgrade unit
// anyway (parked-skip makes every future boot alive-idle by construction);
// any other failure keeps the conservative no-restart arm.
func TestShouldRestartAfterFailedRecovery(t *testing.T) {
	cases := []struct {
		name    string
		parked  bool
		readErr error
		want    bool
	}{
		{"parked, read ok -> restart", true, nil, true},
		{"not parked, read ok -> no restart (genuinely broken recovery)", false, nil, false},
		{"parked, read failed -> no restart (can't trust an unread state)", true, errors.New("db down"), false},
		{"not parked, read failed -> no restart", false, errors.New("db down"), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := shouldRestartAfterFailedRecovery(c.parked, c.readErr)
			if got != c.want {
				t.Errorf("shouldRestartAfterFailedRecovery(parked=%v, err=%v) = %v, want %v", c.parked, c.readErr, got, c.want)
			}
		})
	}
}
