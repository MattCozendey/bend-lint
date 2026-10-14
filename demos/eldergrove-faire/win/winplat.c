// Eldergrove Faire's Windows platform layer: the POSIX calls that Bend's
// generated runtime makes (declared in compat/bend_win.h), the native
// window behind win_frame.c, and the sound device behind snd.c.
//
// Compiled on its own, so windows.h never meets the generated code.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <mmsystem.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <io.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>
#include <stdbool.h>
#include <signal.h>

typedef struct WinWin WinWin;
typedef struct WinSnd WinSnd;

// Memory
// ======

// Every mmap is an address-space reservation (MEM_RESERVE). A touch of a
// reserved page faults; the handler commits the 1 MiB around it (within
// the reservation, never over a guard) and the access runs again. This is
// what MAP_NORESERVE gives the runtime on Linux: its 8 GiB corpus and its
// 2 GiB work stacks cost only the pages they use.
#define WIN_CHUNK (1u << 20)
#define WIN_RES   1024

typedef struct {
  char* volatile base;
  size_t size;
  char*  guard;  // a PROT_NONE range inside, or NULL
  size_t glen;
} WinRes;

static WinRes        win_res[WIN_RES];
static volatile LONG win_nres;
static SRWLOCK       win_res_lock = SRWLOCK_INIT;
static void (*win_segv)(int);

static WinRes* win_res_at(const char* a) {
  LONG n = win_nres;
  for (LONG i = 0; i < n; i += 1) {
    char* b = win_res[i].base;
    if (b != NULL && a >= b && a < b + win_res[i].size) {
      return &win_res[i];
    }
  }
  return NULL;
}

void* win_mmap(void* at, size_t len, int prot, int flags, int fd, long long off) {
  (void)prot; (void)flags; (void)off;
  if (fd != -1) {
    errno = ENOTSUP;
    return (void*)-1;
  }
  void* p = VirtualAlloc(at, len, MEM_RESERVE, PAGE_READWRITE);
  if (p == NULL && at != NULL) {
    p = VirtualAlloc(NULL, len, MEM_RESERVE, PAGE_READWRITE);
  }
  if (p == NULL) {
    errno = ENOMEM;
    return (void*)-1;
  }
  AcquireSRWLockExclusive(&win_res_lock);
  LONG i = 0;
  while (i < win_nres && win_res[i].base != NULL) {
    i += 1;
  }
  if (i == WIN_RES) {
    ReleaseSRWLockExclusive(&win_res_lock);
    VirtualFree(p, 0, MEM_RELEASE);
    errno = ENOMEM;
    return (void*)-1;
  }
  win_res[i].size  = len;
  win_res[i].guard = NULL;
  win_res[i].glen  = 0;
  MemoryBarrier();
  win_res[i].base = p;
  if (i == win_nres) {
    InterlockedIncrement(&win_nres);
  }
  ReleaseSRWLockExclusive(&win_res_lock);
  return p;
}

int win_munmap(void* at, size_t len) {
  AcquireSRWLockExclusive(&win_res_lock);
  WinRes* r = win_res_at(at);
  int ok;
  if (r != NULL && r->base == at) {
    r->base = NULL;
    ok = VirtualFree(at, 0, MEM_RELEASE);
  } else {
    ok = VirtualFree(at, len, MEM_DECOMMIT);
  }
  ReleaseSRWLockExclusive(&win_res_lock);
  return ok ? 0 : -1;
}

