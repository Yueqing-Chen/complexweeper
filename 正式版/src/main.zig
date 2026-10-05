// 复扫雷 正式版 · 主程序
// 纯 Win32 + GDI，无第三方库、无 libc、无运行时依赖，编译结果为单个 exe。
const std = @import("std");
const w = @import("win32.zig");
const g = @import("game.zig");
const A = @import("assets.zig");

// ------------------------------------------------------------------ 常量
const CLASS_MAIN = "ComplexSweeperMain";
const CLASS_DLG = "ComplexSweeperDlg";
const TIMER_ID: usize = 1;
/// 「脸扫雷」闪动用的一次性定时器
const TIMER_FLASH: usize = 2;

const IDM_NEW: usize = 100;
const IDM_BEGINNER: usize = 101;
const IDM_INTERMEDIATE: usize = 102;
const IDM_EXPERT: usize = 103;
const IDM_CUSTOM: usize = 104;
const IDM_EXIT: usize = 105;
const IDM_ZOOM1: usize = 110;
const IDM_ZOOM2: usize = 111;
const IDM_ZOOM3: usize = 112;
const IDM_HELP_HOW: usize = 200;
const IDM_BEST: usize = 106;
const IDM_HELP_ABOUT: usize = 202;

const IDC_EDIT_H: i32 = 1001;
const IDC_EDIT_W: i32 = 1002;
const IDC_EDIT_T1: i32 = 1003;
const IDC_EDIT_T2: i32 = 1004;
const IDC_EDIT_T3: i32 = 1005;
const IDC_EDIT_T4: i32 = 1006;
const IDC_BTN_OK: i32 = 1007;
const IDC_BTN_CANCEL: i32 = 1008;
const IDC_BTN_SPLIT: i32 = 1009;
const IDC_STATIC_ERR: i32 = 1010;

const C_BTNFACE = w.rgb(0xC0, 0xC0, 0xC0);
const C_HILIGHT = w.rgb(0xDF, 0xDF, 0xDF);
const C_SHADOW = w.rgb(0x80, 0x80, 0x80);
const C_BLACK = w.rgb(0, 0, 0);
const C_WHITE = w.rgb(0xFF, 0xFF, 0xFF);
const C_DARKGRAY = w.rgb(0x40, 0x40, 0x40);

// ------------------------------------------------------------------ 全局状态
pub var game: g.Game = .{};
var zoom: i32 = 2;
var hwnd_main: w.HWND = null;
var mem_dc: w.HDC = null;
var mem_bmp: w.HBITMAP = null;
var mem_w: i32 = 0;
var mem_h: i32 = 0;
var atlas_dc: w.HDC = null;
var atlas_bmp: w.HBITMAP = null;
var atlas_old: w.HGDIOBJ = null;
var atlas_pixels: [*]u8 = undefined;
var face_down = false;
/// 这次左键按下是不是"落在人脸按钮上"的：只有按下与松开都在脸上才重开
var face_armed = false;
/// 「脸扫雷」闪到什么时候（GetTickCount 的时间戳）：翻格、插旗时闪一下
var face_flash_until: u32 = 0;
const FACE_FLASH_MS: u32 = 200;
/// 当前被"按住"的格子（传统扫雷的按下预览）：-1 = 没有。松开时只有落在这一格上才真翻开
var press_cell: i32 = -1;
/// 左右键同时按住（或中键按住）时准备展开的那一格：-1 = 没有。
/// 按住期间它周围"即将被展开"的格子会先显示空白贴图，松手才真展开。
var chord_cell: i32 = -1;
/// 鼠标键此刻是否按着（双击的第二下也算"左键按下"）
var l_down = false;
var r_down = false;
var m_down = false;
var mouse_cell: i32 = -1;
var mouse_in_board = false;
var dialog_hwnd: w.HWND = null;
var dialog_done = false;
var dialog_cancel = false;
var edit_handles: [6]w.HWND = .{ null, null, null, null, null, null };
var dlg_err_hwnd: w.HWND = null;
var dlg_font: w.HFONT = null;
/// 对话框的统一底色（白）。对话框窗口、静态标签、编辑框都用它。
var dlg_bg_brush: w.HBRUSH = null;
var win_dc_scratch: w.HDC = null;
var done_flag = false;

// ------------------------------------------------------------------ 布局
pub const Layout = struct {
    z: i32,
    frame: i32,
    pad: i32,
    header_h: i32,
    gap: i32,
    box: i32,
    inner_w: i32,
    client_w: i32,
    client_h: i32,
    board_x: i32,
    board_y: i32,
    cell: i32,
    header_x: i32,
    header_y: i32,
    header_w: i32,
};

/// 数值区固定几格：实雷与计时器是**四格**（第四格也是数字），
/// 虚雷是三格（第四格留给那一格 `i` 单位）。两者相加都是四格，所以五块面板等宽。
const REAL_DIGITS: i32 = 4;
const IMAG_DIGITS: i32 = 3;

/// 数值区实际占几格：负数要占掉一格画负号（于是只剩 base−1 位数字），
/// 数值超出这个范围才再加一格。v = null（还没开局）就按 base 画空格子。
fn valueDigits(base: i32, v: ?i32) i32 {
    if (v == null) return base;
    const x = v.?;
    if (x >= 0) return if (x <= pow10i(base) - 1) base else base + 1;
    return if (x >= -(pow10i(base - 1) - 1)) base else base + 1;
}
/// 数值区占几格（实雷/计时器四格、虚雷三格）
fn panelValueDigits(imag: bool, v: ?i32) i32 {
    return valueDigits(if (imag) IMAG_DIGITS else REAL_DIGITS, v);
}
/// 一块面板占几格：数值区 + 虚雷那一格 `i` 单位（实雷与计时器没有这一格）
fn panelCells(imag: bool, v: ?i32) i32 {
    return panelValueDigits(imag, v) + (if (imag) @as(i32, 1) else 0);
}
/// 一个计雷器的宽度：图标 + 留白 + N 格 LED + 边框（内容刚好等于这个宽度，不溢出不裁切）
fn counterWidth(z: i32, digits: i32) i32 {
    return 16 * z + 2 * z + digits * 13 * z + 2 * z;
}
/// 计雷器上显示的是"这一类雷还剩几颗没标"，并且带上这一类雷自己的符号与单位：
///   正实雷 +k    → k（四格数字）      负实雷 −k    → −k（负号占一格，仍是四格）
///   正虚雷 +k·i  → 三格数字 + 一格 i   负虚雷 −k·i  → 负号 + 两格数字 + 一格 i（四格）
/// 于是标一颗负实旗帜会让那个负数朝零走，看起来就是"数字增加"。
fn counterValue(t: usize) i32 {
    const k = game.unmarked(t);
    return switch (t) {
        2, 4 => -k,
        else => k,
    };
}
/// 还没开局时计雷器画空格子（此时各类雷的颗数还没抽出来）
fn counterShown(t: usize) ?i32 {
    if (!game.started) return null;
    return counterValue(t);
}
/// 虚雷（正、负）的第四格是 i 单位，实雷的第四格是数字
fn counterImag(t: usize) bool {
    return t == 3 or t == 4;
}
/// 计雷器竖排那一列的整体宽度（绘制与人脸定位共用，保证两者一致）
fn countersWidth(L: Layout) i32 {
    var widest: i32 = 0;
    for (1..5) |t| {
        widest = @max(widest, counterWidth(L.z, panelCells(counterImag(t), counterShown(t))));
    }
    return widest;
}
/// 计时器面板宽度：四格 LED + 边框（没有图标那一块）
fn timerWidth(z: i32) i32 {
    return 4 * 13 * z + 2 * z;
}
/// 表头最小宽度：左侧一列计雷器 + 人脸 + 计时 + 留白。
/// 计雷器按常态四格算，数值溢出（≥10000 或 ≤−1000）时那一行自己变宽一丁点。
fn headerContentWidth(z: i32) i32 {
    const col = counterWidth(z, 4);
    return 4 * z + col + 8 * z + FACE_SIZE * z + 8 * z + timerWidth(z) + 4 * z;
}

fn layout() Layout {
    const z = zoom;
    const frame = 3 * z;
    const pad = 6 * z;
    const gap = 6 * z;
    const box = 3 * z;
    const cell = 16 * z;
    const board_w = @as(i32, game.w) * cell + 2 * box;
    const hw = headerContentWidth(z);
    const inner_w = @max(board_w, hw);
    const client_w = inner_w + 2 * (frame + pad);
    // 表头里四个计雷器竖着排：上下边框 2z×2 + 内边距 3z×2 + 四行 26z + 三个行距 2z
    const counters_h = 4 * (26 * z) + 3 * (2 * z);
    const header_h = 2 * (2 * z) + 2 * (3 * z) + counters_h;
    const client_h = 2 * (frame + pad) + header_h + gap + @as(i32, game.h) * cell + 2 * box;
    return .{
        .z = z,
        .frame = frame,
        .pad = pad,
        .header_h = header_h,
        .gap = gap,
        .box = box,
        .inner_w = inner_w,
        .client_w = client_w,
        .client_h = client_h,
        .board_x = frame + pad + @divTrunc(inner_w - board_w, 2) + box,
        .board_y = frame + pad + header_h + gap + box,
        .cell = cell,
        .header_x = frame + pad,
        .header_y = frame + pad,
        .header_w = inner_w,
    };
}

/// 计雷器那一列的起始坐标（四个竖排）
fn countersX(L: Layout) i32 {
    return L.header_x + 4 * L.z;
}
fn countersY(L: Layout) i32 {
    return L.header_y + 2 * L.z + 3 * L.z;
}
/// 人脸按钮就是那张 24×24 贴图本身：素材里已经把立体边画进去了
/// （上/左 2 像素白高光，下/右 2 像素 #808080 阴影；按下的那张是反过来画的），
/// 所以这里**不能再自己画一圈 3D 边框**，否则会套出双层边（就是看起来多出来的那层底图）。
const FACE_SIZE: i32 = 24;
/// 贴图里的脸在 24×24 里偏右下半个像素（左边距 5、右边距 4，上下同理），
/// 再加上手动微调，整体往左上挪这么多屏幕像素。
const FACE_NUDGE: i32 = 2;

/// 人脸按钮左上角：先在表头正中摆，再整体往左上挪 FACE_NUDGE
fn faceLeft(L: Layout) i32 {
    const size = FACE_SIZE * L.z;
    const counters_end = countersX(L) + countersWidth(L);
    const timer_start = timerX(L);
    const clearance = 6 * L.z;
    var fx = L.header_x + @divTrunc(L.header_w, 2) - @divTrunc(size, 2);
    if (fx < counters_end + clearance) fx = counters_end + clearance;
    if (fx + size > timer_start - clearance) fx = timer_start - clearance - size;
    if (fx < L.header_x) fx = L.header_x;
    return fx - FACE_NUDGE;
}

fn faceTop(L: Layout) i32 {
    return L.header_y + @divTrunc(L.header_h - FACE_SIZE * L.z, 2) - FACE_NUDGE;
}

fn timerX(L: Layout) i32 {
    return L.header_x + L.header_w - 4 * L.z - timerWidth(L.z);
}

fn timerY(L: Layout) i32 {
    return L.header_y + @divTrunc(L.header_h - 26 * L.z, 2);
}
// ------------------------------------------------------------------ 绘图小工具
fn fill(dc: w.HDC, x: i32, y: i32, cw: i32, ch: i32, color: w.DWORD) void {
    if (cw <= 0 or ch <= 0) return;
    var r = w.RECT{ .left = x, .top = y, .right = x + cw, .bottom = y + ch };
    const br = w.CreateSolidBrush(color);
    _ = w.FillRect(dc, &r, br);
    _ = w.DeleteObject(br);
}

/// 经典立体边框：raised = 左上亮、右下暗；sunken 反过来
fn draw3d(dc: w.HDC, x: i32, y: i32, cw: i32, ch: i32, t: i32, raised: bool) void {
    const a = if (raised) C_HILIGHT else C_SHADOW;
    const b = if (raised) C_SHADOW else C_HILIGHT;
    fill(dc, x, y, cw, t, a); // 上
    fill(dc, x, y, t, ch, a); // 左
    fill(dc, x, y + ch - t, cw, t, b); // 下
    fill(dc, x + cw - t, y, t, ch, b); // 右
}

