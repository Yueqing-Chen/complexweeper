// 手写的 Win32 绑定：只声明本程序用到的部分，不依赖任何第三方包，也不依赖 libc。
// 目标平台固定为 x86_64-windows（x64 上只有一种调用约定，所以统一用 callconv(.c)）。
const std = @import("std");

pub const HINSTANCE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const HICON = ?*anyopaque;
pub const HCURSOR = ?*anyopaque;
pub const HBRUSH = ?*anyopaque;
pub const HBITMAP = ?*anyopaque;
pub const HDC = ?*anyopaque;
pub const HGDIOBJ = ?*anyopaque;
pub const HFONT = ?*anyopaque;
pub const HMODULE = ?*anyopaque;
pub const HANDLE = ?*anyopaque;

pub const UINT = u32;
pub const DWORD = u32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const BOOL = i32;
pub const ATOM = u16;
pub const WORD = u16;
pub const BYTE = u8;
pub const LPCWSTR = ?[*:0]const u16;
pub const LPWSTR = [*]u16;

pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

pub const POINT = extern struct { x: i32, y: i32 };
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    pub fn w(self: RECT) i32 { return self.right - self.left; }
    pub fn h(self: RECT) i32 { return self.bottom - self.top; }
};
pub const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};
pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.c) LRESULT;
pub const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: LPCWSTR,
    lpszClassName: LPCWSTR,
    hIconSm: HICON,
};
pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]BYTE,
};
pub const RGBQUAD = extern struct { rgbBlue: BYTE, rgbGreen: BYTE, rgbRed: BYTE, rgbReserved: BYTE };
pub const ICONINFO = extern struct {
    fIcon: BOOL,
    xHotspot: DWORD,
    yHotspot: DWORD,
    hbmMask: HBITMAP,
    hbmColor: HBITMAP,
};
pub const BITMAPINFOHEADER = extern struct {
    biSize: DWORD,
    biWidth: i32,
    biHeight: i32,
    biPlanes: WORD,
    biBitCount: WORD,
    biCompression: DWORD,
    biSizeImage: DWORD,
    biXPelsPerMeter: i32,
    biYPelsPerMeter: i32,
    biClrUsed: DWORD,
    biClrImportant: DWORD,
};
pub const BITMAPINFO = extern struct { bmiHeader: BITMAPINFOHEADER, bmiColors: [1]RGBQUAD };

