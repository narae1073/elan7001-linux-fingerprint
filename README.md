# ELAN7001 (04f3:3128) fingerprint reader on Linux

ASUS VivoBook X421EA / X413EA, CachyOS/Arch, KDE Plasma 6.8.

## Hardware

| Item | Value |
| --- | --- |
| Sensor | ELAN7001 (ACPI `\_SB.PC00.SPI0.FPRT`) |
| Bus | Internal SPI (`pxa2xx-spi.3`), `/dev/spidev1.0` |
| Touchpad HID | `04f3:3128` |
| Sensor class | eFSA80SC (80x80) |
| Driver rotation quirk | `ELANSPI_90LEFT_ROTATE` |
| Physical location | Top-right corner of the touchpad |

## Root cause

1. **SPI buffer size**: the default `spidev.bufsiz=4096` splits the 16,640-byte
   fingerprint image into four transfers. The sensor then fails with
   `timed out waiting for image`.
2. **Matcher**: the default NBIS/bozorth3 matcher cannot distinguish fingers on
   the narrow swipe images produced by this sensor (`verify-no-match`, score
   `0/24`). SIGFM is required.
3. **Scan mode**: Windows behaves like a touch sensor, but the Linux `elanspi`
   driver uses a swipe state machine. Swipe slowly across the full sensor in
   either direction (bottom-to-top works too); holding the finger still is not
   enough.

## Changes

- `/etc/modprobe.d/spidev-fingerprint.conf`
  ```
  options spidev bufsiz=32768
  ```
- `/opt/elan3128/`: `rsd/libfprint` (`sigfm-0078`, 1.94.100) plus the
  `elanspi` patch in this repository.
- `/etc/systemd/system/fprintd.service.d/90-elan3128.conf`
  ```
  [Service]
  Environment=LD_LIBRARY_PATH=/opt/elan3128/lib
  ```
- `/etc/pam.d/plasmalogin`: local override that tries fingerprint three times,
  5 seconds each, before falling back to the password stack.

The system `/usr/lib/libfprint-2.so.2.0.0` is not modified. Only `fprintd`
loads the patched library.

## Usage

```bash
# Enroll (7 slow full-length swipes; bottom-to-top works too)
fprintd-enroll -f right-index-finger

# Verify
fprintd-verify -f right-index-finger "$USER"

# List enrolled fingers
fprintd-list "$USER"
```

- **sudo**: `/etc/pam.d/sudo` already contains a `pam_fprintd.so` line
  (`chwd-fprintd`), so sudo accepts a fingerprint.
- **KDE lock screen**: kscreenlocker uses its `kde-fingerprint` PAM stack. A
  slow swipe unlocks the screen; no prompt is necessarily shown before the
  swipe.
- **KDE Settings -> Users -> Fingerprint**: enrollment works again after the
  fixes above.
- **Plasma Login Manager**: `/etc/pam.d/plasmalogin` tries fingerprint three
  times for 5 seconds each (15 seconds total), then falls back to password.
  Plasma Login Manager 6.8 starts PAM only after the login form is submitted,
  so press Enter on the empty password field once and then swipe. This is a
  greeter limitation, not a configuration error. kscreenlocker does not have
  this limitation because it starts `kde-fingerprint` in parallel.

## Test results

- SIGFM enrollment: 7/7 stages.
- Verification: `verify-match` with scores 47622 and 3369 against threshold 100.
- sudo: fingerprint authentication succeeded.
- Lock screen: swipe unlock succeeded.
- Plasma Login Manager: PAM test succeeded; press Enter, then swipe.

## Rebuild

Packages (Arch/CachyOS):

```bash
sudo pacman -S --needed meson ninja doctest opencv \
  glib2 libgusb libgudev pixman openssl nss polkit systemd
```

```bash
git clone --depth 1 --branch sigfm-0078 https://github.com/rsd/libfprint.git ~/src/libfprint-rsd
cd ~/src/libfprint-rsd
git apply /path/to/this/repo/elanspi-3128-sigfm.patch

meson setup build \
  --prefix=/opt/elan3128 \
  -Ddrivers=elanspi \
  -Dudev_rules=disabled \
  -Ddoc=false \
  -Dintrospection=false \
  -Dinstalled-tests=false
ninja -C build
sudo ninja -C build install
sudo systemctl restart fprintd
```

Alternatively, run `./build.sh`.

### Other distributions

The build itself is distribution-independent. Install the development packages
for meson, ninja, GLib, GUsb, libgudev, pixman, OpenSSL, NSS, polkit, systemd,
OpenCV, and doctest.

Ubuntu / Debian:

```bash
sudo apt install git meson ninja-build build-essential pkg-config \
  libglib2.0-dev libgusb-dev libgudev-1.0-dev libpixman-1-dev \
  libssl-dev libnss3-dev libpolkit-gobject-1-dev libsystemd-dev \
  libopencv-dev libdoctest-dev fprintd libpam-fprintd
```

Fedora:

```bash
sudo dnf install git meson ninja-build gcc gcc-c++ pkgconf-pkg-config \
  glib2-devel libgusb-devel libgudev-devel pixman-devel openssl-devel \
  nss-devel polkit-devel systemd-devel opencv-devel doctest-devel fprintd
```

PAM service names differ by distribution and desktop:

| Target | PAM file |
| --- | --- |
| sudo | `/etc/pam.d/sudo` |
| KDE Plasma Login Manager | `/etc/pam.d/plasmalogin` |
| KDE lock screen | `kde-fingerprint` (provided by kscreenlocker) |
| SDDM | `/etc/pam.d/sddm` |
| GDM / GNOME | `/etc/pam.d/gdm-password` or `gdm-fingerprint` |
| polkit | `/etc/pam.d/polkit-1` |

On Ubuntu/Debian, `pam-auth-update` can enable fingerprint authentication. On
Fedora, `authselect` can enable the `with-fingerprint` feature.

The `spidev.bufsiz=32768` module option is distribution-independent. If the
distribution's libfprint package does not provide the ELAN7001 spidev binding
rule, add it to `/etc/udev/rules.d/`:

```
ACTION=="add|change", SUBSYSTEM=="spi", ENV{MODALIAS}=="acpi:ELAN7001:", RUN{builtin}+="kmod load spi:spidev", RUN+="/bin/sh -c 'echo spidev > %S%p/driver_override && echo %k > %S%p/subsystem/drivers/spidev/bind'"
```

The custom library is built against libfprint 1.94.100. If the distribution's
`fprintd` uses a different libfprint ABI, rebuild from a matching source
version instead of using this exact tree.

## Rollback

```bash
sudo rm -f /etc/pam.d/plasmalogin       # disable fingerprint at the login screen
sudo rm -f /etc/systemd/system/fprintd.service.d/90-elan3128.conf
sudo systemctl daemon-reload
sudo systemctl restart fprintd
sudo rm -rf /opt/elan3128
```

Keep `spidev.bufsiz=32768`; the stock libfprint also needs it for capture.
SIGFM templates are not compatible with stock NBIS. Delete and re-enroll after
switching back:

```bash
fprintd-delete "$USER" -f right-index-finger
```

## Notes

- If a `fprintd` or `libfprint` update changes the ABI, rebuild `/opt/elan3128`.
- After a kernel or `spidev` update, verify that
  `cat /sys/module/spidev/parameters/bufsiz` returns `32768`.
- A short or fast swipe can produce `enroll-swipe-too-short`; swipe slowly
  across the full sensor. Both swipe directions work; bottom-to-top is fine and
  often more comfortable.
