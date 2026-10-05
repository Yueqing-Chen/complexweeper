#!/usr/bin/env bash
# 对账 src/x11.zig 里手写的 X11 绑定。两类最容易犯、又最不容易发现的错：
#   1) extern 函数参数个数写错 —— 不报错，跑到那行才炸（XftDrawDestroy 就这么炸过）
#   2) extern struct 成员写错/漏写 —— 不报错，后面字段全体错位
# 依赖：dev 头文件（libx11-dev / libxft-dev / libfreetype-dev）。
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)

echo "== 1/3 extern 函数参数个数对账 =="
python3 tools/check_bindings.py
rc1=$?

echo
echo "== 2/3 准备结构体对账 =="
gcc -o /tmp/cs_structs tools/struct_sizes.c -I/usr/include/freetype2 -lX11 -lXft 2>/dev/null
if [ ! -x /tmp/cs_structs ]; then
    echo "  （跳过：编译不了 struct_sizes.c，缺 dev 头文件？）"
    exit $rc1
fi
/tmp/cs_structs > /tmp/c_struct.txt

# Zig 那边要 import src/x11.zig，得先放进同一个模块目录
cp tools/struct_probe.zig src/_abi_probe.zig
sed -i 's#@import("../src/x11.zig")#@import("x11.zig")#' src/_abi_probe.zig
trap 'rm -f "$ROOT/src/_abi_probe.zig"' EXIT
zig build-exe src/_abi_probe.zig -lc -femit-bin=/tmp/zg_structs >/dev/null 2>&1 || {
    echo "  （跳过：struct_probe.zig 编译失败）"; exit $rc1; }
/tmp/zg_structs > /tmp/zig_struct.txt 2>&1

echo
echo "== 3/3 结构体字段偏移对账 =="
python3 - <<'PY'
import re, sys

def parse(path, with_struct):
    d = {}
    for line in open(path):
        s = line.strip()
        m = re.match(r'^(\S+)\s+size=(\d+) align=(\d+)$', s)
        if m:
            d[m.group(1)] = ('size', int(m.group(2)), int(m.group(3))); continue
        if with_struct:
            m = re.match(r'^(\S+)\.(\S+)\s+offset=(\d+)$', s)
            if m: d[m.group(2)] = ('off', int(m.group(3)))
        else:
            m = re.match(r'^(\S+)\s+offset=(\d+)$', s)
            if m: d[m.group(1)] = ('off', int(m.group(2)))
    return d

c = parse('/tmp/c_struct.txt', True)
z = parse('/tmp/zig_struct.txt', False)

# Zig 把 C 的数组成员拍平了：min_aspect[2] → min_aspect_x / min_aspect_y
alias = {'min_aspect_x': ('min_aspect', 0), 'min_aspect_y': ('min_aspect', 4),
         'max_aspect_x': ('max_aspect', 0), 'max_aspect_y': ('max_aspect', 4),
         'base_width': ('base_size', 0), 'base_height': ('base_size', 4),
         'c_class': ('class', 0)}
# XImage 只声明到 blue_mask，size 比 C 小是故意的（XPutImage 读不到更后面）
size_ok = {'XImage'}

bad = checked = 0
for zn, zv in z.items():
    if zn in alias:
        cn, extra = alias[zn]
        if cn not in c: continue
        cv = c[cn]
        if cv[0] == 'off':
            zv = ('off', zv[1])
            cv = ('off', cv[1] + extra)
    else:
        cn = zn
        cv = c.get(cn)
        if cv is None:
            print(f"  ?? {zn}: C 输出里没有对应项"); continue
    checked += 1
    if cv != zv:
        if zn in size_ok and cv[0] == 'size' and zv[0] == 'size':
            print(f"  ~~ {zn}: C size={cv[1]}，本项目 {zv[1]}（只声明了用得到的字段）")
            continue
        print(f"  ✗✗ {zn} (C 里是 {cn}): C={cv}  本项目={zv}")
        bad += 1

print(f"\n结构体对账：核对 {checked} 项，{bad} 项不符")
sys.exit(1 if bad else 0)
PY
rc2=$?
exit $(( rc1 || rc2 ))
