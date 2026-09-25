package cmd

import "golang.org/x/sys/unix"

const passwordIoctlReadTermios = unix.TCGETS
const passwordIoctlWriteTermios = unix.TCSETS
