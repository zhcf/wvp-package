#Requires -Version 5.1
<#
.SYNOPSIS
  WVP-PRO 3.0.0 · Windows 离线版制作（在可联网的 Windows 机器上运行）
.DESCRIPTION
  Windows 方案只交付离线包：把四个组件（JRE21 / MySQL8 / Redis / ZLMediaKit）
  与本目录的入口脚本 / 配置模板 / 初始化 SQL 组装为完整离线安装包：

      windows\dist\wvp-windows-offline-<版本>.zip

  解压后在【无网络】的 Windows 机器上按三段式使用：
    install.bat  双击 → 组件就位 + 生成配置 + 初始化数据库（装完即退，不启服务）
    start.bat    双击 → 启动服务（含 JRE/MySQL/Redis/ZLM/WVP）
    stop.bat     双击 → 停止全部服务

  说明：
    · ZLMediaKit 获取顺序：-ZlmDir 参数 → runtime\zlm → 下载社区编译版
      （Gitee 免登录直链，约 4MB 单文件）并缓存到 cache\zlm\MediaServer.exe。
    · 组件缓存于本目录 cache\，重复运行不会重复下载；-SkipDownload 时仅用缓存。
.PARAMETER WvpJar
  wvp.jar 路径（可选）。缺省时依次尝试 runtime\wvp\wvp.jar 与离线缓存
  cache\wvp\wvp.jar；两处都没有则包内不含 jar。
  获取方式见 README.md §3.2：构建机 docker compose build wvp 后，提取容器内 /opt/wvp/wvp.jar
.PARAMETER ZlmDir
  ZLMediaKit Windows 运行目录（含 MediaServer.exe 与全部 dll）。
  未提供时自动下载社区编译版单文件（V2024.9.14，静态编译无 dll 依赖）
.PARAMETER OutDir
  产物输出目录（默认 windows\dist）
.PARAMETER Version
  版本号（默认 3.0.0，仅影响包名与包内说明）
.PARAMETER SkipDownload
  不联网下载：组件需已手动放入 cache\（jre21.zip / mysql.zip / redis.zip / zlm\MediaServer.exe）
.EXAMPLE
  .\pack.ps1 -WvpJar D:\wvp\wvp-pro-3.0.0.jar
.EXAMPLE
  .\pack.ps1 -SkipDownload
