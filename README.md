复扫雷 Complexweeper

扫雷，但雷是复数：四种雷分别是正实雷、负实雷、正虚雷、负虚雷；格子上的数字是它周围所有雷之和的模长。

翻开所有非雷格子就胜利。

原生程序，Zig，没有第三方库和运行依赖。有 Windows（Win32）和 Linux（X11）两个版本，共用同一份规则代码和同一张图集。

介绍：

有四种雷：正实雷、负实雷、正虚雷和负虚雷，也就是+1、-1、+i和-i。

一个格子显示的数是周围所有雷之和的模长。

因为周围最多 8 格，所以只可能出现 24 种数字：

0, 1, 2, 3, 4, 5, 6, 7, 8, 

√2, √5, √10, √13, √17, √26, √29, √34, √37, 

2√2, 2√5, 3√2, 4√2, 5√2, 2√10。

正负雷数量相等时会互相抵消，这种1正1负的正负对我们称为“抵消对”；

0和空白不是一回事。空白格子表示周围完全没有雷；0表示周围完全为抵消对。

规则：

当数字格子周围插上的旗帜数量等于真实雷数，且实虚比例符合真实比例或其倒数，则允许展开；可以利用这一点试探周围是否有抵消对。
谨记扫雷的胜利判定是翻开所有的格子，而不是插对全部的旗帜。

## 构建

### Windows

```powershell
.\build.ps1
```

产出 `正式版\复扫雷.exe`，需要 Zig 0.14.1。

### Linux（AppImage）

```bash
cd 正式版
./build-linux.sh
```

产出 `正式版/build/Complexweeper-1.0.12-x86_64.AppImage`（约 1.7 MB，自包含，
需要 x86_64）。要跑起来只依赖三样东西，都是 Linux 桌面本来就有的：

* `libX11` / `libXft` / `libfontconfig`
* FUSE（`libfuse3`）—— 没 FUSE 的环境（容器、极简系统）可以
  `APPIMAGE_EXTRACT_AND_RUN=1 ./Complexweeper-1.0.12-x86_64.AppImage` 退化成解压运行
* 一款中文字体（Noto Sans CJK、文泉驿等）。**包内不塞字体**，图省事也省 20 MB；
  一款都没有时程序会直接给出提示而不是画出乱码

构建需要：`zig 0.14.1`、`squashfs-tools`（`mksquashfs`）、`node`、
`file`。`node` 干两件事：先照 `build.ps1` 第 1 步那样用 `tools/gen_atlas.js` 从
`素材/` 生成图集（`src/atlas.bin` + `src/assets.zig`，这两个是构建产物、不入库，
跟 Windows 那边一致），再从图集里切出图标。

AppImage 的 runtime **是编译产物、不入库**，第一次构建要先编一次（脚本会自己抓源码）：

```bash
sudo apt-get install -y clang libfuse3-dev libsquashfuse-dev \
    liblz4-dev liblzo2-dev liblzma-dev libzstd-dev zlib1g-dev
./tools/appimage-runtime/build-runtime.sh
```

编好之后 `runtime-x86_64` 就在那儿了，以后 `./build-linux.sh` 直接可用。
**runtime 和 squashfuse 的版本必须配套**，坑和版本表见
`正式版/tools/appimage-runtime/README.md`，别随手升级。走 GitHub Actions 的话
这一步是自动的，不用手动做。

`./build-linux.sh --no-pkg` 只编译不打包。

Linux 版和其它几个命令行：

```bash
./Complexweeper-1.0.12-x86_64.AppImage              # 正常启动（需要 FUSE）
./Complexweeper-1.0.12-x86_64.AppImage --version
./Complexweeper-1.0.12-x86_64.AppImage --selftest 报告.txt   # 规则自检
./Complexweeper-1.0.12-x86_64.AppImage --appimage-extract     # 解开看内容，不需要 FUSE
APPIMAGE_EXTRACT_AND_RUN=1 ./Complexweeper-1.0.12-x86_64.AppImage   # 无 FUSE 时兜底
```

### 两个平台共用什么

`正式版/src/game.zig`（规则）、`正式版/src/atlas.bin`（图集）、`正式版/src/selftest.zig`
（自检）三个文件两个平台完全共用。界面层分开：`src/main.zig` + `src/win32.zig` 是
Windows 版，`src/main_linux.zig` + `src/x11.zig` 是 Linux 版。改规则只需要改一处。

Windows 版的最高分写 HKCU 注册表；Linux 版改写
`$XDG_CONFIG_HOME/complexweeper/scores.ini`（没有就退回 `~/.config/...`）。

### 改完 Linux 版怎么验

```bash
cd 正式版
./tools/check_x11_abi.sh        # 手写的 X11 绑定跟系统头文件对账
                                  # （extern 参数个数、extern struct 字段偏移）
./tools/ui_smoke.sh            # Xvfb 上跑 18 步真实交互，逐屏截图到 /tmp/csui
```

`check_x11_abi.sh` 是有来由的：`x11.zig` 的 X11 绑定全是手写的 extern 声明，
写错参数个数或者 extern struct 少一个成员都不会编译报错，只会在运行到那一行时炸。
这两个脚本把它们和 `/usr/include/X11` 逐项对账（需要 libx11-dev / libxft-dev /
libfreetype-dev）。

### 持续集成

两个平台各一个 workflow，push 到 `main`、提 PR、手动触发都会跑：

| workflow | 平台 | 产物 |
|---|---|---|
| `.github/workflows/build.yml` | windows-latest | `复扫雷.exe` + 两份自检报告 |
| `.github/workflows/build-linux.yml` | ubuntu-22.04 | `Complexweeper-1.0.12-x86_64.AppImage` + 自检报告 |

Linux 那个 job 会跑在 `debian:bookworm-slim` 容器里（宿主 `ubuntu-24.04` 只提供内核），
从头跑一遍上面这一套：编 runtime → X11 绑定对账 → 编译 + 规则自检 + 打 AppImage →
验 AppImage 能在无 FUSE 下解开并跑起来 → Xvfb 里跑完 18 步 UI 冒烟。冒烟失败会把
截图作为 artifact 传上来。

**为什么是 bookworm 容器而不是 ubuntu runner**：AppImage runtime 要链
`libsquashfuse`，而各发行版的可用程度差别很大——

| 环境 | libsquashfuse-dev | 能不能编 |
|---|---|---|
| debian bookworm | 0.1.105-1 | 能，符号齐全 |
| ubuntu-22.04 | 0.1.103-3 | **不能**，低层 FUSE 实现（`sqfs_ll_op_*` 等）整个不在包里 |
| ubuntu-24.04 | 0.5.0 | 不能，API 与 `sqfs_opts` 布局早已不兼容 |

workflow 里除了钉版本号，还查一遍静态库有没有那几个关键符号——0.1.103 那个坑
光看头文件发现不了（`sqfs_opts` 布局和 0.1.105 一模一样），只有查符号才拦得住。

## 素材来源：
扫雷原始图像素材：Microsoft（原版扫雷作者 Robert Donner、Curt Johnson）。
新增图像素材（24 个显示值、四种旗帜配色、计雷器第四格的 $i$ 单位、五张脸等）：青月晓。
程序图标：青月晓。

本程序与 Microsoft 公司无隶属关系。
代码按GPL-3.0授权（见 `LICENSE`）。上表中"扫雷原始图像素材"的权利属于 Microsoft，
不在 GPL-3.0 的授权范围内。