/// 方形贴图（格子 16×16、图标 16×16、人脸 24×24）的简写
fn blitSpriteSq(dc: w.HDC, sprite: u16, x: i32, y: i32, size: i32) void {
    blitSprite(dc, sprite, x, y, size, size);
}
/// 贴一张图集里的图。宽高必须分开传：素材里 LED 数字是 13×23，不是方的。
/// 早先这里只收一个 size 并同时当宽高用，数字就被纵向压扁成 13z×13z（看起来像"纵向没放大"）。
fn blitSprite(dc: w.HDC, sprite: u16, x: i32, y: i32, dw: i32, dh: i32) void {
    const r = A.rect(sprite);
    if (dw == r.w and dh == r.h) {
        _ = w.BitBlt(dc, x, y, dw, dh, atlas_dc, r.x, r.y, w.SRCCOPY);
    } else {
        _ = w.StretchBlt(dc, x, y, dw, dh, atlas_dc, r.x, r.y, r.w, r.h, w.SRCCOPY);
    }
}

/// 画一个 LED 数字串；返回宽度。v = null 表示空
fn drawLed(dc: w.HDC, x: i32, y: i32, v: ?i32, digits: i32, z: i32) i32 {
    const lw = 13 * z;
    const lh = 23 * z;
    var cx = x;
    if (v == null) {
        var i: i32 = 0;
        while (i < digits) : (i += 1) {
            blitSprite(dc, A.led_blank, cx, y, lw, lh);
            cx += lw;
        }
        return cx - x;
    }
    const val = v.?;
    if (val < 0) {
        blitSprite(dc, A.led_minus, cx, y, lw, lh);
        cx += lw;
        var m = -val;
        const lim = pow10i(digits - 1) - 1;
        if (m > lim) m = lim;
        var buf: [4]u8 = undefined;
        const n = fmtDigits(&buf, @intCast(m), @intCast(digits - 1));
        for (buf[0..n]) |ch| {
            blitSprite(dc, digitSprite(ch), cx, y, lw, lh);
            cx += lw;
        }
    } else {
        var m = val;
        const lim = pow10i(digits) - 1;
        if (m > lim) m = lim;
        var buf: [4]u8 = undefined;
        const n = fmtDigits(&buf, @intCast(m), @intCast(digits));
        for (buf[0..n]) |ch| {
            blitSprite(dc, digitSprite(ch), cx, y, lw, lh);
            cx += lw;
        }
    }
    return cx - x;
}

fn pow10i(n: i32) i32 {
    var r: i32 = 1;
    var i: i32 = 0;
    while (i < n) : (i += 1) r *= 10;
    return r;
}

fn fmtDigits(buf: []u8, v: u32, digits: u32) usize {
    var i: usize = digits;
    var x = v;
    while (i > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (x % 10));
        x /= 10;
    }
    return digits;
}

fn digitSprite(ch: u8) u16 {
    return switch (ch) {
        '0' => A.led_0,
        '1' => A.led_1,
        '2' => A.led_2,
        '3' => A.led_3,
        '4' => A.led_4,
        '5' => A.led_5,
        '6' => A.led_6,
        '7' => A.led_7,
        '8' => A.led_8,
        else => A.led_9,
    };
}

fn faceSprite() u16 {
    // 按住人脸按钮 → 按下脸（结束后按也算：那是"准备重开"的手势）
    if (face_down) return A.face_down;
    if (game.over) return if (game.win) A.face_win else A.face_dead;
    // 棋盘上按着键（准备翻开 / 准备展开 / 插旗）→ 脸扫雷
    if (boardHeld()) return A.face_scan;
    // 动作刚做完的那 200ms 也保持脸扫雷（由 TIMER_FLASH 收回）
    if (nowMs() < face_flash_until) return A.face_scan;
    return A.face_normal;
}
/// 棋盘上是否有键按着：左键（不是按在人脸上）、右键、中键都算
fn boardHeld() bool {
    return r_down or m_down or (l_down and !face_down);
}
/// 展开一格邻域（左右键同时点击 / 中键松手时走这条）：真展开了就让脸闪一下，
/// 结束时（踩雷/通关）不闪，直接交给死亡脸/胜利脸。
fn doExpand(hwnd: w.HWND, c: usize) void {
    const m0 = game.moves;
    game.tryExpand(c);
    afterGameAction(hwnd);
    if (game.moves != m0 and !game.over) flashFace(hwnd);
    _ = w.InvalidateRect(hwnd, null, 0);
}

/// 触发一次「脸扫雷」闪动（翻格/插旗时调用）
fn flashFace(hwnd: w.HWND) void {
    face_flash_until = nowMs() +% FACE_FLASH_MS;
    _ = w.SetTimer(hwnd, TIMER_FLASH, FACE_FLASH_MS, null);
}

fn timerSeconds() i32 {
    if (!game.started) return 0;
    return @intCast(@min(@as(u32, 9999), game.elapsed_ms / 1000));
}

fn nowMs() u32 {
    return w.GetTickCount();
}

// ------------------------------------------------------------------ 绘制
fn paint(dc: w.HDC, L: Layout) void {
    // 背景
    fill(dc, 0, 0, L.client_w, L.client_h, C_BTNFACE);
    // 外框（凸起）
    draw3d(dc, 0, 0, L.client_w, L.client_h, L.frame, true);

    // 凸起面板（计雷器 + 人脸 + 计时）
    const hx = L.header_x;
    const hy = L.header_y;
    const hh = L.header_h;
    const hw2 = L.header_w;
    draw3d(dc, hx, hy, hw2, hh, 2 * L.z, false);

    // 四个计雷器：竖排一列。实雷四格数字，虚雷三格数字 + 一格 i，五块面板因此等宽。
    const col_x = countersX(L);
    var cy = countersY(L);
    for (1..5) |t| {
        const val = counterShown(t);
        const imag = counterImag(t);
        const cw2 = counterWidth(L.z, panelCells(imag, val));
        draw3d(dc, col_x, cy, cw2, 26 * L.z, 1 * L.z, false);
        blitSpriteSq(dc, flagSprite(@intCast(t)), col_x + L.z + L.z, cy + @divTrunc(26 * L.z - 16 * L.z, 2), 16 * L.z);
        const led_x = col_x + L.z + 2 * L.z + 16 * L.z;
        const led_y = cy + @divTrunc(26 * L.z - 23 * L.z, 2);
        const vw = drawLed(dc, led_x, led_y, val, panelValueDigits(imag, val), L.z);
        // 虚雷还有第四格 i 单位（没开局时那一格也画成空格子，不留白）
        if (imag) blitSprite(dc, if (val == null) A.led_blank else A.led_i, led_x + vw, led_y, 13 * L.z, 23 * L.z);
        cy += 26 * L.z + 2 * L.z;
    }
    // 计时（右对齐，垂直居中；同样是四格数字）
    const tx = timerX(L);
    const ty = timerY(L);
    const tv: ?i32 = if (game.started) timerSeconds() else null;
    draw3d(dc, tx, ty, timerWidth(L.z), 26 * L.z, 1 * L.z, false);
    _ = drawLed(dc, tx + L.z, ty + @divTrunc(26 * L.z - 23 * L.z, 2), tv, panelValueDigits(false, tv), L.z);

    // 人脸：贴图自带立体边，直接贴，不再画边框
    blitSpriteSq(dc, faceSprite(), faceLeft(L), faceTop(L), FACE_SIZE * L.z);

    // 棋盘凹槽
    const bx = L.board_x - L.box;
    const by = L.board_y - L.box;
    const bw = @as(i32, game.w) * L.cell + 2 * L.box;
    const bh = @as(i32, game.h) * L.cell + 2 * L.box;
    draw3d(dc, bx, by, bw, bh, L.box, false);

    // 格子
    var i: usize = 0;
    while (i < game.n) : (i += 1) {
        const r: i32 = @intCast(i / game.w);
        const c: i32 = @intCast(i % game.w);
        const x = L.board_x + c * L.cell;
        const y = L.board_y + r * L.cell;
        blitSpriteSq(dc, cellSprite(i), x, y, L.cell);
    }
    // 没有状态行：原版扫雷底部就是空的（判据不通过时不作任何提示，只留状态枚举给自检）
}

fn flagSprite(t: u8) u16 {
    return switch (t) {
        1 => A.flag_1,
        2 => A.flag_2,
        3 => A.flag_3,
        else => A.flag_4,
    };
}
fn mineSprite(t: u8) u16 {
    return switch (t) {
        1 => A.mine_1,
        2 => A.mine_2,
        3 => A.mine_3,
        else => A.mine_4,
    };
}
fn boomSprite(t: u8) u16 {
    return switch (t) {
        1 => A.boom_1,
        2 => A.boom_2,
        3 => A.boom_3,
        else => A.boom_4,
    };
}
fn wrongSprite(t: u8) u16 {
    return switch (t) {
        1 => A.wrong_1,
        2 => A.wrong_2,
        3 => A.wrong_3,
        else => A.wrong_4,
    };
}

/// 这一格能不能作为展开的起点（门槛和 Game.tryExpand 一致：已翻开的非雷格，且还有未插旗的邻格）
fn chordable(c: usize) bool {
    if (c >= game.n) return false;
    if (game.over or game.open[c] == 0 or game.mine[c] != 0) return false;
    var buf: [8]usize = undefined;
    const k = game.nbrs(c, &buf);
    for (buf[0..k]) |j| {
        if (game.open[j] == 0 and game.flag[j] == 0) return true;
    }
    return false;
}

/// 这一格是不是"按住期间即将被展开"的：chord_cell 的未翻开、未插旗邻格。
/// 注意只看"这个手势会碰哪些格子"，不看判据——判据不通过时棋盘上不给任何提示。
fn chordTarget(i: usize) bool {
    if (chord_cell < 0) return false;
    const c: usize = @intCast(chord_cell);
    if (!chordable(c)) return false;
    if (game.open[i] != 0 or game.flag[i] != 0) return false;
    var buf: [8]usize = undefined;
    const k = game.nbrs(c, &buf);
    for (buf[0..k]) |j| {
        if (j == i) return true;
    }
    return false;
}

fn cellSprite(i: usize) u16 {
    // 按住不放的那一格：画成已翻开的空白（传统扫雷的按下预览），松手才真翻开
    if (press_cell >= 0 and @as(usize, @intCast(press_cell)) == i and game.open[i] == 0) return A.blank;
    // 左右键同时按住 / 中键按住：这一格待会儿会被展开，先画成空白（松开才真展开）
    if (chordTarget(i)) return A.blank;
    const revealed = game.over and !game.win;
    if (game.open[i] != 0) {
        if (game.mine[i] != 0) {
            if (game.boom == @as(i32, @intCast(i))) return boomSprite(game.mine[i]);
            return mineSprite(game.mine[i]);
        }
        const D = game.clue[i];
        if (D == 0 and game.nbrMineCount(i) == 0) return A.blank;
        const s = A.num_by_D[@intCast(D)];
        return if (s == 0xFFFF) A.blank else s;
    }
    if (game.flag[i] != 0) {
        const right = game.mine[i] == game.flag[i];
        if (revealed and !right) return wrongSprite(game.flag[i]);
        return flagSprite(game.flag[i]);
    }
    if (revealed and game.mine[i] != 0) return mineSprite(game.mine[i]);
    return A.closed;
}

const Msg = g.Msg;

/// 自定义对话框的校验错误
const DlgErr = enum(u8) { none = 0, height, width, sum_zero, sum_big };
fn dlgErrText(e: DlgErr) [*:0]const u16 {
    return switch (e) {
        .none => w.wstr(""),
        .height => w.wstr("高度要在 9 – 30 之间。"),
        .width => w.wstr("宽度要在 9 – 40 之间。"),
        .sum_zero => w.wstr("四种雷合计至少 1 颗。"),
        .sum_big => w.wstr("合计超过上限（格数 − 9）。"),
    };
}

// ------------------------------------------------------------------ 双缓冲
fn ensureMemDc(hwnd: w.HWND, L: Layout) void {
    if (mem_dc != null and mem_w == L.client_w and mem_h == L.client_h) return;
    const dc = w.GetDC(hwnd);
    if (mem_bmp != null) {
        _ = w.SelectObject(mem_dc, w.GetStockObject(0));
        _ = w.DeleteObject(mem_bmp);
        _ = w.DeleteDC(mem_dc);
    }
    mem_dc = w.CreateCompatibleDC(dc);
    mem_bmp = w.CreateCompatibleBitmap(dc, L.client_w, L.client_h);
    _ = w.SelectObject(mem_dc, mem_bmp);
    mem_w = L.client_w;
    mem_h = L.client_h;
    _ = w.SetStretchBltMode(mem_dc, 3); // COLORONCOLOR = 最近邻
    _ = w.ReleaseDC(hwnd, dc);
}

