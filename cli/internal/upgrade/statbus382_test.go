package upgrade

import (
	"strings"
	"testing"
)

func TestSTATBUS382NotifyPromotesOnlyAvailableOrUnregistered(t *testing.T) {
	body := extractFuncBody(t, string(packageGoSources(t)["service.go"]), "func (d *Service) promoteExistingCandidate(")
	for _, want := range []string{
		"SELECT state::text",
		`case "available":`,
		`case "scheduled":`,
		"scheduleResultOperatorRequired",
		"scheduleResultUnregistered",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("promoteExistingCandidate missing %q", want)
		}
	}
}

func TestSTATBUS382ClaimTokenCASAndFlockProbe(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	claim := extractFuncBody(t, src, "func (d *Service) claimScheduledUpgradePass(")
	if !strings.Contains(claim, "claim_token = $4::uuid") || !strings.Contains(claim, "claim_token = $3::uuid") {
		t.Error("both claim schema branches must persist the generated claim token")
	}
	dispatch := extractFuncBody(t, src, "func (d *Service) executeScheduled(")
	probe := strings.Index(dispatch, "IsFlockHeld(d.projDir)")
	claimCall := strings.Index(dispatch, "d.claimScheduledUpgrade(ctx, id)")
	if probe < 0 || claimCall < 0 || probe > claimCall {
		t.Errorf("flock probe must precede claim: probe=%d claim=%d", probe, claimCall)
	}
	fail := extractFuncBody(t, src, "func (d *Service) failUpgradeWithFlagDisposition(")
	for _, want := range []string{"state = 'in_progress'", "claim_token = $4::uuid", "claim_token = NULL"} {
		if !strings.Contains(fail, want) {
			t.Errorf("failure CAS missing %q", want)
		}
	}
}

func TestSTATBUS382FlagContentionReschedulesAndDismissClearsPark(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	execute := extractFuncBody(t, src, "func (d *Service) executeUpgrade(")
	for _, want := range []string{
		"returned the claim to scheduled without changing scheduled_at",
		"state = 'scheduled'",
		"claim_token = $2::uuid",
		"parked on deterministic pre-destructive failure",
		"d.removeUpgradeFlag()",
	} {
		if !strings.Contains(execute, want) {
			t.Errorf("executeUpgrade missing %q", want)
		}
	}
	dismiss := extractFuncBody(t, src, "func (d *Service) RunDismiss(")
	for _, want := range []string{"recovery_parked_at = NULL", "recovery_parked_reason = NULL", "claim_token = NULL"} {
		if !strings.Contains(dismiss, want) {
			t.Errorf("RunDismiss missing %q", want)
		}
	}
}
