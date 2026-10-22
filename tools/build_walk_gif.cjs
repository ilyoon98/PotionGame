// Dependency-free GIF preview encoder; production PNGs remain unquantized.
const fs = require('fs');
const path = require('path');
const dir = path.resolve(__dirname, '../assets/characters/walk_cycles_v3');
const width = 896, height = 288;
const frames = Array.from({length: 4}, (_, i) => fs.readFileSync(path.join(dir, `walk_preview_frame_${i}.rgba`)));
const palette = [], colorIndex = new Map();
const indexed = frames.map(frame => {
  if (frame.length !== width * height * 4) throw Error('Incorrect RGBA frame size');
  const result = Buffer.alloc(width * height);
  for (let i = 0; i < result.length; i++) {
    const color = [frame[i*4], frame[i*4+1], frame[i*4+2]].map(v => Math.min(255, Math.round(v/24)*24));
    const key = color.join(',');
    if (!colorIndex.has(key)) { colorIndex.set(key, palette.length); palette.push(color); }
    if (palette.length > 256) throw Error('Palette overflow');
    result[i] = colorIndex.get(key);
  }
  return result;
});
const word = n => Buffer.from([n & 255, n >> 8 & 255]);
const table = Buffer.alloc(256 * 3);
palette.forEach((color, i) => color.forEach((value, c) => table[i*3+c] = value));
const chunks = [Buffer.from('GIF89a'), word(width), word(height), Buffer.from([0xf7,0,0]), table,
  Buffer.from([0x21,0xff,11]), Buffer.from('NETSCAPE2.0'), Buffer.from([3,1,0,0,0])];
for (const pixels of indexed) {
  // Eight frames per second, approximated with alternating centisecond delays.
  const delay = chunks.filter(x => x.length === 8 && x[1] === 0xf9).length % 2 ? 13 : 12;
  chunks.push(Buffer.from([0x21,0xf9,4,4,delay,0,0,0]), Buffer.from([0x2c]), word(0),word(0),word(width),word(height),Buffer.from([0,8]));
  // Frequent CLEAR codes keep every LZW code at 9 bits, simple and valid.
  const bytes = []; let bits = 0, value = 0;
  const emit = code => {value |= code << bits; bits += 9; while(bits >= 8){bytes.push(value & 255); value >>>= 8; bits -= 8;}};
  for (const pixel of pixels) { emit(256); emit(pixel); }
  emit(257); if(bits) bytes.push(value & 255);
  const encoded = Buffer.from(bytes);
  for(let start=0; start<encoded.length; start+=255){const block=encoded.subarray(start,start+255);chunks.push(Buffer.from([block.length]),block);}
  chunks.push(Buffer.from([0]));
}
chunks.push(Buffer.from([0x3b]));
const output = path.join(dir, 'walk_loop_4frames_4x.gif');
fs.writeFileSync(output, Buffer.concat(chunks));
// These exact generated intermediate buffers are no longer needed.
for(let i=0;i<4;i++) fs.unlinkSync(path.join(dir, `walk_preview_frame_${i}.rgba`));
console.log(`Created 4-frame walking GIF, ${width}x${height}, ${palette.length} preview colors`);
