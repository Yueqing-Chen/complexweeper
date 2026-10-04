/* 把 素材/ 里的 PNG 打包成一个图集（atlas.bin）+ 生成 Zig 侧的索引表（src/assets.zig）。
   图集格式（小端）：
     magic  "CSAT"      4 字节
     u16 version = 1
     u16 count
     u16 width, u16 height
     count 项：u16 x, u16 y, u16 w, u16 h
     像素数据：width*height*4 字节，BGRA8（GDI 的 32bpp DIB 顺序），行内自顶向下
   素材只有这一种来源：素材/图集.png + 素材/图集.json（槽位名 → 矩形，数组顺序就是槽位号）。
   早期那套"61 张单张 PNG 按文件名映射后货架打包"的做法已作废：改素材就直接改那张大图，
   槽位表用 tools/dump_atlas.js 生成/维护；放大交给程序做整数倍最近邻（素材只保留原生尺寸）。
   这里只做校验：名字不重、矩形不越界、24 个显示值贴图齐不齐。

   用法: node tools/gen_atlas.js [--out-bin 路径] [--out-zig 路径] */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const root = path.resolve(__dirname, '..', '..');          // 项目根
const assetDir = path.join(root, '素材');
const outDir = path.resolve(__dirname, '..');
const argv = process.argv.slice(2);
const argValue = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null; };
const binPath = argValue('--out-bin') ? path.resolve(argValue('--out-bin')) : path.join(outDir, 'src', 'atlas.bin');
const zigPath = argValue('--out-zig') ? path.resolve(argValue('--out-zig')) : path.join(outDir, 'src', 'assets.zig');
const PACKED_PNG = path.join(assetDir, '图集.png');
const PACKED_JSON = path.join(assetDir, '图集.json');

/* ---------------- 最小 PNG 解码（够用即可：支持 8 位 RGBA / RGB / 调色板） ---------------- */
function readPNG(file){
  const buf = fs.readFileSync(file);
  let off = 8, w = 0, h = 0, bitDepth = 0, colorType = 0, interlace = 0;
  const idat = []; let palette = null, trns = null;
  while (off < buf.length){
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR'){
      w = data.readUInt32BE(0); h = data.readUInt32BE(4);
      bitDepth = data[8]; colorType = data[9]; interlace = data[12];
    } else if (type === 'PLTE') palette = Buffer.from(data);
    else if (type === 'tRNS') trns = Buffer.from(data);
    else if (type === 'IDAT') idat.push(Buffer.from(data));
    else if (type === 'IEND') break;
    off += 12 + len;
  }
  if (bitDepth !== 8) throw new Error(file + ': 只支持 8 位色深，实际 ' + bitDepth);
  if (interlace) throw new Error(file + ': 不支持隔行扫描');
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
  if (!channels) throw new Error(file + ': 不支持的颜色类型 ' + colorType);
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * channels;
  const out = Buffer.alloc(stride * h);
  let pos = 0;
  for (let y = 0; y < h; y++){
    const ft = raw[pos++];
    const line = raw.subarray(pos, pos + stride); pos += stride;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    for (let i = 0; i < stride; i++){
      const a = i >= channels ? cur[i - channels] : 0, b = prev[i], c = i >= channels ? prev[i - channels] : 0;
      let v = line[i];
      if (ft === 1) v += a; else if (ft === 2) v += b; else if (ft === 3) v += (a + b) >> 1;
      else if (ft === 4){ const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); }
      cur[i] = v & 0xff;
    }
  }
  // 统一成 RGBA
  const rgba = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++){
    const s = y * stride + x * channels, d = (y * w + x) * 4;
    if (colorType === 6) { rgba[d] = out[s]; rgba[d+1] = out[s+1]; rgba[d+2] = out[s+2]; rgba[d+3] = out[s+3]; }
    else if (colorType === 2) { rgba[d] = out[s]; rgba[d+1] = out[s+1]; rgba[d+2] = out[s+2]; rgba[d+3] = 255; }
    else if (colorType === 0) { rgba[d] = rgba[d+1] = rgba[d+2] = out[s]; rgba[d+3] = 255; }
    else if (colorType === 4) { rgba[d] = rgba[d+1] = rgba[d+2] = out[s]; rgba[d+3] = out[s+1]; }
    else { const i = out[s]; rgba[d] = palette[i*3]; rgba[d+1] = palette[i*3+1]; rgba[d+2] = palette[i*3+2];
           rgba[d+3] = trns && i < trns.length ? trns[i] : 255; }
  }
  return { w, h, rgba };
}

/* ---------------- 素材来源：素材/图集.png + 素材/图集.json（唯一来源） ---------------- */
const ACHIEVABLE = [0,1,2,4,5,8,9,10,13,16,17,18,20,25,26,29,32,34,36,37,40,49,50,64];
if (!fs.existsSync(PACKED_PNG) || !fs.existsSync(PACKED_JSON)) {
  throw new Error('缺少 素材/图集.png 或 素材/图集.json —— 素材只有这一种来源（散图模式已作废）');
}

