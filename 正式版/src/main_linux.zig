// 复扫雷 Complexweeper · Linux 版主程序
//
// 规则层（game.zig）与素材（assets.zig）与 Windows 版**完全共用**，
// 这里只重写界面层：X11 没有 Win32 那套窗口/菜单/编辑框/MessageBox，
// 所以菜单栏、下拉菜单、自定义雷区对话框、消息框全部自己画（观感照旧是经典 Win95 风格）。
//
// 最高分：Windows 版写 HKCU 注册表，Linux 下改写 XDG 配置目录下的一个 ini。
const std = @import("std");
const x = @import("x11.zig");
const g = @import("game.zig");
const A = @import("assets.zig");
const selftest = @import("selftest.zig");

// ------------------------------------------------------------------ 常量
const APP_TITLE = "复扫雷 Complexweeper";
/// 与 Windows 版同一个版本号（main.zig 的 APP_VERSION，改动时两边一起改）
const APP_VERSION = "1.0.13";

/// 菜单栏高度。X11 没有系统菜单栏，这一条由我们自己画在客户区最上面，
/// 于是棋盘整体往下挪 MENU_H。
const MENU_H: i32 = 22;
/// 下拉菜单里每一项的高度
const ITEM_H: i32 = 20;
/// 菜单项左右留白
const ITEM_PAD_X: i32 = 10;

const IDM_NEW: usize = 100;
const IDM_BEGINNER: usize = 101;
const IDM_INTERMEDIATE: usize = 102;
const IDM_EXPERT: usize = 103;
const IDM_CUSTOM: usize = 104;
const IDM_EXIT: usize = 105;
const IDM_ZOOM1: usize = 110;
const IDM_ZOOM2: usize = 111;
const IDM_ZOOM3: usize = 112;
const IDM_BEST: usize = 106;
const IDM_HELP_HOW: usize = 200;
const IDM_HELP_ABOUT: usize = 202;

const MenuItem = struct {
    id: usize, // 0 = 分隔线
    label: []const u8,
    hint: []const u8, // 右侧快捷键提示
};

const MENU_GAME_ITEMS = [_]MenuItem{
    .{ .id = IDM_NEW, .label = "开局", .hint = "F2" },
    .{ .id = 0, .label = "", .hint = "" },
    .{ .id = IDM_BEGINNER, .label = "初级", .hint = "9×9 · 10 雷" },
    .{ .id = IDM_INTERMEDIATE, .label = "中级", .hint = "16×16 · 40 雷" },
    .{ .id = IDM_EXPERT, .label = "高级", .hint = "30×16 · 99 雷" },
    .{ .id = IDM_CUSTOM, .label = "自定义…", .hint = "" },
    .{ .id = 0, .label = "", .hint = "" },
    .{ .id = IDM_BEST, .label = "最高分纪录…", .hint = "" },
    .{ .id = 0, .label = "", .hint = "" },
    .{ .id = IDM_ZOOM1, .label = "缩放 100%", .hint = "" },
    .{ .id = IDM_ZOOM2, .label = "缩放 200%", .hint = "" },
    .{ .id = IDM_ZOOM3, .label = "缩放 300%", .hint = "" },
    .{ .id = 0, .label = "", .hint = "" },
    .{ .id = IDM_EXIT, .label = "退出", .hint = "" },
};

const MENU_HELP_ITEMS = [_]MenuItem{
    .{ .id = IDM_HELP_HOW, .label = "玩法与操作", .hint = "" },
    .{ .id = 0, .label = "", .hint = "" },
    .{ .id = IDM_HELP_ABOUT, .label = "关于复扫雷…", .hint = "" },
};

const MenuBar = struct {
    title: []const u8,
    items: []const MenuItem,
};

const MENUS = [_]MenuBar{
    .{ .title = "游戏", .items = &MENU_GAME_ITEMS },
    .{ .title = "帮助", .items = &MENU_HELP_ITEMS },
};

const DlgErr = enum(u8) { none = 0, height, width, sum_zero, sum_big };
fn dlgErrText(e: DlgErr) []const u8 {
    return switch (e) {
        .none => "",
        .height => "高度要在 9 – 30 之间。",
        .width => "宽度要在 9 – 40 之间。",
        .sum_zero => "四种雷合计至少 1 颗。",
        .sum_big => "合计超过上限（格数 − 9）。",
    };
}

const ABOUT_TEXT =
    APP_TITLE ++ " " ++ APP_VERSION ++ "\n" ++
    "基于 Microsoft® 扫雷(原版作者：Robert Donner、Curt Johnson)\n" ++
    "\n" ++
    "图像素材来源：Microsoft(扫雷原始图像素材)；青月晓(新增图像素材)。\n" ++
    "Copyright © 2026 青月晓\n" ++
    "本程序为免费软件\n" ++
    "与 Microsoft 公司无隶属关系";

const HELP_TEXT =
    "雷区里有四种雷，分别是正实雷、负实雷、正虚雷、负虚雷。\n" ++
    "左键翻开格子。\n" ++
    "右键插旗，旗帜顺序为正实旗、负实旗、正虚旗、负虚旗。\n" ++
    "中键或左右键同时点击展开格子。\n" ++
    "F2开局。\n" ++
    "\n" ++
    "数字代表该格周围所有雷的加和之模长，均为整数或最简根式。\n" ++
    "\n" ++
    "当旗帜数量等于周围真实雷数，且实虚比例符合真实比例或其倒数，则可以展开。";

// ------------------------------------------------------------------ 全局状态
var ctx: x.Ctx = undefined;
var main_canvas: x.Canvas = undefined;
var alloc: std.mem.Allocator = undefined;

var game: g.Game = .{};
var zoom: i32 = 2;

/// 图集（BGRA，自顶向下）
var atlas_px: []const u8 = &.{};
var atlas_w: i32 = 0;
var atlas_h: i32 = 0;

/// 菜单：-1 = 全部收起
var menu_open: i32 = -1;
var menu_hover: i32 = -1;
/// 菜单栏上正被按住的项（按下即展开，和 Win95 行为一致）
var menu_bar_down: i32 = -1;

/// 人脸与鼠标
var face_down = false;
var face_armed = false;
var face_flash_until: u32 = 0;
/// 闪烁中（事件驱动重绘后需要靠定时器把它收回正常表情）
var face_flashing: bool = false;
const FACE_FLASH_MS: u32 = 200;
var press_cell: i32 = -1;
var chord_cell: i32 = -1;
var l_down = false;
var r_down = false;
var m_down = false;
/// 主窗口在屏幕上的位置（居中对话框要用）
var win_sx: i32 = 0;
var win_sy: i32 = 0;

/// 最高分：三档各一个（秒）
var scores: [3]i32 = .{ 999, 999, 999 };
var scores_loaded = false;

// ------------------------------------------------------------------ 布局
// 与 Windows 版 main.zig 的 Layout 字段一致，坐标原点在**棋盘区**左上角，
// 实际画的时候整体加 MENU_H。
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

const REAL_DIGITS: i32 = 4;
const IMAG_DIGITS: i32 = 3;

