// Eldergrove's window effects: adapted from Bend's Linux window effects
// (bend2/effs/window_open.c, window_frame.c and window_close.c, Copyright
// HigherOrderCO, Apache License 2.0), with a parallel blit that fills each
// quadtree square at once instead of walking the tree per pixel, and a
// native Windows window (win/winplat.c) beside the X11 one.
// The view: the frame is 512 x 320 logical pixels, shown stretched over the
// window (mode 0) or at the largest whole-pixel scale that fits, centred
// (mode 1). Win.config asks for a new window size or mode; the frame's
// helper thread applies it before the next frame (it alone touches the
// window's pixels).
static volatile u32 pk_want_w, pk_want_h, pk_mode, pk_dirty;

#ifdef CID_WIN_CONFIG
Term win_config_run(Env e, Term* f, IoWork* w) {
  pk_want_w = (u32)f[1];
  pk_want_h = (u32)f[2];
  pk_mode   = (u32)f[3];
  pk_dirty  = 1;
  return f[0];
}

static void __attribute__((constructor)) win_config_use(void) {
  io_eff(CID_WIN_CONFIG, win_config_run, 0);
}
#endif

static void pk_view(u32 w, u32 h, u32* ox, u32* oy, u32* sw, u32* sh) {
  if (pk_mode == 1) {
    u32 s = w / 512 < h / 320 ? w / 512 : h / 320;
    if (s < 1) {
      s = 1;
    }
    *sw = 512 * s;
    *sh = 320 * s;
  } else {
    *sw = w;
    *sh = h;
  }
  *ox = w > *sw ? (w - *sw) / 2 : 0;
  *oy = h > *sh ? (h - *sh) / 2 : 0;
}

#if defined(__linux__) || defined(_WIN32)
// Window
// ======

// An event is five words: kind (0 key, 1 mouse, 2 move, 3 close) and
// its fields; a frame answers the events pumped since the last one.

static Term pkwindow_node(Env e, const u32* ev) {
  static const u32 cids[3] = { CID_KEY, CID_MOUSE, CID_MOVE };
  if (ev[0] == 3) {
    return term_pak(CID_CLOSE, 0);
  }
  u32 n = ev[0] == 1 ? 4 : 2;
  Loc l = heap_alloc(e, cls_fit(n));
  for (u32 j = 0; j < n; j += 1) {
    e.mem[l + j] = ev[1 + j];
  }
  return term_ctr(cids[ev[0]], l);
}

static Term pkwindow_list(Env e, const u32* p, u64 n) {
  Term list = term_pak(CID_NIL, 0);
  for (u64 i = n; i > 0;) {
    i -= 1;
    Loc l = heap_alloc(e, 1);
    e.mem[l]     = io_seal(e, pkwindow_node(e, p + 5 * i), CID_CON);
    e.mem[l + 1] = io_seal(e, list, CID_CON);
    list = term_ctr(CID_CON, l);
  }
  return list;
}

static u32 pkwindow_clip(int v, u32 most) {
  return v < 0 ? 0 : (u32)v < most ? (u32)v : most - 1;
}

// a window pixel as the game sees it: the frame at twice its logical size
static u32 pk_mx(int x, u32 ox, u32 sw) {
  return pkwindow_clip((int)(((long)x - (long)ox) * 1024 / (long)sw), 1024);
}

static u32 pk_my(int y, u32 oy, u32 sh) {
  return pkwindow_clip((int)(((long)y - (long)oy) * 640 / (long)sh), 640);
}

// The platform's window: pk_make and pk_close open and close it, pk_pixels
// gives its pixel buffer (0xRRGGBB words, rows top-down), pk_resize gives
// it a new size and a cleared buffer, pk_pump queues its events with
// pkwindow_push, and pk_put shows the buffer.
#if defined(__linux__)

#ifndef BendWin
#define BendWin BendWin
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

typedef struct {
  Display* dpy;
  Window   win;
  Atom     del;
  XImage*  img;
  u32      n;
  u32      cap;
  u32*     evs;
} BendWin;
#endif

#elif defined(_WIN32)

typedef struct {
  WinWin* ww;
  u32     n;
  u32     cap;
  u32*    evs;
} BendWin;

#endif

static void pkwindow_push(BendWin* win, u32 kind, u32 a, u32 b, u32 c, u32 d) {
  if (win->n == win->cap) {
    win->cap = win->cap == 0 ? 64 : win->cap * 2;
    win->evs = io_mem(realloc(win->evs, win->cap * 20));
  }
  u32 ev[5] = { kind, a, b, c, d };
  memcpy(win->evs + win->n * 5, ev, sizeof ev);
  win->n += 1;
}

