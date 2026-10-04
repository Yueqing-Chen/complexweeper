# 复数扫雷 正式版 · 构建脚本
#   1) 用 Node 把 素材/ 打包成图集（src/atlas.bin + src/assets.zig）
#   2) 用 Zig 交叉编译出原生 Windows exe（无第三方库、无 libc、无运行时依赖）
#   3) 注入图标资源，输出单个 exe
#   4) 跑规则自检与界面自检
#
# 用法： powershell -ExecutionPolicy Bypass -File build.ps1 [-NoTest]
param(
    [switch]$NoTest
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

function Find-Zig {
    $c = Get-Command zig -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($v in @('0.14.1', '0.15.1', '0.16.0')) {
        $p = Join-Path $env:LOCALAPPDATA "zig-$v\zig.exe"
        if (Test-Path $p) { return $p }
    }
    $found = Get-ChildItem -Path $env:LOCALAPPDATA -Filter zig.exe -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "找不到 zig.exe。下载 https://ziglang.org/download/ 的 windows-x86_64 包，解压到 %LOCALAPPDATA%\zig-0.14.1\ 即可。"
}

$zig = Find-Zig
Write-Host "zig = $zig"
& $zig version

# exe 被正在运行的实例锁住时，注入图标会以 EBUSY 失败（Node 抛错但脚本曾经照样报"完成"）。
# 所以这里先独占试开一次，锁着就直接说人话。
function Test-Locked([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $fs.Close()
        return $false
    } catch {
        return $true
    }
}

New-Item -ItemType Directory -Force -Path (Join-Path $root 'build') | Out-Null

Write-Host "`n[1/4] 生成图集…"
node (Join-Path $root 'tools\gen_atlas.js')
if ($LASTEXITCODE -ne 0) { throw "生成图集失败" }

Write-Host "`n[2/4] 编译…"
$out = Join-Path $root 'build\cs.exe'
& $zig build-exe (Join-Path $root 'src\main.zig') `
    -target x86_64-windows-gnu -O ReleaseSmall `
    "-femit-bin=$out" --subsystem windows
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

Write-Host "`n[3/4] 注入图标并输出单个 exe…"
$final = Join-Path $root '复扫雷.exe'
# 产物名带版本号：复扫雷 <版本>.exe 是交付/存档用的那一份；复扫雷.exe 是同一份构建的稳定副本
# （自检、工具脚本、快捷方式都读稳定名，两个文件每次构建一起重写，不会各自漂移）。
$verMatch = [regex]::Match((Get-Content (Join-Path $root 'src\main.zig') -Encoding UTF8 -Raw), 'const APP_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)";')
if (-not $verMatch.Success) { throw '读不到 src\main.zig 里的 APP_VERSION' }
$version = $verMatch.Groups[1].Value
$versioned = Join-Path $root "复扫雷 $version.exe"
if ((Test-Locked $final) -or (Test-Locked $versioned)) {
    # 按"进程名里带扫雷"来找，别写死包名：改过名的副本（早期的 复数扫雷.exe 之类）也能报出来
    $who = (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*扫雷*' } |
            Select-Object -ExpandProperty Id) -join ', '
    throw "「复扫雷.exe」正被占用（还在运行的实例 pid: $who），先关掉再构建"
}
node (Join-Path $root 'tools\set_icon.js') $out $final
if ($LASTEXITCODE -ne 0) { throw "注入图标失败" }
node (Join-Path $root 'tools\inspect_exe.js') $final
if ($LASTEXITCODE -ne 0) { throw "PE 检查失败" }
Copy-Item $final $versioned -Force

if (-not $NoTest) {
    Write-Host "`n[4/4] 自检…"
    $rep = Join-Path $root 'build\selftest.txt'
    $p = Start-Process -FilePath $final -ArgumentList '--selftest', $rep -Wait -PassThru -NoNewWindow
    Get-Content $rep -Encoding UTF8
    if ($p.ExitCode -ne 0) { throw "规则自检失败" }

    $rep2 = Join-Path $root 'build\uitest.txt'
    $p2 = Start-Process -FilePath $final -ArgumentList '--uitest', $rep2 -Wait -PassThru -NoNewWindow
    Get-Content $rep2 -Encoding UTF8
    if ($p2.ExitCode -ne 0) { throw "界面自检失败" }
}

$size = (Get-Item $final).Length
$hashA = (Get-FileHash $final -Algorithm SHA256).Hash
$hashB = (Get-FileHash $versioned -Algorithm SHA256).Hash
if ($hashA -ne $hashB) { throw "两个产物不一致（复扫雷.exe 与 复扫雷 $version.exe）" }
Write-Host ("`n完成：{0}  （{1:N0} 字节，{2:N0} KB）" -f $versioned, $size, ($size / 1KB))
Write-Host ("      同一份构建的稳定副本：复扫雷.exe（SHA-256 一致 {0}…）" -f $hashA.Substring(0, 16))
