// Pointer
// =======

// The Windows host's pointer, read through WSL interop. `host_open` starts
// native/pointer-host.ps1 with its output on a pipe and `host_read` drains
// the pipe; what the lines mean is native/pointer.bend's. There is one
// pointer per process, so the pipe is a static and not a handle: a user
// handle type is not something an effect can declare.
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

static int    pointer_fd = -1;
static pid_t  pointer_pid;
static char   pointer_buf[65536];
static size_t pointer_len;

#ifdef CID(host_open)

#define POINTER_SCRIPT "native/pointer-host.ps1"

// Only under WSL, where powershell.exe runs through interop, and only when
// the script is where the client's own relative paths expect it.
static u32 pointer_open(char* title) {
  int fds[2];
  if (pointer_fd >= 0) {
    return 1;
  }
  if (getenv("WSL_DISTRO_NAME") == NULL || access(POINTER_SCRIPT, R_OK) != 0
    || pipe(fds) != 0) {
    return 0;
  }
  pid_t pid = fork();
  if (pid < 0) {
    close(fds[0]);
    close(fds[1]);
    return 0;
  }
  if (pid == 0) {
    int null = open("/dev/null", O_RDONLY);
    dup2(null, 0);
    dup2(fds[1], 1);
    close(fds[0]);
    close(fds[1]);
    execlp("powershell.exe", "powershell.exe", "-NoProfile", "-NonInteractive",
      "-ExecutionPolicy", "Bypass", "-File", POINTER_SCRIPT, "-Title", title,
      (char*)NULL);
    _exit(127);
  }
  close(fds[1]);
  fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK);
  fcntl(fds[0], F_SETFD, FD_CLOEXEC);
  pointer_fd  = fds[0];
  pointer_pid = pid;
  return 1;
}

Term pointer_open_run(Env e, Term* f, IoWork* w) {
  uint64_t n     = 0;
  char*    title = io_cstr(e, f[0], &n);
  u32      ok    = pointer_open(title);
  free(title);
  return (Term)ok;
}

static void __attribute__((constructor)) pointer_open_use(void) {
  io_eff(CID(host_open), pointer_open_run, 0);
}

#endif

#ifdef CID(host_read)

// The whole lines that have arrived; a line still being written waits for
// the next read. A full buffer with no newline in it is not the host's
// protocol and is dropped.
Term pointer_read_run(Env e, Term* f, IoWork* w) {
  while (pointer_fd >= 0 && pointer_len < sizeof pointer_buf) {
    ssize_t n = read(pointer_fd, pointer_buf + pointer_len,
      sizeof pointer_buf - pointer_len);
    if (n > 0) {
      pointer_len += (size_t)n;
    } else if (n == 0) {
      close(pointer_fd);
      waitpid(pointer_pid, NULL, WNOHANG);
      pointer_fd = -1;
    } else {
      break;
    }
  }
  size_t k = pointer_len;
  while (k > 0 && pointer_buf[k - 1] != '\n') {
    k -= 1;
  }
  Term text = io_str(e, pointer_buf, k);
  if (k == 0 && pointer_len == sizeof pointer_buf) {
    k = pointer_len;
  }
  memmove(pointer_buf, pointer_buf + k, pointer_len - k);
  pointer_len -= k;
  return text;
}

static void __attribute__((constructor)) pointer_read_use(void) {
  io_eff(CID(host_read), pointer_read_run, 0);
}

#endif
