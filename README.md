# nabu-camera

**English** | [中文](README.zh.md)

Experimental Linux support for the Xiaomi Pad 5 (`nabu`, SM8150) front and rear cameras, the CN3927
focus actuator, and userspace autofocus.

Like `nabu-iris`, this repository stores a direct source overlay; it does not include a complete
Linux kernel tree, a prebuilt UKI, or a full module tree. Kernel files keep their original relative
paths, so they can be overlaid onto a chosen baseline for review and building.

> This is experimental code. Replacing the DTB, kernel, or modules may prevent the device from
> booting; always prepare a working recovery method.

## Current features

- Qualcomm SM8150 CAMSS, CCI, CSIPHY, CSID, and VFE support
- OV13B10 rear camera, up to 4208×3120
- OV8856 front camera
- CN3927 VCM focus actuator, 10-bit `V4L2_CID_FOCUS_ABSOLUTE`
- libcamera simple IPA color tuning files
- GTK4/GStreamer autofocus prototype with continuous focus and click/touch region focus
- GNOME Snapshot 50.0 high-resolution still capture and orientation fix patch

## Layout

```text
kernel-overlay/   camera kernel source organized by Linux source paths
config/           camera Kconfig fragment that can be merged into an existing .config
camera-app/       the nabu-autofocus prototype and the GNOME Snapshot patch
camera-tuning/    libcamera simple IPA tuning files
scripts/          install helper scripts
LICENSES/         license texts for the source SPDX tags
```

## Device tree

The repository does not override `sm8150.dtsi`, nor does it modify the original
`sm8150-xiaomi-nabu.dts`; it only provides the
`arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu-camera.dtsi` fragment. The combined DTB is no longer
written by hand; it is generated automatically by `nabu-main compose` in product order (Iris,
Camera, Accelerometer, Power).

## Unified build (nabu-main)

This repository no longer ships its own overlay, config merging, or module build scripts. The
cross-repository unified build is handled by the sibling `nabu-main`, which reads the root
`nabu-module.toml`:

```toml
[provides]
overlay = "kernel-overlay"
dtsi    = ["arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu-camera.dtsi"]
config  = ["config/nabu-camera.config"]

[build]
kernel_targets = [
    "drivers/i2c/busses/i2c-qcom-cci.ko",
    "drivers/media/platform/qcom/camss/qcom-camss.ko",
    "drivers/clk/qcom/camcc-sm8150.ko",
    "drivers/media/i2c/ov8856.ko",
    "drivers/media/i2c/ov13b10.ko",
    "drivers/media/i2c/cn3927.ko",
]
```

On kernel baseline `5181e1358ddd6ea8028e841d928942373e6aebc8`, run in `nabu-main`:

```sh
make apply      # reset linux, apply overlay/patch
make compose    # generate the combined DTS
make config     # merge fragments and pin the unified release
make build      # build Image, modules, and DTB
make collect    # collect artifacts into artifacts/<product>/
```

Build artifacts must exactly match the running kernel's version, configuration, and symbols.

## Installing modules and tuning files

After confirming that `BUILD_DIR` points to the unified build output:

```sh
sudo BUILD_DIR=../nabu-main/out ./scripts/install-camera-modules.sh
```

The script installs the CCI, CAMSS, and CN3927 modules and the two libcamera tuning files, keeping
rollback backups. A reboot is required after installation. To roll back:

```sh
sudo ./scripts/install-camera-modules.sh --rollback
```

## Autofocus application

```sh
make -C camera-app
camera-app/nabu-autofocus
```

Clicking or touching the preview focuses on that region; `--once` performs a single windowless
autofocus run. See [`camera-app/README.md`](camera-app/README.md) for the full options.

## Colour calibration in the desktop apps (libcamera 0.5)

Debian trixie ships libcamera 0.4, whose simple IPA has no `Ccm` algorithm, so
GNOME Snapshot and `nabu-autofocus` (both take frames through GStreamer's
`libcamerasrc`) cannot use the tuning profiles and show uncalibrated colours.
Two scripts build and install 0.5.2 next to the distro copy:

```sh
./scripts/build-libcamera-0.5.sh            # out/libcamera-0.5.2-arm64.tar.gz
sudo ./scripts/install-libcamera-0.5.sh out/libcamera-0.5.2-arm64.tar.gz
```

Everything lands under `/usr/local` and is selected through `GST_PLUGIN_PATH`
(written to `/etc/environment.d/50-nabu-gst.conf` and `/etc/environment`);
`/usr/local/lib/aarch64-linux-gnu` is added to `ld.so.conf.d` so
`libcamera.so.0.5` resolves without an environment variable.  The distro
libcamera 0.4 stays in place, so rollback is one command:

```sh
sudo ./scripts/install-libcamera-0.5.sh --rollback
```

Log out and back in (or reboot) once, because the graphical session inherits
`GST_PLUGIN_PATH` from the systemd user manager, then check:

```sh
systemctl --user show-environment | grep GST_PLUGIN_PATH
GST_PLUGIN_PATH=/usr/local/lib/aarch64-linux-gnu/gstreamer-1.0 \
    gst-inspect-1.0 libcamerasrc | grep -E 'Filename|Version'   # 0.5.2
```

`install-camera-modules.sh` detects that tree and installs the tuning profiles
into `/usr/local/share/libcamera/ipa/simple`, the prefix the IPA actually
reads; with only the distro 0.4 present it still skips them (a `Ccm` profile
there makes the IPA fail and the camera deliver no frames).

## PipeWire camera applications (GNOME Snapshot)

