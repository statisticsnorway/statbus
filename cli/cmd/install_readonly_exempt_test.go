package cmd

import (
	"os"
	"strings"
	"testing"
)

// TestConnectInstallDB_SelfExempts_STATBUS209 (ARM B): every install DB session self-exempts
// from the read-only upgrade window on connect, exactly like the pipeline's own sessions and
// install's migrate subprocess. Without this, the completion INSERT can 25006 on a session that
// predates a restore's window-lift (the rc.01 restore-broke arcs). RED before ARM B.
func TestConnectInstallDB_SelfExempts_STATBUS209(t *testing.T) {
	src := readInstallGo(t)
	body := funcBody(t, src, "func connectInstallDB(")
	if !strings.Contains(body, "SET default_transaction_read_only = off") {
		t.Error("ARM B: connectInstallDB must SET default_transaction_read_only = off on the new session — install can never coexist with a live upgrade (the flock refuses), so its writes are never the class the window blocks")
	}
	// The exemption runs on the SAME connection that is returned (before returning it).
	setIdx := strings.Index(body, "SET default_transaction_read_only = off")
	retIdx := strings.LastIndex(body, "return conn, nil")
	if setIdx < 0 || retIdx < 0 || setIdx > retIdx {
		t.Error("ARM B: the exemption must run on the connection before it is returned")
	}
}

// TestInstallCompletion_ClearsStaleWindow_STATBUS209 (ARM A, install invoker): a successful
// install completion invokes the shared ownership-gated backstop so box-wide read-only residue
// (app sessions never self-exempt) is cleared. RED before ARM A.
func TestInstallCompletion_ClearsStaleWindow_STATBUS209(t *testing.T) {
	src := readInstallGo(t)
	if !strings.Contains(src, "ClearStaleReadOnlyWindowIfUnowned(") {
		t.Error("ARM A: the install completion must invoke svc.ClearStaleReadOnlyWindowIfUnowned — reuse the boot backstop as the install ladder's second invoker")
	}
	// It must be reached only after a successful completion INSERT (installErr==nil path).
	complIdx := strings.Index(src, "completeInstallUpgradeRow(installDir, conn, logRelPath)")
	clearIdx := strings.Index(src, "ClearStaleReadOnlyWindowIfUnowned(")
	if complIdx < 0 || clearIdx < 0 || clearIdx < complIdx {
		t.Errorf("ARM A: the stale-window clear must follow the completion INSERT (complete@%d, clear@%d)", complIdx, clearIdx)
	}
}

func readInstallGo(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	return string(b)
}

// funcBody returns the source of the named function up to the next top-level "\nfunc ".
func funcBody(t *testing.T, src, signature string) string {
	t.Helper()
	start := strings.Index(src, signature)
	if start < 0 {
		t.Fatalf("function %q not found", signature)
	}
	rest := src[start+len(signature):]
	if end := strings.Index(rest, "\nfunc "); end >= 0 {
		return src[start : start+len(signature)+end]
	}
	return src[start:]
}
