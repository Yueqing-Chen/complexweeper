/* 把程序 --shot 输出的 32 位 BMP 转成 PNG，方便用 tools/crop.js 与看图工具核对。
   用法: node tools/bmp2png.js <in.bmp> <out.png> */
const fs = require('fs');
const zlib = require('zlib');

const [src, dst] = process.argv.slice(2);
if (!src || !dst) { console.error('用法: node tools/bmp2png.js <in.bmp> <out.png>'); process.exit(2); }
const b = fs.readFileSync(src);
if (b.readUInt16LE(0) !== 0x4D42) { console.error('不是 BMP'); process.exit(2); }
const dataOff = b.readUInt32LE(10);
const hdrSize = b.readUInt32LE(14);
const w = b.readInt32LE(18);
const h = b.readInt32LE(22);
const bpp = b.readUInt16LE(28);
const compression = b.readUInt32LE(30);
if (compression !== 0) { console.error('只支持未压缩 BMP，compression=' + compression); process.exit(2); }
if (bpp !== 32 && bpp !== 24) { console.error('只支持 24/32 位，bpp=' + bpp); process.exit(2); }

const bottomUp = h > 0;
const H = Math.abs(h);
const bytespp = bpp / 8;
const stride = Math.ceil(w * bytespp / 4) * 4;
const raw = Buffer.alloc((w * 3 + 1) * H);
let p = 0;
for (let y = 0; y < H; y++) {
  raw[p++] = 0;                                  // 过滤器：无
  const sy = bottomUp ? H - 1 - y : y;
  const rowOff = dataOff + sy * stride;
  for (let x = 0; x < w; x++) {
    const o = rowOff + x * bytespp;
    raw[p++] = b[o + 2];                         // R
    raw[p++] = b[o + 1];                         // G
    raw[p++] = b[o];                             // B
  }
}

function crc32(buf) { let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) { c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crc = c ^ (crc >>> 8); }
  return (crc ^ 0xffffffff) >>> 0; }
function chunk(type, data) { const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const t = Buffer.from(type, 'ascii'); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([len, t, data, crc]); }
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.writeFileSync(dst, Buffer.concat([Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]),
  chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]));
console.log('-> ' + dst + '  ' + w + 'x' + H);
