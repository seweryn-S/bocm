<!--
SPDX-License-Identifier: GPL-3.0-only
Copyright (C) 2026 Seweryn Sitarski
Author: Seweryn Sitarski

This file is part of this project and is licensed
under the GNU General Public License version 3.
See the LICENSE file for details.
-->

# bocm
BlueOcean Control Manager — automatyczny provisioning bare‑metal z iPXE i własnym initramfs.

BOCM przygotowuje dysk, tworzy LVM zgodnie z YAML, pobiera obraz systemu (HTTP/HTTPS przez rclone), nakłada konfigurację hosta, instaluje bootloader i uruchamia system z lokalnego dysku. Projekt zawiera gotowe hooki dla `initramfs-tools` oraz skrypt do budowy artefaktów netboot.

**Najważniejsze możliwości**
- Boot z sieci (iPXE + initramfs z Dropbear SSH do diagnostyki).
- Pobieranie obrazu systemu z URL (`img_uri`) i konfiguracji hosta (`cfg_uri`).
- Automatyczne partycjonowanie i LVM wg `etc/bocm/partitions.yml` (w tym RAID1 dla LV).
- Wykonywanie skryptu `pre_boot` w chroot (np. specyficzna rekonfiguracja GRUB/dracut).
- Logi z instalacji dostępne po starcie systemu w `/var/log/bocm_install.log`.

W poniższej instrukcji słowo „serwer http” oznacza miejsce, z którego iPXE pobiera kernel/initrd oraz skąd initramfs pobiera obraz i konfigurację.

**Wymagania**
- Docker na maszynie budującej initramfs.
- Serwer iPXE/HTTP (np. nginx, Apache) dostępny dla hostów startujących z sieci.
- DHCP z wpisem do iPXE lub łańcuchowaniem do iPXE.

**Szybki Start**
1) Zbuduj artefakty netboot (kernel + initrd):
   - `./createNetBoot /ścieżka/do/katalogu/www/templates/bocm-v1.0.0`
   - Skrypt buduje obraz Dockera, generuje `vmlinuz` i `initrd.img-<kernel>-<git_ver>` oraz tworzy symlinki `vmlinuz` i `initrd.img` w podanym katalogu.

2) Umieść artefakty na serwerze HTTP, np. pod: `/templates/bocm-v1.0.0/`.

3) Przygotuj obraz systemu do wgrania (tgz lub tzst):
   - Przykład ścieżki: `/templates/ubuntu22.04/ubuntu22.04-latest.tzst`.

4) Przygotuj katalog konfiguracji hosta (overlay kopiowany na root):
   - Przykład: `/templates/CONFIGS/<hostname>/`.
   - Opcjonalnie umieść `etc/pre_boot` (przykład w `etc/pre_boot.OL8.example`).

5) Dostosuj pliki konfiguracyjne po stronie initramfs:
   - `etc/bocm/partitions.yml` — układ partycji i LVM (patrz sekcja niżej).
   - `etc/bocm/default` — m.in. ścieżka do `VOLUMES_FILE`, `PRE_BOOT_FILE`.
   - `etc/bocm/rclone.conf` — definicje zdalnych „remote” `IMG` i `CFG` (domyślnie HTTP). Adresy są automatycznie podmieniane na podstawie `img_uri`/`cfg_uri` (zmienne `${img_server}`, `${cfg_server}`).

6) Skonfiguruj iPXE. Minimalny szablon (dostosuj ścieżki i wersję):
```
#!ipxe
set TEMPLATE ubuntu22.04
set TEMP_VER latest
set BASEURL https://boipxe/templates
set BOCMDIR ${BASEURL}/bocm-v1.0.0
set INITRD initrd.img
set IMG_URI ${BASEURL}/${TEMPLATE}/${TEMPLATE}-${TEMP_VER}.tzst
set CFG_URI ${BASEURL}/CONFIGS/${hostname}
kernel ${BOCMDIR}/vmlinuz root=LABEL=lvroot initrd=${INITRD} net.ifnames=0 biosdevname=0 ip=dhcp rw -- img_uri=${IMG_URI} cfg_uri=${CFG_URI}
initrd ${BOCMDIR}/${INITRD}
boot
```
   - Możesz dodać `make_volumes` (zeruje i odtwarza układ dysku!) albo `disk_info` (diagnostyka).
   - Przykład kompletny znajdziesz w `boot.ipxe`.

**Parametry Kernela (cmdline)**
- `img_uri=<URL>` — pełny URL do archiwum obrazu systemu (`.tgz` lub `.tzst`).
- `cfg_uri=<URL>` — pełny URL do katalogu z konfiguracją hosta (kopiowany 1:1 na root).
- `make_volumes` — wymusza wyczyszczenie dysku i odtworzenie partycji/LVM z YAML.
- `disk_info` — uruchamia narzędzie informacji o dyskach w initramfs i czeka na interakcję.
- `break=<punkt>` — punkty diagnostyczne: `before_net_config`, `after_net_config`, `before_bocm_top`, `before_user_bottom`, `after_user_bottom`, `end`.

