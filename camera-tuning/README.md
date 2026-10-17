# libcamera simple-IPA tuning for the nabu sensors

`ov8856.yaml` (front) and `ov13b10.yaml` (rear) carry the CCMs recovered from
Qualcomm's `com.qti.tuned.nabu_*.bin`, for libcamera's **simple IPA**.

## These files require libcamera >= 0.5

They use the `Ccm` and `Adjust` algorithms. libcamera **0.4.0**'s simple IPA
only implements `BlackLevel`, `Awb`, `Lut` and `Agc`, so loading these files
there fails *hard*:

```
ERROR IPAModuleAlgo module.h:79   IPASoft: Algorithm 'Ccm' not found
ERROR SoftwareIsp software_isp.cpp:133 IPA init failed
```

`IPA init failed` disables the software ISP completely, so the camera delivers
**no frames at all**.  That is worse than having no tuning file: without one,
libcamera falls back to its own `uncalibrated.yaml`, the ISP initialises and the
camera keeps working (uncalibrated colours).

## Therefore they are not installed by default

`nabu-module.toml` deliberately has no `[install]` entry for them, because the
Debian trixie image ships libcamera 0.4.0.

For a tree whose userspace ships libcamera >= 0.5 (e.g. the 7.2.x port), install
them at:

    /usr/share/libcamera/ipa/simple/ov8856.yaml
    /usr/share/libcamera/ipa/simple/ov13b10.yaml

See also `../patches/README.md` for the (cosmetic) libcamera sensor-helper
patch, which has the same "build against the distro libcamera" constraint.
