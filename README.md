# nabu-camera

Xiaomi Pad 5（`nabu`、SM8150）的实验性 Linux 前后摄像头、CN3927 对焦马达和
用户态自动对焦支持。

本仓库与 `nabu-iris` 一样保存直接源码覆盖层，不包含完整 Linux 内核树、预编译
UKI 或完整模块树。内核文件保留原始相对路径，可以覆盖到指定基线后审查和构建。

> 这是实验性代码。替换 DTB、内核或模块可能导致设备无法启动，请准备可用的恢复
> 方式。

## 当前功能

- Qualcomm SM8150 CAMSS、CCI、CSIPHY、CSID 和 VFE 支持
- OV13B10 后摄，最高 4208×3120
- OV8856 前摄
- CN3927 VCM 对焦马达，10 位 `V4L2_CID_FOCUS_ABSOLUTE`
- libcamera simple IPA 色彩调校文件
- GTK4/GStreamer 自动对焦原型，支持连续对焦和点击/触摸区域对焦

## 目录

```text
kernel-overlay/   按 Linux 源码路径组织的相机内核源码
config/           可合并到现有 .config 的相机 Kconfig fragment
camera-app/       nabu-autofocus 原型
camera-tuning/    libcamera simple IPA 调校文件
scripts/          安装辅助脚本
LICENSES/         源码 SPDX 标识对应的许可证文本
```

## 设备树

仓库不覆盖 `sm8150.dtsi`，也不修改原始 `sm8150-xiaomi-nabu.dts`，只提供
`arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu-camera.dtsi` 片段。组合 DTB 不再手写，
由 `nabu-main compose` 按产品顺序自动生成（Iris、Camera、Accelerometer、Power）。

## 统一构建（nabu-main）

本仓库不再自带覆盖、配置合并或模块构建脚本。跨仓统一构建由同级 `nabu-main`
读取根目录的 `nabu-module.toml` 完成：

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

在内核基线 `5181e1358ddd6ea8028e841d928942373e6aebc8` 上，于 `nabu-main` 运行：

```sh
make apply      # reset linux，应用 overlay/patch
make compose    # 生成组合 DTS
make config     # 合并 fragment 并固定统一 release
make build      # 构建 Image、模块与 DTB
make collect    # 收集产物到 artifacts/<product>/
```

构建产物必须与正在运行的内核版本、配置和符号完全匹配。

## 安装模块和调校文件

确认 `BUILD_DIR` 指向统一构建输出后执行：

```sh
sudo BUILD_DIR=../nabu-main/out ./scripts/install-camera-modules.sh
```

脚本安装 CCI、CAMSS、CN3927 模块和两个 libcamera 调校文件，并保留可回滚备份。
安装后需要重启。回滚命令为：

```sh
sudo ./scripts/install-camera-modules.sh --rollback
```

## 自动对焦应用

```sh
make -C camera-app
camera-app/nabu-autofocus
```

点击或触摸预览可以针对该区域对焦；`--once` 执行一次无窗口自动对焦。完整参数见
[`camera-app/README.md`](camera-app/README.md)。

## 来源和许可证

内核基线、原始提交和拆分说明见 [`SOURCE.md`](SOURCE.md)。各文件按自身 SPDX
标识授权；Linux 许可证说明见 `COPYING` 与 `LICENSES/`。
