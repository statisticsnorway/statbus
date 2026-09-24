package upgrade

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dbroles"
)

// The daemon must make the database role passwords equal to .env after the
// database is up and before its first connection, on both connect entrypoints.
// Without it, a volume that outlived its .env.credentials rejects every login
// and the unit never reaches READY=1 (Finland, step 17 timeout).
func TestDaemonSyncsRolePasswordsBeforeFirstConnect(t *testing.T) {
	run := funcBody(t, "service.go", "func (d *Service) Run(")
	up := strings.Index(run, "d.EnsureDBUp(ctx)")
	sync := strings.Index(run, "d.syncRolePasswordsBeforeConnect(ctx)")
	conn := strings.Index(run, "d.connect(ctx)")
	if up < 0 || sync < 0 || conn < 0 || up > sync || sync > conn {
		t.Fatalf("Run must call EnsureDBUp, then syncRolePasswordsBeforeConnect, then connect (positions %d, %d, %d)", up, sync, conn)
	}
	inline := funcBody(t, "service.go", "func (d *Service) LoadConfigAndConnect(")
	sync = strings.Index(inline, "d.syncRolePasswordsBeforeConnect(ctx)")
	conn = strings.Index(inline, "d.connect(ctx)")
	if sync < 0 || conn < 0 || sync > conn {
		t.Fatal("LoadConfigAndConnect must sync role passwords before connect")
	}
}

func TestSyncRolePasswordsBeforeConnectNeverFailsTheBoot(t *testing.T) {
	old := syncRolePasswords
	t.Cleanup(func() { syncRolePasswords = old })
	d := &Service{projDir: t.TempDir()}

	var calledWith string
	syncRolePasswords = func(_ context.Context, dir string) ([]dbroles.Mismatch, error) {
		calledWith = dir
		return []dbroles.Mismatch{{Role: "authenticator", Reason: "differs"}, {Role: "postgres", Reason: "differs"}}, nil
	}
	d.syncRolePasswordsBeforeConnect(context.Background())
	if calledWith != d.projDir {
		t.Fatalf("synced %q, want %q", calledWith, d.projDir)
	}

	syncRolePasswords = func(context.Context, string) ([]dbroles.Mismatch, error) {
		return nil, errors.New("db container not running")
	}
	d.syncRolePasswordsBeforeConnect(context.Background()) // must return, not panic or exit
}
