#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <unistd.h>
#include <math.h>
#include <sys/mman.h>
#include "scheduler.h"
#include "interaction.h"

typedef struct { double cx, cy, span, phase; uint32_t width, height, iterations; } Camera;
typedef struct { uint32_t magic, width, height, bytes; double render_ms; uint32_t gpu, repairs, bits, mode; } FrameHeader;
static BOOL write_all(int fd,const void* data,size_t length) {
  const unsigned char* p=data;
  while(length){ssize_t n=write(fd,p,length);if(n<=0)return NO;p+=n;length-=n;}
  return YES;
}
static BOOL read_exact(int fd, void* data, size_t length) {
  unsigned char* p=data;
  while(length) { ssize_t n=read(fd,p,length); if(n<=0) return NO; p+=n; length-=n; }
  return YES;
}

@interface RenderLane : NSObject
@property NSTask* task;
@property NSFileHandle* input;
@property NSFileHandle* output;
@property NSString* mailboxPath;
@property uint64_t* mailbox;
@property BOOL busy,cancelled;
@property NSRect viewRect,tileRect;
@end
@implementation RenderLane
- (void)stop {
  if(_task.running)[_task terminate];
  if(_mailboxPath)unlink(_mailboxPath.fileSystemRepresentation);
}
- (void)dealloc {if(_mailbox)munmap(_mailbox,8);}
@end

@interface AtlasView : NSView <NSWindowDelegate> {
  RenderScheduler schedule;
  ZoomInteraction interaction;
}
@property CALayer* imageLayer;
@property NSView* heading;
@property NSTextField* info;
@property NSTextField* status;
@property NSTextField* help;
@property NSMutableArray<RenderLane*>* lanes;
@property Camera camera;
@property Camera rendered;
@property BOOL hasImage, automatic, precisionLimit, hiddenHUD;
@property double velocity, anchorX, anchorY, lastTick, renderMilliseconds, displayedAt;
@property NSPoint dragPoint;
@property uint32_t baseIterations;
@property NSString* place;
@property NSString* backend;
@property NSTask* cameraProcess;
@property NSFileHandle* cameraInput;
@property NSFileHandle* cameraOutput;
@property double logZoom;
@property uint32_t precisionBits;
@property NSUInteger cameraGeneration;
@property double pendingScale, pendingX, pendingY;
@property NSInteger pendingPreset;
@property BOOL cameraBusy, failed, focusRequested;
@property NSUInteger preparedGeneration;
@property uint64_t completedRevision;
@property NSMutableArray<CALayer*>* patches;
@property NSData* cameraPacket;
@property NSMutableData* framePixels;
@property unsigned batchRoot;
@property double batchMilliseconds,viewStarted,viewMilliseconds,tileMilliseconds;
@end

