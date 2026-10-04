/* 把编进 exe 的那张图集导成 PNG，方便直接看（或核对），并生成「整图模式」要的槽位表。
   输入可以是 src/atlas.bin，也可以是 复扫雷.exe（会在里面找 CSAT 魔数）。
   用法: node tools/dump_atlas.js <atlas.bin 或 exe> <输出目录>
   输出（都是 1:1 原生尺寸，放大交给程序做整数倍最近邻，这里不再出放大版）:
     atlas.png      整图（保留 alpha，和图集里逐字节一致）
     atlas.json     槽位表（槽位名 → 矩形，数组顺序就是槽位号）
     sprites/       逐张切开的小图 + sprites.txt（名字 / 尺寸 / 位置） */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const [input, outDir] = process.argv.slice(2);
if (!input || !outDir) { console.error('用法: node tools/dump_atlas.js <atlas.bin 或 exe> <输出目录>'); process.exit(2); }
fs.mkdirSync(outDir, { recursive: true });

let buf = fs.readFileSync(input);
let at = buf.indexOf('CSAT', 0, 'ascii');
if (at < 0) { console.error('找不到图集魔数 CSAT：' + input); process.exit(3); }
buf = buf.subarray(at);

const version = buf.readUInt16LE(4);
const count = buf.readUInt16LE(6);
const W = buf.readUInt16LE(8);
const H = buf.readUInt16LE(10);
const pixOff = 12 + count * 8;
if (buf.length < pixOff + W * H * 4) { console.error(`图集数据不完整：需要 ${pixOff + W * H * 4} 字节，实际 ${buf.length}`); process.exit(3); }

const rects = [];
for (let i = 0; i < count; i++) {
  const o = 12 + i * 8;
  rects.push({ i, x: buf.readUInt16LE(o), y: buf.readUInt16LE(o + 2), w: buf.readUInt16LE(o + 4), h: buf.readUInt16LE(o + 6) });
}
console.log(`图集 v${version}：${W}×${H}，${count} 张，像素 ${W * H * 4} 字节（源：${input}，魔数偏移 ${at}）`);

/* ---- 最小 PNG 编码器 ---- */
let crcTable = null;
function crc32(b) {
  if (!crcTable) {
    crcTable = [];
    for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcTable[n] = c >>> 0; }
  }
  let c = 0xFFFFFFFF;
  for (const byte of b) c = crcTable[(c ^ byte) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function png(width, height, rgba) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0; // filter: none
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = 6; // 8bit RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}

// 图集像素是 BGRA（GDI 的顺序）→ RGBA
const raw = Buffer.alloc(W * H * 4);
for (let i = 0; i < W * H; i++) {
  const o = pixOff + i * 4;
  raw[i * 4] = buf[o + 2]; raw[i * 4 + 1] = buf[o + 1]; raw[i * 4 + 2] = buf[o]; raw[i * 4 + 3] = buf[o + 3];
}
const p1 = path.join(outDir, 'atlas.png');
fs.writeFileSync(p1, png(W, H, raw));
console.log('写出 ' + p1 + `（1:1 原生尺寸，保留 alpha；素材只保留这一档，放大由程序做整数倍）`);

// 顺手把矩形表打出来（前 12 项 + 末 3 项，中间太多）
const show = (r) => `  #${String(r.i).padStart(2)}  (${String(r.x).padStart(3)},${String(r.y).padStart(2)})  ${r.w}×${r.h}`;
console.log('矩形表（前 12 项）：');
rects.slice(0, 12).forEach(r => console.log(show(r)));
console.log(`  … 共 ${count} 项`);

/* ---- 再逐张导出一遍：名字取自 src/assets.zig 里生成器写的 "<序号> <名字>" 注释 ---- */
const spritesDir = path.join(outDir, 'sprites');
fs.mkdirSync(spritesDir, { recursive: true });
const nameByIndex = new Map();
const assetsPath = path.join(__dirname, '..', 'src', 'assets.zig');
if (fs.existsSync(assetsPath)) {
  const txt = fs.readFileSync(assetsPath, 'utf8');
  const re = /\.w\s*=\s*\d+,\s*\.h\s*=\s*\d+\s*\},\s*\/\/\s*(\d+)\s+(\S+)/g;
  let m;
  while ((m = re.exec(txt))) nameByIndex.set(Number(m[1]), m[2]);
}
const listing = [];
for (const r of rects) {
  const name = nameByIndex.get(r.i) || `sprite_${String(r.i).padStart(2, '0')}`;
  const sub = Buffer.alloc(r.w * r.h * 4);
  for (let y = 0; y < r.h; y++) {
    const src = (r.y + y) * W * 4 + r.x * 4;
    raw.copy(sub, y * r.w * 4, src, src + r.w * 4);
  }
  fs.writeFileSync(path.join(spritesDir, name + '.png'), png(r.w, r.h, sub));
  listing.push(`${String(r.i).padStart(2)}  ${name.padEnd(24)} ${String(r.w).padStart(2)}×${String(r.h).padStart(2)}  @(${String(r.x).padStart(3)},${String(r.y).padStart(2)})`);
}
fs.writeFileSync(path.join(outDir, 'sprites.txt'), listing.join('\r\n') + '\r\n', 'utf8');
console.log(`写出 ${spritesDir}（逐张 ${count} 个 PNG，1:1 原生尺寸）与 sprites.txt（序号 / 名字 / 尺寸 / 图集位置）`);
console.log(`名字来自 src/assets.zig，${nameByIndex.size}/${count} 张认出了名字`);

/* ---- 槽位表：素材/图集.json 就是这份东西（构建时读它 + 图集.png 出 atlas.bin） ---- */
const meta = {
  version: 1,
  width: W,
  height: H,
  slots: rects.map(r => ({ name: nameByIndex.get(r.i) || ('sprite_' + r.i), x: r.x, y: r.y, w: r.w, h: r.h })),
};
const metaPath = path.join(outDir, 'atlas.json');
fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2) + '\n', 'utf8');
console.log(`写出 ${metaPath}（${meta.slots.length} 个槽位，顺序就是槽位号）`);
