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

## Ccm is currently disabled in the shipped profiles

The conjugation bug in the debayer is fixed
(`patches/libcamera-0.5-debayer-ccm-swap.patch`, see the README section on
it), but the matrices still do more harm than good with the simple IPA's
untuned grey-world AWB:

- front: neutral on a grey wall, but the face region gains ~9% green
  (191.5/211.3/194.3 with Ccm against 200.8/205.1/197.1 without, measured on
  the same subject);
- rear: a strong green cast even on a neutral wall (127.7/183.7/64.5 with
  Ccm against 170.0/173.6/170.4 with the identity matrix) - its recovered
  matrices need their convention re-validated.

## AWB colour gain tables (2026-11-18)

The simple IPA's `Awb` used to be plain grey-world over the whole frame, so a
subject filling the frame was neutralised (the "people change colour"
report).  `patches/libcamera-0.5-simple-awb-colourgains.patch` adds the
standard mechanism: when the tuning file carries `colourGains`, the
grey-world estimate is only used to pick a colour temperature and the applied
gains come from the table (`libipa::AwbGrey`, the same machinery rkisp1
uses).  Dominant-colour subjects keep their colour; calibrated illuminants
stay neutral.

The shipped anchors are measured with the tablet itself:

```text
white wall, indoor LED light:
  rear  ov13b10: grey-world gains R 1.77  B 1.51   estimateCCT 5470
  front ov8856 : grey-world gains R 1.64  B 1.36   estimateCCT 6040
```

Re-measure under daylight by pointing each camera at a neutral surface and
running:

```sh
LIBCAMERA_LOG_LEVELS=IPASoftAwb:DEBUG cam --camera=<n> \
    --stream role=viewfinder,width=640,height=480 --capture=30 2>&1 \
    | grep "gain R/B"
```

then update the `ct`/`gains` rows.  The 2856 K and 7500 K points are
conservative extrapolations.

The deeper issue is the AWB: `IPASoftAwb` is plain grey-world over the whole
frame (`sumG/sumR, 1, sumG/sumB`) with no tuning hook, so a face-dominated
frame gets neutralised - the "people change colour" report - and the CCM
amplifies whatever residual is left.  Restoring calibrated colours needs the
vendor AWB gains extracted from the Chromatix blob (`com.qti.tuned.*.bin`)
plus a colour-gain table in the Awb algorithm (libipa already ships the
machinery).  Until then the profiles run BlackLevel/Awb/Lut/Agc only:
neutral on grey, uncorrected chroma.

## Therefore they are not installed by default

`nabu-module.toml` deliberately has no `[install]` entry for them, because the
Debian trixie image ships libcamera 0.4.0.

For a tree whose userspace ships libcamera >= 0.5 (e.g. the 7.2.x port), install
them at:

    /usr/share/libcamera/ipa/simple/ov8856.yaml
    /usr/share/libcamera/ipa/simple/ov13b10.yaml

See also `../patches/README.md` for the (cosmetic) libcamera sensor-helper
patch, which has the same "build against the distro libcamera" constraint.
