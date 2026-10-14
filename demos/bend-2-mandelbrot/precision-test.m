#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
struct Config { uint32_t limbs,iterations,real_negative,imag_negative,start,stop; };
int main(int argc,const char**argv) { @autoreleasepool {
  bool dump_state=argc==6&&!strcmp(argv[5],"--state");
  if(argc<3||argc>6||(argc==6&&!dump_state)) return 2;
  NSData* input=[NSData dataWithContentsOfFile:@(argv[1])];
  struct Config config; memcpy(&config,input.bytes,sizeof config);
  id<MTLDevice> device=MTLCreateSystemDefaultDevice();
  NSError* error=nil;
  NSString* source=[NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:&error];
  MTLCompileOptions* options=[MTLCompileOptions new];options.mathMode=MTLMathModeSafe;
  id<MTLLibrary> library=[device newLibraryWithSource:source options:options error:&error];
  if(!library){fprintf(stderr,"%s\n",error.description.UTF8String);return 3;}
  unsigned lanes=argc>=4?(unsigned)atoi(argv[3]):1;
  id<MTLComputePipelineState> pipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:lanes>1?@"reference_orbit_parallel":@"reference_orbit"] error:&error];
  id<MTLBuffer> center=[device newBufferWithBytes:(const char*)input.bytes+sizeof config length:config.limbs*8 options:MTLResourceStorageModeShared];
  id<MTLBuffer> scratch=[device newBufferWithLength:(config.limbs*8+2)*4 options:MTLResourceStorageModeShared];
  id<MTLBuffer> orbit=[device newBufferWithLength:config.iterations*8 options:MTLResourceStorageModeShared];
  id<MTLBuffer> length=[device newBufferWithLength:4 options:MTLResourceStorageModeShared];
  id<MTLCommandQueue> queue=[device newCommandQueue];
  unsigned chunk=argc>=5?(unsigned)atoi(argv[4]):config.iterations;
  double gpu_ms=0;
  for(unsigned start=0;start<config.iterations;start+=chunk) {
    config.start=start;config.stop=MIN(start+chunk,config.iterations);
    id<MTLCommandBuffer> command=[queue commandBuffer];id<MTLComputeCommandEncoder> enc=[command computeCommandEncoder];
    [enc setComputePipelineState:pipeline];[enc setBuffer:center offset:0 atIndex:0];[enc setBuffer:scratch offset:0 atIndex:1];[enc setBuffer:orbit offset:0 atIndex:2];[enc setBuffer:length offset:0 atIndex:3];[enc setBytes:&config length:sizeof config atIndex:4];
    [enc dispatchThreads:MTLSizeMake(lanes,1,1) threadsPerThreadgroup:MTLSizeMake(lanes,1,1)];[enc endEncoding];[command commit];[command waitUntilCompleted];
    if(command.error){fprintf(stderr,"%s\n",command.error.description.UTF8String);return 4;}
    gpu_ms+=(command.GPUEndTime-command.GPUStartTime)*1000;
    if(*(uint32_t*)length.contents<=config.stop&&*(uint32_t*)length.contents<config.iterations)break;
  }
  uint32_t n=*(uint32_t*)length.contents;
  fprintf(stderr,"device=%s bits=%u points=%u GPU_ms=%.3f\n",device.name.UTF8String,(config.limbs-1)*16,n,gpu_ms);
  fwrite(&n,4,1,stdout);fwrite(orbit.contents,8,n,stdout);
  if(dump_state) {
    fwrite(scratch.contents,4,config.limbs*2,stdout);
    fwrite((const uint32_t*)scratch.contents+config.limbs*8,4,2,stdout);
  }
}}
