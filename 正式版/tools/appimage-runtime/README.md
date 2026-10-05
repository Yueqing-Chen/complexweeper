# AppImage type 2 runtime（x86_64）

`runtime-x86_64` 是 AppImage type 2 的启动器：静态 PIE ELF，前面是它自己，后面紧跟
squashfs 镜像。执行时它解析自己的 ELF 节头算出 squashfs 的偏移量，挂载后 `chdir`
进去再 `exec AppRun`。所以拼 AppImage 就是 `cat runtime-x86_64 app.squashfs > out.AppImage`，
**不需要回填偏移量**（老版本 appimagetool 那套 8 字节小端偏移量只对更老的 runtime 有意义）。

## 版本组合（重要，别随手升）

| 组件 | 版本 | 为什么 |
|---|---|---|
| AppImage type2-runtime | tag **`old`** | `sqfs_usage(prog, fuse_usage)` 是 **2 参数** |
| squashfuse | **0.1.105** | `sqfs_opts` 只有 5 个字段，`mountpoint` 在偏移 16 |

**这两个必须配套。** runtime.c 里 `fusefs_main` 是按 `sqfs_opts` 的**内存布局**直接写
`opts.mountpoint` 的，而写入的偏移量是编译期从 `fuseprivate.h` 算出来的（`offsetof`），
实际写值的是链接进去的 `libsquashfuse` 里的 `sqfs_opt_proc`——**它按自己那版的布局写**。

拿 20251108 的 runtime（3 参数 `sqfs_usage`，`sqfs_opts` 多了 `subdir/uid/gid/notify_pipe`，
`mountpoint` 整体后移到偏移 24）去链 0.1.105 的库，就会：runtime 往偏移 24 写 mountpoint，
库往偏移 16 写 → runtime 读回 NULL → 参数解析失败。

**症状长这样**（一眼可辨，跟 FUSE 有没有没关系）：

```
squashfuse 0.1.104 (c) 2012 Dave Vasilevsky

Usage: /path/to/xxx.AppImage [options] ARCHIVE MOUNTPOINT
    -h   --help            print help
    ...
execv error: No such file or directory
```

参数解析阶段就挂了，**压根没走到 FUSE**。修好后同样的机器上应该看到的是真正的 FUSE 报错，
比如容器里没有 `/dev/fuse` 权限时会打印：

```
fuse: failed to open /dev/fuse: Operation not permitted
Cannot mount AppImage, please check your FUSE setup.
```

看到 `fuse:` 开头的行 = 参数解析已经过了；看到 `Usage: ... ARCHIVE MOUNTPOINT` = 没修好。

## 重新编译

```bash
sudo apt-get install -y clang libfuse3-dev libsquashfuse-dev \
    liblz4-dev liblzo2-dev liblzma-dev libzstd-dev zlib1g-dev binutils
./build-runtime.sh
```

`build-runtime.sh` 会自己抓源码、做上面那个一致性自检、再编译。手工做的话：

```bash
# 上游源码
git clone --depth 1 --branch old https://github.com/AppImage/type2-runtime
cd type2-runtime/src/runtime

# squashfuse 的 fuseprivate.h 头文件 Debian 没装，要从 squashfuse 仓库拿，
# 且**必须跟 libsquashfuse 的版本一致**（这里是 0.1.105）
mkdir -p inc/squashfuse
curl -Lo inc/squashfuse/fuseprivate.h \
    https://raw.githubusercontent.com/vasi/squashfuse/0.1.105/fuseprivate.h
sed -i 's|#include "squashfuse.h"|#include <squashfuse/squashfuse.h>|' inc/squashfuse/fuseprivate.h

# 不跑上游 Makefile：type2-runtime@old 的 Makefile 把 runtime-fuse3.o / runtime-fuse3
# 各写了两遍（fuse2 一份 fuse3 一份），all 目标也重复，GIT_COMMIT 还得从命令行传，
# 不传编不过。直接按固定命令行调 clang，版本钉死。
# -DGIT_COMMIT 里的值最终会印在 `--appimage-version` 上
clang -I inc -I/usr/include/fuse3 \
    -std=gnu99 -Os -D_FILE_OFFSET_BITS=64 -DGIT_COMMIT=\"$(cat version)\" \
    -T data_sections.ld -ffunction-sections -fdata-sections -Wl,--gc-sections \
    -static -static-pie \
    runtime.c -lsquashfuse -lsquashfuse_ll -lzstd -llz4 -llzo2 -llzma -lz -lfuse3 \
    -o runtime

strip --strip-unneeded runtime
./runtime --appimage-version
```

`data_sections.ld` 里 `.appimage` 段必须 `INSERT AFTER .interp`，magic 字节
`41 49 02` 依赖这个位置被各种工具（AppImageLauncher、appimaged、桌面集成脚本）
识别。实测编出来的 runtime 里这一段落在文件偏移 `0x400`：

```console
$ readelf -S runtime-x86_64 | grep appimage
  [ 1] .appimage  PROGBITS  0000000000000400  00000400
```

（上游在这个段后面还有个 `.static` 标记段，是给 AppImageLauncher 认「静态 runtime」
用的。但它只含 BYTE()、没被任何东西引用，开 `-Wl,--gc-sections` 会被回收掉，
`readelf` 里根本看不到，所以不用管它。）

## 运行时依赖

* **FUSE**（`libfuse3` + `/dev/fuse`）：正常桌面上都有。缺失时可以
  `APPIMAGE_EXTRACT_AND_RUN=1 ./xxx.AppImage` 退化成解压运行（不解压就无法运行，
  但在没有 FUSE 的环境里——比如容器、Minimal 环境、某些 WSL——这是唯一出路）。
  容器里还要 `sudo mknod /dev/fuse c 10 229`，但多数容器仍会被设备 cgroup 挡住。
* runtime 本身全静态，不需要 glibc 以外的东西。
* **AppImage 里不含字体和 X11 库**，扫雷本体只动态链接 `libX11` / `libXft` /
  `libfontconfig`，中文靠宿主机的 Noto Sans CJK / 文泉驿。
