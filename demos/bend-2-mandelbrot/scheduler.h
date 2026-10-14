#ifndef ATLAS_SCHEDULER_H
#define ATLAS_SCHEDULER_H
#include <stdbool.h>
#include <stdint.h>

typedef struct {
  bool dirty;
  unsigned active,root,columns,rows,cursor,remaining,completed;
  uint64_t revision;
} RenderScheduler;
typedef struct { unsigned x,y,root; uint64_t revision; } RenderBatch;

static void render_changed(RenderScheduler* s) { s->dirty=true; }
static bool render_pending(const RenderScheduler* s) { return s->dirty||s->remaining; }
static void render_prepare(RenderScheduler* s,unsigned width,unsigned height,unsigned root) {
  s->root=root;s->columns=(width+root-1)/root;s->rows=(height+root-1)/root;
  s->remaining=s->columns*s->rows;s->completed=0;s->dirty=false;s->revision++;
  s->cursor%=s->remaining;
}
static bool render_take(RenderScheduler* s,unsigned limit,RenderBatch* batch) {
  if(s->dirty||s->active>=limit||!s->remaining)return false;
  unsigned index=s->cursor;
  s->cursor=(s->cursor+1)%(s->columns*s->rows);
  s->remaining--;s->active++;
  *batch=(RenderBatch){(index%s->columns)*s->root,(index/s->columns)*s->root,s->root,s->revision};
  return true;
}
static void render_finished(RenderScheduler* s,uint64_t revision) {
  s->active--;
  if(revision==s->revision)s->completed++;
}
static bool render_complete(const RenderScheduler* s) {
  return !s->dirty&&!s->remaining&&s->completed==s->columns*s->rows;
}
#endif
