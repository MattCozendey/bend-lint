#define main atlas_app_main
#import "host.m"
#undef main
#include <assert.h>
@interface TestPointer : NSObject
@property NSPoint locationInWindow;
@property NSEventModifierFlags modifierFlags;
@property NSInteger buttonNumber;
@end
@implementation TestPointer
@end
static NSEvent* pointer(NSEventType type,NSPoint point,NSEventModifierFlags flags) {
  TestPointer* event=[TestPointer new];event.locationInWindow=point;event.modifierFlags=flags;
  event.buttonNumber=type==NSEventTypeRightMouseDown?1:0;
  return (NSEvent*)(id)event;
}
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    // No window or worker is created: exercise the actual view handlers offscreen.
    AtlasView* view=[[AtlasView alloc] initWithFrame:NSMakeRect(0,0,1100,780)];
    double before=view.logZoom;
    [view mouseDown:pointer(NSEventTypeLeftMouseDown,NSMakePoint(550,390),0)];
    assert(fabs(view.logZoom-before-.12)<1e-10);
    for(unsigned i=0;i<20;i++){view.lastTick=CACurrentMediaTime()-.05;[view tick:nil];}
    assert(view.logZoom>before+1);
    [view mouseUp:pointer(NSEventTypeLeftMouseUp,NSMakePoint(550,390),0)];
    before=view.logZoom;view.lastTick=CACurrentMediaTime()-.05;[view tick:nil];assert(view.logZoom==before);
    [view rightMouseDown:pointer(NSEventTypeRightMouseDown,NSMakePoint(550,390),0)];
    assert(view.logZoom<before);
    [view windowDidResignKey:[NSNotification notificationWithName:NSWindowDidResignKeyNotification object:nil]];before=view.logZoom;view.lastTick=CACurrentMediaTime()-.05;[view tick:nil];assert(view.logZoom==before);
    [view preset:1];
    [view mouseDown:pointer(NSEventTypeLeftMouseDown,NSMakePoint(550,390),NSEventModifierFlagShift)];
    before=view.logZoom;
    [view mouseDragged:pointer(NSEventTypeLeftMouseDragged,NSMakePoint(660,445),NSEventModifierFlagShift)];
    assert(view.logZoom==before&&fabs(view.pendingX+.1)<1e-12&&fabs(fabs(view.pendingY)-.05)<1e-12);
    [view mouseUp:pointer(NSEventTypeLeftMouseUp,NSMakePoint(660,445),NSEventModifierFlagShift)];
    assert([view workerLimit]==3);
    view.cameraPacket=[@"MP " dataUsingEncoding:NSUTF8StringEncoding];
    [view mouseDown:pointer(NSEventTypeLeftMouseDown,NSMakePoint(550,390),0)];
    assert([view workerLimit]==1);
    [view mouseUp:pointer(NSEventTypeLeftMouseUp,NSMakePoint(550,390),0)];
    Camera expensive=view.camera;expensive.iterations=16384;view.camera=expensive;
    assert([view workerLimit]==2);
    view.logZoom=log(3.4)+68*log(10.0);view.tileMilliseconds=1.25;
    assert([view preferredBatchRoot]==512);
    [view mouseDown:pointer(NSEventTypeLeftMouseDown,NSMakePoint(550,390),0)];
    assert([view preferredBatchRoot]==256);
    [view mouseUp:pointer(NSEventTypeLeftMouseUp,NSMakePoint(550,390),0)];
    view.tileMilliseconds=4;assert([view preferredBatchRoot]==256);
    puts("Actual AppKit handlers passed offscreen: click, timed hold, right zoom, release, focus loss, Shift-drag pan.");
  }
}