#if defined(__linux__)

static u32 pk_make(const char* title, u32 w, u32 h, intptr_t* out,
  const char** why) {
  if (w < 1 || h < 1 || w > 16384 || h > 16384) {
    return EINVAL;
  }
  Display* dpy = XOpenDisplay(NULL);
  if (dpy == NULL) {
    *why = "Window.open: no display (build a native binary with bend <file> -o <out> and run it from a desktop session)";
    return ENOTSUP;
  }
  int scr = DefaultScreen(dpy);
  if (DefaultDepth(dpy, scr) < 24) {
    XCloseDisplay(dpy);
    *why = "Window.open: the display has no 24-bit visual";
    return ENOTSUP;
  }
  BendWin* win = io_mem(calloc(1, sizeof *win));
  win->dpy = dpy;
  win->win = XCreateSimpleWindow(dpy, RootWindow(dpy, scr), 0, 0, w, h, 0, 0,
    BlackPixel(dpy, scr));
  win->del = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
  win->img = XCreateImage(dpy, DefaultVisual(dpy, scr), DefaultDepth(dpy, scr),
    ZPixmap, 0, io_mem(calloc(w * h, 4)), w, h, 32, w * 4);
  win->img->byte_order = LSBFirst;
  XSizeHints hints = { .flags = PMinSize | PMaxSize, .min_width = w,
    .min_height = h, .max_width = w, .max_height = h };
  XSetWMNormalHints(dpy, win->win, &hints);
  XSetWMProtocols(dpy, win->win, &win->del, 1);
  XStoreName(dpy, win->win, title);
  XSelectInput(dpy, win->win, KeyPressMask | KeyReleaseMask | ButtonPressMask
    | ButtonReleaseMask | PointerMotionMask);
  XMapRaised(dpy, win->win);
  XFlush(dpy);
  *out = (intptr_t)win;
  return 0;
}

static void pk_close(BendWin* win) {
  XDestroyImage(win->img);
  XCloseDisplay(win->dpy);
  free(win->evs);
  free(win);
}

static u32* pk_pixels(BendWin* win, u32* w, u32* h) {
  *w = win->img->width;
  *h = win->img->height;
  return (u32*)win->img->data;
}

static void pk_resize(BendWin* win, u32 w, u32 h) {
  if (w != (u32)win->img->width || h != (u32)win->img->height) {
    XSizeHints hints = { .flags = PMinSize | PMaxSize, .min_width = w,
      .min_height = h, .max_width = w, .max_height = h };
    XSetWMNormalHints(win->dpy, win->win, &hints);
    XResizeWindow(win->dpy, win->win, w, h);
    int scr = DefaultScreen(win->dpy);
    XImage* old = win->img;
    win->img = XCreateImage(win->dpy, DefaultVisual(win->dpy, scr), DefaultDepth(win->dpy, scr),
      ZPixmap, 0, io_mem(calloc((size_t)w * h, 4)), w, h, 32, w * 4);
    win->img->byte_order = LSBFirst;
    XDestroyImage(old);
  }
  memset(win->img->data, 0, (size_t)w * h * 4);
}

// The Mac's key codes: a key's character in lower case, the function
// keys' private-use characters (the arrows at 63232), a modifier's
// 65536 + its key code.
static const u32 pkwindow_keys[][2] = {
  { XK_Escape,    27 },    { XK_Return,    13 },    { XK_KP_Enter,  13 },
  { XK_Tab,       9 },     { XK_BackSpace, 127 },   { XK_Up,        63232 },
  { XK_Down,      63233 }, { XK_Left,      63234 }, { XK_Right,     63235 },
  { XK_Insert,    63271 }, { XK_Delete,    63272 }, { XK_Home,      63273 },
  { XK_End,       63275 }, { XK_Page_Up,   63276 }, { XK_Page_Down, 63277 },
  { XK_Super_R,   65590 }, { XK_Super_L,   65591 }, { XK_Shift_L,   65592 },
  { XK_Caps_Lock, 65593 }, { XK_Alt_L,     65594 }, { XK_Control_L, 65595 },
  { XK_Shift_R,   65596 }, { XK_Alt_R,     65597 }, { XK_Control_R, 65598 },
};

