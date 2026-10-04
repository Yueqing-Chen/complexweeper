/* 最小 PNG 编解码（无依赖），给 tools/ 下几个脚本共用。
   readPNG(file) → { w, h, rgba }（统一成 8bit RGBA）
   writePNG(file, w, h, rgba) → 写 8bit RGBA 的 PNG（不做滤波，够小图用） */
const fs = require('fs');
const zlib = require('zlib');

function readPNG(file) {
  const buf = fs.readFileSync(file);
  let off = 8, w = 0, h = 0, bitDepth = 0, colorType = 0;
  const idat = [];
  let palette = null, trns = null;
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); bitDepth = data[8]; colorType = data[9]; }
    else if (type === 'PLTE') palette = Buffer.from(data);
    else if (type === 'tRNS') trns = Buffer.from(data);
    else if (type === 'IDAT') idat.push(Buffer.from(data));
    else if (type === 'IEND') break;
    off += 12 + len;
  }
  if (bitDepth !== 8) throw new Error('只支持 8bit PNG：' + file);
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
  if (!channels) throw new Error('不支持的 PNG 颜色类型 ' + colorType + '：' + file);
  const bpp = Math.max(1, Math.ceil(bitDepth * channels / 8));
  const stride = Math.ceil(bitDepth * channels * w / 8);
  const out = Buffer.alloc(stride * h);
  let pos = 0;
  for (let y = 0; y < h; y++) {
    const ft = raw[pos++];
    const line = raw.subarray(pos, pos + stride); pos += stride;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      if (ft === 1) v += a; else if (ft === 2) v += b; else if (ft === 3) v += (a + b) >> 1;
      else if (ft === 4) {
        const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      }
      cur[i] = v & 0xff;
    }
  }
  const rgba = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    const d = i * 4;
    if (colorType === 6) out.copy(rgba, d, i * 4, i * 4 + 4);
    else if (colorType === 2) { rgba[d] = out[i * 3]; rgba[d + 1] = out[i * 3 + 1]; rgba[d + 2] = out[i * 3 + 2]; rgba[d + 3] = 255; }
    else if (colorType === 0) { rgba[d] = rgba[d + 1] = rgba[d + 2] = out[i]; rgba[d + 3] = 255; }
    else if (colorType === 3) {
      const p = out[i];
      rgba[d] = palette[p * 3]; rgba[d + 1] = palette[p * 3 + 1]; rgba[d + 2] = palette[p * 3 + 2];
      rgba[d + 3] = trns && p < trns.length ? trns[p] : 255;
    }
  }
  return { w, h, rgba };
}

let crcTable = null;
function crc32(b) {
  if (!crcTable) {
    crcTable = [];
    for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcTable[n] = c >>> 0; }
  }
  let c = 0xFFFFFFFF;
  for (const x of b) c = crcTable[(c ^ x) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

function writePNG(file, width, height, rgba) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; // 8bit RGBA
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.writeFileSync(file, png);
  return png.length;
}

/** 逐像素比较两张同尺寸 RGBA，返回 { n: 不同像素数, worst: 最大分量差 } */
function diffRGBA(a, b) {
  let n = 0, worst = 0;
  for (let i = 0; i < a.length; i += 4) {
    const d = Math.max(
      Math.abs(a[i] - b[i]), Math.abs(a[i + 1] - b[i + 1]),
      Math.abs(a[i + 2] - b[i + 2]), Math.abs(a[i + 3] - b[i + 3]));
    if (d) { n++; if (d > worst) worst = d; }
  }
  return { n, worst };
}

module.exports = { readPNG, writePNG, diffRGBA };