int win_mprotect(void* at, size_t len, int prot) {
  WinRes* r = win_res_at(at);
  if (r == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (prot == 0) {
    r->guard = at;
    r->glen  = len;
  }
  return 0;
}

static LONG CALLBACK win_fault(EXCEPTION_POINTERS* x) {
  EXCEPTION_RECORD* e = x->ExceptionRecord;
  if (e->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || e->NumberParameters < 2) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  char*   a = (char*)e->ExceptionInformation[1];
  WinRes* r = win_res_at(a);
  if (r == NULL || (r->guard != NULL && a >= r->guard && a < r->guard + r->glen)) {
    if (r != NULL && win_segv != NULL) {
      win_segv(11);
    }
    return EXCEPTION_CONTINUE_SEARCH;
  }
  MEMORY_BASIC_INFORMATION mi;
  if (VirtualQuery(a, &mi, sizeof mi) == 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  if (mi.State == MEM_COMMIT) {
    return EXCEPTION_CONTINUE_EXECUTION;  // another thread got there first
  }
  char* lo = (char*)((uintptr_t)a & ~(uintptr_t)(WIN_CHUNK - 1));
  char* hi = lo + WIN_CHUNK;
  if (lo < r->base) {
    lo = r->base;
  }
  if (hi > r->base + r->size) {
    hi = r->base + r->size;
  }
  if (r->guard != NULL) {
    if (r->guard >= a && r->guard < hi) {
      hi = r->guard;
    }
    if (r->guard + r->glen <= a && r->guard + r->glen > lo) {
      lo = r->guard + r->glen;
    }
  }
  if (VirtualAlloc(lo, (size_t)(hi - lo), MEM_COMMIT, PAGE_READWRITE) == NULL) {
    fflush(stdout);
    fprintf(stderr, "bend: out of memory (Windows could not commit more pages)\n");
    _exit(1);
  }
  return EXCEPTION_CONTINUE_EXECUTION;
}

// Signals
// =======

typedef struct {
  void*  ss_sp;
  int    ss_flags;
  size_t ss_size;
} win_stack_t;

struct win_sigaction {
  void (*sa_handler)(int);
  int sa_flags;
};

int win_sigaltstack(const win_stack_t* ss, win_stack_t* old) {
  (void)ss; (void)old;
  return 0;
}

int win_sigaction(int sig, const struct win_sigaction* sa, struct win_sigaction* old) {
  (void)old;
  if (sig == 11 && sa != NULL) {
    win_segv = sa->sa_handler;
  }
  return 0;
}

// Only the signals the CRT knows go to it: the UCRT treats any other
// number as an invalid parameter and ends the process.
void (*win_signal(int sig, void (*h)(int)))(int) {
  switch (sig) {
    case SIGINT: case SIGILL: case SIGFPE: case SIGSEGV: case SIGTERM: case SIGABRT:
      return signal(sig, h);
    default:
      return NULL;
  }
}

// System
// ======

long win_sysconf(int name) {
  (void)name;
  DWORD n = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
  if (n == 0) {
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    n = si.dwNumberOfProcessors;
  }
  return n > 0 ? (long)n : 1;
}

long win_readlink(const char* path, char* buf, size_t len) {
  (void)path;
  DWORD n = GetModuleFileNameA(NULL, buf, (DWORD)len);
  return n > 0 && n < len ? (long)n : 0;
}

#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

// A high-resolution waitable timer per thread (Windows 10 1803+); on older
// systems a plain one, with the timer period raised to 1 ms at start-up.
int win_nanosleep(const struct timespec* ts, struct timespec* rem) {
  static __thread HANDLE timer;
  (void)rem;
  if (timer == NULL) {
    timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
      TIMER_ALL_ACCESS);
    if (timer == NULL) {
      timer = CreateWaitableTimerW(NULL, TRUE, NULL);
    }
  }
  long long ns = (long long)ts->tv_sec * 1000000000ll + ts->tv_nsec;
  if (ns <= 0) {
    return 0;
  }
  LARGE_INTEGER due;
  due.QuadPart = -(ns + 99) / 100;
  if (timer == NULL || !SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE)) {
    Sleep((DWORD)((ns + 999999) / 1000000));
    return 0;
  }
  WaitForSingleObject(timer, INFINITE);
  return 0;
}

// Files
// =====