static u32 pkwindow_key(XKeyEvent* ev) {
  char   c[8];
  KeySym ks = 0;
  ev->state &= ShiftMask | LockMask;
  int n = XLookupString(ev, c, sizeof c, &ks, NULL);
  for (u32 i = 0; i < sizeof pkwindow_keys / sizeof *pkwindow_keys; i += 1) {
    if (pkwindow_keys[i][0] == ks) {
      return pkwindow_keys[i][1];
    }
  }
  if (ks >= XK_F1 && ks <= XK_F12) {
    return 63236 + (u32)(ks - XK_F1);
  }
  if (n == 1 && (u8)c[0] >= 32) {
    return (u8)c[0] >= 'A' && (u8)c[0] <= 'Z' ? (u8)c[0] + 32 : (u8)c[0];
  }
  return 65536 + ev->keycode;
}

static void pk_pump(BendWin* win) {
  u32 ox, oy, sw, sh;
  pk_view(win->img->width, win->img->height, &ox, &oy, &sw, &sh);
  while (XPending(win->dpy) > 0) {
    XEvent ev;
    XNextEvent(win->dpy, &ev);
    if (ev.type == KeyPress || ev.type == KeyRelease) {
      pkwindow_push(win, 0, pkwindow_key(&ev.xkey), ev.type == KeyPress, 0, 0);
    } else if (ev.type == ButtonPress || ev.type == ButtonRelease) {
      u32 b = ev.xbutton.button;
      // the wheel: 4 up, 5 down, reported as buttons 5 and 6 when pressed
      if ((b == 4 || b == 5) && ev.type == ButtonPress) {
        pkwindow_push(win, 1, pk_mx(ev.xbutton.x, ox, sw),
          pk_my(ev.xbutton.y, oy, sh), b + 1, 1);
      }
      if (b >= 1 && b <= 3) {
        pkwindow_push(win, 1, pk_mx(ev.xbutton.x, ox, sw),
          pk_my(ev.xbutton.y, oy, sh), b == 1 ? 0 : 4 - b,
          ev.type == ButtonPress);
      }
    } else if (ev.type == MotionNotify) {
      pkwindow_push(win, 2, pk_mx(ev.xmotion.x, ox, sw),
        pk_my(ev.xmotion.y, oy, sh), 0, 0);
    } else if (ev.type == ClientMessage
      && (Atom)ev.xclient.data.l[0] == win->del) {
      pkwindow_push(win, 3, 0, 0, 0, 0);
    }
  }
}

static void pk_put(BendWin* win) {
  XPutImage(win->dpy, win->win, DefaultGC(win->dpy, DefaultScreen(win->dpy)),
    win->img, 0, 0, 0, 0, win->img->width, win->img->height);
  XFlush(win->dpy);
}

#elif defined(_WIN32)

static u32 pk_make(const char* title, u32 w, u32 h, intptr_t* out,
  const char** why) {
  if (w < 1 || h < 1 || w > 16384 || h > 16384) {
    return EINVAL;
  }
  WinWin* ww = winw_open(title, w, h, why);
  if (ww == NULL) {
    return ENOTSUP;
  }
  BendWin* win = io_mem(calloc(1, sizeof *win));
  win->ww = ww;
  *out = (intptr_t)win;
  return 0;
}

static void pk_close(BendWin* win) {
  winw_close(win->ww);
  free(win->evs);
  free(win);
}

static u32* pk_pixels(BendWin* win, u32* w, u32* h) {
  return winw_pixels(win->ww, w, h);
}

static void pk_resize(BendWin* win, u32 w, u32 h) {
  winw_resize(win->ww, w, h);
}

// winplat.c queues the events in window pixels; here they become the
// game's coordinates
static void pk_pump(BendWin* win) {
  u32 w, h, ox, oy, sw, sh;
  winw_pixels(win->ww, &w, &h);
  pk_view(w, h, &ox, &oy, &sw, &sh);
  u32 evs[5 * 64];
  u32 n;
  while ((n = winw_pump(win->ww, evs, 64)) > 0) {
    for (u32 i = 0; i < n; i += 1) {
      u32* ev = evs + 5 * i;
      if (ev[0] == 1 || ev[0] == 2) {
        ev[1] = pk_mx((int)ev[1], ox, sw);
        ev[2] = pk_my((int)ev[2], oy, sh);
      }
      pkwindow_push(win, ev[0], ev[1], ev[2], ev[3], ev[4]);
    }
  }
}

static void pk_put(BendWin* win) {
  winw_present(win->ww);
}

#endif

// The frame's pixels, filled from the image's quadtree
typedef struct {
  u32* pix;
  u32  w, ox, oy, sw, sh;
} PkView;