pub const WNDCLASS_STYLES = struct {
    pub const CS_DBLCLKS: UINT = 0x0008;
    pub const CS_HREDRAW: UINT = 0x0002;
    pub const CS_VREDRAW: UINT = 0x0001;
};
pub const WS = struct {
    pub const OVERLAPPED: UINT = 0x00000000;
    pub const POPUP: UINT = 0x80000000;
    pub const CAPTION: UINT = 0x00C00000;
    pub const SYSMENU: UINT = 0x00080000;
    pub const MINIMIZEBOX: UINT = 0x00020000;
    pub const CHILD: UINT = 0x40000000;
    pub const VISIBLE: UINT = 0x10000000;
    pub const BORDER: UINT = 0x00800000;
    pub const DLGFRAME: UINT = 0x00400000;
    pub const TABSTOP: UINT = 0x00010000;
    pub const GROUP: UINT = 0x00020000;
    pub const EX_CLIENTEDGE: UINT = 0x00000200;
    pub const EX_APPWINDOW: UINT = 0x00040000;
};
pub const SW = struct {
    pub const SHOW: i32 = 5;
    pub const HIDE: i32 = 0;
};
pub const WM = struct {
    pub const CREATE: UINT = 0x0001;
    pub const DESTROY: UINT = 0x0002;
    pub const SIZE: UINT = 0x0005;
    pub const SETFOCUS: UINT = 0x0007;
    pub const KILLFOCUS: UINT = 0x0008;
    pub const PAINT: UINT = 0x000F;
    pub const CLOSE: UINT = 0x0010;
    pub const ERASEBKGND: UINT = 0x0014;
    pub const CTLCOLOREDIT: UINT = 0x0133;
    pub const CTLCOLORBTN: UINT = 0x0135;
    pub const CTLCOLORSTATIC: UINT = 0x0138;
    pub const SETCURSOR: UINT = 0x0020;
    pub const GETMINMAXINFO: UINT = 0x0024;
    pub const TIMER: UINT = 0x0113;
    pub const KEYDOWN: UINT = 0x0100;
    pub const COMMAND: UINT = 0x0111;
    pub const SYSCOMMAND: UINT = 0x0112;
    pub const INITMENU: UINT = 0x0116;
    pub const MOUSEMOVE: UINT = 0x0200;
    pub const LBUTTONDOWN: UINT = 0x0201;
    pub const LBUTTONUP: UINT = 0x0202;
    pub const LBUTTONDBLCLK: UINT = 0x0203;
    pub const RBUTTONDOWN: UINT = 0x0204;
    pub const RBUTTONUP: UINT = 0x0205;
    pub const RBUTTONDBLCLK: UINT = 0x0206;
    pub const MBUTTONDOWN: UINT = 0x0207;
    pub const MBUTTONUP: UINT = 0x0208;
    pub const MBUTTONDBLCLK: UINT = 0x0209;
    pub const CAPTURECHANGED: UINT = 0x0215;
    pub const ENTERSIZEMOVE: UINT = 0x0231;
    pub const EXITSIZEMOVE: UINT = 0x0232;
    pub const CONTEXTMENU: UINT = 0x007B;
    pub const PRINT: UINT = 0x0317;
    pub const PRINTCLIENT: UINT = 0x0318;
};
pub const MF = struct {
    pub const STRING: UINT = 0x00000000;
    pub const SEPARATOR: UINT = 0x00000800;
    pub const CHECKED: UINT = 0x00000008;
    pub const GRAYED: UINT = 0x00000003;
    pub const ENABLED: UINT = 0x00000000;
    pub const POPUP: UINT = 0x00000010;
    pub const BYCOMMAND: UINT = 0x00000000;
};
pub const IDC = struct {
    pub const ARROW: usize = 32512;
    pub const HAND: usize = 32649;
};
pub const COLOR = struct {
    pub const BTNFACE: i32 = 15;
    pub const WINDOW: i32 = 5;
    pub const BLACK: i32 = 0;
    pub const WHITE: i32 = 16777215;
};
pub const SRCCOPY: DWORD = 0x00CC0020;
pub const PATCOPY: DWORD = 0x00F00021;
pub const BLACKNESS: DWORD = 0x00000042;
pub const WHITENESS: DWORD = 0x00FF0062;
pub const BI_RGB: DWORD = 0;
pub const DIB_RGB_COLORS: UINT = 0;
pub const TRANSPARENT: i32 = 1;
pub const NULL_BRUSH: i32 = 5;
pub const DT = struct {
    pub const LEFT: UINT = 0x00000000;
    pub const CENTER: UINT = 0x00000001;
    pub const RIGHT: UINT = 0x00000002;
    pub const VCENTER: UINT = 0x00000004;
    pub const SINGLELINE: UINT = 0x00000020;
    pub const WORDBREAK: UINT = 0x00000010;
};
pub const MB = struct {
    pub const OK: UINT = 0x00000000;
    pub const ICONINFORMATION: UINT = 0x00000040;
    pub const ICONWARNING: UINT = 0x00000030;
    /// 配合 MessageBoxIndirect 的 lpszIcon 用：不加这一位，弹窗不会显示自己的图标
    pub const USERICON: UINT = 0x00000080;
    pub const SETFOREGROUND: UINT = 0x00010000;
    pub const TOPMOST: UINT = 0x00040000;
};

