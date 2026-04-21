# Hetzner Bootstrap — rescue to production-ready Ubuntu

Short operator guide for the one-time initial install of Ubuntu 24.04 LTS on a
Hetzner physical ("dedicated") server, specifically the steps that are
Hetzner-rescue-specific and don't belong in the general
[DEPLOYMENT.md](DEPLOYMENT.md) flow.

After the steps in this document, hand off to
[setup-ubuntu-lts-24.md](setup-ubuntu-lts-24.md) for hardening + service
accounts, then [install-statbus.md](install-statbus.md) to install StatBus
itself.

## 1. Activate rescue and log in

From the [Hetzner Robot](https://robot.hetzner.com/) panel, activate the
rescue system for the server. You'll get a one-time password and any SSH keys
you've registered on your Hetzner account will be injected. Reboot the server
(the Robot UI has a "Reset" button that does this).

When it comes back up, SSH in as root:

```bash
ssh root@<server-ip>
# Password: the one-time value from Robot, OR use your registered SSH key.
```

## 2. Verify hardware before touching disks

```bash
lsblk -d -o NAME,SIZE,MODEL,ROTA
```

Typical output on an NVMe-based dedicated host:
```
NAME      SIZE MODEL                 ROTA
nvme0n1 476.9G TOSHIBA THNSN5512GPU7    0
nvme1n1 476.9G TOSHIBA THNSN5512GPU7    0
```

- `ROTA=0` means SSD/NVMe (non-rotational).
- Two identical disks is the right shape for RAID1.
- Older hardware may expose disks as `/dev/sda`, `/dev/sdb` — make a note of
  the actual device names for the `/autosetup` below.

## 3. Detect UEFI vs Legacy BIOS

```bash
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "Legacy BIOS"
```

- **UEFI**: include a `PART /boot/efi esp 1024M` entry in `/autosetup`.
  installimage replicates the ESP onto both disks post-install (it can't live
  on mdadm RAID, UEFI requires raw FAT32).
- **Legacy BIOS**: **omit** the ESP partition. grub goes on the MBR of both
  disks and mdadm handles `/boot` + `/`.

Older Hetzner hardware (e.g. the 4-core Xeon E3 generation) is typically
Legacy BIOS. Newer generations are UEFI.

## 4. Write `/autosetup`

Hetzner's rescue has `installimage` preinstalled; it reads `/autosetup` for
its config. Two variants — pick the one matching your firmware.

**Legacy BIOS variant** (mdadm RAID1 + XFS, no ESP):

```
DRIVE1 /dev/nvme0n1
DRIVE2 /dev/nvme1n1

SWRAID 1
SWRAIDLEVEL 1

BOOTLOADER grub

HOSTNAME <hostname>.statbus.org

# Partitions are all mirrored via SWRAID above.
# /boot must NOT be xfs — installimage enforces this.
PART swap   swap   16G
PART /boot  ext4   1024M
PART /      xfs    all

IMAGE /root/images/Ubuntu-2404-noble-amd64-base.tar.gz
```

**UEFI variant** — same as above plus an ESP partition that installimage
replicates to both disks post-install:

```
DRIVE1 /dev/nvme0n1
DRIVE2 /dev/nvme1n1

SWRAID 1
SWRAIDLEVEL 1

BOOTLOADER grub

HOSTNAME <hostname>.statbus.org

PART /boot/efi  esp    1024M
PART /boot      ext4   1024M
PART swap       swap   16G
PART /          xfs    all

IMAGE /root/images/Ubuntu-2404-noble-amd64-base.tar.gz
```

`IMAGE` points at the preinstalled Ubuntu 24.04 tarball under
`/root/images/`. List what's available with `ls /root/images/ | grep Ubuntu`;
pick the latest `Ubuntu-24*` `amd64` (or `arm64` if that's your hardware).

## 5. Run installimage

The tool is in `/root/.oldroot/nfs/install/installimage`. It may **not be in
the PATH** in non-interactive SSH sessions, so use the full path when
scripting:

```bash
/root/.oldroot/nfs/install/installimage -a -c /autosetup 2>&1 | tee /tmp/installimage.log
```

- `-a` runs in automatic mode (no interactive prompts).
- `-c /autosetup` uses the config you wrote.

From a TTY session you can just type `installimage` — the interactive shell's
PATH picks it up.

When it finishes the 16-step sequence you'll see `INSTALLATION COMPLETE`.

## 6. Reboot into the installed system

```bash
reboot
```

Rescue SSH host key is different from the installed-system's key; on the
next SSH attempt your local `~/.ssh/known_hosts` will complain. Remove the
stale entry:

```bash
ssh-keygen -R <server-ip>
ssh-keygen -R <hostname>.statbus.org
```

Then `ssh root@<server-ip>` (or the hostname) — you'll be on the installed
Ubuntu.

## 7. First-boot checklist

```bash
# Confirm RAID came up clean
cat /proc/mdstat
# Expected: md0/md1/md2 active, all `[UU]`. A `resync` in progress is normal
# for a fresh mirror and does not block anything.

# Confirm the filesystems are what you asked for
findmnt /        # xfs on /dev/mdX
findmnt /boot    # ext4 on /dev/mdX

# Bring the OS current — use `full-upgrade`, not just `upgrade`.
# `apt upgrade` refuses to install NEW packages, and kernel meta-package
# bumps often need that; a fresh Hetzner image will sit on an older kernel
# until you pull in the new one via full-upgrade.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get full-upgrade -y

# Reboot if the new kernel was installed (safe even if not).
reboot
```

## 8. Hand off to setup-ubuntu-lts-24.sh

The box is now a plain Ubuntu 24.04 server. Continue with the StatBus setup
script, which handles the OS hardening + account creation:

```bash
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/ops/setup-ubuntu-lts-24.sh -o setup.sh
chmod +x setup.sh
# Skip Stage 0 on Hetzner — HTTP APT sources work fine here.
SKIP_STAGES="0" ./setup.sh
```

See [setup-ubuntu-lts-24.md](setup-ubuntu-lts-24.md) for the full stage
description and options, and [DEPLOYMENT.md](DEPLOYMENT.md) /
[install-statbus.md](install-statbus.md) for the StatBus install that
follows.
