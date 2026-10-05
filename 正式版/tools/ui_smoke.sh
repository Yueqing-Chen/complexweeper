#!/usr/bin/env bash
# 在 Xvfb 上跑一遍 Linux 版的真实交互，逐屏截图存到 /tmp/csui/。
# 用途：改完 x11.zig / main_linux.zig 之后，确认事件、绘制、菜单、对话框都还正常。
#
# 坐标换算（窗口在屏幕 +80+60，MENU_H=22，ITEM_H=20）：
#   菜单栏第 i 个下拉项的行中心 = 60 + 22 + 20*i + 10
set -u

BIN=${1:-build/cs-linux}
OUT=${2:-/tmp/csui}
export DISPLAY=${DISPLAY:-:99}
WIN_X=80; WIN_Y=60

mkdir -p "$OUT"
pkill -x "$(basename "$BIN")" 2>/dev/null
sleep 0.4

"$BIN" >/tmp/cs-ui.out 2>/tmp/cs-ui.err &
APP=$!
sleep 2.5

shot() {  # shot <名字>  —— 主窗口裁一份 + 整屏缩一份（弹窗是独立顶层窗，得看整屏）
    echo -n "    窗口几何: $(geom)\n"
    import -window root "$OUT/root.png" 2>/dev/null
    convert "$OUT/root.png" -crop 1008x834+$WIN_X+$WIN_Y +repage "$OUT/$1.png"
    convert "$OUT/root.png" -resize 70% "$OUT/$1.full.png"
    echo "  → $1.png (+ .full.png)"
}
click() {  # click <screen_x> <screen_y> [button]
    xdotool mousemove "$1" "$2"; sleep 0.25
    xdotool click "${3:-1}"; sleep 0.6
}
drop() {  # drop <menu_x> <项序号>  —— 打开菜单并点第 n 项（0 起）
    local mx=$1 n=$2
    click "$mx" $((WIN_Y + 11))
    click $((mx + 20)) $((WIN_Y + 22 + 20 * n + 10))
}
key() { xdotool key "$1"; sleep 0.5; }
geom() { xwininfo -root -children 2>/dev/null | grep -o '复扫雷[^)]*)  [0-9]*x[0-9]*+[0-9]*+[0-9]*' | sed 's/.*)  //'; }

if ! kill -0 "$APP" 2>/dev/null; then echo "!! 启动就退了"; cat /tmp/cs-ui.err; exit 1; fi

echo "1. 初始画面";                 shot 01_initial
echo "2. 左键翻开 (2,3)";           click 184 438;        shot 02_opened
echo "3. 右键插旗 ×2";              click 456 612 3; click 584 676 3; shot 03_flags
echo "4. 打开「游戏」菜单";         click 105 71;         shot 04_menu
echo "5. 帮助菜单";                 click 135 71;         shot 05_help_menu
echo "6. 玩法与操作（对话框）";      click 155 92;         shot 06_help_text
echo "7. 关闭对话框";               key Escape;          shot 07_help_closed
echo "8. 关于复扫雷";               click 135 71; click 155 132; shot 08_about
echo "9. 关闭对话框";               key Escape;          shot 09_about_closed
echo "10. 最高分纪录";              click 105 71; click 125 232; shot 10_best
echo "11. 关闭对话框";              key Escape;          shot 11_best_closed
echo "12. 自定义雷区对话框";        click 105 71; click 125 192; shot 12_custom
# 自定义雷区对话框是独立顶层窗，位置 = 主窗口位置 + (40, 60) = 屏幕 (120, 120)
# 框在对话框内的坐标：高度 (80,14) 宽度 (80,44)，宽高各 70×22
DLG_X=120; DLG_Y=120
edit_h() { click $((DLG_X + 115)) $((DLG_Y + 25)); for _ in $(seq 8); do xdotool key BackSpace; done; xdotool type "$1"; }
edit_w() { key Tab; for _ in $(seq 8); do xdotool key BackSpace; done; xdotool type "$1"; }

echo "13. 填 高度=16 宽度=30";         edit_h 16; edit_w 30; shot 13_custom_typed
echo "14. 确定（应用自定义雷区）";      key Return;           shot 14_custom_applied
echo "15. 缩放 100%（默认 200%）";   click 105 71; click 125 272; sleep 0.9; shot 15_zoom100
echo "16. 恢复 200%";               click 105 71; click 125 292; sleep 0.9; shot 16_zoom200
echo "16b. 窗口位置应保持不变";     xwininfo -root -children 2>/dev/null | grep 复扫雷 | sed "s/^/    /"
echo "17. F2 新游戏";               key F2;              shot 17_newgame
echo "18. 退出";                    click 105 71; click 125 352; sleep 0.8

if kill -0 "$APP" 2>/dev/null; then echo "!! 点了退出还在跑"; kill "$APP" 2>/dev/null; rc=1
else wait "$APP" 2>/dev/null; echo "退出正常 (rc=$?)"; rc=0; fi
echo
echo "--- stderr ---"; cat /tmp/cs-ui.err
exit $rc
