// get_real_path
// =============
// Bend unescapes this source once when it builds a binary, so it holds no
// backslash: BS below is the backslash.

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define BENDLINT_BS 0x5C

// The long-path prefixes: BS BS ? BS, and BS BS ? BS UNC BS.
static const wchar_t BENDLINT_LONG[8] = {0x5C, 0x5C, 0x3F, 0x5C, 0x55, 0x4E, 0x43, 0x5C};

static bool bendlint_get_real_path_starts(const wchar_t* s, int n) {
  for (int i = 0; i < n; i += 1) {
    if (s[i] != BENDLINT_LONG[i]) {
      return false;
    }
  }
  return true;
}

static u32 bendlint_get_real_path_errno(DWORD err) {
  switch (err) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_NAME:
      return ENOENT;
    case ERROR_ACCESS_DENIED:
      return EACCES;
    default:
      return EIO;
  }
}

static char* bendlint_get_real_path_os(const char* path, u32* code) {
  int      wn   = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
  wchar_t* wide = io_mem(malloc((size_t)wn * sizeof(wchar_t)));
  MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, wn);
  HANDLE h = CreateFileW(wide, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  free(wide);
  if (h == INVALID_HANDLE_VALUE) {
    *code = bendlint_get_real_path_errno(GetLastError());
    return NULL;
  }
  DWORD    fn   = GetFinalPathNameByHandleW(h, NULL, 0, FILE_NAME_NORMALIZED);
  wchar_t* full = io_mem(malloc((size_t)fn * sizeof(wchar_t)));
  DWORD    got  = GetFinalPathNameByHandleW(h, full, fn, FILE_NAME_NORMALIZED);
  CloseHandle(h);
  if (got == 0 || got >= fn) {
    free(full);
    *code = EIO;
    return NULL;
  }
  // The prefix is dropped; a UNC path keeps its two leading BS.
  wchar_t* at = full;
  if (bendlint_get_real_path_starts(at, 8)) {
    at += 6;
    at[0] = BENDLINT_BS;
  } else if (bendlint_get_real_path_starts(at, 4)) {
    at += 4;
  }
  int   un  = WideCharToMultiByte(CP_UTF8, 0, at, -1, NULL, 0, NULL, NULL);
  char* out = io_mem(malloc((size_t)un));
  WideCharToMultiByte(CP_UTF8, 0, at, -1, out, un, NULL, NULL);
  free(full);
  return out;
}
#else
static char* bendlint_get_real_path_os(const char* path, u32* code) {
  char* out = realpath(path, NULL);
  if (out == NULL) {
    *code = (u32)errno;
  }
  return out;
}
#endif

Term bendlint_get_real_path_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  if (io_nul(path, n)) {
    free(path);
    return io_fail(e, EINVAL, NULL);
  }
  u32   code = 0;
  char* got  = bendlint_get_real_path_os(path, &code);
  free(path);
  if (got == NULL) {
    return io_fail(e, code, NULL);
  }
  Term r = io_done(e, io_str(e, got, strlen(got)));
  free(got);
  return r;
}

static void __attribute__((constructor)) bendlint_get_real_path_use(void) {
  io_eff(CID(get_real_path), bendlint_get_real_path_run);
}