#>
[CmdletBinding()]
param(
    [string]$WvpJar = '',
    [string]$ZlmDir = '',
    [string]$OutDir = '',
    [string]$Version = '3.0.0',
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ========================= 基础路径 =========================
$Base  = $PSScriptRoot                          # windows\（方案与入口脚本所在目录）
$Repo  = Split-Path $Base -Parent               # 仓库根
$Cache = Join-Path $Base 'cache'                # 组件缓存
$Build = Join-Path $Base 'build'                # 打包暂存
if (-not $OutDir) { $OutDir = Join-Path $Base 'dist' }
$PkgName = "wvp-windows-offline-$Version"
$Stage   = Join-Path $Build $PkgName
$ZipPath = Join-Path $OutDir "$PkgName.zip"

# 组件获取源（与 windows\start.ps1 保持一致；网络受限可自行替换为镜像地址）
$JreUrl   = 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jre/hotspot/normal/eclipse'
$RedisUrl = 'https://github.com/tporadowski/redis/releases/download/v5.0.14.1/Redis-x64-5.0.14.1.zip'
$MysqlUrlCandidates = @(
    'https://cdn.mysql.com/Downloads/MySQL-8.0/mysql-8.0.46-winx64.zip',
    'https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.46-winx64.zip',
    'https://mirrors.aliyun.com/mysql/MySQL-8.0/mysql-8.0.28-winx64.zip'
)
$ZlmUrlCandidates = @(
    'https://gitee.com/beixiaocai/zlm/raw/master/V2024.9.14.windows/MediaServer.exe',
    'https://gitee.com/beixiaocai/zlm/raw/master/V2023.3.25.windows/MediaServer.exe',
    'https://gitee.com/beixiaocai/zlm/raw/master/V2022.5.22.windows/MediaServer.exe'
)

# ========================= 工具函数 =========================
function Write-Step { param([string]$Msg) Write-Host "[pack] $Msg" -ForegroundColor Cyan }
function Write-Warn { param([string]$Msg) Write-Host "[警告] $Msg" -ForegroundColor Yellow }
function Fail       { param([string]$Msg) Write-Host "[错误] $Msg" -ForegroundColor Red; exit 1 }

# 依次尝试多个下载源（失败自动切换下一个）；已存在则跳过
function Get-Component {
    param([string[]]$Urls, [string]$FileName, [string]$Desc)
    $dest = Join-Path $Cache $FileName
    if (Test-Path $dest) {
        Write-Step "已缓存 $FileName（$(('{0:N1}' -f ((Get-Item $dest).Length / 1MB))) MB），跳过下载"
        return $dest
    }
    if ($SkipDownload) {
        Fail "$FileName 缺失且指定了 -SkipDownload。请手动下载 $Desc 后保存为：`n  $dest"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    foreach ($u in $Urls) {
        try {
            Write-Step "下载 $Desc ...（文件较大，请耐心等待）"
            Write-Host "      $u" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $u -OutFile $dest -UseBasicParsing
            Write-Step "$FileName 下载完成（$(('{0:N1}' -f ((Get-Item $dest).Length / 1MB))) MB）"
            return $dest
        }
        catch {
            Write-Warn "下载失败（$($_.Exception.Message)），尝试下一个源 ..."
            if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
        }
    }
    Fail "全部下载源均失败：$FileName。请手动下载后保存为：`n  $dest"
}

# 目录树复制
function Copy-Tree {
    param([string]$Src, [string]$Dst)
    New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    Copy-Item -Path (Join-Path $Src '*') -Destination $Dst -Recurse -Force
}

# 生成双击 bat（纯 ASCII + CRLF）
function Write-Bat {
    param([string]$Path, [string]$Title, [string]$ScriptFile, [string[]]$ExtraArgs, [string]$DoneMsg)
    $argText = if ($ExtraArgs.Count -gt 0) { ' ' + ($ExtraArgs -join ' ') } else { '' }
    $lines = @(
        '@echo off',
        'cd /d "%~dp0"',
        'echo ================================================================',
        "echo  $Title",
        'echo ================================================================',
        'echo.',
        "powershell -NoProfile -ExecutionPolicy Bypass -File ""%~dp0$ScriptFile""$argText",
        'set RC=%ERRORLEVEL%',
        'echo.',
        "if not ""%RC%""==""0"" (echo [FAILED] exit code %RC% - see messages above) else (echo $DoneMsg)",
        'echo.',
        'pause'
    )
    [IO.File]::WriteAllText($Path, ($lines -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
}

# ========================= 0. 横幅 =========================
Write-Host ''
Write-Host '========== WVP-PRO Windows 离线包制作 ==========' -ForegroundColor Green
Write-Step "仓库根：$Repo"

# ========================= 1. 来源文件检查 =========================
$required = @(
    'start.ps1',
    'stop.ps1',
    'install.ps1',
    'README.md',
    'config\application.yml.template',
    'config\zlm-config.ini.template',
    'mysql\init\wvp-init-3.0.0.sql'
)
foreach ($r in $required) {
    if (-not (Test-Path (Join-Path $Base $r))) { Fail "缺少 windows\ 文件：$r（请确认仓库目录完整）" }
}
Write-Step '来源文件检查通过'

# ========================= 2. 组件准备（缓存/下载） =========================
Write-Step '准备离线组件（JRE21 / MySQL8 / Redis / ZLMediaKit）...'
$jreZip   = Get-Component @($JreUrl) 'jre21.zip' 'Temurin JRE 21 Windows x64（约 45MB）'
$mysqlZip = Get-Component $MysqlUrlCandidates 'mysql.zip' 'MySQL 8 winx64 zip（约 200MB）'
$redisZip = Get-Component @($RedisUrl) 'redis.zip' 'Redis for Windows 5.0.14.1（约 12MB）'

# ZLM：优先 -ZlmDir 参数，其次本目录 runtime\zlm，最后自动下载社区编译版单文件
$zlmDirSource = $null
if ($ZlmDir) {
    if (-not (Test-Path (Join-Path $ZlmDir 'MediaServer.exe'))) { Fail "指定的 ZLM 目录中未找到 MediaServer.exe：$ZlmDir" }
    $zlmDirSource = $ZlmDir
}
elseif (Test-Path (Join-Path $Base 'runtime\zlm\MediaServer.exe')) {
    $zlmDirSource = Join-Path $Base 'runtime\zlm'
}
$zlmExe = $null
if (-not $zlmDirSource) {
    $zlmExe = Get-Component $ZlmUrlCandidates 'zlm\MediaServer.exe' 'ZLMediaKit 社区编译版（Gitee 免登录直链，约 4MB 单文件）'
}

# ========================= 3. wvp.jar（可选，尽力打包） =========================
# 来源优先级：-WvpJar 参数 → runtime\wvp\wvp.jar → cache\wvp\wvp.jar
$jarSource = $null
if ($WvpJar) {
    if (-not (Test-Path $WvpJar)) { Fail "指定的 jar 不存在：$WvpJar" }
    $jarSource = $WvpJar
}
elseif (Test-Path (Join-Path $Base 'runtime\wvp\wvp.jar')) {
    $jarSource = Join-Path $Base 'runtime\wvp\wvp.jar'
}
elseif (Test-Path (Join-Path $Cache 'wvp\wvp.jar')) {
    $jarSource = Join-Path $Cache 'wvp\wvp.jar'
}
# 来源非缓存时自动同步一份到 cache\wvp\，后续打包直接复用
if ($jarSource) {
    $jarCache = Join-Path $Cache 'wvp\wvp.jar'
    if ([IO.Path]::GetFullPath($jarSource) -ne [IO.Path]::GetFullPath($jarCache)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $jarCache -Parent) | Out-Null
        Copy-Item $jarSource $jarCache -Force
        Write-Step 'wvp.jar 已缓存到 cache\wvp\（后续打包自动复用）'
    }
}
if (-not $jarSource) {
    Write-Warn '未提供 wvp.jar（-WvpJar）：包内将不含 runtime\wvp\wvp.jar，离线机器首次启动前需按包内说明放入'
    Write-Warn '  获取途径：在联网构建机 docker compose build wvp 后提取容器内 /opt/wvp/wvp.jar（见 README.md §3.2），'
    Write-Warn '  放入 cache\wvp\wvp.jar 后重新运行本脚本即自动打包'
}

# ========================= 4. 组装包目录 =========================
Write-Step "组装目录：$Stage"
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'runtime\_download') | Out-Null

# 4.1 三入口脚本（install / start / stop）+ 方案文件
foreach ($f in @('install.ps1', 'start.ps1', 'stop.ps1')) {
    Copy-Item (Join-Path $Base $f) $Stage
}
Copy-Item (Join-Path $Base 'README.md') $Stage
Copy-Tree (Join-Path $Base 'config') $Stage\config
Copy-Tree (Join-Path $Base 'mysql')  $Stage\mysql

# 4.2 组件 zip → runtime\_download\（start.ps1 -SkipDownload 直接使用）
Copy-Item $jreZip   $Stage\runtime\_download
Copy-Item $mysqlZip $Stage\runtime\_download
Copy-Item $redisZip $Stage\runtime\_download
Write-Step '组件 zip 已放入 runtime\_download\'

# 4.3 ZLM 与 jar
if ($zlmDirSource) {
    Copy-Tree $zlmDirSource $Stage\runtime\zlm
    Write-Step "已打包 ZLMediaKit（完整目录）：$zlmDirSource"
}
else {
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'runtime\zlm') | Out-Null
    Copy-Item $zlmExe (Join-Path $Stage 'runtime\zlm\MediaServer.exe')
    Write-Step '已打包 ZLMediaKit（社区编译版单文件 MediaServer.exe）'
}
if ($jarSource) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'runtime\wvp') | Out-Null
    Copy-Item $jarSource (Join-Path $Stage 'runtime\wvp\wvp.jar')
    Write-Step "已打包 wvp.jar：$jarSource"
}