fn repaint(hwnd: w.HWND) void {
    const L = layout();
    ensureMemDc(hwnd, L);
    paint(mem_dc, L);
    const dc = w.GetDC(hwnd);
    _ = w.BitBlt(dc, 0, 0, L.client_w, L.client_h, mem_dc, 0, 0, w.SRCCOPY);
    _ = w.ReleaseDC(hwnd, dc);
}

/// 窗口标题固定不变（难度、局面信息都不往标题里塞）
const APP_TITLE = "复扫雷 Complexweeper";
/// 版本号：**只有这一处**。以后每次改动都顺手把它 +1，关于对话框与两个自检报告的抬头都读它。
const APP_VERSION = "1.0.13";

// ------------------------------------------------------------------ 棋盘交互
fn cellAt(L: Layout, px: i32, py: i32) i32 {
    const cx = px - L.board_x;
    const cy = py - L.board_y;
    if (cx < 0 or cy < 0) return -1;
    const c = @divTrunc(cx, L.cell);
    const r = @divTrunc(cy, L.cell);
    if (c < 0 or r < 0 or c >= game.w or r >= game.h) return -1;
    return @intCast(@as(usize, @intCast(r)) * game.w + @as(usize, @intCast(c)));
}

fn inFace(L: Layout, px: i32, py: i32) bool {
    const fw = FACE_SIZE * L.z;
    const fx = faceLeft(L);
    const fy = faceTop(L);
    return px >= fx and py >= fy and px < fx + fw and py < fy + fw;
}

fn startNewGame(seed_override: ?u32) void {
    const seed = seed_override orelse @as(u32, @intCast(w.GetTickCount()));
    game.newGame(seed);
    // 重开时把"按住/按下"的临时状态一起清掉（可能从菜单或人脸按钮进来）
    press_cell = -1;
    chord_cell = -1;
    l_down = false;
    r_down = false;
    m_down = false;
    face_down = false;
    face_armed = false;
    face_flash_until = 0;
    _ = w.KillTimer(hwnd_main, TIMER_FLASH);
    _ = w.InvalidateRect(hwnd_main, null, 0);
}

fn setPreset(idx: i32) void {
    switch (idx) {
        0 => {
            game.w = g.PRESETS[0].w;
            game.h = g.PRESETS[0].h;
            game.mines = g.PRESETS[0].mines;
            game.type_count = [_]u16{0} ** 5;
        },
        1 => {
            game.w = g.PRESETS[1].w;
            game.h = g.PRESETS[1].h;
            game.mines = g.PRESETS[1].mines;
            game.type_count = [_]u16{0} ** 5;
        },
        2 => {
            game.w = g.PRESETS[2].w;
            game.h = g.PRESETS[2].h;
            game.mines = g.PRESETS[2].mines;
            game.type_count = [_]u16{0} ** 5;
        },
        else => {},
    }
    resizeWindowForBoard();
    startNewGame(null);
}

fn resizeWindowForBoard() void {
    const L = layout();
    var r = w.RECT{ .left = 0, .top = 0, .right = L.client_w, .bottom = L.client_h };
    const style: w.DWORD = w.WS.OVERLAPPED | w.WS.CAPTION | w.WS.SYSMENU | w.WS.MINIMIZEBOX;
    _ = w.AdjustWindowRect(&r, style, w.TRUE);
    _ = w.SetWindowPos(hwnd_main, null, 0, 0, r.right - r.left, r.bottom - r.top, 0x0002 | 0x0004 | 0x0010); // NOMOVE|NOZORDER|NOACTIVATE
}

// ------------------------------------------------------------------ 自定义对话框
var dlg_state: struct {
    h: i32 = 16,
    w: i32 = 30,
    t: [5]i32 = .{ 0, 25, 25, 25, 24 },
    err: DlgErr = .none,
} = .{};

fn getEditInt(h: w.HWND, fallback: i32) i32 {
    var buf: [16]u16 = undefined;
    const n = w.GetWindowTextW(h, &buf, 16);
    if (n <= 0) return fallback;
    var v: i32 = 0;
    var any = false;
    for (buf[0..@intCast(n)]) |ch| {
        if (ch < '0' or ch > '9') continue;
        v = v * 10 + @as(i32, @intCast(ch - '0'));
        any = true;
        if (v > 100000) v = 100000;
    }
    return if (any) v else fallback;
}

fn setEditInt(h: w.HWND, v: i32) void {
    var buf: [16]u16 = undefined;
    const s = w.u32ToW(&buf, @intCast(v));
    _ = w.SetWindowTextW(h, s.ptr);
}

/// 读四个「每种雷颗数」编辑框（edit_handles[2..5]）。
/// 别写成 edit_handles[1..4]——那会把宽度框当成第一种雷（这个 bug 被 uitest 抓过一次）。
fn readDlgCounts() [5]i32 {
    var t = [5]i32{ 0, 0, 0, 0, 0 };
    for (1..5) |k| t[k] = getEditInt(edit_handles[k + 1], 0);
    return t;
}

fn dlgWndProc(hwnd: w.HWND, msg: w.UINT, wp: w.WPARAM, lp: w.LPARAM) callconv(.c) w.LRESULT {
    switch (msg) {
        // 整个对话框是白的：静态标签用白刷子当背景（不返回刷子的话，空白标签会画出一条
        // 白条——就是"按合计均分右边那个奇怪的白条"，其实是错误提示那格 STATIC）。
        w.WM.CTLCOLORSTATIC => {
            const dc: w.HDC = @ptrFromInt(wp);
            _ = w.SetBkMode(dc, 1); // TRANSPARENT
            _ = w.SetTextColor(dc, C_BLACK);
            return @bitCast(@intFromPtr(dlg_bg_brush));
        },
        w.WM.CTLCOLOREDIT => return @bitCast(@intFromPtr(dlg_bg_brush)),
        w.WM.ERASEBKGND => {
            var rc: w.RECT = undefined;
            _ = w.GetClientRect(hwnd, &rc);
            const dc: w.HDC = @ptrFromInt(wp);
            _ = w.FillRect(dc, &rc, dlg_bg_brush);
            return 1;
        },
        w.WM.COMMAND => {
            const id = @as(i32, @intCast(@as(u16, @truncate(wp))));
            if (id == IDC_BTN_OK) {
                dlgApply();
                return 0;
            } else if (id == IDC_BTN_CANCEL) {
                dialog_cancel = true;
                dialog_done = true;
                return 0;
            } else if (id == IDC_BTN_SPLIT) {
                var sum: i32 = 0;
                const cur = readDlgCounts();
                for (1..5) |t| sum += cur[t];
                if (sum <= 0) sum = 99;
                const sp = g.splitEvenly(@intCast(@min(sum, 999)));
                for (1..5) |t| setEditInt(edit_handles[t + 1], sp[t]);
                return 0;
            }
            return 0;
        },
        w.WM.KEYDOWN => {
            const vk = wp;
            if (vk == 0x0D) { // Enter
                dlgApply();
                return 0;
            } else if (vk == 0x1B) { // Esc
                dialog_cancel = true;
                dialog_done = true;
                return 0;
            } else if (vk == 0x09) { // Tab：在编辑框之间轮换
                const cur = w.GetFocus();
                var idx: usize = 0;
                for (0..6) |i| {
                    if (edit_handles[i] == cur) idx = i;
                }
                idx = (idx + 1) % 6;
                _ = w.SetFocus(edit_handles[idx]);
                return 0;
            }
            return 0;
        },
        w.WM.CLOSE => {
            dialog_cancel = true;
            dialog_done = true;
            return 0;
        },
        else => return w.DefWindowProcW(hwnd, msg, wp, lp),
    }
}

fn dlgApply() void {
    const h = getEditInt(edit_handles[0], 16);
    const ww = getEditInt(edit_handles[1], 30);
    const t = readDlgCounts();
    var sum: i32 = 0;
    for (1..5) |k| sum += t[k];
    if (h < 9 or h > 30) {
        dlg_state.err = .height;
        setErrText();
        return;
    }
    if (ww < 9 or ww > 40) {
        dlg_state.err = .width;
        setErrText();
        return;
    }
    if (sum < 1) {
        dlg_state.err = .sum_zero;
        setErrText();
        return;
    }
    const maxm = ww * h - 9;
    if (sum > maxm) {
        dlg_state.err = .sum_big;
        setErrText();
        return;
    }
    dlg_state.err = .none;
    setErrText();
    game.w = @intCast(ww);
    game.h = @intCast(h);
    game.mines = @intCast(sum);
    game.type_count = .{ 0, @intCast(t[1]), @intCast(t[2]), @intCast(t[3]), @intCast(t[4]) };

    dialog_done = true;
}

fn setErrText() void {
    _ = w.SetWindowTextW(dlg_err_hwnd, dlgErrText(dlg_state.err));
}

/// 建对话框窗口与控件。与模态循环分开，便于自检直接驱动。
fn createCustomWindow() bool {
    dialog_done = false;
    dialog_cancel = false;
    if (dlg_bg_brush == null) dlg_bg_brush = w.CreateSolidBrush(C_WHITE);
    var wc: w.WNDCLASSEXW = std.mem.zeroes(w.WNDCLASSEXW);
    wc.cbSize = @sizeOf(w.WNDCLASSEXW);
    wc.lpfnWndProc = dlgWndProc;
    wc.hInstance = w.GetModuleHandleW(null);
    wc.hCursor = w.LoadCursorW(null, @ptrFromInt(w.IDC.ARROW));
    wc.hbrBackground = dlg_bg_brush; // 白底
    wc.lpszClassName = w.wstr(CLASS_DLG);
    _ = w.RegisterClassExW(&wc);

    const dw: i32 = 330;
    const dh: i32 = 246; // 去掉"四种雷各自的颗数"那一行之后，高度跟着收 22
    const scr_w = w.GetSystemMetrics(w.SM.CXSCREEN);
    const scr_h = w.GetSystemMetrics(w.SM.CYSCREEN);
    var r = w.RECT{ .left = 0, .top = 0, .right = dw, .bottom = dh };
    _ = w.AdjustWindowRect(&r, w.WS.CAPTION | w.WS.SYSMENU, w.FALSE);
    const win_w = r.right - r.left;
    const win_h = r.bottom - r.top;

    dlg_state.h = game.h;
    dlg_state.w = game.w;
    var tc = game.type_count;
    var any: u16 = 0;
    for (1..5) |t| any += tc[t];
    if (any == 0) tc = g.splitEvenly(game.mines);
    for (1..5) |t| dlg_state.t[t] = tc[t];

    var mr: w.RECT = undefined;
    _ = w.GetWindowRect(hwnd_main, &mr);
    var px = mr.left + 40;
    var py = mr.top + 60;
    if (px + win_w > scr_w) px = scr_w - win_w - 8;
    if (py + win_h > scr_h) py = scr_h - win_h - 8;

    dialog_hwnd = w.CreateWindowExW(0, w.wstr(CLASS_DLG), w.wstr("自定义雷区"), w.WS.CAPTION | w.WS.SYSMENU | w.WS.POPUP, px, py, win_w, win_h, hwnd_main, null, w.GetModuleHandleW(null), null);
    if (dialog_hwnd == null) return false;

    if (dlg_font == null) dlg_font = w.CreateFontW(-12, 0, 0, 0, 400, 0, 0, 0, 134, 0, 0, 0, 0, w.wstr("Microsoft YaHei UI"));
    const font = dlg_font;
    const hinst = w.GetModuleHandleW(null);

    const label = struct {
        fn make(hp: w.HWND, hi: w.HINSTANCE, x: i32, y: i32, cw: i32, ch: i32, font2: w.HFONT, text: [*:0]const u16) w.HWND {
            const h = w.CreateWindowExW(0, w.wstr("STATIC"), text, w.WS.CHILD | w.WS.VISIBLE, x, y, cw, ch, hp, null, hi, null);
            _ = w.SendMessageW(h, 0x0030, @intFromPtr(font2), w.TRUE); // WM_SETFONT
            return h;
        }
    }.make;

    var y: i32 = 12;
    _ = label(dialog_hwnd, hinst, 12, y + 3, 60, 18, font, w.wstr("高度(H)："));
    edit_handles[0] = w.CreateWindowExW(w.WS.EX_CLIENTEDGE, w.wstr("EDIT"), w.wstr(""), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x2000, 78, y, 70, 22, dialog_hwnd, @ptrFromInt(@as(usize, IDC_EDIT_H)), hinst, null);
    _ = w.SendMessageW(edit_handles[0], 0x0030, @intFromPtr(font), w.TRUE);
    _ = label(dialog_hwnd, hinst, 156, y + 3, 150, 18, font, w.wstr("9 – 30 行"));
    y += 30;
    _ = label(dialog_hwnd, hinst, 12, y + 3, 60, 18, font, w.wstr("宽度(W)："));
    edit_handles[1] = w.CreateWindowExW(w.WS.EX_CLIENTEDGE, w.wstr("EDIT"), w.wstr(""), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x2000, 78, y, 70, 22, dialog_hwnd, @ptrFromInt(@as(usize, IDC_EDIT_W)), hinst, null);
    _ = w.SendMessageW(edit_handles[1], 0x0030, @intFromPtr(font), w.TRUE);
    _ = label(dialog_hwnd, hinst, 156, y + 3, 150, 18, font, w.wstr("9 – 40 列"));
    y += 34;

    const names = [4][*:0]const u16{ w.wstr("正实雷："), w.wstr("负实雷："), w.wstr("正虚雷："), w.wstr("负虚雷：") };
    var k: usize = 0;
    while (k < 4) : (k += 1) {
        const col: i32 = if (k % 2 == 0) 0 else 160;
        const row: i32 = @divTrunc(@as(i32, @intCast(k)), 2);
        const yy = y + row * 30;
        _ = label(dialog_hwnd, hinst, 12 + col, yy + 3, 68, 18, font, names[k]);
        edit_handles[k + 2] = w.CreateWindowExW(w.WS.EX_CLIENTEDGE, w.wstr("EDIT"), w.wstr(""), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x2000, 80 + col, yy, 62, 22, dialog_hwnd, @ptrFromInt(@as(usize, @intCast(IDC_EDIT_T1 + @as(i32, @intCast(k))))), hinst, null);
        _ = w.SendMessageW(edit_handles[k + 2], 0x0030, @intFromPtr(font), w.TRUE);
        setEditInt(edit_handles[k + 2], dlg_state.t[k + 1]);
    }
    y += 66;
    const split_btn = w.CreateWindowExW(0, w.wstr("BUTTON"), w.wstr("按合计均分"), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP, 12, y, 100, 24, dialog_hwnd, @ptrFromInt(@as(usize, IDC_BTN_SPLIT)), hinst, null);
    _ = w.SendMessageW(split_btn, 0x0030, @intFromPtr(font), w.TRUE);
    dlg_err_hwnd = label(dialog_hwnd, hinst, 120, y + 3, 200, 18, font, w.wstr(""));
    y += 34;
    const ok_btn = w.CreateWindowExW(0, w.wstr("BUTTON"), w.wstr("确定"), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP | 0x0001, 122, y, 88, 26, dialog_hwnd, @ptrFromInt(@as(usize, IDC_BTN_OK)), hinst, null);
    _ = w.SendMessageW(ok_btn, 0x0030, @intFromPtr(font), w.TRUE);
    const cancel_btn = w.CreateWindowExW(0, w.wstr("BUTTON"), w.wstr("取消"), w.WS.CHILD | w.WS.VISIBLE | w.WS.TABSTOP, 218, y, 88, 26, dialog_hwnd, @ptrFromInt(@as(usize, IDC_BTN_CANCEL)), hinst, null);
    _ = w.SendMessageW(cancel_btn, 0x0030, @intFromPtr(font), w.TRUE);

    setEditInt(edit_handles[0], dlg_state.h);
    setEditInt(edit_handles[1], dlg_state.w);
    setErrText();
    _ = w.ShowWindow(dialog_hwnd, w.SW.SHOW);
    _ = w.SetFocus(edit_handles[0]);
    return true;
}

