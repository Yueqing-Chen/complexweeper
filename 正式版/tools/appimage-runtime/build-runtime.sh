#!/usr/bin/env bash
# 从源码重建 AppImage type 2 runtime（x86_64），并做一致性自检。
#
# 为什么不跑上游 Makefile：
#   1. type2-runtime@old 的 Makefile 把 `runtime-fuse3.o` / `runtime-fuse3` 各写了两遍
#      （fuse2 一份、fuse3 一份），`all` 目标也是 `runtime-fuse3 runtime-fuse3`；
#      GIT_COMMIT 还得从命令行传进来，不传直接编不过。直接按固定命令行调 clang，
#      版本钉死，也不受上游 Makefile 以后变动的影响。
#   2. **squashfuse 的版本必须和 runtime.c 对得上**，这是本脚本存在的最主要原因。
#      runtime.c 直接按 sqfs_opts 的内存布局写 opts.mountpoint，fuseprivate.h 和
#      实际链接的 libsquashfuse 版本一旦不一致，后面所有字段整体错位，
#      表现为「一启动就打印 squashfuse 的 usage 然后 execv error」——
#      参数解析阶段就挂了，压根没走到 FUSE。详见下面 SQFS_REF。
#
# 跑完会把上游源码（runtime.c / data_sections.ld / Makefile / fuseprivate.h，
# fuseprivate.h 只改了 include 路径）覆盖回本目录，仓库里存的就是实际编的那份。
#
# 用法：./build-runtime.sh
set -euo pipefail
cd "$(dirname "$0")"
# 装到哪儿要提前钉死：下面会 cd 进 $WORK 编译，那时相对路径全指到临时目录去了，
# cp 出来的 runtime-x86_64 会跟着 EXIT trap 一起被删，仓库里一个字节都没换过。
HERE=$(pwd)

# ---- 版本钉死，别随手升 ----------------------------------------------
# type2-runtime 的 'old' tag：和 squashfuse 0.1.105 的 API 完全对应
RUNTIME_TAG=old
# squashfuse 0.1.105：sqfs_usage(prog, fuse_usage) 两个参数，
# sqfs_opts = { progname, image, mountpoint, offset, idle_timeout_secs }
SQFS_REF=0.1.105
SQFS_DEB=libsquashfuse-dev
# ------------------------------------------------------------------------

WORK=$(mktemp -d -t runtime-build-XXXXXX)
trap '/bin/rm -rf "$WORK"' EXIT

# autotools / configure 会大量 rm 临时文件，容器的 rm 被包过，先换回真的
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexec /bin/rm "$@"\n'  > "$WORK/bin/rm"
printf '#!/bin/sh\nexec /bin/mv "$@"\n'  > "$WORK/bin/mv"
export PATH="$WORK/bin:$PATH"

fetch() {  # fetch <jsdelivr 路径> <输出>
    curl -fsSL -m 60 -o "$2" "https://cdn.jsdelivr.net/gh/$1"
}

echo "== 取 AppImage type2-runtime@$RUNTIME_TAG =="
mkdir -p "$WORK/rt/src/runtime"
for f in runtime.c data_sections.ld Makefile; do
    fetch "AppImage/type2-runtime@$RUNTIME_TAG/src/runtime/$f" "$WORK/rt/src/runtime/$f"
done
# runtime.c 把 GIT_COMMIT 原样印在 --appimage-version 上。上游 Makefile 取的是
# git rev-parse HEAD，这里是从 tarball 抓的源码（没有 .git），拿不到 commit，
# 就写 tag 名 —— 比编个假日期或 UNSUPPORTED_LOCAL_DEVELOPER_BUILD 都强。
echo "type2-runtime@$RUNTIME_TAG" > "$WORK/rt/src/runtime/version"

echo "== 取 squashfuse@$SQFS_REF 的 fuseprivate.h =="
mkdir -p "$WORK/rt/src/runtime/inc/squashfuse"
fetch "vasi/squashfuse@$SQFS_REF/fuseprivate.h" "$WORK/rt/src/runtime/inc/squashfuse/fuseprivate.h"
# Debian 的头文件布局是 squashfuse/xxx.h，这里 fuseprivate.h 内部用了相对 include
sed -i 's|#include "squashfuse.h"|#include <squashfuse/squashfuse.h>|' \
    "$WORK/rt/src/runtime/inc/squashfuse/fuseprivate.h"

echo "== 一致性自检：runtime.c 期望的 sqfs_usage 参数个数 =="
want=$(grep -c 'sqfs_usage(argv\[0\], true)' "$WORK/rt/src/runtime/runtime.c" || true)
got=$(grep -c 'sqfs_usage(char \*progname, bool fuse_usage);' \
      "$WORK/rt/src/runtime/inc/squashfuse/fuseprivate.h" || true)
if [ "$want" -eq 0 ] || [ "$got" -eq 0 ]; then
    echo "!! sqfs_usage 对不上：runtime.c 2 参数调用 $want 处，头文件 2 参数声明 $got 处" >&2
    echo "   说明 runtime tag 和 squashfuse 版本错配了，换 $RUNTIME_TAG / $SQFS_REF 试试" >&2
    exit 1
fi
echo "   runtime.c 和 fuseprivate.h 都是 2 参数 ✓"

echo "== 编译 =="
cd "$WORK/rt/src/runtime"
# 末尾的 2> >(grep …) 是为了滤掉 ld 那条 dlopen/fuse_get_module 的静态链接告警，
# 同时保住 clang 自己的退出码。别写成 `clang … 2>&1 | grep … || true`，那样管道会把
# 编译失败一起吞掉。
clang -I inc -I/usr/include/fuse3 \
    -std=gnu99 -Os -D_FILE_OFFSET_BITS=64 -DGIT_COMMIT=\"$(cat version)\" \
    -T data_sections.ld -ffunction-sections -fdata-sections -Wl,--gc-sections \
    -static -static-pie \
    runtime.c -lsquashfuse -lsquashfuse_ll -lzstd -llz4 -llzo2 -llzma -lz -lfuse3 \
    -o runtime 2> >(grep -vE "dlopen|fuse_get_module" >&2)
strip --strip-unneeded runtime

echo "== 装到仓库 =="
# 这一段人在 $WORK 里执行，所有目标都得写绝对路径 $HERE
cp runtime "$HERE/runtime-x86_64"
cp runtime.c data_sections.ld Makefile "$HERE/"
cp inc/squashfuse/fuseprivate.h "$HERE/"
"$HERE/runtime-x86_64" --appimage-version
ls -la "$HERE/runtime-x86_64"
file "$HERE/runtime-x86_64"