/// MessageBoxIndirect 的参数包。用它才能在弹窗里放**自己的图标**
/// （MessageBoxW 的 dwStyle 只能选那几个系统预设图标）。
pub const MSGBOXPARAMS = extern struct {
    cbSize: UINT,
    hwndOwner: HWND,
    hInstance: HINSTANCE,
    lpszText: LPCWSTR,
    lpszCaption: LPCWSTR,
    dwStyle: DWORD,
    /// 图标：既可以传资源 ID（低位为 0 时系统当成 ID），也可以传宽字符串。
    /// ID 不保证 u16 对齐（例如 ID=1），所以这里不用 LPCWSTR，交给 resId() 造。
    lpszIcon: ?*const anyopaque,
    dwContextHelpId: usize,
    lpfnMsgBoxCallback: ?*const fn (usize) callconv(.c) void,
    dwLanguageId: DWORD,
};

pub const IMAGE_ICON: UINT = 1;
pub const LR_DEFAULTCOLOR: UINT = 0x00000000;

// ---- user32 ----
pub extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.c) ATOM;
pub extern "user32" fn CreateWindowExW(DWORD, LPCWSTR, LPCWSTR, DWORD, i32, i32, i32, i32, HWND, HMENU, HINSTANCE, ?*anyopaque) callconv(.c) HWND;
pub extern "user32" fn DestroyWindow(HWND) callconv(.c) BOOL;
pub extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn ShowWindow(HWND, i32) callconv(.c) BOOL;
pub extern "user32" fn UpdateWindow(HWND) callconv(.c) BOOL;
pub extern "user32" fn GetMessageW(*MSG, HWND, UINT, UINT) callconv(.c) BOOL;
pub extern "user32" fn TranslateMessage(*const MSG) callconv(.c) BOOL;
pub extern "user32" fn DispatchMessageW(*const MSG) callconv(.c) LRESULT;
pub extern "user32" fn PostQuitMessage(i32) callconv(.c) void;
pub extern "user32" fn BeginPaint(HWND, *PAINTSTRUCT) callconv(.c) HDC;
pub extern "user32" fn EndPaint(HWND, *const PAINTSTRUCT) callconv(.c) BOOL;
pub extern "user32" fn GetClientRect(HWND, *RECT) callconv(.c) BOOL;
pub extern "user32" fn InvalidateRect(HWND, ?*const RECT, BOOL) callconv(.c) BOOL;
pub extern "user32" fn GetDC(HWND) callconv(.c) HDC;
pub extern "user32" fn ReleaseDC(HWND, HDC) callconv(.c) i32;
pub extern "user32" fn SetCapture(HWND) callconv(.c) HWND;
pub extern "user32" fn ReleaseCapture() callconv(.c) BOOL;
pub extern "user32" fn GetCapture() callconv(.c) HWND;
pub extern "user32" fn LoadCursorW(HINSTANCE, LPCWSTR) callconv(.c) HCURSOR;
pub extern "user32" fn LoadIconW(HINSTANCE, ?*const anyopaque) callconv(.c) HICON;
/// 按指定尺寸取图标资源（图标资源里放了 16/32/48 三档，这里点名要哪一档）
pub extern "user32" fn LoadImageW(HINSTANCE, ?*const anyopaque, UINT, i32, i32, UINT) callconv(.c) HANDLE;
/// MAKEINTRESOURCE：把整数资源 ID 当"指针"传（低位为 0 时系统认作 ID）。
/// 不写成 LPCWSTR 是因为 ID 只保证是整数，1 这种奇数地址过不了 u16 的对齐要求。
pub fn resId(id: usize) ?*const anyopaque {
    return @ptrFromInt(id);
}
pub extern "user32" fn SetTimer(HWND, usize, UINT, ?*anyopaque) callconv(.c) usize;
pub extern "user32" fn KillTimer(HWND, usize) callconv(.c) BOOL;
pub extern "user32" fn MessageBoxW(HWND, LPCWSTR, LPCWSTR, UINT) callconv(.c) i32;
pub extern "user32" fn MessageBoxIndirectW(*const MSGBOXPARAMS) callconv(.c) i32;
pub extern "user32" fn CreateMenu() callconv(.c) HMENU;
pub extern "user32" fn CreatePopupMenu() callconv(.c) HMENU;
pub extern "user32" fn AppendMenuW(HMENU, UINT, usize, LPCWSTR) callconv(.c) BOOL;
pub extern "user32" fn SetMenu(HWND, HMENU) callconv(.c) BOOL;
pub extern "user32" fn CheckMenuRadioItem(HMENU, UINT, UINT, UINT, UINT) callconv(.c) BOOL;
pub extern "user32" fn CheckMenuItem(HMENU, UINT, UINT) callconv(.c) DWORD;
pub extern "user32" fn EnableMenuItem(HMENU, UINT, UINT) callconv(.c) BOOL;
pub extern "user32" fn GetSystemMetrics(i32) callconv(.c) i32;
pub extern "user32" fn AdjustWindowRect(*RECT, DWORD, BOOL) callconv(.c) BOOL;
pub extern "user32" fn SetWindowPos(HWND, HWND, i32, i32, i32, i32, UINT) callconv(.c) BOOL;
pub extern "user32" fn FillRect(HDC, *const RECT, HBRUSH) callconv(.c) i32;
pub extern "user32" fn DrawEdge(HDC, *RECT, UINT, UINT) callconv(.c) BOOL;
pub extern "user32" fn DrawTextW(HDC, LPCWSTR, i32, *RECT, UINT) callconv(.c) i32;
pub extern "user32" fn SetWindowTextW(HWND, LPCWSTR) callconv(.c) BOOL;
pub extern "user32" fn GetWindowTextW(HWND, LPWSTR, i32) callconv(.c) i32;
pub extern "user32" fn GetDlgItem(HWND, i32) callconv(.c) HWND;
pub extern "user32" fn SetFocus(HWND) callconv(.c) HWND;
pub extern "user32" fn IsDialogMessageW(HWND, *MSG) callconv(.c) BOOL;
pub extern "user32" fn SetProcessDPIAware() callconv(.c) BOOL;
pub extern "user32" fn SetProcessDpiAwarenessContext(?*anyopaque) callconv(.c) BOOL;
pub extern "user32" fn GetKeyState(i32) callconv(.c) i16;
pub extern "user32" fn SendMessageW(HWND, UINT, WPARAM, LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn GetMenu(HWND) callconv(.c) HMENU;
pub extern "user32" fn GetSubMenu(HMENU, i32) callconv(.c) HMENU;
pub extern "user32" fn GetMenuItemCount(HMENU) callconv(.c) i32;
pub extern "user32" fn GetMenuItemID(HMENU, i32) callconv(.c) UINT;
/// 遍历子控件（自检用它把对话框里的标签文案收出来核对）
pub extern "user32" fn EnumChildWindows(HWND, ?*const fn (HWND, LPARAM) callconv(.c) BOOL, LPARAM) callconv(.c) BOOL;
pub extern "user32" fn IsChild(HWND, HWND) callconv(.c) BOOL;
pub extern "user32" fn GetFocus() callconv(.c) HWND;
pub extern "user32" fn GetWindowRect(HWND, *RECT) callconv(.c) BOOL;
pub extern "user32" fn GetParent(HWND) callconv(.c) HWND;
pub extern "user32" fn PrintWindow(HWND, HDC, UINT) callconv(.c) BOOL;
pub extern "user32" fn CreateIconIndirect(*ICONINFO) callconv(.c) HICON;
pub extern "user32" fn ScreenToClient(HWND, *POINT) callconv(.c) BOOL;
pub extern "user32" fn ClientToScreen(HWND, *POINT) callconv(.c) BOOL;
pub extern "user32" fn GetForegroundWindow() callconv(.c) HWND;
pub extern "user32" fn SetForegroundWindow(HWND) callconv(.c) BOOL;
pub extern "user32" fn GetDesktopWindow() callconv(.c) HWND;
pub extern "user32" fn SystemParametersInfoW(UINT, UINT, ?*anyopaque, UINT) callconv(.c) BOOL;

// ---- gdi32 ----
pub extern "gdi32" fn CreateCompatibleDC(HDC) callconv(.c) HDC;
pub extern "gdi32" fn CreateCompatibleBitmap(HDC, i32, i32) callconv(.c) HBITMAP;
pub extern "gdi32" fn CreateDIBSection(HDC, *const BITMAPINFO, UINT, *?*anyopaque, HANDLE, DWORD) callconv(.c) HBITMAP;
pub extern "gdi32" fn SelectObject(HDC, HGDIOBJ) callconv(.c) HGDIOBJ;
pub extern "gdi32" fn DeleteObject(HGDIOBJ) callconv(.c) BOOL;
pub extern "gdi32" fn DeleteDC(HDC) callconv(.c) BOOL;
pub extern "gdi32" fn BitBlt(HDC, i32, i32, i32, i32, HDC, i32, i32, DWORD) callconv(.c) BOOL;
pub extern "gdi32" fn StretchBlt(HDC, i32, i32, i32, i32, HDC, i32, i32, i32, i32, DWORD) callconv(.c) BOOL;
pub extern "gdi32" fn SetStretchBltMode(HDC, i32) callconv(.c) i32;
pub extern "gdi32" fn CreateSolidBrush(DWORD) callconv(.c) HBRUSH;
pub extern "gdi32" fn GetStockObject(i32) callconv(.c) HGDIOBJ;
pub extern "gdi32" fn SetBkMode(HDC, i32) callconv(.c) i32;
pub extern "gdi32" fn SetTextColor(HDC, DWORD) callconv(.c) DWORD;
pub extern "gdi32" fn SetBkColor(HDC, DWORD) callconv(.c) DWORD;
pub extern "gdi32" fn CreatePen(i32, i32, DWORD) callconv(.c) HGDIOBJ;
pub extern "gdi32" fn Rectangle(HDC, i32, i32, i32, i32) callconv(.c) BOOL;
pub extern "gdi32" fn MoveToEx(HDC, i32, i32, ?*POINT) callconv(.c) BOOL;
pub extern "gdi32" fn LineTo(HDC, i32, i32) callconv(.c) BOOL;
pub extern "gdi32" fn CreateFontW(i32, i32, i32, i32, i32, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, LPCWSTR) callconv(.c) HFONT;

// ---- kernel32 ----
pub extern "kernel32" fn GetModuleHandleW(LPCWSTR) callconv(.c) HMODULE;
pub extern "kernel32" fn GetTickCount() callconv(.c) DWORD;
pub extern "kernel32" fn GetTickCount64() callconv(.c) u64;
pub extern "kernel32" fn ExitProcess(UINT) callconv(.c) noreturn;
pub extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.c) BOOL;