int win_open(const char* path, int flags, ...) {
  int mode = 0;
  if (flags & _O_CREAT) {
    va_list ap;
    va_start(ap, flags);
    va_arg(ap, int);
    va_end(ap);
    mode = _S_IREAD | _S_IWRITE;
  }
  return _open(path, flags | _O_BINARY | _O_NOINHERIT, mode);
}

long long win_pread(int fd, void* buf, size_t n, long long off) {
  HANDLE h = (HANDLE)_get_osfhandle(fd);
  if (h == INVALID_HANDLE_VALUE) {
    errno = EBADF;
    return -1;
  }
  OVERLAPPED ov = {0};
  ov.Offset     = (DWORD)off;
  ov.OffsetHigh = (DWORD)(off >> 32);
  DWORD got = 0;
  if (!ReadFile(h, buf, n > 0x7FFFFFFF ? 0x7FFFFFFF : (DWORD)n, &got, &ov)) {
    if (GetLastError() == ERROR_HANDLE_EOF) {
      return 0;
    }
    errno = EIO;
    return -1;
  }
  return got;
}

// The wake pipe
// =============

static int    win_wake_r = -1, win_wake_w = -1;
static HANDLE win_wake_ev;

int win_pipe(int fds[2]) {
  if (_pipe(fds, 1 << 16, _O_BINARY | _O_NOINHERIT) != 0) {
    return -1;
  }
  if (win_wake_r < 0) {
    win_wake_r  = fds[0];
    win_wake_w  = fds[1];
    win_wake_ev = CreateEventW(NULL, FALSE, FALSE, NULL);
  }
  return 0;
}

int win_fcntl(int fd, int cmd, ...) {
  (void)fd; (void)cmd;
  return 0;
}

static DWORD win_wake_avail(void) {
  DWORD n = 0;
  if (!PeekNamedPipe((HANDLE)_get_osfhandle(win_wake_r), NULL, 0, NULL, &n, NULL)) {
    return 0;
  }
  return n;
}

long long win_read(int fd, void* buf, size_t n) {
  if (n > 0x7FFFFFFF) {
    n = 0x7FFFFFFF;
  }
  if (fd == win_wake_r) {
    DWORD avail = win_wake_avail();
    if (avail == 0) {
      errno = EAGAIN;
      return -1;
    }
    n = n < avail ? n : avail;
  }
  return _read(fd, buf, (unsigned)n);
}

long long win_write(int fd, const void* buf, size_t n) {
  int r = _write(fd, buf, (unsigned)(n > 0x7FFFFFFF ? 0x7FFFFFFF : n));
  if (fd == win_wake_w && r > 0) {
    SetEvent(win_wake_ev);
  }
  return r;
}

struct win_timeval {
  long tv_sec;
  long tv_usec;
};

// The loop's select: the sets are the runtime's own bitsets (bit fd of
// byte fd / 8). Only the wake pipe's read end is watched.
int win_select(int n, void* rd, void* wr, void* ex, struct win_timeval* tv) {
  (void)ex;
  DWORD ms = tv == NULL ? INFINITE
    : (DWORD)(tv->tv_sec * 1000 + (tv->tv_usec + 999) / 1000);
  bool want = rd != NULL && win_wake_r >= 0 && win_wake_r < n
    && (((unsigned char*)rd)[win_wake_r / 8] >> (win_wake_r % 8) & 1);
  if (!(want && win_wake_avail() > 0)) {
    WaitForSingleObject(win_wake_ev, ms);
  }
  size_t len = ((size_t)n + 7) / 8;
  if (rd != NULL) {
    memset(rd, 0, len);
  }
  if (wr != NULL) {
    memset(wr, 0, len);
  }
  if (want && win_wake_avail() > 0) {
    ((unsigned char*)rd)[win_wake_r / 8] |= (unsigned char)(1 << (win_wake_r % 8));
    return 1;
  }
  return 0;
}

