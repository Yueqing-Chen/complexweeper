#!/usr/bin/env python3
"""把 src/x11.zig 里的 extern 声明逐个跟 /usr/include/X11 下的真实头文件对账。

重点查**参数个数**——手写绑定写错参数个数不会编译报错，只会在运行到那一行时炸
（XftDrawDestroy 就是这么把 XRenderFindDisplay 喂了个垃圾指针进去的）。
"""
import re
import sys
import glob
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

HDRS = [
    "/usr/include/X11/Xlib.h",
    "/usr/include/X11/Xutil.h",
    "/usr/include/X11/Xatom.h",
    "/usr/include/X11/keysym.h",
    "/usr/include/X11/extensions/Xrender.h",
    "/usr/include/X11/Xft/Xft.h",
    "/usr/include/fontconfig/fontconfig.h",
]


def strip(t: str) -> str:
    t = re.sub(r"/\*.*?\*/", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    t = re.sub(r"^\s*#.*$", " ", t, flags=re.M)
    return t


def nargs(args: str) -> int:
    args = args.strip()
    if args in ("void", ""):
        return 0
    return len([a for a in args.split(",") if a.strip()])


real = {}
for h in HDRS:
    if not os.path.exists(h):
        continue
    t = strip(open(h, errors="ignore").read())
    for m in re.finditer(r"\b(X[A-Za-z0-9_]+|Fc[A-Za-z0-9_]+)\s*\(([^;{()]*)\)\s*;", t):
        real.setdefault(m.group(1), set()).add(nargs(m.group(2)))

src = open("src/x11.zig", encoding="utf-8").read()
mine = {}
for m in re.finditer(r'pub extern\s+"\w+"\s+fn\s+(\w+)\s*\(([^)]*)\)', src):
    mine[m.group(1)] = nargs(m.group(2))

bad = ok = missing = 0
for name, n in sorted(mine.items()):
    if name not in real:
        print(f"  ?? {name}: 头文件里没匹配到（可能是宏，检查一下）")
        missing += 1
    elif n not in real[name]:
        print(f"  ✗✗ {name}: 本项目写了 {n} 个参数，头文件是 {sorted(real[name])}")
        bad += 1
    else:
        ok += 1

print(f"\n对账结果：{ok} 个参数个数一致，{bad} 个不符，{missing} 个未匹配")
sys.exit(1 if bad else 0)
