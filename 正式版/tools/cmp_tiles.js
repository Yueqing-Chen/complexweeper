/* 把指定的槽位「新旧并排」画成一张图（旧在左、新在右，8× 最近邻、衬 #C0C0C0），
   用来看清这一轮素材到底改了什么。
   用法: node tools/cmp_tiles.js [槽位名...]        # 默认那六张带系数的根式
   默认比对目录: build\素材导出_旧\sprites 与 build\素材导出\sprites（可用环境变量覆盖） */
const fs = require('fs');
const path = require('path');
const { readPNG, writePNG } = require('./png.js');

const root = path.join(__dirname, '..');
const OLD = process.env.CMP_OLD || path.join(root, 'build', '素材导出_旧', 'sprites');
const NEW = process.env.CMP_NEW || path.join(root, 'build', '素材导出', 'sprites');
const OUT = process.env.CMP_OUT || path.join(root, 'build', '数字贴图对比.png');

const names = process.argv.slice(2).length ? process.argv.slice(2)
  : ['num_8', 'num_18', 'num_20', 'num_32', 'num_40', 'num_50'];

const Z = 8, GAP = 6, PAD = 6;
const cells = [];
for (const n of names) {
  const a = path.join(OLD, n + '.png'), b = path.join(NEW, n + '.png');
  if (!fs.existsSync(a) || !fs.existsSync(b)) { console.error('缺图，跳过: ' + n); continue; }
  cells.push({ n, a: readPNG(a), b: readPNG(b) });
}
if (!cells.length) { console.error('没有可比对的槽位'); process.exit(2); }

const cw = cells[0].a.w * Z, chh = cells[0].a.h * Z;
const W = PAD + cells.length * (cw * 2 + GAP + 2 * PAD) + PAD;
const H = chh + 2 * PAD;
const img = Buffer.alloc(W * H * 4);
for (let i = 0; i < W * H; i++) { img[i * 4] = img[i * 4 + 1] = img[i * 4 + 2] = 0xC0; img[i * 4 + 3] = 255; }
function put(im, ox, oy) {
  for (let y = 0; y < im.h * Z; y++) {
    for (let x = 0; x < im.w * Z; x++) {
      const s = (Math.floor(y / Z) * im.w + Math.floor(x / Z)) * 4;
      const d = ((oy + y) * W + ox + x) * 4;
      const a = im.rgba[s + 3] / 255;
      img[d] = Math.round(im.rgba[s] * a + 0xC0 * (1 - a));
      img[d + 1] = Math.round(im.rgba[s + 1] * a + 0xC0 * (1 - a));
      img[d + 2] = Math.round(im.rgba[s + 2] * a + 0xC0 * (1 - a));
      img[d + 3] = 255;
    }
  }
}
let x0 = PAD;
for (const c of cells) {
  put(c.a, x0, PAD); x0 += cw + PAD;
  put(c.b, x0, PAD); x0 += cw + PAD + GAP;
}
writePNG(OUT, W, H, img);
console.log(`写出 ${OUT}（${W}×${H}）：${cells.length} 组，每组左旧右新 — ${cells.map(c => c.n).join(' / ')}`);
