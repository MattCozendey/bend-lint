// Plain-text PPM, as used in Ray Tracing in One Weekend. Pixels are already
// gamma-encoded by Bend; display the channels without another color transform.
export function decodePpm(text){
  const tokens=/#[^\r\n]*|[^\s#]+/g;
  function next(){
    let token;
    do{token=tokens.exec(text)?.[0];}while(token?.startsWith('#'));
    return token;
  }
  function integer(){
    const token=next();
    if(!/^\d+$/.test(token??''))throw new Error('Invalid or incomplete PPM data.');
    const value=Number(token);
    if(!Number.isSafeInteger(value))throw new Error('Invalid PPM integer.');
    return value;
  }
  if(next()!=='P3')throw new Error('Expected plain-text P3 PPM data.');
  const width=integer(),height=integer(),maximum=integer(),count=width*height;
  if(!width||!height||!Number.isSafeInteger(count)||count*3>text.length)throw new Error('Invalid or incomplete PPM dimensions.');
  if(maximum!==255)throw new Error('Expected 8-bit PPM colors (maximum 255).');
  const rgba=new Uint8ClampedArray(count*4);
  for(let i=0;i<rgba.length;i+=4){
    for(let channel=0;channel<3;channel++){
      const value=integer();
      if(value>255)throw new Error('PPM color is outside 0–255.');
      rgba[i+channel]=value;
    }
    rgba[i+3]=255;
  }
  if(next()!==undefined)throw new Error('Unexpected pixels after the PPM image.');
  return {width,height,rgba};
}
