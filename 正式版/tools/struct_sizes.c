/* 打印 X11 结构体的大小与关键字段偏移，和 src/x11.zig 里手写的声明对账。
 * 手写 extern struct 少一个成员，后面所有字段都会错位——这类 bug 同样是静默的。 */
#include <stdio.h>
#include <stddef.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/Xrender.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <X11/Xft/Xft.h>

#define SZ(t)      printf("%-24s size=%zu align=%zu\n", #t, sizeof(t), _Alignof(t))
#define OFF(t, f)  printf("  %-22s offset=%zu\n", #t "." #f, offsetof(t, f))

int main(void)
{
    SZ(XSizeHints);
    OFF(XSizeHints, flags); OFF(XSizeHints, x); OFF(XSizeHints, y);
    OFF(XSizeHints, width); OFF(XSizeHints, height); OFF(XSizeHints, min_width);
    OFF(XSizeHints, min_height); OFF(XSizeHints, max_width); OFF(XSizeHints, max_height);
    OFF(XSizeHints, width_inc); OFF(XSizeHints, height_inc); OFF(XSizeHints, min_aspect);
    OFF(XSizeHints, max_aspect); OFF(XSizeHints, win_gravity);

    SZ(XWMHints);
    OFF(XWMHints, flags); OFF(XWMHints, input); OFF(XWMHints, initial_state);
    OFF(XWMHints, icon_pixmap); OFF(XWMHints, icon_window); OFF(XWMHints, icon_x);
    OFF(XWMHints, icon_y); OFF(XWMHints, icon_mask); OFF(XWMHints, window_group);

    SZ(XSetWindowAttributes);
    OFF(XSetWindowAttributes, background_pixmap); OFF(XSetWindowAttributes, background_pixel);
    OFF(XSetWindowAttributes, border_pixmap); OFF(XSetWindowAttributes, border_pixel);
    OFF(XSetWindowAttributes, bit_gravity); OFF(XSetWindowAttributes, win_gravity);
    OFF(XSetWindowAttributes, backing_store); OFF(XSetWindowAttributes, backing_planes);
    OFF(XSetWindowAttributes, backing_pixel); OFF(XSetWindowAttributes, override_redirect);
    OFF(XSetWindowAttributes, save_under); OFF(XSetWindowAttributes, event_mask);
    OFF(XSetWindowAttributes, do_not_propagate_mask); OFF(XSetWindowAttributes, colormap);
    OFF(XSetWindowAttributes, cursor);

    SZ(XWindowAttributes);
    OFF(XWindowAttributes, x); OFF(XWindowAttributes, y); OFF(XWindowAttributes, width);
    OFF(XWindowAttributes, height); OFF(XWindowAttributes, border_width);
    OFF(XWindowAttributes, depth); OFF(XWindowAttributes, visual);
    OFF(XWindowAttributes, root); OFF(XWindowAttributes, class);
    OFF(XWindowAttributes, bit_gravity); OFF(XWindowAttributes, win_gravity);
    OFF(XWindowAttributes, backing_store); OFF(XWindowAttributes, backing_planes);
    OFF(XWindowAttributes, backing_pixel); OFF(XWindowAttributes, save_under);
    OFF(XWindowAttributes, map_installed); OFF(XWindowAttributes, map_state);
    OFF(XWindowAttributes, all_event_masks); OFF(XWindowAttributes, your_event_mask);
    OFF(XWindowAttributes, do_not_propagate_mask); OFF(XWindowAttributes, override_redirect);
    OFF(XWindowAttributes, colormap);

    SZ(XImage);
    OFF(XImage, width); OFF(XImage, height); OFF(XImage, xoffset); OFF(XImage, format);
    OFF(XImage, data); OFF(XImage, byte_order); OFF(XImage, bitmap_unit);
    OFF(XImage, bitmap_bit_order); OFF(XImage, bitmap_pad); OFF(XImage, depth);
    OFF(XImage, bytes_per_line); OFF(XImage, bits_per_pixel); OFF(XImage, red_mask);
    OFF(XImage, green_mask); OFF(XImage, blue_mask);

    SZ(XRenderColor);
    OFF(XRenderColor, red); OFF(XRenderColor, green); OFF(XRenderColor, blue); OFF(XRenderColor, alpha);

    SZ(XftColor);
    OFF(XftColor, pixel); OFF(XftColor, color);

    SZ(XGlyphInfo);
    OFF(XGlyphInfo, width); OFF(XGlyphInfo, height); OFF(XGlyphInfo, x); OFF(XGlyphInfo, y);
    OFF(XGlyphInfo, xOff); OFF(XGlyphInfo, yOff);

    SZ(XErrorEvent);
    OFF(XErrorEvent, type); OFF(XErrorEvent, display); OFF(XErrorEvent, resourceid);
    OFF(XErrorEvent, serial); OFF(XErrorEvent, error_code); OFF(XErrorEvent, request_code);
    OFF(XErrorEvent, minor_code);

    SZ(XEvent);
    SZ(XKeyEvent);
    OFF(XKeyEvent, type); OFF(XKeyEvent, serial); OFF(XKeyEvent, send_event);
    OFF(XKeyEvent, display); OFF(XKeyEvent, window); OFF(XKeyEvent, root);
    OFF(XKeyEvent, subwindow); OFF(XKeyEvent, time); OFF(XKeyEvent, x);
    OFF(XKeyEvent, y); OFF(XKeyEvent, x_root); OFF(XKeyEvent, y_root);
    OFF(XKeyEvent, state); OFF(XKeyEvent, keycode);
    printf("sizeof(union _XEvent)=%zu  (按 192 字节切片解码的前提)\n", sizeof(XEvent));

    /* XVisualInfo：帧缓冲通道布局全靠它。不能只靠 depth 猜 red/green/blue_mask，
       因为同样是 24 位 TrueColor，有的服务器是 0xff0000/0xff00/0xff（R 在高位，
       内存即 BGRA），有的是 0xff/0xff00/0xff0000（R 在低位，内存即 RGBA）。
       写死一个就会在另一种布局的桌面上把红蓝显示反 —— 灰色看不出来，
       红色数字会变成蓝色、在黑底上几乎看不见。 */
    SZ(XVisualInfo);
    OFF(XVisualInfo, visual); OFF(XVisualInfo, visualid); OFF(XVisualInfo, screen);
    OFF(XVisualInfo, depth); OFF(XVisualInfo, red_mask);
    OFF(XVisualInfo, green_mask); OFF(XVisualInfo, blue_mask);
    OFF(XVisualInfo, colormap_size); OFF(XVisualInfo, bits_per_rgb);
    return 0;
}
