// Linux 版的后端：手写的 X11 + Xft 绑定，配一个软件帧缓冲。
//
// 和 win32.zig 同样的思路：只声明本程序用得到的那部分，不引入任何第三方包。
// 文字走 Xft（fontconfig 挑系统字体，中文靠用户机器上已有的 Noto CJK / 文泉驿，
// 不往 AppImage 里塞 20MB 字体）；图形全部自己画进软件帧缓冲，再用 XPutImage 一次送上去。
//
// 分两层：
//   Ctx    —— 一个 X display + 一套字体，被主窗口和所有对话框共用
//   Canvas —— 一个窗口 + 它自己的帧缓冲 + 待画文字队列；主窗口是一个，弹窗再各开一个
//
// 依赖：libX11 / libXft / libfontconfig（都是 Linux 桌面的基础库）。
const std = @import("std");

// ------------------------------------------------------------------ 基础类型
// Xlib/Xft 的这些句柄本质都是指针，直接用指针表示：
// opaque{} 不能当 extern 返回类型，也没法内嵌进结构体。
pub const Display = *anyopaque;
pub const Visual = *const anyopaque;
pub const GC = *anyopaque;
pub const Font = *anyopaque;
pub const FcPattern = *anyopaque;
pub const FcConfig = *anyopaque;
pub const FcCharSet = *anyopaque;
pub const XftDraw = *anyopaque;

pub const XID = c_ulong;
pub const VisualID = c_ulong;
pub const Window = XID;
pub const Drawable = XID;
pub const Colormap = XID;
pub const Atom = XID;
pub const FcChar32 = u32;
pub const FcBool = c_int;

// ------------------------------------------------------------------ Xlib 绑定
pub extern "X11" fn XOpenDisplay(?[*:0]const u8) ?*Display;
pub extern "X11" fn XCloseDisplay(*Display) c_int;
/// XGetVisualInfo 返回的数组必须用 XFree 释放（Xlib 自己的分配器，不是 libc free）
pub extern "X11" fn XFree(?*anyopaque) c_int;
pub extern "X11" fn XDefaultScreen(*Display) c_int;
pub extern "X11" fn XRootWindow(*Display, c_int) Window;
pub extern "X11" fn XDefaultVisual(*Display, c_int) ?*const Visual;
/// Visual 是不透明指针，要拿它的 XID 只能问服务端。
/// **只 1 个参数**——没有 Display（Xlib.h 的签名和多数 X 函数不一样，ABI 对账会抓到）。
pub extern "X11" fn XVisualIDFromVisual(?*const Visual) VisualID;
pub extern "X11" fn XDefaultDepth(*Display, c_int) c_int;
pub extern "X11" fn XDefaultColormap(*Display, c_int) Colormap;
pub extern "X11" fn XDefaultGC(*Display, c_int) GC;
pub extern "X11" fn XConnectionNumber(*Display) c_int;
pub extern "X11" fn XDisplayWidth(*Display, c_int) c_int;
pub extern "X11" fn XDisplayHeight(*Display, c_int) c_int;

pub extern "X11" fn XCreateSimpleWindow(
    *Display, Window, c_int, c_int, c_uint, c_uint, c_uint, c_ulong, c_ulong,
) Window;
/// 12 个参数，末尾就是 valuemask + attributes，没有 depth/copy_depth
pub extern "X11" fn XCreateWindow(
    *Display, Window, c_int, c_int, c_uint, c_uint, c_uint, c_int,
    c_uint, ?*const Visual, c_ulong, ?*const anyopaque,
) Window;
pub extern "X11" fn XDestroyWindow(*Display, Window) c_int;
pub extern "X11" fn XMapWindow(*Display, Window) c_int;
pub extern "X11" fn XMapRaised(*Display, Window) c_int;
pub extern "X11" fn XUnmapWindow(*Display, Window) c_int;
pub extern "X11" fn XStoreName(*Display, Window, [*:0]const u8) c_int;
pub extern "X11" fn XSetIconName(*Display, Window, [*:0]const u8) c_int;
pub extern "X11" fn XSelectInput(*Display, Window, c_long) c_int;
pub extern "X11" fn XNextEvent(*Display, ?*anyopaque) c_int;
pub extern "X11" fn XPending(*Display) c_int;
pub extern "X11" fn XFlush(*Display) c_int;
pub extern "X11" fn XGetWindowAttributes(*Display, Window, *XWindowAttributes) c_int;
/// Xlib.h 的真实签名是 **11 个参数**，末尾 prop_return 是 unsigned char**。
/// 后五个是纯出参，必须给指针（不能给 null，服务端无条件往里写）。
pub extern "X11" fn XGetWindowProperty(
    *Display, Window, Atom, c_long, c_long, c_int, Atom,
    ?*Atom, ?*c_int, ?*c_ulong, ?*c_ulong, ?*[*]u8,
) c_int;
/// 3 个参数。设一个实体背景像素：背景为 None 时，某些合成器/服务器会在
/// 特定时刻把窗口当成未定义内容（露底/透明），设成跟界面同色最稳。
pub extern "X11" fn XSetWindowBackground(*Display, Window, c_ulong) c_int;
/// 4 个参数。**第 4 个是 `int*` 出参不是入参**——传常量 1 会让服务端往常量/栈上写数量，
/// 直接踩坏栈（实测段错误）。mask 传 VisualNoMask 时只按 template 里的 visual 指针匹配。
pub extern "X11" fn XGetVisualInfo(*Display, c_long, ?*XVisualInfo, ?*c_int) ?*XVisualInfo;
pub extern "X11" fn XGetGeometry(*Display, Drawable, ?*Window, ?*c_int, ?*c_int, ?*c_uint, ?*c_uint, ?*c_uint, ?*c_uint) c_int;
pub extern "X11" fn XTranslateCoordinates(*Display, Drawable, Drawable, c_int, c_int, ?*c_int, ?*c_int, ?*Window) c_int;
pub extern "X11" fn XSync(*Display, c_int) c_int;
pub extern "X11" fn XInternAtom(*Display, [*:0]const u8, c_int) Atom;
pub extern "X11" fn XSetWMProtocols(*Display, Window, [*]const Atom, c_int) c_int;
pub extern "X11" fn XSetWMNormalHints(*Display, Window, *XSizeHints) c_int;
pub extern "X11" fn XSetWMHints(*Display, Window, *XWMHints) c_int;
pub extern "X11" fn XMoveResizeWindow(*Display, Window, c_int, c_int, c_uint, c_uint) c_int;
pub extern "X11" fn XResizeWindow(*Display, Window, c_uint, c_uint) c_int;
pub extern "X11" fn XClearWindow(*Display, Window) c_int;
pub extern "X11" fn XChangeProperty(
    *Display, Drawable, Atom, Atom, c_int, c_int, ?*const anyopaque, c_int,
) c_int;
/// 10 个参数，format 是 XImage 自己的字段，不在这里再传一遍
pub extern "X11" fn XPutImage(
    *Display, Drawable, GC, *XImage, c_int, c_int, c_int, c_int, c_uint, c_uint,
) c_int;
pub extern "X11" fn XLookupKeysym(*XKeyEventZ, c_int) c_ulong;
pub extern "X11" fn XSetInputFocus(*Display, Window, c_int, c_ulong) c_int;
pub extern "X11" fn XRaiseWindow(*Display, Window) c_int;
/// 9 个参数：末尾那个 time 少写了会把 cursor 挤到 time 槽里
pub extern "X11" fn XGrabPointer(
    *Display, Window, c_int, c_uint, c_int, c_int, XID, c_ulong, c_ulong,
) c_int;
pub extern "X11" fn XUngrabPointer(*Display, c_ulong) c_int;
pub extern "X11" fn XAllowEvents(*Display, c_int, c_ulong) c_int;
pub const XErrorHandler = *const fn (*Display, *XErrorEvent) callconv(.c) c_int;
/// 只吃一个 handler 参数
pub extern "X11" fn XSetErrorHandler(XErrorHandler) XErrorHandler;

/// Xutil.h 的 XErrorEvent。Xlib 的默认错误处理器会打印然后 exit()，一个无关紧要的
/// BadValue 就能让扫雷直接消失，所以这里自己装一个只记日志、绝不退出的处理器。
pub const XErrorEvent = extern struct {
    type: c_int,
    display: ?*Display,
    resourceid: c_ulong,
    serial: c_ulong,
    error_code: u8,
    request_code: u8,
    minor_code: u8,
};

fn xErrorHandler(dpy: ?*Display, ev: *XErrorEvent) callconv(.c) c_int {
    _ = dpy;
    dbg(.always, "X error: code={d} major={d} minor={d} serial={d} resource=0x{x}", .{
        ev.error_code, ev.request_code, ev.minor_code, ev.serial, ev.resourceid,
    });
    return 0; // 0 = 忽略这个错误，继续跑
}

