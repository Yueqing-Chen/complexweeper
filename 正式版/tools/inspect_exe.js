/* 检查 PE 文件：子系统、导入的 DLL、是否含 CLR/浏览器运行时痕迹。
   用法: node tools/inspect_exe.js <exe> */
const fs = require('fs');

const file = process.argv[2];
if (!file) { console.error('用法: node tools/inspect_exe.js <exe>'); process.exit(2); }
const b = fs.readFileSync(file);

if (b.readUInt16LE(0) !== 0x5A4D) { console.error('不是 PE 文件（缺 MZ）'); process.exit(2); }
const peOff = b.readUInt32LE(0x3C);
if (b.readUInt32LE(peOff) !== 0x00004550) { console.error('不是 PE 文件（缺 PE\\0\\0）'); process.exit(2); }

const machine = b.readUInt16LE(peOff + 4);
const numSections = b.readUInt16LE(peOff + 6);
const optSize = b.readUInt16LE(peOff + 20);
const optOff = peOff + 24;
const magic = b.readUInt16LE(optOff);
const is64 = magic === 0x20B;
const subsystem = b.readUInt16LE(optOff + (is64 ? 68 : 68));

// 数据目录
const ddOff = optOff + (is64 ? 112 : 96);
const importRva = b.readUInt32LE(ddOff + 8);
const importSize = b.readUInt32LE(ddOff + 12);
const clrRva = b.readUInt32LE(ddOff + 14 * 8 + 0);

// 节表
const sections = [];
for (let i = 0; i < numSections; i++) {
  const o = optOff + optSize + i * 40;
  const name = b.toString('ascii', o, o + 8).replace(/\0+$/, '');
  sections.push({
    name,
    virtSize: b.readUInt32LE(o + 8),
    virtAddr: b.readUInt32LE(o + 12),
    rawSize: b.readUInt32LE(o + 16),
    rawPtr: b.readUInt32LE(o + 20),
  });
}
const rvaToOff = (rva) => {
  for (const s of sections) {
    if (rva >= s.virtAddr && rva < s.virtAddr + Math.max(s.virtSize, s.rawSize)) {
      return s.rawPtr + (rva - s.virtAddr);
    }
  }
  return -1;
};

const dlls = [];
if (importRva) {
  let off = importRva;
  for (;;) {
    const o = rvaToOff(off);
    if (o < 0) break;
    const nameRva = b.readUInt32LE(o + 12);
    const firstThunk = b.readUInt32LE(o + 16);
    if (!nameRva && !firstThunk) break;
    const no = rvaToOff(nameRva);
    if (no < 0) break;
    let end = no;
    while (b[end] !== 0) end++;
    dlls.push(b.toString('ascii', no, end));
    off += 20;
  }
}

const MACHINE = { 0x8664: 'x86_64', 0x14c: 'i386', 0xaa64: 'arm64' };
const SUBSYS = { 2: 'GUI (windows)', 3: 'console', 1: 'native' };
console.log(JSON.stringify({
  file,
  size: b.length,
  machine: MACHINE[machine] || ('0x' + machine.toString(16)),
  subsystem: SUBSYS[subsystem] || subsystem,
  hasCLR: clrRva !== 0,
  sections: sections.map(s => s.name),
  imports: dlls,
}, null, 1));