let W, H, placed;
const meta = JSON.parse(fs.readFileSync(PACKED_JSON, 'utf8'));
if (meta.version !== 1) throw new Error('图集.json 的 version 不认识：' + meta.version);
W = meta.width; H = meta.height;
const sheet = readPNG(PACKED_PNG);
if (sheet.w !== W || sheet.h !== H) throw new Error(`整图尺寸与 json 不符：png ${sheet.w}×${sheet.h}，json ${W}×${H}`);
const seen = new Set();
placed = meta.slots.map((s, i) => {
  if (!s || typeof s.name !== 'string' || !s.name) throw new Error('第 ' + i + ' 个槽位没有名字');
  if (seen.has(s.name)) throw new Error('槽位重名：' + s.name);
  seen.add(s.name);
  if (!(s.w > 0) || !(s.h > 0) || s.x < 0 || s.y < 0 || s.x + s.w > W || s.y + s.h > H) {
    throw new Error(`槽位越界或尺寸非法：${s.name} (${s.x},${s.y} ${s.w}×${s.h})`);
  }
  const rgba = Buffer.alloc(s.w * s.h * 4);
  for (let ry = 0; ry < s.h; ry++) {
    sheet.rgba.copy(rgba, ry * s.w * 4, ((s.y + ry) * W + s.x) * 4, ((s.y + ry) * W + s.x + s.w) * 4);
  }
  return { name: s.name, x: s.x, y: s.y, w: s.w, h: s.h, im: { w: s.w, h: s.h, rgba } };
});
for (const D of ACHIEVABLE) if (!seen.has('num_' + D)) throw new Error('整图里缺少 D=' + D + ' 的贴图（num_' + D + '）');
const numCount = [...seen].filter(n => /^num_\d+$/.test(n)).length;
if (numCount !== ACHIEVABLE.length) throw new Error('整图里的数字贴图数量不对：' + numCount);
console.log(`素材来源：整图（图集.png + 图集.json，${placed.length} 个槽位，${W}×${H}）`);

const pix = Buffer.alloc(W * H * 4);      // 0 = 透明黑
// 计时/计数的 LED 素材里，"未点亮的段"是用 128,0,0 与黑交替点阵画出来的（半色调虚段）。
// 13×23 原尺寸下看着像淡淡的残影，但游戏里贴图要放大到 2×/3×，每个点变成 2×2/3×3 的方块，
// 整块数字就变成一片噪点、像被压扁了。这里把虚段的暗红像素抹成黑，只留点亮的段，
// 放大后就是干净的经典 LED。想保留虚段效果把这一行改成 false。
const CLEAN_LED_GHOST_SEGMENTS = false;
for (const p of placed){
  const is_led = CLEAN_LED_GHOST_SEGMENTS && p.name.startsWith('led_');
  for (let ry = 0; ry < p.h; ry++){
    for (let rx = 0; rx < p.w; rx++){
      const s = (ry * p.w + rx) * 4, d = ((p.y + ry) * W + (p.x + rx)) * 4;
      let r = p.im.rgba[s], g = p.im.rgba[s + 1], b = p.im.rgba[s + 2];
      if (is_led && r > 40 && r < 200 && g < 40 && b < 40){ r = 0; g = 0; b = 0; }
      pix[d]     = b;                     // B
      pix[d + 1] = g;                     // G
      pix[d + 2] = r;                     // R
      pix[d + 3] = p.im.rgba[s + 3];      // A
    }
  }
}

/* ---------------- 写出 atlas.bin ---------------- */
const header = Buffer.alloc(12 + placed.length * 8);
header.write('CSAT', 0, 'ascii');
header.writeUInt16LE(1, 4);
header.writeUInt16LE(placed.length, 6);
header.writeUInt16LE(W, 8);
header.writeUInt16LE(H, 10);
placed.forEach((p, i) => {
  const o = 12 + i * 8;
  header.writeUInt16LE(p.x, o); header.writeUInt16LE(p.y, o + 2);
  header.writeUInt16LE(p.w, o + 4); header.writeUInt16LE(p.h, o + 6);
});
fs.mkdirSync(path.dirname(binPath), { recursive: true });
fs.writeFileSync(binPath, Buffer.concat([header, pix]));

/* ---------------- 写出 src/assets.zig ---------------- */
const idx = new Map(placed.map((p, i) => [p.name, i]));
const lines = [];
lines.push('// 本文件由 tools/gen_atlas.js 自动生成，不要手改。');
lines.push('// 图集来自 素材/ 目录，格式见 tools/gen_atlas.js 顶部注释。');
lines.push('');
lines.push('pub const blob = @embedFile("atlas.bin");');
lines.push('pub const atlas_w: u16 = ' + W + ';');
lines.push('pub const atlas_h: u16 = ' + H + ';');
lines.push('pub const count: u16 = ' + placed.length + ';');
lines.push('');
lines.push('pub const Rect = struct { x: u16, y: u16, w: u16, h: u16 };');
lines.push('pub const rects = [_]Rect{');
placed.forEach((p, i) => {
  lines.push('    .{ .x = ' + p.x + ', .y = ' + p.y + ', .w = ' + p.w + ', .h = ' + p.h + ' }, // ' + i + ' ' + p.name);
});
lines.push('};');
lines.push('');
lines.push('pub fn rect(i: u16) Rect { return rects[i]; }');
lines.push('');
for (const [name, i] of idx) lines.push('pub const ' + name + ': u16 = ' + i + ';');
lines.push('');
lines.push('/// 显示值 D = |S|^2 -> 数字贴图；表外为 0xFFFF（不该出现）');
lines.push('pub const num_by_D = blk: {');
lines.push('    var t = [_]u16{0xFFFF} ** 65;');
for (const D of ACHIEVABLE) lines.push('    t[' + D + '] = num_' + D + ';');
lines.push('    break :blk t;');
lines.push('};');
lines.push('');
fs.mkdirSync(path.dirname(zigPath), { recursive: true });
fs.writeFileSync(zigPath, lines.join('\n') + '\n');

const total = placed.reduce((a, p) => a + p.w * p.h, 0);
console.log('图集: ' + W + 'x' + H + '，' + placed.length + ' 张，' +
  '像素 ' + total + '，bin ' + (fs.statSync(binPath).size) + ' 字节');
console.log('写出 ' + binPath);
console.log('写出 ' + zigPath);