@implementation AtlasView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSTextField*)label:(NSString*)text rect:(NSRect)rect size:(CGFloat)size color:(NSColor*)color parent:(NSView*)parent {
  NSTextField* label=[NSTextField labelWithString:text];
  label.frame=rect; label.font=[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightMedium];
  label.textColor=color; [parent addSubview:label]; return label;
}
- (instancetype)initWithFrame:(NSRect)frame {
  self=[super initWithFrame:frame];
  self.wantsLayer=YES;
  self.layer.backgroundColor=[NSColor colorWithRed:0.02 green:0.035 blue:0.055 alpha:1].CGColor;
  self.layer.masksToBounds=YES;
  _imageLayer=[CALayer layer];
  _imageLayer.contentsGravity=kCAGravityResize;
  _imageLayer.minificationFilter=kCAFilterTrilinear;
  _imageLayer.magnificationFilter=kCAFilterLinear;
  [self.layer addSublayer:_imageLayer];
  _heading=[[NSView alloc] initWithFrame:NSMakeRect(24,24,344,94)];
  _heading.wantsLayer=YES;
  _heading.layer.backgroundColor=[NSColor colorWithRed:0.025 green:0.045 blue:0.065 alpha:0.87].CGColor;
  _heading.layer.cornerRadius=12;
  _heading.layer.borderWidth=0.5;
  _heading.layer.borderColor=[NSColor colorWithWhite:1 alpha:0.18].CGColor;
  [self addSubview:_heading];
  [self label:@"M A N D E L B R O T" rect:NSMakeRect(18,61,310,20) size:15 color:NSColor.whiteColor parent:_heading];
  [self label:@"B E N D   /   T H E   S E A H O R S E   A T L A S" rect:NSMakeRect(18,41,315,15) size:8 color:[NSColor colorWithRed:0.63 green:0.83 blue:0.8 alpha:1] parent:_heading];
  _info=[self label:@"Preparing the first full-resolution frame…" rect:NSMakeRect(18,13,316,18) size:10 color:[NSColor colorWithWhite:0.75 alpha:1] parent:_heading];
  _status=[self label:@"" rect:NSMakeRect(26,frame.size.height-57,frame.size.width-52,17) size:10 color:NSColor.whiteColor parent:self];
  _status.wantsLayer=YES;
  _status.layer.shadowColor=NSColor.blackColor.CGColor;
  _status.layer.shadowOpacity=1; _status.layer.shadowRadius=4;
  _help=[self label:@"HOLD left/right zoom    SHIFT-DRAG / MIDDLE pan    SCROLL / PINCH zoom    SPACE auto    1–7 places    H hide" rect:NSMakeRect(26,frame.size.height-34,frame.size.width-52,17) size:10 color:[NSColor colorWithWhite:0.72 alpha:1] parent:self];
  _help.wantsLayer=YES; _help.layer.shadowColor=NSColor.blackColor.CGColor; _help.layer.shadowOpacity=1; _help.layer.shadowRadius=4;
  _baseIterations=384;
  _camera=(Camera){-.743643887037151,.131825904205330,.008,.4,0,0,0};
  _logZoom=log(3.4/.008);
  _place=@"Seahorse valley"; render_changed(&schedule);
  _pendingScale=1;_pendingPreset=-1;_cameraGeneration=1;_batchRoot=256;_patches=[NSMutableArray new];_lanes=[NSMutableArray new];
  _lastTick=CACurrentMediaTime();
  return self;
}
- (void)viewDidMoveToWindow {
  if(!self.window||_lanes.count) return;
  NSString* executable=[NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"worker"];
  _backend=[NSProcessInfo.processInfo.arguments containsObject:@"--cpu"] ? @"CPU" : @"Metal GPU";
  NSError* error;
  for(unsigned i=0;i<3;i++) {
    RenderLane* lane=[RenderLane new];
    char path[]="/tmp/mandelbrot-mailbox-XXXXXX";
    int fd=mkstemp(path);
    if(fd<0||ftruncate(fd,8)) {if(fd>=0){close(fd);unlink(path);}_failed=YES;break;}
    void* memory=mmap(NULL,8,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);close(fd);
    if(memory==MAP_FAILED){unlink(path);_failed=YES;break;}
    lane.mailbox=memory;lane.mailboxPath=@(path);
    __atomic_store_n(lane.mailbox,_cameraGeneration,__ATOMIC_RELEASE);
    lane.task=[NSTask new];lane.task.executableURL=[NSURL fileURLWithPath:executable];
    lane.task.arguments=[_backend isEqual:@"CPU"]?@[@"--gpu",@"off"]:@[@"--gpu",@"on"];
    NSPipe* input=[NSPipe pipe];NSPipe* output=[NSPipe pipe];
    lane.task.standardInput=input;lane.task.standardOutput=output;
    lane.input=input.fileHandleForWriting;lane.output=output.fileHandleForReading;
    NSMutableDictionary* environment=[NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"MANDELBROT_MAILBOX"]=lane.mailboxPath;lane.task.environment=environment;
    [_lanes addObject:lane];
    if(![lane.task launchAndReturnError:&error]) {_failed=YES;break;}
  }
  if(_failed){for(RenderLane* lane in _lanes)[lane stop];_status.stringValue=error.localizedDescription?:@"Unable to create render workers";return;}
  _cameraProcess=[NSTask new]; _cameraProcess.executableURL=[NSURL fileURLWithPath:@"/usr/bin/python3"];
  NSString* cameraScript=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"camera.py"];
  _cameraProcess.arguments=@[@"-u",cameraScript];
  NSPipe* cameraIn=[NSPipe pipe]; NSPipe* cameraOut=[NSPipe pipe];
  _cameraProcess.standardInput=cameraIn; _cameraProcess.standardOutput=cameraOut;
  _cameraInput=cameraIn.fileHandleForWriting; _cameraOutput=cameraOut.fileHandleForReading;
  if(![_cameraProcess launchAndReturnError:&error]) {_failed=YES;for(RenderLane* lane in _lanes)[lane stop];_status.stringValue=error.localizedDescription;return;}
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(shutdown:) name:NSApplicationWillTerminateNotification object:nil];
  double refresh=fmax(60,fmin(120,self.window.screen.maximumFramesPerSecond));
  NSTimer* timer=[NSTimer timerWithTimeInterval:1.0/refresh target:self selector:@selector(tick:) userInfo:nil repeats:YES];
  [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}
- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  _status.frame=NSMakeRect(26,size.height-57,size.width-52,17);
  _help.frame=NSMakeRect(26,size.height-34,size.width-52,17);
  [self invalidate]; [self reproject];
}
- (void)changed { render_changed(&schedule); }
- (void)invalidate {
  _cameraGeneration++;
  for(RenderLane* lane in _lanes)__atomic_store_n(lane.mailbox,_cameraGeneration,__ATOMIC_RELEASE);
  [self changed];
}
- (void)compose:(double)scale dx:(double)dx dy:(double)dy {
  _pendingX+=_pendingScale*dx;_pendingY+=_pendingScale*dy;_pendingScale*=scale;
  [self changed];
}
- (void)reproject { }
- (NSRect)transform:(NSRect)rect scale:(double)factor at:(NSPoint)point dx:(double)dx dy:(double)dy {
  return NSMakeRect(point.x+(rect.origin.x-point.x)*factor+dx,point.y+(rect.origin.y-point.y)*factor+dy,rect.size.width*factor,rect.size.height*factor);
}
- (void)moveCache:(double)factor at:(NSPoint)point dx:(double)dx dy:(double)dy {
  [CATransaction begin];[CATransaction setDisableActions:YES];
  if(_hasImage) _imageLayer.frame=[self transform:_imageLayer.frame scale:factor at:point dx:dx dy:dy];
  for(RenderLane* lane in _lanes)if(lane.busy) {
    lane.viewRect=[self transform:lane.viewRect scale:factor at:point dx:dx dy:dy];
    lane.tileRect=[self transform:lane.tileRect scale:factor at:point dx:dx dy:dy];
    double scale=lane.viewRect.size.width/self.bounds.size.width;
    if(!lane.cancelled&&(scale<.8||scale>1.25||!NSIntersectsRect(lane.tileRect,self.bounds))) {
      lane.cancelled=YES;__atomic_store_n(lane.mailbox,0,__ATOMIC_RELEASE);
    }
  }
  for(CALayer* patch in [_patches copy]) {
    patch.frame=[self transform:patch.frame scale:factor at:point dx:dx dy:dy];
    if(!NSIntersectsRect(patch.frame,self.bounds)) {[patch removeFromSuperlayer];[_patches removeObject:patch];}
  }
  [CATransaction commit];

}
- (void)zoom:(double)delta at:(NSPoint)point {
  double width=self.bounds.size.width,height=self.bounds.size.height;
  double next=_logZoom-delta;
  if(next>16000*log(2.0)) { _precisionLimit=YES;_velocity=0;_automatic=NO;interaction=(ZoomInteraction){0};return; }
  if(next<log(3.4/12.0)) { delta=_logZoom-log(3.4/12.0);next=log(3.4/12.0); }
  double scale=exp(delta);
  [self compose:scale dx:(1-scale)*(point.x-width*.5)/width dy:(1-scale)*(point.y-height*.5)/width];
  _logZoom=next;_precisionLimit=NO;[self changed];
  [self moveCache:exp(-delta) at:point dx:0 dy:0];
}
- (void)tick:(NSTimer*)timer {
  double now=CACurrentMediaTime(), dt=fmin(.1,now-_lastTick); _lastTick=now;
  double held=zoom_step(&interaction,dt);
  if(held)[self zoom:held at:NSMakePoint(_anchorX,_anchorY)];
  if(fabs(_velocity)>.00001) { double f=1-exp(-18*dt); [self zoom:_velocity*f at:NSMakePoint(_anchorX,_anchorY)]; _velocity*=1-f; }
  if(_automatic) [self zoom:-dt*.18 at:NSMakePoint(self.bounds.size.width*.5,self.bounds.size.height*.5)];
  if(render_pending(&schedule)&&!_failed) [self requestFrame];
  NSString* dimensions=_hasImage?[NSString stringWithFormat:@"%u × %u",_rendered.width,_rendered.height]:@"native pixels";
  _info.stringValue=[NSString stringWithFormat:@"%.2f e%.0f × / %@ / %@",exp(fmod(_logZoom,log(10.0))),floor(_logZoom/log(10.0)),dimensions,_backend];
  if(_failed)return;
  if(_precisionLimit) _status.stringValue=@"CURRENT GPU RESOURCE BUDGET REACHED · 16,000 precision bits. Zoom out to continue.";
  else {
    BOOL refining=schedule.active||_cameraBusy||render_pending(&schedule);
    unsigned total=schedule.columns*schedule.rows;
    NSString* progress=refining?[NSString stringWithFormat:@"%u%% refined · %.1f ms batch",total?100*schedule.completed/total:0,_renderMilliseconds]:[NSString stringWithFormat:@"%.1f ms full view",_viewMilliseconds];
    _status.stringValue=[NSString stringWithFormat:@"%@   ·   %@   ·   %u-bit GPU precision   ·   %u iterations   ·   %@",_place,_automatic?@"AUTO":@"EXPLORE",_precisionBits,_camera.iterations,progress];
  }
}
- (unsigned)preferredBatchRoot {
  BOOL moving=interaction.pressed||_automatic||fabs(_velocity)>.00001;
  double width=fmax(256,_camera.width);
  BOOL multiprecision=(log(3.4)-_logZoom)/log(2.0)-log2(width)<= -35;
  return !moving&&multiprecision&&_tileMilliseconds>0&&_tileMilliseconds<2?512:256;
}
- (unsigned)workerLimit {
  BOOL moving=interaction.pressed||_automatic||fabs(_velocity)>.00001;
  BOOL multiprecision=_cameraPacket.length>=3&&!memcmp(_cameraPacket.bytes,"MP ",3);
  return moving?((multiprecision||_camera.iterations>4096)?1:2):((_camera.iterations>4096||(multiprecision&&_batchRoot==512))?2:3);
}
- (void)prepareView {
  _cameraBusy=YES;_viewStarted=CACurrentMediaTime();
  double backing=self.window.backingScaleFactor;
  _camera.width=(unsigned)fmin(4096,fmax(256,llround(self.bounds.size.width*backing)));
  _camera.height=(unsigned)fmin(4096,fmax(256,llround(self.bounds.size.height*backing)));
  _camera.iterations=MIN(16384,_baseIterations+(uint32_t)(96*fmax(0,_logZoom/log(2.0))));
  _batchRoot=[self preferredBatchRoot];
  if(_focusRequested) {
    unsigned columns=(_camera.width+_batchRoot-1)/_batchRoot;
    unsigned px=(unsigned)fmin(_camera.width-1,fmax(0,_anchorX/self.bounds.size.width*_camera.width));
    unsigned py=(unsigned)fmin(_camera.height-1,fmax(0,_anchorY/self.bounds.size.height*_camera.height));
    schedule.cursor=(py/_batchRoot)*columns+px/_batchRoot;_focusRequested=NO;
  }
  render_prepare(&schedule,_camera.width,_camera.height,_batchRoot);
  _preparedGeneration=_cameraGeneration;
  _framePixels=[NSMutableData dataWithLength:(size_t)_camera.width*_camera.height*4];
  NSMutableString* snapshot=[NSMutableString new];
  if(_pendingPreset>=0)[snapshot appendFormat:@"preset %ld\n",(long)_pendingPreset];
  [snapshot appendFormat:@"transform %.17g %.17g %.17g\nsnapshot %u %u %u %.17g\n",_pendingScale,_pendingX,_pendingY,_camera.width,_camera.height,_camera.iterations,_camera.phase];
  _pendingPreset=-1;_pendingScale=1;_pendingX=_pendingY=0;
  NSData* text=[snapshot dataUsingEncoding:NSUTF8StringEncoding];
  int input=_cameraInput.fileDescriptor,output=_cameraOutput.fileDescriptor;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
    uint32_t size=0;
    BOOL ok=write_all(input,text.bytes,text.length)&&read_exact(output,&size,4)&&size>0&&size<100000;
    NSMutableData* packet=ok?[NSMutableData dataWithLength:size]:nil;
    ok=ok&&read_exact(output,packet.mutableBytes,size);
    dispatch_async(dispatch_get_main_queue(), ^{
      self.cameraBusy=NO;
      if(!ok){self.failed=YES;self.automatic=NO;self.status.stringValue=@"Camera service stopped. Relaunch with ./run.sh.";return;}
      self.cameraPacket=packet;[self requestFrame];
    });
  });
}
- (void)requestFrame {
  if(_failed||_cameraBusy||!_cameraProcess.running||schedule.active>=[self workerLimit])return;
  if(schedule.dirty){[self prepareView];return;}
  for(RenderLane* lane in _lanes) {
    if(lane.busy)continue;
    RenderBatch batch;
    if(!render_take(&schedule,[self workerLimit],&batch))break;
    [self renderBatch:batch lane:lane];
  }
}
- (void)renderBatch:(RenderBatch)batch lane:(RenderLane*)lane {
  lane.busy=YES;lane.cancelled=NO;lane.viewRect=self.bounds;
  Camera request=_camera;unsigned width=request.width,height=request.height;
  NSUInteger generation=_preparedGeneration;
  __atomic_store_n(lane.mailbox,generation,__ATOMIC_RELEASE);
  unsigned tileWidth=MIN(batch.root,width-batch.x),tileHeight=MIN(batch.root,height-batch.y);
  lane.tileRect=NSMakeRect(self.bounds.size.width*batch.x/width,self.bounds.size.height*batch.y/height,self.bounds.size.width*tileWidth/width,self.bounds.size.height*tileHeight/height);
  NSData* command=_cameraPacket;
  NSData* prefix=[[NSString stringWithFormat:@"T %lu %u %u %u\n",(unsigned long)generation,batch.x,batch.y,batch.root] dataUsingEncoding:NSUTF8StringEncoding];
  int input=lane.input.fileDescriptor,output=lane.output.fileDescriptor;
  double started=CACurrentMediaTime();
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
    BOOL ok=write_all(input,prefix.bytes,prefix.length)&&write_all(input,command.bytes,command.length);
    FrameHeader header={0};ok=ok&&read_exact(output,&header,sizeof header);
    BOOL cancelled=header.mode==2&&header.bytes==0;
    ok=ok&&header.magic==0x4d424632&&header.width==tileWidth&&header.height==tileHeight&&(cancelled||header.bytes==tileWidth*tileHeight*4);
    NSMutableData* data=ok?[NSMutableData dataWithLength:header.bytes]:nil;
    ok=ok&&read_exact(output,data.mutableBytes,data.length);
    dispatch_async(dispatch_get_main_queue(), ^{
      lane.busy=NO;render_finished(&self->schedule,batch.revision);
      self.batchMilliseconds=(CACurrentMediaTime()-started)*1000;
      if(ok&&!cancelled&&tileWidth==batch.root&&tileHeight==batch.root) {
        double sample=self.batchMilliseconds*256*256/((double)batch.root*batch.root);
        self.tileMilliseconds=self.tileMilliseconds?self.tileMilliseconds*.8+sample*.2:sample;
      }
      if(!ok){self.failed=YES;self.status.stringValue=@"Bend renderer stopped. Relaunch with ./run.sh; see worker diagnostics in the terminal.";self.automatic=NO;return;}
      if(cancelled||lane.cancelled||generation!=self.cameraGeneration||batch.revision<=self.completedRevision) {
        if(batch.revision==self->schedule.revision&&batch.revision>self.completedRevision)[self changed];
        [self requestFrame];return;
      }
      NSRect rect=lane.tileRect;
      BOOL current=!self->schedule.dirty&&batch.revision==self->schedule.revision;
      if(current)for(unsigned y=0;y<tileHeight;y++)memcpy((char*)self.framePixels.mutableBytes+((size_t)(batch.y+y)*width+batch.x)*4,(const char*)data.bytes+(size_t)y*tileWidth*4,tileWidth*4);
      BOOL complete=current&&render_complete(&self->schedule);
      NSData* display=complete?self.framePixels:data;
      unsigned displayWidth=complete?width:tileWidth,displayHeight=complete?height:tileHeight;
      CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)display);
      CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
      CGImageRef image=CGImageCreate(displayWidth,displayHeight,8,32,displayWidth*4,colors,kCGImageAlphaLast|kCGBitmapByteOrderDefault,provider,NULL,false,kCGRenderingIntentDefault);
      [CATransaction begin];[CATransaction setDisableActions:YES];
      if(complete) {
        self.viewMilliseconds=(CACurrentMediaTime()-self.viewStarted)*1000;
        self.imageLayer.contents=(__bridge id)image;self.imageLayer.frame=self.bounds;self.completedRevision=batch.revision;
        for(CALayer* patch in self.patches)[patch removeFromSuperlayer];[self.patches removeAllObjects];
      } else if(NSIntersectsRect(rect,self.bounds)) {
        for(CALayer* patch in [self.patches copy])if([[patch valueForKey:@"revision"] unsignedLongLongValue]<=batch.revision&&NSContainsRect(rect,patch.frame)){[patch removeFromSuperlayer];[self.patches removeObject:patch];}
        CALayer* patch=[CALayer layer];patch.contents=(__bridge id)image;patch.frame=rect;patch.contentsGravity=kCAGravityResize;patch.magnificationFilter=kCAFilterLinear;[patch setValue:@(batch.revision) forKey:@"revision"];
        NSUInteger index=0;while(index<self.patches.count&&[[self.patches[index] valueForKey:@"revision"] unsignedLongLongValue]<=batch.revision)index++;
        [self.layer insertSublayer:patch above:index?self.patches[index-1]:self.imageLayer];[self.patches insertObject:patch atIndex:index];
        while(self.patches.count>256){[self.patches.firstObject removeFromSuperlayer];[self.patches removeObjectAtIndex:0];}
      }
      self.rendered=request;self.hasImage=YES;self.renderMilliseconds=self.batchMilliseconds;
      self.backend=header.gpu?@"Metal GPU":@"CPU";self.precisionBits=header.bits;
      [CATransaction commit];CGImageRelease(image);CGColorSpaceRelease(colors);CGDataProviderRelease(provider);
      self.displayedAt=CACurrentMediaTime();[self requestFrame];
    });
  });
}
- (void)scrollWheel:(NSEvent*)event {
  NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
  _anchorX=point.x; _anchorY=point.y; _automatic=NO;_focusRequested=YES;interaction=(ZoomInteraction){0};
  _velocity+=fmax(-.6,fmin(.6,-event.scrollingDeltaY*(event.hasPreciseScrollingDeltas?.006:.10)));
}
- (void)magnifyWithEvent:(NSEvent*)event { _automatic=NO; [self zoom:-event.magnification*2 at:[self convertPoint:event.locationInWindow fromView:nil]]; }
- (void)mouseDown:(NSEvent*)event {
  _automatic=NO;_velocity=0;
  _dragPoint=[self convertPoint:event.locationInWindow fromView:nil];
  _anchorX=_dragPoint.x;_anchorY=_dragPoint.y;_focusRequested=YES;
  zoom_press(&interaction,(unsigned)event.buttonNumber,(event.modifierFlags&NSEventModifierFlagShift)!=0);
  if(!interaction.panning)[self zoom:interaction.direction*.12 at:_dragPoint];
}
- (void)rightMouseDown:(NSEvent*)event {[self mouseDown:event];}
- (void)otherMouseDown:(NSEvent*)event {if(event.buttonNumber==2)[self mouseDown:event];}
- (void)mouseUp:(NSEvent*)event {zoom_release(&interaction,(unsigned)event.buttonNumber);}
- (void)rightMouseUp:(NSEvent*)event {[self mouseUp:event];}
- (void)otherMouseUp:(NSEvent*)event {[self mouseUp:event];}
- (void)mouseDragged:(NSEvent*)event {
  NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
  if(interaction.panning) {
    double dx=point.x-_dragPoint.x,dy=point.y-_dragPoint.y;
    [self compose:1 dx:-dx/self.bounds.size.width dy:-dy/self.bounds.size.width];
    [self moveCache:1 at:NSZeroPoint dx:dx dy:dy];
  }
  _anchorX=point.x;_anchorY=point.y;_dragPoint=point;
}
- (void)rightMouseDragged:(NSEvent*)event {[self mouseDragged:event];}
- (void)otherMouseDragged:(NSEvent*)event {[self mouseDragged:event];}
- (void)windowDidResignKey:(NSNotification*)notification {interaction=(ZoomInteraction){0};_velocity=0;_automatic=NO;}
- (void)preset:(int)place {
  _velocity=0; _automatic=NO; _precisionLimit=NO;interaction=(ZoomInteraction){0};
  [self invalidate]; _hasImage=NO; _imageLayer.contents=nil;
  for(CALayer* patch in _patches)[patch removeFromSuperlayer];[_patches removeAllObjects];
  if(place==0) { _camera.cx=-.62; _camera.cy=0; _camera.span=3.4; _place=@"The whole set"; }
  if(place==1) { _camera.cx=-.743643887037151; _camera.cy=.131825904205330; _camera.span=.008; _place=@"Seahorse valley"; }
  if(place==2) { _camera.cx=-.74543; _camera.cy=.11301; _camera.span=.015; _place=@"Double spiral"; }
  if(place==3) { _camera.cx=-.743643887037151; _camera.cy=.131825904205330; _camera.span=.0000001; _place=@"Deep seahorse · 34 million times"; }
  if(place==4) { _camera.cx=0; _camera.cy=1; _camera.span=1e-12; _place=@"Deep antenna"; }
  if(place==5) { _camera.span=1e-100; _place=@"Antenna · 100 decimal orders"; }
  if(place==6) { _camera.span=1e-300; _place=@"Antenna · 300 decimal orders"; }
  _logZoom=log(3.4)-log(_camera.span);
  _pendingPreset=place;_pendingScale=1;_pendingX=_pendingY=0;
  schedule.cursor=0;[self changed];
}
- (void)keyDown:(NSEvent*)event {
  NSString* s=event.charactersIgnoringModifiers.lowercaseString;
  if([s isEqual:@"q"]||event.keyCode==53) [NSApp terminate:nil];
  else if([s isEqual:@"r"]) [self preset:1];
  else if(s.length==1&&[s characterAtIndex:0]>='1'&&[s characterAtIndex:0]<='7') [self preset:[s characterAtIndex:0]-'1'];
  else if([s isEqual:@"g"]) { [self preset:4]; _automatic=YES; }
  else if([s isEqual:@" "]) { _automatic=!_automatic; _velocity=0;interaction=(ZoomInteraction){0}; }
  else if([s isEqual:@"c"]) { _camera.phase=fmod(_camera.phase+1./6,1.); [self invalidate]; }
  else if([s isEqual:@"h"]) { _hiddenHUD=!_hiddenHUD; _heading.hidden=_hiddenHUD; _status.hidden=_hiddenHUD; _help.hidden=_hiddenHUD; }
  else if([s isEqual:@"["]) { _baseIterations=MAX(128,_baseIterations/2); [self invalidate]; }
  else if([s isEqual:@"]"]) { _baseIterations=MIN(8192,_baseIterations*2); [self invalidate]; }
  else if([s isEqual:@"+"]||[s isEqual:@"="]||[s isEqual:@"-"]) { _anchorX=self.bounds.size.width*.5; _anchorY=self.bounds.size.height*.5; _velocity+=[s isEqual:@"-"]?.3:-.3; }
}
- (BOOL)windowShouldClose:(NSWindow*)sender { [NSApp terminate:nil]; return YES; }
- (void)shutdown:(NSNotification*)notification {
  _failed=YES;for(RenderLane* lane in _lanes)[lane stop];[_cameraProcess terminate];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self];for(RenderLane* lane in _lanes)[lane stop];[_cameraInput closeFile];[_cameraProcess terminate]; }
@end

int main(int argc,const char** argv) {
  @autoreleasepool {
    [NSApplication sharedApplication]; NSApp.activationPolicy=NSApplicationActivationPolicyRegular;
    NSMenu* bar=[NSMenu new]; NSMenuItem* item=[NSMenuItem new]; [bar addItem:item];
    NSMenu* menu=[NSMenu new]; [menu addItemWithTitle:@"Quit Mandelbrot" action:@selector(terminate:) keyEquivalent:@"q"]; item.submenu=menu; NSApp.mainMenu=bar;
    NSWindow* window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1100,780) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.title=@"Mandelbrot — Bend"; window.backgroundColor=NSColor.blackColor; window.releasedWhenClosed=NO;
    window.contentMinSize=NSMakeSize(740,520);
    AtlasView* view=[[AtlasView alloc] initWithFrame:window.contentView.bounds];
    view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    window.contentView=view; window.delegate=view;
    [window makeFirstResponder:view]; [window center]; [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
  }
  return 0;
}