/// Xutil.h 的 XImage，布局自 1988 年起没变过，手写一份避免依赖 X11 头文件
pub const XImage = extern struct {
    width: c_int,
    height: c_int,
    xoffset: c_int,
    format: c_int,
    data: ?[*]u8,
    byte_order: c_int,
    bitmap_unit: c_int,
    bitmap_bit_order: c_int,
    bitmap_pad: c_int,
    depth: c_int,
    bytes_per_line: c_int,
    bits_per_pixel: c_int,
    red_mask: c_ulong,
    green_mask: c_ulong,
    blue_mask: c_ulong,
};

pub const XWindowAttributes = extern struct {
    x: c_int, y: c_int, width: c_int, height: c_int, border_width: c_int, depth: c_int,
    visual: ?*const Visual, root: Window, c_class: c_int, bit_gravity: c_int, win_gravity: c_int,
    backing_store: c_int, backing_planes: c_ulong, backing_pixel: c_ulong, save_under: c_int,
    colormap: Colormap, map_installed: c_int, map_state: c_int,
    all_event_masks: c_long, your_event_mask: c_long, do_not_propagate_mask: c_long,
    override_redirect: c_int, screen: ?*anyopaque,
};

/// Xutil.h 的 XVisualInfo。字段名 class 在 C 里是关键字，Zig 侧改名 c_class，
/// 其余字段与顺序完全一致。偏移由 tools/struct_sizes.c 对账：
/// visual@0 visualid@8 screen@16 depth@20 red_mask@32 green_mask@40 blue_mask@48
/// colormap_size@56 bits_per_rgb@60 sizeof=64
pub const XVisualInfo = extern struct {
    visual: ?*const Visual,
    visualid: VisualID,
    screen: c_int,
    depth: c_int,
    c_class: c_int,
    red_mask: c_ulong,
    green_mask: c_ulong,
    blue_mask: c_ulong,
    colormap_size: c_int,
    bits_per_rgb: c_int,
};

pub const XSizeHints = extern struct {
    flags: c_long,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    min_width: c_int,
    min_height: c_int,
    max_width: c_int,
    max_height: c_int,
    width_inc: c_int,
    height_inc: c_int,
    min_aspect_x: c_int,
    min_aspect_y: c_int,
    max_aspect_x: c_int,
    max_aspect_y: c_int,
    base_width: c_int,
    base_height: c_int,
    win_gravity: c_int,
};

pub const XWMHints = extern struct {
    flags: c_long,
    input: c_int,
    initial_state: c_int,
    icon_pixmap: XID,
    icon_window: Window,
    icon_x: c_int,
    icon_y: c_int,
    icon_mask: XID,
    window_group: XID,
};

/// XCreateWindow 的 attributes。**valuemask 是按这个结构体的成员顺序取值的**，
/// 所以必须老老实实按结构体传，不能塞一维数组（塞错会写到别的成员上）。
pub const XSetWindowAttributes = extern struct {
    background_pixmap: XID,
    background_pixel: c_ulong,
    border_pixmap: XID,
    border_pixel: c_ulong,
    bit_gravity: c_int,
    win_gravity: c_int,
    backing_store: c_int,
    backing_planes: c_ulong,
    backing_pixel: c_ulong,
    save_under: c_int,
    event_mask: c_long,
    do_not_propagate_mask: c_long,
    override_redirect: c_int,
    colormap: Colormap,
    cursor: XID,
};

/// XLookupKeysym 要的第一个参数：只读 keycode/state，喂一个假的头即可
pub const XKeyEventZ = extern struct {
    type: c_int,
    serial: c_ulong,
    send_event: c_int,
    display: ?*Display,
    window: Window,
    root: Window,
    subwindow: Window,
    time: c_ulong,
    x: c_int,
    y: c_int,
    x_root: c_int,
    y_root: c_int,
    state: c_uint,
    keycode: c_uint,
    same_screen: c_int,
};

// ------------------------------------------------------------------ Xft / fontconfig 绑定
/// Xrender.h 的 XRenderColor
pub const XRenderColor = extern struct {
    red: u16,
    green: u16,
    blue: u16,
    alpha: u16,
};

/// Xft.h 的 XftColor：pixel 之外还有一层 XRenderColor，别写扁了
pub const XftColor = extern struct {
    pixel: c_ulong,
    color: XRenderColor,
};

/// Xrender.h 的 XGlyphInfo。Xft 的文字度量最终写进这个结构（不是 XftTextExtents）。
pub const XGlyphInfo = extern struct {
    width: u16,
    height: u16,
    x: i16,
    y: i16,
    xOff: i16,
    yOff: i16,
};

pub extern "Xft" fn XftDrawCreate(*Display, Drawable, ?*const Visual, Colormap) ?*XftDraw;
/// 注意：只吃 draw 一个参数（Display 是从 draw 里取的），
/// 多传一个 dpy 会被 C 侧当成 draw，XRenderFindDisplay(垃圾) 必崩。
pub extern "Xft" fn XftDrawDestroy(?*XftDraw) void;
pub extern "Xft" fn XftDrawPicture(*XftDraw) c_ulong;
/// 注意：第一个参数是 XftDraw（不是 Display），且参数顺序是 draw,color,font,x,y,str,len
pub extern "Xft" fn XftDrawStringUtf8(
    *XftDraw, *const XftColor, *Font, c_int, c_int, [*]const u8, c_int,
) void;
pub extern "Xft" fn XftTextExtents8(*Display, *Font, [*]const u8, c_int, *XGlyphInfo) void;
/// len 是 **UTF-16 码元个数**，不是字节数。中文必须走这个才量得准。
pub extern "Xft" fn XftTextExtents16(*Display, *Font, [*]const u16, c_int, *XGlyphInfo) void;
pub extern "Xft" fn XftFontOpenName(*Display, c_int, [*:0]const u8) ?*Font;
pub extern "Xft" fn XftFontClose(*Display, *Font) void;

pub extern "fontconfig" fn FcInit() FcBool;

// ------------------------------------------------------------------ 常量
pub const EventMask = struct {
    pub const KEY_PRESS: c_long = 1 << 0;
    pub const KEY_RELEASE: c_long = 1 << 1;
    pub const BUTTON_PRESS: c_long = 1 << 2;
    pub const BUTTON_RELEASE: c_long = 1 << 3;
    pub const EXPOSURE: c_long = 1 << 15;
    pub const STRUCTURE_NOTIFY: c_long = 1 << 17;
    pub const POINTER_MOTION: c_long = 1 << 6;
    pub const FOCUS_CHANGE: c_long = 1 << 21;
};

/// XGrabPointer 允许的 event_mask 位（见 X.h 的 GrabMask）
const GrabMask = struct {
    pub const BUTTON_PRESS: c_long = 1 << 2;
    pub const BUTTON_RELEASE: c_long = 1 << 3;
    pub const ENTER_WINDOW: c_long = 1 << 4;
    pub const LEAVE_WINDOW: c_long = 1 << 5;
    pub const POINTER_MOTION: c_long = 1 << 6;
    pub const KEY_STATE: c_long = 1 << 14;
};

const EventType = struct {
    pub const KEY_PRESS: c_int = 2;
    pub const KEY_RELEASE: c_int = 3;
    pub const BUTTON_PRESS: c_int = 4;
    pub const BUTTON_RELEASE: c_int = 5;
    pub const MOTION_NOTIFY: c_int = 6;
    pub const FOCUS_IN: c_int = 9;
    pub const FOCUS_OUT: c_int = 10;
    pub const EXPOSE: c_int = 12;
    pub const MAP_NOTIFY: c_int = 19;
    pub const CONFIGURE_NOTIFY: c_int = 22;
    pub const CLIENT_MESSAGE: c_int = 33;
};

const CW = struct {
    pub const BACK_PIXEL: c_ulong = 1 << 1;
    pub const BORDER_PIXEL: c_ulong = 1 << 3;
    pub const OVERRIDE_REDIRECT: c_ulong = 1 << 9;
    pub const EVENT_MASK: c_ulong = 1 << 11;
};

const US = struct {
    pub const SIZE: c_long = 1 << 18;
    pub const POSITION: c_long = 1 << 2;
    pub const MIN_SIZE: c_long = 1 << 4;
    pub const MAX_SIZE: c_long = 1 << 5;
};

const PMask = struct {
    pub const INPUT: c_long = 1 << 0;
    pub const STATE_HINT: c_long = 1 << 1;
};

const InputHint = struct { pub const HINT_NONE: c_int = 0; };
const ZPixmap: c_int = 2;
const LSBFirst: c_int = 0;
/// XGetVisualInfo 的 mask 位：什么都不筛，只按 visualid 取
const VisualNoMask: c_long = 0;
/// Xutil.h VisualIDMask：只按 template.visualid 匹配
const VisualIDMask: c_long = 0x1;
/// X.h：传给 XGetWindowProperty 表示「任意属性类型」
const AnyPropertyType: Atom = 0;
/// X.h：XGetWindowProperty 成功返回值
const XSuccess: c_int = 0;
/// Xatom.h：XA_CARDINAL，用于写 32 位整数的窗口属性
const XA_CARDINAL: Atom = 6;
const GrabModeAsync: c_int = 1;
pub const GrabSuccess: c_int = 0;
pub const ReplayPointer: c_int = 2;

