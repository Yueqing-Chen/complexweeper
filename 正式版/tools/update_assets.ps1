# 复扫雷 · 素材更新流水线
#   改完 D:\游戏\大肥鱼扫雷\素材\ 里的 PNG 之后跑这一条就行：
#     1) 素材指纹比对：61 个 PNG 的 SHA-256 和上次跑完时一致 → 直接跳过（-Force 可强制跑完）
#     2) 存档上一版导出（build\素材导出 → build\素材导出_旧）
#     3) 版本号 +1（src\main.zig 的 APP_VERSION，README 里那行也一起改；-NoBump 可跳过）
#     4) 重建（build.ps1：重打图集 → 编译 → 注入图标 → 规则自检 + 界面自检）
#     5) 重新导出（tools\dump_atlas.js）并验收（tools\check_export.js：逐张对图集 + 抽查对素材原件）
#     6) 与上一版逐像素比对（tools\diff_sprites.js），把变了的槽位画成对比图（tools\cmp_tiles.js）
#     7) 重画素材对照表，并按 -Flakes N 跑 N 次界面自检查抖动
#
# 用法: powershell -ExecutionPolicy Bypass -File tools\update_assets.ps1 [-NoBump] [-Force] [-Flakes 15] [-SkipTests]
#   注意: 本文件必须保持 UTF-8 BOM —— PowerShell 5.1 读无 BOM 文件会按 ANSI 解析，中文全变乱码。
param(
    [switch]$NoBump,
    [switch]$Force,
    [int]$Flakes = 15,
    [switch]$SkipTests
)
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$root = Split-Path -Parent $tools          # 正式版/
Set-Location $root
$assetsDir = Join-Path (Split-Path -Parent $root) '素材'
$exp = Join-Path $root 'build\素材导出'
$expOld = Join-Path $root 'build\素材导出_旧'
$fpFile = Join-Path $root 'build\素材指纹.txt'
$mainZig = Join-Path $root 'src\main.zig'
$readme = Join-Path $root 'README.md'

function Step([string]$t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Run([string]$what, [scriptblock]$body) {
    & $body
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "$what 失败（退出码 $LASTEXITCODE）" }
}

$cmpMade = $false   # 这一轮有没有画出对比图