fn closeCustomWindow() void {
    if (dialog_hwnd != null) {
        _ = w.DestroyWindow(dialog_hwnd);
        dialog_hwnd = null;
    }
}

fn runCustomDialog() bool {
    if (!createCustomWindow()) return false;
    var msg: w.MSG = undefined;
    while (!dialog_done) {
        const r2 = w.GetMessageW(&msg, null, 0, 0);
        if (r2 <= 0) break;
        _ = w.TranslateMessage(&msg);
        _ = w.DispatchMessageW(&msg);
    }
    closeCustomWindow();
    return !dialog_cancel;
}

// ------------------------------------------------------------------ 最高分纪录
// 三档标准难度各记一个最快通关用时（秒），写在 HKCU\Software\Complexweeper 下，
// 和原版扫雷一样用注册表，所以分发仍然只有一个 exe、不会多出存档文件。
// 自定义棋盘不计入（尺寸/雷数任意，比时间没有意义）。
const REG_PATH = "Software\\Complexweeper";
const SCORE_VALUES = [3][*:0]const u16{ w.wstr("Beginner"), w.wstr("Intermediate"), w.wstr("Expert") };
/// 纪录窗里只出现这三行：难度名 + 用时。棋盘尺寸不写（"游戏"菜单里有），
/// 名字统一两字，等宽字体下三行的用时正好对齐一列。
const SCORE_LABEL = [3][*:0]const u16{
    w.wstr("初级"),
    w.wstr("中级"),
    w.wstr("高级"),
};
/// 下标 0/1/2 = 初级/中级/高级；0 表示还没有纪录
var best_scores = [3]i32{ 0, 0, 0 };
/// 自检里关掉：既不写注册表，也不弹结算窗
var scores_persist = true;
var scores_quiet = false;

/// 当前棋盘是不是标准三档之一；是就返回档位下标，自定义返回 -1
fn presetIndex() i32 {
    for (g.PRESETS, 0..) |p, i| {
        if (game.w == p.w and game.h == p.h and game.mines == p.mines) return @intCast(i);
    }
    return -1;
}

fn loadScores() void {
    var hkey: usize = 0;
    if (w.RegOpenKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, w.KEY_READ, &hkey) != w.ERROR_SUCCESS) return;
    defer _ = w.RegCloseKey(hkey);
    for (0..3) |i| {
        var data: u32 = 0;
        var size: u32 = @sizeOf(u32);
        var kind: u32 = 0;
        if (w.RegQueryValueExW(hkey, SCORE_VALUES[i], null, &kind, @ptrCast(&data), &size) == w.ERROR_SUCCESS) {
            best_scores[i] = @intCast(data);
        }
    }
}

fn saveScores() void {
    if (!scores_persist) return;
    var hkey: usize = 0;
    if (w.RegCreateKeyExW(w.HKEY_CURRENT_USER, w.wstr(REG_PATH), 0, null, w.REG_OPTION_NON_VOLATILE, w.KEY_WRITE, null, &hkey, null) != w.ERROR_SUCCESS) return;
    defer _ = w.RegCloseKey(hkey);
    for (0..3) |i| {
        if (best_scores[i] <= 0) continue;
        const v: u32 = @intCast(best_scores[i]);
        _ = w.RegSetValueExW(hkey, SCORE_VALUES[i], 0, w.REG_DWORD, @ptrCast(&v), @sizeOf(u32));
    }
}

// 运行时拼宽字符串（模板是编译期字面量，数字是运行时值）
fn appendW(buf: []u16, n: *usize, src: [*:0]const u16) void {
    var i: usize = 0;
    while (src[i] != 0 and n.* + 1 < buf.len) : (i += 1) {
        buf[n.*] = src[i];
        n.* += 1;
    }
}
fn appendDigits(buf: []u16, n: *usize, v: i32) void {
    if (v <= 0) {
        appendW(buf, n, w.wstr("———"));
        return;
    }
    var tmp: [12]u16 = undefined;
    var k: usize = 0;
    var x: u32 = @intCast(v);
    while (x > 0) : (x /= 10) {
        tmp[k] = @intCast('0' + x % 10);
        k += 1;
    }
    while (k > 0) {
        k -= 1;
        if (n.* + 1 < buf.len) {
            buf[n.*] = tmp[k];
            n.* += 1;
        }
    }
}
fn appendNL(buf: []u16, n: *usize) void {
    appendW(buf, n, w.wstr("\r\n"));
}

/// 装配「最高分纪录」的正文：只有三档纪录本身（没纪录的档给占位符）。对话框与自检共用这一段。
fn buildScoresText(buf: []u16) usize {
    var n: usize = 0;
    for (0..3) |i| {
        appendW(buf, &n, SCORE_LABEL[i]);
        appendW(buf, &n, w.wstr("      "));
        appendDigits(buf, &n, best_scores[i]);
        if (best_scores[i] > 0) appendW(buf, &n, w.wstr(" 秒"));
        appendNL(buf, &n);
    }
    return n;
}

/// 弹出"最高分纪录"：只有三档的纪录本身，别的都不写。
/// 刚破纪录时标题换成"新纪录！"（`highlight`）。
fn showBestScores(highlight: bool) void {
    var buf: [512]u16 = undefined;
    const n = buildScoresText(&buf);
    buf[n] = 0;
    const title = if (highlight) w.wstr("新纪录！") else w.wstr("最高分纪录");
    _ = w.MessageBoxW(hwnd_main, @ptrCast(&buf), title, w.MB.OK | w.MB.ICONINFORMATION);
}

