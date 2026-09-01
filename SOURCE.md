# Source and provenance

The kernel overlay targets commit
`5181e1358ddd6ea8028e841d928942373e6aebc8` from the postmarketOS
Qualcomm SM8150 Linux tree:

```text
https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux.git
```

The initial standalone snapshot was extracted from the contiguous camera
development series ending at
`8c4de3a70e6c055534783a59ba5d71f46e853089`. The series consists of:

```text
4443551f28a8 media: qcom: camss: add support for SM8150
9ce352402f3f arm64: dts: qcom: sm8150: add CAMSS and CCI nodes
6f5503db122f dt-bindings: media: qcom: add SM8150 CAMSS binding
c924508c3d56 arm64: dts: qcom: enable nabu cameras
ad1e2bf09c0c media: qcom: enable nabu front camera capture
041b769b956d media: ov8856: preserve the active mbus format
1c1260a85ffd media: ov8856: expose firmware orientation properties
cd1a99f100b5 media: qcom: fix camera reopen after runtime suspend
a4485a73ea4f arm64: dts: qcom: enable nabu rear camera
ca7668b97f07 camera: add libcamera colour tuning profiles
b4ab15046e3b camera: enable high-resolution Snapshot captures
1969622e00b0 camera: fix high-resolution Snapshot capture
8c4de3a70e6c camera: add CN3927 lens and autofocus support
```

The original development tree also contained nabu Iris/Venus work. The two
overlapping DTS files were intentionally not copied. Their camera-only changes
were moved into `sm8150-xiaomi-nabu-camera.dtsi`, which is included by the new
derived board DTS. This keeps the camera overlay independent and composable
with `nabu-iris`.
