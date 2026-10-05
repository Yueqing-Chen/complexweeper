#!/usr/bin/env node
/* 从 src/atlas.bin 里切出 32×32 的程序图标，最近邻放大成 AppImage 要的 PNG。
 *
 *   node tools/make_icon.js <atlas.bin> <输出.png> [边长]
 *
 * 图集格式：magic "CSAT" + 版本/张数/宽高（各 u16）+ 每张 8 字节矩形表 + BGRA 像素。
 * 槽位 0 固定是 icon（32×32）。放大用最近邻，和程序里把精灵放大到棋盘格的做法一致，
 * 免得图标边缘糊掉。
 */
const fs = require('fs');
const path = require('path');
const { writePNG } = require('./png.js');

const [input, outFile, sizeArg] = process.argv.slice(2);
if (!input || !outFile) {
  console.error('用法: node tools/make_icon.js <atlas.bin> <输出.png> [边长]');
  process.exit(2);
}
const size = parseInt(sizeArg || '256', 10);

let buf = fs.readFileSync(input);
const at = buf.indexOf('CSAT', 0, 'ascii');
if (at < 0) { console.error('图集魔数 CSAT 没找到: ' + input); process.exit(3); }
buf = buf.subarray(at);

const count = buf.readUInt16LE(6);
const pixOff = 12 + count * 8;
const r = { x: buf.readUInt16LE(12), y: buf.readUInt16LE(14), w: buf.readUInt16LE(16), h: buf.readUInt16LE(18) };
if (r.w !== 32 || r.h !== 32) { console.error(`槽位 0 不是 32×32（是 ${r.w}×${r.h}）`); process.exit(3); }

// 图集是 BGRA、自顶向下
const src = Buffer.alloc(r.w * r.h * 4);
for (let y = 0; y < r.h; y++) {
  const so = pixOff + ((r.y + y) * buf.readUInt16LE(8) + r.x) * 4;
  for (let x = 0; x < r.w; x++) {
    const d = (y * r.w + x) * 4;
    const s = so + x * 4;
    src[d + 0] = buf[s + 2]; // R
    src[d + 1] = buf[s + 1]; // G
    src[d + 2] = buf[s + 0]; // B
    src[d + 3] = buf[s + 3]; // A
  }
}

// 最近邻放大
const out = Buffer.alloc(size * size * 4);
for (let y = 0; y < size; y++) {
  const sy = Math.min(r.h - 1, Math.floor(y * r.h / size));
  for (let x = 0; x < size; x++) {
    const sx = Math.min(r.w - 1, Math.floor(x * r.w / size));
    src.copy(out, (y * size + x) * 4, (sy * r.w + sx) * 4, (sy * r.w + sx) * 4 + 4);
  }
}

fs.mkdirSync(path.dirname(outFile), { recursive: true });
writePNG(outFile, size, size, out);
console.log(`图标 ${outFile}  ${size}×${size}`);