// a square of the logical frame (x0, y0, side 1 << k) onto its window pixels
static void pkfill_rec(Corpus H, Term t, u32 k, u32 x0, u32 y0, const PkView* v) {
  if (x0 >= 512 || y0 >= 320) {
    return;
  }
  if (term_tag(t) == TAG_CTR && k > 0) {
    Loc l = term_rfc(t) ? H[term_loc(t)] >> 24 : term_loc(t);
    u32 hs = 1u << (k - 1);
    pkfill_rec(H, H[l + 0], k - 1, x0, y0, v);
    pkfill_rec(H, H[l + 1], k - 1, x0 + hs, y0, v);
    pkfill_rec(H, H[l + 2], k - 1, x0, y0 + hs, v);
    pkfill_rec(H, H[l + 3], k - 1, x0 + hs, y0 + hs, v);
    return;
  }
  while (term_tag(t) == TAG_CTR) {
    Loc l = term_rfc(t) ? H[term_loc(t)] >> 24 : term_loc(t);
    t = H[l];
  }
  u32 c = (u32)term_loc(t) & 0xFFFFFF;
  u32 s = 1u << k;
  u32 lx1 = x0 + s < 512 ? x0 + s : 512;
  u32 ly1 = y0 + s < 320 ? y0 + s : 320;
  u32 X0 = v->ox + x0 * v->sw / 512, X1 = v->ox + lx1 * v->sw / 512;
  u32 Y0 = v->oy + y0 * v->sh / 320, Y1 = v->oy + ly1 * v->sh / 320;
  for (u32 y = Y0; y < Y1; y += 1) {
    u32* row = v->pix + (u64)y * v->w;
    for (u32 x = X0; x < X1; x += 1) {
      row[x] = c;
    }
  }
}

#include <pthread.h>

typedef struct {
  Corpus        H;
  Term          t;
  u32           k, x0, y0;
  const PkView* v;
} PkJob;

static void* pkfill_job(void* arg) {
  PkJob* j = (PkJob*)arg;
  pkfill_rec(j->H, j->t, j->k, j->x0, j->y0, j->v);
  return NULL;
}

// the 16 squares two levels down are filled on their own threads
static void pkwindow_fill(Corpus H, const PkView* v, Term image, u32 k) {
  PkJob jobs[16];
  pthread_t th[16];
  u32 n = 0;
  Term top = image;
  if (term_tag(top) != TAG_CTR || k < 2) {
    pkfill_rec(H, image, k, 0, 0, v);
    return;
  }
  Loc l = term_rfc(top) ? H[term_loc(top)] >> 24 : term_loc(top);
  u32 hs = 1u << (k - 1);
  for (u32 q = 0; q < 4; q += 1) {
    Term c = H[l + q];
    u32 cx = (q & 1) * hs;
    u32 cy = (q >> 1) * hs;
    if (term_tag(c) != TAG_CTR) {
      pkfill_rec(H, c, k - 1, cx, cy, v);
      continue;
    }
    Loc m = term_rfc(c) ? H[term_loc(c)] >> 24 : term_loc(c);
    u32 qs = hs >> 1;
    for (u32 r = 0; r < 4; r += 1) {
      PkJob* j = &jobs[n];
      j->H = H; j->t = H[m + r]; j->k = k - 2;
      j->x0 = cx + (r & 1) * qs; j->y0 = cy + (r >> 1) * qs;
      j->v = v;
      pthread_create(&th[n], NULL, pkfill_job, j);
      n += 1;
    }
  }
  for (u32 i = 0; i < n; i += 1) {
    pthread_join(th[i], NULL);
  }
}

// A frame waits for the next 60 Hz tick, as the Mac's display sync.
static void pkwindow_pace(void) {
  static u64 due;
  static int off = -1;
  if (off < 0) {
    off = getenv("PARK_NOPACE") != NULL;
  }
  if (off) {
    return;
  }
  // keep the cadence: a late wake-up is absorbed by the next frame, and
  // only a frame that misses a whole slot resets the schedule
  u64 now = io_tick();
  if (due > now) {
    struct timespec ts = { 0, (long)(due - now) };
    nanosleep(&ts, NULL);
  }
  due = (now > due + 16666667 ? now : due) + 16666667;
}

// The frame runs on a helper thread (io_work), so the event loop, and the
// worker pool, carry on with other computations -- the game computes its
// next frame while this one is filled, paced and shown. Only the helper
// touches the window between the effect's start and its pack.
typedef struct {
  Corpus H;
  Term   image;
} PkArgs;

