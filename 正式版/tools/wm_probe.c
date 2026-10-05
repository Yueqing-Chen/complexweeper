/* wm_probe —— 在**没有窗口管理器**的环境里模拟 WM 的行为，用来复现真机上才看得到的问题。
 *
 * 三个子命令：
 *   close <winid>   往窗口发 WM_PROTOCOLS / WM_DELETE_WINDOW 的 ClientMessage
 *                   —— 等价于用户在真实桌面点右上角的叉。不装 WM 也能验关窗处理。
 *   dump <winid> <x> <y> <w> <h> <out.ppm>
 *                   用 XGetImage 把窗口的一块像素读回来存成 PPM。
 *                   —— 判断「数字到底有没有画进去」：图上有没有，跟有没有送到窗口上是两件事。
 *   grab <winid> <n> <prefix> <interval_ms>
 *                   连续抓 n 帧窗口全图，间隔 interval_ms。
 *                   —— 判断「图标抖动」：逐帧 diff，看是整块闪还是只在某个区域抖。
 *
 * 依赖：libX11（不需要 libXft、不需要 WM）。编译：cc wm_probe.c -lX11 -o wm_probe
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>   /* XGetPixel / XDestroyImage 是这里的宏 */
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* X 错误处理器：默认的会 exit()，探测工具里绝不许它把进程带走 */
static int swallow_errors(Display *d, XErrorEvent *e) {
    (void)d;
    fprintf(stderr, "[wm_probe] X error: code=%d request=%d minor=%d\n",
            e->error_code, e->request_code, e->minor_code);
    return 0;
}

static unsigned long parse_win(const char *s) { return strtoul(s, NULL, 0); }

static int cmd_close(Display *d, unsigned long win) {
    Atom proto = XInternAtom(d, "WM_PROTOCOLS", False);
    Atom del  = XInternAtom(d, "WM_DELETE_WINDOW", False);

    /* 先确认窗口确实声明了 WM_DELETE_WINDOW，否则「没反应」是别的原因 */
    Atom actual_type = None;
    int actual_fmt = 0;
    unsigned long n_items = 0, bytes_after = 0;
    unsigned char *data = NULL;
    if (XGetWindowProperty(d, (Window)win, proto, 0, 32, False, AnyPropertyType,
                           &actual_type, &actual_fmt, &n_items, &bytes_after, &data) == Success) {
        printf("WM_PROTOCOLS: type=%lu fmt=%d items=%lu\n",
               (unsigned long)actual_type, actual_fmt, n_items);
        if (data) {
            Atom *atoms = (Atom *)(void *)data;
            printf("  contains WM_DELETE_WINDOW: %s\n",
                   (n_items > 0 && atoms[0] == del) ? "yes" : "no");
        }
        if (data) XFree(data);
    } else {
        printf("WM_PROTOCOLS: read failed\n");
    }

    XEvent ev;
    memset(&ev, 0, sizeof ev);
    ev.xclient.type             = ClientMessage;
    ev.xclient.window           = (Window)win;
    ev.xclient.message_type     = proto;   /* 必须在 @40 */
    ev.xclient.format           = 32;      /* 必须在 @48 */
    ev.xclient.data.l[0]        = (long)del; /* 协议原子在 @56 */
    ev.xclient.data.l[1]        = CurrentTime;
    XSendEvent(d, (Window)win, False, NoEventMask, &ev);
    XFlush(d);
    printf("sent WM_DELETE_WINDOW to 0x%lx\n", win);
    return 0;
}

/* 读回一块像素存 PPM（24 位真彩，无损、无压缩依赖） */
static int cmd_dump(Display *d, unsigned long win, int x, int y, int w, int h, const char *out) {
    XImage *img = XGetImage(d, (Drawable)win, x, y, (unsigned)w, (unsigned)h,
                            AllPlanes, ZPixmap);
    if (!img) { fprintf(stderr, "XGetImage failed\n"); return 1; }

    FILE *f = fopen(out, "wb");
    if (!f) { perror("fopen"); return 1; }
    fprintf(f, "P6\n%d %d\n255\n", w, h);

    /* 用 XGetPixel 逐点取，正确处理任意 visual 的通道掩码，
       免得把 32 位 ARGB visual 当成 24 位读偏 */
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            unsigned long p = XGetPixel(img, i, j);
            unsigned char rgb[3];
            /* XImage 的 red_mask 等字段是这次读回的真实掩码 */
            rgb[0] = (unsigned char)((p & img->red_mask)   >> 16);
            rgb[1] = (unsigned char)((p & img->green_mask) >> 8);
            rgb[2] = (unsigned char)( p & img->blue_mask);
            fwrite(rgb, 1, 3, f);
        }
    }
    fclose(f);
    XDestroyImage(img);
    printf("dumped %dx%d+%d+%d -> %s\n", w, h, x, y, out);
    return 0;
}

static int cmd_grab(Display *d, unsigned long win, int n, const char *prefix, int interval) {
    XWindowAttributes wa;
    if (!XGetWindowAttributes(d, (Window)win, &wa)) {
        fprintf(stderr, "XGetWindowAttributes failed\n"); return 1;
    }
    int w = wa.width, h = wa.height;
    printf("window 0x%lx is %dx%d at +%d+%d depth=%d\n", win, w, h, wa.x, wa.y, wa.depth);
    for (int f = 0; f < n; f++) {
        char path[512];
        snprintf(path, sizeof path, "%s%03d.ppm", prefix, f);
        cmd_dump(d, win, 0, 0, w, h, path);
        if (interval > 0 && f + 1 < n) usleep((useconds_t)interval * 1000);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr,
            "usage: wm_probe close  <winid>\n"
            "       wm_probe dump   <winid> <x> <y> <w> <h> <out.ppm>\n"
            "       wm_probe grab   <winid> <n> <prefix> [interval_ms]\n");
        return 2;
    }
    Display *d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "cannot open display\n"); return 1; }
    XSetErrorHandler(swallow_errors);

    int rc = 2;
    if      (!strcmp(argv[1], "close")) rc = cmd_close(d, parse_win(argv[2]));
    else if (!strcmp(argv[1], "dump"))  rc = cmd_dump(d, parse_win(argv[2]), atoi(argv[3]),
                                                      atoi(argv[4]), atoi(argv[5]),
                                                      atoi(argv[6]), argv[7]);
    else if (!strcmp(argv[1], "grab"))  rc = cmd_grab(d, parse_win(argv[2]), atoi(argv[3]),
                                                      argv[4], argc > 5 ? atoi(argv[5]) : 60);
    else fprintf(stderr, "unknown command: %s\n", argv[1]);

    XCloseDisplay(d);
    return rc;
}
