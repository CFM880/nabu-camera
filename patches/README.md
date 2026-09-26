# libcamera patches

## libcamera-0.7.0-ov8856-ov13b10-sensor-helper.patch

Adds `CameraSensorHelper` classes for the nabu front OV8856 and rear OV13B10 so
libcamera's simple IPA no longer logs

```text
IPASoft: Failed to create camera sensor helper for ov8856/ov13b10
```

and reports analogue gain in real units. Both sensors expose
`V4L2_CID_ANALOGUE_GAIN` in 1/128 steps with `0x80` (128) as 1x, so the helper
uses the same model as the other OmniVision helpers:
`AnalogueGainLinear{ 1, 0, 0, 128 }`.

### This is (almost) cosmetic

Without the helper the simple IPA takes the `else` branch in
`IPASoftSimple::configure()` and works with the raw V4L2 gain code, using the
control's min/default/max as `againMin`/`again10`/`againMax`. For these two
sensors that is 128/128/1984, i.e. a linear scale whose 1x reference is exactly
the calibrated one. Auto-exposure therefore behaves the same; only the log units
(`gain 128-1984` vs `gain 1-15.5`) and `againMinStep` differ. Do not replace the
system libcamera just for this unless you actually want the cleaner logs.

### Building and installing

The helper must be compiled into libcamera's simple IPA module
(`ipa_soft_simple.so`, which statically links `libipa`).

It must be built from the **distribution's** libcamera source. A locally built
IPA mixed with the distro core trips a libcamera assertion when the camera is
stopped:

```text
FATAL default pipeline_handler.cpp:398 assertion "data->queuedRequests_.empty()" failed in stop()
```

That aborts the process, so build the full distro source (core + IPA) from the
same tree and install both together:

```sh
# apt-get source libcamera && dpkg-source -x libcamera_*.dsc
cd libcamera-0.7.0
git apply /path/to/libcamera-0.7.0-ov8856-ov13b10-sensor-helper.patch
# build both core and ipa_soft_simple from this tree, then install them together
```

Verified on nabu (7.2.7, OV13B10/OV8856): the warning disappears and the IPA
logs `Exposure 4-792, gain 1-15.5`.