// a new window size or view mode, asked for by Win.config
static void pk_apply(BendWin* win) {
  pk_dirty = 0;
  u32 w = pk_want_w, h = pk_want_h;
  if (w < 512 || h < 320 || w > 4096 || h > 4096) {
    return;
  }
  pk_resize(win, w, h);
}

static void pkwindow_show(Corpus H, BendWin* win, Term image) {
  static u64 n, tf, tp, tx, last;
  u32 w, h;
  PkView v;
  v.pix = pk_pixels(win, &w, &h);
  v.w   = w;
  pk_view(w, h, &v.ox, &v.oy, &v.sw, &v.sh);
  u64 t0 = io_tick();
  pkwindow_fill(H, &v, image, 9);
  u64 t1 = io_tick();
  pkwindow_pace();
  u64 t2 = io_tick();
  pk_put(win);
  u64 t3 = io_tick();
  tf += t1 - t0; tp += t2 - t1; tx += t3 - t2;
  // PARK_DUMP=path: write the 300th frame's pixels as it was shown (PPM)
  static u64 shown;
  const char* dump = getenv("PARK_DUMP");
  if (dump && ++shown == 300) {
    FILE* fp = fopen(dump, "wb");
    if (fp) {
      fprintf(fp, "P6\n%u %u\n255\n", w, h);
      for (u64 i = 0; i < (u64)w * h; i += 1) {
        unsigned char rgb[3] = { (v.pix[i] >> 16) & 255, (v.pix[i] >> 8) & 255, v.pix[i] & 255 };
        fwrite(rgb, 1, 3, fp);
      }
      fclose(fp);
    }
  }
  if (getenv("PARK_PROF") && ++n % 64 == 0) {
    fprintf(stderr, "fill %.1fms pace %.1fms put %.1fms frame %.1fms\n", tf / 64e6,
      tp / 64e6, tx / 64e6, (t3 - last) / 64e6);
    tf = tp = tx = 0; last = t3;
  }
}

static void pkframe_call(IoWork* w) {
  BendWin* win = (BendWin*)w->hand;
  PkArgs*  a   = (PkArgs*)w->data;
  if (pk_dirty) {
    pk_apply(win);
  }
  pk_pump(win);
  pkwindow_show(a->H, win, a->image);
}

static Term pkframe_pack(Env e, IoWork* w) {
  BendWin* win   = (BendWin*)w->hand;
  PkArgs*  a     = (PkArgs*)w->data;
  Term     image = a->image;
  Term     list  = pkwindow_list(e, win->evs, win->n);
  win->n = 0;
  free(a);
  w->data = NULL;
  return io_tup(e, io_hand(w->hand), io_tup(e, image, list));
}

#else

typedef struct {
  u32 n;
} BendWin;

static u32 pk_make(const char* title, u32 w, u32 h, intptr_t* out,
  const char** why) {
  *why = "Window.open: no display (build a native binary with bend <file> -o <out> and run it from a desktop session)";
  return ENOTSUP;
}

static void pk_close(BendWin* win) {
}

#endif

#ifdef CID_WIN_OPEN
Term win_open_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* title = io_cstr(e, f[0], &n);
  intptr_t out;
  const char* why = NULL;
  u32 q = io_nul(title, n) ? EILSEQ
    : pk_make(title, (u32)f[1], (u32)f[2], &out, &why);
  free(title);
  if (q != 0) {
    return io_fail(e, q, why);
  }
  return io_done(e, io_hand(out));
}

static void __attribute__((constructor)) win_open_use(void) {
  io_eff(CID_WIN_OPEN, win_open_run, 0);
}
#endif

#ifdef CID_WIN_CLOSE
Term win_close_run(Env e, Term* f, IoWork* w) {
  pk_close((BendWin*)(intptr_t)io_hand_v(f[0]));
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) win_close_use(void) {
  io_eff(CID_WIN_CLOSE, win_close_run, 0);
}
#endif

#if defined(__linux__) || defined(_WIN32)
Term win_frame_run(Env e, Term* f, IoWork* w) {
  io_sync();
  PkArgs* a = io_mem(malloc(sizeof *a));
  a->H     = e.mem;
  a->image = f[1];
  w->hand  = (intptr_t)io_hand_v(f[0]);
  w->data  = (char*)a;
  return io_work(w, pkframe_call, pkframe_pack);
}

static void __attribute__((constructor)) win_frame_use(void) {
  io_eff(CID_WIN_FRAME, win_frame_run, 0);
}
#endif
