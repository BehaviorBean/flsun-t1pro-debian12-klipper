#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# FLSun T1 Pro (Debian 12 on SD card): install config/printer.cfg and append the SAVE_CONFIG
# block (delta calibration, bed mesh, PID, input shaper) of YOUR printer.
#
#  - first run : the block is taken from the FLSun stock printer.cfg on the eMMC
#                (eMMC is mounted READ-ONLY, nothing is written to it)
#  - later runs: the block of the current printer.cfg is kept (your own calibration)
#  - optional  : --copy-gcodes also copies the G-code files from the stock system
#
# Run as user pi WITHOUT sudo (sudo is used internally):  bash scripts/install_printer_cfg.sh [--copy-gcodes]
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
TEMPLATE=$HERE/config/printer.cfg
CFG=$HOME/printer_data/config
MNT=/mnt/emmc
STAMP=$(date +%Y%m%d-%H%M%S)
COPY_GCODES=0
[ "${1:-}" = "--copy-gcodes" ] && COPY_GCODES=1

die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -un)" = "pi" ] || die "run as user pi without sudo"
findmnt -n -o SOURCE / | grep -q '^/dev/mmcblk2p6$' || die "not running on the Debian 12 SD card system"
[ -f "$TEMPLATE" ] || die "$TEMPLATE not found"
[ -f "$CFG/mainsail.cfg" ] || die "$CFG/mainsail.cfg missing - install Mainsail/mainsail-config with KIAUH first"
sudo -v

mount_emmc() {
  if ! findmnt "$MNT" >/dev/null 2>&1; then
    sudo mkdir -p "$MNT"
    sudo mount -o ro,noload /dev/mmcblk0p6 "$MNT"
    trap 'sudo umount "$MNT" 2>/dev/null || true' EXIT
  fi
}

SRC=""
if [ -f "$CFG/printer.cfg" ] && grep -q '^#\*# <-* SAVE_CONFIG' "$CFG/printer.cfg" \
   && grep -q 'BehaviorBean/flsun-t1pro-debian12-klipper' "$CFG/printer.cfg"; then
  SRC=$CFG/printer.cfg
  echo ">> keeping the SAVE_CONFIG block of the current printer.cfg"
else
  echo ">> reading the stock FLSun printer.cfg from the eMMC (read-only)"
  mount_emmc
  [ -f "$MNT/home/pi/printer_data/config/printer.cfg" ] || die "stock printer.cfg not found on the eMMC"
  cp "$MNT/home/pi/printer_data/config/printer.cfg" "$HOME/flsun_stock_printer.cfg"
  echo ">> copy of the stock config: ~/flsun_stock_printer.cfg"
  SRC=$HOME/flsun_stock_printer.cfg
fi
if [ "$COPY_GCODES" = 1 ]; then
  mount_emmc
  mkdir -p "$HOME/printer_data/gcodes"
  cp -rn --preserve=timestamps "$MNT/home/pi/printer_data/gcodes/." "$HOME/printer_data/gcodes/"
  echo ">> G-code files on the SD system: $(find "$HOME/printer_data/gcodes" -type f -iname '*.gcode' | wc -l) (existing files not overwritten)"
fi

TMP=$(mktemp)
python3 - "$TEMPLATE" "$SRC" "$TMP" <<'PY'
import re, sys
tpl, src, out = sys.argv[1:4]
mark = re.compile(r'^#\*# <-+ SAVE_CONFIG -+>', re.M)
s = open(src, encoding='utf-8').read()
m = mark.search(s)
if not m:
    sys.exit("ERROR: no SAVE_CONFIG block in " + src)
block = s[m.start():]
t = open(tpl, encoding='utf-8').read()
mt = mark.search(t)
if mt:
    t = t[:mt.start()]
open(out, 'w', encoding='utf-8').write(t.rstrip('\n') + '\n\n' + block)
for key in ('delta_radius', 'position_endstop', '[bed_mesh default]', '[input_shaper]'):
    print("   taken over: %-18s x%d" % (key, block.count(key)))
tsecs = set(re.findall(r'^\[([^\]]+)\]', t, re.M))
for sec in re.findall(r'^#\*# \[([^\]]+)\]', block, re.M):
    base = sec.split()[0] if not sec.startswith('bed_mesh ') else 'bed_mesh'
    if sec not in tsecs and base not in tsecs:
        print("   WARNING: SAVE_CONFIG section [%s] has no counterpart in the template - "
              "remove it from printer.cfg if Klipper reports an error" % sec)
PY
if [ -f "$CFG/printer.cfg" ]; then
  cp -a "$CFG/printer.cfg" "$CFG/printer.cfg.bak-$STAMP"
  echo ">> previous printer.cfg saved as printer.cfg.bak-$STAMP"
fi
cp "$TMP" "$CFG/printer.cfg"; rm -f "$TMP"
echo ">> printer.cfg installed"

sudo systemctl restart klipper
echo ">> Klipper restarted, waiting 30 s ..."
sleep 30
curl -sf http://127.0.0.1:7125/printer/info | python3 -c '
import json,sys
r=json.load(sys.stdin)["result"]
print(">> Klipper state:", r.get("state"))
m=(r.get("state_message") or "").strip()
if r.get("state")!="ready": print(m[:900])' || echo ">> Moonraker/Klipper not answering yet - check Mainsail in a minute"