pub const SM = struct {
    pub const CXSCREEN: i32 = 0;
    pub const CYSCREEN: i32 = 1;
    pub const CXFRAME: i32 = 32;
    pub const CYFRAME: i32 = 33;
    pub const CYCAPTION: i32 = 4;
    pub const CXMENU: i32 = 54;
    pub const CYSIZEFRAME: i32 = 32;
};

pub inline fn loWord(v: LPARAM) i32 {
    return @as(i32, @intCast(@as(u16, @truncate(@as(usize, @bitCast(v))))));
}
pub inline fn hiWord(v: LPARAM) i32 {
    const u: usize = @bitCast(v);
    return @as(i32, @intCast(@as(u16, @truncate(u >> 16))));
}
pub inline fn makeLParam(lo: i32, hi: i32) LPARAM {
    const l: usize = @as(u16, @intCast(@as(u32, @bitCast(lo)) & 0xFFFF));
    const h: usize = @as(u16, @intCast(@as(u32, @bitCast(hi)) & 0xFFFF));
    return @bitCast(l | (h << 16));
}
pub inline fn rgb(r: u8, g: u8, b: u8) DWORD {
    return @as(DWORD, r) | (@as(DWORD, g) << 8) | (@as(DWORD, b) << 16);
}
/// 经典 Win95/98 配色
pub const C_BTNFACE = rgb(0xC0, 0xC0, 0xC0);
pub const C_BTNSHADOW = rgb(0x80, 0x80, 0x80);
pub const C_BTNHIGHLIGHT = rgb(0xDF, 0xDF, 0xDF);
pub const C_BTNDKSHADOW = rgb(0x00, 0x00, 0x00);
pub const C_BTNLIGHT = rgb(0xFF, 0xFF, 0xFF);

