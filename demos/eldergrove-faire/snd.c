// Eldergrove's sound output: the game synthesizes its own samples (see
// sound.bend) and this effect plays them. Adapted from Bend's audio effect
// (bend2/effs/audio.c, Copyright HigherOrderCO, Apache License 2.0): the same
// ring of float32 stereo frames, but the pump feeds PulseAudio through
// `pacat` (WSLg provides a PulseAudio server; there is no ALSA device), or
// on Windows the waveOut device (win/winplat.c), and when there is no
// output the ring simply drains at the sample clock.
#if defined(__linux__) || defined(_WIN32)
#ifndef SND_RING
#define SND_RING 4096u
#include <signal.h>

#if defined(_WIN32)
typedef WinSnd SndOut;
#else
typedef FILE SndOut;
#endif

typedef struct {
  _Atomic(u64) read, written;
  float        pcm[SND_RING * 2];
  u32          rate;
  SndOut*      out;
  pthread_t    pump;
} SndRing;

static u64 snd_ring_write(SndRing* p, const float* pcm, u32 n) {
  u64 w = atomic_load_explicit(&p->written, memory_order_relaxed);
  u64 r = atomic_load_explicit(&p->read, memory_order_acquire);
  if (w - r + n <= SND_RING) {
    u32 at    = (u32)(w % SND_RING);
    u32 first = n < SND_RING - at ? n : SND_RING - at;
    memcpy(p->pcm + at * 2, pcm, first * 8);
    memcpy(p->pcm, pcm + first * 2, (n - first) * 8);
    atomic_store_explicit(&p->written, w + n, memory_order_release);
    w += n;
  }
  return w - r;
}

static void snd_ring_pull(SndRing* p, float* out, u32 frames) {
  u64 r     = atomic_load_explicit(&p->read, memory_order_relaxed);
  u64 w     = atomic_load_explicit(&p->written, memory_order_acquire);
  u32 n     = (u32)(w - r < frames ? w - r : frames);
  u32 at    = (u32)(r % SND_RING);
  u32 first = n < SND_RING - at ? n : SND_RING - at;
  memcpy(out, p->pcm + at * 2, first * 8);
  memcpy(out + first * 2, p->pcm, (n - first) * 8);
  memset(out + n * 2, 0, (frames - n) * 8);
  atomic_store_explicit(&p->read, r + n, memory_order_release);
}

// 256 frames at a time: to pacat as 16-bit stereo (its pipe blocks while
// the server's buffer is full, which paces the ring) or to waveOut (which
// blocks until a block is free), or, with no output, by the clock
static void* snd_pump(void* ctx) {
  SndRing* p = ctx;
  float    buf[256 * 2];
  int16_t  s16[256 * 2];
  for (;;) {
    snd_ring_pull(p, buf, 256);
    if (p->out != NULL) {
      for (u32 i = 0; i < 512; i += 1) {
        float v = buf[i] < -1.0f ? -1.0f : buf[i] > 1.0f ? 1.0f : buf[i];
        s16[i] = (int16_t)(v * 32767.0f);
      }
#if defined(_WIN32)
      if (wins_play(p->out, s16, 256) != 0) {
        p->out = NULL;
      }
#else
      if (fwrite(s16, sizeof s16, 1, p->out) != 1) {
        pclose(p->out);
        p->out = NULL;
      } else {
        fflush(p->out);
      }
#endif
    } else {
      struct timespec ts = { 0, (long)(256.0 * 1e9 / p->rate) };
      nanosleep(&ts, NULL);
    }
  }
  return NULL;
}

#if defined(_WIN32)
static SndOut* snd_device(u32 rate) {
  return wins_open(rate);
}
#else
static SndOut* snd_device(u32 rate) {
  if (getenv("PARK_MUTE") != NULL) {
    return NULL;
  }
  char cmd[512];
  const char* tries[2] = { "pacat", "/home/linuxbrew/.linuxbrew/bin/pacat" };
  for (int i = 0; i < 2; i += 1) {
    snprintf(cmd, sizeof cmd, "command -v %s >/dev/null 2>&1 && exec %s --raw --format=s16le "
      "--rate=%u --channels=2 --latency-msec=80 --client-name=eldergrove 2>/dev/null",
      tries[i], tries[i], rate);
    char check[256];
    snprintf(check, sizeof check, "command -v %s >/dev/null 2>&1", tries[i]);
    if (system(check) == 0) {
      FILE* f = popen(cmd, "w");
      if (f != NULL) {
        return f;
      }
    }
  }
  return NULL;
}
#endif
#endif

#ifdef CID_SND_OPEN
Term snd_open_run(Env e, Term* f, IoWork* w) {
  u32      rate = (u32)f[0];
  SndRing* p    = io_mem(calloc(1, sizeof *p));
  p->rate = rate < 8000 || rate > 96000 ? 22050 : rate;
  signal(SIGPIPE, SIG_IGN);
  p->out = snd_device(p->rate);
  pthread_create(&p->pump, NULL, snd_pump, p);
  return io_hand((intptr_t)p);
}

static void __attribute__((constructor)) snd_open_use(void) {
  io_eff(CID_SND_OPEN, snd_open_run, 0);
}
#endif

#ifdef CID_SND_WRITE
// The samples (interleaved L R ...) into the ring; the frames queued
// after the write (past the ring's room they are dropped).
Term snd_write_run(Env e, Term* f, IoWork* w) {
  SndRing* p   = (SndRing*)(uintptr_t)io_hand_v(f[0]);
  float    pcm[SND_RING * 2];
  u32      n   = 0;
  Term     s   = f[1];
  while (term_aux(s) == CID_CON) {
    Term fb[2];
    spare_free(e, cls_fit(2), ctr_take(e, s, 2, fb));
    if (n < SND_RING * 2) {
      pcm[n] = f32_unbox(fb[0]);
    }
    n += 1;
    s  = fb[1];
  }
  u64 q = n > SND_RING * 2 ? snd_ring_write(p, pcm, 0)
    : snd_ring_write(p, pcm, n / 2);
  return io_tup(e, f[0], q);
}

static void __attribute__((constructor)) snd_write_use(void) {
  io_eff(CID_SND_WRITE, snd_write_run, 0);
}
#endif
#endif