pub const ModMask = struct {
    pub const SHIFT: u16 = 1 << 0;
    pub const CONTROL: u16 = 1 << 2;
    pub const MOD1: u16 = 1 << 3; // Alt
    pub const BUTTON1: u16 = 1 << 8;
    pub const BUTTON2: u16 = 1 << 9;
    pub const BUTTON3: u16 = 1 << 10;
};

pub const Button = struct {
    pub const LEFT: u8 = 1;
    pub const MIDDLE: u8 = 2;
    pub const RIGHT: u8 = 3;
};

/// 常用 keysym（X11 里是 32 位）
pub const Key = struct {
    pub const RETURN: u32 = 0xFF0D;
    pub const KP_ENTER: u32 = 0xFF8D;
    pub const ESCAPE: u32 = 0xFF1B;
    pub const TAB: u32 = 0xFF09;
    pub const BACKSPACE: u32 = 0xFF08;
    pub const LEFT: u32 = 0xFF51;
    pub const UP: u32 = 0xFF52;
    pub const RIGHT: u32 = 0xFF53;
    pub const DOWN: u32 = 0xFF54;
    pub const HOME: u32 = 0xFF50;
    pub const END: u32 = 0xFF57;
    pub const F1: u32 = 0xFFBE;
    pub const F2: u32 = 0xFFC1;
    pub const DELETE: u32 = 0xFFFF;
};

pub const Error = error{ X11Unavailable, UnsupportedVisual, OutOfMemory };

// ------------------------------------------------------------------ 颜色
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// 与图集一致：图集是 BGBA 字节序（byte0=B, byte1=G, byte2=R）。
    /// 帧缓冲的字节序要跟默认 visual 对得上，见 Ctx.queryVisualMasks。
    pub fn pack(c: Color) u32 {
        return @as(u32, c.b) | (@as(u32, c.g) << 8) | (@as(u32, c.r) << 16);
    }

    /// 按目标帧缓冲的字节序打包。rgb_low_first=true（visual 是 RGBA 布局）时
    /// R 与 B 对调。
    pub fn packFor(c: Color, rgb_low_first: bool) u32 {
        if (!rgb_low_first) return pack(c);
        return @as(u32, c.r) | (@as(u32, c.g) << 8) | (@as(u32, c.b) << 16);
    }
};

/// 经典 Win95/98 配色，与 Windows 版保持一致
pub const C_BTNFACE = Color{ .r = 0xC0, .g = 0xC0, .b = 0xC0 };
pub const C_BTNSHADOW = Color{ .r = 0x80, .g = 0x80, .b = 0x80 };
pub const C_BTNHIGHLIGHT = Color{ .r = 0xDF, .g = 0xDF, .b = 0xDF };
pub const C_BTNLIGHT = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF };
pub const C_WINDOW = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF };
pub const C_BLACK = Color{ .r = 0, .g = 0, .b = 0 };
pub const C_WHITE = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF };
pub const C_DARKGRAY = Color{ .r = 0x40, .g = 0x40, .b = 0x40 };
pub const C_GRAYTEXT = Color{ .r = 0x80, .g = 0x80, .b = 0x80 };
pub const C_MENUHILIGHT = Color{ .r = 0x00, .g = 0x00, .b = 0x80 };
pub const C_MENUHILIGHT_TEXT = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF };
pub const C_HILIGHT = C_BTNHIGHLIGHT;
pub const C_SHADOW = C_BTNSHADOW;

// ------------------------------------------------------------------ 软件帧缓冲
pub const Surface = struct {
    px: []u8, // 4 字节/像素，字节序由 rgb_low_first 决定
    w: i32,
    h: i32,
    /// 目标 visual 是 RGBA 内存序（R 在低字节）时为 true。
    /// 决定 fill/blit 往 px 里写 R 还是写 B。
    rgb_low_first: bool,

    pub fn create(alloc: std.mem.Allocator, w: i32, h: i32, rgb_low_first: bool) !Surface {
        if (w <= 0 or h <= 0) return error.OutOfMemory;
        const n = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;
        const px = try alloc.alloc(u8, n);
        @memset(px, 0);
        return .{ .px = px, .w = w, .h = h, .rgb_low_first = rgb_low_first };
    }

    pub fn destroy(self: *Surface, alloc: std.mem.Allocator) void {
        alloc.free(self.px);
        self.px = &.{};
        self.w = 0;
        self.h = 0;
    }

    pub fn fillAll(self: *Surface, c: Color) void {
        self.fill(0, 0, self.w, self.h, c);
    }

    /// 填充一个矩形；宽高非正就什么都不做（和 Win32 版 fill() 一致）
    pub fn fill(self: *Surface, x: i32, y: i32, cw: i32, ch: i32, c: Color) void {
        if (cw <= 0 or ch <= 0) return;
        const x0 = @max(x, 0);
        const y0 = @max(y, 0);
        const x1 = @min(x + cw, self.w);
        const y1 = @min(y + ch, self.h);
        if (x1 <= x0 or y1 <= y0) return;
        const v: u32 = c.packFor(self.rgb_low_first);
        const bytes = [_]u8{ @truncate(v), @truncate(v >> 8), @truncate(v >> 16), 0xFF };
        var yy = y0;
        while (yy < y1) : (yy += 1) {
            const row = @as(usize, @intCast(yy)) * @as(usize, @intCast(self.w)) * 4;
            var xx = x0;
            while (xx < x1) : (xx += 1) {
                const o = row + @as(usize, @intCast(xx)) * 4;
                @memcpy(self.px[o .. o + 4], &bytes);
            }
        }
    }

    /// 1 像素描边矩形
    pub fn frame(self: *Surface, x: i32, y: i32, cw: i32, ch: i32, c: Color) void {
        if (cw <= 0 or ch <= 0) return;
        self.fill(x, y, cw, 1, c);
        self.fill(x, y + ch - 1, cw, 1, c);
        self.fill(x, y + 1, 1, ch - 2, c);
        self.fill(x + cw - 1, y + 1, 1, ch - 2, c);
    }

    /// 经典立体边框：raised = 左上亮、右下暗；sunken 反过来（与 Win32 版 draw3d 同参同观感）
    pub fn draw3d(self: *Surface, x: i32, y: i32, cw: i32, ch: i32, t: i32, raised: bool) void {
        if (cw <= 0 or ch <= 0 or t <= 0) return;
        const a = if (raised) C_HILIGHT else C_SHADOW;
        const b = if (raised) C_SHADOW else C_HILIGHT;
        self.fill(x, y, cw, t, a); // 上
        self.fill(x, y, t, ch, a); // 左
        self.fill(x, y + ch - t, cw, t, b); // 下
        self.fill(x + cw - t, y, t, ch, b); // 右
    }

    /// 从图集里贴一张图，可整数倍缩放（最近邻，与 Win32 版 StretchBlt 观感一致）
    pub fn blit(
        self: *Surface,
        src: []const u8,
        src_w: i32,
        src_h: i32,
        sx: i32,
        sy: i32,
        sw: i32,
        sh: i32,
        dx: i32,
        dy: i32,
        dw: i32,
        dh: i32,
    ) void {
        if (sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0) return;
        if (src_w <= 0 or src_h <= 0) return;
        if (sx < 0 or sy < 0 or sx + sw > src_w or sy + sh > src_h) return;
        const x0 = @max(dx, 0);
        const y0 = @max(dy, 0);
        const x1 = @min(dx + dw, self.w);
        const y1 = @min(dy + dh, self.h);
        if (x1 <= x0 or y1 <= y0) return;

        var yy = y0;
        while (yy < y1) : (yy += 1) {
            const fy = @divTrunc((yy - dy) * sh, dh);
            const srow = @as(usize, @intCast(sy + fy)) * @as(usize, @intCast(src_w));
            const drow = @as(usize, @intCast(yy)) * @as(usize, @intCast(self.w));
            var xx = x0;
            while (xx < x1) : (xx += 1) {
                const fx = @divTrunc((xx - dx) * sw, dw);
                const so = (srow + @as(usize, @intCast(sx + fx))) * 4;
                if (so + 3 >= src.len) break;
                const a = src[so + 3];
                const doff = (drow + @as(usize, @intCast(xx))) * 4;
                if (a == 0) continue; // 全透明：保留底下的像素
                const b = src[so];
                const g2 = src[so + 1];
                const r = src[so + 2];
                if (a == 255) {
                    self.store(doff, b, g2, r);
                } else {
                    // 图集带 alpha（人脸等边缘半透明），按 alpha 混到背景上
                    const ia = 255 - a;
                    self.blend(doff, b, g2, r, a, ia);
                }
                self.px[doff + 3] = 0xFF;
            }
        }
    }

    /// 写一个不透明像素。图集是 BGBA，帧缓冲字节序由 visual 决定，所以 R/B 要看情况换位。
    inline fn store(self: *Surface, o: usize, b: u8, g: u8, r: u8) void {
        if (self.rgb_low_first) {
            self.px[o] = r;
            self.px[o + 1] = g;
            self.px[o + 2] = b;
        } else {
            self.px[o] = b;
            self.px[o + 1] = g;
            self.px[o + 2] = r;
        }
    }

    /// 半透明混合，通道顺序同样要跟着 visual 走。
    inline fn blend(self: *Surface, o: usize, b: u8, g: u8, r: u8, a: u16, ia: u16) void {
        const d0 = self.px[o];
        const d1 = self.px[o + 1];
        const d2 = self.px[o + 2];
        const n0: u8 = @truncate((@as(u16, if (self.rgb_low_first) r else b) * a + @as(u16, d0) * ia) / 255);
        const n1: u8 = @truncate((@as(u16, g) * a + @as(u16, d1) * ia) / 255);
        const n2: u8 = @truncate((@as(u16, if (self.rgb_low_first) b else r) * a + @as(u16, d2) * ia) / 255);
        self.px[o] = n0;
        self.px[o + 1] = n1;
        self.px[o + 2] = n2;
    }
};