/// 编译期把 UTF-8 字面量转成 UTF-16（只处理 BMP，够用）。
/// 用 comptime 块返回指向编译期常量的指针，字符串会被放进只读数据段。
pub fn wstr(comptime s: []const u8) *const [wlen(s):0]u16 {
    return comptime blk: {
        const N = wlen(s);
        var buf: [N:0]u16 = [_:0]u16{0} ** N;
        var i: usize = 0;
        var o: usize = 0;
        while (i < s.len) {
            const c = s[i];
            if (c < 0x80) {
                buf[o] = c;
                i += 1;
            } else if (c & 0xE0 == 0xC0) {
                buf[o] = (@as(u16, c & 0x1F) << 6) | @as(u16, s[i + 1] & 0x3F);
                i += 2;
            } else if (c & 0xF0 == 0xE0) {
                buf[o] = (@as(u16, c & 0x0F) << 12) | (@as(u16, s[i + 1] & 0x3F) << 6) | @as(u16, s[i + 2] & 0x3F);
                i += 3;
            } else {
                // 4 字节：转成代理对
                const cp: u21 = (@as(u21, c & 0x07) << 18) | (@as(u21, s[i + 1] & 0x3F) << 12) |
                    (@as(u21, s[i + 2] & 0x3F) << 6) | @as(u21, s[i + 3] & 0x3F);
                const v = cp - 0x10000;
                buf[o] = @intCast(0xD800 + (v >> 10));
                o += 1;
                buf[o] = @intCast(0xDC00 + (v & 0x3FF));
                i += 4;
            }
            o += 1;
        }
        const frozen = buf;
        break :blk &frozen;
    };
}
fn wlen(comptime s: []const u8) usize {
    var i: usize = 0;
    var n: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c < 0x80) {
            i += 1;
        } else if (c & 0xE0 == 0xC0) {
            i += 2;
        } else if (c & 0xF0 == 0xE0) {
            i += 3;
        } else {
            i += 4;
            n += 1; // 代理对占两个 u16
        }
        n += 1;
    }
    return n;
}

