package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// userRuntimeDirBase is where systemd keeps each user's runtime directory,
// /run/user/<uid>. A variable so tests can point it at a temporary tree.
var userRuntimeDirBase = "/run/user"

// ensureUserRuntimeDir sets XDG_RUNTIME_DIR to this user's own runtime
// directory when the login did not set it.
//
// Every `systemctl --user` call (the upgrader unit, its status, the install's
// service checks) finds the user's service manager through XDG_RUNTIME_DIR.
// A login through sshd or a console sets it; `sudo -iu statbus`, the documented
// way from root to the install user, does not, because sudo does not open a
// systemd session. The manager is still running (setup enables linger), so the
// directory exists; only the variable is missing, and systemctl then fails
// with "$DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined" (observed
// on the manual test box, 2026-11-02, STATBUS-559).
//
// It is set only when the directory exists and belongs to this user, so a box
// without a running user manager still reports that real cause. Set once here
// and inherited by every child process, like GIT_TERMINAL_PROMPT.
func ensureUserRuntimeDir() {
	if os.Getenv("XDG_RUNTIME_DIR") != "" {
		return
	}
	uid := os.Getuid()
	dir := filepath.Join(userRuntimeDirBase, fmt.Sprint(uid))
	info, err := os.Stat(dir)
	if err != nil || !info.IsDir() {
		return
	}
	if st, ok := info.Sys().(*syscall.Stat_t); !ok || int(st.Uid) != uid {
		return
	}
	_ = os.Setenv("XDG_RUNTIME_DIR", dir)
}