// ------------------------------------------------------------------ 主窗口
/// 一盘结束后统一处理：停表、冻结用时，胜利且进标准三档时结算纪录
fn afterGameAction(hwnd: w.HWND) void {
    if (!game.over) return;
    _ = w.KillTimer(hwnd, TIMER_ID);
    if (game.t0 != 0) game.elapsed_ms = nowMs() -% game.t0;
    if (!game.win) return;
    const idx = presetIndex();
    if (idx < 0) return;
    const sec: i32 = @max(1, @as(i32, @intCast(game.elapsed_ms / 1000)));
    const u: usize = @intCast(idx);
    if (best_scores[u] != 0 and sec >= best_scores[u]) return; // 没破纪录
    best_scores[u] = sec;
    saveScores();
    if (!scores_quiet) showBestScores(true);
}
fn mainWndProc(hwnd: w.HWND, msg: w.UINT, wp: w.WPARAM, lp: w.LPARAM) callconv(.c) w.LRESULT {
    switch (msg) {
        w.WM.PAINT => {
            var ps: w.PAINTSTRUCT = undefined;
            const dc = w.BeginPaint(hwnd, &ps);
            const L = layout();
            ensureMemDc(hwnd, L);
            paint(mem_dc, L);
            _ = w.BitBlt(dc, 0, 0, L.client_w, L.client_h, mem_dc, 0, 0, w.SRCCOPY);
            _ = w.EndPaint(hwnd, &ps);
            return 0;
        },
        w.WM.ERASEBKGND => return 1,
        // 抓图靠这两条：WM_PRINT 的 HDC 从 wParam 来，客户区自己画、非客户区交回系统；
        // 不接这两条消息的话，PrintWindow 拿到的客户区是空白（无 DWM 合成时尤其明显）。
        w.WM.PRINT => {
            const dc: w.HDC = @ptrFromInt(wp);
            const flags: usize = @bitCast(lp);
            if (dc != null and (flags & 0x04) != 0) paint(dc, layout()); // PRF_CLIENT
            return w.DefWindowProcW(hwnd, msg, wp, lp);                  // 标题栏/菜单由系统画
        },
        w.WM.PRINTCLIENT => {
            const dc: w.HDC = @ptrFromInt(wp);
            if (dc != null) paint(dc, layout());
            return 0;
        },
        w.WM.TIMER => {
            if (wp == TIMER_FLASH) {
                // 「脸扫雷」那段一闪而过：到点就把脸收回普通状态
                _ = w.KillTimer(hwnd, TIMER_FLASH);
                _ = w.InvalidateRect(hwnd, null, 0);
                return 0;
            }
            if (game.started and !game.over) {
                game.elapsed_ms = w.GetTickCount() -% game.t0;
            }
            _ = w.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        w.WM.COMMAND => {
            const id = @as(usize, @intCast(@as(u16, @truncate(wp))));
            handleCommand(hwnd, id);
            return 0;
        },
        w.WM.KEYDOWN => {
            if (wp == 0x72) { // F2
                startNewGame(null);
                return 0;
            }
            return 0;
        },
        // 左键按下（含双击的第二下）：只"压住"不翻开，松手才真翻。
        // 「脸按下」**只属于人脸按钮本身**：按棋盘（翻格/展开/插旗）一律不播它，
        // 那时候该出现的是「脸扫雷」——翻格、插旗、展开成功各闪一下。
        w.WM.LBUTTONDOWN, w.WM.LBUTTONDBLCLK => {
            const L = layout();
            const x = w.loWord(lp);
            const y = w.hiWord(lp);
            const on_face = inFace(L, x, y);
            l_down = true;
            face_armed = on_face;
            face_down = on_face;
            _ = w.SetCapture(hwnd);
            const c = cellAt(L, x, y);
            if (r_down) {
                // 右键已经按着 → 这是"左右键同时点击"，进入展开预览（松手才真展开）
                chord_cell = c;
                press_cell = -1;
            } else {
                // 传统扫雷：按下不翻开，只把那一格"压住"（画成已翻开的空白），松手才真翻。
                // 拖到别的格子上，按住的格子跟着走；拖出棋盘就取消。
                press_cell = if (c >= 0 and !on_face and !game.over and game.open[@intCast(c)] == 0) c else -1;
            }
            _ = w.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        w.WM.MOUSEMOVE => {
            const L = layout();
            const c = cellAt(L, w.loWord(lp), w.hiWord(lp));
            // 展开预览跟着鼠标走（拖出棋盘就取消）
            if (chord_cell >= 0) {
                const next: i32 = if (c >= 0) c else -1;
                if (next != chord_cell) {
                    chord_cell = next;
                    _ = w.InvalidateRect(hwnd, null, 0);
                }
                return 0;
            }
            if (press_cell < 0) return 0;
            const next: i32 = if (c >= 0 and game.open[@intCast(c)] == 0) c else -1;
            if (next != press_cell) {
                press_cell = next;
                _ = w.InvalidateRect(hwnd, null, 0);
            }
            return 0;
        },
        w.WM.LBUTTONUP => {
            const L = layout();
            const x = w.loWord(lp);
            const y = w.hiWord(lp);
            // 先把这次按下的状态读进局部量：ReleaseCapture() 会**同步**发 WM_CAPTURECHANGED，
            // 而那条消息会把 press_cell / face_armed 清掉（踩过一次：先 ReleaseCapture 再判断，
            // 结果人脸永远重开不了）。
            const held = press_cell;
            const chord = chord_cell;
            const was_face = face_armed;
            l_down = false;
            press_cell = -1;
            chord_cell = -1;
            face_down = false; // 按下脸到此结束——和"正式翻开/展开"同一时刻
            face_armed = false;
            _ = w.ReleaseCapture();
            // 人脸按钮：按下与松开都必须在脸上才算重开（从棋盘拖到脸上松手不算）
            if (was_face and inFace(L, x, y)) {
                _ = w.KillTimer(hwnd, TIMER_ID);
                startNewGame(null);
                return 0;
            }
            // 左右键同时点击：在按住的那一格上松手才真展开
            if (chord >= 0) {
                if (cellAt(L, x, y) == chord) doExpand(hwnd, @intCast(chord));
                _ = w.InvalidateRect(hwnd, null, 0);
                return 0;
            }
            // 只在"按住的那一格"上松手才生效；插了旗的格子左键打不开（传统扫雷：旗子保护它，
            // 要翻开得先用右键把旗循环回"空"）
            if (held >= 0 and cellAt(L, x, y) == held and !game.over and game.flag[@intCast(held)] == 0) {
                const c: usize = @intCast(held);
                const covered = game.open[c] == 0;
                if (!game.started) {
                    game.startAt(c, nowMs());
                    game.setMsg(.started);
                    _ = w.SetTimer(hwnd, TIMER_ID, 250, null);
                } else {
                    game.reveal(c, nowMs());
                    afterGameAction(hwnd);
                }
                // 真翻开了（或开局连片了）就让脸闪一下；局面已结束时不闪（那时是胜利/死亡脸）
                if (covered and !game.over) flashFace(hwnd);
            }
            _ = w.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        w.WM.RBUTTONDOWN, w.WM.RBUTTONDBLCLK => {
            // 连点两下时，第二下收到的是 DBLCLK 而不是 DOWN —— 不一起处理的话
            // 快速连点会丢一次按键（实测：连点两下只走一步）。开局前也允许插旗
            // （传统扫雷就是这样，旗帜会保留到开局之后）。
            r_down = true;
            const L = layout();
            const c = cellAt(L, w.loWord(lp), w.hiWord(lp));
            if (l_down) {
                // 左键已经按着 → 这是"左右键同时点击"，进入展开预览（松手才真展开）
                chord_cell = c;
                press_cell = -1;
                _ = w.InvalidateRect(hwnd, null, 0);
                return 0;
            }
            if (c >= 0 and !game.over and game.open[@intCast(c)] == 0) {
                if (game.cycleFlag(@intCast(c))) {
                    flashFace(hwnd); // 插旗也算"动手扫雷"，脸闪一下
                    _ = w.InvalidateRect(hwnd, null, 0);
                }
            }
            return 0;
        },
        w.WM.RBUTTONUP => {
            r_down = false;
            // 左右键同时点击：先松右键也算数（传统扫雷是"先松哪个都展开"）
            const chord = chord_cell;
            if (chord >= 0) {
                const L = layout();
                chord_cell = -1;
                press_cell = -1;
                face_down = false;
                if (cellAt(L, w.loWord(lp), w.hiWord(lp)) == chord) doExpand(hwnd, @intCast(chord));
                _ = w.ReleaseCapture();
                _ = w.InvalidateRect(hwnd, null, 0);
            }
            return 0;
        },
        // 中键：按住时先预览周围即将展开的格子，松手才真展开（不再是按下就展开）。
        // 按住期间人脸播「脸扫雷」（跟按住左键准备翻开一样）。
        w.WM.MBUTTONDOWN, w.WM.MBUTTONDBLCLK => {
            const L = layout();
            const c = cellAt(L, w.loWord(lp), w.hiWord(lp));
            m_down = true;
            chord_cell = c;
            press_cell = -1;
            _ = w.SetCapture(hwnd);
            _ = w.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        w.WM.MBUTTONUP => {
            const L = layout();
            const chord = chord_cell;
            m_down = false;
            chord_cell = -1;
            face_down = false;
            _ = w.ReleaseCapture();
            if (chord >= 0 and cellAt(L, w.loWord(lp), w.hiWord(lp)) == chord) doExpand(hwnd, @intCast(chord));
            _ = w.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        w.WM.CAPTURECHANGED => {
            if (face_down or face_armed or press_cell >= 0 or chord_cell >= 0 or l_down or r_down or m_down) {
                face_down = false;
                face_armed = false;
                press_cell = -1;
                chord_cell = -1;
                l_down = false;
                r_down = false;
                m_down = false;
                _ = w.InvalidateRect(hwnd, null, 0);
            }
            return 0;
        },
        w.WM.CLOSE => {
            _ = w.DestroyWindow(hwnd);
            return 0;
        },
        w.WM.DESTROY => {
            _ = w.KillTimer(hwnd, TIMER_ID);
            if (mem_dc != null) {
                _ = w.DeleteObject(mem_bmp);
                _ = w.DeleteDC(mem_dc);
                mem_dc = null;
            }
            w.PostQuitMessage(0);
            return 0;
        },
        else => return w.DefWindowProcW(hwnd, msg, wp, lp),
    }
}

/// 自定义对话框点「确定」之后的收尾：菜单与自检走同一条路（顺手把窗口尺寸与局面重排）
fn applyCustomFromDialog() void {
    resizeWindowForBoard();
    startNewGame(null);
}

fn handleCommand(hwnd: w.HWND, id: usize) void {
    switch (id) {
        IDM_NEW => startNewGame(null),
        IDM_BEGINNER => setPreset(0),
        IDM_INTERMEDIATE => setPreset(1),
        IDM_EXPERT => setPreset(2),
        IDM_CUSTOM => {
            if (runCustomDialog()) applyCustomFromDialog();
        },
        IDM_BEST => showBestScores(false),
        IDM_EXIT => _ = w.DestroyWindow(hwnd),
        IDM_ZOOM1, IDM_ZOOM2, IDM_ZOOM3 => {
            zoom = switch (id) {
                IDM_ZOOM1 => 1,
                IDM_ZOOM2 => 2,
                else => 3,
            };
            mem_w = 0; // 强制重建后备位图
            resizeWindowForBoard();
            _ = w.InvalidateRect(hwnd, null, 0);
        },
        IDM_HELP_HOW => showHelp(),
        IDM_HELP_ABOUT => showAbout(),
        else => {},
    }
}

/// 「关于」按"克隆作品"的经典署名格式排：产品名（中文名 + 英文名）与版本 → 基于什么
/// （附原版作者）→ 素材与代码的归属 → 授权状态 → 与微软无隶属关系。
/// 第一行直接由 APP_TITLE 拼出来，所以这里的英文名永远和窗口标题一致。
/// 用 MessageBoxIndirect 而不是 MessageBox：只有前者能把**程序自己的图标**放进弹窗
/// （MessageBox 的 dwStyle 只能挑那几个系统预设图标）。
const ABOUT_TEXT = APP_TITLE ++ " " ++ APP_VERSION ++ "\r\n" ++
    "基于 Microsoft® 扫雷(原版作者：Robert Donner、Curt Johnson)\r\n" ++
    "\r\n" ++
    "图像素材来源：Microsoft(扫雷原始图像素材)；青月晓(新增图像素材)。\r\n" ++
    "Copyright © 2026 青月晓\r\n" ++
    "本程序为免费软件\r\n" ++
    "与 Microsoft 公司无隶属关系";

fn showAbout() void {
    const hinst = w.GetModuleHandleW(null);
    if (w.LoadIconW(hinst, w.resId(ICON_RES_ID)) == null) {
        // 中间产物（build\cs.exe）还没注入 .rsrc：退回系统信息图标，弹窗本身照常
        _ = w.MessageBoxW(hwnd_main, w.wstr(ABOUT_TEXT), w.wstr("关于复扫雷"), w.MB.OK | w.MB.ICONINFORMATION);
        return;
    }
    var mp: w.MSGBOXPARAMS = std.mem.zeroes(w.MSGBOXPARAMS);
    mp.cbSize = @sizeOf(w.MSGBOXPARAMS);
    mp.hwndOwner = hwnd_main;
    mp.hInstance = hinst;
    mp.lpszText = w.wstr(ABOUT_TEXT);
    mp.lpszCaption = w.wstr("关于复扫雷");
    mp.dwStyle = w.MB.OK | w.MB.USERICON; // USERICON 这一位才是"用 lpszIcon 那个图标"
    mp.lpszIcon = w.resId(ICON_RES_ID);
    _ = w.MessageBoxIndirectW(&mp);
}

/// 「玩法与操作」正文：三小段——四种雷的名字 + 五行操作 + 数字含义 + 展开条件。
/// 规矩：雷说雷的名字（正实雷…），旗说旗的名字（正实旗…），**不写 `+1/−1/+i/−i` 那套符号**。
const HELP_TEXT = "雷区里有四种雷，分别是正实雷、负实雷、正虚雷、负虚雷。\r\n" ++
    "左键翻开格子。\r\n" ++
    "右键插旗，旗帜顺序为正实旗、负实旗、正虚旗、负虚旗。\r\n" ++
    "中键或左右键同时点击展开格子。\r\n" ++
    "F2开局。\r\n" ++
    "\r\n" ++
    "数字代表该格周围所有雷的加和之模长，均为整数或最简根式。\r\n" ++
    "\r\n" ++
    "当旗帜数量等于周围真实雷数，且实虚比例符合真实比例或其倒数，则可以展开。";

fn showHelp() void {
    _ = w.MessageBoxW(hwnd_main, w.wstr(HELP_TEXT), w.wstr("玩法与操作"), w.MB.OK | w.MB.ICONINFORMATION);
}

fn buildMenu() w.HMENU {
    const bar = w.CreateMenu();
    const game_menu = w.CreatePopupMenu();
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_NEW, w.wstr("开局(&N)\tF2"));
    _ = w.AppendMenuW(game_menu, w.MF.SEPARATOR, 0, null);
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_BEGINNER, w.wstr("初级(&B)\t9×9 · 10 雷"));
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_INTERMEDIATE, w.wstr("中级(&I)\t16×16 · 40 雷"));
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_EXPERT, w.wstr("高级(&E)\t30×16 · 99 雷"));
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_CUSTOM, w.wstr("自定义(&C)…"));
    _ = w.AppendMenuW(game_menu, w.MF.SEPARATOR, 0, null);
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_BEST, w.wstr("最高分纪录(&R)…"));
    _ = w.AppendMenuW(game_menu, w.MF.SEPARATOR, 0, null);
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_ZOOM1, w.wstr("缩放 100%"));
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_ZOOM2, w.wstr("缩放 200%"));
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_ZOOM3, w.wstr("缩放 300%"));
    _ = w.AppendMenuW(game_menu, w.MF.SEPARATOR, 0, null);
    _ = w.AppendMenuW(game_menu, w.MF.STRING, IDM_EXIT, w.wstr("退出(&X)"));
    _ = w.AppendMenuW(bar, w.MF.POPUP, @intFromPtr(game_menu), w.wstr("游戏(&G)"));

    const help_menu = w.CreatePopupMenu();
    _ = w.AppendMenuW(help_menu, w.MF.STRING, IDM_HELP_HOW, w.wstr("玩法与操作(&H)"));
    _ = w.AppendMenuW(help_menu, w.MF.SEPARATOR, 0, null);
    _ = w.AppendMenuW(help_menu, w.MF.STRING, IDM_HELP_ABOUT, w.wstr("关于复扫雷(&A)…"));
    _ = w.AppendMenuW(bar, w.MF.POPUP, @intFromPtr(help_menu), w.wstr("帮助(&H)"));
    return bar;
}

