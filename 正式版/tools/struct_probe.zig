// 打印 x11.zig 里手写结构体的 sizeof / offsetOf，和 tools/struct_sizes.c 的 C 输出对账。
// 手写 extern struct 少一个成员，后面所有字段都会错位，而且是静默的。
const std = @import("std");
const x = @import("x11.zig");

fn sz(comptime T: type, comptime name: []const u8) void {
    std.debug.print("{s:<28} size={d} align={d}\n", .{ name, @sizeOf(T), @alignOf(T) });
}

fn off(comptime T: type, comptime name: []const u8) void {
    std.debug.print("  {s:<40} offset={d}\n", .{ name, @offsetOf(T, name) });
}

pub fn main() void {
    sz(x.XSizeHints, "XSizeHints");
    off(x.XSizeHints, "flags"); off(x.XSizeHints, "x"); off(x.XSizeHints, "y");
    off(x.XSizeHints, "width"); off(x.XSizeHints, "height"); off(x.XSizeHints, "min_width");
    off(x.XSizeHints, "min_height"); off(x.XSizeHints, "max_width"); off(x.XSizeHints, "max_height");
    off(x.XSizeHints, "width_inc"); off(x.XSizeHints, "height_inc"); off(x.XSizeHints, "min_aspect_x"); off(x.XSizeHints, "min_aspect_y");
    off(x.XSizeHints, "max_aspect_x"); off(x.XSizeHints, "max_aspect_y");
    off(x.XSizeHints, "base_width"); off(x.XSizeHints, "base_height"); off(x.XSizeHints, "win_gravity");

    sz(x.XWMHints, "XWMHints");
    off(x.XWMHints, "flags"); off(x.XWMHints, "input"); off(x.XWMHints, "initial_state");
    off(x.XWMHints, "icon_pixmap"); off(x.XWMHints, "icon_window"); off(x.XWMHints, "icon_x");
    off(x.XWMHints, "icon_y"); off(x.XWMHints, "icon_mask"); off(x.XWMHints, "window_group");

    sz(x.XSetWindowAttributes, "XSetWindowAttributes");
    off(x.XSetWindowAttributes, "background_pixmap"); off(x.XSetWindowAttributes, "background_pixel");
    off(x.XSetWindowAttributes, "border_pixmap"); off(x.XSetWindowAttributes, "border_pixel");
    off(x.XSetWindowAttributes, "bit_gravity"); off(x.XSetWindowAttributes, "win_gravity");
    off(x.XSetWindowAttributes, "backing_store"); off(x.XSetWindowAttributes, "backing_planes");
    off(x.XSetWindowAttributes, "backing_pixel"); off(x.XSetWindowAttributes, "override_redirect");
    off(x.XSetWindowAttributes, "save_under"); off(x.XSetWindowAttributes, "event_mask");
    off(x.XSetWindowAttributes, "do_not_propagate_mask"); off(x.XSetWindowAttributes, "colormap");
    off(x.XSetWindowAttributes, "cursor");

    sz(x.XWindowAttributes, "XWindowAttributes");
    off(x.XWindowAttributes, "x"); off(x.XWindowAttributes, "y"); off(x.XWindowAttributes, "width");
    off(x.XWindowAttributes, "height"); off(x.XWindowAttributes, "border_width");
    off(x.XWindowAttributes, "depth"); off(x.XWindowAttributes, "visual");
    off(x.XWindowAttributes, "root"); off(x.XWindowAttributes, "c_class");
    off(x.XWindowAttributes, "bit_gravity"); off(x.XWindowAttributes, "win_gravity");
    off(x.XWindowAttributes, "backing_store"); off(x.XWindowAttributes, "backing_planes");
    off(x.XWindowAttributes, "backing_pixel"); off(x.XWindowAttributes, "save_under");
    off(x.XWindowAttributes, "map_installed"); off(x.XWindowAttributes, "map_state");
    off(x.XWindowAttributes, "all_event_masks"); off(x.XWindowAttributes, "your_event_mask");
    off(x.XWindowAttributes, "do_not_propagate_mask"); off(x.XWindowAttributes, "override_redirect");
    off(x.XWindowAttributes, "colormap");

    sz(x.XImage, "XImage");
    off(x.XImage, "width"); off(x.XImage, "height"); off(x.XImage, "xoffset"); off(x.XImage, "format");
    off(x.XImage, "data"); off(x.XImage, "byte_order"); off(x.XImage, "bitmap_unit");
    off(x.XImage, "bitmap_bit_order"); off(x.XImage, "bitmap_pad"); off(x.XImage, "depth");
    off(x.XImage, "bytes_per_line"); off(x.XImage, "bits_per_pixel"); off(x.XImage, "red_mask");
    off(x.XImage, "green_mask"); off(x.XImage, "blue_mask");

    sz(x.XRenderColor, "XRenderColor");
    off(x.XRenderColor, "red"); off(x.XRenderColor, "green"); off(x.XRenderColor, "blue"); off(x.XRenderColor, "alpha");

    sz(x.XftColor, "XftColor");
    off(x.XftColor, "pixel"); off(x.XftColor, "color");

    sz(x.XGlyphInfo, "XGlyphInfo");
    off(x.XGlyphInfo, "width"); off(x.XGlyphInfo, "height"); off(x.XGlyphInfo, "x"); off(x.XGlyphInfo, "y");
    off(x.XGlyphInfo, "xOff"); off(x.XGlyphInfo, "yOff");

    sz(x.XErrorEvent, "XErrorEvent");
    off(x.XErrorEvent, "type"); off(x.XErrorEvent, "display"); off(x.XErrorEvent, "resourceid");
    off(x.XErrorEvent, "serial"); off(x.XErrorEvent, "error_code"); off(x.XErrorEvent, "request_code");
    off(x.XErrorEvent, "minor_code");

    sz(x.XKeyEventZ, "XKeyEvent");
    off(x.XKeyEventZ, "type"); off(x.XKeyEventZ, "serial"); off(x.XKeyEventZ, "send_event");
    off(x.XKeyEventZ, "display"); off(x.XKeyEventZ, "window"); off(x.XKeyEventZ, "root");
    off(x.XKeyEventZ, "subwindow"); off(x.XKeyEventZ, "time"); off(x.XKeyEventZ, "x");
    off(x.XKeyEventZ, "y"); off(x.XKeyEventZ, "x_root"); off(x.XKeyEventZ, "y_root");
    off(x.XKeyEventZ, "state"); off(x.XKeyEventZ, "keycode");

    sz(x.XVisualInfo, "XVisualInfo");
    off(x.XVisualInfo, "visual"); off(x.XVisualInfo, "visualid"); off(x.XVisualInfo, "screen");
    off(x.XVisualInfo, "depth"); off(x.XVisualInfo, "red_mask");
    off(x.XVisualInfo, "green_mask"); off(x.XVisualInfo, "blue_mask");
    off(x.XVisualInfo, "colormap_size"); off(x.XVisualInfo, "bits_per_rgb");
}
