package cmd

import "golang.org/x/sys/unix"

const passwordIoctlReadTermios = unix.TIOCGETA
const passwordIoctlWriteTermios = unix.TIOCSETA