// ------------------------------------------------------------------ 事件
pub const Event = union(enum) {
    none,
    expose,
    configure: struct { x: i32, y: i32, w: i32, h: i32 },
    close,
    key_down: struct { keysym: u32, state: u16, x: i32, y: i32 },
    key_up: struct { keysym: u32, state: u16 },
    button_down: struct { button: u8, x: i32, y: i32, state: u16 },
    button_up: struct { button: u8, x: i32, y: i32, state: u16 },
    motion: struct { x: i32, y: i32, state: u16 },
    focus_in,
    focus_out,
    map,
    other,
};

pub const FontKind = enum { ui, mono };

const TextCmd = struct {
    x: i32,
    y: i32, // 基线
    mono: bool,
    c: Color,
    bytes: []const u8,
};

// ------------------------------------------------------------------ Ctx：display + 字体
pub const Ctx = struct {
    alloc: std.mem.Allocator,
    dpy: *Display,
    screen: c_int,
    depth: c_int,
    visual: *const Visual,
    cmap: Colormap,
    gc: GC,
    font_ui: ?*Font,
    font_mono: ?*Font,
    wm_delete: Atom,
    wm_protocols: Atom,
    /// 没有可用字体（比如系统一个中文字体都没有）时置 true，界面层据此提示
    no_font: bool,
    /// 默认 visual 的真实通道掩码。**不能写死**：同样是 24 位 TrueColor，
    /// Xvfb/多数服务器是 0xff0000/0xff00/0xff（R 在高位，内存序 BGRA），
    /// 而另一些桌面是 0xff/0xff00/0xff0000（R 在低位，内存序 RGBA）。
    red_mask: c_ulong,
    green_mask: c_ulong,
    blue_mask: c_ulong,
    /// 内存里 R 在低字节（RGBA 布局）时为 true，此时帧缓冲的红蓝要互换。
    /// 写死掩码的后果很隐蔽：灰色三通道相等看不出来，红色 LED 数字会变蓝，
    /// 在黑底上几乎「看不见」——正是真机上报告的症状。
    rgb_low_first: bool,

    pub fn init(alloc: std.mem.Allocator) !Ctx {
        const dpy = XOpenDisplay(null) orelse return Error.X11Unavailable;
        errdefer _ = XCloseDisplay(dpy);
        _ = XSetErrorHandler(xErrorHandler);

        const screen = XDefaultScreen(dpy);
        const depth = XDefaultDepth(dpy, screen);
        // 本程序按 24/32 位 TrueColor 直接写内存；16 位色深的老服务器直接拒绝，省得画出乱色
        if (depth != 24 and depth != 32) return Error.UnsupportedVisual;
        const visual = XDefaultVisual(dpy, screen) orelse return Error.UnsupportedVisual;

        var ctx: Ctx = .{
            .alloc = alloc,
            .dpy = dpy,
            .screen = screen,
            .depth = depth,
            .visual = visual,
            .cmap = XDefaultColormap(dpy, screen),
            .gc = XDefaultGC(dpy, screen),
            .font_ui = null,
            .font_mono = null,
            .wm_delete = XInternAtom(dpy, "WM_DELETE_WINDOW", 0),
            .wm_protocols = XInternAtom(dpy, "WM_PROTOCOLS", 0),
            .no_font = false,
            .red_mask = 0xFF0000,
            .green_mask = 0x00FF00,
            .blue_mask = 0x0000FF,
            .rgb_low_first = false,
        };
        // 问默认 visual 要真实掩码，别猜
        ctx.queryVisualMasks();
        // 找一套能显示中文的系统字体：lang=zh-cn 交给 fontconfig 去挑，
        // 于是中文靠用户机器上已有的 Noto CJK / 文泉驿，不往包里塞字体
        _ = FcInit();
        ctx.font_ui = openFont(dpy, screen, "sans-serif:lang=zh-cn");
        if (ctx.font_ui == null) ctx.font_ui = openFont(dpy, screen, "sans-serif");
        ctx.font_mono = openFont(dpy, screen, "monospace:lang=zh-cn");
        if (ctx.font_mono == null) ctx.font_mono = ctx.font_ui;
        ctx.no_font = ctx.font_ui == null;
        return ctx;
    }

    /// 取默认 visual 的 red/green/blue_mask，并判定帧缓冲要不要按 RGBA 存。
    /// 拿不到就退回 Xvfb 那种常见布局（BGRX），与旧行为一致。
    fn queryVisualMasks(self: *Ctx) void {
        var tmpl: XVisualInfo = .{
            .visual = self.visual,
            .visualid = 0,
            .screen = 0,
            .depth = 0,
            .c_class = 0,
            .red_mask = 0,
            .green_mask = 0,
            .blue_mask = 0,
            .colormap_size = 0,
            .bits_per_rgb = 0,
        };
        // 用 visualid 匹配最稳：先取当前 visual 的 XID，再按 id 精确查。
        // 传 VisualNoMask 时 Xlib 会拿整个 template 去比，visual/screen/depth
        // 这些占位值反而可能匹配不上，所以显式给 id。
        tmpl.visualid = XVisualIDFromVisual(self.visual);
        var n: c_int = 0;
        const info = XGetVisualInfo(self.dpy, VisualIDMask, &tmpl, &n) orelse return;
        defer _ = XFree(@constCast(@ptrCast(info)));
        if (n < 1) return;
        if (info.red_mask != 0 and info.green_mask != 0 and info.blue_mask != 0) {
            self.red_mask = info.red_mask;
            self.green_mask = info.green_mask;
            self.blue_mask = info.blue_mask;
        }
        // 帧缓冲约定是 BGRA（byte0=B）。当服务器把 R 放在低字节（RGBA 布局）时，
        // 光改 XImage 里的掩码不够 —— XPutImage 对 ZPixmap 是按视觉逐字节直传的，
        // 所以必须让帧缓冲本身也变成 RGBA，两处一致才对得上。
        self.rgb_low_first = (self.red_mask & 0xFF) != 0;
    }

    pub fn deinit(self: *Ctx) void {
        if (self.font_ui) |f| XftFontClose(self.dpy, f);
        if (self.font_mono) |f| {
            if (f != self.font_ui) XftFontClose(self.dpy, f);
        }
        _ = XCloseDisplay(self.dpy);
    }

    pub fn fontOf(self: *Ctx, kind: FontKind) ?*Font {
        return switch (kind) {
            .ui => self.font_ui,
            .mono => self.font_mono,
        };
    }

    /// 量一段字的宽度（像素）。Xft 把整串的前进宽度累加在 xOff 上。
    ///
    /// **必须走 XftTextExtents16**：XftTextExtents8 的 len 在本机 libXft 里是按
    /// 「字节」推进的，中文会被算成 2.5 倍宽（"游戏" 度量出 84px，实际墨迹只有 33px），
    /// 而且 y 返回正值这种没法用的垃圾。TextExtents16 的 len 才是字符数。
    pub fn textWidth(self: *Ctx, s: []const u8, kind: FontKind) i32 {
        return self.measure(s, kind, true);
    }

    /// 一行文字的像素高度（含上下伸部），用来垂直居中
    pub fn textHeight(self: *Ctx, kind: FontKind) i32 {
        return self.measure("Agjy国Ag", kind, false);
    }

    /// 基线到该行顶端的距离（画字时 y 就是基线，居中排版要用它）
    pub fn textAscent(self: *Ctx, kind: FontKind) i32 {
        return self.measure("国Ag", kind, false);
    }

    /// 走 UTF-16 量度。want_xoff=false 时返回 y+height（行高），否则返回前进宽度。
    fn measure(self: *Ctx, s: []const u8, kind: FontKind, want_xoff: bool) i32 {
        const f = self.fontOf(kind) orelse return if (want_xoff) 0 else 14;
        var buf: [256]u16 = undefined;
        const n = utf8ToUtf16(s, &buf);
        if (n == 0) return if (want_xoff) 0 else 14;
        var ext: XGlyphInfo = undefined;
        XftTextExtents16(self.dpy, f, buf[0..n].ptr, @intCast(n), &ext);
        if (want_xoff) return ext.xOff;
        return @as(i32, ext.y) + @as(i32, ext.height);
    }

    /// 一行文字的高度（含行距）
    pub fn lineHeight(self: *Ctx, kind: FontKind) i32 {
        return self.textHeight(kind) + 6;
    }

    /// 一行字**墨迹**的上下边界（相对基线）。
    ///
    /// Xft 的 XGlyphInfo 里 `y` 是从基线往**上**量的距离，`height` 是墨迹本身
    /// 的高度，所以整行墨迹占 [-y, height] 这段。注意 y+height 不是行高：
    /// 拿中文字体实测 "游戏" 得到 y=8 height=2（y+h=10），而字实际高约 18px，
    /// 因为中文的墨迹在基线上方较多、基线下方几乎没有。
    pub fn inkBox(self: *Ctx, kind: FontKind) struct { up: i32, down: i32 } {
        const f = self.fontOf(kind) orelse return .{ .up = 12, .down = 4 };
        var buf: [64]u16 = undefined;
        const n = utf8ToUtf16("国Agjy", &buf);
        var ext: XGlyphInfo = undefined;
        XftTextExtents16(self.dpy, f, buf[0..n].ptr, @intCast(n), &ext);
        // XGlyphInfo 的字段是 u16，y 语义上是「向上」，先统一成 i32 再算
        const ey: i32 = ext.y;
        const eh: i32 = ext.height;
        return .{ .up = @max(ey, 0), .down = @max(eh - ey, 0) };
    }

    /// 把一行字**垂直居中**在从 top 开始、高 box_h 的方框里，返回该用的基线 y。
    ///
    /// 旧写法是 `(box_h + textHeight) / 2 + 1`，而 textHeight = y + height
    /// 既不是行高也不对称，中文一算就偏低——菜单栏和所有按钮/对话框里的
    /// 标签都因此往下沉。这里改成按真实墨迹上下界算：
    ///   上留白 = (box_h - (up + down)) / 2，基线 = top + 上留白 + up
    pub fn centerBaseline(self: *Ctx, top: i32, box_h: i32, kind: FontKind) i32 {
        const ib = self.inkBox(kind);
        const total = ib.up + ib.down;
        const pad = @divTrunc(@max(box_h - total, 0), 2);
        return top + pad + ib.up;
    }

    pub fn waitEvent(self: *Ctx, timeout_ms: i32) Event {
        // Xlib 会把 socket 上的数据预读进自己的队列，光盯着 socket poll 会漏掉
        // 队列里已有的事件，所以先看队列，空了再去等 socket。
        if (XPending(self.dpy) > 0) return self.nextEvent();

        const fd = XConnectionNumber(self.dpy);
        var fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.IN, .revents = 0 }};
        const n = std.posix.poll(&fds, timeout_ms) catch return .none;
        if (n == 0) return .none; // 超时：调用方该去跑计时器了
        if (fds[0].revents == 0) return .none;
        // socket 有数据 ⇒ 连接上一定还有事件，nextEvent 不会阻塞
        return self.nextEvent();
    }

    /// 非阻塞地取一个事件：先排 Xlib 的队列，队列空了再探 socket。
    /// 队列非空或 socket 可读时 XNextEvent 必定立即返回；两者都没有就直接 .none，
    /// 绝不能让 XNextEvent 在空队列上空转 —— 它是会阻塞的。
    pub fn nextEvent(self: *Ctx) Event {
        if (XPending(self.dpy) == 0 and !self.socketReadable(0)) return .none;
        var buf: [256]u8 align(8) = undefined;
        // 关键：XNextEvent 的返回值不是「取到了没」。它把事件写进 buf、从队列摘掉
        // 之后返回的仍然是 0，所以必须无条件解码 buf，不能拿返回值当开关。
        const r = XNextEvent(self.dpy, @ptrCast(&buf));
        const raw = std.mem.readInt(i32, buf[0..4], .little);
        const e = self.decode(buf[0..192]);
        dbg(.dbg, "next: r={} raw={d} q={} -> {s}", .{ r, raw, XPending(self.dpy), @tagName(e) });
        return e;
    }

    /// socket 上还有没有数据（0ms 探测，不阻塞）
    fn socketReadable(self: *Ctx, timeout_ms: i32) bool {
        const fd = XConnectionNumber(self.dpy);
        var fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.IN, .revents = 0 }};
        const n = std.posix.poll(&fds, timeout_ms) catch return false;
        if (n == 0) return false;
        return (fds[0].revents & (std.posix.POLL.IN | std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0;
    }

    /// XEvent 按字节偏移读，而不是声明整个 union：
    /// Xlib 事件结构的前缀在 64 位上是固定布局，按偏移读最不容易出错。
    pub fn decode(self: *Ctx, b: []const u8) Event {
        const t = std.mem.readInt(i32, b[0..4], .little);
        switch (t) {
            EventType.EXPOSE => return .expose,
            EventType.MAP_NOTIFY => return .map,
            EventType.CONFIGURE_NOTIFY => return .{ .configure = .{
                .x = readI32(b, 40),
                .y = readI32(b, 44),
                .w = readI32(b, 48),
                .h = readI32(b, 52),
            } },
            EventType.CLIENT_MESSAGE => {
                // XClientMessageEvent 布局：message_type@40 恒为 WM_PROTOCOLS，
                // 真正的协议原子在 data.l[0]@56。以前拿 @40 跟 wm_delete 比，
                // 永远不相等 —— 窗口管理器的关闭按钮点了跟没点一样。
                if (@as(Atom, readU32(b, 56)) == self.wm_delete) return .close;
                return .other;
            },
            EventType.KEY_PRESS, EventType.KEY_RELEASE => {
                const state: u16 = @truncate(readU32(b, 80));
                const keycode: u8 = @truncate(readU32(b, 84));
                const ks = self.keysymOf(keycode, state);
                if (t == EventType.KEY_PRESS) {
                    return .{ .key_down = .{ .keysym = ks, .state = state, .x = readI32(b, 64), .y = readI32(b, 68) } };
                }
                return .{ .key_up = .{ .keysym = ks, .state = state } };
            },
            EventType.BUTTON_PRESS, EventType.BUTTON_RELEASE => {
                const state: u16 = @truncate(readU32(b, 80));
                const button: u8 = @truncate(readU32(b, 84));
                const x = readI32(b, 64);
                const y = readI32(b, 68);
                if (t == EventType.BUTTON_PRESS) return .{ .button_down = .{ .button = button, .x = x, .y = y, .state = state } };
                return .{ .button_up = .{ .button = button, .x = x, .y = y, .state = state } };
            },
            EventType.MOTION_NOTIFY => return .{ .motion = .{
                .x = readI32(b, 64),
                .y = readI32(b, 68),
                .state = @truncate(readU32(b, 80)),
            } },
            EventType.FOCUS_IN => return .focus_in,
            EventType.FOCUS_OUT => return .focus_out,
            else => return .other,
        }
    }

    /// keysym ← keycode。用一个假的 XKeyEvent 头喂 XLookupKeysym（它只读 keycode/state）
    fn keysymOf(self: *Ctx, keycode: u8, state: u16) u32 {
        var ev: XKeyEventZ = std.mem.zeroes(XKeyEventZ);
        ev.type = EventType.KEY_PRESS;
        ev.display = self.dpy;
        ev.keycode = keycode;
        ev.state = state;
        return @truncate(XLookupKeysym(&ev, 0));
    }
};

