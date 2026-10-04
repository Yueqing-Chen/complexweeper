/* 给 exe 注入图标资源（Zig 没有资源编译器，所以自己写 PE 的 .rsrc 节）。
   图标来源：图集里的 icon 槽位（素材/图标.png，32×32，带 alpha）。
   写出 16 / 32 / 48 三种尺寸：16 = 2×2 方框平均（原图是点阵抖动，抽样会走样），
   32 = 原图，48 = 最近邻放大 1.5×（像素画宁可硬边也不要糊）。
   用法: node tools/set_icon.js <输入exe> <输出exe> */
const fs = require('fs');
const path = require('path');

const [inExe, outExe] = process.argv.slice(2);
if (!inExe || !outExe) { console.error('用法: node tools/set_icon.js <输入exe> <输出exe>'); process.exit(2); }

/* ---------------- 1. 从 atlas.bin 里取出图标像素 ---------------- */
const atlasPath = path.resolve(__dirname, '..', 'src', 'atlas.bin');
const atlas = fs.readFileSync(atlasPath);
if (atlas.toString('ascii', 0, 4) !== 'CSAT') { console.error('atlas.bin 格式不对'); process.exit(2); }
const count = atlas.readUInt16LE(6);
const atlasW = atlas.readUInt16LE(8);
const pixOff = 12 + count * 8;
// 从生成的 assets.zig 里解析下标，别猜
const assetsZig = fs.readFileSync(path.resolve(__dirname, '..', 'src', 'assets.zig'), 'utf8');
const m = /pub const icon: u16 = (\d+);/.exec(assetsZig);
if (!m) { console.error('assets.zig 里找不到 icon（素材/图标.png 没进图集？）'); process.exit(2); }
const idx = parseInt(m[1], 10);
const rx = atlas.readUInt16LE(12 + idx * 8);
const ry = atlas.readUInt16LE(12 + idx * 8 + 2);
const SW = atlas.readUInt16LE(12 + idx * 8 + 4);
const SH = atlas.readUInt16LE(12 + idx * 8 + 6);
if (SW !== 32 || SH !== 32) { console.error(`图标应为 32×32，实际 ${SW}×${SH}`); process.exit(2); }

const px = (x, y) => {                        // 图集像素（BGRA，直通 alpha）
  const o = pixOff + ((ry + y) * atlasW + (rx + x)) * 4;
  return [atlas[o], atlas[o + 1], atlas[o + 2], atlas[o + 3]];   // B,G,R,A
};

/* ---------------- 2. 生成 16 / 32 / 48 三档 RGBA ---------------- */
const RGBA = (w, h) => ({ w, h, px: new Uint8Array(w * h * 4) });

// 原图
const src = RGBA(SW, SH);
for (let y = 0; y < SH; y++) for (let x = 0; x < SW; x++) {
  const c = px(x, y), o = (y * SW + x) * 4;
  src.px[o] = c[2]; src.px[o + 1] = c[1]; src.px[o + 2] = c[0]; src.px[o + 3] = c[3];
}

// 2×2 方框平均：按 alpha 加权求 RGB，alpha 取平均（点阵抖动这样才会变成中间灰）
function half(img) {
  const out = RGBA(img.w >> 1, img.h >> 1);
  for (let y = 0; y < out.h; y++) for (let x = 0; x < out.w; x++) {
    let r = 0, g = 0, b = 0, a = 0;
    for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
      const o = ((y * 2 + dy) * img.w + (x * 2 + dx)) * 4;
      const wa = img.px[o + 3] / 255;
      r += img.px[o] * wa; g += img.px[o + 1] * wa; b += img.px[o + 2] * wa; a += img.px[o + 3];
    }
    const sa = a / 4, o = (y * out.w + x) * 4;
    const norm = sa > 0 ? (a / 255) : 1;         // 用总权重归一
    out.px[o] = Math.round(r / norm); out.px[o + 1] = Math.round(g / norm);
    out.px[o + 2] = Math.round(b / norm); out.px[o + 3] = Math.round(sa);
  }
  return out;
}

// 最近邻缩放（放大用；像素硬边）
function nearest(img, nw, nh) {
  const out = RGBA(nw, nh);
  for (let y = 0; y < nh; y++) for (let x = 0; x < nw; x++) {
    const sx = Math.min(img.w - 1, Math.floor(x * img.w / nw));
    const sy = Math.min(img.h - 1, Math.floor(y * img.h / nh));
    const s = (sy * img.w + sx) * 4, o = (y * nw + x) * 4;
    out.px[o] = img.px[s]; out.px[o + 1] = img.px[s + 1];
    out.px[o + 2] = img.px[s + 2]; out.px[o + 3] = img.px[s + 3];
  }
  return out;
}

