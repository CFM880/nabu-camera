# nabu-camera

[English](README.md) | **中文**

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
config/           可合并到现有 .config 的相机 Kconfig fragment
camera-app/       nabu-autofocus 原型及 GNOME Snapshot 补丁
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

## 桌面应用的颜色校准（libcamera 0.5）

Debian trixie 自带 libcamera 0.4，它的 simple IPA 没有 `Ccm` 算法，所以
GNOME Snapshot 和 `nabu-autofocus`（都通过 GStreamer 的 `libcamerasrc` 取帧）
无法使用调校文件，颜色未校准。两个脚本会把 0.5.2 安装到发行版版本旁边：

```sh
./scripts/build-libcamera-0.5.sh            # 生成 out/libcamera-0.5.2-arm64.tar.gz
sudo ./scripts/install-libcamera-0.5.sh out/libcamera-0.5.2-arm64.tar.gz
```

所有文件都在 `/usr/local` 下，通过 `GST_PLUGIN_PATH` 选择（写入
`/etc/environment.d/50-nabu-gst.conf` 和 `/etc/environment`）；
`/usr/local/lib/aarch64-linux-gnu` 会加入 `ld.so.conf.d`，因此
`libcamera.so.0.5` 不需要环境变量即可解析。发行版的 libcamera 0.4 保持原样，
回退只需一条命令：

```sh
sudo ./scripts/install-libcamera-0.5.sh --rollback
```

需要注销再登录（或重启）一次，图形会话才会从 systemd user manager 继承
`GST_PLUGIN_PATH`，然后确认：

```sh
systemctl --user show-environment | grep GST_PLUGIN_PATH
GST_PLUGIN_PATH=/usr/local/lib/aarch64-linux-gnu/gstreamer-1.0 \
    gst-inspect-1.0 libcamerasrc | grep -E 'Filename|Version'   # 0.5.2
```

`install-camera-modules.sh` 会识别这棵 0.5 树，把调校文件安装到
`/usr/local/share/libcamera/ipa/simple`（IPA 实际读取的前缀）；只有发行版
0.4 时仍会跳过调校文件（带 `Ccm` 的配置会让 IPA 初始化失败，相机完全不出帧）。

## PipeWire 相机应用（GNOME Snapshot）

GNOME Snapshot 不使用 `libcamerasrc`，而是从 PipeWire 的相机节点取帧，该节点
由 PipeWire 的 SPA `libcamera` 插件创建。发行版插件链接的是 libcamera 0.4，
所以即使装了 0.5 栈，应用仍是未校准颜色、无自动对焦。两个脚本只重编这个插件：

```sh
./scripts/build-pipewire-libcamera-0.5.sh       # 生成 out/libspa-libcamera-0.5-arm64.so
sudo ./scripts/install-pipewire-libcamera-0.5.sh out/libspa-libcamera-0.5-arm64.so
sudo ./scripts/install-pipewire-libcamera-0.5.sh --rollback
```

安装器会把发行版插件备份为 `libspa-libcamera.so.nabu-orig`，并重启用户的
`pipewire`/`wireplumber`。平板实测：journal 显示 wireplumber 使用
`libcamera v0.5.2`，节点按调校文件实例化 `BlackLevel/Awb/Ccm/Lut/Agc`，
节点出流时 `focus_absolute` 按粗扫/精扫轨迹移动。

PipeWire 节点仍只枚举到 4096x2160（不含传感器原生 4:3 的 4208x3120），所以
应用内静态拍照的分辨率上限受此约束。

## libcamera 内的自动对焦

上游的 simple pipeline（0.5 到 0.8 以及 master）没有镜头支持，软件 IPA 也没有
自动对焦，因此 `patches/libcamera-0.5-simple-autofocus.patch` 在 v0.5.2 上补上
这两部分（构建脚本会自动应用）：

- simple pipeline 把 `CameraSensor::focusLens()` 接到软件 ISP，并暴露标准的
  `AfMode` 控件（Manual/Auto/Continuous，默认 Continuous）；
- `DebayerCpu` 在去马赛克后计算对比度指标：画面中心一半区域的绿色通道平均
  绝对梯度，按平均亮度归一化（避免 AGC 影响），并取三帧中位数；
- `SoftwareIsp` 先在整个镜头范围粗扫，再在最佳位置附近精扫（保留粗扫最优），
  之后持续跟踪，分数下降时重新扫描。锁定结果在换流（预览→拍照）后保留，
  静态照片不会拍在扫描过程中。

在平板上用 `LIBCAMERA_LOG_LEVELS=SoftwareIsp:DEBUG` 验证：

```text
Autofocus position 0 score 40 ... 1016 score 28      (粗扫)
Autofocus position 254 score 55 ... 506 score 30     (精扫)
Autofocus locked at 253 score 65
```

`cam --list-controls` 能看到 `AfMode`；进程退出后
`v4l2-ctl --get-ctrl focus_absolute` 读回锁定位置（253）。

高通的 AF 调校（`com.qti.tuned.*.bin`）和马达驱动
（`com.qti.actuator.nabu_cn3927.so`）位于 `super` 分区的
`/vendor/lib64/camera`，Linux 侧无法访问，所以扫描参数是实测得到的，不是照搬。
需要自己控制镜头时把 `AfMode` 设为 `Manual`（`nabu-autofocus` 就属于这种情况）。

## 拍照应用（GNOME Snapshot）

`camera-app/gnome-snapshot-50.0-nabu.patch` 适用于 GNOME Snapshot 标签 50.0：
保留 nabu 取景器方向修正、跳过对原始 libcamera 流的多余解码，并在保留 1080p
预览的同时为静拍增加独立的 4:3 高分辨率 caps。

`scripts/install-snapshot-camera.sh` 会克隆 Snapshot 50.0、应用补丁、跑一遍
cargo 测试，然后安装到 `~/.local`（可用 `SNAPSHOT_INSTALL_PREFIX` 覆盖）。请以
桌面用户运行，不要 sudo：

```sh
./scripts/install-snapshot-camera.sh
```

后摄 OV13B10 用于静拍；若画面偏软，用 `nabu-autofocus` 驱动 CN3927 对焦。
libcamera 同一时刻只允许一个消费者，先关闭其它相机预览程序。

## 来源和许可证

内核基线、原始提交和拆分说明见 [`SOURCE.md`](SOURCE.md)。各文件按自身 SPDX
标识授权；Linux 许可证说明见 `COPYING` 与 `LICENSES/`。