/// 菜单里不再画「当前难度」的项目符号：原版用圆点，但我们的选中态没跟着难度切换更新，
/// 留着反而像 bug。菜单保持干净，难度看标题栏。
fn checkMenu() void {
    if (hwnd_main == null) return;
}

// ------------------------------------------------------------------ 图集
/// exe 里 .rsrc 图标资源的 ID（tools/set_icon.js 写的 RT_GROUP_ICON，里面是 16/32/48 三档）
const ICON_RES_ID: usize = 1;

/// 程序图标 = 素材/图标.png。优先直接用 exe 里注入的那份资源（尺寸齐全、alpha 原样），
/// 拿不到时（例如还没注入 .rsrc 的中间产物 build\cs.exe）才用图集里那张 32×32 现场造一个。
fn makeIcon() w.HICON {
    const hinst = w.GetModuleHandleW(null);
    const from_res = w.LoadIconW(hinst, w.resId(ICON_RES_ID));
    if (from_res != null) return from_res;
    return makeIconFromSprite();
}

/// 从图集里的 icon 贴图造 HICON：32×32 原样拷贝像素（不缩放、不丢 alpha）。
/// 注意不能用 StretchBlt——那会把透明像素当成黑色画上去（图标里 404 个像素是全透明的）。
fn makeIconFromSprite() w.HICON {
    const ic = A.rect(A.icon);
    if (ic.w != 32 or ic.h != 32) return null;
    const dc = w.GetDC(null);
    defer _ = w.ReleaseDC(null, dc);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = 32;
    bi.bmiHeader.biHeight = -32; // 自顶向下，和图集一致
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var cbits: ?*anyopaque = null;
    const color = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &cbits, null, 0);
    var mbits: ?*anyopaque = null;
    const mask = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &mbits, null, 0);
    if (color == null or mask == null or cbits == null or mbits == null) return null;
    const dst: [*]u8 = @ptrCast(cbits.?);
    @memset(dst[0 .. 32 * 32 * 4], 0);
    @memset(@as([*]u8, @ptrCast(mbits.?))[0 .. 32 * 32 * 4], 0);
    // 图集一定已经加载（loadAtlas 在 makeIcon 之前，失败就直接退出了）
    var y: u32 = 0;
    while (y < 32) : (y += 1) {
        const srow = (@as(usize, ic.y + y) * A.atlas_w + ic.x) * 4;
        @memcpy(dst[@as(usize, y) * 32 * 4 ..][0 .. 32 * 4], atlas_pixels[srow..][0 .. 32 * 4]);
    }
    var ii = w.ICONINFO{ .fIcon = w.TRUE, .xHotspot = 0, .yHotspot = 0, .hbmMask = mask, .hbmColor = color };
    return w.CreateIconIndirect(&ii);
}

fn loadAtlas() bool {
    const blob = A.blob;
    if (blob.len < 12) return false;
    if (!(blob[0] == 'C' and blob[1] == 'S' and blob[2] == 'A' and blob[3] == 'T')) return false;
    const bmp_w: i32 = A.atlas_w;
    const bmp_h: i32 = A.atlas_h;
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = bmp_w;
    bi.bmiHeader.biHeight = -bmp_h; // 自顶向下
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const scr = w.GetDC(null);
    atlas_bmp = w.CreateDIBSection(scr, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, scr);
    if (atlas_bmp == null or bits == null) return false;
    atlas_pixels = @ptrCast(bits.?);
    const pix_off: usize = 12 + @as(usize, A.count) * 8;
    const need: usize = @as(usize, @intCast(bmp_w)) * @as(usize, @intCast(bmp_h)) * 4;
    if (blob.len < pix_off + need) return false;
    @memcpy(atlas_pixels[0..need], blob[pix_off .. pix_off + need]);
    atlas_dc = w.CreateCompatibleDC(null);
    atlas_old = w.SelectObject(atlas_dc, atlas_bmp);
    return true;
}

// ------------------------------------------------------------------ 截图 / 自检
fn saveBmp(path: []const u8, pixels: [*]u8, cw: i32, ch: i32) bool {
    const row_bytes: usize = @as(usize, @intCast(cw)) * 4;
    const img_size = row_bytes * @as(usize, @intCast(ch));
    const file_size = 14 + 40 + img_size;
    const f = std.fs.cwd().createFile(path, .{}) catch return false;
    defer f.close();
    var hdr: [54]u8 = [_]u8{0} ** 54;
    hdr[0] = 'B';
    hdr[1] = 'M';
    std.mem.writeInt(u32, hdr[2..6], @intCast(file_size), .little);
    std.mem.writeInt(u32, hdr[10..14], 54, .little);
    std.mem.writeInt(u32, hdr[14..18], 40, .little);
    std.mem.writeInt(i32, hdr[18..22], cw, .little);
    std.mem.writeInt(i32, hdr[22..26], ch, .little);
    std.mem.writeInt(u16, hdr[26..28], 1, .little);
    std.mem.writeInt(u16, hdr[28..30], 32, .little);
    std.mem.writeInt(u32, hdr[34..38], @intCast(img_size), .little);
    f.writeAll(&hdr) catch return false;
    // 从 DIB 里取像素，按 BMP 要求自底向上写
    var row: [4096 * 4]u8 = undefined;
    var y: i32 = ch - 1;
    while (y >= 0) : (y -= 1) {
        const n: usize = @intCast(cw * 4);
        const src = pixels + @as(usize, @intCast(y)) * @as(usize, @intCast(cw * 4));
        @memcpy(row[0..n], src[0..n]);
        f.writeAll(row[0..n]) catch return false;
    }
    return true;
}


// ------------------------------------------------------------------ 入口
var shot_path_buf: [260]u8 = undefined;
var shot_path_len: usize = 0;
var selftest_path_buf: [260]u8 = undefined;
var selftest_path_len: usize = 0;

fn copyPath(dst: []u8, src: []const u8) usize {
    const n = @min(src.len, dst.len);
    @memcpy(dst[0..n], src[0..n]);
    return n;
}

fn shotPath() ?[]const u8 {
    if (shot_path_len == 0) return null;
    return shot_path_buf[0..shot_path_len];
}
fn selftestPath() ?[]const u8 {
    if (selftest_path_len == 0) return null;
    return selftest_path_buf[0..selftest_path_len];
}
var uitest_path_buf: [260]u8 = undefined;
var uitest_path_len: usize = 0;
fn uitestPath() ?[]const u8 {
    if (uitest_path_len == 0) return null;
    return uitest_path_buf[0..uitest_path_len];
}
var dump_path_buf: [260]u8 = undefined;
var dump_path_len: usize = 0;
fn dumpPath() ?[]const u8 {
    if (dump_path_len == 0) return null;
    return dump_path_buf[0..dump_path_len];
}

/// 把当前局面写成文本，用于核对计数器数值等方法：--dump out.txt

fn parseArgs() void {
    var it = std.process.argsWithAllocator(std.heap.page_allocator) catch return;
    defer it.deinit();
    var expect: enum { none, shot, selftest, dump, uitest } = .none;
    _ = &window_shot;
    while (it.next()) |arg| {
        switch (expect) {
            .shot => {
                shot_path_len = copyPath(&shot_path_buf, arg);
                expect = .none;
                continue;
            },
            .selftest => {
                selftest_path_len = copyPath(&selftest_path_buf, arg);
                expect = .none;
                continue;
            },
            .dump => {
                dump_path_len = copyPath(&dump_path_buf, arg);
                expect = .none;
                continue;
            },
            .uitest => {
                uitest_path_len = copyPath(&uitest_path_buf, arg);
                expect = .none;
                continue;
            },
            .none => {},
        }
        if (std.mem.eql(u8, arg, "--shot")) expect = .shot;
        if (std.mem.eql(u8, arg, "--selftest")) expect = .selftest;
        if (std.mem.eql(u8, arg, "--dump")) expect = .dump;
        if (std.mem.eql(u8, arg, "--uitest")) expect = .uitest;
        if (std.mem.eql(u8, arg, "--demo")) demo_mode = .mid;
        if (std.mem.eql(u8, arg, "--demo-lose")) demo_mode = .lose;
        if (std.mem.eql(u8, arg, "--demo-win")) demo_mode = .win;
        if (std.mem.eql(u8, arg, "--custom")) demo_mode = .custom;
        if (std.mem.eql(u8, arg, "--zoom1")) zoom = 1;
        if (std.mem.eql(u8, arg, "--zoom2")) zoom = 2;
        if (std.mem.eql(u8, arg, "--zoom3")) zoom = 3;
        // 这两个开关既能写成 `--shot 路径 --sheet`，也能写成 `--sheet 路径`。
        // 所以只有在还没拿到输出路径时才去"期待下一个参数是路径"——否则会把后面的
        // `--quiet` 之类的开关当成文件名（踩过：渲染出的图被存成了名为 `--quiet` 的文件）。
        if (std.mem.eql(u8, arg, "--shot-window")) {
            window_shot = true;
            if (shot_path_len == 0) expect = .shot;
        }
        if (std.mem.eql(u8, arg, "--sheet")) {
            sheet_mode = true;
            if (shot_path_len == 0) expect = .shot;
        }
        if (std.mem.eql(u8, arg, "--quiet")) scores_quiet = true;
    }
}

var window_shot = false;
var sheet_mode = false;

const DemoMode = enum { none, mid, lose, win, custom };
var demo_mode: DemoMode = .none;

/// 造一个可复现的局面用于截图核对
fn setupDemo() void {
    switch (demo_mode) {
        .none => return,
        .custom => {
            game.w = 12;
            game.h = 12;
            game.mines = 14;
            game.type_count = .{ 0, 0, 7, 0, 7 };

            game.newGame(20260101);
            game.startAt(6 * 12 + 6, 0);
            game.setMsg(.started);
            game.elapsed_ms = 42_000;
            return;
        },
        else => {},
    }
    game.w = 16;
    game.h = 16;
    game.mines = 40;

    game.newGame(20260101);
    game.startAt(8 * 16 + 8, 0);
    game.setMsg(.started);
    game.elapsed_ms = 83_000;

    if (demo_mode == .mid) {
        var i: usize = 0;
        var opened: u32 = 0;
        while (i < game.n and opened < 14) : (i += 1) {
            if (game.mine[i] != 0 or game.open[i] != 0) continue;
            game.reveal(i, 0);
            opened += 1;
        }
        var flagged: u32 = 0;
        i = 0;
        while (i < game.n and flagged < 6) : (i += 1) {
            if (game.open[i] != 0) continue;
            _ = game.setFlag(i, @intCast(1 + (flagged % 4)));
            flagged += 1;
        }
    } else if (demo_mode == .win) {
        for (0..game.n) |i| {
            if (game.mine[i] == 0 and game.open[i] == 0) game.reveal(i, 0);
        }
        // 走真实的结算路径：冻结用时 + 结算最高分纪录
        afterGameAction(hwnd_main);
    } else if (demo_mode == .lose) {
        var i: usize = 0;
        var flagged: u32 = 0;
        while (i < game.n and flagged < 4) : (i += 1) {
            if (game.open[i] != 0 or game.mine[i] != 0) continue;
            _ = game.setFlag(i, @intCast(1 + (flagged % 4)));
            flagged += 1;
        }
        i = 0;
        while (i < game.n) : (i += 1) {
            if (game.mine[i] == 2) {
                game.reveal(i, 0);
                break;
            }
        }
    }
}

