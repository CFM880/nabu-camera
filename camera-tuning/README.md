# libcamera simple-IPA tuning for the nabu sensors

`ov8856.yaml` (front) and `ov13b10.yaml` (rear) carry the CCMs recovered from
Qualcomm's `com.qti.tuned.nabu_*.bin`, for libcamera's **simple IPA**.

## These files require libcamera >= 0.5

They use the `Ccm` algorithm (libcamera 0.5.0 has `Ccm` but not `Adjust`, which
landed later, so the profiles do not list `Adjust`).  libcamera **0.4.0**'s
simple IPA only implements `BlackLevel`, `Awb`, `Lut` and `Agc`, so loading
these files there fails *hard*:

```
ERROR IPAModuleAlgo module.h:79   IPASoft: Algorithm 'Ccm' not found
ERROR SoftwareIsp software_isp.cpp:133 IPA init failed
```

`IPA init failed` disables the software ISP completely, so the camera delivers
**no frames at all**.  That is worse than having no tuning file: without one,
libcamera falls back to its own `uncalibrated.yaml`, the ISP initialises and the
camera keeps working (uncalibrated colours).

## The algorithm list matters

```
algorithms:
  - BlackLevel:
      blackLevel: 1024    # 16-bit value; the IPA uses blackLevel >> 8
  - Awb:
  - Ccm:
      ccms: [ { ct: ..., ccm: [...] }, ... ]
  - Lut:                   # must come AFTER Ccm
```

- **`Lut` is mandatory.**  `DebayerParams` is a plain aggregate: if no `Lut`
  algorithm runs, `gammaLut` stays zero and the CCM store path
  (`GAMMA(blue.b + green.b + red.b)`) writes black for every pixel.  The
  symptom is a capture that is `RGB 0, alpha 255` (25 % non-zero bytes) even
  though the ISP input is valid.
- `Lut` must be listed **after** `Ccm`: `Ccm::prepare()` sets
  `activeState.ccm.changed`, and `Lut::prepare()` only fills the CCM and gamma
  tables when that flag (or a black-level change) is seen.  With the wrong
  order the first frame is black and the CCM columns stay zero.
- `blackLevel` is a 16-bit value (`BlackLevel::init()` shifts it right by 8).
  The 10-bit sensors here have a pedestal of ~16 (10-bit) = 4 (8-bit), so the
  value is `1024` (= 16 << 6).  `4096` crushes shadows, `64` shifts to 0, and
  the absent/default `255` clamps the whole image to black.

With `Lut` after `Ccm` a `cam --capture=5` run yields five consecutive frames:
frame 0 is the CCM warm-up (black), frames 1-4 are fully populated.  libcamera
0.5.0 also multiplies the CCM and AWB gains in the wrong order (a colour cast);
v0.5.2 has the fix (`libcamera: software_isp: Fix CCM multiplication`).

## Therefore they are not installed by default

`nabu-module.toml` deliberately has no `[install]` entry for them, because the
Debian trixie image ships libcamera 0.4.0.

For a tree whose userspace ships libcamera >= 0.5 (e.g. the 7.2.x port), install
them at:

    /usr/share/libcamera/ipa/simple/ov8856.yaml
    /usr/share/libcamera/ipa/simple/ov13b10.yaml

See also `../patches/README.md` for the (cosmetic) libcamera sensor-helper
patch, which has the same "build against the distro libcamera" constraint.
