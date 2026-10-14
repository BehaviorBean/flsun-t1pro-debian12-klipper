# FLSun T1 Pro – Debian 12 + Upstream-Klipper von der SD-Karte

**English version: [README.md](README.md)**

Mit diesem Projekt läuft auf dem FLSun T1 Pro ein sauberer, aktueller Software-Stand **von einer microSD-Karte**: **Debian 12 (bookworm)**, **Upstream-Klipper**, Moonraker, Mainsail, Crowsnest und KlipperScreen. Das Werksystem auf dem eMMC bleibt dabei unangetastet, und das **Mainboard wird nicht geflasht**.

* **Karte drin** → Debian 12 mit Upstream-Klipper
* **Karte raus** → das unveränderte FLSun-Werksystem startet wie gewohnt

> ⚠️ **Inoffizielles Community-Projekt – Nutzung auf eigene Gefahr.** Keine Verbindung zu FLSun. Entwickelt und getestet an **einem** Drucker (siehe [Getestet mit](#getestet-mit)). Die Skripte lesen das eMMC nur und schreiben ausschließlich auf die SD-Karte. Ein Fehler mit `dd` oder ein falsches Gerät kann trotzdem Daten kosten. Erst die Sicherungen aus Schritt 0 machen und jeden Schritt vor dem Ausführen lesen.

> **Stand der Skripte (bitte lesen):** Alles Beschriebene läuft auf dem Referenzdrucker. Die Skripte fassen die Befehle aus der Entwicklung zusammen:
> `make_sd_boot.py` erzeugt das funktionierende Boot-Image **byte-genau** nach. Die `printer.cfg` ist offline gegen Upstream-Klipper und das Protokoll der Werks-MCU geprüft.
> `build_sd_card.sh`, `install_printer_cfg.sh`, `setup_light.sh` und `setup_klipperscreen.sh` sind **erste öffentliche Fassungen** und wurden in genau dieser Form noch nicht komplett durchlaufen. Sie halten an ihren Sicherheitsprüfungen an. Bitte meldet die Ausgabe der ersten Durchläufe in einem Issue.

---

## Inhalt

- [So funktioniert es](#so-funktioniert-es)
- [Getestet mit](#getestet-mit)
- [Was geht – und was nicht](#was-geht--und-was-nicht)
- [Voraussetzungen](#voraussetzungen)
- [Schritt 0 – eMMC sichern](#schritt-0--emmc-sichern)
- [Schritt 1 – Werksystem vorbereiten](#schritt-1--werksystem-vorbereiten)
- [Schritt 2 – SD-Karte bauen](#schritt-2--sd-karte-bauen)
- [Schritt 3 – Erster Start](#schritt-3--erster-start)
- [Schritt 4 – Klipper, Moonraker, Mainsail (KIAUH)](#schritt-4--klipper-moonraker-mainsail-kiauh)
- [Schritt 5 – printer.cfg](#schritt-5--printercfg)
- [Schritt 6 – Erste Tests und Kalibrierung](#schritt-6--erste-tests-und-kalibrierung)
- [Schritt 7 – Webcam (Crowsnest)](#schritt-7--webcam-crowsnest)
- [Schritt 8 – Bauraumlicht](#schritt-8--bauraumlicht)
- [Schritt 9 – Touch-Display (KlipperScreen)](#schritt-9--touch-display-klipperscreen)
- [Schritt 10 – Optional: Fernzugriff](#schritt-10--optional-fernzugriff)
- [Slicer und alte G-Code-Dateien](#slicer-und-alte-g-code-dateien)
- [SD-Karte sichern und zurückspielen](#sd-karte-sichern-und-zurückspielen)
- [Klipper-Updates mit der Werks-Mainboard-Firmware](#klipper-updates-mit-der-werks-mainboard-firmware)
- [Mainboard flashen (nicht umgesetzt)](#mainboard-flashen-nicht-umgesetzt)
- [Fehlersuche](#fehlersuche)
- [Aufbau des Repositorys](#aufbau-des-repositorys)
- [Danksagung](#danksagung) · [Lizenz](#lizenz)

---

## So funktioniert es

Der T1 Pro hat zwei Rechner:

| Platine | Chip | Aufgabe |
|---|---|---|
| Core-Board (Linux) | Rockchip **RV1109**, 8 GB eMMC, FLSun-Debian 10, Kernel 4.19.111 | Klipper-Host, Weboberfläche, Display, Kamera, WLAN |
| Mainboard | **STM32F103 / GD32F303** (Klipper-MCU-Firmware v0.10.0, FLSun-Fork) | Motoren, Heizungen, Sensoren – per CH340 USB-Seriell angebunden |

Boot-ROM und SPL von Rockchip **bevorzugen die SD-Karte**. Gemeint ist der Slot *SD1* auf dem Sensorboard im oberen Rahmen. Liegt auf der Karte ein Rockchip-Lader, startet U-Boot die `boot`-Partition der Karte. Das FLSun-Boot-Image hängt aber immer das Root-Dateisystem vom eMMC ein (`root=PARTUUID=614e0000-0000`).

`scripts/make_sd_boot.py` nimmt deshalb **deine eigene** eMMC-Boot-Partition und ändert genau ein Kernel-Argument auf `root=/dev/mmcblk2p6`. Außerdem aktualisiert es die Prüfsummen, die U-Boot kontrolliert:

* die **SHA1** jeder DTB in der Rockchip-Resource-Tabelle. Ohne sie meldet U-Boot *„Invalid DTB hash“* und startet nicht.
* die **SHA256** im FIT-Header.

Kernel, Treiber sowie Display- und Touch-Timing bleiben die von FLSun. Deshalb laufen Display, Touch, Kamera und WLAN sofort.

Die SD-Karte bekommt die Partitionsaufteilung des eMMC, den kopierten Lader und U-Boot, das gepatchte Boot-Image und ein frisches **Debian 12 armhf**. Das Debian wird per `debootstrap` direkt auf dem Drucker gebaut.

**Upstream-Klipper (v0.13) spricht mit der unveränderten FLSun-Mainboard-Firmware** (v0.10.0). Nur der Beschleunigungssensor ADXL345 funktioniert nicht, weil sich sein Protokoll geändert hat. Die Input-Shaper-Werte aus der Werkskalibrierung bleiben aktiv.

---

## Getestet mit

| Komponente | Version |
|---|---|
| Drucker | FLSun T1 Pro, Werks-Firmwarestand 11/2025 (TUI) |
| Core-Board | CKDZ_DDHXB V2.3, RV1109, U-Boot 2017.09, Kernel 4.19.111 (FLSun) |
| WLAN | AP6212A (Broadcom bcmdhd, 2,4 GHz). *Die AIC8800-Variante berücksichtigt das Skript, sie ist aber **ungetestet**.* |
| Mainboard-Firmware | Klipper `v0.10.0-439-gdfa5afdf` (FLSun, unverändert) |
| SD-Karte | SanDisk Extreme PLUS 32 GB |
| Debian | 12 (bookworm) armhf |
| KIAUH | v6.3.2 |
| Klipper | v0.13.0-800 |
| Moonraker | v0.11.0 |
| Mainsail | v2.19.0 |
| Crowsnest | v5.0.12 |
| KlipperScreen | v0.4.7 |

Weicht dein Drucker ab, etwa mit einer anderen Platinenrevision oder einem anderen FLSun-Update, brechen die Skripte bei ihren Prüfungen ab, statt zu raten. Bitte dann ein Issue mit der Ausgabe eröffnen.

---

## Was geht – und was nicht

| Funktion | Stand |
|---|---|
| Drucken, Homing, Delta-Kalibrierung, Bettnetz, Probe | ✅ |
| Hotend-Relais (PD6), Heizungen, Lüfter, Filamentsensor | ✅ |
| Mainsail, Upload aus dem Slicer („Hochladen und drucken“ im FLSun Slicer/Orca) | ✅ |
| Webcam 1080p über Crowsnest | ✅ ca. 17 fps mit Belichtungsautomatik (30 fps mit fester Belichtung möglich, aber dunkel) |
| Bauraumlicht als Schalter + Makros | ✅ |
| KlipperScreen auf dem 480×272-Touchdisplay | ✅ (Kamera-Seite deaktiviert, siehe Fehlersuche) |
| OctoEverywhere für Klipper, OctoApp-Begleitdienst | ✅ (KIAUH-Erweiterungen) |
| Alte G-Code-Dateien aus dem FLSun-Profil | ✅ (Bettnetz wird automatisch geladen) |
| ADXL345 / Resonanzmessung | ❌ braucht geflashte Mainboard-Firmware |
| FLSun-Cloud, FLSun-App, Power-Loss-Recovery, KI-Erkennung | ❌ nur FLSun |
| Box-Lüfter (PE2) | ❌ beim T1 Pro ohne Funktion (auch im Werksystem) |
| Klipper-Warnungen zu veraltetem MCU-Code | ⚠️ erwartet und harmlos (alte Firmware) |

---

## Voraussetzungen

* microSD-Karte **ab 16 GB** (32 GB empfohlen, A1/A2, Markenkarte)
* PC mit SSH-Programm (Linux/macOS: Terminal, Windows: MobaXterm oder PowerShell `ssh`)
* WLAN mit Internetzugang, denn der Drucker lädt die Debian-Pakete selbst
* Der SSH-Zugang zum Werksystem (Benutzer `pi`)
* Etwa 2–3 Stunden, davon das meiste Warten

---

## Schritt 0 – eMMC sichern

Mach **zuerst** ein vollständiges Abbild des eMMC auf den PC. Auf dem Drucker (Werksystem):

```bash
sudo systemctl stop klipper moonraker
sudo chmod o+r /dev/mmcblk0          # gilt bis zum nächsten Neustart
```

Auf dem PC:

```bash
ssh pi@<drucker-ip> "dd if=/dev/mmcblk0 bs=4M status=none | gzip -1" > t1pro_emmc_backup.img.gz
```

Danach den Drucker neu starten. Die Datei bitte nicht weitergeben. Sie enthält dein WLAN-Passwort, SSH-Schlüssel und FLSun- bzw. Cloud-Zugangsdaten.

---

## Schritt 1 – Werksystem vorbereiten

Manche Werks-Images können HTTPS-Zertifikate nicht prüfen. Einmal testen und bei Bedarf reparieren:

```bash
wget -q --spider https://deb.debian.org/debian/dists/bookworm/Release && echo OK || sudo update-ca-certificates --fresh
```

Dieses Repository nach `/home/pi` auf den Drucker kopieren. Zum Beispiel lädst du das ZIP auf den PC und kopierst es per `scp`. Ist git im Werksystem vorhanden, geht auch `git clone`.

---

## Schritt 2 – SD-Karte bauen

1. Drucker **ohne** Karte starten (Werksystem).
2. **Danach** die Karte in den SD-Slot des Sensorboards stecken (oberer Rahmen, Slot *SD1*). Nicht verwechseln mit dem Slot auf dem Mainboard, der nur für die MCU-Firmware da ist.
3. Auf dem Drucker:

```bash
cd ~/flsun-t1pro-debian12-klipper/scripts
sudo HOSTNAME_NEW=t1pro-debian12 TZ_NEW=Europe/Berlin LOCALES="de_DE.UTF-8 en_US.UTF-8" bash build_sd_card.sh
```

Das Skript verlangt die Eingabe `YES` und erledigt dann der Reihe nach:

1. eMMC-Boot-Partition lesen und patchen. `make_sd_boot.py` prüft vorher alle Prüfsummen.
2. GPT auf der Karte anlegen: Aufteilung wie das eMMC, rootfs bis zum Kartenende.
3. U-Boot und misc kopieren, das gepatchte Boot-Image schreiben und zur Kontrolle zurücklesen.
4. rootfs formatieren und `debootstrap` für Debian 12 armhf ausführen. Das dauert 20–60 Minuten.
5. WLAN-Treiber und Firmware übernehmen, WLAN-Fix, Hostname, fstab, Paketquellen und Sprache setzen.
6. NetworkManager-Profil aus `/etc/wpa_supplicant.conf` erzeugen. Das Passwort wird dabei nicht angezeigt.
7. Nach dem **Passwort für den Benutzer `pi`** im neuen System fragen.
8. Den Rockchip-Lader-Bereich **zuletzt** kopieren. Erst damit wird die Karte startfähig.

Danach ausschalten, 10 s warten und **mit** Karte einschalten.

---

## Schritt 3 – Erster Start

2–3 Minuten warten, dann:

```bash
ssh pi@t1pro-debian12.local        # oder die IP aus dem Router
```

Meist bekommt der Drucker dieselbe IP wie im Werksystem, weil die MAC-Adresse gleich ist. Das SSH-Programm warnt deshalb vor einem **anderen Host-Key**. Das ist richtig so, denn es ist ein anderes System. Speichere den Schlüssel zusätzlich für diesen Host.

```bash
sudo apt update && sudo apt full-upgrade -y
findmnt -n -o SOURCE /             # muss /dev/mmcblk2p6 zeigen
```

---

## Schritt 4 – Klipper, Moonraker, Mainsail (KIAUH)

Der FLSun-Kernel hat **kein IPv6**. Die nginx-Standardseite lauscht auf `[::]` und startet deshalb nicht. Bereite nginx vor, bevor KIAUH Mainsail installiert:

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

In dieser Reihenfolge installieren:

1. **Klipper** (Python 3, 1 Instanz)
2. **Moonraker**
3. **Mainsail** (Port 80) und, wenn gefragt, die **mainsail-config**. Die wird für `mainsail.cfg` gebraucht.

**Crowsnest** folgt später in Schritt 7. **Keine** MCU-Firmware bauen oder flashen.

Meckert nginx nach der Mainsail-Installation wieder wegen `[::]`:

```bash
sudo sed -i 's/^\(\s*listen \[::\]\)/#\1/' /etc/nginx/sites-available/*
sudo nginx -t && sudo systemctl restart nginx
```

---

## Schritt 5 – printer.cfg

```bash
cd ~/flsun-t1pro-debian12-klipper
bash scripts/install_printer_cfg.sh --copy-gcodes
```

Das Skript:

* installiert [`config/printer.cfg`](config/printer.cfg)
* hängt das eMMC **nur lesend** ein und übernimmt den **SAVE_CONFIG-Block deiner Werks-printer.cfg**. Das sind deine werksseitige Delta-Kalibrierung, das Bettnetz, die PID-Werte und der Input Shaper.
* kopiert mit `--copy-gcodes` zusätzlich deine G-Code-Dateien aus dem Werksystem
* startet Klipper neu. Danach sollte `ready` erscheinen.

Spätere Aufrufe behalten den SAVE_CONFIG-Block der aktuellen printer.cfg. Deine eigene Kalibrierung geht also nie verloren.

---

## Schritt 6 – Erste Tests und Kalibrierung

**Wichtig zur T1-Pro-Hardware:**

* **Das Relais PD6 versorgt die Hotend-Heizung.** FLSuns Klipper hat es automatisch geschaltet, die Konfig macht das genauso: an beim Start und immer dann, wenn die Düse eine Zieltemperatur bekommt. Drück während des Heizens nie `RELAY_OFF`. Sonst schaltet Klipper mit „not heating at expected rate“ ab.
* **Die Probe ist ein Drucksensor, der nur auf einen schnellen Kraftanstieg reagiert.** Drückst du die Düse von Hand, zeigt sie immer `probe: open`, auch im Werksystem. `QUERY_PROBE` ist daher kein Test. Der richtige Test ist `PROBE_ACCURACY` auf dem Bett.
* Upstream meldet `bed will contact at z = Auslösehöhe − z_offset`. Der Sollwert ist also ≈ 0.
* Upstream-`M109`/`M190` warten auf ±1 °C und eine stabile Temperatur. FLSun hat auf ±3 °C gewartet. Das Aufheizen wirkt deshalb länger, hängt aber nicht.

**Kalibrierung** (Düse 140 °C, Bett 60 °C, die Makros heizen und warten selbst):

1. `G28`, dann `PROBE_ACCURACY` in der Bettmitte
2. Makro **BED_LEVEL_1** ausführen: Delta-Kalibrierung, am Ende SAVE_CONFIG mit Neustart
3. Makro **BED_LEVEL_2** ausführen: Bettnetz 7×7, am Ende SAVE_CONFIG mit Neustart
4. Einen 20-mm-Testwürfel drucken. Die erste Schicht stellst du über den Z-Offset in Mainsail oder die Makros `ZUP`/`ZDOWN` fein ein.

Beim Referenzdrucker änderte sich der Delta-Radius gegenüber dem Werkswert um etwa 1 mm. Der Testwürfel maß danach 20,04 / 20,06 / 20,00 mm.

---

## Schritt 7 – Webcam (Crowsnest)

Installiere **Crowsnest** über KIAUH. Ersetze dann in `~/printer_data/config/crowsnest.conf` den Abschnitt `[cam 1]` durch [`config/crowsnest-cam.conf`](config/crowsnest-cam.conf) und führ `sudo systemctl restart crowsnest` aus.

Wähle in Mainsail unter Einstellungen → Webcams den Dienst **MJPEG-Streamer**. „Adaptive“ zeigt das erste Bild zwar schneller, liefert aber weniger Bilder pro Sekunde.

Hinweise:

* **Bildrate:** Die Kamera liefert MJPG 1080p mit bis zu 30 fps. Wie viele es tatsächlich sind, hängt von der Belichtung ab. Mit fester Belichtung ≤ 25 ms sind 30 fps drin, im normal hellen Raum ist das Bild dann aber zu dunkel. Mit Belichtungsautomatik sind es rund 17 fps bei gutem Bild.
* **Belichtung:** Die Kamera stellt die Belichtung bei jedem Stream-Start auf Automatik zurück. Eine feste Belichtung in `crowsnest.conf` hält deshalb nicht.
* **Reglernamen:** Crowsnest v5 benennt Regler mit Klammern im V4L2-Namen anders, nämlich `exposure_absolute_` mit Unterstrich am Ende. Mit dem normalen Namen bricht Crowsnest mit einem `KeyError` ab.
* Den Werks-Dienst `pushStream` (fest 10 fps) gibt es im SD-System nicht.

---

## Schritt 8 – Bauraumlicht

Das Licht hängt nicht am Mainboard, sondern an **GPIO108 des Linux-Boards**. FLSuns `box_light.py` hat einfach in `/sys/class/gpio/gpio108/value` geschrieben.

```bash
bash scripts/setup_light.sh
```

Das Skript:

* ermittelt den passenden `/dev/gpiochipN`. Dafür fragt es Bank `gpio3`, Leitung 12 nur lesend ab.
* installiert eine udev-Regel (Gruppe `gpio`)
* legt den Moonraker-Schalter **`[power Light]`** an, der beim Start einschaltet

In Mainsail erscheint das Licht dann als Schalter. Dazu bringt die printer.cfg die Makros `LIGHT_ON` und `LIGHT_OFF` mit sowie das FLSun-kompatible `F106 S1` / `F106 S0`.

---

## Schritt 9 – Touch-Display (KlipperScreen)

1. Installiere über KIAUH → Install → **KlipperScreen** und beantworte die Fragen so:
   * Install standalone? → **Ja**
   * X11 oder Wayland? → **X11**, weil Wayland KMS/DRM-Funktionen braucht, die der 4.19-Kernel nicht hat.
   * NetworkManager installieren? → **Nein**. Er läuft schon, und mit „Ja“ kann er neu starten und deine SSH-Verbindung trennen.
2. Danach:

```bash
bash scripts/setup_klipperscreen.sh
```

* **Touch:** Der tlsc6x-Controller meldet vertauschte Achsen. Das Skript installiert FLSuns eigene tslib-Kalibrierung aus `/etc/pointercal`, umgerechnet in eine libinput-`CalibrationMatrix`: [`system/99-t1pro-touch.conf`](system/99-t1pro-touch.conf).
* **Kamera-Seite ausgeblendet:** Die Kamera in KlipperScreen startet `mpv`. Auf dieser Hardware übernimmt mpv die DRM-Ausgabe und hinterlässt ein eingefrorenes schwarzes Bild bis zum Neustart. Die Webcam bleibt in Mainsail verfügbar.
* Die Klipper-Warnung zu veraltetem MCU-Code erscheint bei jedem Start als Popup. Einfach wegtippen.

480×272 liegt unter dem offiziellen KlipperScreen-Minimum von 480×320, funktioniert aber. Schriftgröße und Theme lassen sich in den KlipperScreen-Einstellungen anpassen.

---

## Schritt 10 – Optional: Fernzugriff

* **OctoEverywhere for Klipper:** KIAUH → Extensions → *OctoEverywhere for Klipper*. Während der Installer den Verknüpfungscode zeigt, **nicht Strg+C drücken**. Das bricht den Installer in den meisten Terminals ab, statt zu kopieren. Markier den Text stattdessen mit der Maus. Der Zugriff über den Browser ist kostenlos.
* **OctoApp:** KIAUH → Extensions → *OctoApp for Klipper* (Begleitdienst für Benachrichtigungen). Im kostenlosen OctoEverywhere-Tarif setzt der Fernzugriff per OctoApp ein Abo voraus. Kostenlose Alternativen sind die OctoEverywhere-Webseite im Handy-Browser oder ein VPN ins Heimnetz (z. B. WireGuard am Router) mit OctoApp auf „Manuell“ und der lokalen IP.
* OctoPrint wird nicht gebraucht. Mainsail und Moonraker decken alles ab und sparen Arbeitsspeicher, denn das Board hat 715 MB nutzbar.

---

## Slicer und alte G-Code-Dateien

**FLSun Slicer (auf Orca-Basis):** Kopiere dein T1-Pro-Druckerprofil und passe die Kopie an:

* Start-G-Code: nach `G28` die Zeile `BED_MESH_PROFILE LOAD=default` einfügen. Das ist optional, weil die Konfig das Netz ohnehin beim Start lädt.
* End-G-Code: `M104 S0 T1 Pro` (ein Fehler in der FLSun-Vorlage) und `TIMELAPSE_RENDER` entfernen.
* „Hochladen und drucken“ aus der Vorschau funktioniert direkt mit Moonraker.

**Alte G-Code-Dateien** aus dem FLSun-Profil drucken unverändert:

* Sie enthalten kein `START_PRINT` und keinen Netz-Befehl. Die Konfig lädt das Bettnetz deshalb 2 s nach dem Klipper-Start, und `G28` löscht es nicht.
* `M104 S0 T1 Pro` ignoriert Klipper still. Es bedeutet „Heizung aus“ für einen nicht vorhandenen Extruder 1.
* Für `TIMELAPSE_*` gibt es leere Platzhalter-Makros. Für `EXCLUDE_OBJECT_*` ist `[exclude_object]` aktiv.
* `SET_TMC_CURRENT STEPPER=extruder CURRENT=0.8` ist FLSuns normaler Druckstrom.

---

## SD-Karte sichern und zurückspielen

Windows sieht die Linux-Partitionen nicht, daher funktionieren Programme wie Win32DiskImager nicht. Das Sichern läuft deshalb über den Drucker selbst:

1. **Werksystem** ohne Karte starten, danach die Karte einstecken.
2. Auf dem Drucker: `sudo chmod o+r /dev/mmcblk2`
3. Auf dem PC:

```bash
ssh pi@<drucker-ip> 'test "$(cat /sys/block/mmcblk2/device/type)" = SD && dd if=/dev/mmcblk2 bs=4M status=none | gzip -1' > t1pro_sd_backup.img.gz
```

4. Gegenprüfen. Beide Werte müssen gleich sein:
   * Drucker: `sudo sha256sum /dev/mmcblk2`
   * PC: `gzip -dc t1pro_sd_backup.img.gz | sha256sum`

**Zurückspielen** (Werksystem, Karte nach dem Start eingesteckt):

* Drucker: `sudo chmod o+rw /dev/mmcblk2`
* PC:

```bash
gzip -dc t1pro_sd_backup.img.gz | ssh pi@<drucker-ip> 'test "$(cat /sys/block/mmcblk2/device/type)" = SD && dd of=/dev/mmcblk2 bs=4M conv=fsync'
```

Eine 32-GB-Karte braucht etwa 30–40 Minuten.

---

## Klipper-Updates mit der Werks-Mainboard-Firmware

Upstream-Klipper unterstützt die alte MCU-Firmware v0.10.0 derzeit noch. Zwei Warnungen zeigt Klipper dabei an, beide sind harmlos: `spi_set_sw_bus` fehlt, und *deprecated code / STEPPER_STEP_BOTH_EDGE*. Ein späteres Update kann diese Unterstützung beenden. Dann bleibt Klipper mit *protocol* oder *command format mismatch* stehen.

Empfehlungen:

* **Vor dem Update** die Änderungen anschauen, also `git log` in `~/klipper` oder die Commits auf GitHub. Achte auf alles, was `klippy/mcu.py`, `serialhdl.py` oder das MCU-Protokoll betrifft.
* **SD-Sicherung bereithalten.** Bricht ein Update die Verbindung, spielst du das Abbild zurück. Alternativ gehst du mit `git -C ~/klipper checkout <alter-commit>` auf den vorigen Stand zurück und startest Klipper neu.

---

## Mainboard flashen (nicht umgesetzt)

Dieses Projekt flasht das Mainboard **bewusst nicht**. Sobald eine aktuelle Klipper-Firmware auf der MCU ist, **kann das Werksystem nicht mehr drucken**. Es spricht nur mit seiner FLSun-Firmware. „Karte raus = Werksystem“ wäre damit vorbei, es sei denn, die Original-Firmware wurde vorher gesichert.

Bekannt ist bisher, siehe [mulcmu/T1-pyro](https://github.com/mulcmu/T1-pyro):

* Die MCU ist ein STM32F103 / GD32F303 mit Bootloader „Robin Nano 3.5“.
* Geflasht wird über den microSD-Slot **auf dem Mainboard** mit `Robin_nano35.bin`.
* Klipper-menuconfig dort: STM32F103, 28 KiB Bootloader, 8-MHz-Quarz, Serial USART3 (PB11/PB10), 250000 Baud.
* Eine Sicherung der Werks-MCU-Firmware hat noch niemand veröffentlicht. Auslesen ginge nur mit einem ST-Link über SWD (PA13/PA14), und nur wenn kein Ausleseschutz aktiv ist.

Nach einem Flash in der printer.cfg `[adxl345]` und `[resonance_tester]` wieder aktivieren.

---

## Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| Karte startet nicht, Display bleibt schwarz | Boot-Image wurde geändert, ohne die RSCE-SHA1 anzupassen („Invalid DTB hash“). Immer `make_sd_boot.py` auf die **originale** eMMC-Boot-Partition anwenden. |
| WLAN `config-failed`, NetworkManager gibt auf | bcmdhd kann die MAC nicht ändern → [`system/90-t1pro-bcmdhd.conf`](system/90-t1pro-bcmdhd.conf), Profil mit `autoconnect-retries=0` (beides macht das Build-Skript) |
| nginx startet nicht | kein IPv6 im Kernel → `listen [::]` auskommentieren (Schritt 4) |
| `probe: open` beim Drücken der Düse | normal, der dynamische Drucksensor reagiert nur bei Bewegung → `PROBE_ACCURACY` nutzen |
| „Heater extruder not heating at expected rate“ | Relais PD6 aus → Konfig aus diesem Repo verwenden, beim Heizen kein RELAY_OFF |
| BED_LEVEL scheint beim Aufheizen zu hängen | strenges Upstream-M109; die Makros hier nutzen `TEMPERATURE_WAIT` |
| „Command format mismatch: query_adxl345“ | alte MCU-Firmware → `[adxl345]` deaktiviert lassen |
| Heightmap nach Neustart leer | Upstream lädt das Netz nicht mehr; diese Konfig lädt es beim Start |
| KlipperScreen nach „Kamera“ schwarz und eingefroren | mpv übernimmt die DRM-Ausgabe → Neustart, `setup_klipperscreen.sh` (blendet die Seite aus) |
| Touch trifft daneben | `system/99-t1pro-touch.conf` fehlt → `setup_klipperscreen.sh` |
| Crowsnest `KeyError: 'exposure_absolute'` | Name in Crowsnest v5 ist `exposure_absolute_` |
| Lichtschalter: „device or resource busy“ | GPIO108 noch per sysfs freigegeben → `echo 108 \| sudo tee /sys/class/gpio/unexport` |
| Einige `grep`-Zombieprozesse unter polkitd | harmlos; `sudo systemctl restart polkit` räumt auf |
| Eingefügte mehrzeilige Befehle „verschwinden“ | das erste `sudo` fragt nach dem Passwort und schluckt die eingefügten Zeilen → vorher `sudo -v` |
| Werksystem hängt am FLSun-Logo | die TUI braucht manchmal einige Minuten (wartet auf Klipper/Netz) |

---

## Aufbau des Repositorys

```
config/printer.cfg            printer.cfg für Upstream-Klipper (SAVE_CONFIG-Block ergänzt das Installationsskript)
config/crowsnest-cam.conf     [cam 1] für crowsnest.conf
config/moonraker-light.conf   Beispiel [power Light] (schreibt setup_light.sh)
system/90-t1pro-bcmdhd.conf   NetworkManager-Fix für das bcmdhd-WLAN
system/99-t1pro-touch.conf    Touch-Kalibrierung für X/libinput
system/60-gpiochip.rules      udev-Regel für den Licht-GPIO
scripts/make_sd_boot.py       DEINE eMMC-Boot-Partition für SD-Start patchen (prüft alle Hashes)
scripts/build_sd_card.sh      SD-Karte bauen (im Werksystem ausführen)
scripts/install_printer_cfg.sh  printer.cfg + deine Kalibrierung (+ G-Codes) einspielen
scripts/setup_light.sh        Bauraumlicht als Moonraker-Schalter
scripts/setup_klipperscreen.sh  Touch-Kalibrierung + Kamera-Seite in KlipperScreen ausblenden
```

Es sind keine FLSun-Binärdateien, Images oder Schlüssel enthalten. Alles wird aus **deinem eigenen** Drucker erzeugt.

---

## Danksagung

* [Klipper](https://github.com/Klipper3d/klipper), [Moonraker](https://github.com/Arksine/moonraker), [Mainsail](https://github.com/mainsail-crew/mainsail), [Crowsnest](https://github.com/mainsail-crew/crowsnest), [KlipperScreen](https://github.com/KlipperScreen/KlipperScreen), [KIAUH](https://github.com/dw-0/kiauh)
* [mulcmu/T1-pyro](https://github.com/mulcmu/T1-pyro): Recherche zur T1-Pro-Hardware und zum Mainboard-Flash
* [Guilouz/FLSUN-S1-Open-Source-Edition](https://github.com/Guilouz): Open-Source-OS für den verwandten FLSun S1
* Die FLSun-T1/T1-Pro-Community auf GitHub
* Autor: **BehaviorBean**. Entwickelt mit Unterstützung eines KI-Assistenten (Claude).

## Lizenz

[GPL-3.0](LICENSE), wie Klipper. Teile der Konfiguration stammen aus der FLSun-Werkskonfiguration und aus Beispielen von Klipper und Mainsail.