fn valueDigits(base: i32, v: ?i32) i32 {
    if (v == null) return base;
    const x2 = v.?;
    if (x2 >= 0) return if (x2 <= pow10i(base) - 1) base else base + 1;
    return if (x2 >= -(pow10i(base - 1) - 1)) base else base + 1;
}
fn panelValueDigits(imag: bool, v: ?i32) i32 {
    return valueDigits(if (imag) IMAG_DIGITS else REAL_DIGITS, v);
}
fn panelCells(imag: bool, v: ?i32) i32 {
    return panelValueDigits(imag, v) + (if (imag) @as(i32, 1) else 0);
}
fn counterWidth(z: i32, digits: i32) i32 {
    return 16 * z + 2 * z + digits * 13 * z + 2 * z;
}
fn counterValue(t: usize) i32 {
    const k = game.unmarked(t);
    return switch (t) {
        2, 4 => -k,
        else => k,
    };
}
fn counterShown(t: usize) ?i32 {
    if (!game.started) return null;
    return counterValue(t);
}
fn counterImag(t: usize) bool {
    return t == 3 or t == 4;
}
fn countersWidth(L: Layout) i32 {
    var widest: i32 = 0;
    for (1..5) |t| {
        widest = @max(widest, counterWidth(L.z, panelCells(counterImag(t), counterShown(t))));
    }
    return widest;
}
fn timerWidth(z: i32) i32 {
    return 4 * 13 * z + 2 * z;
}
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

const FACE_SIZE: i32 = 24;
const FACE_NUDGE: i32 = 2;

fn countersX(L: Layout) i32 {
    return L.header_x + 4 * L.z;
}
fn countersY(L: Layout) i32 {
    return L.header_y + 2 * L.z + 3 * L.z;
}
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

