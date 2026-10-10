// get_spliced_text
// ================
// The text with its code points from beg to end replaced by put.

#include <stdlib.h>
#include <string.h>

// The byte offset of code point n in the UTF-8 text s of len bytes.
static u64 bendlint_point_at(const char* s, u64 len, u32 n) {
  u64 at = 0;
  for (u32 k = 0; k < n && at < len; k += 1) {
    at += 1;
    while (at < len && ((unsigned char)s[at] & 0xC0) == 0x80) {
      at += 1;
    }
  }
  return at;
}

Term bendlint_get_spliced_text_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  u64   m    = 0;
  char* text = io_cstr(e, f[0], &n);
  char* put  = io_cstr(e, f[3], &m);
  u64   beg  = bendlint_point_at(text, n, (u32)f[1]);
  u64   end  = bendlint_point_at(text, n, (u32)f[2]);
  end = end < beg ? beg : end;
  char* out = io_mem(malloc(beg + m + (n - end) + 1));
  memcpy(out, text, beg);
  memcpy(out + beg, put, m);
  memcpy(out + beg + m, text + end, n - end);
  Term r = io_str(e, out, beg + m + (n - end));
  free(out);
  free(text);
  free(put);
  return r;
}

static void __attribute__((constructor)) bendlint_get_spliced_text_use(void) {
  io_eff(CID(get_spliced_text), bendlint_get_spliced_text_run);
}