# 4.4 三个双击 bat（纯 ASCII + CRLF）
Write-Bat (Join-Path $Stage 'install.bat') "WVP-PRO $Version Windows Offline Install (1/3)" 'install.ps1' @() 'Install done. Now run start.bat to launch, then open http://THIS-PC-IP:18080  admin/admin'
Write-Bat (Join-Path $Stage 'start.bat')   "WVP-PRO $Version Windows Start Service  (2/3)" 'start.ps1' @('-SkipDownload') 'WVP-PRO is running. Open http://THIS-PC-IP:18080  admin/admin'
Write-Bat (Join-Path $Stage 'stop.bat')    "WVP-PRO $Version Windows Stop Service   (3/3)" 'stop.ps1' @() 'WVP-PRO stopped.'
Write-Step 'install.bat / start.bat / stop.bat 已生成'

# 4.5 离线安装说明.txt（UTF-8 with BOM，记事本直接可读）
$jarNote = if ($jarSource) { '已内置（runtime\wvp\wvp.jar）' } else { '【缺失】需手动放入 runtime\wvp\wvp.jar 后再启动' }
$readmeTxt = @"
WVP-PRO $Version · Windows 离线包（绿色版：解压即用，全程无需联网）
====================================================================
一、运行（两种方式任选）
  1. 将本文件夹解压到任意路径（建议不含中文/空格的路径，如 D:\wvp）
  2. 一键运行（推荐）：双击 start.bat
     自动完成：组件解压就位 → 生成配置 → 初始化数据库 → 启动服务（首次约 2~4 分钟）
     浏览器访问 http://<本机IP>:18080，默认账号 admin / admin
     或分步运行：先双击 install.bat（仅完成安装后退出，约 1~3 分钟，可先确认无误），再双击 start.bat
  · 绿色版说明：不写注册表、不注册系统服务；组件/数据/日志全部在包内 runtime\ 下，删除整个文件夹即完全卸载
  · wvp.jar 状态：$jarNote

