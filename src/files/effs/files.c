// Files
// =====
// The C twins of files.js. A path crosses as UTF-8: Windows reads it so, as
// every Bend binary has a UTF-8 manifest.

#include <sys/stat.h>
#ifndef _WIN32
#include <dirent.h>
#endif

// The names a folder listing collects, each ended by a NUL.
typedef struct {
  char* text;
  u64   len;
  u64   cap;
} FilesNames;

#ifdef _WIN32
// The errno of a failed Win32 call.
static int files_errno(DWORD code) {
  return code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND ? ENOENT
    : code == ERROR_ACCESS_DENIED ? EACCES
    : code == ERROR_DIRECTORY ? ENOTDIR
    : EIO;
}
#endif

static void files_put(FilesNames* names, const char* name) {
  u64 k = strlen(name);
  if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
    return;
  }
  while (names->len + k + 1 > names->cap) {
    names->cap *= 2;
    names->text = realloc(names->text, names->cap);
  }
  memcpy(names->text + names->len, name, k + 1);
  names->len += k + 1;
}

// Puts the names in the folder at `path` (`n` bytes) into `names`. Gives 0,
// or the errno.
static int files_list_into(FilesNames* names, const char* path, u64 n) {
#ifdef _WIN32
  char* all = malloc(n + 3);
  memcpy(all, path, n);
  memcpy(all + n, "/*", 3);
  WIN32_FIND_DATAA found;
  HANDLE           h = FindFirstFileA(all, &found);
  free(all);
  if (h == INVALID_HANDLE_VALUE) {
    return files_errno(GetLastError());
  }
  do {
    files_put(names, found.cFileName);
  } while (FindNextFileA(h, &found));
  FindClose(h);
  return 0;
#else
  DIR* d = opendir(path);
  if (d == NULL) {
    return errno;
  }
  for (struct dirent* de = readdir(d); de != NULL; de = readdir(d)) {
    files_put(names, de->d_name);
  }
  closedir(d);
  return 0;
#endif
}

// The names in a folder, but "." and "..", each ended by a NUL, in the
// order the OS gives them.
Term files_list_run(Env e, Term* f, IoWork* w) {
  u64        n     = 0;
  char*      path  = io_cstr(e, f[0], &n);
  FilesNames names = { malloc(256), 0, 256 };
  int        code  = io_nul(path, n) ? EINVAL : files_list_into(&names, path, n);
  free(path);
  Term r = code != 0 ? io_fail(e, code, NULL) : io_done(e, io_str(e, names.text, names.len));
  free(names.text);
  return r;
}

// What is at a path, links followed: 0 nothing, 1 a file, 2 a folder, 3
// something else.
Term files_kind_run(Env e, Term* f, IoWork* w) {
  u64         n    = 0;
  char*       path = io_cstr(e, f[0], &n);
  struct stat st;
  u32         kind = io_nul(path, n) || stat(path, &st) != 0 ? 0
    : (st.st_mode & S_IFMT) == S_IFREG ? 1
    : (st.st_mode & S_IFMT) == S_IFDIR ? 2
    : 3;
  free(path);
  return (Term)kind;
}

// A path's real path: absolute, links resolved, "/" between its parts.
Term files_real_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  if (io_nul(path, n)) {
    free(path);
    return io_fail(e, EINVAL, NULL);
  }
#ifdef _WIN32
  HANDLE h = CreateFileA(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  free(path);
  if (h == INVALID_HANDLE_VALUE) {
    return io_fail(e, files_errno(GetLastError()), NULL);
  }
  char  buf[32768];
  DWORD k   = GetFinalPathNameByHandleA(h, buf, sizeof buf, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  DWORD why = GetLastError();
  CloseHandle(h);
  if (k == 0 || k >= sizeof buf) {
    return io_fail(e, k == 0 ? files_errno(why) : ENAMETOOLONG, NULL);
  }
  // \\?\C:\a is C:\a, and \\?\UNC\host\a is \\host\a.
  char* real = buf;
  if (strncmp(buf, "\\\\?\\UNC\\", 8) == 0) {
    real    = buf + 6;
    real[0] = '\\';
  } else if (strncmp(buf, "\\\\?\\", 4) == 0) {
    real = buf + 4;
  }
  for (char* c = real; *c != 0; c += 1) {
    *c = *c == '\\' ? '/' : *c;
  }
  return io_done(e, io_str(e, real, strlen(real)));
#else
  char* real = realpath(path, NULL);
  int   code = errno;
  free(path);
  if (real == NULL) {
    return io_fail(e, code, NULL);
  }
  Term r = io_done(e, io_str(e, real, strlen(real)));
  free(real);
  return r;
#endif
}

static void __attribute__((constructor)) files_use(void) {
  io_eff(CID(list.raw), files_list_run);
  io_eff(CID(kind), files_kind_run);
  io_eff(CID(real), files_real_run);
}