// ------------------------------------------------------------------ Canvas：一个窗口
/// 脏矩形（窗口内坐标）。w/h 非正表示「空」。
pub const Rect = struct { x: i32 = 0, y: i32 = 0, w: i32 = 0, h: i32 = 0 };

pub const Canvas = struct {
    ctx: *Ctx,
    win: Window,
    w: i32,
    h: i32,
    surface: Surface,
    text_cmds: std.ArrayList(TextCmd),
    pending_text: std.ArrayList([]u8),
    xft_draw: ?*XftDraw,
    shown: bool,
    /// 本帧要推上屏的区域（窗口内坐标）。空矩形（w<=0）表示「这次不用推」。
    dirty: Rect,
    /// 强制整窗推送：首次显示、resize、Expose 之后置位
    force_full: bool,
    /// XSPY 帧统计
    pushed_px: u64 = 0,
    pushed_frames: u64 = 0,
    /// 窗口是否被合成器接管。合成器接管后必须整窗推送：它把窗口重定向到离屏
    /// pixmap 再整体合成，脏矩形这种碎片更新会让它读到半成品的一帧。
    composited: bool = false,

    /// override_redirect = true 时不请 WM 参与（自绘对话框用），否则是普通顶层窗
    pub fn create(
        ctx: *Ctx,
        parent: Window,
        px: i32,
        py: i32,
        w: i32,
        h: i32,
        title: []const u8,
        override_redirect: bool,
    ) !Canvas {
        const alloc = ctx.alloc;
        const dpy = ctx.dpy;
        // 父窗口由调用方给（顶层窗传 root）
        // 这两个像素也走 packFor：XCreateSimpleWindow 的 bg/fg 同样按
        // visual 掩码解释，通道顺序错了窗口一创建就是花的。
        const bg = C_BTNFACE.packFor(ctx.rgb_low_first);
        const fg = C_BLACK.packFor(ctx.rgb_low_first);

        const win = XCreateSimpleWindow(
            dpy,
            parent,
            px,
            py,
            @intCast(@max(w, 1)),
            @intCast(@max(h, 1)),
            0,
            bg,
            fg,
        );
        if (win == 0) return Error.X11Unavailable;
        _ = XSelectInput(dpy, win, evtMaskAll());

        // XStoreName 要的是以 NUL 结尾的字符串，这里补一个临时缓冲
        if (title.len > 0) {
            var tb: [256]u8 = undefined;
            const n = @min(title.len, tb.len - 1);
            @memcpy(tb[0..n], title[0..n]);
            tb[n] = 0;
            _ = XStoreName(dpy, win, @ptrCast(&tb));
        }
        _ = XSetWMProtocols(dpy, win, &[_]Atom{ctx.wm_delete}, 1);

        if (!override_redirect) {
            // 背景像素设成界面底色。留着 None 的话，合成器/服务器在某些时刻
            // 会把窗口内容当未定义（露底或透出桌面），表现就是局部内容凭空消失。
            // packFor：背景像素要走 X server 的通道掩码，不能用固定的 BGRA 打包，
            // 否则在 RGBA 布局的桌面上背景色会变（跟窗口内容对不上就是花屏边）。
            _ = XSetWindowBackground(dpy, win, C_BTNFACE.packFor(ctx.rgb_low_first));

            // 声明「我打算用 XPutImage 整窗覆盖，请别把我重定向到离屏缓冲」。
            // 合成器一旦接管，碎片更新就是无效输入，只能整窗推。声明绕开后
            // 走的是直接上屏路径，脏矩形优化和合成器都能正常工作。
            const bypass = XInternAtom(dpy, "_NET_WM_BYPASS_COMPOSITOR", 0);
            const one: u32 = 1;
            _ = XChangeProperty(dpy, win, bypass, XA_CARDINAL, 32, 1, &one, 4);

            // 固定大小：扫雷窗口本来就不该拖拽改变大小，和 Windows 版观感一致
            var sh: XSizeHints = std.mem.zeroes(XSizeHints);
            sh.flags = US.SIZE | US.POSITION | US.MIN_SIZE | US.MAX_SIZE;
            sh.width = w;
            sh.height = h;
            sh.min_width = w;
            sh.min_height = h;
            sh.max_width = w;
            sh.max_height = h;
            _ = XSetWMNormalHints(dpy, win, &sh);

            var wm: XWMHints = std.mem.zeroes(XWMHints);
            wm.flags = PMask.INPUT | PMask.STATE_HINT;
            wm.input = 0;
            wm.initial_state = InputHint.HINT_NONE; // 启动时不抢焦点
            _ = XSetWMHints(dpy, win, &wm);
        }

        return .{
            .ctx = ctx,
            .win = win,
            .w = w,
            .h = h,
            .surface = try Surface.create(alloc, w, h, ctx.rgb_low_first),
            .text_cmds = std.ArrayList(TextCmd).init(alloc),
            .pending_text = std.ArrayList([]u8).init(alloc),
            .xft_draw = null,
            .shown = false,
            .dirty = .{},
            .force_full = true,
            .composited = compositingActive(ctx),
        };
    }

    pub fn destroy(self: *Canvas) void {
        self.clearText();
        self.text_cmds.deinit();
        self.pending_text.deinit();
        self.surface.destroy(self.ctx.alloc);
        if (self.xft_draw) |d| {
            dbg(.dbg, "destroy: dpy={*} xft_draw={*} win=0x{x}", .{ self.ctx.dpy, d, self.win });
            XftDrawDestroy(d);
        }
        self.xft_draw = null;
        if (self.win != 0) _ = XDestroyWindow(self.ctx.dpy, self.win);
        self.win = 0;
    }

    pub fn show(self: *Canvas) void {
        _ = XMapRaised(self.ctx.dpy, self.win);
        // 映射之后再选一次事件：建窗属性里那份只在建窗那一刻生效
        _ = XSelectInput(self.ctx.dpy, self.win, evtMaskAll());
        _ = XFlush(self.ctx.dpy);
        self.shown = true;
        // 刚映射的窗口内容是未定义的，必须整窗推一次
        self.invalidate();
    }

    /// 声明一块「这一帧变了」的区域。多次调用取并集。
    pub fn damage(self: *Canvas, x: i32, y: i32, w: i32, h: i32) void {
        if (w <= 0 or h <= 0) return;
        if (self.dirty.w <= 0 or self.dirty.h <= 0) {
            self.dirty = .{ .x = x, .y = y, .w = w, .h = h };
            return;
        }
        const x0 = @min(self.dirty.x, x);
        const y0 = @min(self.dirty.y, y);
        const x1 = @max(self.dirty.x + self.dirty.w, x + w);
        const y1 = @max(self.dirty.y + self.dirty.h, y + h);
        self.dirty = .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    /// 下一帧整窗重推（Expose、resize、显示/隐藏之后用）
    pub fn invalidate(self: *Canvas) void {
        self.force_full = true;
    }

    /// 改窗口与帧缓冲尺寸。**不重建窗口**：难度/缩放一变就调它，
    /// 这样焦点、图标、窗口位置都还在（重建窗口这些都会丢）。
    pub fn resize(self: *Canvas, w: i32, h: i32) !void {
        if (w == self.w and h == self.h) return;
        // 必须用 XResizeWindow：XMoveResizeWindow 会顺手把窗口挪到 (0,0)，
        // 改一次缩放窗口就跳到屏幕左上角了。
        _ = XResizeWindow(self.ctx.dpy, self.win, @intCast(@max(w, 1)), @intCast(@max(h, 1)));
        self.clearText();
        self.surface.destroy(self.ctx.alloc);
        self.surface = try Surface.create(self.ctx.alloc, w, h, self.ctx.rgb_low_first);
        self.w = w;
        self.h = h;
        self.invalidate();
    }

    pub fn focus(self: *Canvas) void {
        _ = XRaiseWindow(self.ctx.dpy, self.win);
        _ = XSetInputFocus(self.ctx.dpy, self.win, 1, 0); // RevertToPointerRoot
        _ = XFlush(self.ctx.dpy);
    }

    /// 抓鼠标：菜单/弹窗打开时用，指针移出窗口也能继续收到事件
    pub fn grabPointer(self: *Canvas) void {
        _ = XGrabPointer(
            self.ctx.dpy,
            self.win,
            0, // owner_events = false：全给我
            grabEventMask(),
            GrabModeAsync,
            GrabModeAsync,
            0, // confine_to = None
            0, // cursor = None
            0, // time = CurrentTime
        );
    }

    pub fn ungrabPointer(self: *Canvas) void {
        _ = XUngrabPointer(self.ctx.dpy, 0);
        _ = XAllowEvents(self.ctx.dpy, ReplayPointer, 0);
    }

    // ---------------- 画字 ----------------
    pub fn clearText(self: *Canvas) void {
        const alloc = self.ctx.alloc;
        for (self.pending_text.items) |s| alloc.free(s);
        self.pending_text.clearRetainingCapacity();
        self.text_cmds.clearRetainingCapacity();
    }

    /// 记一条要画的字。y 是**基线**。
    pub fn text(self: *Canvas, x: i32, y: i32, s: []const u8, c: Color, kind: FontKind) void {
        if (s.len == 0) return;
        if (self.ctx.fontOf(kind) == null) return; // 没有字体就别记，免得 flush 崩
        const alloc = self.ctx.alloc;
        const copy = alloc.dupe(u8, s) catch return;
        self.pending_text.append(copy) catch {
            alloc.free(copy);
            return;
        };
        self.text_cmds.append(.{ .x = x, .y = y, .mono = kind == .mono, .c = c, .bytes = copy }) catch {};
    }

    /// 把帧缓冲的**变化区域**推上窗口，再把记下来的字用 Xft 画上去。
    /// 顺序不能反：XPutImage 覆盖的区域在前，Xft 的字必须在其后。
    ///
    /// **为什么只推脏矩形**：早期版本每 60ms 无条件整窗 XPutImage一次。那样做在
    /// 没有窗口管理器的 Xvfb 上看着完全正常（画面静止），可一放到有 WM 的真实桌面上
    /// 就会出两个问题：
    ///   1. 整窗持续损伤 ⇒ WM 反复重合成，标题栏图标跟着「一抖一抖」；
    ///   2. 整窗 XPutImage 会把上一帧 Xft 画上去的字一起擦掉，字必须每帧重画，
    ///      于是文字（菜单、对话框里的数字）在两次重画之间闪。
    /// 只推脏矩形既让 WM 无事可做，也把闪烁降到不可见。
    pub fn flush(self: *Canvas) void {
        const dpy = self.ctx.dpy;
        if (self.w <= 0 or self.h <= 0) return;

        const d = self.dirty;
        const dw = @max(d.w, 0);
        const dh = @max(d.h, 0);
        // 整窗被标脏（首次显示、resize 之后）时退化成全窗口推送。
        // **被合成器接管时也必须整窗推**：合成器把窗口重定向到离屏 pixmap，
        // 再按自己的节奏整体合成到屏幕。碎片更新对它是无效输入——它只会在
        // 下一次合成时把离屏缓冲里的旧内容搬上去，于是出现「数字/局部内容不显示」。
        // 无 WM 的 Xvfb 下 composited=false，仍然享受脏矩形省流量的好处。
        const full = self.force_full or self.composited or dw <= 0 or dh <= 0;
        const px = if (full) 0 else d.x;
        const py = if (full) 0 else d.y;
        const cw: c_uint = @intCast(if (full) self.w else @min(dw, self.w - px));
        const ch: c_uint = @intCast(if (full) self.h else @min(dh, self.h - py));
        if (cw == 0 or ch == 0) {
            self.dirty = .{};
            self.force_full = false;
            return;
        }

        var img: XImage = .{
            .width = self.surface.w,
            .height = self.surface.h,
            .xoffset = 0,
            .format = ZPixmap,
            .data = self.surface.px.ptr,
            .byte_order = LSBFirst,
            .bitmap_unit = 32,
            .bitmap_bit_order = LSBFirst,
            .bitmap_pad = 32,
            .depth = self.ctx.depth,
            .bytes_per_line = self.surface.w * 4,
            .bits_per_pixel = 32,
            .red_mask = self.ctx.red_mask,
            .green_mask = self.ctx.green_mask,
            .blue_mask = self.ctx.blue_mask,
        };
        // 注意 dx/dy 是**源图**里的偏移，x/y 是**目标**窗口里的偏移；
        // 整窗时源和目标都是 0，两者恰好相同，所以上一版写 0,0 也没露馅。
        _ = XPutImage(dpy, self.win, self.ctx.gc, &img, @intCast(px), @intCast(py), px, py, cw, ch);

        if (self.text_cmds.items.len > 0) {
            if (self.xft_draw == null) {
                self.xft_draw = XftDrawCreate(dpy, self.win, self.ctx.visual, self.ctx.cmap);
            }
            if (self.xft_draw) |dr| {
                for (self.text_cmds.items) |t| {
                    // 文字落在脏矩形之外就别画了：Xft 直接画在窗口上，
                    // 画出去的话这块区域会在下一次 XPutImage 时被抹掉、又没重画，
                    // 结果就是「字自己消失了」——这正是数字不显示最隐蔽的一种成因。
                    if (!full and (t.x < px or t.y < py or
                        t.x >= px + @as(i32, @intCast(cw)) or
                        t.y >= py + @as(i32, @intCast(ch)))) continue;
                    const f = (if (t.mono) self.ctx.font_mono else self.ctx.font_ui) orelse continue;
                    XftDrawStringUtf8(
                        dr,
                        &toXftColor(t.c),
                        f,
                        t.x,
                        t.y,
                        t.bytes.ptr,
                        @intCast(t.bytes.len),
                    );
                }
            }
        }
        _ = XFlush(dpy);
        self.clearText();
        // 脏区已经推上去了，清掉；force_full 同样复位
        self.dirty = .{};
        self.force_full = false;
        // 帧统计：XSPY_TRACE=1 时每 60 帧汇总一次。真机上「图标抖不抖」取决于
        // 每秒推了多少像素——持续推整窗就是每秒 16 帧全量损伤，WM 必然反复重合成。
        self.pushed_px += @as(u64, cw) * @as(u64, ch);
        self.pushed_frames += 1;
        if (self.pushed_frames % 60 == 0) {
            dbg(.dbg, "frames={d} pushed_px={d} avg_px_per_frame={d}", .{
                self.pushed_frames, self.pushed_px, self.pushed_px / self.pushed_frames,
            });
            self.pushed_px = 0;
        }
    }
};

// ------------------------------------------------------------------ 内部实现
fn evtMaskAll() c_long {
    return @intCast(EventMask.EXPOSURE |
        EventMask.STRUCTURE_NOTIFY |
        EventMask.KEY_PRESS |
        EventMask.KEY_RELEASE |
        EventMask.BUTTON_PRESS |
        EventMask.BUTTON_RELEASE |
        EventMask.POINTER_MOTION |
        EventMask.FOCUS_CHANGE);
}

/// XGrabPointer 的 event_mask 合法位比 XSelectInput 窄得多：只允许指针/按键状态那
/// 几项，塞进 EXPOSURE / STRUCTURE_NOTIFY / FOCUS_CHANGE 会直接 BadValue 报错，
/// 而未捕获的 X 错误默认会让进程退出 —— 表现就是「一开菜单程序就没了」。
fn grabEventMask() c_uint {
    return @intCast(GrabMask.BUTTON_PRESS |
        GrabMask.BUTTON_RELEASE |
        GrabMask.ENTER_WINDOW |
        GrabMask.LEAVE_WINDOW |
        GrabMask.POINTER_MOTION |
        GrabMask.KEY_STATE);
}

/// 打开一套字体。spec 走 fontconfig 的模式串语法，例如 "sans-serif:lang=zh-cn"：
/// XftFontOpenName 内部自己做 fontconfig 匹配，所以中文靠用户机器上已有的
/// Noto CJK / 文泉驿，不需要往包里塞字体。匹配不到就返回 null（上层会退到下一个候选）。
fn openFont(dpy: *Display, screen: c_int, spec: []const u8) ?*Font {
    if (spec.len == 0 or spec.len >= 256) return null;
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..spec.len], spec);
    buf[spec.len] = 0;
    return XftFontOpenName(dpy, screen, @ptrCast(&buf));
}

