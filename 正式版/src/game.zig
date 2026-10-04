// 复扫雷 · 规则与状态。这一层不碰任何 Win32，方便单独自检。
const std = @import("std");

pub const MAX_W: usize = 40;
pub const MAX_H: usize = 30;
pub const MAX_CELLS: usize = MAX_W * MAX_H;
pub const MAX_MINES: usize = 999;

/// 四种雷：(a,b) 分别是实部与虚部的贡献
pub const TYPES = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
/// 只可能出现的 24 个显示值 D = |S|^2
pub const ACHIEVABLE = [24]u16{ 0, 1, 2, 4, 5, 8, 9, 10, 13, 16, 17, 18, 20, 25, 26, 29, 32, 34, 36, 37, 40, 49, 50, 64 };

pub const Preset = struct { w: u16, h: u16, mines: u16, label: []const u8 };
/// 标准三档（类型随机撒）
pub const PRESETS = [3]Preset{
    .{ .w = 9, .h = 9, .mines = 10, .label = "初级 9×9 · 10 雷" },
    .{ .w = 16, .h = 16, .mines = 40, .label = "中级 16×16 · 40 雷" },
    .{ .w = 30, .h = 16, .mines = 99, .label = "高级 30×16 · 99 雷" },
};

/// 状态行文字（逻辑层只给枚举，文案在界面层）
pub const Msg = enum(u8) {
    none = 0,
    started,
    judge_fail,
    expand_ok,
    win,
    lose,
};

/// mulberry32：与 demo/archive.js 完全一致，同种子同棋盘
pub const Rng = struct {
    a: u32,
    pub fn init(seed: u32) Rng {
        return .{ .a = if (seed == 0) 1 else seed };
    }
    pub fn next(self: *Rng) f64 {
        self.a +%= 0x6D2B79F5;
        var t: u32 = self.a;
        t = (t ^ (t >> 15)) *% (t | 1);
        t ^= t +% ((t ^ (t >> 7)) *% (t | 61));
        return @as(f64, @floatFromInt((t ^ (t >> 14)))) / 4294967296.0;
    }
    /// [0, n) 的整数
    pub fn below(self: *Rng, n: usize) usize {
        if (n == 0) return 0;
        return @intFromFloat(self.next() * @as(f64, @floatFromInt(n)));
    }
};