GNOME Snapshot does not use `libcamerasrc`; it takes frames from the PipeWire
camera node, which is created by PipeWire's SPA `libcamera` plugin.  The distro
plugin is linked against libcamera 0.4, so even with the 0.5 stack installed
the application keeps the uncalibrated colours and gets no autofocus.  Two
scripts rebuild just that plugin against the 0.5 stack:

```sh
./scripts/build-pipewire-libcamera-0.5.sh       # out/libspa-libcamera-0.5-arm64.so
sudo ./scripts/install-pipewire-libcamera-0.5.sh out/libspa-libcamera-0.5-arm64.so
sudo ./scripts/install-pipewire-libcamera-0.5.sh --rollback
```

The installer keeps the distro plugin as `libspa-libcamera.so.nabu-orig` and
restarts the user's `pipewire`/`wireplumber`.  Verified on the tablet: the
journal shows `libcamera v0.5.2` from wireplumber, the node instantiates
`BlackLevel/Awb/Ccm/Lut/Agc` from the tuned profile, and `focus_absolute`
moves through the coarse/fine scan while the node streams.

The PipeWire node still enumerates only up to 4096x2160 (the sensor's native
4:3 4208x3120 is not in the list), so the still-capture resolution inside the
application is capped by that.

## Colour pipeline: the CCM swap bug (fixed)

`DebayerCpu` flips the Bayer order to reuse the RGB888 debayer functions when
the output is BGR888/ABGR8888, and swaps the simple gain tables to compensate.
The same swap was also applied to the CCM columns - plus an extra `.r/.b`
field swap - which conjugates the colour matrix with the R/B permutation:
every CCM then skews colours instead of correcting them.  The front camera
showed a strong yellow cast from exactly this:

```text
neutral wall, no Ccm:            RGB 168.4/167.8/167.8   (sensor + AWB are fine)
neutral wall, Ccm (buggy):       RGB 196.6/167.5/134.4   (R +17 %, B -20 %)
neutral wall, Ccm (identity):    RGB 162.4/161.9/162.5   (pipeline handles diagonals)
neutral wall, Ccm (fixed):       RGB 168.1/167.9/169.5   (cast gone)
```

`patches/libcamera-0.5-debayer-ccm-swap.patch` keeps the column swap (the
flipped function really does deliver physically R/B-swapped samples) and drops
the field swap.  The build script applies it with the other patches.

This is an upstream software-ISP bug, not nabu-specific: every pipeline that
uses the Ccm algorithm with a BGR888-family output is affected.

The rear OV13B10 needs its own look under the corrected pipeline: on one
scene its identity matrix reads 148.0/173.7/132.3 while the front's identity
is neutral, and the recovered matrices turn green on that scene.  The old
bug partially masked this; next step is the SGRBG statistics channel
mapping and the AWB convergence for the rear sensor.

## Autofocus in libcamera

Upstream's simple pipeline (0.5 to 0.8 and master) has no lens support, and the
software IPA has no autofocus, so `patches/libcamera-0.5-simple-autofocus.patch`
adds both on top of v0.5.2 (the build script applies it automatically):

- the simple pipeline attaches `CameraSensor::focusLens()` to the software ISP
  and exposes the standard `AfMode` control (Manual/Auto/Continuous, default
  Continuous);
- `DebayerCpu` computes a contrast metric right after debayering: the mean
  absolute green gradient over the central half of the frame, normalised by the
  mean green level so AGC changes do not move it, median of three frames;
- `SoftwareIsp` runs a coarse scan over the lens range, a fine scan around the
  best position (keeping the coarse best), then tracks the scene and rescans
  when the score drops.  The lock survives stream reconfiguration
  (preview -> still) so a still is not captured mid-scan.

Verified on the tablet with `LIBCAMERA_LOG_LEVELS=SoftwareIsp:DEBUG`:

```text
Autofocus position 0 score 40 ... 1016 score 28      (coarse)
Autofocus position 254 score 55 ... 506 score 30     (fine)
Autofocus locked at 253 score 65
```

`cam --list-controls` lists `AfMode`, and after the process exits
`v4l2-ctl --get-ctrl focus_absolute` reads back the locked position (253).

The closed Qualcomm AF tuning (`com.qti.tuned.*.bin`) and the actuator driver
(`com.qti.actuator.nabu_cn3927.so`) live in `/vendor/lib64/camera` inside the
`super` partition and are not accessible from the Linux side, so the scan
parameters are measured rather than copied.  Setting `AfMode=Manual` disables
the built-in loop for applications that drive the lens themselves
(`nabu-autofocus` does).

## Still photo capture (GNOME Snapshot)

`camera-app/gnome-snapshot-50.0-nabu.patch` applies to GNOME Snapshot tag 50.0.
It keeps the nabu viewfinder orientation correction, bypasses the redundant
decoder for raw libcamera streams, and adds separate high-resolution 4:3 caps
for still capture while retaining a 1080p preview.

`scripts/install-snapshot-camera.sh` clones Snapshot 50.0, applies the patch,
runs its cargo test suite, and installs it under `~/.local` (override with
`SNAPSHOT_INSTALL_PREFIX`). Run it as the desktop user, without sudo:

```sh
./scripts/install-snapshot-camera.sh
```

The rear OV13B10 is the still-capture sensor; use `nabu-autofocus` to drive the
CN3927 lens if the image looks soft. libcamera hands the sensor to one consumer
at a time, so close other camera preview applications first.

## Provenance and license

See [`SOURCE.md`](SOURCE.md) for the kernel baseline, original commits, and split notes. Each file
is licensed under its own SPDX tag; see `COPYING` and `LICENSES/` for the Linux license notices.
