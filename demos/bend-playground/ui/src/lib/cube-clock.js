// The clock is simulation time in seconds, never a collision index.
export function duration(data){
  return data.motion?.length?data.motion.at(-1).time:data.frames.at(-1).time+2;
}

export function stateAt(data,time){
  const sampled=!!data.motion?.length,frames=sampled?data.motion:data.frames;
  time=Math.max(0,Math.min(time,duration(data)));
  let lo=0,hi=frames.length;
  while(lo+1<hi){const mid=(lo+hi)>>>1;if(frames[mid].time<=time)lo=mid;else hi=mid;}
  const s=frames[lo],next=frames[lo+1],dt=time-s.time;
  let x,y;
  if(sampled&&next&&next.count!==s.count){
    // These are uniformly spaced physical-time samples computed in Bend.
    // Interpolate the recorded positions, not an invented collision sequence.
    const f=dt/(next.time-s.time);
    x=s.x+(next.x-s.x)*f;y=s.y+(next.y-s.y)*f;
  }else{
    x=s.x+s.v*dt;y=s.y+s.w*dt;
  }
  // F32 event timestamps can put the displayed contact a few ulps past a wall.
  y=Math.max(0,y);x=Math.min(y,Math.max(0,x));
  return {...s,x,y,time,eventTime:s.time,index:lo,sampled};
}

export function nextTime(data,time){
  const frames=data.motion?.length?data.motion:data.frames;
  return frames.find(f=>f.time>time+1e-7)?.time??duration(data);
}
