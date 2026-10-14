#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# FLSun T1 Pro: build a bootable Debian 12 (bookworm, armhf) SD card - run ON THE PRINTER
# in the FLSun STOCK system (root file system on the eMMC).
#
# The eMMC is only READ. Every write goes to /dev/mmcblk2 (the SD card) and is guarded.
# Without the card the printer boots the stock system exactly as before.
#
# What the card gets:
#   GPT layout of the eMMC (rootfs grown to the card size, new UUIDs)
#   loader area (sector 64..16383), uboot (p1) and misc (p2) copied from the eMMC
#   boot (p3): YOUR eMMC boot partition patched by make_sd_boot.py (root=/dev/mmcblk2p6)
#   rootfs (p6): fresh Debian 12 via debootstrap + Wi-Fi driver/firmware of the stock system,
#                NetworkManager (Wi-Fi profile taken over from /etc/wpa_supplicant.conf),
#                SSH, Avahi, user "pi"
#
# Usage (stock system, card inserted AFTER booting):
#   sudo HOSTNAME_NEW=t1pro-debian12 TZ_NEW=Europe/Berlin bash build_sd_card.sh
set -euo pipefail
HOSTNAME_NEW=${HOSTNAME_NEW:-t1pro-debian12}
TZ_NEW=${TZ_NEW:-Europe/Berlin}
LOCALES=${LOCALES:-"en_US.UTF-8"}
MIRROR=${MIRROR:-https://deb.debian.org/debian}
SUITE=bookworm
EMMC=/dev/mmcblk0
CARD=/dev/mmcblk2
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=/home/pi/t1pro-sd-build
MNT=/mnt/sd
INCLUDE=sudo,openssh-server,network-manager,wpasupplicant,avahi-daemon,locales,ca-certificates,curl,wget,git,nano,python3,python3-venv,python3-pip,python3-dev,iw,wireless-regdb,kmod,dbus,systemd-timesyncd,usbutils,v4l-utils

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }
wr()   { case "$1" in "$CARD"|"$CARD"p[0-9]) ;; *) die "refusing to write to $1";; esac; }

# ------------------------------------------------------------------ checks
[ "$(id -u)" = 0 ] || die "run with sudo"
case "$(findmnt -n -o SOURCE /)" in ${EMMC}p*) ;; *) die "must run in the FLSun stock system (root on $EMMC)";; esac
[ -b "$CARD" ] || die "no SD card at $CARD - insert the card after the printer has booted"
[ "$(cat /sys/block/mmcblk2/device/type 2>/dev/null)" = "SD" ] || die "$CARD is not an SD card"
[ "$(cat /sys/block/mmcblk0/device/type 2>/dev/null)" = "MMC" ] || die "$EMMC is not the eMMC"
SECT=$(cat /sys/block/mmcblk2/size)
[ "$SECT" -ge $((14 * 1024 * 1024 * 2)) ] || die "SD card too small (>= 16 GB needed)"
[ -f "/usr/share/zoneinfo/$TZ_NEW" ] || die "unknown time zone: $TZ_NEW"
grep -q "^$CARD" /proc/mounts && die "partitions of $CARD are mounted - unmount them first"
[ -f "$HERE/make_sd_boot.py" ] || die "make_sd_boot.py must be next to this script"
for t in sfdisk wipefs mkfs.ext4 dpkg-deb wget python3 chroot; do command -v $t >/dev/null || die "tool missing: $t"; done
wget -q --spider "$MIRROR/dists/$SUITE/Release" || die "cannot reach $MIRROR (HTTPS). Try: sudo update-ca-certificates --fresh"

echo "SD card : $CARD  name=$(cat /sys/block/mmcblk2/device/name)  size=$((SECT / 2 / 1024)) MiB"
echo "Hostname: $HOSTNAME_NEW   Timezone: $TZ_NEW   Locales: $LOCALES"
echo
echo "ALL DATA ON THE SD CARD WILL BE ERASED. The eMMC is only read."
read -r -p "Type YES to continue: " a
[ "$a" = "YES" ] || die "aborted"
mkdir -p "$WORK" "$MNT"