/// 运行时 ascii -> utf16（数字、路径这类）
pub fn asciiToW(buf: []u16, s: []const u8) [:0]u16 {
    const n = @min(s.len, buf.len - 1);
    for (s[0..n], 0..) |c, i| buf[i] = c;
    buf[n] = 0;
    return buf[0..n :0];
}

pub fn u32ToW(buf: []u16, v: u32) [:0]u16 {
    var tmp: [12]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}", .{v}) catch return buf[0..0 :0];
    return asciiToW(buf, s);
}

// ---- advapi32：最高分纪录写在 HKCU（和原版扫雷一样，不产生额外文件） ----
pub const HKEY_CURRENT_USER: usize = 0x80000001;
pub const KEY_READ: u32 = 0x20019;
pub const KEY_WRITE: u32 = 0x20006;
pub const REG_DWORD: u32 = 4;
pub const REG_OPTION_NON_VOLATILE: u32 = 0;
pub const ERROR_SUCCESS: i32 = 0;

pub extern "advapi32" fn RegCreateKeyExW(usize, LPCWSTR, u32, LPCWSTR, u32, u32, ?*anyopaque, *usize, ?*u32) callconv(.c) i32;
pub extern "advapi32" fn RegOpenKeyExW(usize, LPCWSTR, u32, u32, *usize) callconv(.c) i32;
pub extern "advapi32" fn RegSetValueExW(usize, LPCWSTR, u32, u32, [*]const u8, u32) callconv(.c) i32;
pub extern "advapi32" fn RegQueryValueExW(usize, LPCWSTR, ?*u32, ?*u32, ?[*]u8, ?*u32) callconv(.c) i32;
pub extern "advapi32" fn RegCloseKey(usize) callconv(.c) i32;