fn pow10i(n: i32) i32 {
    var r: i32 = 1;
    var i: i32 = 0;
    while (i < n) : (i += 1) r *= 10;
    return r;
}
fn fmtDigits(buf: []u8, v: u32, digits: u32) usize {
    var i: usize = digits;
    var x2 = v;
    while (i > 0) {
        i -= 1;
        buf[i] = @intCast('0' + (x2 % 10));
        x2 /= 10;
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

// ------------------------------------------------------------------ 图集
fn rectOf(sprite: u16) A.Rect {
    return A.rect(sprite);
}
fn blitSpriteSq(sf: *x.Surface, sprite: u16, x0: i32, y0: i32, size: i32) void {
    blitSprite(sf, sprite, x0, y0, size, size);
}
fn blitSprite(sf: *x.Surface, sprite: u16, x0: i32, y0: i32, dw: i32, dh: i32) void {
    const r = rectOf(sprite);
    sf.blit(atlas_px, atlas_w, atlas_h, r.x, r.y, r.w, r.h, x0, y0, dw, dh);
}

fn loadAtlas() bool {
    const blob = A.blob;
    if (blob.len < 12) return false;
    if (!(blob[0] == 'C' and blob[1] == 'S' and blob[2] == 'A' and blob[3] == 'T')) return false;
    atlas_w = A.atlas_w;
    atlas_h = A.atlas_h;
    const pix_off: usize = 12 + @as(usize, A.count) * 8;
    const need: usize = @as(usize, @intCast(atlas_w)) * @as(usize, @intCast(atlas_h)) * 4;
    if (blob.len < pix_off + need) return false;
    atlas_px = blob[pix_off .. pix_off + need];
    return true;
}

/// 图集里的 32×32 图标转成 RGBA（_NET_WM_ICON 要 RGBA）
fn iconRGBA(buf: []u8) ?[]const u8 {
    const r = rectOf(A.icon);
    if (r.w != 32 or r.h != 32) return null;
    const n: usize = 32 * 32 * 4;
    if (buf.len < n) return null;
    const src_w: usize = @intCast(atlas_w);
    var y: usize = 0;
    while (y < 32) : (y += 1) {
        var xx: usize = 0;
        while (xx < 32) : (xx += 1) {
            const s = (y * src_w + @as(usize, r.x) + xx) * 4;
            const d = (y * 32 + xx) * 4;
            buf[d + 0] = atlas_px[s + 2]; // R
            buf[d + 1] = atlas_px[s + 1]; // G
            buf[d + 2] = atlas_px[s + 0]; // B
            buf[d + 3] = atlas_px[s + 3]; // A
        }
    }
    return buf[0..n];
}

// ------------------------------------------------------------------ 棋盘绘制
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
fn chordable(c: usize) bool {
    return game.open[c] != 0 and game.flag[c] == 0 and !game.over;
}
fn chordTarget(i: usize) bool {
    if (game.open[i] == 0) return true;
    if (game.flag[i] != 0) return false;
    return game.clue[i] == 0;
}

fn cellSprite(i: usize) u16 {
    if (game.over and !game.win) {
        if (i == @as(usize, @intCast(game.boom))) return boomSprite(game.mine[i]);
        if (game.flag[i] != 0 and game.flag[i] != game.mine[i]) return wrongSprite(game.flag[i]);
    }
    var revealed = game.open[i] != 0;
    if (chord_cell >= 0 and game.open[i] == 0 and game.flag[i] == 0) {
        const c: usize = @intCast(chord_cell);
        if (chordTarget(i) and i != c) revealed = true;
    }
    if (press_cell >= 0 and @as(usize, @intCast(press_cell)) == i) revealed = true;
    if (revealed and game.mine[i] != 0) return mineSprite(game.mine[i]);
    if (game.flag[i] != 0) return flagSprite(game.flag[i]);
    if (revealed) {
        // 数字要取 clue，不是 open。open 只是「已翻开」的**状态标志**，
        // 值等于开图顺序（1、2、3…），拿它当 clue 会把整片棋盘画成空白
        // ——数字精灵一个都不显示，正是真机上的症状。
        //
        // 空白格的判据是「线索为 0 且周围一圈都没雷」，与 open 的值无关。
        // 这条与 Win32 版 main.zig 的 cellSprite 保持一致。
        const D: i16 = game.clue[i];
        if (D <= 0 and game.nbrMineCount(i) == 0) return A.blank;
        if (D < 0) return A.blank; // 还没算线索：按空白处理
        const s = A.num_by_D[@intCast(@min(D, 64))];
        return if (s == 0xFFFF) A.blank else s;
    }
    return A.closed;
}

fn faceSprite() u16 {
    if (face_down) return A.face_down;
    if (game.over) return if (game.win) A.face_win else A.face_dead;
    if (boardHeld()) return A.face_scan;
    if (x.nowMs() < face_flash_until) return A.face_scan;
    return A.face_normal;
}
fn boardHeld() bool {
    return r_down or m_down or (l_down and !face_down);
}

fn timerSeconds() i32 {
    if (!game.started) return 0;
    return @intCast(@min(@as(u32, 9999), game.elapsed_ms / 1000));
}

fn drawLed(sf: *x.Surface, x0: i32, y0: i32, v: ?i32, digits: i32, z: i32) i32 {
    const lw = 13 * z;
    const lh = 23 * z;
    var cx = x0;
    if (v == null) {
        var i: i32 = 0;
        while (i < digits) : (i += 1) {
            blitSprite(sf, A.led_blank, cx, y0, lw, lh);
            cx += lw;
        }
        return cx - x0;
    }
    const val = v.?;
    if (val < 0) {
        blitSprite(sf, A.led_minus, cx, y0, lw, lh);
        cx += lw;
        var m = -val;
        const lim = pow10i(digits - 1) - 1;
        if (m > lim) m = lim;
        var buf: [4]u8 = undefined;
        const n = fmtDigits(&buf, @intCast(m), @intCast(digits - 1));
        for (buf[0..n]) |ch| {
            blitSprite(sf, digitSprite(ch), cx, y0, lw, lh);
            cx += lw;
        }
    } else {
        var m = val;
        const lim = pow10i(digits) - 1;
        if (m > lim) m = lim;
        var buf: [4]u8 = undefined;
        const n = fmtDigits(&buf, @intCast(m), @intCast(digits));
        for (buf[0..n]) |ch| {
            blitSprite(sf, digitSprite(ch), cx, y0, lw, lh);
            cx += lw;
        }
    }
    return cx - x0;
}

fn paintBoard(sf: *x.Surface, L: Layout, yoff: i32) void {
    sf.fill(0, yoff, L.client_w, L.client_h, x.C_BTNFACE);
    sf.draw3d(0, yoff, L.client_w, L.client_h, L.frame, true);

    // 表头凹槽（sunken）
    sf.draw3d(L.header_x, yoff + L.header_y, L.header_w, L.header_h, 2 * L.z, false);

    // 四个计雷器竖排
    const col_x = countersX(L);
    var cy = countersY(L);
    for (1..5) |t| {
        const val = counterShown(t);
        const imag = counterImag(t);
        const cw = counterWidth(L.z, panelCells(imag, val));
        sf.draw3d(col_x, yoff + cy, cw, 26 * L.z, 1 * L.z, false);
        blitSpriteSq(sf, flagSprite(@intCast(t)), col_x + 2 * L.z, yoff + cy + @divTrunc(26 * L.z - 16 * L.z, 2), 16 * L.z);
        const led_x = col_x + L.z + 2 * L.z + 16 * L.z;
        const led_y = cy + @divTrunc(26 * L.z - 23 * L.z, 2);
        const vw = drawLed(sf, led_x, yoff + led_y, val, panelValueDigits(imag, val), L.z);
        if (imag) blitSprite(sf, if (val == null) A.led_blank else A.led_i, led_x + vw, yoff + led_y, 13 * L.z, 23 * L.z);
        cy += 26 * L.z + 2 * L.z;
    }

    // 计时器
    const tx = timerX(L);
    const ty = timerY(L);
    const tv: ?i32 = if (game.started) timerSeconds() else null;
    sf.draw3d(tx, yoff + ty, timerWidth(L.z), 26 * L.z, 1 * L.z, false);
    _ = drawLed(sf, tx + L.z, yoff + ty + @divTrunc(26 * L.z - 23 * L.z, 2), tv, panelValueDigits(false, tv), L.z);

    // 人脸
    blitSpriteSq(sf, faceSprite(), faceLeft(L), yoff + faceTop(L), FACE_SIZE * L.z);

    // 棋盘凹槽 + 格子
    const bx = L.board_x - L.box;
    const by = L.board_y - L.box;
    const bw = @as(i32, game.w) * L.cell + 2 * L.box;
    const bh = @as(i32, game.h) * L.cell + 2 * L.box;
    sf.draw3d(bx, yoff + by, bw, bh, L.box, false);

    var i: usize = 0;
    while (i < game.n) : (i += 1) {
        const r: i32 = @intCast(i / game.w);
        const c: i32 = @intCast(i % game.w);
        blitSpriteSq(sf, cellSprite(i), L.board_x + c * L.cell, yoff + L.board_y + r * L.cell, L.cell);
    }
}

fn cellAt(L: Layout, px: i32, py: i32) i32 {
    const dx = px - L.board_x;
    const dy = py - L.board_y;
    if (dx < 0 or dy < 0) return -1;
    const c = @divTrunc(dx, L.cell);
    const r = @divTrunc(dy, L.cell);
    if (c < 0 or c >= @as(i32, game.w)) return -1;
    if (r < 0 or r >= @as(i32, game.h)) return -1;
    return r * @as(i32, game.w) + c;
}
fn inFace(L: Layout, px: i32, py: i32) bool {
    const fx = faceLeft(L);
    const fy = faceTop(L);
    const s = FACE_SIZE * L.z;
    return px >= fx and px < fx + s and py >= fy and py < fy + s;
}

// ------------------------------------------------------------------ 菜单
fn menuBarX(i: usize) i32 {
    var cx: i32 = 0;
    for (MENUS[0..i]) |m| {
        cx += ctx.textWidth(m.title, .ui) + ITEM_PAD_X * 2;
    }
    return cx;
}
fn menuBarW(i: usize) i32 {
    return @as(i32, @intCast(ctx.textWidth(MENUS[i].title, .ui))) + ITEM_PAD_X * 2;
}
fn menuBarHit(px: i32) i32 {
    for (MENUS, 0..) |_, i| {
        const mx = menuBarX(i);
        if (px >= mx and px < mx + menuBarW(i)) return @intCast(i);
    }
    return -1;
}

const DropGeom = struct { x: i32, y: i32, w: i32, h: i32, item_h: i32 };

fn dropGeom(mi: usize) DropGeom {
    var wmax: i32 = 0;
    for (MENUS[mi].items) |it| {
        if (it.id == 0) continue;
        const lw = ctx.textWidth(it.label, .ui) + ctx.textWidth(it.hint, .ui);
        wmax = @max(wmax, lw);
    }
    const w = wmax + ITEM_PAD_X * 2 + 24; // 24 给提示留的列间距
    const item_h = ITEM_H;
    return .{ .x = menuBarX(mi), .y = MENU_H, .w = w, .h = @as(i32, @intCast(MENUS[mi].items.len)) * item_h, .item_h = item_h };
}

fn dropItemAt(px: i32, py: i32) i32 {
    const mi: usize = @intCast(menu_open);
    if (mi >= MENUS.len) return -1;
    const d = dropGeom(mi);
    if (px < d.x or px >= d.x + d.w) return -1;
    if (py < d.y or py >= d.y + d.h) return -1;
    return @divTrunc(py - d.y, d.item_h);
}

fn paintMenuBar(cv: *x.Canvas) void {
    const sf = &cv.surface;
    sf.fill(0, 0, cv.w, MENU_H, x.C_BTNFACE);
    sf.fill(0, MENU_H - 1, cv.w, 1, x.C_BTNSHADOW);

    // 垂直居中：按真实墨迹上下界算基线，旧的 (MENU_H+th)/2+1 会把中文压到下面去
    const base = ctx.centerBaseline(0, MENU_H, .ui);
    for (MENUS, 0..) |m, i| {
        const mx = menuBarX(i);
        const mw = menuBarW(i);
        if (menu_open == @as(i32, @intCast(i)) or menu_bar_down == @as(i32, @intCast(i))) {
            sf.fill(mx, 1, mw, MENU_H - 2, x.C_MENUHILIGHT);
            cv.text(mx + ITEM_PAD_X, base, m.title, x.C_MENUHILIGHT_TEXT, .ui);
        } else {
            cv.text(mx + ITEM_PAD_X, base, m.title, x.C_BLACK, .ui);
        }
    }

    if (menu_open < 0) return;
    const mi: usize = @intCast(menu_open);
    const d = dropGeom(mi);
    // 下拉面板：凸起外框 + 白底
    sf.draw3d(d.x, d.y, d.w, d.h, 2, true);
    sf.fill(d.x + 2, d.y + 2, d.w - 4, d.h - 4, x.C_BTNFACE);
    for (MENUS[mi].items, 0..) |it, i| {
        const iy = d.y + @as(i32, @intCast(i)) * d.item_h;
        if (it.id == 0) {
            sf.fill(d.x + 4, iy + @divTrunc(d.item_h, 2), d.w - 8, 1, x.C_BTNSHADOW);
            sf.fill(d.x + 4, iy + @divTrunc(d.item_h, 2) + 1, d.w - 8, 1, x.C_BTNHIGHLIGHT);
            continue;
        }
        const hot = (menu_hover == @as(i32, @intCast(i)));
        if (hot) {
            sf.fill(d.x + 2, iy, d.w - 4, d.item_h, x.C_MENUHILIGHT);
        }
        const col = if (hot) x.C_MENUHILIGHT_TEXT else x.C_BLACK;
        const tb = ctx.centerBaseline(iy, d.item_h, .ui);
        cv.text(d.x + ITEM_PAD_X, tb, it.label, col, .ui);
        if (it.hint.len > 0) {
            const hw = ctx.textWidth(it.hint, .ui);
            cv.text(d.x + d.w - ITEM_PAD_X - hw, tb, it.hint, col, .ui);
        }
    }
}

fn closeMenu(cv: *x.Canvas) void {
    if (menu_open < 0) return;
    menu_open = -1;
    menu_hover = -1;
    menu_bar_down = -1;
    cv.ungrabPointer();
    cv.focus();
}

// ------------------------------------------------------------------ 最高分
fn scoresPath(buf: []u8) ?[]const u8 {
    const home = std.process.getEnvVarOwned(alloc, "XDG_CONFIG_HOME") catch null;
    if (home) |h| {
        if (h.len > 0) {
            const p = std.fmt.bufPrint(buf, "{s}/complexweeper/scores.ini", .{h}) catch return null;
            return p;
        }
        alloc.free(h);
    }
    const h2 = std.process.getEnvVarOwned(alloc, "HOME") catch return null;
    defer alloc.free(h2);
    return std.fmt.bufPrint(buf, "{s}/.config/complexweeper/scores.ini", .{h2}) catch null;
}

fn loadScores() void {
    if (scores_loaded) return;
    scores_loaded = true;
    var pb: [512]u8 = undefined;
    const p = scoresPath(&pb) orelse return;
    const data = std.fs.cwd().readFileAlloc(alloc, p, 4096) catch return;
    defer alloc.free(data);
    const keys = [_][]const u8{ "beginner=", "intermediate=", "expert=" };
    for (keys, 0..) |k, i| {
        if (std.mem.indexOf(u8, data, k)) |at| {
            const rest = data[at + k.len ..];
            const nl = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const v = std.mem.trim(u8, rest[0..nl], " \t\r");
            if (v.len > 0) scores[i] = std.fmt.parseInt(i32, v, 10) catch scores[i];
        }
    }
}

fn saveScores() void {
    var pb: [512]u8 = undefined;
    const p = scoresPath(&pb) orelse return;
    if (std.fs.path.dirname(p)) |dir| {
        std.fs.cwd().makePath(dir) catch {};
    }
    const f = std.fs.cwd().createFile(p, .{ .truncate = true }) catch return;
    defer f.close();
    const w = f.writer();
    w.print("beginner={d}\nintermediate={d}\nexpert={d}\n", .{ scores[0], scores[1], scores[2] }) catch {};
}

fn presetIndex() i32 {
    for (g.PRESETS, 0..) |p, i| {
        if (p.w == game.w and p.h == game.h and p.mines == game.mines) return @intCast(i);
    }
    return -1;
}

/// 通关后记分（与 Windows 版同规则：同一档里秒数更小才刷新）
fn afterGameAction() void {
    if (!game.over or !game.win) return;
    const pi = presetIndex();
    if (pi < 0) return;
    const secs: i32 = @intCast(@min(@as(u32, 9999), game.elapsed_ms / 1000));
    if (secs < scores[@intCast(pi)]) {
        scores[@intCast(pi)] = secs;
        saveScores();
    }
}

// ------------------------------------------------------------------ 局面操作
fn startNewGame(seed_override: ?u32) void {
    // 没有指定种子就用时钟换一个，同一毫秒内重开也无所谓
    game.newGame(seed_override orelse x.nowMs());
}

fn setPreset(idx: i32) void {
    if (idx < 0 or idx >= @as(i32, g.PRESETS.len)) return;
    const p = g.PRESETS[@intCast(idx)];
    game.w = p.w;
    game.h = p.h;
    game.mines = p.mines;
    game.type_count = [_]u16{0} ** 5; // 回到"类型随机撒"
    game.newGame(x.nowMs());
    rebuildMain();
}

fn flashFace() void {
    face_flash_until = x.nowMs() +% FACE_FLASH_MS;
    face_flashing = true;
}

fn doExpand(c: usize) void {
    const m0 = game.moves;
    game.tryExpand(c);
    afterGameAction();
    if (game.moves != m0 and !game.over) flashFace();
}

// ------------------------------------------------------------------ 尺寸重建
/// 难度或缩放变了就改窗口尺寸。走 resize 而不是重建窗口，焦点和图标都保得住。
fn rebuildMain() void {
    const L = layout();
    main_canvas.resize(L.client_w, MENU_H + L.client_h) catch {};
}

// ------------------------------------------------------------------ 对话框
const Edit = struct {
    data: [8]u8 = undefined,
    len: usize = 0,
    focused: bool = false,

    fn setInt(self: *Edit, v: i32) void {
        var tmp: [12]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{@max(v, 0)}) catch "0";
        self.len = @min(s.len, self.data.len);
        @memcpy(self.data[0..self.len], s[0..self.len]);
    }
    fn str(self: *const Edit) []const u8 {
        return self.data[0..self.len];
    }
    fn insert(self: *Edit, d: u8) void {
        if (d < '0' or d > '9') return;
        if (self.len >= self.data.len) return;
        self.data[self.len] = d;
        self.len += 1;
    }
    fn backspace(self: *Edit) void {
        if (self.len > 0) self.len -= 1;
    }
    fn value(self: *const Edit) i32 {
        if (self.len == 0) return 0;
        return std.fmt.parseInt(i32, self.str(), 10) catch 0;
    }
};

/// 自绘对话框的公共外观：白底 + 凸起外框
fn dialogFrame(sf: *x.Surface, w: i32, h: i32) void {
    sf.fillAll(x.C_WINDOW);
    sf.draw3d(0, 0, w, h, 1, false);
}

fn buttonFace(sf: *x.Surface, x0: i32, y0: i32, w: i32, h: i32, pressed: bool) void {
    sf.draw3d(x0, y0, w, h, 1, !pressed);
    if (pressed) {
        sf.fill(x0 + 1, y0 + 1, w - 2, h - 2, x.C_BTNFACE);
    }
}

/// 自定义雷区对话框。返回 true 表示用户按了确定。
fn runCustomDialog() bool {
    const dw: i32 = 330;
    const dh: i32 = 250;

    var e_h: Edit = .{};
    var e_w: Edit = .{};
    var e_t: [4]Edit = .{ .{}, .{}, .{}, .{} };

    e_h.setInt(@intCast(game.h));
    e_w.setInt(@intCast(game.w));
    var tc = game.type_count;
    var any: u16 = 0;
    for (1..5) |t| any += tc[t];
    if (any == 0) tc = g.splitEvenly(game.mines);
    for (0..4) |k| e_t[k].setInt(tc[k + 1]);

    var err: DlgErr = .none;
    e_h.focused = true;

    // 编辑框与按钮的位置（与 Windows 版同一套排布）
    const EDIT_W: i32 = 70;
    const EDIT_H: i32 = 22;
    const y_h: i32 = 14;
    const y_w: i32 = 44;
    const y_t: i32 = 78;
    const y_split: i32 = 140;
    const y_ok: i32 = 176;
    const ok_rect = [_]i32{ 122, y_ok, 88, 26 };
    const cancel_rect = [_]i32{ 218, y_ok, 88, 26 };
    const split_rect = [_]i32{ 14, y_split, 104, 24 };

    const scr_w = x.XDisplayWidth(ctx.dpy, ctx.screen);
    const scr_h = x.XDisplayHeight(ctx.dpy, ctx.screen);
    var px = @max(win_sx + 40, 0);
    if (px + dw > scr_w) px = @max(scr_w - dw - 8, 0);
    const py = @max(@min(win_sy + 60, scr_h - dh - 8), 0);

    var cv = x.Canvas.create(&ctx, x.XRootWindow(ctx.dpy, ctx.screen), px, py, dw, dh, "自定义雷区", true) catch return false;
    defer cv.destroy();

    const th = ctx.textHeight(.ui);

    var result = false;
    var running = true;
    while (running) {
        // ---- 画 ----
        const sf = &cv.surface;
        dialogFrame(sf, dw, dh);
        const th_base = th;

        cv.text(14, y_h + 4 + th_base, "高度：", x.C_BLACK, .ui);
        cv.text(160, y_h + 4 + th_base, "9 – 30 行", x.C_DARKGRAY, .ui);
        cv.text(14, y_w + 4 + th_base, "宽度：", x.C_BLACK, .ui);
        cv.text(160, y_w + 4 + th_base, "9 – 40 列", x.C_DARKGRAY, .ui);

        const names = [_][]const u8{ "正实雷：", "负实雷：", "正虚雷：", "负虚雷：" };
        for (0..4) |k| {
            const col: i32 = if (k % 2 == 0) 0 else 160;
            const row: i32 = @divTrunc(@as(i32, @intCast(k)), 2);
            const yy = y_t + row * 30;
            cv.text(14 + col, yy + 4 + th_base, names[k], x.C_BLACK, .ui);
        }

        // 编辑框：白底 + 凹陷边 + 文字
        const boxes = [_]struct { e: *Edit, bx: i32, by: i32, bw: i32 }{
            .{ .e = &e_h, .bx = 80, .by = y_h, .bw = EDIT_W },
            .{ .e = &e_w, .bx = 80, .by = y_w, .bw = EDIT_W },
            .{ .e = &e_t[0], .bx = 80, .by = y_t, .bw = EDIT_W },
            .{ .e = &e_t[1], .bx = 240, .by = y_t, .bw = EDIT_W },
            .{ .e = &e_t[2], .bx = 80, .by = y_t + 30, .bw = EDIT_W },
            .{ .e = &e_t[3], .bx = 240, .by = y_t + 30, .bw = EDIT_W },
        };
        for (boxes) |b| {
            sf.fill(b.bx, b.by, b.bw, EDIT_H, x.C_WINDOW);
            sf.draw3d(b.bx, b.by, b.bw, EDIT_H, 1, false);
            sf.frame(b.bx, b.by, b.bw, EDIT_H, x.C_BTNSHADOW);
            cv.text(b.bx + 6, ctx.centerBaseline(b.by, EDIT_H, .mono), b.e.str(), x.C_BLACK, .mono);
            if (b.e.focused) {
                // 光标：闪烁由定时器重画驱动
                const cw = ctx.textWidth(b.e.str(), .mono);
                if ((x.nowMs() / 500) % 2 == 0) {
                    sf.fill(b.bx + 6 + cw + 1, b.by + 4, 1, EDIT_H - 8, x.C_BLACK);
                }
            }
        }

        // 「按合计均分」+ 错误提示
        buttonFace(sf, split_rect[0], split_rect[1], split_rect[2], split_rect[3], false);
        cv.text(split_rect[0] + 10, ctx.centerBaseline(split_rect[1], split_rect[3], .ui), "按合计均分", x.C_BLACK, .ui);
        if (err != .none) cv.text(130, ctx.centerBaseline(split_rect[1], split_rect[3], .ui), dlgErrText(err), x.Color{ .r = 0xA0, .g = 0, .b = 0 }, .ui);

        for ([_][4]i32{ ok_rect, cancel_rect }) |br| {
            buttonFace(sf, br[0], br[1], br[2], br[3], false);
            const label = if (br[0] == ok_rect[0]) "确定" else "取消";
            const lw = ctx.textWidth(label, .ui);
            cv.text(br[0] + @divTrunc(br[2] - lw, 2), ctx.centerBaseline(br[1], br[3], .ui), label, x.C_BLACK, .ui);
        }

        cv.show();
        cv.flush();

        // ---- 收事件 ----
        const ev = ctx.waitEvent(30);
        switch (ev) {
            .none, .other, .expose, .map, .focus_in, .focus_out => continue,
            .close => {
                running = false;
            },
            .configure => {},
            .key_down => |k| {
                switch (k.keysym) {
                    x.Key.ESCAPE => running = false,
                    x.Key.RETURN, x.Key.KP_ENTER => {
                        err = applyCustomValues(&e_h, &e_w, &e_t);
                        if (err == .none) {
                            result = true;
                            running = false;
                        }
                    },
                    x.Key.TAB => {
                        // 在 6 个框之间轮换
                        var idx: usize = 0;
                        for (boxes, 0..) |b, i| {
                            if (b.e.focused) idx = (i + 1) % boxes.len;
                        }
                        for (boxes) |b| b.e.focused = false;
                        boxes[idx].e.focused = true;
                    },
                    x.Key.BACKSPACE => {
                        for (boxes) |b| {
                            if (b.e.focused) b.e.backspace();
                        }
                        err = .none;
                    },
                    else => {
                        // 只收数字键
                        if (k.keysym >= 0x30 and k.keysym <= 0x39) {
                            const d: u8 = @intCast(k.keysym);
                            for (boxes) |b| {
                                if (b.e.focused) b.e.insert(d);
                            }
                            err = .none;
                        }
                    },
                }
            },
            .key_up => {},
            .motion => {},
            .button_down => |b| {
                switch (b.button) {
                    x.Button.LEFT => {
                        // 点谁谁获得焦点
                        var hit = false;
                        for (boxes) |bx| {
                            const inside = b.x >= bx.bx and b.x < bx.bx + bx.bw and b.y >= bx.by and b.y < bx.by + EDIT_H;
                            bx.e.focused = inside;
                            if (inside) hit = true;
                        }
                        if (hit) {
                            for (boxes) |bx| {
                                if (bx.e.focused and bx.e.len < bx.e.data.len) {
                                    // 追加而不是替换：和真实编辑框一样往光标处插
                                }
                            }
                        }
                        if (inRect(b.x, b.y, &ok_rect)) {
                            err = applyCustomValues(&e_h, &e_w, &e_t);
                            if (err == .none) {
                                result = true;
                                running = false;
                            }
                        } else if (inRect(b.x, b.y, &cancel_rect)) {
                            running = false;
                        } else if (inRect(b.x, b.y, &split_rect)) {
                            const total: i32 = e_h.value() * e_w.value();
                            const sp = g.splitEvenly(@intCast(@max(total - 1, 1)));
                            for (0..4) |k| e_t[k].setInt(sp[k + 1]);
                        }
                    },
                    x.Button.RIGHT => running = false, // 右键当取消
                    else => {},
                }
            },
            .button_up => {},
        }
    }
    return result;
}

fn inRect(px: i32, py: i32, r: *const [4]i32) bool {
    return px >= r[0] and px < r[0] + r[2] and py >= r[1] and py < r[1] + r[3];
}

/// 校验并套用自定义雷区。返回 .none 表示成功，否则是对应的错误（顺带把焦点挪到出错的框上）
fn applyCustomValues(e_h: *Edit, e_w: *Edit, e_t: *[4]Edit) DlgErr {
    e_h.focused = false;
    e_w.focused = false;
    for (e_t) |*e| e.focused = false;

    const h = e_h.value();
    const w = e_w.value();
    if (h < 9 or h > @as(i32, g.MAX_H)) {
        e_h.focused = true;
        return .height;
    }
    if (w < 9 or w > @as(i32, g.MAX_W)) {
        e_w.focused = true;
        return .width;
    }
    var sum: i32 = 0;
    for (e_t) |e| sum += e.value();
    if (sum < 1) return .sum_zero;
    if (sum > h * w - 9) return .sum_big;

    game.h = @intCast(h);
    game.w = @intCast(w);
    game.mines = @intCast(sum);
    game.type_count = .{ 0, @intCast(e_t[0].value()), @intCast(e_t[1].value()), @intCast(e_t[2].value()), @intCast(e_t[3].value()) };
    return .none;
}

/// 通用消息框：一段多行文字 + 确定按钮
fn runMessageBox(title: []const u8, body: []const u8) void {
    const th = ctx.textHeight(.ui);
    const lh = ctx.lineHeight(.ui);

    // 先把 \n 切出来量高度、量宽度
    var lines_buf: [64][256]u8 = undefined;
    var lens: [64]usize = undefined;
    var nlines: usize = 0;
    {
        var it = std.mem.splitScalar(u8, body, '\n');
        var ln = it.next();
        while (ln) |l| {
            if (nlines >= lines_buf.len) break;
            const clean = std.mem.trimRight(u8, l, "\r");
            const n = @min(clean.len, lines_buf[0].len);
            @memcpy(lines_buf[nlines][0..n], clean[0..n]);
            lens[nlines] = n;
            nlines += 1;
            ln = it.next();
        }
    }
    var text_w: i32 = 0;
    for (0..nlines) |i| text_w = @max(text_w, ctx.textWidth(lines_buf[i][0..lens[i]], .ui));

    const dw = @max(text_w + 40, 280);
    const dh = @as(i32, @intCast(nlines)) * lh + @as(i32, @intCast(nlines)) * 4 + 96;
    const scr_w = x.XDisplayWidth(ctx.dpy, ctx.screen);
    const scr_h = x.XDisplayHeight(ctx.dpy, ctx.screen);
    const px = @max(@min(win_sx + @divTrunc(main_canvas.w - dw, 2), scr_w - dw - 8), 0);
    const py = @max(@min(win_sy + @divTrunc(main_canvas.h - dh, 2), scr_h - dh - 8), 0);

    var cv = x.Canvas.create(&ctx, x.XRootWindow(ctx.dpy, ctx.screen), px, py, dw, dh, title, true) catch return;
    defer cv.destroy();

    const btn_w: i32 = 84;
    const btn_h: i32 = 26;
    const btn = [_]i32{ @divTrunc(dw - btn_w, 2), dh - btn_h - 16, btn_w, btn_h };

    var running = true;
    while (running) {
        const sf = &cv.surface;
        dialogFrame(sf, dw, dh);
        for (lines_buf[0..nlines], 0..) |lnb, i| {
            cv.text(20, 20 + @as(i32, @intCast(i)) * lh + th, lnb[0..lens[i]], x.C_BLACK, .ui);
        }
        buttonFace(sf, btn[0], btn[1], btn[2], btn[3], false);
        const lw = ctx.textWidth("确定", .ui);
        cv.text(btn[0] + @divTrunc(btn[2] - lw, 2), ctx.centerBaseline(btn[1], btn[3], .ui), "确定", x.C_BLACK, .ui);
        cv.show();
        cv.flush();

        const ev = ctx.waitEvent(30);
        switch (ev) {
            .close, .button_down, .button_up => running = false,
            .key_down => |k| {
                if (k.keysym == x.Key.RETURN or k.keysym == x.Key.KP_ENTER or k.keysym == x.Key.ESCAPE) running = false;
            },
            else => {},
        }
    }
}

fn showBestScores() void {
    loadScores();
    const names = [_][]const u8{ "初级", "中级", "高级" };
    var buf: [512]u8 = undefined;
    var w = std.fmt.bufPrint(&buf, "三档纪录（秒）：\n", .{}) catch return;
    for (names, 0..) |n, i| {
        w = std.fmt.bufPrint(w, "{s}：{d}\n", .{ n, scores[i] }) catch return;
    }
    _ = std.fmt.bufPrint(w, "\n纪录保存在 ~/.config/complexweeper/scores.ini", .{}) catch {};
    runMessageBox("最高分纪录", buf[0..w.len]);
}

// ------------------------------------------------------------------ 命令
/// 返回 true = 退出程序。**只有「退出」该返回 true**，
/// 其余菜单项都只是改状态/弹对话框，返回 true 会让主循环立刻收摊（曾因此一点任何菜单项程序就没）。
fn handleCommand(id: usize) bool {
    switch (id) {
        IDM_NEW => {
            startNewGame(null);
        },
        IDM_BEGINNER => setPreset(0),
        IDM_INTERMEDIATE => setPreset(1),
        IDM_EXPERT => setPreset(2),
        IDM_CUSTOM => {
            if (runCustomDialog()) {
                game.newGame(x.nowMs());
                rebuildMain();
            }
        },
        IDM_BEST => showBestScores(),
        IDM_ZOOM1 => {
            zoom = 1;
            rebuildMain();
        },
        IDM_ZOOM2 => {
            zoom = 2;
            rebuildMain();
        },
        IDM_ZOOM3 => {
            zoom = 3;
            rebuildMain();
        },
        IDM_HELP_HOW => runMessageBox("玩法与操作", HELP_TEXT),
        IDM_HELP_ABOUT => runMessageBox("关于复扫雷", ABOUT_TEXT),
        IDM_EXIT => return true,
        else => {},
    }
    return false;
}

// ------------------------------------------------------------------ 鼠标
fn onLeftDown(px: i32, py: i32) void {
    const L = layout();
    if (py < MENU_H) {
        menu_bar_down = menuBarHit(px);
        if (menu_open >= 0) menu_hover = dropItemAt(px, py);
        return;
    }
    const gy = py - MENU_H;
    const on_face = inFace(L, px, gy);
    l_down = true;
    face_armed = on_face;
    face_down = on_face;
    const c = cellAt(L, px, gy);
    if (r_down) {
        chord_cell = c;
        press_cell = -1;
    } else {
        press_cell = if (c >= 0 and !on_face and !game.over and game.open[@intCast(c)] == 0) c else -1;
    }
}

fn onLeftUp(px: i32, py: i32) void {
    // 先把状态读进局部量（与 Windows 版同思路：状态要在清标志之前取）
    const held = press_cell;
    const chord = chord_cell;
    const was_face = face_armed;
    l_down = false;
    press_cell = -1;
    chord_cell = -1;
    face_down = false;
    face_armed = false;

    if (py < MENU_H) {
        const hit = menuBarHit(px);
        if (menu_bar_down >= 0 and hit == menu_bar_down) {
            menu_open = if (menu_open == hit) -1 else hit;
            menu_hover = -1;
            menu_bar_down = -1;
            if (menu_open >= 0) {
                main_canvas.grabPointer();
            } else {
                main_canvas.focus();
            }
        } else {
            menu_bar_down = -1;
        }
        return;
    }
    if (menu_open >= 0) {
        // 先把要选的项取出来，再收菜单（收菜单会把 menu_open 清掉）
        const mi: usize = @intCast(menu_open);
        const idx = dropItemAt(px, py);
        var pick: ?usize = null;
        if (idx >= 0 and idx < @as(i32, @intCast(MENUS[mi].items.len))) {
            const it = MENUS[mi].items[@intCast(idx)];
            if (it.id != 0) pick = it.id;
        }
        closeMenu(&main_canvas);
        if (pick) |id| {
            if (handleCommand(id)) quit_requested = true;
        }
        return;
    }

    const L = layout();
    const gy = py - MENU_H;
    if (was_face and inFace(L, px, gy)) {
        startNewGame(null);
        return;
    }
    if (chord >= 0) {
        if (cellAt(L, px, gy) == chord) doExpand(@intCast(chord));
        return;
    }
    if (held >= 0 and cellAt(L, px, gy) == held and !game.over and game.flag[@intCast(held)] == 0) {
        const c: usize = @intCast(held);
        const covered = game.open[c] == 0;
        if (!game.started) {
            game.startAt(c, x.nowMs());
            game.setMsg(.started);
        } else {
            game.reveal(c, x.nowMs());
            afterGameAction();
        }
        if (covered and !game.over) flashFace();
    }
}

fn onRightDown(px: i32, py: i32) void {
    if (py < MENU_H) return;
    if (menu_open >= 0) {
        closeMenu(&main_canvas);
        return;
    }
    r_down = true;
    const L = layout();
    const c = cellAt(L, px, py - MENU_H);
    if (l_down) {
        chord_cell = c;
        press_cell = -1;
        return;
    }
    if (c >= 0 and !game.over and game.open[@intCast(c)] == 0) {
        if (game.cycleFlag(@intCast(c))) flashFace();
    }
}

fn onRightUp(px: i32, py: i32) void {
    r_down = false;
    if (menu_open >= 0) return;
    const chord = chord_cell;
    if (chord >= 0) {
        const L = layout();
        chord_cell = -1;
        press_cell = -1;
        face_down = false;
        if (cellAt(L, px, py - MENU_H) == chord) doExpand(@intCast(chord));
    }
}

fn onMiddleDown(px: i32, py: i32) void {
    if (py < MENU_H) return;
    const L = layout();
    chord_cell = cellAt(L, px, py - MENU_H);
    press_cell = -1;
    m_down = true;
}

fn onMiddleUp(px: i32, py: i32) void {
    const L = layout();
    const chord = chord_cell;
    m_down = false;
    chord_cell = -1;
    face_down = false;
    if (chord >= 0 and cellAt(L, px, py - MENU_H) == chord) doExpand(@intCast(chord));
}

/// 返回 true 表示状态真的变了、需要重绘。鼠标移动是最频繁的事件，
/// 不做这个判断的话「鼠标在窗口里晃一下」就会把整个窗口重推一遍。
fn onMotion(px: i32, py: i32) bool {
    if (menu_open >= 0) {
        const idx = dropItemAt(px, py);
        // 跳过分隔线：高亮落到第一个非分隔项上
        const mi: usize = @intCast(menu_open);
        var hi = idx;
        if (hi >= 0 and MENUS[mi].items[@intCast(hi)].id == 0) {
            var k: i32 = hi;
            while (k < @as(i32, @intCast(MENUS[mi].items.len))) : (k += 1) {
                if (MENUS[mi].items[@intCast(k)].id != 0) {
                    hi = k;
                    break;
                }
            }
        }
        if (hi != menu_hover) {
            menu_hover = hi;
            return true;
        }
        return false;
    }
    const L = layout();
    if (chord_cell >= 0) {
        const next: i32 = cellAt(L, px, py - MENU_H);
        if (next != chord_cell) {
            chord_cell = next;
            return true;
        }
        return false;
    }
    if (press_cell < 0) return false;
    const next: i32 = cellAt(L, px, py - MENU_H);
    if (next != press_cell) {
        press_cell = next;
        return true;
    }
    return false;
}

// ------------------------------------------------------------------ main
pub fn main() void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    alloc = gpa.allocator();
    defer _ = gpa.deinit();

    // ---- 命令行 ----
    // 注意：argsAlloc 的内存随 argsFree 一起没了，所以这里必须复制一份
    var selftest_out: ?[]const u8 = null;
    {
        const args = std.process.argsAlloc(alloc) catch return;
        defer std.process.argsFree(alloc, args);
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const a = args[i];
            if (std.mem.eql(u8, a, "--selftest") and i + 1 < args.len) {
                i += 1;
                selftest_out = alloc.dupe(u8, args[i]) catch return;
            } else if (std.mem.eql(u8, a, "--version")) {
                printLine(APP_TITLE ++ " " ++ APP_VERSION ++ " (linux)");
                return;
            }
        }
    }

    // 规则自检不开窗口，直接出报告
    if (selftest_out) |p| {
        var out = std.ArrayList(u8).init(alloc);
        defer out.deinit();
        const code = selftest.run(&out);
        writeFileText(p, out.items);
        std.process.exit(@intCast(code));
    }

    if (!loadAtlas()) {
        printLine("内置图集损坏，无法启动。");
        return;
    }

    ctx = x.Ctx.init(alloc) catch |e| {
        printLine(switch (e) {
            x.Error.X11Unavailable => "打不开 X display。请在 X11 / XWayland 会话里运行（纯 Wayland 会话需要开 XWayland）。",
            x.Error.UnsupportedVisual => "当前 X 服务器不是 24/32 位 TrueColor，无法绘制。",
            else => "初始化 X11 失败。",
        });
        return;
    };
    defer ctx.deinit();

    // XSPY_TRACE=1 时把本机环境（visual 通道布局 / 有没有 WM / 是哪个 WM / 字体）
    // 一次打清楚。真机和容器差别都在这儿，猜是猜不出来的。
    x.reportEnvironment(&ctx);

    if (ctx.no_font) {
        printLine("找不到可用的界面字体（需要 fontconfig + 任意一款中文字体，例如 Noto Sans CJK 或文泉驿）。");
        return;
    }

    game.w = g.PRESETS[2].w;
    game.h = g.PRESETS[2].h;
    game.mines = g.PRESETS[2].mines;
    game.newGame(1);
    loadScores();

    // 建主窗口（尺寸随布局来）
    const L0 = layout();
    main_canvas = x.Canvas.create(
        &ctx,
        x.XRootWindow(ctx.dpy, ctx.screen),
        80,
        60,
        L0.client_w,
        MENU_H + L0.client_h,
        APP_TITLE,
        false,
    ) catch {
        printLine("创建窗口失败。");
        return;
    };

    // 窗口图标：取图集里那张 32×32
    var ibuf: [32 * 32 * 4]u8 = undefined;
    if (iconRGBA(&ibuf)) |ico| x.setIcon(&ctx, main_canvas.win, ico, 32);

    main_canvas.show();
    main_canvas.focus();
    // 记下窗口在屏幕上的实际位置：弹窗要贴着主窗口摆，而没有窗口管理器时
    // 不会来 CONFIGURE_NOTIFY，光靠事件更新的话位置会一直停在 0,0。
    if (x.windowRootPos(ctx.dpy, main_canvas.win)) |p| {
        win_sx = p.x;
        win_sy = p.y;
    }

    var last_tick: u32 = x.nowMs();
    var last_shown_sec: i32 = -1;
    var running = true;
    // 首帧必须整窗推
    main_canvas.invalidate();
    repaint();
    while (running) {
        // 事件驱动：没有事件就不重绘。以前这里是 repaint(); waitEvent(60);
        // 每秒 16 次整窗 XPutImage，在有 WM 的桌面上会让窗口持续损伤、
        // 标题栏图标跟着抖，Xft 的字也会闪。
        const ev = ctx.waitEvent(60);
        // 凡是可能改变画面的事件，处理完都要重绘一次。旧版本靠循环顶部
        // 无条件 repaint() 兜底，所以各处理函数里一个 repaint 都没有；
        // 改成事件驱动后必须在这里统一补上，否则点了格子界面不动。
        var need_repaint = false;
        switch (ev) {
            .none => {},
            .other, .map, .focus_in, .focus_out => {},
            .expose => {
                main_canvas.invalidate();
                need_repaint = true;
            },
            .close => running = false,
            .configure => |c| {
                win_sx = c.x;
                win_sy = c.y;
            },
            .key_down => |k| {
                if (menu_open >= 0) {
                    // 菜单打开时 Esc 收起
                    if (k.keysym == x.Key.ESCAPE) closeMenu(&main_canvas);
                    need_repaint = true;
                } else {
                    if (k.keysym == x.Key.F2) {
                        startNewGame(null);
                        need_repaint = true;
                    }
                }
            },
            .key_up => {},
            .motion => |m| {
                need_repaint = onMotion(m.x, m.y);
            },
            .button_down => |b| {
                switch (b.button) {
                    x.Button.LEFT => onLeftDown(b.x, b.y),
                    x.Button.RIGHT => onRightDown(b.x, b.y),
                    x.Button.MIDDLE => onMiddleDown(b.x, b.y),
                    else => {},
                }
                need_repaint = true;
            },
            .button_up => |b| {
                switch (b.button) {
                    x.Button.LEFT => onLeftUp(b.x, b.y),
                    x.Button.RIGHT => onRightUp(b.x, b.y),
                    x.Button.MIDDLE => onMiddleUp(b.x, b.y),
                    else => {},
                }
                need_repaint = true;
                if (quit_requested) running = false;
            },
        }
        if (need_repaint) repaint();

        // 计时器：每 250ms 刷一次计时值，但**只有秒数真的变了**才重绘。
        // 每秒 16 次整窗重画的旧写法是图标抖动和文字闪烁的根源。
        const now = x.nowMs();
        if (now -% last_tick >= 250) {
            last_tick = now;
            if (game.started and !game.over) {
                game.elapsed_ms = now -% game.t0;
                const sec = timerSeconds();
                if (sec != last_shown_sec) {
                    last_shown_sec = sec;
                    repaint();
                }
            }
            // 人脸「扫描」表情是定时恢复的（flashFace 设的到期时间），
            // 事件驱动之后没有事件就不会自己变回来，得在这里补一刀。
            if (face_flashing) {
                if (x.nowMs() >= face_flash_until) {
                    face_flashing = false;
                    repaint();
                } else {
                    // 闪烁期内还要保证到期后有人重画：把等待粒度缩到 FACE_FLASH_MS 内
                    last_tick = now - FACE_FLASH_MS + 30;
                }
            }
        }
    }

    main_canvas.destroy();
}

var quit_requested = false;

fn repaint() void {
    const L = layout();
    paintBoard(&main_canvas.surface, L, MENU_H);
    paintMenuBar(&main_canvas);
    main_canvas.flush();
}

fn printLine(s: []const u8) void {
    _ = std.posix.write(1, s) catch {};
    _ = std.posix.write(1, "\n") catch {};
}

fn writeFileText(path: []const u8, data: []const u8) void {
    const f = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return;
    defer f.close();
    f.writeAll(data) catch {};
}