# ------------------------------------------------------------------ 1. boot image
step "1/8 read eMMC boot partition and patch it for the SD card"
dd if=${EMMC}p3 of="$WORK/boot_p3.img" bs=1M status=none
python3 "$HERE/make_sd_boot.py" "$WORK/boot_p3.img" "$WORK/boot_sd.img"

# ------------------------------------------------------------------ 2. partitions
step "2/8 create GPT on the SD card (layout of the eMMC, rootfs fills the card)"
sfdisk --dump $EMMC > "$WORK/emmc.sfdisk"
python3 - "$WORK/emmc.sfdisk" "$WORK/sd.sfdisk" <<'PY'
import sys
src, dst = sys.argv[1:3]
out, names = [], []
for l in open(src):
    if l.startswith(('label-id:', 'device:', 'last-lba:')):
        continue
    if l.startswith('/dev/'):
        dev, rest = l.split(':', 1)
        f = [x.strip() for x in rest.split(',')]
        f = [x for x in f if not x.startswith('uuid=')]
        name = next((x for x in f if x.startswith('name=')), '')
        names.append(name)
        if name == 'name="rootfs"':
            f = [x for x in f if not x.startswith('size=')]
        l = dev.strip().replace('mmcblk0', 'mmcblk2') + ' : ' + ', '.join(f) + '\n'
    out.append(l)
want = ['name="uboot"', 'name="misc"', 'name="boot"', 'name="recovery"', 'name="backup"', 'name="rootfs"']
if names != want:
    sys.exit("unexpected eMMC layout: %s" % names)
first = next(l for l in out if l.startswith('/dev/'))
if 'start=' not in first or int(first.split('start=')[1].split(',')[0]) != 16384:
    sys.exit("unexpected eMMC layout: first partition does not start at sector 16384")
open(dst, 'w').write(''.join(out))
PY
wr $CARD
wipefs -q -a $CARD
sfdisk -q --wipe always --wipe-partitions always $CARD < "$WORK/sd.sfdisk"
blockdev --rereadpt $CARD || true
sleep 3
[ -b ${CARD}p6 ] || die "${CARD}p6 not found after partitioning"
lsblk -o NAME,SIZE,PARTLABEL $CARD

# ------------------------------------------------------------------ 3. uboot, misc, boot
step "3/8 copy uboot + misc from the eMMC, write the patched boot image"
wr ${CARD}p1; dd if=${EMMC}p1 of=${CARD}p1 bs=1M conv=fsync status=none
wr ${CARD}p2; dd if=${EMMC}p2 of=${CARD}p2 bs=1M conv=fsync status=none
wr ${CARD}p3; dd if="$WORK/boot_sd.img" of=${CARD}p3 bs=1M conv=fsync status=none
SZ=$(stat -c %s "$WORK/boot_sd.img")
sync; echo 3 > /proc/sys/vm/drop_caches
[ "$(head -c "$SZ" ${CARD}p3 | sha256sum | cut -d' ' -f1)" = "$(sha256sum < "$WORK/boot_sd.img" | cut -d' ' -f1)" ] \
  || die "boot image read-back mismatch"
echo ">> boot image written and verified"

# ------------------------------------------------------------------ 4. rootfs
step "4/8 format rootfs and run debootstrap ($SUITE armhf) - takes a while"
wr ${CARD}p6
mkfs.ext4 -q -F -L rootfs ${CARD}p6
mount ${CARD}p6 "$MNT"
cleanup() {
  for d in dev/pts dev sys proc; do umount "$MNT/$d" 2>/dev/null || true; done
  umount "$MNT" 2>/dev/null || true
}
trap cleanup EXIT
cd "$WORK"
for pkg in debootstrap debian-archive-keyring; do
  f=$(wget -qO- "$MIRROR/pool/main/d/$pkg/" | grep -o "${pkg}_[0-9][^\"<>]*_all\.deb" | sort -uV | tail -n 1 || true)
  [ -n "$f" ] || die "cannot find $pkg on $MIRROR"
  wget -q -O "$f" "$MIRROR/pool/main/d/$pkg/$f"
  rm -rf "x-$pkg"; dpkg-deb -x "$f" "x-$pkg"
  echo ">> using $f"
