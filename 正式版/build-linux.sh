#!/usr/bin/env bash
# 复扫雷 Complexweeper —— Linux 版打包脚本，产出 x86_64 AppImage。
#
#   ./build-linux.sh            编译 + 打包
#   ./build-linux.sh --no-pkg   只编译
#   ZIG=/path/to/zig ./build-linux.sh
#
# 产物：build/复扫雷-Complexweeper-1.0.12-x86_64.AppImage
#
# 依赖：
#   zig 0.14.1            （CI 里断言这个版本，别改）
#   node                  生成图集 + 从图集切图标
#   mksquashfs            squashfs-tools
#   appimage-runtime      AppImage type 2 的 runtime（见 tools/appimage-runtime/）
set -euo pipefail
cd "$(dirname "$0")"

ZIG=${ZIG:-zig}
PKG=1
[ "${1:-}" = "--no-pkg" ] && PKG=0

APP_NAME="Complexweeper"
APP_TITLE="复扫雷 Complexweeper"
# 版本号直接取 src/main.zig 里的 APP_VERSION，跟 build.ps1 读的是同一处，
# 产出的文件名和 release.yml 的附件名都由它决定。
APP_VERSION=$(sed -n 's/.*const APP_VERSION = "\([^"]*\)".*/\1/p' src/main.zig | head -1)
[ -n "$APP_VERSION" ] || { echo "读不到 APP_VERSION，检查 src/main.zig"; exit 1; }
# main_linux.zig 里另有一份 APP_VERSION（main.zig 是 Windows 程序，带一堆 win32 依赖，
# Linux 这边没法 import，只能各留一份）。两份必须一致——不一致的话 --version 显示的
# 和包文件名会对不上，而且没人会发现。
LINUX_VERSION=$(sed -n 's/.*const APP_VERSION = "\([^"]*\)".*/\1/p' src/main_linux.zig | head -1)
if [ "$LINUX_VERSION" != "$APP_VERSION" ]; then
    echo "版本号不一致：src/main.zig = $APP_VERSION，src/main_linux.zig = ${LINUX_VERSION:-读不到}" >&2
    echo "两处都要改，否则 --version 显示的和 AppImage 文件名对不上" >&2
    exit 1
fi

ZIG_VER=$("$ZIG" version)
case "$ZIG_VER" in
    0.14.*) ;;
    *) echo "警告：Zig 版本是 $ZIG_VER，CI 固定要求 0.14.x（0.14.1 最稳）" ;;
esac

BUILD=build
APPDIR="$BUILD/AppDir"
OUT="$BUILD/${APP_NAME}-${APP_VERSION}-x86_64.AppImage"

echo "== 1/6 生成图集 =="
# src/atlas.bin 和 src/assets.zig 是 build 产物，不进版本库 —— build.ps1 第 1 步做的是
# 同一件事。仓库里 checkout 出来的源码没有这两个文件，Linux 这边也得自己生成，
# 否则 zig 会报找不到 assets.zig。
command -v node >/dev/null || {
    echo "找不到 node。生成图集和切图标都要它（build.ps1 也一样依赖）。" >&2
    exit 1
}
node tools/gen_atlas.js