UWAGA: `make_volumes` jest operacją destrukcyjną — skasuje dane na dysku docelowym.

**Pliki Konfiguracyjne**
- `etc/bocm/partitions.yml`
  - `conf.diskdev` — dysk (np. `/dev/sda` lub stabilne `/dev/disk/by-path/...`).
  - `partition[]` — numer, typ (np. `ef00`, `8e00`), `fstype`, `mnt`, `size`.
  - `volume[]` — `part`, `name`, `dev` (np. `mapper/vgroot-lvroot`), `fstype` (`xfs`/`swap`/`vfat`), `size`, `mnt`, `mntopt`, `raid` (`raid1` lub `n`), `type` (`SYS` nadpisywane zawsze, `USR` tylko z `make_volumes`).
  - Partycje i punkty montowania przetwarzane są w kolejności z pliku (nie po numerach). Gdy `/boot` i `/boot/efi` istnieją, upewnij się, że `/boot` występuje wcześniej niż `/boot/efi`.
- `etc/bocm/default` — m.in.: `VOLUMES_FILE`, `PRE_BOOT_FILE` (domyślnie `/etc/pre_boot`), `MANUAL_DISK_MANAGE`, `INITRD_CONF_PATH`.
- `etc/bocm/rclone.conf` — zdalne „remotes” `IMG` i `CFG` (typ `http`). Adresy są podmieniane w locie na podstawie `img_uri` i `cfg_uri`.
- `etc/initramfs-tools/conf.d/bocm` — parsowanie `img_uri`/`cfg_uri` i flag sterujących.
- Przykład skryptu `pre_boot` dla OL8: `etc/pre_boot.OL8.example`.

**Przebieg Działania (w skrócie)**
- Faza TOP (`bocm_top` w initramfs):
  - Konfiguracja sieci, weryfikacja dostępności obrazu (`IMG:`). Opcjonalnie `disk_info`.
  - Detekcja dysku (`conf.diskdev` lub by‑path). Opcjonalne: `cleanDisk` + `makeStdPartition` gdy `make_volumes`.
  - `makeVolumes` według YAML, następnie `vgchange -ay`.
- Faza BOTTOM (`bocm_bottom`):
  - Montowanie wszystkich partycji/LV na `rootmnt` (`mountAll`).
  - Pobranie i rozpakowanie obrazu do `rootmnt` (tgz/tzst przez rclone).
  - Overlay konfiguracji z `CFG:` do `rootmnt/` (z wykluczeniami jak `boot.ipxe`, `initrd.conf`).
  - Instalacja bootloadera i przebudowa initramfs w chroot; opcjonalnie wykonanie `PRE_BOOT_FILE`.
  - Przeniesienie logów do `/var/log/bocm_install.log`, odmontowanie i remount RO.

Domyślnie kernel ma `root=LABEL=lvroot`. Upewnij się, że LV root ma etykietę zgodną z YAML (`name: lvroot`).

**SSH do initramfs (diagnostyka)**
- W initramfs działa Dropbear na porcie `2222` (klucze w `etc/dropbear-initramfs/authorized_keys`).
- Łączenie: `ssh -p 2222 -oHostKeyAlgorithms=ssh-rsa -oPubkeyAcceptedKeyTypes=+ssh-rsa root@<adres>`.
- Przydaje się z `break=after_net_config`.

**Logi i Diagnostyka**
- Logi runtime w initramfs: `/logfile.log` (po instalacji przenoszone do `/var/log/bocm_install.log`).
- Punkty `break` do zatrzymania przebiegu na wybranym etapie.
- Narzędzie `disk_info` pomocne przy doborze właściwego `conf.diskdev`.

**Budowanie i Rozwój**
- Skrypt budujący: `createNetBoot` (wymaga Docker). Artefakty kopiowane do wskazanego katalogu.
- Hooki i skrypty initramfs: `etc/initramfs-tools/hooks/bocm`, `etc/initramfs-tools/scripts/local-top/bocm-top.sh`, `etc/initramfs-tools/scripts/local-bottom/bocm-bottom.sh`.
- Funkcje instalatora: `etc/bocm/functions.sh` (m.in. `cleanDisk`, `makeStdPartition`, `makeVolumes`, `mountAll`, `umountAll`).
- Proste testy/skrypty pomocnicze: `tests/`.

**Bezpieczeństwo**
- Operacje z `make_volumes` są destrukcyjne — używaj świadomie na właściwym dysku (`conf.diskdev`).
- `rclone` w initramfs używa `--no-check-certificate` — w środowiskach produkcyjnych rozważ pełne TLS z poprawnym certyfikatem.

**Licencja**
Projekt jest dostępny na licencji GPLv3 (zob. plik `LICENSE`).
