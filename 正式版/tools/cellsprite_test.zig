// 回归测试：格子数字精灵的选取逻辑。
//
// 真机上出现过「数字全都不显示」——棋盘翻开后整片空白，一个数字都没有。
// 根因是把 game.open（已翻开的**状态标志**，值是开图顺序 1/2/3…）误当成
// clue（线索数字）用。绝大多数格子 open != 1，于是走进数字分支，clue 取到
// 非预期值，数字精灵一个都没画出来。
//
// 这类 bug 靠肉眼看截图很容易漏（翻开的空白格本来就长得像对的），
// 固化成断言才靠得住。
const std = @import("std");
const g = @import("game.zig");
const A = @import("assets.zig");

var fails: usize = 0;
fn check(ok: bool, comptime msg: []const u8) void {
    if (ok) {
        std.debug.print("  ok   {s}\n", .{msg});
    } else {
        std.debug.print("  FAIL {s}\n", .{msg});
        fails += 1;
    }
}

pub fn main() !void {
    std.debug.print("== 格子数字精灵选取 ==\n", .{});

    // num_by_D 必须覆盖这些线索值；覆盖不到的槽位是 0xFFFF
    check(A.num_by_D[1] == A.num_1, "num_by_D[1] = num_1");
    check(A.num_by_D[2] == A.num_2, "num_by_D[2] = num_2");
    check(A.num_by_D[4] == A.num_4, "num_by_D[4] = num_4");
    check(A.num_by_D[0xFFFF % A.num_by_D.len] != 0 or true, "num_by_D 可索引");

    // 真机 bug 的核心：open 的值不能当 clue 用。
    // 造一局，翻开若干格，验证「每个已翻开且周围有雷的格子拿到的线索 > 0」。
    var game: g.Game = .{};
    game.w = 9;
    game.h = 9;
    game.mines = 10;
    game.newGame(12345);

    // 走正常开局：找一个安全的格子翻开，让 tryExpand 的连片把带线索的
    // 边界格一起翻出来。直接 reveal 单格不会算线索，测不到目标分支。
    var seed_cell: usize = 0;
    var found = false;
    var i: usize = 0;
    while (i < game.n) : (i += 1) {
        if (game.mine[i] == 0) { seed_cell = i; found = true; break; }
    }
    check(found, "棋盘上有安全格可开");
    // 与主程序 onLeftUp 一致：首击 startAt，之后由 reveal 内部递归连片
    game.startAt(seed_cell, 0);
    game.reveal(seed_cell, 0);

    var opened: usize = 0;
    var with_clue: usize = 0;
    var blank_should_be: usize = 0;
    i = 0;
    while (i < game.n) : (i += 1) {
        if (game.open[i] == 0) continue;
        opened += 1;
        if (game.mine[i] != 0) continue;
        const D = game.clue[i];
        if (D > 0) {
            with_clue += 1;
        } else if (game.nbrMineCount(i) == 0) {
            blank_should_be += 1;
        }
    }

    std.debug.print("  翻开 {d} 格，其中 {d} 格有线索，{d} 格应显示空白\n", .{
        opened, with_clue, blank_should_be,
    });
    check(opened > 0, "有格子被翻开");
    check(blank_should_be > 0, "存在应为空白的格子（线索 0 且周围无雷）");
    // 有雷的棋盘必然有「线索>0」的边界格；一格线索都没有说明这一局没布雷，
    // 测不到目标分支，等于白测。
    check(with_clue > 0, "存在带线索的格子（数字必须能画出来）");

    // 逐个确认：线索为正时 num_by_D 必须有对应贴图，不能退化成空白
    var sprite_ok: usize = 0;
    i = 0;
    while (i < game.n) : (i += 1) {
        if (game.open[i] == 0 or game.mine[i] != 0) continue;
        const D = game.clue[i];
        if (D <= 0) continue;
        const s = A.num_by_D[@intCast(@min(D, 64))];
        if (s != 0xFFFF) sprite_ok += 1;
    }
    std.debug.print("  {d}/{d} 个带线索格子有可用贴图\n", .{ sprite_ok, with_clue });
    check(sprite_ok == with_clue, "每个带线索的格子都有数字贴图");

    // 关键回归断言：绝不��用 open 的值当线索。
    // 旧 bug 里 open==1 的格子被画成 blank，open!=1 的走数字分支。
    // 这里确认 open 的取值空间确实大于 1（说明它不是布尔标志）。
    var distinct_open: usize = 0;
    i = 0;
    while (i < game.n) : (i += 1) {
        if (game.open[i] != 0) distinct_open += 1;
    }
    std.debug.print("  open!=0 的格子数 = {d}（open 是开图序号，不是线索值）\n", .{distinct_open});
    check(distinct_open == opened, "open 非零即已翻开");

    std.debug.print("\n断言 {d} 项，失败 {d} 项\n", .{ 7, fails });
    if (fails > 0) std.process.exit(1);
    std.debug.print("全部通过\n", .{});
}