fn toXftColor(c: Color) XftColor {
    return .{
        .pixel = c.pack(),
        .color = .{
            .red = @intCast(@as(u32, c.r) * 257),
            .green = @intCast(@as(u32, c.g) * 257),
            .blue = @intCast(@as(u32, c.b) * 257),
            .alpha = 0xFFFF,
        },
    };
}

/// 窗口左上角在**屏幕**上的坐标。XGetGeometry 给的是相对父窗口的，得换算一次。
pub fn windowRootPos(dpy: *Display, win: Window) ?struct { x: i32, y: i32 } {
    var root: Window = 0;
    var rxp: c_int = 0;
    var ryp: c_int = 0;
    var wx: c_uint = 0;
    var wy: c_uint = 0;
    var bw: c_uint = 0;
    var depth: c_uint = 0;
    if (XGetGeometry(dpy, win, &root, &rxp, &ryp, &wx, &wy, &bw, &depth) == 0) return null;
    var dest_x: c_int = 0;
    var dest_y: c_int = 0;
    var child: Window = 0;
    if (XTranslateCoordinates(dpy, win, root, 0, 0, &dest_x, &dest_y, &child) == 0) return null;
    return .{ .x = dest_x, .y = dest_y };
}

/// 把 _NET_WM_ICON 设成 RGBA 像素（标题栏 / 任务栏 / 启动器都读这个属性）
pub fn setIcon(ctx: *Ctx, win: Window, rgba: []const u8, size: i32) void {
    if (size <= 0) return;
    const need = @as(usize, @intCast(size)) * @as(usize, @intCast(size)) * 4;
    if (rgba.len < need) return;
    const net_wm_icon = XInternAtom(ctx.dpy, "_NET_WM_ICON", 0);

    // 协议：属性类型 XA_PIXMAP(20)、格式 32，内容是「宽 高 宽高 ...」+ BGRA 像素
    const w_h = 8;
    const n_words: usize = w_h / 4 + need / 4;
    const buf = std.heap.page_allocator.alloc(u8, n_words * 4) catch return;
    defer std.heap.page_allocator.free(buf);
    std.mem.writeInt(u32, buf[0..4], @intCast(size), .little);
    std.mem.writeInt(u32, buf[4..8], @intCast(size), .little);
    var i: usize = 0;
    while (i < need / 4) : (i += 1) {
        const o = w_h + i * 4;
        buf[o + 0] = rgba[i * 4 + 2]; // B
        buf[o + 1] = rgba[i * 4 + 1]; // G
        buf[o + 2] = rgba[i * 4 + 0]; // R
        buf[o + 3] = rgba[i * 4 + 3]; // A
    }
    // format=32 时：nelements 是 32 位单元个数，datasize 必须是**字节数**。
    // 两者写混会让服务端读短一个请求，X 连接协议直接错位（后面所有请求都废）。
    _ = XChangeProperty(ctx.dpy, win, net_wm_icon, 20, 32, @intCast(n_words), buf.ptr, @intCast(n_words * 4));
}