pub fn main() void {
    parseArgs();
    if (selftestPath()) |p| {
        const code = runSelftest(p);
        w.ExitProcess(@intCast(code));
    }
    _ = w.SetProcessDPIAware();
    if (!loadAtlas()) {
        _ = w.MessageBoxW(null, w.wstr("内置图集损坏，无法启动。"), w.wstr("错误"), w.MB.OK);
        return;
    }
    game.w = g.PRESETS[2].w;
    game.h = g.PRESETS[2].h;
    game.mines = g.PRESETS[2].mines;

    game.newGame(1);

    const hinst = w.GetModuleHandleW(null);
    var wc: w.WNDCLASSEXW = std.mem.zeroes(w.WNDCLASSEXW);
    wc.cbSize = @sizeOf(w.WNDCLASSEXW);
    wc.style = w.WNDCLASS_STYLES.CS_DBLCLKS;
    wc.lpfnWndProc = mainWndProc;
    wc.hInstance = hinst;
    wc.hCursor = w.LoadCursorW(null, @ptrFromInt(w.IDC.ARROW));
    wc.hbrBackground = null;
    wc.hIcon = makeIcon();
    // 小图标单独按 16×16 取：图标资源里有 16 这一档，直接取比让系统缩 32 的清楚
    const icon16 = w.LoadImageW(hinst, w.resId(ICON_RES_ID), w.IMAGE_ICON, 16, 16, w.LR_DEFAULTCOLOR);
    wc.hIconSm = if (icon16 != null) @ptrCast(icon16) else wc.hIcon;
    wc.lpszClassName = w.wstr(CLASS_MAIN);
    _ = w.RegisterClassExW(&wc);

    const L = layout();
    var r = w.RECT{ .left = 0, .top = 0, .right = L.client_w, .bottom = L.client_h };
    const style: w.DWORD = w.WS.OVERLAPPED | w.WS.CAPTION | w.WS.SYSMENU | w.WS.MINIMIZEBOX;
    _ = w.AdjustWindowRect(&r, style, w.TRUE);
    hwnd_main = w.CreateWindowExW(0, w.wstr(CLASS_MAIN), w.wstr(APP_TITLE), style, 80, 60, r.right - r.left, r.bottom - r.top, null, buildMenu(), hinst, null);
    if (hwnd_main == null) return;
    loadScores();
    checkMenu();

    if (uitestPath()) |p| {
        const code = runUiTest(p);
        w.ExitProcess(@intCast(code));
    }
    if (shotPath()) |p| {
        setupDemo();
        if (dumpPath()) |dp| dumpState(dp);
        resizeWindowForBoard();
        if (sheet_mode) {
            renderSheet(p);
        } else if (window_shot) captureWindow(p) else renderToFile(p);
        return;
    }

    _ = w.ShowWindow(hwnd_main, w.SW.SHOW);
    _ = w.UpdateWindow(hwnd_main);
    var msg: w.MSG = undefined;
    while (w.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = w.TranslateMessage(&msg);
        _ = w.DispatchMessageW(&msg);
    }
}

/// 抓整窗（含标题栏、菜单栏），用 PrintWindow，不需要窗口可见/前台
fn captureWindow(path: []const u8) void {
    _ = w.ShowWindow(hwnd_main, 8); // SW_SHOWNA：显示但不激活，否则 PrintWindow 抓到全黑
    _ = w.UpdateWindow(hwnd_main);
    var r: w.RECT = undefined;
    _ = w.GetWindowRect(hwnd_main, &r);
    const cw = r.right - r.left;
    const ch = r.bottom - r.top;
    const dc = w.GetDC(null);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = cw;
    bi.bmiHeader.biHeight = -ch;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const bmp = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, dc);
    if (bmp == null or bits == null) return;
    const odc = w.CreateCompatibleDC(null);
    _ = w.SelectObject(odc, bmp);
    // flag=0：走 WM_PRINT/WM_PRINTCLIENT 这条老路，任何会话里都稳（flag=2 要 DWM 合成）
    _ = w.PrintWindow(hwnd_main, odc, 0);
    _ = saveBmp(path, @ptrCast(bits.?), cw, ch);
}

/// 素材对照表：把 24 个显示值贴图 + 旗帜/雷/踩中/标错 + LED + 人脸 全画出来核对映射。
/// 用 --sheet 输出，配合 bmp2png.js 看。
fn renderSheet(path: []const u8) void {
    const z: i32 = 3;
    const cellw = 16 * z + 6;
    const cellh = 16 * z + 22;
    const w0: i32 = 24 * cellw + 20;
    // 五行的高度全部按实际绘制位置算：早先这里写死了一个偏小的常量，
    // 结果第 4 行（LED）被裁掉一截、第 5 行（人脸）整行都画在画布外面。
    const y0: i32 = 6; // 数字行
    const y1: i32 = y0 + cellh; // 未翻开/旗/雷
    const y2: i32 = y1 + cellh; // 踩中/标错
    const y3: i32 = y2 + cellh; // LED
    const y4: i32 = y3 + 24 * z + 8; // 人脸
    const h0: i32 = y4 + 24 * z + 12;
    const dcs = w.GetDC(null);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w0;
    bi.bmiHeader.biHeight = -h0;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const bmp = w.CreateDIBSection(dcs, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, dcs);
    if (bmp == null or bits == null) return;
    const dc = w.CreateCompatibleDC(null);
    _ = w.SelectObject(dc, bmp);
    _ = w.SetStretchBltMode(dc, 3);
    fill(dc, 0, 0, w0, h0, C_BTNFACE);
    const font = w.GetStockObject(17);
    _ = w.SelectObject(dc, font);
    _ = w.SetBkMode(dc, w.TRANSPARENT);
    _ = w.SetTextColor(dc, C_BLACK);

    // 第一行：24 个显示值（按 D 升序），下方标 D 与文本
    var x: i32 = 10;
    for (g.ACHIEVABLE) |D| {
        const spr = A.num_by_D[D];
        blitSpriteSq(dc, spr, x, y0, 16 * z);
        var buf: [64]u16 = undefined;
        var txt: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&txt, "D={d}", .{D}) catch "?";
        _ = w.SetWindowTextW; // 不用窗口，直接 DrawTextW
        const ws = w.asciiToW(&buf, s);
        var r = w.RECT{ .left = x - 4, .top = y0 + 16 * z + 2, .right = x + 16 * z + 4, .bottom = y0 + 16 * z + 18 };
        _ = w.DrawTextW(dc, ws.ptr, -1, &r, w.DT.CENTER | w.DT.SINGLELINE);
        x += cellw;
    }

    // 第二行：未翻开 / 空白 / 四种旗 / 四种雷
    var x2: i32 = 10;
    const row2 = [_]struct { s: u16, label: []const u8 }{
        .{ .s = A.closed, .label = "closed" },
        .{ .s = A.blank, .label = "blank" },
        .{ .s = A.flag_1, .label = "+1" },
        .{ .s = A.flag_2, .label = "-1" },
        .{ .s = A.flag_3, .label = "+i" },
        .{ .s = A.flag_4, .label = "-i" },
        .{ .s = A.mine_1, .label = "m+1" },
        .{ .s = A.mine_2, .label = "m-1" },
        .{ .s = A.mine_3, .label = "m+i" },
        .{ .s = A.mine_4, .label = "m-i" },
    };
    for (row2) |it| {
        blitSpriteSq(dc, it.s, x2, y1, 16 * z);
        var buf: [32]u16 = undefined;
        const ws = w.asciiToW(&buf, it.label);
        var r = w.RECT{ .left = x2 - 4, .top = y1 + 16 * z + 2, .right = x2 + 16 * z + 4, .bottom = y1 + 16 * z + 18 };
        _ = w.DrawTextW(dc, ws.ptr, -1, &r, w.DT.CENTER | w.DT.SINGLELINE);
        x2 += cellw;
    }

    // 第三行：四种踩中 + 四种标错
    var x3: i32 = 10;
    const row3 = [_]struct { s: u16, label: []const u8 }{
        .{ .s = A.boom_1, .label = "boom+1" },
        .{ .s = A.boom_2, .label = "boom-1" },
        .{ .s = A.boom_3, .label = "boom+i" },
        .{ .s = A.boom_4, .label = "boom-i" },
        .{ .s = A.wrong_1, .label = "wrong+1" },
        .{ .s = A.wrong_2, .label = "wrong-1" },
        .{ .s = A.wrong_3, .label = "wrong+i" },
        .{ .s = A.wrong_4, .label = "wrong-i" },
    };
    for (row3) |it| {
        blitSpriteSq(dc, it.s, x3, y2, 16 * z);
        var buf: [32]u16 = undefined;
        const ws = w.asciiToW(&buf, it.label);
        var r = w.RECT{ .left = x3 - 4, .top = y2 + 16 * z + 2, .right = x3 + 16 * z + 4, .bottom = y2 + 16 * z + 18 };
        _ = w.DrawTextW(dc, ws.ptr, -1, &r, w.DT.CENTER | w.DT.SINGLELINE);
        x3 += cellw;
    }

    // 第四行：LED 0-9 / 空 / 负
    var x4: i32 = 10;
    var d: u16 = 0;
    while (d <= 9) : (d += 1) {
        blitSprite(dc, digitSprite(@intCast('0' + d)), x4, y3, 13 * z, 23 * z);
        x4 += 13 * z + 4;
    }
    blitSprite(dc, A.led_blank, x4, y3, 13 * z, 23 * z);
    x4 += 13 * z + 4;
    blitSprite(dc, A.led_minus, x4, y3, 13 * z, 23 * z);
    x4 += 13 * z + 4;
    blitSprite(dc, A.led_i, x4, y3, 13 * z, 23 * z);

    // 第五行：人脸
    var x5: i32 = 10;
    for ([_]u16{ A.face_normal, A.face_down, A.face_scan, A.face_dead, A.face_win }) |f| {
        blitSpriteSq(dc, f, x5, y4, 24 * z);
        x5 += 24 * z + 8;
    }
    // 顺手画四块真实的 LED 面板（实雷四格数字、虚雷三格数字 + 一格 i），验证对齐与那一格 i
    const sx = x5 + 20;
    const sw = 4 * 13 * z + 10;
    const sy = y4;
    // 正实雷：0083
    _ = drawLed(dc, sx, sy, 83, 4, z);
    // 负实雷：−014（负号占一格，仍是四格）
    _ = drawLed(dc, sx + sw, sy, -14, 4, z);
    // 正虚雷：007 + i
    var vx = sx + 2 * sw;
    _ = drawLed(dc, vx, sy, 7, 3, z);
    blitSprite(dc, A.led_i, vx + 3 * 13 * z, sy, 13 * z, 23 * z);
    // 负虚雷：−07 + i
    vx = sx + 3 * sw;
    _ = drawLed(dc, vx, sy, -7, 3, z);
    blitSprite(dc, A.led_i, vx + 3 * 13 * z, sy, 13 * z, 23 * z);

    _ = saveBmp(path, @ptrCast(bits.?), w0, h0);
    _ = w.DeleteObject(bmp);
    _ = w.DeleteDC(dc);
}

