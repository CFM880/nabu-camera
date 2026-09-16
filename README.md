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

## Layout

```text
kernel-overlay/   camera kernel source organized by Linux source paths
config/           camera Kconfig fragment that can be merged into an existing .config
camera-app/       the nabu-autofocus prototype
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

## Provenance and license

See [`SOURCE.md`](SOURCE.md) for the kernel baseline, original commits, and split notes. Each file
is licensed under its own SPDX tag; see `COPYING` and `LICENSES/` for the Linux license notices.