int win_inet_pton(int af, const char* src, void* dst) {
  unsigned a[4];
  char     end;
  if (af != 2 || sscanf(src, "%u.%u.%u.%u%c", &a[0], &a[1], &a[2], &a[3], &end) != 4
    || a[0] > 255 || a[1] > 255 || a[2] > 255 || a[3] > 255) {
    return 0;
  }
  unsigned char* d = dst;
  for (int i = 0; i < 4; i += 1) {
    d[i] = (unsigned char)a[i];
  }
  return 1;
}

// Start-up
// ========

// The release is a GUI program (no console window when double-clicked);
// started from a console, it prints there, and output that is already
// redirected stays redirected.
static void win_console(void) {
  HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
  if ((out == NULL || out == INVALID_HANDLE_VALUE) && AttachConsole(ATTACH_PARENT_PROCESS)) {
    freopen("CONOUT$", "w", stdout);
    freopen("CONOUT$", "w", stderr);
  }
}

static void __attribute__((constructor)) win_start(void) {
  AddVectoredExceptionHandler(1, win_fault);
  timeBeginPeriod(1);
  win_console();
}

// The window
// ==========

// The window lives on its own thread, which pumps its messages; the game
// fills a pixel buffer on its frame thread and blits it with GDI. Events
// are queued as five words (kind, a, b, c, d) in window coordinates:
// 0 key (code, down), 1 mouse (x, y, button, down), 2 move (x, y), 3 close.
struct WinWin {
  HWND             hwnd;
  HANDLE           thread;
  HANDLE           ready;
  const char*      title;
  unsigned         w, h;
  unsigned*        pix;
  CRITICAL_SECTION lock;  // the pixel buffer and the event queue
  unsigned*        evs;
  unsigned         n, cap;
  const char*      why;
  int              down;  // mouse buttons held (for capture)
};

static const wchar_t WIN_CLASS[] = L"EldergroveFaire";

static void win_push(WinWin* win, unsigned kind, unsigned a, unsigned b, unsigned c, unsigned d) {
  EnterCriticalSection(&win->lock);
  if (win->n == win->cap) {
    unsigned  cap = win->cap == 0 ? 64 : win->cap * 2;
    unsigned* evs = realloc(win->evs, (size_t)cap * 20);
    if (evs == NULL) {
      LeaveCriticalSection(&win->lock);
      return;
    }
    win->evs = evs;
    win->cap = cap;
  }
  unsigned* ev = win->evs + (size_t)win->n * 5;
  ev[0] = kind; ev[1] = a; ev[2] = b; ev[3] = c; ev[4] = d;
  win->n += 1;
  LeaveCriticalSection(&win->lock);
}

// The Mac's key codes, as the X11 port gives them: a key's character in
// lower case, the function keys' private-use characters (the arrows at
// 63232), a modifier's 65536 + its Mac key code.
static unsigned win_key(WPARAM vk, LPARAM lp) {
  int ext = (lp >> 24) & 1;
  switch (vk) {
    case VK_ESCAPE: return 27;
    case VK_RETURN: return 13;
    case VK_TAB:    return 9;
    case VK_BACK:   return 127;
    case VK_UP:     return 63232;
    case VK_DOWN:   return 63233;
    case VK_LEFT:   return 63234;
    case VK_RIGHT:  return 63235;
    case VK_INSERT: return 63271;
    case VK_DELETE: return 63272;
    case VK_HOME:   return 63273;
    case VK_END:    return 63275;
    case VK_PRIOR:  return 63276;
    case VK_NEXT:   return 63277;
    case VK_RWIN:   return 65590;
    case VK_LWIN:   return 65591;
    case VK_CAPITAL: return 65593;
    case VK_SHIFT:
      return MapVirtualKeyW((lp >> 16) & 0xFF, MAPVK_VSC_TO_VK_EX) == VK_RSHIFT ? 65596 : 65592;
    case VK_CONTROL: return ext ? 65598 : 65595;
    case VK_MENU:    return ext ? 65597 : 65594;
  }
  if (vk >= VK_F1 && vk <= VK_F12) {
    return 63236 + (unsigned)(vk - VK_F1);
  }
  // the character with only Shift and Caps Lock applied, as XLookupString
  BYTE ks[256] = {0};
  ks[VK_SHIFT]   = (BYTE)(GetKeyState(VK_SHIFT) & 0x80);
  ks[VK_CAPITAL] = (BYTE)(GetKeyState(VK_CAPITAL) & 1);
  wchar_t c[4];
  int n = ToUnicode((UINT)vk, (lp >> 16) & 0xFF, ks, c, 4, 4);  // 4: keep dead-key state
  if (n == 1 && c[0] >= 32) {
    return c[0] >= 'A' && c[0] <= 'Z' ? c[0] + 32 : c[0];
  }
  return 65536 + (unsigned)((lp >> 16) & 0xFF);
}

