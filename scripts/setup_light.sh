#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# FLSun T1 Pro (Debian 12 on SD card): chamber light as Moonraker power device "Light".
# The light is NOT connected to the mainboard but to GPIO108 of the Linux board (RV1109).
# GPIO108 = bank gpio3, line 12. Moonraker switches it via /dev/gpiochipN.
# Afterwards: toggle "Light" in Mainsail (power menu) or use the macros LIGHT_ON / LIGHT_OFF / F106.
#
# Run as user pi WITHOUT sudo:  bash scripts/setup_light.sh
set -euo pipefail
MR=$HOME/printer_data/config/moonraker.conf
die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -un)" = "pi" ] || die "run as user pi without sudo"
findmnt -n -o SOURCE / | grep -q '^/dev/mmcblk2p6$' || die "not running on the Debian 12 SD card system"
[ -f "$MR" ] || die "$MR not found"
sudo -v

# 1) which /dev/gpiochipN is bank gpio3? (read-only ioctl GPIO_GET_CHIPINFO, no line is requested)
[ "$(cat /sys/class/gpio/gpiochip96/label 2>/dev/null)" = "gpio3" ] || die "GPIO bank gpio3 (base 96) not found"
CHIP=$(sudo python3 - <<'PY'
import fcntl, struct, glob
hits = []
for p in sorted(glob.glob('/dev/gpiochip*')):
    with open(p, 'rb') as f:
        buf = bytearray(68)
        fcntl.ioctl(f, 0x8044B401, buf, True)
        name, label, lines = struct.unpack('32s32sI', bytes(buf))
        if label.split(b'\0')[0] == b'gpio3' and lines == 32:
            hits.append(p.split('/')[-1])
print(' '.join(hits))
PY
)
case "$CHIP" in gpiochip[0-9]) ;; *) die "cannot map gpio3 to /dev/gpiochipN ('$CHIP')";; esac
echo ">> light pin: GPIO108 = /dev/$CHIP line 12"

# 2) access for pi / Moonraker (group gpio)
getent group gpio >/dev/null || sudo groupadd --system gpio
id -nG pi | grep -qw gpio || sudo usermod -aG gpio pi
sudo install -m 644 "$(cd "$(dirname "$0")/.." && pwd)/system/60-gpiochip.rules" /etc/udev/rules.d/60-gpiochip.rules
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=gpio --action=add
sleep 2
[ "$(stat -c %G /dev/$CHIP)" = "gpio" ] || die "/dev/$CHIP is not in group gpio"
# the line must not be exported via sysfs, otherwise it is busy
[ -d /sys/class/gpio/gpio108 ] && echo 108 | sudo tee /sys/class/gpio/unexport >/dev/null || true

# 3) Moonraker power device
if grep -q '^\[power Light\]' "$MR"; then
  echo ">> [power Light] already present - unchanged"
else
  cp -a "$MR" "$MR.bak-$(date +%Y%m%d-%H%M%S)"
  cat >> "$MR" <<EOF

# FLSun T1 Pro: chamber light (GPIO108 on the Linux board), switched on when Moonraker starts
[power Light]
type: gpio
pin: $CHIP/gpio12
initial_state: on
EOF
  echo ">> [power Light] added to moonraker.conf"
fi

sudo systemctl restart moonraker
sleep 10
curl -sf http://127.0.0.1:7125/machine/device_power/devices | python3 -c '
import json,sys
d=json.load(sys.stdin).get("result",{}).get("devices",[])
print(">> power devices:", ", ".join("%s=%s" % (x["device"], x["status"]) for x in d) or "none")' || echo ">> Moonraker not answering yet - check Mainsail in a minute"
