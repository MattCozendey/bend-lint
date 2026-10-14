// The POSIX surface that Bend's generated C expects, on Windows.
//
// park.c is force-included with this header (gcc -include bend_win.h), so
// the system headers it would pull in later are already here, and the
// calls Windows lacks or does differently are renamed to win_* functions
// in winplat.c. windows.h stays out of park.c: its macros (TRUE, ERROR,
// near, small, ...) would collide with generated names, so everything that
// needs Win32 lives in winplat.c behind the plain C declarations below.
#ifndef BEND_WIN_H
#define BEND_WIN_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <io.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/stat.h>

// Memory: address-space reservations; pages are committed on first touch
// by a vectored exception handler (see winplat.c), as MAP_NORESERVE does.
#define PROT_NONE     0
#define PROT_READ     1
#define PROT_WRITE    2
#define MAP_PRIVATE   2
#define MAP_ANON      0x20
#define MAP_ANONYMOUS MAP_ANON
#define MAP_NORESERVE 0x4000
#define MAP_FAILED    ((void*)-1)
void* win_mmap(void* at, size_t len, int prot, int flags, int fd, long long off);
int   win_munmap(void* at, size_t len);
int   win_mprotect(void* at, size_t len, int prot);
#define mmap     win_mmap
#define munmap   win_munmap
#define mprotect win_mprotect

// Signals: the runtime traps SIGSEGV on an alternate stack to report a
// machine stack overflow; here the fault handler calls the same handler.
#ifndef SIGBUS
#define SIGBUS 10
#endif
#ifndef SIGPIPE
#define SIGPIPE 13
#endif
#define SA_ONSTACK 0x08000000
#ifndef SIGSTKSZ
#define SIGSTKSZ 16384
#endif
typedef struct {
  void*  ss_sp;
  int    ss_flags;
  size_t ss_size;
} stack_t;
struct sigaction {
  void (*sa_handler)(int);
  int sa_flags;
};
int win_sigaltstack(const stack_t* ss, stack_t* old);
int win_sigaction(int sig, const struct sigaction* sa, struct sigaction* old);
void (*win_signal(int sig, void (*h)(int)))(int);
#define sigaltstack win_sigaltstack
#define sigaction(s, a, o) win_sigaction(s, a, o)
#define signal     win_signal

// Processors, the executable's path, a precise sleep.
#define _SC_NPROCESSORS_ONLN 84
long win_sysconf(int name);
long win_readlink(const char* path, char* buf, size_t len);
int  win_nanosleep(const struct timespec* ts, struct timespec* rem);
#define sysconf   win_sysconf
#define readlink  win_readlink
#define nanosleep win_nanosleep

// Files: binary mode always; pread by offset.
int       win_open(const char* path, int flags, ...);
long long win_pread(int fd, void* buf, size_t n, long long off);
#define open(...) win_open(__VA_ARGS__)
#define pread     win_pread

// The event loop's wake pipe: a CRT pipe whose read end reports EAGAIN
// when empty, and a select() that waits on the pipe's signal and the
// timeout. Sockets are not supported (the game opens none).
#ifndef O_NONBLOCK
#define O_NONBLOCK 04000
#endif
#define F_SETFL 4
#define POLLIN  0x001
#define POLLOUT 0x004
struct timeval;
int       win_pipe(int fds[2]);
int       win_fcntl(int fd, int cmd, ...);
long long win_read(int fd, void* buf, size_t n);
long long win_write(int fd, const void* buf, size_t n);
int       win_select(int n, void* rd, void* wr, void* ex, struct timeval* tv);
#define pipe   win_pipe
#define fcntl  win_fcntl
#define read   win_read
#define write  win_write
#define select win_select
#ifndef _TIMEVAL_DEFINED
#define _TIMEVAL_DEFINED
struct timeval {
  long tv_sec;
  long tv_usec;
};
#endif
typedef struct {
  unsigned char bits[1];
} fd_set;

// Addresses, for the socket effects' parser (never reached by the game).
#define AF_INET 2
struct in_addr {
  uint32_t s_addr;
};
struct sockaddr_in {
  short          sin_family;
  uint16_t       sin_port;
  struct in_addr sin_addr;
  char           sin_zero[8];
};
static inline uint16_t htons(uint16_t v) {
  return (uint16_t)((v << 8) | (v >> 8));
}
int win_inet_pton(int af, const char* src, void* dst);
#define inet_pton win_inet_pton

// The native window (win_frame.c) and sound device (snd.c).
typedef struct WinWin WinWin;
WinWin*   winw_open(const char* title, unsigned w, unsigned h, const char** why);
void      winw_close(WinWin* win);
unsigned* winw_pixels(WinWin* win, unsigned* w, unsigned* h);
void      winw_resize(WinWin* win, unsigned w, unsigned h);
unsigned  winw_pump(WinWin* win, unsigned* out, unsigned cap);
void      winw_present(WinWin* win);
void      winw_lock(WinWin* win, int on);

typedef struct WinSnd WinSnd;
WinSnd* wins_open(unsigned rate);
int     wins_play(WinSnd* s, const int16_t* frames, unsigned n);

#endif