const sizes = [half(src), src, nearest(src, 48, 48)];   // 16 / 32 / 48

// 每个尺寸序列化成一个 ICO 图像块：BITMAPINFOHEADER + XOR（自底向上 BGRA）+ AND 掩码
function encodeImage(img) {
  const xorSize = img.w * img.h * 4;
  const andStride = Math.ceil(img.w / 32) * 4;
  const andSize = andStride * img.h;
  const buf = Buffer.alloc(40 + xorSize + andSize);
  buf.writeUInt32LE(40, 0);
  buf.writeInt32LE(img.w, 4);
  buf.writeInt32LE(img.h * 2, 8);              // 高度 = 2 倍（含掩码）
  buf.writeUInt16LE(1, 12);
  buf.writeUInt16LE(32, 14);
  buf.writeUInt32LE(0, 16);
  buf.writeUInt32LE(xorSize, 20);
  for (let y = 0; y < img.h; y++) {
    const sy = img.h - 1 - y;                  // 自底向上
    for (let x = 0; x < img.w; x++) {
      const s = (sy * img.w + x) * 4, d = 40 + (y * img.w + x) * 4;
      buf[d] = img.px[s + 2]; buf[d + 1] = img.px[s + 1];   // BGRA
      buf[d + 2] = img.px[s]; buf[d + 3] = img.px[s + 3];
    }
  }
  for (let y = 0; y < img.h; y++) {
    for (let x = 0; x < img.w; x++) {
      if (img.px[((img.h - 1 - y) * img.w + x) * 4 + 3] === 0) {
        buf[40 + xorSize + y * andStride + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return buf;
}

const images = sizes.map(encodeImage);

/* ---------------- 3. 构造 .rsrc 节 ---------------- */
// 标准三层资源树：根(按类型) -> 类型目录(按 ID) -> 语言目录 -> 数据条目。
// 三层都要对：多一层的话 Windows 会把下一层的目录头当成数据条目读，
// 于是 RVA 取到 0，LoadIconW/LoadImageW 直接失败（"关于"弹窗和窗口图标都靠它们）。
const ROOT_HDR = 16, DIR_ENT = 8, DATA_ENT = 16, LANG = 0x0409;
const N = images.length;
let cursor = 0;
const allocDir = (n) => { const at = cursor; cursor += ROOT_HDR + n * DIR_ENT; return at; };
const allocData = (n) => { const at = cursor; cursor += n * DATA_ENT; return at; };

const root = allocDir(2);                                   // L0：类型
const typeIcon = allocDir(N);                               // L1：RT_ICON 的 ID
const typeGroup = allocDir(1);                              // L1：RT_GROUP_ICON 的 ID
const iconLangDirs = [];                                    // L2：语言
for (let i = 0; i < N; i++) iconLangDirs.push(allocDir(1));
const groupLangDir = allocDir(1);
const iconData = allocData(N);
const groupData = allocData(1);
const imgOffsets = [];
for (const im of images) { imgOffsets.push(cursor); cursor += im.length; }
const offGroupImage = cursor;
const grpLen = 6 + 14 * N;
const rsrc = Buffer.alloc(offGroupImage + grpLen);
const w16 = (o, v) => rsrc.writeUInt16LE(v, o);
const w32 = (o, v) => rsrc.writeUInt32LE(v >>> 0, o);
const sub = (at) => (0x80000000 | at) >>> 0;                 // 条目指向下一层目录
/// 写一个目录的全部条目；isDir=false 时偏移直接指向数据条目
const writeEntries = (d, list) => {
  w16(d + 12, 0);                                            // 无名字条目
  w16(d + 14, list.length);
  list.forEach((it, i) => {
    const o = d + ROOT_HDR + i * DIR_ENT;
    w32(o, it.id);
    w32(o + 4, it.isDir ? sub(it.off) : it.off);
  });
};

writeEntries(root, [{ id: 3, off: typeIcon, isDir: true }, { id: 14, off: typeGroup, isDir: true }]);
writeEntries(typeIcon, iconLangDirs.map((d, i) => ({ id: i + 1, off: d, isDir: true })));
for (let i = 0; i < N; i++) {
  writeEntries(iconLangDirs[i], [{ id: LANG, off: iconData + i * DATA_ENT, isDir: false }]);
}
writeEntries(typeGroup, [{ id: 1, off: groupLangDir, isDir: true }]);
writeEntries(groupLangDir, [{ id: LANG, off: groupData, isDir: false }]);

// 数据条目：OffsetToData 的 RVA 稍后填，先写长度
for (let i = 0; i < N; i++) w32(iconData +  i * DATA_ENT + 4, images[i].length);
w32(groupData +  4, grpLen);
for (let i = 0; i < N; i++) images[i].copy(rsrc, imgOffsets[i]);

// GRPICONDIR：每个尺寸一条 14 字节条目
const grp = Buffer.alloc(grpLen);
grp.writeUInt16LE(0, 0);
grp.writeUInt16LE(1, 2);      // type = icon
grp.writeUInt16LE(N, 4);
sizes.forEach((im, i) => {
  const o = 6 + i * 14;
  grp[o] = im.w >= 256 ? 0 : im.w;
  grp[o + 1] = im.h >= 256 ? 0 : im.h;
  grp[o + 2] = 0;             // 调色板色数
  grp[o + 3] = 0;
  grp.writeUInt16LE(1, o + 4);          // planes
  grp.writeUInt16LE(32, o + 6);         // bitcount
  grp.writeUInt32LE(images[i].length, o + 8);
  grp.writeUInt16LE(i + 1, o + 12);     // 引用的 RT_ICON id
});
grp.copy(rsrc, offGroupImage);

/* ---------------- 4. 注入 PE ---------------- */
const b = Buffer.from(fs.readFileSync(inExe));
const peOff = b.readUInt32LE(0x3C);
const numSections = b.readUInt16LE(peOff + 6);
const optSize = b.readUInt16LE(peOff + 20);
const optOff = peOff + 24;
const fileAlign = b.readUInt32LE(optOff + 36);
const sectAlign = b.readUInt32LE(optOff + 32);
const sizeOfHeaders = b.readUInt32LE(optOff + 60);
const ddOff = optOff + 112;
const sectTable = optOff + optSize;

let lastEnd = 0, lastVirt = 0;
const sections = [];
for (let i = 0; i < numSections; i++) {
  const o = sectTable + i * 40;
  const s = {
    name: b.toString('ascii', o, o + 8).replace(/\0+$/, ''),
    virtSize: b.readUInt32LE(o + 8),
    virtAddr: b.readUInt32LE(o + 12),
    rawSize: b.readUInt32LE(o + 16),
    rawPtr: b.readUInt32LE(o + 20),
  };
  sections.push(s);
  lastEnd = Math.max(lastEnd, s.rawPtr + s.rawSize);
  lastVirt = Math.max(lastVirt, s.virtAddr + Math.max(s.virtSize, s.rawSize));
}
const align = (v, a) => Math.ceil(v / a) * a;
const newVirtAddr = align(lastVirt, sectAlign);
const newRawPtr = align(lastEnd, fileAlign);
const rawSize = align(rsrc.length, fileAlign);

// 数据条目里的 RVA
for (let i = 0; i < N; i++) {
  rsrc.writeUInt32LE(newVirtAddr + imgOffsets[i], iconData +  i * DATA_ENT + 0);
}
rsrc.writeUInt32LE(newVirtAddr + offGroupImage, groupData +  0);

// 新节头必须放得下
const newSectHeaderOff = sectTable + numSections * 40;
if (newSectHeaderOff + 40 > sizeOfHeaders) {
  console.error('节表空间不足，无法追加 .rsrc（需要把节表挪进新位置）');
  process.exit(3);
}

const out = Buffer.alloc(newRawPtr + rawSize);
b.copy(out, 0);
rsrc.copy(out, newRawPtr);
// 节头
const h = newSectHeaderOff;
out.write('.rsrc\0\0\0', h, 'ascii');
out.writeUInt32LE(rsrc.length, h + 8);
out.writeUInt32LE(newVirtAddr, h + 12);
out.writeUInt32LE(rawSize, h + 16);
out.writeUInt32LE(newRawPtr, h + 20);
out.writeUInt32LE(0, h + 24);            // 无重定位
out.writeUInt32LE(0, h + 28);            // 无行号
out.writeUInt16LE(0, h + 32);
out.writeUInt16LE(0, h + 34);
out.writeUInt32LE(0x40000040, h + 36);   // 已初始化数据 | 可读
// 更新 PE 头
out.writeUInt16LE(numSections + 1, peOff + 6);
out.writeUInt32LE(align(newVirtAddr + rsrc.length, sectAlign), optOff + 56);   // SizeOfImage
out.writeUInt32LE(0, optOff + 64);                                             // 校验和置 0（非驱动不校验）
out.writeUInt32LE(newVirtAddr, ddOff + 2 * 8 + 0);                             // 资源目录 RVA
out.writeUInt32LE(rsrc.length, ddOff + 2 * 8 + 4);                             // 资源目录大小

fs.writeFileSync(outExe, out);
console.log('-> ' + outExe + '  ' + out.length + ' 字节（.rsrc 图标 ' +
  sizes.map(s => s.w + '×' + s.h).join(' / ') + '，源 素材/图标.png ' + SW + '×' + SH + '）');
