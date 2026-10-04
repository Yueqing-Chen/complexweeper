// 界面层自检：直接给窗口过程投递菜单命令与鼠标消息，验证输入→状态→布局这条链路。
// 由 main.zig 的 --uitest 调用。
const std = @import("std");
const w = @import("win32.zig");
const g = @import("game.zig");
const ui = @import("main.zig");

var checks: u32 = 0;
var fails: u32 = 0;

fn expect(out: *std.ArrayList(u8), cond: bool, name: []const u8) void {
    checks += 1;
    if (!cond) {
        fails += 1;
        out.writer().print("  [失败] {s}\n", .{name}) catch {};
    }
}

/// 辅助：在 (bx,by) 开局 → 把开局时刻回拨 backdate_ms → 点开所有非雷格
fn clearBoard(out: *std.ArrayList(u8), bx: i32, by: i32, backdate_ms: u32) void {
    _ = out;
    ui.testMouse(w.WM.LBUTTONDOWN, bx, by);
    ui.testMouse(w.WM.LBUTTONUP, bx, by);
    ui.testBackdate(backdate_ms);
    var guard: u32 = 0;
    while (guard < 4) : (guard += 1) {
        var done = true;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.mine[k] != 0 or ui.game_ptr.open[k] != 0) continue;
            const L = ui.testLayout();
            const mx = L.board_x + @as(i32, @intCast(k % ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
            const my = L.board_y + @as(i32, @intCast(k / ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
            ui.testMouse(w.WM.LBUTTONDOWN, mx, my);
            ui.testMouse(w.WM.LBUTTONUP, mx, my);
            if (ui.game_ptr.over) return;
            done = false;
        }
        if (done) return;
    }
}
/// 找一个"判据一定放行、邻域里还有非雷空格可翻"的已翻开数字格：按真值把邻域的雷插满旗。
/// 返回格子下标（-1 = 找不到）。7b/7c 用它保证展开真的会发生（不是"没格子可翻所以静默返回"）。
fn setupExpandable() i32 {
    for (0..ui.game_ptr.n) |k| {
        if (ui.game_ptr.open[k] == 0 or ui.game_ptr.mine[k] != 0) continue;
        var buf: [8]usize = undefined;
        const nk = ui.game_ptr.nbrs(k, &buf);
        var free_cells: u32 = 0;
        for (buf[0..nk]) |j| {
            if (ui.game_ptr.open[j] == 0 and ui.game_ptr.flag[j] == 0 and ui.game_ptr.mine[j] == 0) free_cells += 1;
        }
        if (free_cells == 0) continue;
        for (buf[0..nk]) |j| {
            if (ui.game_ptr.mine[j] != 0) {
                _ = ui.game_ptr.setFlag(j, ui.game_ptr.mine[j]);
            } else if (ui.game_ptr.flag[j] != 0) {
                _ = ui.game_ptr.setFlag(j, 0);
            }
        }
        if (ui.game_ptr.matchComboTruth(k)) return @intCast(k);
    }
    return -1;
}

/// 辅助：右键点一下（插旗在"按下"时生效，松开只是复位按键状态）
fn rightClick(x: i32, y: i32) void {
    ui.testMouse(w.WM.RBUTTONDOWN, x, y);
    ui.testMouse(w.WM.RBUTTONUP, x, y);
}
/// 辅助：中键点一下（按住只是预览，松手才展开）
fn middleClick(x: i32, y: i32) void {
    ui.testMouse(w.WM.MBUTTONDOWN, x, y);
    ui.testMouse(w.WM.MBUTTONUP, x, y);
}
/// 辅助：格子 -> 该格中心的客户区坐标
fn cellXY(L: ui.Layout, k: usize) [2]i32 {
    const w_: usize = ui.game_ptr.w;
    return .{
        L.board_x + @as(i32, @intCast(k % w_)) * L.cell + @divTrunc(L.cell, 2),
        L.board_y + @as(i32, @intCast(k / w_)) * L.cell + @divTrunc(L.cell, 2),
    };
}
/// UTF-16 码元 → UTF-8，用来核对对话框正文（都是 BMP 内的字，够用）
fn u16ToUtf8(buf: []u8, src: []const u16) []const u8 {
    const n = std.unicode.utf16LeToUtf8(buf, src) catch return "";
    return buf[0..n];
}
pub fn run(out: *std.ArrayList(u8)) u32 {
    checks = 0;
    fails = 0;
    ui.testScoresStopPersist(); // 全程静默：不写注册表、不弹结算窗
    const hwnd = ui.testWindow();
    if (hwnd == null) {
        out.writer().print("无法创建窗口\n", .{}) catch {};
        return 1;
    }
    out.writer().print("复扫雷 {s} · 界面自检（消息级）\n====================================\n", .{ui.testAppVersion}) catch {};

    // 0) 窗口标题：中文部分只有「复扫雷」，后面跟英文名
    {
        var wb: [256]u8 = undefined;
        const t = u16ToUtf8(&wb, ui.testWindowTitle());
        expect(out, std.mem.eql(u16, ui.testWindowTitle(), std.mem.span(ui.testAppTitle)), "窗口标题应与 APP_TITLE 一致");
        expect(out, std.mem.indexOf(u8, t, "复扫雷") != null, "标题里应有「复扫雷」");
        expect(out, std.mem.indexOf(u8, t, "复数扫雷") == null, "标题里不该再有「复数扫雷」");
        expect(out, std.mem.indexOf(u8, t, "Complexweeper") != null, "标题里应保留英文名 Complexweeper");
        expect(out, ui.testIconResourceOk(), "exe 里应有可加载的图标资源（.rsrc 的 16/32/48 三档）");
        out.writer().print("0 窗口标题：[{s}]\n", .{t}) catch {};
    }

    // 0b) 版本号：形状必须是 数字.数字.数字，而且「关于」正文里要带着它
    {
        const v = ui.testAppVersion;
        var dots: usize = 0;
        var ok = v.len >= 5;
        for (v) |ch| {
            if (ch == '.') {
                dots += 1;
            } else if (ch < '0' or ch > '9') {
                ok = false;
            }
        }
        expect(out, ok and dots == 2, "版本号应形如 1.0.1");
        var ab: [1024]u8 = undefined;
        const about = u16ToUtf8(&ab, std.mem.span(ui.testAboutText));
        expect(out, std.mem.indexOf(u8, about, v) != null, "「关于」正文里应带着版本号");
        // 程序名要中文名 + 英文名（和窗口标题同一个常量，改一处两边一起动）
        expect(out, std.mem.indexOf(u8, about, "复扫雷 Complexweeper") != null, "「关于」里的程序名应是「复扫雷 Complexweeper」");
        expect(out, std.mem.indexOf(u8, about, "Complexweeper") != null, "「关于」里应有英文名 Complexweeper");
        // 旗帜顺序那行说的是"旗"的名字（正实旗…），不是雷的名字
        var hb: [1024]u8 = undefined;
        const help = u16ToUtf8(&hb, std.mem.span(ui.testHelpText));
        expect(out, std.mem.indexOf(u8, help, "旗帜顺序为正实旗、负实旗、正虚旗、负虚旗") != null, "玩法里的旗帜顺序应是正实旗、负实旗、正虚旗、负虚旗");
        expect(out, std.mem.indexOf(u8, help, "旗帜顺序为正实雷") == null, "旗帜顺序不该再写成雷的名字");
        expect(out, std.mem.indexOf(u8, help, "分别是正实雷、负实雷、正虚雷、负虚雷") != null, "四种雷仍按雷的名字列（正实雷…）");
        expect(out, std.mem.indexOf(u8, help, "+1") == null and std.mem.indexOf(u8, help, "-1") == null, "玩法里不该出现 +1/−1 那套符号");
        out.writer().print("0b 版本号：[{s}] · 关于程序名：[复扫雷 Complexweeper]\n", .{v}) catch {};
    }

    // 1) 菜单：三档难度
    ui.testCommand(ui.test_IDM_BEGINNER);
    expect(out, ui.game_ptr.w == 9 and ui.game_ptr.h == 9 and ui.game_ptr.mines == 10, "初级菜单应切成 9×9/10");
    ui.testCommand(ui.test_IDM_INTERMEDIATE);
    expect(out, ui.game_ptr.w == 16 and ui.game_ptr.h == 16 and ui.game_ptr.mines == 40, "中级菜单应切成 16×16/40");
    ui.testCommand(ui.test_IDM_EXPERT);
    expect(out, ui.game_ptr.w == 30 and ui.game_ptr.h == 16 and ui.game_ptr.mines == 99, "高级菜单应切成 30×16/99");
    out.writer().print("1 难度菜单：通过\n", .{}) catch {};

    // 2) 菜单：缩放
    ui.testCommand(ui.test_IDM_ZOOM1);
    expect(out, ui.testZoom() == 1, "缩放菜单应切到 100%");
    ui.testCommand(ui.test_IDM_ZOOM3);
    expect(out, ui.testZoom() == 3, "缩放菜单应切到 300%");
    ui.testCommand(ui.test_IDM_ZOOM2);
    expect(out, ui.testZoom() == 2, "缩放菜单应切回 200%");
    // 菜单里真实挂了哪些命令：帮助下拉只剩「玩法与操作 / 分隔线 / 关于」
    expect(out, ui.testPopupCount(1) == 3, "帮助菜单应只剩 3 项（玩法与操作、分隔线、关于）");
    expect(out, ui.testMenuHasId(ui.test_IDM_HELP_HOW), "帮助菜单应有「玩法与操作」");
    expect(out, ui.testMenuHasId(ui.test_IDM_HELP_ABOUT), "帮助菜单应有「关于」");
    expect(out, !ui.testMenuHasId(ui.test_IDM_HELP_TABLE_REMOVED), "「显示值对照表」应从菜单里删掉");
    expect(out, ui.testMenuHasId(ui.test_IDM_BEST), "游戏菜单应有「最高分纪录」");
    out.writer().print("2 缩放菜单：通过\n", .{}) catch {};

    // 3) 鼠标：左键"按下只预览、松开才翻开"（传统扫雷的做法）
    const L = ui.testLayout();
    const cx = L.board_x + @as(i32, @intCast(ui.game_ptr.w / 2)) * L.cell + @divTrunc(L.cell, 2);
    const cy = L.board_y + @as(i32, @intCast(ui.game_ptr.h / 2)) * L.cell + @divTrunc(L.cell, 2);
    const mid_cell: usize = @as(usize, @intCast(ui.game_ptr.h / 2)) * ui.game_ptr.w + @as(usize, @intCast(ui.game_ptr.w / 2));
    ui.testMouse(w.WM.LBUTTONDOWN, cx, cy);
    expect(out, !ui.game_ptr.started, "只按下不该开局");
    expect(out, ui.game_ptr.open[mid_cell] == 0, "只按下不该翻开格子");
    expect(out, ui.testPressCell() == @as(i32, @intCast(mid_cell)), "按下应记下被按住的那一格");
    expect(out, ui.testCellSprite(mid_cell) == ui.testBlankSprite, "按住的那格应画成已翻开的空白");
    // 棋盘上按住不放 = "准备翻开"，人脸播「脸扫雷」（按下脸只属于人脸按钮）
    expect(out, !ui.testFaceDown(), "按棋盘不该换成按下脸");
    expect(out, ui.testFaceSpriteIsScan(), "按住棋盘准备翻开时应播「脸扫雷」");
    ui.testMouse(w.WM.LBUTTONUP, cx, cy);
    expect(out, ui.game_ptr.started, "松开后才开局");
    expect(out, ui.game_ptr.openedCount() >= 9, "开局应连片（≥9 格）");
    expect(out, ui.testPressCell() < 0, "松开后不该还有按住的格子");
    expect(out, !ui.testFaceDown(), "翻格前后都不该出现按下脸");
    // 翻开的一瞬间：脸放「脸扫雷」，闪完回普通
    expect(out, ui.testFaceSpriteIsScan(), "翻开时脸应闪一下「脸扫雷」");
    ui.testFaceFlashExpire();
    expect(out, !ui.testFaceSpriteIsScan(), "闪完应回到普通脸");
    out.writer().print("3 左键按下预览 / 松开翻开：翻开 {d} 格\n", .{ui.game_ptr.openedCount()}) catch {};

    // 3b) 拖到别的格子上再松手：翻开的是松手那一格；拖出棋盘则取消
    //     这两格都要挑"非雷"的：踩雷会把局面结束掉，后面整组插旗断言会连着崩（曾经每 6 次偶发一次）
    {
        var t1: i32 = -1;
        var t2: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.open[k] == 0 and ui.game_ptr.mine[k] == 0) {
                if (t1 < 0) t1 = @intCast(k) else if (t2 < 0) {
                    t2 = @intCast(k);
                    break;
                }
            }
        }
        expect(out, t1 >= 0 and t2 >= 0, "应能找到两个未翻开的非雷格");
        const p1 = cellXY(L, @intCast(t1));
        const p2 = cellXY(L, @intCast(t2));
        ui.testMouse(w.WM.LBUTTONDOWN, p1[0], p1[1]);
        expect(out, ui.testPressCell() == t1, "按下时应按住第一格");
        ui.testMouse(w.WM.MOUSEMOVE, p2[0], p2[1]);
        expect(out, ui.testPressCell() == t2, "拖到第二格后，按住预览应跟过去");
        expect(out, ui.testCellSprite(@intCast(t1)) == ui.testClosedSprite, "第一格应恢复成未翻开的样子");
        ui.testMouse(w.WM.LBUTTONUP, p2[0], p2[1]);
        expect(out, ui.game_ptr.open[@intCast(t2)] != 0, "松手的那一格应被翻开");
        // 拖出棋盘（表头区域）松手：什么都不该翻开
        var before: u32 = 0;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.open[k] != 0) before += 1;
        }
        var t3: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.open[k] == 0) {
                t3 = @intCast(k);
                break;
            }
        }
        if (t3 >= 0) {
            const p3 = cellXY(L, @intCast(t3));
            ui.testMouse(w.WM.LBUTTONDOWN, p3[0], p3[1]);
            ui.testMouse(w.WM.MOUSEMOVE, L.header_x + 4, L.header_y + 4);
            expect(out, ui.testPressCell() < 0, "拖出棋盘后不该还有按住的格子");
            ui.testMouse(w.WM.LBUTTONUP, L.header_x + 4, L.header_y + 4);
            var after: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) after += 1;
            }
            expect(out, after == before, "拖出棋盘松手不该翻开任何格子");
        }
        out.writer().print("3b 拖动预览 / 拖出取消：通过\n", .{}) catch {};
    }

    // 4) 鼠标：右键循环插旗；中键不再清旗（中键改成展开了，见第 7 组）
    //    先确认局面还在进行中：一旦结束了，插旗会被逻辑层拒绝，这一组会整片崩（看不出真正原因）
    expect(out, !ui.game_ptr.over, "第 4 组开始时局面应还在进行中");
    var closed: i32 = -1;
    for (0..ui.game_ptr.n) |k| {
        if (ui.game_ptr.open[k] == 0) {
            closed = @intCast(k);
            break;
        }
    }
    expect(out, closed >= 0, "应能找到未翻开的格子");
    const fx = L.board_x + @as(i32, @intCast(@as(usize, @intCast(closed)) % ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
    const fy = L.board_y + @as(i32, @intCast(@as(usize, @intCast(closed)) / ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
    rightClick(fx, fy);
    expect(out, ui.game_ptr.flag[@intCast(closed)] == 1, "右键第一次应插 +1 旗");
    expect(out, ui.testFaceSpriteIsScan(), "插旗时脸也应闪一下「脸扫雷」");
    expect(out, !ui.testFaceDown(), "插旗不该播按下脸");
    ui.testFaceFlashExpire();
    rightClick(fx, fy);
    expect(out, ui.game_ptr.flag[@intCast(closed)] == 2, "右键第二次应改成 −1 旗");
    expect(out, ui.game_ptr.flags_of[2] == 1 and ui.game_ptr.flags_of[1] == 0, "计数应跟着改");
    // 中键点在未翻开的格子上：既不翻格，也不能再动旗帜
    middleClick(fx, fy);
    expect(out, ui.game_ptr.flag[@intCast(closed)] == 2, "中键不应再清旗");
    expect(out, ui.game_ptr.flags_of[2] == 1 and ui.game_ptr.flags_of[1] == 0, "中键不应改动旗帜计数");
    expect(out, ui.game_ptr.open[@intCast(closed)] == 0, "中键点在未翻开格上不应翻开它");
    // 快速连点两下右键：第二下收到的是 DBLCLK 而不是 DOWN，也得走一步
    ui.testMouse(w.WM.RBUTTONDBLCLK, fx, fy);
    ui.testMouse(w.WM.RBUTTONUP, fx, fy);
    expect(out, ui.game_ptr.flag[@intCast(closed)] == 3, "连点的第二下（DBLCLK）也应循环旗帜");
    middleClick(fx, fy);
    expect(out, ui.game_ptr.flag[@intCast(closed)] == 3, "中键连点也不该动旗帜");
    rightClick(fx, fy); // −i → 空，收拾干净
    expect(out, ui.game_ptr.flag[@intCast(closed)] == 4, "第四次右键应到 −i");
    rightClick(fx, fy);
    expect(out, ui.game_ptr.flag[@intCast(closed)] == 0, "第五次右键应循环回空");
    out.writer().print("4 右键循环插旗（含连点）/ 中键不清旗：通过\n", .{}) catch {};

    // 4d) 计雷器：显示的是"这一类雷还剩几颗没标"，还要带上这一类雷自己的符号与单位。
    //     正实雷 → k，负实雷 → −k，正虚雷 → 三格数值 + 一格 i，负虚雷 → −数值 + 一格 i。
    {
        expect(out, !ui.game_ptr.over, "第 4d 组开始时局面应还在进行中");
        var t: usize = 1;
        while (t <= 4) : (t += 1) {
            const left: i32 = @as(i32, ui.game_ptr.type_total[t]) - @as(i32, ui.game_ptr.flags_of[t]);
            const want: i32 = switch (t) {
                2, 4 => -left,
                else => left,
            };
            expect(out, ui.testCounterValue(t) == want, "计雷器显示值 = 该类雷剩余颗数 × 该类雷的符号");
        }
        expect(out, !ui.testCounterImag(1) and !ui.testCounterImag(2), "实雷的计雷器不该带 i 单位格");
        expect(out, ui.testCounterImag(3) and ui.testCounterImag(4), "虚雷的计雷器应带 i 单位格");
        // 五块 LED 面板等宽：实雷与计时器是四格数字，虚雷是三格数字 + 一格 i，都是四格
        expect(out, ui.testCounterCells() == 4, "四个计雷器都应是四格");
        expect(out, ui.testCounterValueCells(1) == 4 and ui.testCounterValueCells(2) == 4, "实雷的第四格是真数字（四格数字），不是空 LED");
        expect(out, ui.testCounterValueCells(3) == 3 and ui.testCounterValueCells(4) == 3, "虚雷是三格数字，第四格留给 i");
        expect(out, ui.testTimerCells() == 4 and ui.testTimerValueCells() == 4, "计时器也是四格数字");
        expect(out, ui.testTimerWidth() == 4 * 13 * ui.testZoom() + 2 * ui.testZoom(), "计时器面板宽度按四格算");
        // 计雷器那一列必须待得下：左边留白 + 整列宽度不能顶出表头，也不能压到人脸
        {
            const L2 = ui.testLayout();
            const cx2 = L2.header_x + 4 * L2.z;
            expect(out, cx2 + ui.testCountersWidth() < L2.header_x + L2.header_w, "计雷器整列应落在表头里面");
            expect(out, cx2 + ui.testCountersWidth() < ui.testFaceX(), "计雷器整列不该压到人脸");
        }
        const before2 = ui.testCounterValue(2);
        const before1 = ui.testCounterValue(1);
        const before3 = ui.testCounterValue(3);
        const before4 = ui.testCounterValue(4);
        expect(out, before2 < 0 and before4 < 0, "负实雷与负虚雷的计雷器应是负数");
        expect(out, before1 >= 0 and before3 >= 0, "正实雷与正虚雷的计雷器不该是负数");
        var cf: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.open[k] == 0 and ui.game_ptr.flag[k] == 0) {
                cf = @intCast(k);
                break;
            }
        }
        expect(out, cf >= 0, "应能找到未翻开的空格子用来插旗");
        const pf = cellXY(ui.testLayout(), @intCast(cf));
        // 插旗顺序是 正实 → 负实 → 正虚 → 负虚 → 空；每插一面，只有它自己那一类的计雷器跟着走，
        // 而且走的方向由那一类的符号决定（负类的数字朝零去 = 变大，正类的数字变小）。
        rightClick(pf[0], pf[1]);
        expect(out, ui.game_ptr.flag[@intCast(cf)] == 1, "那格应插上 +1 旗");
        expect(out, ui.testCounterValue(1) == before1 - 1, "标一颗正实旗帜应让正实计雷器减 1");
        expect(out, ui.testCounterValue(2) == before2 and ui.testCounterValue(3) == before3 and ui.testCounterValue(4) == before4, "别的类的计雷器不该跟着动");
        rightClick(pf[0], pf[1]);
        expect(out, ui.game_ptr.flag[@intCast(cf)] == 2, "那格应改成 −1 旗");
        expect(out, ui.testCounterValue(2) == before2 + 1, "标一颗负实旗帜应让负实计雷器的数字增加 1（朝零走）");
        expect(out, ui.testCounterValue(1) == before1, "撤掉正实旗后正实计雷器应复原");
        rightClick(pf[0], pf[1]);
        expect(out, ui.game_ptr.flag[@intCast(cf)] == 3, "那格应改成 +i 旗");
        expect(out, ui.testCounterValue(3) == before3 - 1, "标一颗正虚旗帜应让正虚计雷器的数字减 1");
        expect(out, ui.testCounterValue(2) == before2, "撤掉负实旗后负实计雷器应复原");
        rightClick(pf[0], pf[1]);
        expect(out, ui.game_ptr.flag[@intCast(cf)] == 4, "那格应改成 −i 旗");
        expect(out, ui.testCounterValue(4) == before4 + 1, "标一颗负虚旗帜应让负虚计雷器的数字增加 1");
        expect(out, ui.testCounterValue(3) == before3, "撤掉正虚旗后正虚计雷器应复原");
        rightClick(pf[0], pf[1]);
        expect(out, ui.game_ptr.flag[@intCast(cf)] == 0, "循环一圈应回到空格");
        expect(out, ui.testCounterValue(4) == before4, "撤旗后负虚计雷器应回到原值");
        // 没开局时各类雷的颗数还没抽出来：整块面板画空格子（虚雷那格 i 也是空格子，不留白）
        ui.testCommand(ui.test_IDM_NEW);
        expect(out, !ui.game_ptr.started, "重开后应回到未开局");
        expect(out, ui.testCounterCells() == 4 and ui.testTimerCells() == 4, "未开局时计雷器与计时器仍是四格");
        expect(out, ui.testCounterValueCells(1) == 4 and ui.testTimerValueCells() == 4, "未开局时实雷与计时器画四格空格子");
        expect(out, ui.testCounterValueCells(3) == 3 and ui.testCounterValueCells(4) == 3, "未开局时虚雷画三格空格子，第四格 i 也画成空格子（计时空）");
        out.writer().print("4d 计雷器符号与 i 单位：通过\n", .{}) catch {};
    }

    // 4b) 开局前就能插旗（传统扫雷就是这样），而且这面旗要活过第一次左键
    {
        ui.testCommand(ui.test_IDM_NEW);
        expect(out, !ui.game_ptr.started, "重开后应回到未开局");
        var pre: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            pre = @intCast(k);
            break;
        }
        const ppre = cellXY(ui.testLayout(), @intCast(pre));
        rightClick(ppre[0], ppre[1]);
        expect(out, ui.game_ptr.flag[@intCast(pre)] == 1, "开局前右键也应插上旗");
        expect(out, ui.game_ptr.flags_of[1] == 1, "开局前的旗也要计数");
        // 换一格用左键开局，旗帜必须还在
        var start_k: usize = 0;
        const L0 = ui.testLayout();
        start_k = @as(usize, @intCast(ui.game_ptr.h)) * ui.game_ptr.w - 1;
        const ps = cellXY(L0, start_k);
        ui.testMouse(w.WM.LBUTTONDOWN, ps[0], ps[1]);
        ui.testMouse(w.WM.LBUTTONUP, ps[0], ps[1]);
        expect(out, ui.game_ptr.started, "左键松开应开局");
        expect(out, ui.game_ptr.flag[@intCast(pre)] == 1, "开局后旗帜应保留");
        expect(out, ui.game_ptr.flags_of[1] == 1, "开局后旗帜计数应保留");
        out.writer().print("4b 开局前插旗 / 活过开局：通过\n", .{}) catch {};
    }

    // 4c) 插了旗的格子左键打不开（传统扫雷：旗子保护它）；撤旗之后才开
    {
        var t: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.open[k] == 0 and ui.game_ptr.mine[k] == 0 and ui.game_ptr.flag[k] == 0) {
                t = @intCast(k);
                break;
            }
        }
        expect(out, t >= 0, "应能找到未翻开的非雷格");
        const p = cellXY(ui.testLayout(), @intCast(t));
        rightClick(p[0], p[1]);
        expect(out, ui.game_ptr.flag[@intCast(t)] == 1, "先给它插一面 +1 旗");
        ui.testMouse(w.WM.LBUTTONDOWN, p[0], p[1]);
        expect(out, ui.testPressCell() == t, "插旗格也能按下（按下时照样显示预览）");
        ui.testMouse(w.WM.LBUTTONUP, p[0], p[1]);
        expect(out, ui.game_ptr.open[@intCast(t)] == 0, "插了旗的格子左键翻不开");
        expect(out, ui.game_ptr.flag[@intCast(t)] == 1, "翻不开时旗子应原样保留");
        // 右键循环回"空"，再左键就该翻开
        rightClick(p[0], p[1]);
        rightClick(p[0], p[1]);
        rightClick(p[0], p[1]);
        rightClick(p[0], p[1]);
        expect(out, ui.game_ptr.flag[@intCast(t)] == 0, "四次右键应把旗循环回空");
        ui.testMouse(w.WM.LBUTTONDOWN, p[0], p[1]);
        ui.testMouse(w.WM.LBUTTONUP, p[0], p[1]);
        expect(out, ui.game_ptr.open[@intCast(t)] != 0, "撤旗之后左键就能翻开");
        out.writer().print("4c 旗子保护格子：通过\n", .{}) catch {};
    }

    // 5) 人脸：点一下重开
    const face_x = ui.testFaceX() + 13 * L.z;
    const face_y = ui.testFaceY() + 13 * L.z;
    ui.testMouse(w.WM.LBUTTONDOWN, face_x, face_y);
    expect(out, ui.testFaceDown(), "按在人脸上应显示按下脸");
    expect(out, ui.testFaceArmed(), "按在人脸上应记下『这次是从人脸按下的』");
    expect(out, ui.testFaceSpriteIsDown(), "按住时用的应是「脸按下」那张贴图");
    ui.testMouse(w.WM.LBUTTONUP, face_x, face_y);
    expect(out, !ui.game_ptr.started, "松开后应重开（回到未开局）");
    expect(out, !ui.testFaceDown(), "重开后脸应恢复正常");
    out.writer().print("5 人脸重开：通过\n", .{}) catch {};

    // 6) 键盘 F2
    ui.testMouse(w.WM.LBUTTONDOWN, cx, cy);
    ui.testMouse(w.WM.LBUTTONUP, cx, cy);
    expect(out, ui.game_ptr.started, "再开一局");
    _ = ui.testKey(0x72);
    expect(out, !ui.game_ptr.started, "F2 应重开（回到未开局）");
    out.writer().print("6 键盘 F2：通过\n", .{}) catch {};

    // 7) 展开：双击与中键是同一条路，判据不通过时都不能改变棋盘
    ui.testMouse(w.WM.LBUTTONDOWN, cx, cy);
    ui.testMouse(w.WM.LBUTTONUP, cx, cy);
    var target: i32 = -1;
    for (0..ui.game_ptr.n) |k| {
        if (ui.game_ptr.open[k] != 0 and ui.game_ptr.mine[k] == 0) {
            var buf: [8]usize = undefined;
            const nk = ui.game_ptr.nbrs(k, &buf);
            var uns: u32 = 0;
            for (buf[0..nk]) |j| {
                if (ui.game_ptr.open[j] == 0 and ui.game_ptr.flag[j] == 0) uns += 1;
            }
            if (uns > 0) {
                target = @intCast(k);
                break;
            }
        }
    }
    if (target >= 0) {
        const tx = L.board_x + @as(i32, @intCast(@as(usize, @intCast(target)) % ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
        const ty = L.board_y + @as(i32, @intCast(@as(usize, @intCast(target)) / ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
        const passed = ui.game_ptr.matchComboTruth(@intCast(target));
        // 邻域里"待会儿会被展开"的格子（未翻开、未插旗）
        var pending: [8]usize = undefined;
        var npending: usize = 0;
        {
            var nbuf: [8]usize = undefined;
            const nk = ui.game_ptr.nbrs(@intCast(target), &nbuf);
            for (nbuf[0..nk]) |j| {
                if (ui.game_ptr.open[j] == 0 and ui.game_ptr.flag[j] == 0) {
                    pending[npending] = j;
                    npending += 1;
                }
            }
        }

        // 7.1 左右键同时点击：按住时邻域显示空白预览，松手才展开
        {
            // 先只按左键：按棋盘（准备翻格）也不播按下脸
            ui.testMouse(w.WM.LBUTTONDOWN, tx, ty);
            expect(out, !ui.testFaceDown(), "按棋盘（准备翻格）不该播按下脸");
            expect(out, ui.testFaceSpriteIsScan(), "按住棋盘准备翻开时应播「脸扫雷」");
            ui.testMouse(w.WM.RBUTTONDOWN, tx, ty);
            expect(out, ui.testChordCell() == target, "左右键同时按下应记下展开目标");
            expect(out, !ui.testFaceDown(), "左右键同时按住时更不该播按下脸");
            expect(out, ui.testFaceSpriteIsScan(), "左右键同时按住（准备展开）应播「脸扫雷」");
            var all_preview = true;
            for (pending[0..npending]) |j| {
                if (ui.testCellSprite(j) != ui.testBlankSprite) all_preview = false;
            }
            expect(out, all_preview, "按住期间待展开的邻格应显示空白贴图");
            expect(out, ui.testCellSprite(@intCast(target)) != ui.testBlankSprite, "展开目标自己不该变成空白格");
            var before_open: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) before_open += 1;
            }
            ui.testMouse(w.WM.RBUTTONUP, tx, ty);
            expect(out, ui.testChordCell() < 0, "松手后展开预览应清掉");
            var after_open: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) after_open += 1;
            }
            if (passed) {
                expect(out, after_open >= before_open + npending, "判据通过时左右键同时应展开邻域");
                expect(out, ui.game_ptr.msg == .expand_ok, "左右键同时展开成功应给出 expand_ok 枚举");
                expect(out, ui.testFaceSpriteIsScan(), "展开成功应闪一下「脸扫雷」");
                ui.testFaceFlashExpire();
            } else {
                expect(out, after_open == before_open, "判据不通过时左右键同时不能改变棋盘");
                expect(out, ui.game_ptr.msg == .judge_fail, "判据不通过时应给出判据枚举");
            }
            out.writer().print("7 左右键同时展开：判据{s}，翻开 {d} → {d}\n", .{ if (passed) "通过" else "不通过", before_open, after_open }) catch {};
        }

        // 7.2 中键：也是"按住预览、松手才展开"
        if (!ui.game_ptr.over) {
            var before_open: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) before_open += 1;
            }
            ui.testMouse(w.WM.MBUTTONDOWN, tx, ty);
            expect(out, ui.testChordCell() == target, "中键按住应记下展开目标");
            expect(out, !ui.testFaceDown(), "中键按住不该播按下脸");
            expect(out, ui.testFaceSpriteIsScan(), "中键按住（准备展开）应播「脸扫雷」");
            var after_open_mid: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) after_open_mid += 1;
            }
            expect(out, after_open_mid == before_open, "中键只按下还没松开时不该展开");
            ui.testMouse(w.WM.MBUTTONUP, tx, ty);
            expect(out, ui.testChordCell() < 0, "中键松手后预览应清掉");
            var after_open: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) after_open += 1;
            }
            expect(out, after_open >= before_open, "中键松手后应展开");
            ui.testFaceFlashExpire();
            out.writer().print("7 中键展开（松手才生效）：翻开 {d} → {d}\n", .{ before_open, after_open }) catch {};
        }

        // 7.3 双击不再是展开触发器：第二下只算"按下"，松手什么都不做
        {
            var before_open: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) before_open += 1;
            }
            ui.testMouse(w.WM.LBUTTONDBLCLK, tx, ty);
            ui.testMouse(w.WM.LBUTTONUP, tx, ty);
            var after_open: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) after_open += 1;
            }
            expect(out, after_open == before_open, "双击不该再展开（触发改成了左右键同时/中键）");
            out.writer().print("7 双击不再展开：通过\n", .{}) catch {};
        }
    }

    // 7b) 判据确实通过时，两条展开路径都要真把格子翻开（别只证明"不动棋盘"）
    if (!ui.game_ptr.over) {
        // 7b.1 左右键同时点击
        const t2: i32 = setupExpandable();
        if (t2 >= 0) {
            var before2: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) before2 += 1;
            }
            const t2x = L.board_x + @as(i32, @intCast(@as(usize, @intCast(t2)) % ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
            const t2y = L.board_y + @as(i32, @intCast(@as(usize, @intCast(t2)) / ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
            ui.testMouse(w.WM.LBUTTONDOWN, t2x, t2y);
            ui.testMouse(w.WM.RBUTTONDOWN, t2x, t2y);
            ui.testMouse(w.WM.RBUTTONUP, t2x, t2y);
            ui.testMouse(w.WM.LBUTTONUP, t2x, t2y);
            var after2: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) after2 += 1;
            }
            expect(out, ui.game_ptr.matchComboTruth(@intCast(t2)), "按真值插旗后判据应通过");
            expect(out, after2 > before2, "判据通过时左右键同时点击应真的翻开格子");
            expect(out, ui.game_ptr.msg == .expand_ok, "左右键同时展开成功应给出 expand_ok 枚举");
            out.writer().print("7b 左右键同时展开（判据通过）：翻开 {d} → {d}\n", .{ before2, after2 }) catch {};
        }
        // 7b.2 中键：同一套判据路径，换个目标再来一次
        var t3: i32 = -1;
        if (!ui.game_ptr.over) t3 = setupExpandable();
        if (t3 >= 0) {
            var before3: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) before3 += 1;
            }
            const t3x = L.board_x + @as(i32, @intCast(@as(usize, @intCast(t3)) % ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
            const t3y = L.board_y + @as(i32, @intCast(@as(usize, @intCast(t3)) / ui.game_ptr.w)) * L.cell + @divTrunc(L.cell, 2);
            middleClick(t3x, t3y);
            var after3: u32 = 0;
            for (0..ui.game_ptr.n) |k| {
                if (ui.game_ptr.open[k] != 0) after3 += 1;
            }
            expect(out, after3 > before3, "判据通过时中键应真的翻开格子");
            expect(out, ui.game_ptr.msg == .expand_ok, "中键展开成功应给出 expand_ok 枚举");
            out.writer().print("7b 中键展开（判据通过）：翻开 {d} → {d}\n", .{ before3, after3 }) catch {};
        }
    }

    // 8) 版式：棋盘必须完整落在客户区内
    {
        const L2 = ui.testLayout();
        expect(out, L2.board_x >= L2.frame and L2.board_y >= L2.header_y + L2.header_h, "棋盘不能在框外");
        expect(out, L2.board_x + @as(i32, @intCast(ui.game_ptr.w)) * L2.cell + L2.box <= L2.client_w - L2.frame, "棋盘右边不能越界");
        expect(out, L2.frame + L2.pad + ui.game_ptr.h * L2.cell + L2.box + L2.gap <= L2.client_h, "棋盘下边不能越界");
        out.writer().print("8 版式边界：通过\n", .{}) catch {};
    }

    // 9) 自定义雷区对话框：校验与生效。
    //    注意：菜单里的"自定义…"会进入模态消息循环，自检不能走那条路，直接用钩子建窗口。
    {
        expect(out, ui.testOpenDialog(), "自定义对话框应能创建");
        expect(out, ui.testEditValue(0) == @as(i32, ui.game_ptr.h) and ui.testEditValue(1) == @as(i32, ui.game_ptr.w),
            "对话框应预填当前尺寸");
        // 文案：四种雷按"正实雷/负实雷/正虚雷/负虚雷"命名，"四种雷各自的颗数（…）"那行已删
        {
            var tb2: [2048]u8 = undefined;
            const labels = u16ToUtf8(&tb2, ui.testDialogTexts());
            expect(out, std.mem.indexOf(u8, labels, "正实雷") != null, "对话框应有「正实雷」");
            expect(out, std.mem.indexOf(u8, labels, "负实雷") != null, "对话框应有「负实雷」");
            expect(out, std.mem.indexOf(u8, labels, "正虚雷") != null, "对话框应有「正虚雷」");
            expect(out, std.mem.indexOf(u8, labels, "负虚雷") != null, "对话框应有「负虚雷」");
            expect(out, std.mem.indexOf(u8, labels, "各自的颗数") == null, "「四种雷各自的颗数」那行应删掉");
            expect(out, std.mem.indexOf(u8, labels, "+1 正实") == null and std.mem.indexOf(u8, labels, "−1 负实") == null,
                "标签里不该再带 +1/−1 前缀");
            // 白底：静态标签拿到的背景刷子必须是那块白刷子（否则空白标签会画出一条白条）
            expect(out, ui.testDialogBgBrushIsWhite(), "静态标签的背景应是白色刷子");
            out.writer().print("9 对话框文案与白底：{s}\n", .{labels}) catch {};
        }
        // 高度越界
        ui.testSetEdit(0, 99);
        _ = ui.testApplyDialog();
        expect(out, std.mem.eql(u8, ui.testDialogErrName(), "height"), "高度 99 应报 height");
        expect(out, !ui.testDialogDone(), "校验不过时对话框不应关闭");
        {
            // 错误提示要真的写进那个 STATIC（白底黑字，位置上就在"按合计均分"右边）
            var tb4: [2048]u8 = undefined;
            const labels4 = u16ToUtf8(&tb4, ui.testDialogTexts());
            expect(out, std.mem.indexOf(u8, labels4, "高度要在") != null, "校验失败时错误提示应出现在对话框里");
        }
        // 合计为 0
        ui.testSetEdit(0, 12);
        ui.testSetEdit(1, 12);
        ui.testSetEdit(2, 0);
        ui.testSetEdit(3, 0);
        ui.testSetEdit(4, 0);
        ui.testSetEdit(5, 0);
        _ = ui.testApplyDialog();
        expect(out, std.mem.eql(u8, ui.testDialogErrName(), "sum_zero"), "合计 0 应报 sum_zero");
        // 合计超过 格数-9
        ui.testSetEdit(2, 200);
        _ = ui.testApplyDialog();
        expect(out, std.mem.eql(u8, ui.testDialogErrName(), "sum_big"), "合计超上限应报 sum_big");
        // 均分按钮
        ui.testSetEdit(2, 0);
        ui.testSplitClick();
        const a1 = ui.testEditValue(2);
        const a2 = ui.testEditValue(3);
        const a3 = ui.testEditValue(4);
        const a4 = ui.testEditValue(5);
        expect(out, a1 + a2 + a3 + a4 == 99, "均分应按当前合计（99）平摊");
        expect(out, a1 >= 24 and a1 <= 25 and a4 >= 24 and a4 <= 25, "均分结果应尽量平均");
        // 合法：12×12，只有 −1 与 −i
        ui.testSetEdit(0, 12);
        ui.testSetEdit(1, 12);
        ui.testSetEdit(2, 0);
        ui.testSetEdit(3, 7);
        ui.testSetEdit(4, 0);
        ui.testSetEdit(5, 7);
        expect(out, ui.testApplyDialog(), "合法输入应通过并按新配置重开");
        expect(out, std.mem.eql(u8, ui.testDialogErrName(), "none"), "合法输入不应报错");
        expect(out, ui.game_ptr.w == 12 and ui.game_ptr.h == 12 and ui.game_ptr.mines == 14, "应切成 12×12/14");
        expect(out, ui.game_ptr.type_count[2] == 7 and ui.game_ptr.type_count[4] == 7, "配比应写入");
        ui.testCloseDialog();
        // 真开一局，确认配比落到棋盘上
        const L3 = ui.testLayout();
        const c3x = L3.board_x + 6 * L3.cell + @divTrunc(L3.cell, 2);
        const c3y = L3.board_y + 6 * L3.cell + @divTrunc(L3.cell, 2);
        ui.testMouse(w.WM.LBUTTONDOWN, c3x, c3y);
        ui.testMouse(w.WM.LBUTTONUP, c3x, c3y);
        expect(out, ui.game_ptr.type_total[1] == 0 and ui.game_ptr.type_total[3] == 0, "纯实+纯虚之外的两类应为 0");
        expect(out, ui.game_ptr.type_total[2] == 7 and ui.game_ptr.type_total[4] == 7, "实际配比应等于请求");
        out.writer().print("9 自定义对话框：校验/均分/生效 通过\n", .{}) catch {};
    }

    // 10) 整局：用消息接口把非雷格全部翻开 → 胜利 + 胜利脸
    {
        ui.testCommand(ui.test_IDM_BEGINNER);
        const L4 = ui.testLayout();
        var started = false;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.mine[k] != 0) continue;
            const mx = L4.board_x + @as(i32, @intCast(k % ui.game_ptr.w)) * L4.cell + @divTrunc(L4.cell, 2);
            const my = L4.board_y + @as(i32, @intCast(k / ui.game_ptr.w)) * L4.cell + @divTrunc(L4.cell, 2);
            ui.testMouse(w.WM.LBUTTONDOWN, mx, my);
            ui.testMouse(w.WM.LBUTTONUP, mx, my);
            started = true;
            if (ui.game_ptr.over) break;
        }
        expect(out, started and ui.game_ptr.win and ui.game_ptr.over, "翻开所有非雷格必须判胜");
        expect(out, ui.testFaceSpriteIsWin(), "胜利后应换成胜利脸");
        expect(out, ui.game_ptr.openedCount() == ui.game_ptr.safeCount(), "非雷格应全部翻开");
        // 胜利后雷区彻底不再响应：按下也不压格、不换脸
        var t: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.open[k] == 0) {
                t = @intCast(k);
                break;
            }
        }
        if (t >= 0) {
            const p = cellXY(ui.testLayout(), @intCast(t));
            ui.testMouse(w.WM.LBUTTONDOWN, p[0], p[1]);
            expect(out, ui.testPressCell() < 0, "胜利后按下不该再压住格子");
            expect(out, !ui.testFaceDown(), "胜利后按棋盘不该再换脸");
            ui.testMouse(w.WM.LBUTTONUP, p[0], p[1]);
            expect(out, ui.testFaceSpriteIsWin(), "胜利后点棋盘仍是胜利脸");
        }
        out.writer().print("10 整局通关：胜利脸 + 全部翻开 + 结束后不响应 通过\n", .{}) catch {};
    }

    // 11) 整局：踩雷 → 死亡脸 + 记录踩中格
    {
        ui.testCommand(ui.test_IDM_BEGINNER);
        const L5 = ui.testLayout();
        // 棋盘是第一次点击时才生成的，所以先开局
        const mid_x = L5.board_x + 2 * L5.cell + @divTrunc(L5.cell, 2);
        const mid_y = L5.board_y + 2 * L5.cell + @divTrunc(L5.cell, 2);
        ui.testMouse(w.WM.LBUTTONDOWN, mid_x, mid_y);
        ui.testMouse(w.WM.LBUTTONUP, mid_x, mid_y);
        expect(out, ui.game_ptr.started, "应先开局");
        var mine_cell: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.mine[k] != 0) {
                mine_cell = @intCast(k);
                break;
            }
        }
        expect(out, mine_cell >= 0, "开局后应能找到雷格");
        const mx2 = L5.board_x + @as(i32, @intCast(@as(usize, @intCast(mine_cell)) % ui.game_ptr.w)) * L5.cell + @divTrunc(L5.cell, 2);
        const my2 = L5.board_y + @as(i32, @intCast(@as(usize, @intCast(mine_cell)) / ui.game_ptr.w)) * L5.cell + @divTrunc(L5.cell, 2);
        ui.testMouse(w.WM.LBUTTONDOWN, mx2, my2);
        ui.testMouse(w.WM.LBUTTONUP, mx2, my2);
        expect(out, ui.game_ptr.over and !ui.game_ptr.win, "点雷应判负");
        expect(out, ui.game_ptr.boom == mine_cell, "应记录踩中的格子");
        expect(out, ui.testFaceSpriteIsDead(), "失败后应换成死亡脸");
        expect(out, ui.testCellSprite(@intCast(mine_cell)) != 0, "踩中的格子应有贴图");
        // 失败后雷区也彻底不再响应（按下不压格、右键不再插旗）
        var t2: i32 = -1;
        for (0..ui.game_ptr.n) |k| {
            if (ui.game_ptr.open[k] == 0) {
                t2 = @intCast(k);
                break;
            }
        }
        if (t2 >= 0) {
            const p2 = cellXY(ui.testLayout(), @intCast(t2));
            ui.testMouse(w.WM.LBUTTONDOWN, p2[0], p2[1]);
            expect(out, ui.testPressCell() < 0, "失败后按下不该再压住格子");
            expect(out, !ui.testFaceDown(), "失败后按棋盘不该再换脸");
            ui.testMouse(w.WM.LBUTTONUP, p2[0], p2[1]);
            const before_flag = ui.game_ptr.flag[@intCast(t2)];
            rightClick(p2[0], p2[1]);
            expect(out, ui.game_ptr.flag[@intCast(t2)] == before_flag, "失败后右键不该再改旗帜");
            expect(out, ui.testFaceSpriteIsDead(), "失败后点棋盘仍是死亡脸");
        }
        out.writer().print("11 踩雷结算：死亡脸 + 记录踩中格 + 结束后不响应 通过\n", .{}) catch {};

        // 结束后按人脸按钮 = "准备重开"：这时才播按下脸，松开就重开
        {
            const fpx = ui.testFaceX() + 13 * L.z;
            const fpy = ui.testFaceY() + 13 * L.z;
            ui.testMouse(w.WM.LBUTTONDOWN, fpx, fpy);
            expect(out, ui.testFaceDown(), "结束后按人脸按钮应播按下脸（准备重开）");
            expect(out, ui.testFaceSpriteIsDown(), "结束后按人脸按钮用的应是「脸按下」贴图");
            ui.testMouse(w.WM.LBUTTONUP, fpx, fpy);
            expect(out, !ui.game_ptr.over, "松开人脸按钮应重开一局");
            out.writer().print("11b 结束后按人脸重开：按下脸 → 松开重开 通过\n", .{}) catch {};
        }
    }



    // 12) 最高分纪录：三档各记一个最快用时；慢的不覆盖快的；自定义不计入
    {
        ui.testScoresStopPersist(); // 别往用户注册表里写测试数据
        ui.testSetScores(0, 0, 0);

        // 12.1 初级通关，用时 50 秒 → 记下 50
        ui.testCommand(ui.test_IDM_BEGINNER);
        const L6 = ui.testLayout();
        const bx = L6.board_x + 2 * L6.cell + @divTrunc(L6.cell, 2);
        const by = L6.board_y + 2 * L6.cell + @divTrunc(L6.cell, 2);
        clearBoard(out, bx, by, 50_000);
        expect(out, ui.game_ptr.win, "初级应通关");
        var tbuf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&tbuf, "初级纪录应记为 50 秒，实际 {d}", .{ui.testGetScore(0)}) catch "初级纪录不对";
        expect(out, ui.testGetScore(0) == 50, msg);

        // 12.2 再来一局，用时 80 秒（更慢）→ 纪录不动
        ui.testCommand(ui.test_IDM_BEGINNER);
        clearBoard(out, bx, by, 80_000);
        expect(out, ui.game_ptr.win, "第二局也应通关");
        expect(out, ui.testGetScore(0) == 50, "更慢的用时不应覆盖纪录");

        // 12.3 更快的一局 20 秒 → 覆盖
        ui.testCommand(ui.test_IDM_BEGINNER);
        clearBoard(out, bx, by, 20_000);
        expect(out, ui.testGetScore(0) == 20, "更快的用时应覆盖纪录");

        // 12.4 自定义棋盘不计入纪录
        ui.testSetScores(7, 8, 9);
        _ = ui.testOpenDialog();
        ui.testSetEdit(0, 12);
        ui.testSetEdit(1, 12);
        ui.testSetEdit(2, 0);
        ui.testSetEdit(3, 5);
        ui.testSetEdit(4, 0);
        ui.testSetEdit(5, 5);
        _ = ui.testApplyDialog();
        expect(out, ui.game_ptr.w == 12, "自定义应生效");
        const L7 = ui.testLayout();
        const cx7 = L7.board_x + 6 * L7.cell + @divTrunc(L7.cell, 2);
        const cy7 = L7.board_y + 6 * L7.cell + @divTrunc(L7.cell, 2);
        clearBoard(out, cx7, cy7, 5_000);
        expect(out, ui.game_ptr.win, "自定义盘也应能通关");
        expect(out, ui.testGetScore(0) == 7 and ui.testGetScore(1) == 8 and ui.testGetScore(2) == 9,
            "自定义棋盘不应写入任何纪录");
        out.writer().print("12 最高分纪录：记账/不覆盖/自定义不计入 通过\n", .{}) catch {};

        // 12.5 弹窗正文：只有三行，除三档纪录之外一个字都没有
        ui.testSetScores(12, 0, 340);
        var tb: [512]u8 = undefined;
        const s = u16ToUtf8(&tb, ui.testScoresText());
        expect(out, std.mem.count(u8, s, "\r\n") == 3, "纪录窗应正好三行");
        expect(out, std.mem.startsWith(u8, s, "初级"), "第一行应是初级");
        expect(out, std.mem.indexOf(u8, s, "中级") != null, "应有中级");
        expect(out, std.mem.indexOf(u8, s, "高级") != null, "应有高级");
        expect(out, std.mem.indexOf(u8, s, "12 秒") != null, "初级应显示 12 秒");
        expect(out, std.mem.indexOf(u8, s, "340 秒") != null, "高级应显示 340 秒");
        expect(out, std.mem.indexOf(u8, s, "———") != null, "没纪录的档应给占位符，不该显示 0 秒");
        expect(out, std.mem.indexOf(u8, s, "9×9") == null and std.mem.indexOf(u8, s, "雷") == null, "纪录窗不该再带棋盘尺寸/雷数");
        expect(out, std.mem.indexOf(u8, s, "自定义") == null, "纪录窗不该再提自定义棋盘");
        expect(out, std.mem.indexOf(u8, s, "HKEY") == null and std.mem.indexOf(u8, s, "注册表") == null, "纪录窗不该再写存档位置");
        expect(out, std.mem.indexOf(u8, s, "新纪录") == null, "纪录窗正文里不该再带「新纪录」标记（只在标题里）");
        out.writer().print("12.5 纪录窗正文：\n{s}", .{s}) catch {};
    }

    out.writer().print("\n断言 {d} 项，失败 {d} 项\n", .{ checks, fails }) catch {};
    out.writer().print("{s}\n", .{if (fails == 0) "全部通过" else "存在失败"}) catch {};
    return fails;
}
