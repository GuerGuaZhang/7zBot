# ============================================================
#  7zBot 智能批量压缩工具
#  用法: 把文件/文件夹放到 input 目录，双击运行
# ============================================================

# 切换到脚本所在目录
Set-Location $PSScriptRoot

# --- 查找 7z.exe ---
$sz = $null
$paths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    "$env:LOCALAPPDATA\7-Zip\7z.exe"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        $sz = $p
        break
    }
}

if (-not $sz) {
    Write-Host "[错误] 未找到 7-Zip，请先安装: https://www.7-zip.org/" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

# --- 检查目录 ---
if (-not (Test-Path "input")) {
    Write-Host "[错误] 请在脚本同目录创建 input 文件夹并放入文件" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

if (-not (Test-Path "output")) {
    New-Item -ItemType Directory -Path "output" | Out-Null
}

# --- 清理临时目录 ---
$tempBot = "$env:TEMP\7zbot"
if (Test-Path $tempBot) {
    Remove-Item -Path $tempBot -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 统计文件数量 ---
$files = Get-ChildItem -Path "input" -File
$dirs = Get-ChildItem -Path "input" -Directory
$nF = $files.Count
$nD = $dirs.Count
$nT = $nF + $nD

if ($nT -eq 0) {
    Write-Host "[错误] input 文件夹为空" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

Write-Host "============================================"
Write-Host "  7zBot 智能批量压缩工具"
Write-Host "  来源: $PSScriptRoot\input"
Write-Host "  输出: $PSScriptRoot\output"
Write-Host "  文件: $nF   文件夹: $nD"
Write-Host "============================================"
Write-Host ""

# ===== 内存自适应参数 =====
Write-Host ""
Write-Host "========================================"
Write-Host "  内存自适应压缩"
Write-Host "========================================"

# 检测可用内存
$os = Get-CimInstance Win32_OperatingSystem
$FreeMemKB = [Math]::Round($os.FreePhysicalMemory)
$FreeMemMB = [Math]::Round($FreeMemKB / 1024)
$FreeMemGB = [Math]::Round($FreeMemMB / 1024, 1)

Write-Host "可用内存: $FreeMemMB MB ($FreeMemGB GB)"

# 根据可用内存选择压缩参数
# 公式: 预估内存 = 字典大小(MB) x 10.5 x 线程数
if ($FreeMemMB -ge 16384) {
    # 16GB+: 256MB字典, 8线程, ~23.5GB内存
    $Z_DICT = "256m"; $Z_FB = 273; $Z_MMT = 8
    $Z_LEVEL = "极致"; $Z_MEM_EST = "23.5GB"
}
elseif ($FreeMemMB -ge 8192) {
    # 8GB+: 128MB字典, 8线程, ~11.8GB内存
    $Z_DICT = "128m"; $Z_FB = 273; $Z_MMT = 8
    $Z_LEVEL = "极限"; $Z_MEM_EST = "11.8GB"
}
elseif ($FreeMemMB -ge 4096) {
    # 4GB+: 64MB字典, 4线程, ~2.9GB内存
    $Z_DICT = "64m"; $Z_FB = 128; $Z_MMT = 4
    $Z_LEVEL = "最高"; $Z_MEM_EST = "2.9GB"
}
elseif ($FreeMemMB -ge 2048) {
    # 2GB+: 32MB字典, 4线程, ~1.5GB内存
    $Z_DICT = "32m"; $Z_FB = 64; $Z_MMT = 4
    $Z_LEVEL = "标准"; $Z_MEM_EST = "1.5GB"
}
elseif ($FreeMemMB -ge 1024) {
    # 1GB+: 16MB字典, 2线程, ~370MB内存
    $Z_DICT = "16m"; $Z_FB = 32; $Z_MMT = 2
    $Z_LEVEL = "快速"; $Z_MEM_EST = "370MB"
}
else {
    # < 1GB: 8MB字典, 1线程, ~92MB内存
    $Z_DICT = "8m"; $Z_FB = 16; $Z_MMT = 1
    $Z_LEVEL = "最快"; $Z_MEM_EST = "92MB"
}

Write-Host ""
Write-Host "已选压缩参数:"
Write-Host "  级别:     $Z_LEVEL"
Write-Host "  字典:     $Z_DICT"
Write-Host "  快速字节: $Z_FB"
Write-Host "  线程:     $Z_MMT"
Write-Host "  预估内存: $Z_MEM_EST"
Write-Host "========================================"
Write-Host ""

# 设置压缩选项
$zopts = @("-t7z", "-m0=lzma2", "-mx=9", "-mfb=$Z_FB", "-md=$Z_DICT", "-ms=on", "-mmt=$Z_MMT")

$OK = 0
$NG = 0

# --- 处理文件: 解压后重新打包 ---
foreach ($f in $files) {
    $bn = $f.BaseName
    Write-Host "文件: $($f.Name)"

    $td = "$tempBot\${bn}_$(Get-Random)"
    New-Item -ItemType Directory -Path $td -Force | Out-Null

    Write-Host "  解压中..."
    & $sz x $f.FullName "-o$td" -y -bsp1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [失败] 解压出错" -ForegroundColor Red
        Remove-Item -Path $td -Recurse -Force -ErrorAction SilentlyContinue
        $NG++
        continue
    }

    Write-Host "  压缩中..."
    & $sz a $zopts "output\$bn.7z" "$td\*" -bsp1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [失败] 压缩出错" -ForegroundColor Red
        Remove-Item -Path $td -Recurse -Force -ErrorAction SilentlyContinue
        $NG++
        continue
    }

    Remove-Item -Path $td -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [成功] output\$bn.7z" -ForegroundColor Green
    $OK++
}

# --- 处理文件夹: 直接打包 ---
foreach ($d in $dirs) {
    $bn = $d.Name
    Write-Host "文件夹: $bn"

    Write-Host "  压缩中..."
    Push-Location "input"
    & $sz a $zopts "..\output\$bn.7z" $bn -bsp1
    Pop-Location

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [失败] 压缩出错" -ForegroundColor Red
        $NG++
        continue
    }

    Write-Host "  [成功] output\$bn.7z" -ForegroundColor Green
    $OK++
}

Write-Host ""
Write-Host "============================================"
Write-Host "  完成 | 成功: $OK | 失败: $NG"
Write-Host "  输出目录: $PSScriptRoot\output"
Write-Host "============================================"
Read-Host "按回车键退出"