/// UTF-8 → UTF-16。只为把 Xft 的量度 API 用对（XftTextExtents16 的 len 是码元数）。
/// 遇到非法字节按 Latin-1 兜底，保证函数不会因为脏输入死循环。
fn utf8ToUtf16(s: []const u8, out: []u16) usize {
    var i: usize = 0;
    var n: usize = 0;
    while (i < s.len and n < out.len) {
        const b = s[i];
        var cp: u32 = undefined;
        var need: usize = undefined;
        if (b < 0x80) {
            cp = b;
            need = 0;
        } else if (b & 0xe0 == 0xc0) {
            cp = b & 0x1f;
            need = 1;
        } else if (b & 0xf0 == 0xe0) {
            cp = b & 0x0f;
            need = 2;
        } else if (b & 0xf8 == 0xf0) {
            cp = b & 0x07;
            need = 3;
        } else {
            cp = b; // 续字节出现在开头：按 Latin-1 兜底
            need = 0;
        }
        i += 1;
        var k: usize = 0;
        while (k < need) : (k += 1) {
            if (i >= s.len or s[i] & 0xc0 != 0x80) break;
            cp = (cp << 6) | (s[i] & 0x3f);
            i += 1;
        }
        if (cp < 0x10000) {
            out[n] = @intCast(cp);
            n += 1;
        } else {
            if (n + 1 >= out.len) break;
            const v = cp - 0x10000;
            out[n] = @intCast(0xd800 + (v >> 10));
            out[n + 1] = @intCast(0xdc00 + (v & 0x3ff));
            n += 2;
        }
    }
    return n;
}