pub const Game = struct {
    w: u16 = 9,
    h: u16 = 9,
    n: usize = 81,
    mine: [MAX_CELLS]u8 = [_]u8{0} ** MAX_CELLS,
    clue: [MAX_CELLS]i16 = [_]i16{-1} ** MAX_CELLS,
    open: [MAX_CELLS]u8 = [_]u8{0} ** MAX_CELLS,
    flag: [MAX_CELLS]u8 = [_]u8{0} ** MAX_CELLS,
    seed: u32 = 1,
    rng: Rng = Rng.init(1),
    mines: u16 = 10,
    /// 各类雷的总数（下标 1..4），开局公开
    type_total: [5]u16 = [_]u16{0} ** 5,
    /// 当前插了各类旗几面
    flags_of: [5]u16 = [_]u16{0} ** 5,
    /// 自定义配比（下标 1..4）；全 0 表示"类型随机撒"
    type_count: [5]u16 = [_]u16{0} ** 5,
    started: bool = false,
    over: bool = false,
    win: bool = false,
    boom: i32 = -1,
    start_cell: i32 = -1,
    elapsed_ms: u32 = 0,
    t0: u32 = 0,
    moves: u32 = 0,
    /// 上一次操作的反馈（文案在界面层）
    msg: Msg = .none,
    /// 附加数字（例如展开格数），0 表示无
    msg_arg: u16 = 0,

    pub fn cellCount(self: *const Game) usize {
        return self.n;
    }

    pub fn inb(self: *const Game, r: i32, c: i32) bool {
        return r >= 0 and c >= 0 and r < self.h and c < self.w;
    }

    /// 8 邻域，写到 buf 里，返回个数
    pub fn nbrs(self: *const Game, cell: usize, buf: *[8]usize) usize {
        const w: i32 = self.w;
        const r: i32 = @intCast(cell / self.w);
        const c: i32 = @intCast(cell % self.w);
        var k: usize = 0;
        var dr: i32 = -1;
        while (dr <= 1) : (dr += 1) {
            var dc: i32 = -1;
            while (dc <= 1) : (dc += 1) {
                if (dr == 0 and dc == 0) continue;
                const rr = r + dr;
                const cc = c + dc;
                if (rr < 0 or cc < 0 or rr >= self.h or cc >= self.w) continue;
                buf[k] = @intCast(rr * w + cc);
                k += 1;
            }
        }
        return k;
    }

    pub fn nbrMineCount(self: *const Game, cell: usize) usize {
        var buf: [8]usize = undefined;
        const k = self.nbrs(cell, &buf);
        var n: usize = 0;
        for (buf[0..k]) |j| {
            if (self.mine[j] != 0) n += 1;
        }
        return n;
    }

    /// 空白格：邻域一颗雷都没有。只有它会连片展开
    pub fn isBlank(self: *const Game, cell: usize) bool {
        return self.mine[cell] == 0 and self.nbrMineCount(cell) == 0;
    }

    pub fn flagsTotal(self: *const Game) usize {
        var s: usize = 0;
        for (1..5) |t| s += self.flags_of[t];
        return s;
    }

    /// 该类雷还有几颗没标（可以是负数）
    pub fn unmarked(self: *const Game, t: usize) i32 {
        return @as(i32, self.type_total[t]) - @as(i32, self.flags_of[t]);
    }

    pub fn setMsg(self: *Game, m: Msg) void {
        self.msg = m;
        self.msg_arg = 0;
    }

    // ---------------------------------------------------------------- 生成
    pub fn setSeed(self: *Game, s: u32) void {
        self.seed = if (s == 0) 1 else s;
        self.rng = Rng.init(self.seed);
    }

    /// 新开一局（未开局状态，棋盘等第一次点击时再生成）
    pub fn newGame(self: *Game, seed: u32) void {
        self.n = @as(usize, self.w) * @as(usize, self.h);
        for (0..self.n) |i| {
            self.mine[i] = 0;
            self.clue[i] = -1;
            self.open[i] = 0;
            self.flag[i] = 0;
        }
        self.started = false;
        self.over = false;
        self.win = false;
        self.boom = -1;
        self.start_cell = -1;
        self.elapsed_ms = 0;
        self.t0 = 0;
        self.moves = 0;
        self.type_total = [_]u16{0} ** 5;
        self.flags_of = [_]u16{0} ** 5;
        self.setSeed(seed);
        self.setMsg(.none);
    }

    /// 布雷 + 算显示值 + 从开局格连片。safe = 开局格及其（界内）8 邻居。
    pub fn genBoard(self: *Game, start_cell: usize) void {
        const N = self.n;
        for (0..N) |i| {
            self.mine[i] = 0;
            self.clue[i] = -1;
            self.open[i] = 0;
            // 注意：这里**不动 flag[]**。开局前插的旗要活过第一次左键
            // （传统扫雷就是这样）；清旗由 newGame() 负责，那里 flag 与 flags_of 一起归零。
        }
        var is_safe = [_]bool{false} ** MAX_CELLS;
        is_safe[start_cell] = true;
        var nbuf: [8]usize = undefined;
        const nk = self.nbrs(start_cell, &nbuf);
        for (nbuf[0..nk]) |j| is_safe[j] = true;

        var pool: [MAX_CELLS]usize = undefined;
        var m: usize = 0;
        for (0..N) |i| {
            if (!is_safe[i]) {
                pool[m] = i;
                m += 1;
            }
        }
        // 洗位置
        if (m > 1) {
            var i: usize = m - 1;
            while (i > 0) : (i -= 1) {
                const j = self.rng.below(i + 1);
                const t = pool[i];
                pool[i] = pool[j];
                pool[j] = t;
            }
        }
        var want: usize = 0;
        for (1..5) |t| want += self.type_count[t];
        const count = @min(if (want > 0) want else @as(usize, self.mines), m);

        if (want > 0) {
            // 精确配比：先铺类型序列，再洗一遍
            var list: [MAX_CELLS]u8 = undefined;
            var ln: usize = 0;
            for (1..5) |t| {
                var k: usize = 0;
                while (k < self.type_count[t]) : (k += 1) {
                    list[ln] = @intCast(t);
                    ln += 1;
                }
            }
            if (ln > count) ln = count;
            if (ln > 1) {
                var i: usize = ln - 1;
                while (i > 0) : (i -= 1) {
                    const j = self.rng.below(i + 1);
                    const t = list[i];
                    list[i] = list[j];
                    list[j] = t;
                }
            }
            for (0..ln) |k| self.mine[pool[k]] = list[k];
        } else {
            for (0..count) |k| self.mine[pool[k]] = @intCast(1 + self.rng.below(4));
        }
        self.mines = @intCast(count);
        self.computeClues();
        self.countTypes();
        // 这里既不碰 flag[] 也不碰 flags_of：开局前插的旗（以及它的计数）要留到开局之后。
        _ = self.cascadeOpen(&[_]usize{start_cell});
    }

    pub fn computeClues(self: *Game) void {
        for (0..self.n) |i| {
            if (self.mine[i] != 0) {
                self.clue[i] = -1;
                continue;
            }
            var a: i32 = 0;
            var b: i32 = 0;
            var buf: [8]usize = undefined;
            const k = self.nbrs(i, &buf);
            for (buf[0..k]) |j| {
                // 必须跳过空邻居：mine[j]==0 时 TYPES[mine[j]-1] 会越界读到垃圾，
                // 把显示值算错（这个 bug 一度因为越界正好读到 0 而"看起来正常"）
                if (self.mine[j] == 0) continue;
                const t = TYPES[self.mine[j] - 1];
                a += t[0];
                b += t[1];
            }
            self.clue[i] = @intCast(a * a + b * b);
        }
    }

    pub fn countTypes(self: *Game) void {
        self.type_total = [_]u16{0} ** 5;
        for (0..self.n) |i| {
            if (self.mine[i] != 0) self.type_total[self.mine[i]] += 1;
        }
    }

    /// 连片翻开：只在空白格上继续扩散。返回新翻开的格数。
    pub fn cascadeOpen(self: *Game, seeds: []const usize) usize {
        var stack: [MAX_CELLS]usize = undefined;
        var sp: usize = 0;
        for (seeds) |s| {
            if (sp < stack.len) {
                stack[sp] = s;
                sp += 1;
            }
        }
        var opened: usize = 0;
        while (sp > 0) {
            sp -= 1;
            const i = stack[sp];
            // 连片也不碰插了旗的格子（传统扫雷：旗子保护它，得玩家自己撤旗）
            if (self.open[i] != 0 or self.mine[i] != 0 or self.flag[i] != 0) continue;
            self.open[i] = 1;
            opened += 1;
            if (self.isBlank(i)) {
                var buf: [8]usize = undefined;
                const k = self.nbrs(i, &buf);
                for (buf[0..k]) |j| {
                    if (self.open[j] == 0 and self.mine[j] == 0 and self.flag[j] == 0 and sp < stack.len) {
                        stack[sp] = j;
                        sp += 1;
                    }
                }
            }
        }
        return opened;
    }

    // ---------------------------------------------------------------- 操作
    pub fn startAt(self: *Game, cell: usize, now_ms: u32) void {
        self.setSeed(self.seed);
        self.genBoard(cell);
        self.start_cell = @intCast(cell);
        self.started = true;
        self.over = false;
        self.win = false;
        self.elapsed_ms = 0;
        self.t0 = now_ms;
        self.moves = 1;
        self.setMsg(.none);
    }

    /// 插/改/清旗。旗帜不限量，永远成功
    pub fn setFlag(self: *Game, cell: usize, t: u8) bool {
        if (t > 4) return false;
        const old = self.flag[cell];
        if (old == t) return true;
        if (old != 0) self.flags_of[old] -= 1;
        self.flag[cell] = t;
        if (t != 0) self.flags_of[t] += 1;
        return true;
    }

    /// 右键循环：空 → +1 → −1 → +i → −i → 空
    pub fn cycleFlag(self: *Game, cell: usize) bool {
        if (self.over or self.open[cell] != 0) return false;
        const next: u8 = @intCast((@as(usize, self.flag[cell]) + 1) % 5);
        _ = self.setFlag(cell, next);
        self.moves += 1;
        return true;
    }

    /// 翻开一格。**插了旗的格子翻不开**（传统扫雷：旗子保护它）——要翻开得先用右键把旗循环回"空"。
    pub fn reveal(self: *Game, cell: usize, now_ms: u32) void {
        _ = now_ms;
        if (self.over or self.open[cell] != 0 or self.flag[cell] != 0) return;
        if (self.mine[cell] != 0) {
            self.open[cell] = 1;
            self.lose(cell);
            return;
        }
        self.open[cell] = 1;
        if (self.isBlank(cell)) {
            var buf: [8]usize = undefined;
            const k = self.nbrs(cell, &buf);
            _ = self.cascadeOpen(buf[0..k]);
        }
        self.moves += 1;
        self.checkWin();
    }

    /// 组合匹配（严档，现行默认）：旗帜总数 = 邻域真实雷总数，且实/虚旗数
    /// 与真实实/虚雷数一致（顺序不限）
    pub fn matchComboTruth(self: *const Game, cell: usize) bool {
        var truth = [4]u16{ 0, 0, 0, 0 };
        var got = [4]u16{ 0, 0, 0, 0 };
        var buf: [8]usize = undefined;
        const k = self.nbrs(cell, &buf);
        for (buf[0..k]) |j| {
            if (self.mine[j] != 0) truth[self.mine[j] - 1] += 1;
            if (self.flag[j] != 0) got[self.flag[j] - 1] += 1;
        }
        const P = truth[0] + truth[1];
        const V = truth[2] + truth[3];
        const gp = got[0] + got[1];
        const gv = got[2] + got[3];
        return (gp + gv == P + V) and ((gp == P and gv == V) or (gp == V and gv == P));
    }

    /// 双击展开：判据通过就翻开周围未插旗的格（可能踩雷）
    pub fn tryExpand(self: *Game, cell: usize) void {
        if (self.over or self.open[cell] == 0 or self.mine[cell] != 0) return;
        var buf: [8]usize = undefined;
        const k = self.nbrs(cell, &buf);
        var uns: [8]usize = undefined;
        var un: usize = 0;
        for (buf[0..k]) |j| {
            if (self.open[j] == 0 and self.flag[j] == 0) {
                uns[un] = j;
                un += 1;
            }
        }
        if (un == 0) return;
        if (!self.matchComboTruth(cell)) {
            self.setMsg(.judge_fail);
            return;
        }
        var boom: i32 = -1;
        for (uns[0..un]) |j| {
            if (self.mine[j] != 0) {
                boom = @intCast(j);
                break;
            }
        }
        if (boom >= 0) {
            const b: usize = @intCast(boom);
            self.open[b] = 1;
            self.lose(b);
            return;
        }
        _ = self.cascadeOpen(uns[0..un]);
        self.moves += 1;
        self.msg_arg = @intCast(un);
        self.setMsg(.expand_ok);
        self.checkWin();
    }

    pub fn checkWin(self: *Game) void {
        for (0..self.n) |i| {
            if (self.mine[i] == 0 and self.open[i] == 0) return;
        }
        self.over = true;
        self.win = true;
        self.setMsg(.win);
    }

    pub fn lose(self: *Game, cell: usize) void {
        self.over = true;
        self.win = false;
        self.boom = @intCast(cell);
        self.setMsg(.lose);
    }

    pub fn openedCount(self: *const Game) usize {
        var k: usize = 0;
        for (0..self.n) |i| {
            if (self.open[i] != 0) k += 1;
        }
        return k;
    }

    pub fn safeCount(self: *const Game) usize {
        var k: usize = 0;
        for (0..self.n) |i| {
            if (self.mine[i] == 0) k += 1;
        }
        return k;
    }

    pub fn correctFlags(self: *const Game) usize {
        var k: usize = 0;
        for (0..self.n) |i| {
            if (self.mine[i] != 0 and self.flag[i] == self.mine[i]) k += 1;
        }
        return k;
    }

    /// 精确定义下的合法配比（供自检用）：各类雷数之和 = 总雷数
    pub fn typeSum(self: *const Game) usize {
        var s: usize = 0;
        for (1..5) |t| s += self.type_total[t];
        return s;
    }
};

/// 把总数尽量均匀分给四种雷（自定义对话框的预填值）
pub fn splitEvenly(total: u16) [5]u16 {
    var out = [_]u16{0} ** 5;
    const base = total / 4;
    var rest = total - base * 4;
    for (1..5) |t| {
        out[t] = base;
        if (rest > 0) {
            out[t] += 1;
            rest -= 1;
        }
    }
    return out;
}
