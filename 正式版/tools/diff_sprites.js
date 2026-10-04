/* 逐像素比较两个「散图目录」（槽位名同名的一批 PNG），用来核对素材更新到底改了哪几张。
   用法:
     node tools/diff_sprites.js <旧目录> <新目录>             # 打印改了的槽位与像素数
     node tools/diff_sprites.js <旧目录> <新目录> --names-only # 只打印改了的槽位名（每行一个）
   退出码: 0 正常（有没有差异都算正常），2 目录缺失 */
const fs = require('fs');
const path = require('path');
const { readPNG, diffRGBA } = require('./png.js');

const args = process.argv.slice(2).filter(a => a !== '--names-only');
const namesOnly = process.argv.includes('--names-only');
const [oldDir, newDir] = args;
if (!oldDir || !newDir) {
  console.error('用法: node tools/diff_sprites.js <旧目录> <新目录> [--names-only]');
  process.exit(2);
}
for (const d of [oldDir, newDir]) {
  if (!fs.existsSync(d)) { console.error('目录不存在：' + d); process.exit(2); }
}

const newFiles = fs.readdirSync(newDir).filter(f => f.toLowerCase().endsWith('.png')).sort();
const changed = [], added = [], same = [];
for (const f of newFiles) {
  const a = path.join(oldDir, f), b = path.join(newDir, f);
  if (!fs.existsSync(a)) { added.push(f.replace(/\.png$/, '')); continue; }
  const ia = readPNG(a), ib = readPNG(b);
  if (ia.w !== ib.w || ia.h !== ib.h) { changed.push({ name: f.replace(/\.png$/, ''), note: `尺寸 ${ia.w}×${ia.h} → ${ib.w}×${ib.h}` }); continue; }
  const d = diffRGBA(ia.rgba, ib.rgba);
  if (d.n) changed.push({ name: f.replace(/\.png$/, ''), note: `${d.n} 像素（最大差 ${d.worst}）` });
  else same.push(f);
}
const oldOnly = fs.readdirSync(oldDir).filter(f => f.toLowerCase().endsWith('.png'))
  .filter(f => !newFiles.includes(f)).map(f => f.replace(/\.png$/, ''));

if (namesOnly) {
  for (const c of changed) console.log(c.name);
  for (const n of added) console.log(n);
  process.exit(0);
}

console.log(`没变的：${same.length} 张`);
console.log('变了的：' + (changed.length ? '' : '无'));
for (const c of changed) console.log(`  ${c.name.padEnd(12)} ${c.note}`);
if (added.length) console.log('新加的：' + added.join(' / '));
if (oldOnly.length) console.log('删掉的：' + oldOnly.join(' / '));
