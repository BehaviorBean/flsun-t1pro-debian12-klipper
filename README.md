# FLSun T1 Pro – Debian 12 + upstream Klipper from an SD card

**Deutsche Anleitung: [README.de.md](README.de.md)**

Run a clean, current software stack on the FLSun T1 Pro – **Debian 12 (bookworm)**, **upstream Klipper**, Moonraker, Mainsail, Crowsnest and KlipperScreen – **from a microSD card**, without touching the stock system on the eMMC and **without flashing the mainboard**.

* **Card in** → Debian 12 with upstream Klipper
* **Card out** → the untouched FLSun stock system boots as before

> ⚠️ **Unofficial community project – use at your own risk.** Not affiliated with FLSun. It was developed and tested on **one** printer (see [Tested with](#tested-with)). The scripts only read the eMMC and only write to the SD card, but a mistake with `dd` or a wrong device can still cost you data. Make the backups in step 0 first and read each step before running it.

> **Status of the scripts (please read):** Everything described here runs on the reference printer. The scripts in this repository bundle the commands used during development into reusable form:
> `make_sd_boot.py` reproduces the working boot image **byte for byte**. `printer.cfg` was checked offline against upstream Klipper and the stock MCU protocol.
> `build_sd_card.sh`, `install_printer_cfg.sh`, `setup_light.sh` and `setup_klipperscreen.sh` are **first public versions** and have not yet been run end-to-end in exactly this form. They stop at their safety checks. Please report the output of the first runs in an issue.

---

## Contents

- [How it works](#how-it-works)
- [Tested with](#tested-with)
- [What works – and what doesn't](#what-works--and-what-doesnt)
- [Requirements](#requirements)
- [Step 0 – Back up the eMMC](#step-0--back-up-the-emmc)
- [Step 1 – Prepare the stock system](#step-1--prepare-the-stock-system)
- [Step 2 – Build the SD card](#step-2--build-the-sd-card)
- [Step 3 – First boot](#step-3--first-boot)
- [Step 4 – Klipper, Moonraker, Mainsail (KIAUH)](#step-4--klipper-moonraker-mainsail-kiauh)
- [Step 5 – printer.cfg](#step-5--printercfg)
- [Step 6 – First tests and calibration](#step-6--first-tests-and-calibration)
- [Step 7 – Webcam (Crowsnest)](#step-7--webcam-crowsnest)
- [Step 8 – Chamber light](#step-8--chamber-light)
- [Step 9 – Touch display (KlipperScreen)](#step-9--touch-display-klipperscreen)
- [Step 10 – Optional: remote access](#step-10--optional-remote-access)
- [Slicer and old G-code files](#slicer-and-old-g-code-files)
- [Backing up and restoring the SD card](#backing-up-and-restoring-the-sd-card)
- [Klipper updates with the stock mainboard firmware](#klipper-updates-with-the-stock-mainboard-firmware)
- [Flashing the mainboard (not done)](#flashing-the-mainboard-not-done)
- [Troubleshooting](#troubleshooting)
- [Repository layout](#repository-layout)
- [Credits](#credits) · [License](#license)

---

## How it works

The T1 Pro has two computers:

| Board | Chip | Job |
|---|---|---|
| Core board (Linux) | Rockchip **RV1109**, 8 GB eMMC, FLSun Debian 10, kernel 4.19.111 | Klipper host, web UI, display, camera, Wi-Fi |
| Mainboard | **STM32F103 / GD32F303** (Klipper MCU firmware v0.10.0, FLSun fork) | steppers, heaters, sensors – connected via CH340 USB-serial |

The Rockchip boot ROM/SPL **prefers the SD card** (slot *SD1* on the sensor board in the top frame). If the card carries a Rockchip loader, U-Boot boots the card's `boot` partition. The FLSun boot image, however, always mounts the root file system from the eMMC (`root=PARTUUID=614e0000-0000`).

`scripts/make_sd_boot.py` therefore takes **your own** eMMC boot partition and changes exactly one kernel argument to `root=/dev/mmcblk2p6`. It also updates the checksums U-Boot verifies: the per-DTB **SHA1** in the Rockchip resource table (without it U-Boot reports *"Invalid DTB hash"* and refuses to boot) and the FIT **SHA256**. Kernel, drivers, display and touch timing stay FLSun's – that's why the display, touch, camera and Wi-Fi work out of the box.

The SD card gets the eMMC's partition layout, the copied loader/U-Boot, the patched boot image and a fresh **Debian 12 armhf** root file system built with `debootstrap` directly on the printer.

**Upstream Klipper (v0.13) talks to the unchanged FLSun mainboard firmware** (v0.10.0). Only the ADXL345 accelerometer doesn't work (protocol changed) – the input-shaper values from the stock calibration stay active.

---

## Tested with

| Component | Version |
|---|---|
| Printer | FLSun T1 Pro, stock firmware state 11/2025 (TUI) |
| Core board | CKDZ_DDHXB V2.3, RV1109, U-Boot 2017.09, kernel 4.19.111 (FLSun) |
| Wi-Fi | AP6212A (Broadcom bcmdhd, 2.4 GHz). *The AIC8800 variant is handled by the script but **untested**.* |
| Mainboard firmware | Klipper `v0.10.0-439-gdfa5afdf` (FLSun, unchanged) |
| SD card | SanDisk Extreme PLUS 32 GB |
| Debian | 12 (bookworm) armhf |
| KIAUH | v6.3.2 |
| Klipper | v0.13.0-800 |
| Moonraker | v0.11.0 |
| Mainsail | v2.19.0 |
| Crowsnest | v5.0.12 |
| KlipperScreen | v0.4.7 |

If your printer differs (other board revision, other FLSun update), the scripts stop at their checks instead of guessing. Please open an issue with the output.

---

## What works – and what doesn't

| Feature | Status |
|---|---|
| Printing, homing, delta calibration, bed mesh, probe | ✅ |
| Hotend relay (PD6), heaters, fans, filament sensor | ✅ |
| Mainsail, slicer upload ("upload and print" from FLSun Slicer/Orca) | ✅ |
| Webcam 1080p via Crowsnest | ✅ ~17 fps with auto exposure (30 fps possible with fixed exposure, but dark) |
| Chamber light as switch + macros | ✅ |
| KlipperScreen on the 480×272 touch display | ✅ (camera page disabled, see troubleshooting) |
| OctoEverywhere for Klipper, OctoApp companion | ✅ (KIAUH extensions) |
| Old G-code files from the FLSun profile | ✅ (bed mesh is loaded automatically) |
| ADXL345 / resonance measurement | ❌ needs flashed mainboard firmware |
| FLSun cloud, FLSun app, power-loss recovery, AI detection | ❌ FLSun-only |
| Box fan (PE2) | ❌ no function on the T1 Pro (also not in the stock system) |
| Klipper warnings about deprecated MCU code | ⚠️ expected and harmless (old firmware) |

---

## Requirements

* microSD card **≥ 16 GB** (32 GB recommended, A1/A2, good brand)
* PC with SSH client (Linux/macOS terminal, Windows: MobaXterm or PowerShell `ssh`)
* Wi-Fi with internet access (the printer downloads Debian packages)
* The SSH login of the stock system (user `pi`)
* About 2–3 hours, most of it waiting

---

## Step 0 – Back up the eMMC

Make a complete image of the eMMC on your PC **before anything else**. On the printer (stock system):

```bash
sudo systemctl stop klipper moonraker
sudo chmod o+r /dev/mmcblk0          # reset at the next reboot
```

On the PC:

```bash
ssh pi@<printer-ip> "dd if=/dev/mmcblk0 bs=4M status=none | gzip -1" > t1pro_emmc_backup.img.gz
```

Then reboot the printer. Keep this file private: it contains your Wi-Fi password, SSH keys and FLSun/cloud tokens.

---

## Step 1 – Prepare the stock system

Some stock images can't verify HTTPS certificates. Test and repair once:

```bash
wget -q --spider https://deb.debian.org/debian/dists/bookworm/Release && echo OK || sudo update-ca-certificates --fresh
```

Copy this repository to `/home/pi` on the printer, e.g. download the ZIP on your PC and copy it with `scp`, or with `git clone` if git is available on your stock system.

---

## Step 2 – Build the SD card

1. Boot the printer **without** the card (stock system).
2. **Then** insert the card into the SD slot of the sensor board (top frame, slot *SD1*). Don't confuse it with the slot on the mainboard, which is only for MCU firmware.
3. On the printer:

```bash
cd ~/flsun-t1pro-debian12-klipper/scripts
sudo HOSTNAME_NEW=t1pro-debian12 TZ_NEW=Europe/Berlin bash build_sd_card.sh
```

The script asks you to type `YES`, then:

1. reads your eMMC boot partition and patches it (`make_sd_boot.py` verifies every hash first)
2. creates the GPT on the card, with the eMMC layout and rootfs filling the card
3. copies U-Boot + misc and writes the patched boot image, then reads it back to verify
4. formats the rootfs and runs `debootstrap` for Debian 12 armhf (20–60 min)
5. copies the Wi-Fi driver/firmware, writes the network fix, hostname, fstab, sources and locale
6. creates a NetworkManager profile from `/etc/wpa_supplicant.conf` (the password is not displayed)
7. asks for the **password of user `pi`** on the new system
8. copies the Rockchip loader area **last**. Only then does the card become bootable.

Power off, wait 10 s, power on **with** the card.

---

## Step 3 – First boot

Wait 2–3 minutes, then:

```bash
ssh pi@t1pro-debian12.local        # or the IP from your router
```

The printer usually gets the same IP as in the stock system, because the MAC address is the same. Your SSH client will therefore warn about a **different host key**. That is expected, because it's a different system. Store it as an additional key for this host.

```bash
sudo apt update && sudo apt full-upgrade -y
findmnt -n -o SOURCE /             # must show /dev/mmcblk2p6
```

---

## Step 4 – Klipper, Moonraker, Mainsail (KIAUH)

The FLSun kernel has **no IPv6**. nginx' default site listens on `[::]` and won't start. Prepare nginx before KIAUH installs Mainsail:

```bash
printf '#!/bin/sh\nexit 101\n' | sudo tee /usr/sbin/policy-rc.d >/dev/null && sudo chmod +x /usr/sbin/policy-rc.d
sudo apt install -y nginx
sudo rm /usr/sbin/policy-rc.d
sudo sed -i 's/^\(\s*listen \[::\]\)/#\1/' /etc/nginx/sites-available/default
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
```

KIAUH:

```bash
cd ~ && git clone https://github.com/dw-0/kiauh.git
./kiauh/kiauh.sh
```

Install in this order: **Klipper** (Python 3, 1 instance), **Moonraker**, **Mainsail** (port 80), and when asked, the **mainsail-config**, which is needed for `mainsail.cfg`. **Crowsnest** comes later in step 7. Don't build or flash any MCU firmware.

If nginx complains about `[::]` again after the Mainsail install:

```bash
sudo sed -i 's/^\(\s*listen \[::\]\)/#\1/' /etc/nginx/sites-available/*
sudo nginx -t && sudo systemctl restart nginx
```

---

## Step 5 – printer.cfg

```bash
cd ~/flsun-t1pro-debian12-klipper
bash scripts/install_printer_cfg.sh --copy-gcodes
```

* installs [`config/printer.cfg`](config/printer.cfg)
* mounts the eMMC **read-only** and appends the **SAVE_CONFIG block of your stock printer.cfg**, i.e. your factory delta calibration, bed mesh, PID and input shaper
* `--copy-gcodes` also copies your G-code files from the stock system
* restarts Klipper, which should report `ready`

Later runs keep the SAVE_CONFIG block of your current printer.cfg, so your own calibration is never lost.

---

## Step 6 – First tests and calibration

**Important facts about the T1 Pro hardware:**

* **Relay PD6 powers the hotend heater.** FLSun's Klipper switched it automatically. The config does the same: it switches on at start and whenever the nozzle gets a target temperature. Never press `RELAY_OFF` while heating, or Klipper will shut down with "not heating at expected rate".
* **The probe is a pressure sensor that only reacts to a fast force rise.** Pushing the nozzle by hand always shows `probe: open`, even in the stock system. Don't use `QUERY_PROBE` as a test. `PROBE_ACCURACY` on the bed is the right test.
* Upstream reports `bed will contact at z = trigger - z_offset`. The target value is therefore ≈ 0.
* Upstream `M109`/`M190` wait for ±1 °C and a stable temperature. FLSun waited for ±3 °C. Heating up looks slower, but it isn't hanging.

**Calibration** (nozzle 140 °C, bed 60 °C; the macros heat and wait by themselves):

1. `G28`, then `PROBE_ACCURACY` in the middle of the bed
2. Run the macro **BED_LEVEL_1** (delta calibration, ends with SAVE_CONFIG/restart)
3. Run the macro **BED_LEVEL_2** (7×7 bed mesh, ends with SAVE_CONFIG/restart)
4. Print a 20 mm test cube. Fine-tune the first layer with Mainsail's Z offset or the macros `ZUP`/`ZDOWN`.

On the reference printer the delta radius changed by about 1 mm compared to the factory value. The test cube then measured 20.04 / 20.06 / 20.00 mm.

---

## Step 7 – Webcam (Crowsnest)

Install **Crowsnest** with KIAUH. Then replace the `[cam 1]` section of `~/printer_data/config/crowsnest.conf` with [`config/crowsnest-cam.conf`](config/crowsnest-cam.conf) and run `sudo systemctl restart crowsnest`.

In Mainsail → Settings → Webcams use the service **MJPEG-Streamer**. "Adaptive" shows the first picture faster, but delivers fewer frames.

Notes:

* The camera delivers MJPG 1080p at up to 30 fps. The frame rate depends on the exposure time: with fixed exposure ≤ 25 ms you get 30 fps, but in a normally lit room the image is too dark. With auto exposure you get about 17 fps and a good image.
* The camera resets the exposure to *auto* each time the stream starts. A fixed exposure from `crowsnest.conf` therefore doesn't stick.
* Crowsnest v5 calls controls with brackets in their V4L2 name differently: `exposure_absolute_`, with a trailing underscore. With the plain name, Crowsnest fails with a `KeyError`.
* The stock `pushStream` service (10 fps fixed) doesn't exist on the SD system.

---

## Step 8 – Chamber light

The chamber light is not on the mainboard. It hangs on **GPIO108 of the Linux board**. FLSun's `box_light.py` simply wrote `/sys/class/gpio/gpio108/value`.

```bash
bash scripts/setup_light.sh
```

The script:

* finds the right `/dev/gpiochipN` with a read-only query of bank `gpio3`, line 12
* installs a udev rule (group `gpio`)
* adds the Moonraker power device **`[power Light]`**, which is switched on at start

In Mainsail it then shows up as a switch. The printer.cfg also has the macros `LIGHT_ON`, `LIGHT_OFF` and the FLSun-compatible `F106 S1` / `F106 S0`.

---

## Step 9 – Touch display (KlipperScreen)

1. KIAUH → Install → **KlipperScreen**
   * Install standalone? → **Yes**
   * Backend X11 or Wayland? → **X11**. Wayland needs KMS/DRM features the 4.19 kernel lacks.
   * Install NetworkManager? → **No**. It is already running. "Yes" may restart it and drop your SSH session.
2. Then run:

```bash
bash scripts/setup_klipperscreen.sh
```

* **Touch:** The tlsc6x controller reports swapped axes. The script installs FLSun's own tslib calibration (`/etc/pointercal`) converted to a libinput `CalibrationMatrix`: [`system/99-t1pro-touch.conf`](system/99-t1pro-touch.conf).
* **Camera page hidden:** Opening the camera in KlipperScreen starts `mpv`. On this hardware it takes over the DRM output and leaves a frozen black screen until reboot. The webcam stays available in Mainsail.
* The Klipper warning about deprecated MCU code shows as a pop-up on every start. Tap it away.

480×272 is below KlipperScreen's official minimum (480×320), but it works. You can adjust font size and theme in KlipperScreen's settings.

---

## Step 10 – Optional: remote access

* **OctoEverywhere for Klipper:** KIAUH → Extensions → *OctoEverywhere for Klipper*. While the installer shows the link code, **don't press Ctrl+C**. In most terminals that aborts the installer, it doesn't copy. Mark the text with the mouse instead. Browser access is free.
* **OctoApp:** KIAUH → Extensions → *OctoApp for Klipper* (companion for notifications). In the free OctoEverywhere plan, app remote access through OctoApp requires a paid subscription. Free alternatives are the OctoEverywhere website in the phone browser, or a VPN to your home network (e.g. WireGuard on your router) with OctoApp set to "manual" and the local IP.
* OctoPrint is not needed. Mainsail/Moonraker cover everything and save RAM: the board has 715 MB usable.

---

## Slicer and old G-code files

**FLSun Slicer (Orca based):** Copy your T1 Pro printer profile, then:

* Start G-code: add `BED_MESH_PROFILE LOAD=default` after `G28`. Optional, the config loads the mesh at startup anyway.
* End G-code: remove `M104 S0 T1 Pro` (a bug in the FLSun template) and `TIMELAPSE_RENDER`.
* "Upload and print" from the preview works directly against Moonraker.

**Old G-code files** from the FLSun profile print as they are:

* they contain no `START_PRINT` and no mesh command → the config loads the bed mesh 2 s after Klipper starts. `G28` doesn't clear it.
* `M104 S0 T1 Pro` is ignored silently by Klipper (heater off for a non-existing extruder 1)
* `TIMELAPSE_*` → empty placeholder macros; `EXCLUDE_OBJECT_*` → `[exclude_object]` is enabled
* `SET_TMC_CURRENT STEPPER=extruder CURRENT=0.8` is FLSun's normal print current

---

## Backing up and restoring the SD card

Windows can't see the Linux partitions, so tools like Win32DiskImager don't work. Use the printer itself:

1. Boot the **stock system** without the card, then insert the card.
2. On the printer: `sudo chmod o+r /dev/mmcblk2`
3. On the PC:

```bash
ssh pi@<printer-ip> 'test "$(cat /sys/block/mmcblk2/device/type)" = SD && dd if=/dev/mmcblk2 bs=4M status=none | gzip -1' > t1pro_sd_backup.img.gz
```

4. Verify. Both values must be equal:
   * printer: `sudo sha256sum /dev/mmcblk2`
   * PC: `gzip -dc t1pro_sd_backup.img.gz | sha256sum`

**Restore** (stock system, card inserted after boot):

* printer: `sudo chmod o+rw /dev/mmcblk2`
* PC:

```bash
gzip -dc t1pro_sd_backup.img.gz | ssh pi@<printer-ip> 'test "$(cat /sys/block/mmcblk2/device/type)" = SD && dd of=/dev/mmcblk2 bs=4M conv=fsync'
```

A 32 GB card takes about 30–40 minutes.

---

## Klipper updates with the stock mainboard firmware

Upstream Klipper currently still supports the old MCU firmware v0.10.0. Klipper shows two harmless warnings: `spi_set_sw_bus` is missing, and *deprecated code / STEPPER_STEP_BOTH_EDGE*. A future update may drop that support. Klipper then stops with a *protocol* or *command format mismatch* error.

Recommendations:

* Before updating, look at the changes (`git log` in `~/klipper`, or the commits on GitHub) for anything that touches `klippy/mcu.py`, `serialhdl.py` or MCU protocol changes.
* Keep an SD card backup. If an update breaks the connection, restore the image, or go back to the previous version with `git -C ~/klipper checkout <old-commit>` and restart Klipper.

---

## Flashing the mainboard (not done)

This project **deliberately does not flash** the mainboard. Once current Klipper firmware is on the MCU, the **stock system can no longer print**, because it only speaks with its FLSun firmware. "Card out = stock system" would then be gone, unless the original firmware was saved first.

Known facts, see [mulcmu/T1-pyro](https://github.com/mulcmu/T1-pyro):

* MCU STM32F103 / GD32F303 ("Robin Nano 3.5" bootloader)
* flash via the microSD slot **on the mainboard** with `Robin_nano35.bin`
* Klipper menuconfig there: STM32F103, 28 KiB bootloader, 8 MHz crystal, serial USART3 (PB11/PB10), 250000 baud
* Nobody has published a backup of the stock MCU firmware yet. Reading it requires an ST-Link via SWD (PA13/PA14) and works only if read protection is off.

After flashing, re-enable `[adxl345]` / `[resonance_tester]` in printer.cfg.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Card doesn't boot, display stays black | The boot image was changed without updating the RSCE SHA1 ("Invalid DTB hash"). Always use `make_sd_boot.py` on the **original** eMMC boot partition. |
| Wi-Fi `config-failed`, NetworkManager gives up | bcmdhd can't change its MAC → [`system/90-t1pro-bcmdhd.conf`](system/90-t1pro-bcmdhd.conf), profile with `autoconnect-retries=0` (both done by the build script) |
| nginx won't start | no IPv6 in the kernel → comment out `listen [::]` (step 4) |
| `probe: open` when pushing the nozzle | normal, the dynamic pressure sensor reacts only during a move → use `PROBE_ACCURACY` |
| "Heater extruder not heating at expected rate" | relay PD6 off → use the config from this repo, don't press RELAY_OFF while heating |
| BED_LEVEL seems to hang while heating | the strict upstream M109 wait; the macros here use `TEMPERATURE_WAIT` |
| "Command format mismatch: query_adxl345" | old MCU firmware → keep `[adxl345]` disabled |
| Heightmap empty after restart | upstream no longer loads the mesh; this config loads it at startup |
| KlipperScreen: black, frozen screen after "Camera" | mpv takes over the DRM output → reboot, run `setup_klipperscreen.sh` (hides the page) |
| Touch hits the wrong place | `system/99-t1pro-touch.conf` missing → `setup_klipperscreen.sh` |
| Crowsnest `KeyError: 'exposure_absolute'` | Crowsnest v5 name is `exposure_absolute_` |
| Light switch: "device or resource busy" | GPIO108 still exported via sysfs → `echo 108 \| sudo tee /sys/class/gpio/unexport` |
| A few `grep` zombie processes under polkitd | harmless; `sudo systemctl restart polkit` clears them |
| Pasted multi-line commands "disappear" | the first `sudo` asked for the password and swallowed the pasted lines → run `sudo -v` first |
| Stock system hangs at the FLSun logo | its TUI sometimes takes a few minutes (waits for Klipper/network) |

---

## Repository layout

```
config/printer.cfg            printer.cfg for upstream Klipper (SAVE_CONFIG block added by the install script)
config/crowsnest-cam.conf     [cam 1] for crowsnest.conf
config/moonraker-light.conf   [power Light] example (setup_light.sh writes it)
system/90-t1pro-bcmdhd.conf   NetworkManager fix for the bcmdhd Wi-Fi
system/99-t1pro-touch.conf    touch calibration for X/libinput
system/60-gpiochip.rules      udev rule for the light GPIO
scripts/make_sd_boot.py       patch YOUR eMMC boot partition for SD boot (verifies all hashes)
scripts/build_sd_card.sh      build the SD card (run in the stock system)
scripts/install_printer_cfg.sh  install printer.cfg + your calibration (+ G-codes)
scripts/setup_light.sh        chamber light as Moonraker power device
scripts/setup_klipperscreen.sh  touch calibration + hide KlipperScreen camera page
```

No FLSun binaries, images or keys are included. Everything is created from **your own** printer.

---

## Credits

* [Klipper](https://github.com/Klipper3d/klipper), [Moonraker](https://github.com/Arksine/moonraker), [Mainsail](https://github.com/mainsail-crew/mainsail), [Crowsnest](https://github.com/mainsail-crew/crowsnest), [KlipperScreen](https://github.com/KlipperScreen/KlipperScreen), [KIAUH](https://github.com/dw-0/kiauh)
* [mulcmu/T1-pyro](https://github.com/mulcmu/T1-pyro): T1 Pro hardware and mainboard flashing research
* [Guilouz/FLSUN-S1-Open-Source-Edition](https://github.com/Guilouz): open-source OS for the related FLSun S1
* The FLSun T1/T1 Pro community discussions on GitHub
* Author: **BehaviorBean**. Developed with the help of an AI assistant (Claude).

## License

[GPL-3.0](LICENSE), like Klipper. Configuration parts are derived from the FLSun stock configuration and from Klipper/Mainsail examples.