echo "== 2/6 编译 x86_64-linux =="
mkdir -p "$BUILD"
# 把上一版残留的 AppImage 清掉。文件名带版本号，升降版本后 build/ 里会同时躺着
# 好几个，而 CI 的「挂到 Release」和本地验产物都是 ls build/*.AppImage —— 一旦匹配到
# 多份，取到的就不一定是这次的产物。
rm -f "$BUILD"/*.AppImage
"$ZIG" build-exe src/main_linux.zig \
    -target x86_64-linux-gnu -O ReleaseSmall \
    -L/usr/lib/x86_64-linux-gnu -lc -lX11 -lXft -lfontconfig \
    -femit-bin="$BUILD/cs-linux"
strip --strip-unneeded "$BUILD/cs-linux"
echo "   $BUILD/cs-linux  $(stat -c%s "$BUILD/cs-linux") 字节"

echo "== 3/6 规则自检 =="
DISPLAY="${DISPLAY:-}" "$BUILD/cs-linux" --selftest "$BUILD/selftest.txt"
tail -2 "$BUILD/selftest.txt" | sed 's/^/   /'

[ "$PKG" = 1 ] || { echo "完成（--no-pkg）"; exit 0; }

echo "== 4/6 组装 AppDir =="
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
         "$APPDIR/usr/share/applications" "$APPDIR/usr/share/metainfo"
cp "$BUILD/cs-linux" "$APPDIR/usr/bin/complexweeper"
chmod +x "$APPDIR/usr/bin/complexweeper"

# 图标：从 src/atlas.bin 里切 32×32 那张，最近邻放大到 256
# （node 在第 1 步已经查过了，这里没有再退让的必要——没图标包出来是不能发的）
node tools/make_icon.js src/atlas.bin "$APPDIR/usr/share/icons/hicolor/256x256/apps/complexweeper.png" 256
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/complexweeper.png" "$APPDIR/complexweeper.png"

cat > "$APPDIR/complexweeper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_TITLE
GenericName=扫雷
Comment=扫雷，但雷是复数：四种雷分别是正实雷、负实雷、正虚雷、负虚雷
Exec=complexweeper
Icon=complexweeper
Categories=Game;LogicGame;
Terminal=false
StartupWMClass=complexweeper
EOF
cp "$APPDIR/complexweeper.desktop" "$APPDIR/usr/share/applications/complexweeper.desktop"

# AppRun：优先跑 AppImage 内置的 usr/bin，找不到再退回系统 PATH
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
if [ -x "$HERE/usr/bin/complexweeper" ]; then
    exec "$HERE/usr/bin/complexweeper" "$@"
fi
exec complexweeper "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 运行时依赖：X11 / Xft / fontconfig。AppImage 不塞字体，中文靠宿主机的
# Noto Sans CJK / 文泉驿（启动时找不到会给出明确提示）。
cat > "$APPDIR/complexweeper.sh" <<'EOF'
# 不需要额外环境变量，保留这个文件是为了让 ldd 依赖清单在 AppDir 里可查
EOF

echo "== 5/6 mksquashfs =="
SQFS="$BUILD/app.squashfs"
rm -f "$SQFS"
# runtime 内置的 squashfuse 支持 gzip/zstd/xz/lz4/lzo；gzip 兼容性最好，体积对
# 这个只有 175KB 的程序也够用
# -no-xattrs：AppDir 落在带 POSIX ACL 的文件系统上时 mksquashfs 会刷一屏
# "Unrecognised xattr prefix system.posix_acl_*"。AppImage 靠权限位授权，ACL 本来
# 就不该进包，顺手别存。
mksquashfs "$APPDIR" "$SQFS" \
    -root-owned -noappend -no-progress -no-xattrs -comp gzip -b 131072 >/dev/null
echo "   $SQFS  $(stat -c%s "$SQFS") 字节"

echo "== 6/6 合成 AppImage =="
RUNTIME=tools/appimage-runtime/runtime-x86_64
if [ ! -f "$RUNTIME" ]; then
    echo "找不到 AppImage runtime：$RUNTIME"
    echo "见 tools/appimage-runtime/README.md（可以直接从 AppImage/type2-runtime 编）"
    exit 1
fi
# type2 的结构就是「runtime ELF 后面直接接 squashfs」；runtime 启动时自己解析 ELF
# 节头算出 squashfs 的偏移量，所以这里不用像老版本 appimagetool 那样回填 8 字节偏移。
rm -f "$OUT"
cat "$RUNTIME" "$SQFS" > "$OUT"
chmod +x "$OUT"

echo
echo "完成：$OUT"
echo "  $(stat -c%s "$OUT") 字节"
file "$OUT"
"$OUT" --appimage-offset | sed 's/^/  squashfs 偏移量: /'
echo
echo "验证："
echo "  $OUT --version"
echo "  $OUT --selftest /tmp/st.txt     # 规则自检"
echo "  $OUT --appimage-extract         # 解开看内容（不需要 FUSE）"
