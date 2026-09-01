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
- GNOME Snapshot 50.0 高分辨率拍照与方向修正补丁

## 目录

```text
kernel-overlay/   按 Linux 源码路径组织的相机内核源码
camera-app/       nabu-autofocus 及 GNOME Snapshot 补丁
camera-tuning/    libcamera simple IPA 调校文件
scripts/          覆盖、构建和安装辅助脚本
LICENSES/         源码 SPDX 标识对应的许可证文本
```

## 设备树追加模式

仓库不覆盖 `sm8150.dtsi`，也不修改原始
`sm8150-xiaomi-nabu.dts`。相机设备树由两个新文件组成：

```text
sm8150-xiaomi-nabu-camera.dts
  ├─ include sm8150-xiaomi-nabu.dts
  └─ include sm8150-xiaomi-nabu-camera.dtsi
```

因此构建和启动时必须使用派生 DTB：

```text
qcom/sm8150-xiaomi-nabu-camera.dtb
```

这种布局允许原 nabu DTS 继续由上游维护，而相机节点保持独立。如果同时安装
`nabu-iris`，两个追加文件由显式的组合 DTS 汇总。

## 放入内核树

准备位于精确基线的 Linux 源码树：

```sh
git clone https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux.git linux
git -C linux checkout 5181e1358ddd6ea8028e841d928942373e6aebc8
./scripts/apply-overlay.sh ./linux
```

安装脚本允许目标树存在不重叠的修改，所以可以先应用 `nabu-iris`。如果某个相机
覆盖目标已经被其他工作修改，脚本会停止，不会静默覆盖。

## 构建

输出目录需要已有适用于 nabu 的 `.config`。应用覆盖层后运行：

```sh
./scripts/build.sh ./linux ./linux/out
```

脚本构建模块以及：

```text
linux/out/arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu-camera.dtb
```

如果目标树同时安装了 `nabu-iris`，脚本会自动改为构建：

```text
linux/out/arch/arm64/boot/dts/qcom/sm8150-xiaomi-nabu-iris-camera.dtb
```

构建产物必须与正在运行的内核版本、配置和符号完全匹配。

## 安装模块和调校文件

确认 `BUILD_DIR` 指向内核输出目录后执行：

```sh
sudo BUILD_DIR=$PWD/linux/out ./scripts/install-camera-modules.sh
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
