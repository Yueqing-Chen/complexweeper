// 验证帧缓冲通道布局的自适应逻辑。
//
// 背景：同样是 24 位 TrueColor，Xvfb/多数服务器是 R=0xff0000（内存 BGRA），
// 而有些桌面是 R=0xff（内存 RGBA）。以前掩码写死成 0xff0000，在后一种机器上
// 红蓝互换 —— 灰色格子看不出来，红色 LED 数字会变成蓝色、在黑底上几乎看不见。
//
// 这里不依赖特定 X server：直接拿两种布局各跑一遍 blit，检查内存里字节的落位。
const std = @import("std");
const x11 = @import("../src/x11.zig");

var fails: usize = 0;
fn check(ok: bool, comptime msg: []const u8) void {
    if (ok) {
        std.debug.print("  ok   {s}\n", .{msg});
    } else {
        std.debug.print("  FAIL {s}\n", .{msg});
        fails += 1;
    }
}

/// 造一个 4x4 的"图集"：一个不透明的纯红像素 (BGRA: B=0,G=0,R=255,A=255)
fn redAtlas() [4 * 4 * 4]u8 {
    var a = [_]u8{0} ** (4 * 4 * 4);
    for (0..16) |i| {
        a[i * 4 + 0] = 0; // B
        a[i * 4 + 1] = 0; // G
        a[i * 4 + 2] = 255; // R
        a[i * 4 + 3] = 255; // A
    }
    return a;
}

fn firstPixel(sf: *x11.Surface) [3]u8 {
    const o = 0;
    return .{ sf.px[o], sf.px[o + 1], sf.px[o + 2] };
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const atlas = redAtlas();

    std.debug.print("== 通道布局自适应 ==\n", .{});

    // ---- 情形一：visual 是 BGRA（R 在高位，Xvfb / 多数服务器）----
    {
        var sf = try x11.Surface.create(alloc, 4, 4, false);
        defer sf.destroy(alloc);
        // 先铺成黑色，模拟 LED 的黑底
        sf.fillAll(.{ .r = 0, .g = 0, .b = 0 });
        sf.blit(&atlas, 4, 4, 0, 0, 4, 4, 0, 0, 4, 4);
        const p = firstPixel(&sf);
        std.debug.print("  BGRA 布局: 内存字节 = [{d} {d} {d}]\n", .{ p[0], p[1], p[2] });
        check(p[0] == 0 and p[1] == 0 and p[2] == 255, "BGRA: byte2 存 R=255");
    }

    // ---- 情形二：visual 是 RGBA（R 在低位）----
    {
        var sf = try x11.Surface.create(alloc, 4, 4, true);
        defer sf.destroy(alloc);
        sf.fillAll(.{ .r = 0, .g = 0, .b = 0 });
        sf.blit(&atlas, 4, 4, 0, 0, 4, 4, 0, 0, 4, 4);
        const p = firstPixel(&sf);
        std.debug.print("  RGBA 布局: 内存字节 = [{d} {d} {d}]\n", .{ p[0], p[1], p[2] });
        check(p[0] == 255 and p[1] == 0 and p[2] == 0, "RGBA: byte0 存 R=255");
    }

    // ---- 灰色在两种布局下都应是 (192,192,192)：灰色三通道相等，不该被换位影响 ----
    {
        var g = [_]u8{0} ** (4 * 4 * 4);
        for (0..16) |i| {
            g[i * 4 + 0] = 192; // B
            g[i * 4 + 1] = 192; // G
            g[i * 4 + 2] = 192; // R
            g[i * 4 + 3] = 255;
        }
        var s1 = try x11.Surface.create(alloc, 4, 4, false);
        defer s1.destroy(alloc);
        s1.blit(&g, 4, 4, 0, 0, 4, 4, 0, 0, 4, 4);
        var s2 = try x11.Surface.create(alloc, 4, 4, true);
        defer s2.destroy(alloc);
        s2.blit(&g, 4, 4, 0, 0, 4, 4, 0, 0, 4, 4);
        const a = firstPixel(&s1);
        const b = firstPixel(&s2);
        check(a[0] == 192 and a[1] == 192 and a[2] == 192, "灰色在 BGRA 下正确");
        check(b[0] == 192 and b[1] == 192 and b[2] == 192, "灰色在 RGBA 下也正确");
    }

    // ---- 半透明混合也要跟着布局走 ----
    {
        // 50% alpha 的红，混到黑底上 => (128,0,0)
        var a2 = [_]u8{0} ** (4 * 4 * 4);
        for (0..16) |i| {
            a2[i * 4 + 0] = 0; // B
            a2[i * 4 + 1] = 0; // G
            a2[i * 4 + 2] = 255; // R
            a2[i * 4 + 3] = 128; // A
        }
        var s1 = try x11.Surface.create(alloc, 4, 4, false);
        defer s1.destroy(alloc);
        s1.fillAll(.{ .r = 0, .g = 0, .b = 0 });
        s1.blit(&a2, 4, 4, 0, 0, 4, 4, 0, 0, 4, 4);
        const p1 = firstPixel(&s1);
        check(p1[0] == 0 and p1[1] == 0 and p1[2] == 128, "BGRA 半透明: byte2=128");

        var s2 = try x11.Surface.create(alloc, 4, 4, true);
        defer s2.destroy(alloc);
        s2.fillAll(.{ .r = 0, .g = 0, .b = 0 });
        s2.blit(&a2, 4, 4, 0, 0, 4, 4, 0, 0, 4, 4);
        const p2 = firstPixel(&s2);
        check(p2[0] == 128 and p2[1] == 0 and p2[2] == 0, "RGBA 半透明: byte0=128");
    }

    // ---- Color.packFor 与掩码判定一致 ----
    {
        const red = x11.Color{ .r = 0xFF, .g = 0, .b = 0 };
        const bgra = red.packFor(false);
        const rgba = red.packFor(true);
        check(@as(u8, @truncate(bgra)) == 0 and @as(u8, @truncate(bgra >> 16)) == 0xFF, "packFor(false) 红色落在 byte2");
        check(@as(u8, @truncate(rgba)) == 0xFF and @as(u8, @truncate(rgba >> 16)) == 0, "packFor(true) 红色落在 byte0");
    }

    std.debug.print("\n断言 {d} 项，失败 {d} 项\n", .{ 7, fails });
    if (fails > 0) std.process.exit(1);
    std.debug.print("全部通过\n", .{});
}