done
KR=""
for c in "$WORK"/x-debian-archive-keyring/usr/share/keyrings/debian-archive-keyring.gpg \
         "$WORK"/x-debian-archive-keyring/usr/share/keyrings/debian-archive-keyring.pgp; do
  if [ -L "$c" ]; then c="$WORK/x-debian-archive-keyring/usr/share/keyrings/$(basename "$(readlink "$c")")"; fi
  [ -s "$c" ] && { KR=$c; break; }
done
[ -n "$KR" ] || die "debian-archive-keyring file not found in the extracted package"
DEBOOTSTRAP_DIR="$WORK/x-debootstrap/usr/share/debootstrap" "$WORK/x-debootstrap/usr/sbin/debootstrap" \
  --arch=armhf --components=main,contrib,non-free,non-free-firmware \
  --keyring="$KR" \
  --include="$INCLUDE" $SUITE "$MNT" "$MIRROR"
cd /

# ------------------------------------------------------------------ 5. system config
step "5/8 configure the new system"
T=$MNT
mkdir -p "$T/vendor/etc" "$T/lib/modules"
cp -a /vendor/etc/firmware "$T/vendor/etc/"
for m in bcmdhd.ko aic8800_bsp.ko aic8800_fdrv.ko; do [ -f /lib/modules/$m ] && cp -a /lib/modules/$m "$T/lib/modules/"; done
cat > "$T/usr/local/sbin/t1-wifi-module.sh" <<'EOS'
#!/bin/sh
# FLSun T1/T1 Pro have two Wi-Fi variants: try AIC8800 (5 GHz) first, else Broadcom bcmdhd (AP6212)
if [ -f /lib/modules/aic8800_bsp.ko ] && insmod /lib/modules/aic8800_bsp.ko 2>/dev/null && insmod /lib/modules/aic8800_fdrv.ko 2>/dev/null; then
  echo "aic8800 loaded"
else
  rmmod aic8800_bsp 2>/dev/null || true
  insmod /lib/modules/bcmdhd.ko && echo "bcmdhd loaded"
fi
EOS
chmod 755 "$T/usr/local/sbin/t1-wifi-module.sh"
cat > "$T/etc/systemd/system/t1-wifi-module.service" <<'EOS'
[Unit]
Description=FLSun T1 Pro: load Wi-Fi driver
Before=network-pre.target NetworkManager.service
Wants=network-pre.target
DefaultDependencies=no
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/t1-wifi-module.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOS
mkdir -p "$T/etc/NetworkManager/conf.d"
install -m 644 "$HERE/../system/90-t1pro-bcmdhd.conf" "$T/etc/NetworkManager/conf.d/90-t1pro-bcmdhd.conf"
echo "$HOSTNAME_NEW" > "$T/etc/hostname"
cat > "$T/etc/hosts" <<EOS
127.0.0.1   localhost
127.0.1.1   $HOSTNAME_NEW
::1         localhost ip6-localhost ip6-loopback
EOS
echo "/dev/mmcblk2p6  /  ext4  defaults,noatime  0  1" > "$T/etc/fstab"
cat > "$T/etc/apt/sources.list" <<EOS
deb $MIRROR $SUITE main contrib non-free non-free-firmware
deb $MIRROR $SUITE-updates main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security $SUITE-security main contrib non-free non-free-firmware
EOS
cp /etc/resolv.conf "$T/etc/resolv.conf"
ln -sf "/usr/share/zoneinfo/$TZ_NEW" "$T/etc/localtime"
echo "$TZ_NEW" > "$T/etc/timezone"
for l in $LOCALES; do sed -i "s/^# *$l /$l /" "$T/etc/locale.gen"; done
echo "LANG=${LOCALES%% *}" > "$T/etc/default/locale"