inline fn readI32(b: []const u8, off: usize) i32 {    return std.mem.readInt(i32, b[off..][0..4], .little);
}
inline fn readU32(b: []const u8, off: usize) u32 {
    return std.mem.readInt(u32, b[off..][0..4], .little);
}

// ------------------------------------------------------------------ 杂项
/// 调试开关：编译时 -DXDBG=1，或运行时设 XSPY_TRACE=1
const XDBG: bool = blk: {
    if (@hasDecl(@import("builtin"), "mode")) {
        const opts = @import("builtin").mode;
        if (opts == .Debug) break :blk true;
    }
    break :blk false;
};
fn dbg_enabled() bool {
    if (XDBG) return true;
    const v: [*:0]const u8 = std.c.getenv("XSPY_TRACE") orelse return false;
    return v[0] != 0 and v[0] != '0';
}
pub fn dbg(comptime lvl: enum { dbg, always }, comptime fmt: []const u8, args: anytype) void {
    if (lvl == .dbg and !dbg_enabled()) return;
    var b: [1024]u8 = undefined;
    const m = std.fmt.bufPrint(&b, "[" ++ fmt ++ "]\n", args) catch return;
    _ = std.posix.write(2, m) catch {};
}

/// XSPY_TRACE=1 时把「这台机器上到底发生了什么」一次性打清楚：
/// visual 通道布局、窗口管理器是谁、字体解析成了什么、每帧推了多少像素。
/// 真机和容器（Xvfb 无 WM）的差别几乎都落在前两项上，靠猜迟早猜错。
pub fn reportEnvironment(ctx: *Ctx) void {
    if (!dbg_enabled()) return;
    dbg(.always, "=== XSPY 环境报告 ===", .{});
    dbg(.always, "DISPLAY={s}", .{std.posix.getenv("DISPLAY") orelse "(unset)"});
    dbg(.always, "XDG_SESSION_TYPE={s} XDG_CURRENT_DESKTOP={s}", .{
        std.posix.getenv("XDG_SESSION_TYPE") orelse "(unset)",
        std.posix.getenv("XDG_CURRENT_DESKTOP") orelse "(unset)",
    });
    dbg(.always, "screen={d} depth={d}", .{ ctx.screen, ctx.depth });
    dbg(.always, "visual masks: R=0x{X} G=0x{X} B=0x{X}", .{
        ctx.red_mask, ctx.green_mask, ctx.blue_mask,
    });
    // 这一行是关键：rgb_low_first 为 true 说明内存序是 RGBA，
    // 帧缓冲必须按 RGBA 写；为 false 是 BGRA。两者写反就是红蓝互换。
    dbg(.always, "framebuffer byte order: {s}", .{
        if (ctx.rgb_low_first) "RGBA (R in low byte)" else "BGRA (B in low byte)",
    });
    dbg(.always, "no_font={} font_ui={any} font_mono={any}", .{
        ctx.no_font, ctx.font_ui != null, ctx.font_mono != null,
    });
    reportWindowManager(ctx);
    dbg(.always, "compositing (_NET_WM_COMPOSITING): {s}", .{
        if (compositingActive(ctx)) "YES -> 强制整窗推送" else "no  -> 可用脏矩形",
    });
    dbg(.always, "=== 报告结束 ===", .{});
}

/// 问 root 上有没有合成器（Mutter/KWin/Compiz 都会设 _NET_WM_COMPOSITING）。
/// 有的话整窗推送才稳；没有（纯 Xvfb）则可以只推脏矩形省流量。
fn compositingActive(ctx: *Ctx) bool {
    const root = XRootWindow(ctx.dpy, ctx.screen);
    const atom = XInternAtom(ctx.dpy, "_NET_WM_COMPOSITING", 0);
    var t: Atom = 0;
    var f: c_int = 0;
    var n: c_ulong = 0;
    var b: c_ulong = 0;
    var d: [*]u8 = undefined;
    const rc = XGetWindowProperty(
        ctx.dpy, root, atom, 0, 1, 0, AnyPropertyType,
        &t, &f, &n, &b, &d,
    );
    if (rc != XSuccess or n < 1) return false;
    const p: [*]const u8 = @ptrCast(@alignCast(d));
    return p[0] != 0;
}

/// 问 root 上有没有窗口管理器，以及是哪一家。合成器的重绘策略（重不重画标题栏、
/// 怎么合成）直接决定「图标抖不抖」，光看自己画的对不对看不出来。
fn reportWindowManager(ctx: *Ctx) void {
    const root = XRootWindow(ctx.dpy, ctx.screen);
    const wm_check = XInternAtom(ctx.dpy, "_NET_SUPPORTING_WM_CHECK", 0);
    const wm_name = XInternAtom(ctx.dpy, "_NET_WM_NAME", 0);

    var actual_type: Atom = 0;
    var actual_fmt: c_int = 0;
    var n_items: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var data: [*]u8 = undefined;
    const rc = XGetWindowProperty(
        ctx.dpy, root, wm_check, 0, 1, 0, AnyPropertyType,
        &actual_type, &actual_fmt, &n_items, &bytes_after, &data,
    );
    if (rc == XSuccess and n_items >= 1) {
        {
            const p: [*]const u64 = @ptrCast(@alignCast(data));
            const wm_win: Window = @intCast(p[0]);
            dbg(.always, "WM: present, check window=0x{x}", .{wm_win});

            // 顺带取 WM 名字：_NET_WM_NAME 是 UTF-8，取不到退回 WM_NAME
            var t2: Atom = 0;
            var f2: c_int = 0;
            var n2: c_ulong = 0;
            var b2: c_ulong = 0;
            var d2: [*]u8 = undefined;
            if (XGetWindowProperty(
                ctx.dpy, wm_win, wm_name, 0, 256, 0, AnyPropertyType,
                &t2, &f2, &n2, &b2, &d2,
            ) == XSuccess and n2 > 0) {
                // 长度用服务端给的 n2，不靠找 NUL：WM 名字未必以 0 结尾，
                // 拿不准就按 n2 截断打印。
                const n: usize = @intCast(@min(n2, 255));
                dbg(.always, "WM name (_NET_WM_NAME): {s}", .{
                    @as([*:0]const u8, @ptrCast(d2))[0..n :0],
                });
            }
            dbg(.always, "WM: 窗口有 WM_DELETE_WINDOW 协议 = {s}", .{
                if (hasWmDelete(ctx, wm_win)) "yes" else "no",
            });
        }
    } else {
        dbg(.always, "WM: NONE (没有任何窗口管理器接管这个 display)", .{});
        dbg(.always, "WM: 这种环境下窗口不重画标题栏，图标抖动类问题复现不了", .{});
    }
}

fn hasWmDelete(ctx: *Ctx, win: Window) bool {
    var t: Atom = 0;
    var f: c_int = 0;
    var n: c_ulong = 0;
    var b: c_ulong = 0;
    var d: [*]u8 = undefined;
    if (XGetWindowProperty(
        ctx.dpy, win, ctx.wm_protocols, 0, 32, 0, AnyPropertyType,
        &t, &f, &n, &b, &d,
    ) != XSuccess) return false;
    const atoms: [*]const Atom = @ptrCast(@alignCast(d));
    var found = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (atoms[i] == ctx.wm_delete) found = true;
    }
    return found;
}

/// 单调毫秒（CLOCK_MONOTONIC），对应 Win32 的 GetTickCount
pub fn nowMs() u32 {
    const ts = std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC) catch return 0;
    const ms = @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(@divTrunc(ts.nsec, 1_000_000)));
    return @truncate(ms); // 32 位回绕，和 GetTickCount 一样
}