二、启动 / 停止
  · 启动：双击 start.bat（或 powershell -ExecutionPolicy Bypass -File .\start.ps1）
  · 停止：双击 stop.bat （或 powershell -ExecutionPolicy Bypass -File .\stop.ps1）
  · 多网卡机器请指定对外 IP：.\start.ps1 -StreamIp <本机IP>

三、本包内容
  · install.ps1 / start.ps1 / stop.ps1   三个入口脚本（三个 bat 为其双击包装）
  · runtime\_download\  已内置 JRE21 / MySQL8 / Redis 离线压缩包（安装时免下载解压）
  · runtime\zlm\        ZLMediaKit（社区编译版 V2024.9.14 单文件 MediaServer.exe）
  · runtime\wvp\        WVP-PRO jar
  · 包内 README.md 为完整使用说明（安装 / 参数 / 端口 / 常见问题）

四、常见问题
  · 端口 3306/6379/18080/9092 被占用会导致启动失败（报错信息会指明端口）
  · 双击 bat 已内置 -ExecutionPolicy Bypass，无需手工改 PowerShell 策略
  · ZLM 为社区编译版单文件；如需完整目录（含 dll/静态资源）可自行编译后替换 runtime\zlm\
  · 详细文档：包内 README.md（含参数、端口、FAQ）
====================================================================
"@
[IO.File]::WriteAllText((Join-Path $Stage '离线安装说明.txt'), $readmeTxt, [Text.UTF8Encoding]::new($true))
Write-Step '离线安装说明.txt 已生成'

# ========================= 5. 压缩 =========================
Write-Step '压缩为 zip ...'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
    $Stage, $ZipPath, [IO.Compression.CompressionLevel]::Optimal, $true)

# ========================= 6. 摘要 =========================
$zipSize = '{0:N1}' -f ((Get-Item $ZipPath).Length / 1MB)
Write-Host ''
Write-Host '================= 离线包制作完成 =================' -ForegroundColor Green
Write-Host "  产物   :  $ZipPath（$zipSize MB）"
Write-Host "  内容   :  JRE21 + MySQL8 + Redis + ZLMediaKit$(if ($jarSource) { ' + wvp.jar' } else { '（无 wvp.jar）' })"
if (-not $jarSource) {
    Write-Host '  注意   :  包内缺少 wvp.jar（见上方警告）；补齐后重新运行本脚本可生成完整包'
}
Write-Host '  使用   :  拷贝到离线 Windows 机器 → 解压 → start.bat（一键安装+启动，绿色版）'
Write-Host '==================================================' -ForegroundColor Green