fn renderToFile(path: []const u8) void {
    const L = layout();
    const dc = w.GetDC(null);
    var bi: w.BITMAPINFO = std.mem.zeroes(w.BITMAPINFO);
    bi.bmiHeader.biSize = @sizeOf(w.BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = L.client_w;
    bi.bmiHeader.biHeight = -L.client_h;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = w.BI_RGB;
    var bits: ?*anyopaque = null;
    const bmp = w.CreateDIBSection(dc, &bi, w.DIB_RGB_COLORS, &bits, null, 0);
    _ = w.ReleaseDC(null, dc);
    if (bmp == null or bits == null) return;
    const odc = w.CreateCompatibleDC(null);
    _ = w.SelectObject(odc, bmp);
    _ = w.SetStretchBltMode(odc, 3);
    paint(odc, L);
    _ = saveBmp(path, @ptrCast(bits.?), L.client_w, L.client_h);
}

fn dumpState(path: []const u8) void {
    const f = std.fs.cwd().createFile(path, .{}) catch return;
    defer f.close();
    var buf: [1024]u8 = undefined;
    var s = std.ArrayList(u8).init(std.heap.page_allocator);
    _ = &buf;
    s.writer().print("棋盘 {d}×{d} · 雷 {d} · 已翻开 {d} · 开局格 {d}\n", .{ game.w, game.h, game.mines, game.openedCount(), game.start_cell }) catch {};
    s.writer().print("type_total  = {d} {d} {d} {d}\n", .{ game.type_total[1], game.type_total[2], game.type_total[3], game.type_total[4] }) catch {};
    s.writer().print("flags_of    = {d} {d} {d} {d}\n", .{ game.flags_of[1], game.flags_of[2], game.flags_of[3], game.flags_of[4] }) catch {};
    s.writer().print("unmarked    = {d} {d} {d} {d}\n", .{ game.unmarked(1), game.unmarked(2), game.unmarked(3), game.unmarked(4) }) catch {};
    s.writer().print("counterValue= {d} {d} {d} {d}\n", .{ counterValue(1), counterValue(2), counterValue(3), counterValue(4) }) catch {};
    s.writer().print("panelCells  = {d} {d} {d} {d}   timer={d}\n", .{
        panelCells(false, counterShown(1)), panelCells(true, counterShown(2)),
        panelCells(true,  counterShown(3)), panelCells(true, counterShown(4)),
        panelCells(false, if (game.started) timerSeconds() else null),
    }) catch {};
    s.writer().print("started={} over={} win={} elapsed_ms={d}\n", .{ game.started, game.over, game.win, game.elapsed_ms }) catch {};
    f.writeAll(s.items) catch {};
}

fn runSelftest(path: []const u8) u32 {
    var buf: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var out = std.ArrayList(u8).init(fba.allocator());
    const fails = selftest.run(&out);
    const file = std.fs.cwd().createFile(path, .{}) catch return 2;
    defer file.close();
    file.writeAll(out.items) catch return 2;
    return if (fails == 0) 0 else 1;
}

const selftest = @import("selftest.zig");
const uitest = @import("uitest.zig");

fn runUiTest(path: []const u8) u32 {
    const buf = std.heap.page_allocator;
    var out = std.ArrayList(u8).init(buf);
    defer out.deinit();
    const fails = uitest.run(&out);
    const file = std.fs.cwd().createFile(path, .{}) catch return 2;
    defer file.close();
    file.writeAll(out.items) catch return 2;
    return if (fails == 0) 0 else 1;
}

// ------------------------------------------------------------------ 给 uitest 用的钩子
pub const game_ptr = &game;
pub const test_IDM_BEGINNER = IDM_BEGINNER;
pub const test_IDM_INTERMEDIATE = IDM_INTERMEDIATE;
pub const test_IDM_EXPERT = IDM_EXPERT;
pub const test_IDM_ZOOM1 = IDM_ZOOM1;
pub const test_IDM_ZOOM2 = IDM_ZOOM2;
pub const test_IDM_ZOOM3 = IDM_ZOOM3;
pub const test_IDM_NEW = IDM_NEW;
pub const test_IDM_HELP_HOW = IDM_HELP_HOW;
pub const test_IDM_HELP_ABOUT = IDM_HELP_ABOUT;
pub const test_IDM_BEST = IDM_BEST;
/// 被删掉的那条菜单命令（显示值对照表）的 ID：菜单里绝不该再出现它
pub const test_IDM_HELP_TABLE_REMOVED: usize = 201;

pub fn testWindow() w.HWND {
    return hwnd_main;
}
pub fn testCommand(id: usize) void {
    handleCommand(hwnd_main, id);
}
pub fn testZoom() i32 {
    return zoom;
}
pub fn testLayout() Layout {
    return layout();
}
pub fn testFaceDown() bool {
    return face_down;
}
/// 这次左键是不是"从人脸按下的"（决定松手时要不要重开）
pub fn testFaceArmed() bool {
    return face_armed;
}
/// 当前被按住的格子（-1 = 没有）与两张关键贴图，供自检核对"按下预览"
pub fn testPressCell() i32 {
    return press_cell;
}
/// 左右键同时按住 / 中键按住时记下的展开目标（-1 = 没有）
pub fn testChordCell() i32 {
    return chord_cell;
}
pub const testBlankSprite = A.blank;
pub const testClosedSprite = A.closed;
pub fn testFaceX() i32 {
    return faceLeft(layout());
}
pub fn testFaceY() i32 {
    return faceTop(layout());
}
/// 计雷器上实际显示的数（负实/负虚 是负的，虚雷另外挂 i 单位格）
pub fn testCounterValue(t: usize) i32 {
    return counterValue(t);
}
/// 计雷器里最宽的一条占几格（常态是四格：实雷四格数字、虚雷三格数字 + 一格 i）
pub fn testCounterCells() i32 {
    var widest: i32 = 0;
    for (1..5) |t| widest = @max(widest, panelCells(counterImag(t), counterShown(t)));
    return widest;
}
/// 某一条计雷器的数值区画几格**数字**（实雷四格、虚雷三格；没开局时整条画空格子）
pub fn testCounterValueCells(t: usize) i32 {
    return panelValueDigits(counterImag(t), counterShown(t));
}
/// 计时器面板占几格（和计雷器同样四格）
pub fn testTimerCells() i32 {
    const tv: ?i32 = if (game.started) timerSeconds() else null;
    return panelCells(false, tv);
}
/// 计时器画几格数字（四格）
pub fn testTimerValueCells() i32 {
    const tv: ?i32 = if (game.started) timerSeconds() else null;
    return panelValueDigits(false, tv);
}
/// 计时器面板宽度（版式自检用）
pub fn testTimerWidth() i32 {
    return timerWidth(zoom);
}
pub fn testCounterImag(t: usize) bool {
    return counterImag(t);
}
/// 计雷器那一列的整体宽度（版式自检拿它核对没有溢进人脸/表头外）
pub fn testCountersWidth() i32 {
    return countersWidth(layout());
}
pub fn testMouse(msg: w.UINT, x: i32, y: i32) void {
    _ = mainWndProc(hwnd_main, msg, 0, w.makeLParam(x, y));
}
/// 菜单里到底挂了哪些命令：遍历菜单栏的每个下拉，收集所有命令 ID。
/// 不给真实点击菜单的机会（那会进模态循环），所以直接查系统里的菜单句柄。
pub fn testMenuHasId(id: usize) bool {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return false;
    const tops = w.GetMenuItemCount(bar);
    var i: i32 = 0;
    while (i < tops) : (i += 1) {
        const sub = w.GetSubMenu(bar, i);
        if (sub == null) {
            if (w.GetMenuItemID(bar, i) == @as(u32, @intCast(id))) return true;
            continue;
        }
        const items = w.GetMenuItemCount(sub);
        var j: i32 = 0;
        while (j < items) : (j += 1) {
            if (w.GetMenuItemID(sub, j) == @as(u32, @intCast(id))) return true;
        }
    }
    return false;
}
/// 第 top 个下拉里的项目数（含分隔线）。帮助菜单是第 2 个（索引 1）。
pub fn testPopupCount(top: i32) i32 {
    const bar = w.GetMenu(hwnd_main);
    if (bar == null) return -1;
    const sub = w.GetSubMenu(bar, top);
    if (sub == null) return -1;
    return w.GetMenuItemCount(sub);
}
/// 窗口标题（自检核对用户看得见的那串字）
pub fn testWindowTitle() []const u16 {
    const hwnd = hwnd_main orelse return &[_]u16{};
    const n = w.GetWindowTextW(hwnd, &title_buf, title_buf.len);
    if (n <= 0) return &[_]u16{};
    return title_buf[0..@intCast(n)];
}
var title_buf: [128]u16 = undefined;
/// 编译期那份标题常量，供自检比对（别在自检里写死字符串，改标题时自检要跟着报）
pub const testAppTitle: [*:0]const u16 = w.wstr(APP_TITLE);
/// 版本号（关于对话框与自检报告抬头都用它）
pub const testAppVersion = APP_VERSION;
/// 关于对话框的完整正文（自检核对里面有没有版本号）
pub const testAboutText: [*:0]const u16 = w.wstr(ABOUT_TEXT);
/// 「玩法与操作」的完整正文（自检核对旗帜顺序那几行用的是不是"旗"的名字）
pub const testHelpText: [*:0]const u16 = w.wstr(HELP_TEXT);
/// 图标资源在不在：窗口图标、"关于"弹窗都靠它，缺失说明 .rsrc 没注入或者写坏了。
/// 两档都验：LoadIconW 走默认尺寸，LoadImageW 点名 16×16。
pub fn testIconResourceOk() bool {
    const hinst = w.GetModuleHandleW(null);
    if (w.LoadIconW(hinst, w.resId(ICON_RES_ID)) == null) return false;
    return w.LoadImageW(hinst, w.resId(ICON_RES_ID), w.IMAGE_ICON, 16, 16, w.LR_DEFAULTCOLOR) != null;
}
pub fn testKey(vk: w.WPARAM) w.LRESULT {
    return mainWndProc(hwnd_main, w.WM.KEYDOWN, vk, 0);
}
// ---- 对话框与渲染的测试钩子 ----
pub fn testOpenDialog() bool {
    return createCustomWindow();
}
pub fn testCloseDialog() void {
    closeCustomWindow();
}
pub fn testSetEdit(idx: usize, v: i32) void {
    setEditInt(edit_handles[idx], v);
}
pub fn testApplyDialog() bool {
    dlgApply();
    if (dialog_done and !dialog_cancel) {
        applyCustomFromDialog();
        return true;
    }
    return false;
}
pub fn testDialogErrName() []const u8 {
    return switch (dlg_state.err) {
        .none => "none",
        .height => "height",
        .width => "width",
        .sum_zero => "sum_zero",
        .sum_big => "sum_big",
    };
}
pub fn testDialogDone() bool {
    return dialog_done;
}
// ---- 对话框外观／文案的测试钩子 ----
var dlg_texts_buf: [1024]u16 = undefined;
var dlg_texts_len: usize = 0;
fn collectDlgText(h: w.HWND, lp: w.LPARAM) callconv(.c) w.BOOL {
    _ = lp;
    if (dlg_texts_len + 130 >= dlg_texts_buf.len) return w.TRUE;
    const n = w.GetWindowTextW(h, dlg_texts_buf[dlg_texts_len..].ptr, 128);
    if (n > 0) {
        dlg_texts_len += @intCast(n);
        dlg_texts_buf[dlg_texts_len] = '|'; // 分隔符，整串搜索时不会跨控件粘连
        dlg_texts_len += 1;
    }
    return w.TRUE;
}
/// 对话框里所有子控件的文字拼成一串（自检用来核对标签文案）
pub fn testDialogTexts() []const u16 {
    dlg_texts_len = 0;
    if (dialog_hwnd != null) _ = w.EnumChildWindows(dialog_hwnd, collectDlgText, 0);
    return dlg_texts_buf[0..dlg_texts_len];
}
/// 静态标签拿到的背景刷子是不是那块白刷子（整个对话框白底）
pub fn testDialogBgBrushIsWhite() bool {
    if (dialog_hwnd == null or dlg_bg_brush == null) return false;
    const dc = w.GetDC(dialog_hwnd);
    defer _ = w.ReleaseDC(dialog_hwnd, dc);
    const r = dlgWndProc(dialog_hwnd, w.WM.CTLCOLORSTATIC, @intFromPtr(dc), @as(w.LPARAM, @intCast(@intFromPtr(dlg_err_hwnd))));
    return r == @as(w.LRESULT, @bitCast(@intFromPtr(dlg_bg_brush)));
}
pub fn testSplitClick() void {
    // 走对话框里那条真实路径（点"按合计均分"按钮）
    _ = dlgWndProc(dialog_hwnd, w.WM.COMMAND, @as(w.WPARAM, @intCast(IDC_BTN_SPLIT)), 0);
}
pub fn testEditValue(idx: usize) i32 {
    return getEditInt(edit_handles[idx], -1);
}
pub fn testFaceSpriteIsWin() bool {
    return faceSprite() == A.face_win;
}
/// 按住人脸时用的是不是"按下"那张（换素材后至少要确认五张脸都被认到）
pub fn testFaceSpriteIsDown() bool {
    return faceSprite() == A.face_down;
}
/// 翻格/插旗那一瞬间是不是在放「脸扫雷」
pub fn testFaceSpriteIsScan() bool {
    return faceSprite() == A.face_scan;
}
/// 手动把「脸扫雷」的闪动结束掉，免得自检里要真等 200ms
pub fn testFaceFlashExpire() void {
    face_flash_until = 0;
}
pub fn testFaceSpriteIsDead() bool {
    return faceSprite() == A.face_dead;
}
pub fn testCellSprite(cell: usize) u16 {
    return cellSprite(cell);
}
// ---- 最高分纪录的测试钩子 ----
pub fn testScoresStopPersist() void {
    scores_persist = false;
    scores_quiet = true;
}
pub fn testSetScores(v0: i32, v1: i32, v2: i32) void {
    best_scores = .{ v0, v1, v2 };
}
pub fn testGetScore(i: usize) i32 {
    return best_scores[i];
}
var scores_text_buf: [512]u16 = undefined;
/// 把「最高分纪录」对话框的正文取出来给自检核对（UTF-16 码元，不含结尾 0）
pub fn testScoresText() []const u16 {
    const n = buildScoresText(&scores_text_buf);
    return scores_text_buf[0..n];
}
/// 把开局时刻往前挪 ms 毫秒，用来在自检里模拟"用了多久"
pub fn testBackdate(ms: u32) void {
    game.t0 = nowMs() -% ms;
}