# ---- 0) 素材指纹 ----
# 素材只有 图集.png + 图集.json 这一对（散图已作废，不再参与构建，也不算进指纹）
Step '0 素材指纹'
$srcs = @()
foreach ($n in '图集.png', '图集.json') {
    $f = Join-Path $assetsDir $n
    if (-not (Test-Path $f)) { throw "素材缺失：$f" }
    $srcs += Get-Item $f
}
$now = @{}
foreach ($f in $srcs) { $now[$f.Name] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash }
$nowText = (($now.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n")
$oldText = if (Test-Path $fpFile) { [System.IO.File]::ReadAllText($fpFile) } else { '' }
$changedFiles = @()
if ($oldText) {
    $old = @{}
    foreach ($line in ($oldText -split "`n")) {
        if ($line -match '^(.+?)=([0-9A-Fa-f]{64})$') { $old[$Matches[1]] = $Matches[2] }
    }
    foreach ($k in $now.Keys) { if (-not $old.ContainsKey($k)) { $changedFiles += "$k（新增）" } elseif ($old[$k] -ne $now[$k]) { $changedFiles += $k } }
    foreach ($k in $old.Keys) { if (-not $now.ContainsKey($k)) { $changedFiles += "$k（删除）" } }
}
Write-Host "素材：图集.png + 图集.json"
if (-not $oldText) { Write-Host '第一次跑（还没有指纹基线），按"全变了"处理' }
if ($changedFiles.Count) { Write-Host ("这一轮变了：" + ($changedFiles -join ' / ')) }
elseif ($oldText) { Write-Host '和上次跑完时一模一样' }
if ($oldText -and -not $changedFiles.Count -and -not $Force) {
    Write-Host "`n素材没变，跳过重建。真要重跑一遍加 -Force。" -ForegroundColor Yellow
    exit 0
}

# ---- 1) 版本号 +1 ----
Step '1 版本号'
$zigText = [System.IO.File]::ReadAllText($mainZig)
if (-not ($zigText -match 'const APP_VERSION = "(\d+)\.(\d+)\.(\d+)";')) { throw 'src\main.zig 里找不到 APP_VERSION' }
$major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]
$verOld = "$major.$minor.$patch"
$verNew = "$major.$minor.$($patch + 1)"
if ($NoBump) {
    Write-Host "-NoBump：版本号保持 $verOld"
    $verNew = $verOld
} else {
    $zigText = $zigText.Replace("const APP_VERSION = ""$verOld"";", "const APP_VERSION = ""$verNew"";")
    [System.IO.File]::WriteAllText($mainZig, $zigText)
    if (Test-Path $readme) {
        $rd = [System.IO.File]::ReadAllText($readme)
        $rd = $rd.Replace("> **版本号纪律**：当前 **$verOld**", "> **版本号纪律**：当前 **$verNew**")
        [System.IO.File]::WriteAllText($readme, $rd)
    }
    Write-Host "版本号 $verOld → $verNew（main.zig 的 APP_VERSION + README 那行）"
}

# ---- 2) 存档上一版导出 ----
Step '2 存档上一版导出'
if (Test-Path $exp) {
    if (Test-Path $expOld) { Remove-Item -Recurse -Force $expOld }
    Copy-Item -Recurse $exp $expOld
    $n = (Get-ChildItem (Join-Path $expOld 'sprites') -Filter *.png -ErrorAction SilentlyContinue).Count
    Write-Host "build\素材导出 → build\素材导出_旧（$n 张）"
} else {
    Write-Host '还没有导出过，跳过存档（这一轮没有"旧版"可比）'
}

# ---- 3) 重建 ----
Step '3 重建（build.ps1）'
try {
    if ($SkipTests) { & (Join-Path $root 'build.ps1') -NoTest } else { & (Join-Path $root 'build.ps1') }
} catch {
    Write-Host "`n构建失败：$_" -ForegroundColor Red
    exit 1
}

# ---- 4) 重新导出 + 验收 ----
Step '4 重新导出并验收'
if (Test-Path $exp) { Remove-Item -Recurse -Force $exp }
Run '导出' { node (Join-Path $tools 'dump_atlas.js') 'src\atlas.bin' 'build\素材导出' 4 | Select-Object -Last 2 }
Run '验收' { node (Join-Path $tools 'check_export.js') }

# ---- 5) 与上一版逐像素比对 ----
Step '5 与上一版比对'
if (Test-Path (Join-Path $expOld 'sprites')) {
    node (Join-Path $tools 'diff_sprites.js') (Join-Path $expOld 'sprites') (Join-Path $exp 'sprites')
    $names = @(node (Join-Path $tools 'diff_sprites.js') (Join-Path $expOld 'sprites') (Join-Path $exp 'sprites') --names-only |
        Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    if ($names.Count) {
        node (Join-Path $tools 'cmp_tiles.js') @names
        $cmpMade = $true
    } else {
        Write-Host '这一轮没有任何槽位变化（图集字节应当完全相同）'
        $stale = Join-Path $root 'build\数字贴图对比.png'
        if (Test-Path $stale) { Remove-Item $stale -Force; Write-Host '上一轮留下的对比图已删掉（它不是这一轮的）' }
    }
} else {
    Write-Host '没有旧导出，跳过比对'
}

# ---- 6) 素材对照表 ----
Step '6 重画素材对照表'
Run '对照表' { & (Join-Path $root '复扫雷.exe') --shot 'build\sheet.bmp' --sheet --quiet }
Run '转 PNG' { node (Join-Path $tools 'bmp2png.js') 'build\sheet.bmp' 'build\sheet.png' }
Copy-Item (Join-Path $root 'build\sheet.png') (Join-Path $exp '对照表.png') -Force
Write-Host 'build\素材导出\对照表.png 已刷新'

# ---- 7) 抖动检查 ----
$flakeBad = 0
if ($Flakes -gt 0) {
    Step "7 界面自检抖动（连跑 $Flakes 次）"
    for ($i = 1; $i -le $Flakes; $i++) {
        & (Join-Path $root '复扫雷.exe') --uitest 'build\uitest.txt' | Out-Null
        $code = $LASTEXITCODE
        $txt = [System.IO.File]::ReadAllText((Join-Path $root 'build\uitest.txt'))
        $ok = ($code -eq 0) -and ($txt -match '失败 0 项') -and ($txt -notmatch '\[失败\]') -and ($txt -match [regex]::Escape($verNew))
        if (-not $ok) { $flakeBad++; Write-Host "  第 $i 次失败" -ForegroundColor Red }
    }
    if ($flakeBad) { Write-Host "$Flakes 次里有 $flakeBad 次失败" -ForegroundColor Red } else { Write-Host "$Flakes 次全部通过" }
}

# ---- 收尾：记下指纹，打印摘要 ----
[System.IO.File]::WriteAllText($fpFile, $nowText)
$exe = Join-Path $root '复扫雷.exe'
$size = [math]::Round((Get-Item $exe).Length / 1KB)
Step '完成'
Write-Host "版本 $verNew · 产物 复扫雷 $verNew.exe（$size KB；另有一份稳定副本 复扫雷.exe）"
Write-Host "这一轮变了的槽位：$(if ($changedFiles.Count) { $changedFiles -join ' / ' } else { '（无）' })"
Write-Host '产出：'
Write-Host '  build\素材导出\atlas.png + atlas.json（整图与槽位表，都是原生尺寸）'
Write-Host '  build\素材导出\sprites\（逐张 61 个 PNG）+ sprites.txt（名字清单）'
Write-Host '  build\素材导出\对照表.png（程序画的分组对照表）'
if ($cmpMade) { Write-Host '  build\数字贴图对比.png（变了的那几张，左旧右新）' }
if ($flakeBad) { exit 1 }
