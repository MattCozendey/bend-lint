#ifndef ATLAS_INTERACTION_H
#define ATLAS_INTERACTION_H
#include <stdbool.h>
#include <math.h>
typedef struct { bool pressed,panning; unsigned button; int direction; double speed; } ZoomInteraction;
static void zoom_press(ZoomInteraction* s,unsigned button,bool shift) {
  *s=(ZoomInteraction){.pressed=true,.panning=button==2||(button==0&&shift),.button=button,.direction=button==1?1:-1};
}
static void zoom_release(ZoomInteraction* s,unsigned button) { if(s->button==button)*s=(ZoomInteraction){0}; }
static double zoom_step(ZoomInteraction* s,double dt) {
  if(!s->pressed||s->panning)return 0;
  s->speed+=(1.2-s->speed)*(1-exp(-10*dt));
  return s->direction*s->speed*dt;
}
#endif