for d in proc sys dev dev/pts; do mount --bind /$d "$T/$d"; done
chroot "$T" /bin/bash -e <<'EOS'
export DEBIAN_FRONTEND=noninteractive LANG=C
locale-gen
getent group netdev >/dev/null || groupadd -r netdev
id pi >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,dialout,tty,video,plugdev,netdev pi
systemctl enable ssh NetworkManager avahi-daemon systemd-timesyncd t1-wifi-module
EOS

# ------------------------------------------------------------------ 6. Wi-Fi profile
step "6/8 take over the Wi-Fi profile from /etc/wpa_supplicant.conf (password is not shown)"
mkdir -p "$T/etc/NetworkManager/system-connections"
CUR=$(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^ssid=//p' || true)
CUR_SSID="$CUR" python3 - "$T/etc/NetworkManager/system-connections/wlan-home.nmconnection" <<'PY'
import re, sys, binascii, os
out, cur = sys.argv[1], os.environ.get('CUR_SSID', '')
try:
    txt = open('/etc/wpa_supplicant.conf', encoding='utf-8', errors='replace').read()
except OSError:
    print("!! /etc/wpa_supplicant.conf not found - configure Wi-Fi later with nmtui"); sys.exit(0)
blocks = re.findall(r'network\s*=\s*\{(.*?)\}', txt, re.S)
def get(b, k):
    m = re.search(r'^\s*' + k + r'\s*=\s*(.+?)\s*$', b, re.M)
    return m.group(1) if m else None
def unq(v):
    if v is None: return None
    if v.startswith('"') and v.endswith('"'): return v[1:-1]
    try: return binascii.unhexlify(v).decode('utf-8', 'replace')
    except Exception: return v
cands = [b for b in blocks if unq(get(b, 'ssid')) and unq(get(b, 'ssid')) != 'SSID']
pick = [b for b in cands if cur and unq(get(b, 'ssid')) == cur] or cands[-1:]
if not pick:
    print("!! no usable network block - configure Wi-Fi later with nmtui"); sys.exit(0)
b = pick[0]
ssid, psk, km = unq(get(b, 'ssid')), get(b, 'psk'), (get(b, 'key_mgmt') or 'WPA-PSK').upper()
L = ["[connection]", "id=wlan-home", "type=wifi", "interface-name=wlan0", "autoconnect=true",
     "autoconnect-retries=0", "", "[wifi]", "mode=infrastructure", "ssid=" + ssid, ""]
if km != 'NONE' and psk:
    if psk.startswith('"') and psk.endswith('"'): psk = psk[1:-1]
    L += ["[wifi-security]", "key-mgmt=wpa-psk", "psk=" + psk, ""]
L += ["[ipv4]", "method=auto", "", "[ipv6]", "method=ignore", ""]
open(out, 'w', encoding='utf-8').write("\n".join(L))
os.chmod(out, 0o600)
print(">> Wi-Fi profile for SSID '%s' written (password not shown)" % ssid)
PY

# ------------------------------------------------------------------ 7. password
step "7/8 set the password for user pi on the SD card system"
until chroot "$T" passwd pi; do echo "please try again"; done

trap - EXIT
sync
for d in dev/pts dev sys proc; do umount "$MNT/$d"; done
umount "$MNT"
mountpoint -q "$MNT" && die "$MNT is still mounted - not making the card bootable"

# ------------------------------------------------------------------ 8. loader (last = card becomes bootable)
step "8/8 copy the loader area (sector 64..16383) - makes the card bootable"
wr $CARD
dd if=$EMMC of=$CARD bs=512 skip=64 seek=64 count=16320 conv=fsync status=none
sync
echo
echo ">> DONE. Power off, wait 10 s, power on WITH the card -> Debian 12 boots from the card."
echo "   Remove the card -> the stock system boots from the eMMC as before."
echo "   Host name: $HOSTNAME_NEW (ssh pi@$HOSTNAME_NEW.local or the IP from your router)."
echo "   Working files (contain your boot image): $WORK"
