#include "scheduler.h"
#include "interaction.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
  RenderScheduler s={.dirty=true};RenderBatch old[3],b;
  render_prepare(&s,2200,1560,256);
  for(unsigned i=0;i<3;i++)assert(render_take(&s,3,&old[i]));
  assert(!render_take(&s,3,&b));
  uint64_t first=s.revision;
  for(unsigned i=0;i<100000;i++) {
    render_changed(&s);assert(!render_take(&s,3,&b));assert(s.revision==first);
  }
  render_prepare(&s,777,531,256);
  assert(s.active==3&&!render_take(&s,3,&b));
  render_finished(&s,old[2].revision);
  assert(s.completed==0&&render_take(&s,3,&b));
  bool seen[12]={0};unsigned completed=0;
  unsigned index=(b.y/256)*4+b.x/256;seen[index]=true;completed++;
  render_finished(&s,b.revision);
  render_finished(&s,old[0].revision);render_finished(&s,old[1].revision);
  assert(s.completed==1&&s.active==0);
  RenderBatch final[3];unsigned active=0;
  while(render_take(&s,3,&b)) {
    index=(b.y/256)*4+b.x/256;assert(index<12&&!seen[index]);seen[index]=true;completed++;
    final[active++]=b;
    if(active==3) {assert(!render_complete(&s));for(unsigned i=active;i;i--)render_finished(&s,final[i-1].revision);active=0;}
  }
  assert(!render_complete(&s));
  while(active)render_finished(&s,final[--active].revision);
  assert(completed==12&&render_complete(&s)&&!render_pending(&s)&&s.active==0);
  render_changed(&s);render_prepare(&s,777,531,256);
  assert(render_take(&s,3,&b));assert(!render_take(&s,1,&b));
  render_finished(&s,b.revision);assert(render_take(&s,1,&b));
  ZoomInteraction input={0};double amount=0;
  zoom_press(&input,0,false);
  for(unsigned i=0;i<120;i++)amount+=zoom_step(&input,1./120);
  assert(amount<-.9&&amount>-1.3);
  zoom_release(&input,0);assert(zoom_step(&input,.1)==0);
  zoom_press(&input,1,false);assert(zoom_step(&input,.1)>0);
  zoom_release(&input,0);assert(input.pressed);
  zoom_release(&input,1);assert(!input.pressed);
  zoom_press(&input,0,true);assert(input.panning&&zoom_step(&input,.1)==0);
  zoom_press(&input,2,false);assert(input.panning&&zoom_step(&input,.1)==0);
  puts("Passed: bounded pool, 100000 latest-view replacements, out-of-order completion, stale exclusion, coverage, dynamic limit, hold/release/pan controls.");
}