static void win_button(WinWin* win, HWND hwnd, LPARAM lp, unsigned b, int down) {
  win->down = down ? win->down | (1 << b) : win->down & ~(1 << b);
  if (down) {
    SetCapture(hwnd);
  } else if (win->down == 0) {
    ReleaseCapture();
  }
  win_push(win, 1, (unsigned)(short)LOWORD(lp), (unsigned)(short)HIWORD(lp), b, down);
}

static LRESULT CALLBACK win_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  WinWin* win = (WinWin*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  if (win == NULL) {
    return DefWindowProcW(hwnd, msg, wp, lp);
  }
  switch (msg) {
    case WM_CLOSE:
      win_push(win, 3, 0, 0, 0, 0);
      return 0;
    case WM_KEYDOWN: case WM_SYSKEYDOWN:
      if (msg == WM_SYSKEYDOWN && wp == VK_F4) {
        break;  // Alt+F4: close, as usual
      }
      win_push(win, 0, win_key(wp, lp), 1, 0, 0);
      return 0;
    case WM_KEYUP: case WM_SYSKEYUP:
      win_push(win, 0, win_key(wp, lp), 0, 0, 0);
      return 0;
    case WM_SYSCHAR: case WM_CHAR:
      return 0;
    case WM_SYSCOMMAND:
      if ((wp & 0xFFF0) == SC_KEYMENU) {
        return 0;  // Alt alone must not open the window menu
      }
      break;
    case WM_LBUTTONDOWN: win_button(win, hwnd, lp, 0, 1); return 0;
    case WM_LBUTTONUP:   win_button(win, hwnd, lp, 0, 0); return 0;
    case WM_RBUTTONDOWN: win_button(win, hwnd, lp, 1, 1); return 0;
    case WM_RBUTTONUP:   win_button(win, hwnd, lp, 1, 0); return 0;
    case WM_MBUTTONDOWN: win_button(win, hwnd, lp, 2, 1); return 0;
    case WM_MBUTTONUP:   win_button(win, hwnd, lp, 2, 0); return 0;
    case WM_MOUSEMOVE:
      win_push(win, 2, (unsigned)(short)LOWORD(lp), (unsigned)(short)HIWORD(lp), 0, 0);
      return 0;
    case WM_MOUSEWHEEL: {
      // X11 reports the wheel as buttons 4 (up) and 5 (down); the game
      // reads them as buttons 5 and 6
      POINT p = { (short)LOWORD(lp), (short)HIWORD(lp) };
      ScreenToClient(hwnd, &p);
      win_push(win, 1, (unsigned)p.x, (unsigned)p.y, (short)HIWORD(wp) > 0 ? 5 : 6, 1);
      return 0;
    }
    case WM_KILLFOCUS:
      win->down = 0;
      break;
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      EnterCriticalSection(&win->lock);
      BITMAPINFO bi = {0};
      bi.bmiHeader.biSize        = sizeof bi.bmiHeader;
      bi.bmiHeader.biWidth       = (LONG)win->w;
      bi.bmiHeader.biHeight      = -(LONG)win->h;
      bi.bmiHeader.biPlanes      = 1;
      bi.bmiHeader.biBitCount    = 32;
      bi.bmiHeader.biCompression = BI_RGB;
      SetDIBitsToDevice(dc, 0, 0, win->w, win->h, 0, 0, 0, win->h, win->pix, &bi,
        DIB_RGB_COLORS);
      LeaveCriticalSection(&win->lock);
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_USER:
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

static const DWORD WIN_STYLE = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;

// the outer size of a window whose client area is w x h
static void win_outer(HWND hwnd, unsigned w, unsigned h, int* ow, int* oh) {
  RECT r = { 0, 0, (LONG)w, (LONG)h };
  typedef BOOL (WINAPI *AdjustDpi)(LPRECT, DWORD, BOOL, DWORD, UINT);
  typedef UINT (WINAPI *DpiFor)(HWND);
  HMODULE u = GetModuleHandleW(L"user32.dll");
  AdjustDpi adjust = (AdjustDpi)(void*)GetProcAddress(u, "AdjustWindowRectExForDpi");
  DpiFor    dpi    = (DpiFor)(void*)GetProcAddress(u, "GetDpiForWindow");
  if (adjust != NULL && dpi != NULL && hwnd != NULL) {
    adjust(&r, WIN_STYLE, FALSE, 0, dpi(hwnd));
  } else {
    AdjustWindowRectEx(&r, WIN_STYLE, FALSE, 0);
  }
  *ow = r.right - r.left;
  *oh = r.bottom - r.top;
}

// Crisp pixels: the window is measured in device pixels, as on Linux,
// rather than stretched (and blurred) by display scaling.
static void win_dpi_aware(void) {
  typedef BOOL (WINAPI *SetCtx)(HANDLE);
  SetCtx set = (SetCtx)(void*)GetProcAddress(GetModuleHandleW(L"user32.dll"),
    "SetProcessDpiAwarenessContext");
  if (set == NULL || !set((HANDLE)-4)) {  // per-monitor v2
    SetProcessDPIAware();
  }
}

static DWORD WINAPI win_main(LPVOID arg) {
  WinWin*   win  = arg;
  HINSTANCE inst = GetModuleHandleW(NULL);
  WNDCLASSEXW wc = {0};
  wc.cbSize        = sizeof wc;
  wc.lpfnWndProc   = win_proc;
  wc.hInstance     = inst;
  wc.hCursor       = LoadCursorW(NULL, (LPCWSTR)IDC_ARROW);
  wc.hIcon         = LoadIconW(inst, MAKEINTRESOURCEW(1));
  wc.lpszClassName = WIN_CLASS;
  RegisterClassExW(&wc);
  wchar_t title[256];
  MultiByteToWideChar(CP_UTF8, 0, win->title, -1, title, 256);
  int ow, oh;
  win_outer(NULL, win->w, win->h, &ow, &oh);
  win->hwnd = CreateWindowExW(0, WIN_CLASS, title, WIN_STYLE, CW_USEDEFAULT, CW_USEDEFAULT,
    ow, oh, NULL, NULL, inst, NULL);
  if (win->hwnd == NULL) {
    win->why = "Window.open: Windows could not create the window";
    SetEvent(win->ready);
    return 0;
  }
  SetWindowLongPtrW(win->hwnd, GWLP_USERDATA, (LONG_PTR)win);
  // now that the window knows its monitor's scale, size it exactly, centred
  win_outer(win->hwnd, win->w, win->h, &ow, &oh);
  MONITORINFO mi = { sizeof mi };
  GetMonitorInfoW(MonitorFromWindow(win->hwnd, MONITOR_DEFAULTTOPRIMARY), &mi);
  RECT wa = mi.rcWork;
  int  x  = wa.left + ((wa.right - wa.left) - ow) / 2;
  int  y  = wa.top + ((wa.bottom - wa.top) - oh) / 2;
  SetWindowPos(win->hwnd, NULL, x > wa.left ? x : wa.left, y > wa.top ? y : wa.top, ow, oh,
    SWP_NOZORDER);
  ShowWindow(win->hwnd, SW_SHOWNORMAL);
  SetForegroundWindow(win->hwnd);
  SetEvent(win->ready);
  MSG m;
  while (GetMessageW(&m, NULL, 0, 0) > 0) {
    TranslateMessage(&m);
    DispatchMessageW(&m);
  }
  return 0;
}

WinWin* winw_open(const char* title, unsigned w, unsigned h, const char** why) {
  win_dpi_aware();
  WinWin* win = calloc(1, sizeof *win);
  if (win == NULL) {
    *why = "Window.open: out of memory";
    return NULL;
  }
  win->title = title;
  win->w     = w;
  win->h     = h;
  win->pix   = calloc((size_t)w * h, 4);
  win->ready = CreateEventW(NULL, TRUE, FALSE, NULL);
  InitializeCriticalSection(&win->lock);
  win->thread = CreateThread(NULL, 0, win_main, win, 0, NULL);
  if (win->pix == NULL || win->thread == NULL) {
    *why = "Window.open: out of memory";
    return NULL;
  }
  WaitForSingleObject(win->ready, INFINITE);
  win->title = NULL;
  if (win->hwnd == NULL) {
    *why = win->why;
    return NULL;
  }
  return win;
}

void winw_close(WinWin* win) {
  PostMessageW(win->hwnd, WM_USER, 0, 0);
  WaitForSingleObject(win->thread, 5000);
  CloseHandle(win->thread);
  CloseHandle(win->ready);
  DeleteCriticalSection(&win->lock);
  free(win->pix);
  free(win->evs);
  free(win);
}

unsigned* winw_pixels(WinWin* win, unsigned* w, unsigned* h) {
  *w = win->w;
  *h = win->h;
  return win->pix;
}

void winw_lock(WinWin* win, int on) {
  if (on) {
    EnterCriticalSection(&win->lock);
  } else {
    LeaveCriticalSection(&win->lock);
  }
}

// a new client size: a new (black) buffer, and the window resized to fit
void winw_resize(WinWin* win, unsigned w, unsigned h) {
  if (w != win->w || h != win->h) {
    unsigned* pix = calloc((size_t)w * h, 4);
    if (pix == NULL) {
      return;
    }
    EnterCriticalSection(&win->lock);
    free(win->pix);
    win->pix = pix;
    win->w   = w;
    win->h   = h;
    LeaveCriticalSection(&win->lock);
    int ow, oh;
    win_outer(win->hwnd, w, h, &ow, &oh);
    SetWindowPos(win->hwnd, NULL, 0, 0, ow, oh, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
  } else {
    memset(win->pix, 0, (size_t)w * h * 4);
  }
}

unsigned winw_pump(WinWin* win, unsigned* out, unsigned cap) {
  EnterCriticalSection(&win->lock);
  unsigned n = win->n < cap ? win->n : cap;
  memcpy(out, win->evs, (size_t)n * 20);
  memmove(win->evs, win->evs + (size_t)n * 5, (size_t)(win->n - n) * 20);
  win->n -= n;
  LeaveCriticalSection(&win->lock);
  return n;
}

void winw_present(WinWin* win) {
  HDC dc = GetDC(win->hwnd);
  if (dc == NULL) {
    return;
  }
  BITMAPINFO bi = {0};
  bi.bmiHeader.biSize        = sizeof bi.bmiHeader;
  bi.bmiHeader.biWidth       = (LONG)win->w;
  bi.bmiHeader.biHeight      = -(LONG)win->h;
  bi.bmiHeader.biPlanes      = 1;
  bi.bmiHeader.biBitCount    = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  SetDIBitsToDevice(dc, 0, 0, win->w, win->h, 0, 0, 0, win->h, win->pix, &bi, DIB_RGB_COLORS);
  ReleaseDC(win->hwnd, dc);
}

// Sound
// =====

// waveOut, 16-bit stereo: a ring of blocks the device plays in turn. A
// play waits (on the device's event) until the oldest block is done, so
// the caller's pump runs at the sample clock, as pacat's pipe paces it on
// Linux. With no device (or PARK_MUTE set) wins_open returns NULL and the
// pump falls back to the clock.
#define WINS_BLOCKS 8
#define WINS_FRAMES 512

struct WinSnd {
  HWAVEOUT       dev;
  volatile LONG  shut;
  HANDLE   done;
  WAVEHDR  hdr[WINS_BLOCKS];
  int16_t  pcm[WINS_BLOCKS][WINS_FRAMES * 2];
  unsigned next, fill;
};

// At exit the devices are stopped and closed: a process that ends with
// waveOut blocks still queued does not end.
static WinSnd*       wins_all[8];
static volatile LONG wins_n;

static void wins_stop(void) {
  for (LONG i = 0; i < wins_n && i < 8; i += 1) {
    WinSnd* s = wins_all[i];
    InterlockedExchange(&s->shut, 1);
    waveOutReset(s->dev);
    waveOutClose(s->dev);
  }
}

WinSnd* wins_open(unsigned rate) {
  if (getenv("PARK_MUTE") != NULL) {
    return NULL;
  }
  WinSnd* s = calloc(1, sizeof *s);
  if (s == NULL) {
    return NULL;
  }
  s->done = CreateEventW(NULL, FALSE, FALSE, NULL);
  WAVEFORMATEX f = {0};
  f.wFormatTag      = WAVE_FORMAT_PCM;
  f.nChannels       = 2;
  f.nSamplesPerSec  = rate;
  f.wBitsPerSample  = 16;
  f.nBlockAlign     = 4;
  f.nAvgBytesPerSec = rate * 4;
  if (waveOutOpen(&s->dev, WAVE_MAPPER, &f, (DWORD_PTR)s->done, 0, CALLBACK_EVENT)
    != MMSYSERR_NOERROR) {
    CloseHandle(s->done);
    free(s);
    return NULL;
  }
  for (int i = 0; i < WINS_BLOCKS; i += 1) {
    s->hdr[i].lpData         = (LPSTR)s->pcm[i];
    s->hdr[i].dwBufferLength = sizeof s->pcm[i];
    s->hdr[i].dwFlags        = WHDR_DONE;
    waveOutPrepareHeader(s->dev, &s->hdr[i], sizeof s->hdr[i]);
    s->hdr[i].dwFlags |= WHDR_DONE;
  }
  LONG i = InterlockedIncrement(&wins_n) - 1;
  if (i < 8) {
    wins_all[i] = s;
  }
  if (i == 0) {
    atexit(wins_stop);
  }
  return s;
}

// n frames (at most WINS_FRAMES) into the next free block; 0 on success
int wins_play(WinSnd* s, const int16_t* frames, unsigned n) {
  if (s->shut) {
    return -1;
  }
  WAVEHDR*        h     = &s->hdr[s->next];
  volatile DWORD* flags = &h->dwFlags;  // the device sets WHDR_DONE
  while (!(*flags & WHDR_DONE)) {
    if (WaitForSingleObject(s->done, 1000) == WAIT_TIMEOUT && !(*flags & WHDR_DONE)) {
      return -1;  // the device stopped playing
    }
  }
  n = n < WINS_FRAMES ? n : WINS_FRAMES;
  memcpy(s->pcm[s->next], frames, (size_t)n * 4);
  h->dwBufferLength = n * 4;
  h->dwFlags &= ~WHDR_DONE;
  if (waveOutWrite(s->dev, h, sizeof *h) != MMSYSERR_NOERROR) {
    h->dwFlags |= WHDR_DONE;
    return -1;
  }
  s->next = (s->next + 1) % WINS_BLOCKS;
  return 0;
}
