#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# FLSun T1 Pro (Debian 12 on SD card): finish KlipperScreen on the 480x272 display
#   1. touch calibration for the tlsc6x controller (X server / libinput)
#      The matrix is FLSun's own tslib calibration (/etc/pointercal of the stock system:
#      -719 62098 1205500 -65727 81 17556672 65536 480 272) converted to libinput.
#   2. hide the camera button in KlipperScreen - opening the camera there starts mpv,
#      which takes over the display output; the screen stays black until a reboot.
#
# Install KlipperScreen with KIAUH first (standalone: yes, backend: X11, NetworkManager: no).
# Run as user pi WITHOUT sudo:  bash scripts/setup_klipperscreen.sh
# Undo touch: sudo rm /etc/X11/xorg.conf.d/99-t1pro-touch.conf && sudo systemctl restart KlipperScreen
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -un)" = "pi" ] || die "run as user pi without sudo"
findmnt -n -o SOURCE / | grep -q '^/dev/mmcblk2p6$' || die "not running on the Debian 12 SD card system"
systemctl cat KlipperScreen.service >/dev/null 2>&1 || die "KlipperScreen is not installed (KIAUH)"
dpkg -s xserver-xorg-input-libinput >/dev/null 2>&1 || die "xserver-xorg-input-libinput missing"
sudo -v

# 1) touch
sudo mkdir -p /etc/X11/xorg.conf.d
sudo install -m 644 "$HERE/system/99-t1pro-touch.conf" /etc/X11/xorg.conf.d/99-t1pro-touch.conf
echo ">> touch calibration installed"

# 2) hide camera entries (main menu and print menu), above KlipperScreen's own saved section
C=$HOME/printer_data/config/KlipperScreen.conf
python3 - "$C" <<'PY'
import os, re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read() if os.path.exists(p) else ''
secs = ['menu __main more camera', 'menu __print camera']
new = ''.join("[%s]\nenable: False\n\n" % x for x in secs if "[%s]" % x not in s)
if new:
    m = re.search(r'^#~#', s, re.M)
    s = (s[:m.start()] + new + s[m.start():]) if m else (s.rstrip('\n') + ('\n\n' if s else '') + new)
    open(p, 'w', encoding='utf-8').write(s)
    print(">> camera button hidden in KlipperScreen.conf")
else:
    print(">> camera button already hidden")
PY

sudo systemctl restart KlipperScreen
sleep 20
echo ">> KlipperScreen: $(systemctl is-active KlipperScreen)"
grep -E 'T1 Pro Touch|CalibrationMatrix' /var/log/Xorg.0.log 2>/dev/null | tail -n 3 | sed 's/^/   /' || true
