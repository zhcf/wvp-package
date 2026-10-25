#Requires -Version 5.1
<#
.SYNOPSIS
  WVP-PRO 3.0.0 · Windows 原生一键启动（不依赖 Docker）
.DESCRIPTION
  在 Windows 上以原生进程方式运行 WVP-PRO 全套：
  JRE21（自动检测系统 Java，缺失则下载） + MySQL8（便携版） + Redis（Windows版） + ZLMediaKit + WVP-PRO jar。
  首次运行自动下载组件、初始化数据库并导入 3.0.0 表结构；幂等设计，可重复运行。
  组件/数据/日志统一位于本脚本目录下 runtime\ 内（不修改系统注册表、不开机自启）。
.PARAMETER StreamIp
  Stream_IP / SDP_IP / SIP_ShowIP 使用的本机 IP（默认自动探测；多网卡请显式指定）
.PARAMETER WvpJar
  已有 wvp-pro jar 的路径（首次使用时复制到 runtime\wvp\wvp.jar；之后无需再传）
.PARAMETER SkipDownload
  纯离线模式：不下载任何组件，全部组件需已就位于 runtime\
.PARAMETER InstallOnly
  仅安装不启动：完成组件准备、配置生成与数据库初始化（含停止临时启动的 MySQL）后退出，不启动服务
.PARAMETER SipPassword
  设备注册密码（默认 12345678，生产建议修改；仅首次初始化时写入数据库）
.PARAMETER MysqlRootPassword / MysqlPassword / RedisPassword
  数据库与 Redis 密码（默认内置值，生产建议修改；仅首次初始化时写入）
.PARAMETER ZlmSecret
  ZLM API 密钥（默认内置值，生产建议修改；同步写入 WVP 与 ZLM 配置）
.PARAMETER Force
  检测到组件已在运行时：先停止再重新启动（等价于先执行 stop.ps1）
.EXAMPLE
  .\start.ps1
.EXAMPLE
  .\start.ps1 -WvpJar D:\download\wvp-pro-3.0.0.jar
.EXAMPLE
  .\start.ps1 -StreamIp 192.168.1.105 -SipPassword MySipPwd
.EXAMPLE
  .\start.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$StreamIp          = '',
    [string]$WvpJar            = '',
    [string]$SipPassword       = '12345678',
    [string]$MysqlRootPassword = 'wvp_root_123456',
    [string]$MysqlPassword     = 'wvp_123456',
    [string]$RedisPassword     = 'wvp_redis_123456',
    [string]$ZlmSecret         = 'wvppro-zlm-3.0.0-9f3a7c2e5b1d4068a1c9',
    [switch]$SkipDownload,
    [switch]$InstallOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # IWR 进度条严重拖慢下载速度

# ========================= 可调配置 =========================
# 端口（如需修改，请同步修改 stop.ps1 顶部的对应端口）
$WvpPort     = 18080
$SipPort     = 5060
$MysqlPort   = 3306
$RedisPort   = 6379
$ZlmHttpPort = 9092
$ZlmRtspPort = 554
$ZlmRtmpPort = 1935
$ZlmRtpPort  = 10000
$ZlmRtcPort  = 8000

# 平台参数
$MediaId   = 'zlmediakit-01'
$SipId     = '34020000002000000001'
$SipDomain = '3402000000'
$MysqlDb   = 'wvp'
$MysqlUser = 'wvp'
$RedisDb   = 1

# 组件下载源（如网络受限，可自行替换为镜像地址）
$JreUrl   = 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jre/hotspot/normal/eclipse'
$RedisUrl = 'https://github.com/tporadowski/redis/releases/download/v5.0.14.1/Redis-x64-5.0.14.1.zip'
$MysqlUrlCandidates = @(
    'https://cdn.mysql.com/Downloads/MySQL-8.0/mysql-8.0.46-winx64.zip',
    'https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.46-winx64.zip',
    'https://mirrors.aliyun.com/mysql/MySQL-8.0/mysql-8.0.28-winx64.zip'
)

# ========================= 基础路径 =========================
$Base    = $PSScriptRoot
$Runtime = Join-Path $Base 'runtime'
$RConfig = Join-Path $Runtime 'config'
$RLogs   = Join-Path $Runtime 'logs'
$RRun    = Join-Path $Runtime 'run'
$RDl     = Join-Path $Runtime '_download'
$RData   = Join-Path $Runtime 'data'
$RMysql  = Join-Path $Runtime 'mysql'
$RRedis  = Join-Path $Runtime 'redis'
$RZlm    = Join-Path $Runtime 'zlm'
$RWvp    = Join-Path $Runtime 'wvp'
$RJre    = Join-Path $Runtime 'jre21'

# ========================= 工具函数 =========================
function Write-Step { param([string]$Msg) Write-Host "[start] $Msg" -ForegroundColor Cyan }
function Write-Warn { param([string]$Msg) Write-Host "[警告] $Msg" -ForegroundColor Yellow }
function Fail       { param([string]$Msg) Write-Host "[错误] $Msg" -ForegroundColor Red; exit 1 }
function Esc-Sql    { param([string]$S) return $S.Replace("'", "''") }

# 容忍原生命令的 stderr 警告（如 MySQL 密码安全提示）：临时降级错误偏好，避免 'Stop' 模式误终止
# 命令本身失败仍由 $LASTEXITCODE 判断处理
function Invoke-Tolerant {
    param([scriptblock]$Action)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Action } finally { $ErrorActionPreference = $prev }
}

# 含空格/特殊字符的参数加引号（供 Start-Process 使用）
function Quote-Arg {
    param([string]$S)
    if ($S -match '[\s"&|<>^()]') { return '"' + ($S -replace '"', '\"') + '"' }
    return $S
}

# 后台启动进程并记录 PID
function Start-Bg {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$WorkDir,
        [string]$PidName,
        [string]$LogBase
    )
    $quoted = @($Arguments | ForEach-Object { Quote-Arg $_ })
    $spArgs = @{
        FilePath         = $Exe
        ArgumentList     = $quoted
        WorkingDirectory = $WorkDir
        WindowStyle      = 'Hidden'
        PassThru         = $true
    }
    if ($LogBase) {
        $spArgs.RedirectStandardOutput = "$LogBase.out.log"
        $spArgs.RedirectStandardError  = "$LogBase.err.log"
    }
    $p = Start-Process @spArgs
    if ($PidName) {
        New-Item -ItemType Directory -Force -Path $RRun | Out-Null
        Set-Content -Path (Join-Path $RRun "$PidName.pid") -Value $p.Id -Encoding ASCII
    }
    return $p
}

# 等待 TCP 端口可连接（$Proc 可选：进程提前退出则直接失败）
function Wait-Tcp {
    param([int]$Port, [int]$TimeoutSec, [string]$Desc, $Proc = $null)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($Proc -and $Proc.HasExited) { Fail "$Desc 进程已退出（退出码 $($Proc.ExitCode)），请查看 runtime\logs 下日志" }
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.Connect('127.0.0.1', $Port)
            $c.Close()
            return
        }
        catch { Start-Sleep -Seconds 2 }
    }
    Fail "$Desc 在 $TimeoutSec 秒内未就绪（端口 $Port），请查看 runtime\logs 下日志"
}

# 等待 HTTP 地址可访问
function Wait-Http {
    param([string]$Url, [int]$TimeoutSec, [string]$Desc, $Proc = $null)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($Proc -and $Proc.HasExited) { Fail "$Desc 进程已退出（退出码 $($Proc.ExitCode)），请查看 runtime\logs 下日志" }
        try { $null = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3; return }
        catch { Start-Sleep -Seconds 3 }
    }
    Fail "$Desc 在 $TimeoutSec 秒内未就绪（$Url），可能仍在启动中，请查看 runtime\logs 下日志"
}

# 探测本机 IPv4（多级兜底：默认路由网卡 -> 全部网卡 -> UDP 出口地址）
function Get-HostIPv4 {
    # 方法 1：默认路由所在网卡（最准确）
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '169.254.*' } |
            Select-Object -First 1 -ExpandProperty IPAddress
        if ($ip) { return $ip }
    }
    # 方法 2：全部非回环网卡
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1 -ExpandProperty IPAddress
    if ($ip) { return $ip }
    # 方法 3：UDP 出口探测（仅本地路由查询，不产生实际流量）
    try {
        $udp = [System.Net.Sockets.UdpClient]::new()
        $udp.Connect('8.8.8.8', 53)
        $ip = $udp.Client.LocalEndPoint.Address.ToString()
        $udp.Close()
        if ($ip -and $ip -ne '0.0.0.0' -and $ip -ne '127.0.0.1') { return $ip }
    }
    catch { }
    return $null
}

function Test-PortUsed {
    param([int]$Port)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $Port)
        $c.Close()
        return $true
    }
    catch { return $false }
}

function Get-SystemJavaMajorVersion {
    try {
        $out = (& java -version 2>&1 | Out-String)
        if ($out -match 'version "(\d+)') { return [int]$Matches[1] }
    }
    catch { }
    return 0
}

function Get-RunningComponents {
    $result = @()
    foreach ($name in @('mysql', 'redis', 'zlm', 'wvp')) {
        $f = Join-Path $RRun "$name.pid"
        if (Test-Path $f) {
            $pidText = Get-Content $f -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($pidText -and (Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue)) { $result += $name }
        }
    }
    return $result
}

# 依次尝试多个下载源（失败自动切换下一个）
function Get-FileFromUrls {
    param([string[]]$Urls, [string]$Dest, [string]$Desc)
    if ($SkipDownload) { Fail "$Desc 缺失且指定了 -SkipDownload。请手动下载后放到：$Dest" }
    New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
    foreach ($u in $Urls) {
        try {
            Write-Step "下载 $Desc ...（文件较大，请耐心等待）"
            Write-Host "      $u" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $u -OutFile $Dest -UseBasicParsing
            Write-Step "$Desc 下载完成"
            return
        }
        catch {
            Write-Warn "下载失败：$($_.Exception.Message)"
        }
    }
    Fail "$Desc 的所有下载源均失败。可手动下载后放到：$Dest 再重新运行"
}

# 模板渲染：将 @KEY@ 占位符替换为实际值（输出 UTF-8 无 BOM）
function Render-Template {
    param([string]$TplPath, [string]$OutPath, [hashtable]$Map)
    $content = [IO.File]::ReadAllText($TplPath)
    foreach ($k in $Map.Keys) { $content = $content.Replace("@$k@", [string]$Map[$k]) }
    [IO.File]::WriteAllText($OutPath, $content, [Text.UTF8Encoding]::new($false))
}

# ========================= 0. 环境检查 =========================
Write-Host ''
Write-Host '=========== WVP-PRO 3.0.0 Windows 一键启动（原生，无 Docker） ===========' -ForegroundColor Green
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { Fail '本脚本仅支持 Windows' }

# ========================= 1. IP 探测 =========================
if (-not $StreamIp) {
    $StreamIp = Get-HostIPv4
    if ($StreamIp) {
        Write-Step "已自动探测本机 IP：$StreamIp（多网卡或需指定时请用 -StreamIp 参数）"
    }
    else {
        Fail '未能探测本机 IP，请用 -StreamIp 参数显式指定（须为设备/浏览器可访问的本机地址）'
    }
}

# ========================= 2. 运行状态检查 =========================
$running = Get-RunningComponents
if ($running.Count -gt 0) {
    if ($InstallOnly) {
        Write-Step "检测到组件已在运行（$($running -join ', ')）：视为已安装，无需重复安装"
        Write-Step '如需应用新配置：请先执行 .\stop.ps1 停止，再重新运行安装'
        exit 0
    }
    if ($Force) {
        Write-Step "检测到组件已在运行（$($running -join ', ')）：-Force 生效，先停止再重启"
        & (Join-Path $Base 'stop.ps1') -Quiet
    }
    else {
        Fail "组件已在运行：$($running -join ', ')。如需重启请先执行 .\stop.ps1，或使用 -Force 参数"
    }
}

# ========================= 3. 目录与端口检查 =========================
foreach ($d in @($Runtime, $RConfig, $RLogs, $RRun, $RDl, (Join-Path $RData 'mysql'), (Join-Path $RData 'redis'), (Join-Path $RData 'record'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

foreach ($p in @($MysqlPort, $RedisPort, $WvpPort, $ZlmHttpPort)) {
    if (Test-PortUsed $p) {
        Fail "端口 $p 已被占用（可能是系统上已安装的同类服务）。请停止占用程序，或修改 start.ps1/stop.ps1 顶部的端口配置"
    }
}
foreach ($p in @($SipPort, $ZlmRtspPort, $ZlmRtmpPort, $ZlmRtpPort, $ZlmRtcPort)) {
    if (Test-PortUsed $p) { Write-Warn "端口 $p 已被占用，可能导致对应功能（SIP/RTSP/RTMP/RTP/RTC）不可用" }
}

# ========================= 4. 组件准备 =========================
# ---- 4.1 Java（系统优先，否则下载 Temurin JRE 21） ----
$JavaExe = Join-Path $RJre 'bin\java.exe'
if (-not (Test-Path $JavaExe)) {
    $sysJava = Get-SystemJavaMajorVersion
    if ($sysJava -ge 21) {
        Write-Step "检测到系统 Java $sysJava（>=21），直接使用系统 java"
        $JavaExe = 'java'
    }
    else {
        if ($sysJava -gt 0) { Write-Warn "检测到系统 Java $sysJava（<21，WVP 3.0.0 需要 21+），将使用内置 JRE" }
        $zip = Join-Path $RDl 'jre21.zip'
        if (-not (Test-Path $zip)) { Get-FileFromUrls @($JreUrl) $zip 'Temurin JRE 21（约 45MB）' }
        Write-Step '解压 JRE 21 ...'
        $tmp = Join-Path $RDl 'jre_tmp'
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
        Move-Item $inner.FullName $RJre
        Remove-Item $tmp -Recurse -Force
        $JavaExe = Join-Path $RJre 'bin\java.exe'
        Write-Step 'JRE 21 准备完成'
    }
}

# ---- 4.2 MySQL 8 便携版 ----
$MysqldExe = Join-Path $RMysql 'bin\mysqld.exe'
if (-not (Test-Path $MysqldExe)) {
    $zip = Join-Path $RDl 'mysql.zip'
    if (-not (Test-Path $zip)) { Get-FileFromUrls $MysqlUrlCandidates $zip 'MySQL 8 winx64 zip（约 200MB）' }
    Write-Step '解压 MySQL ...'
    $tmp = Join-Path $RDl 'mysql_tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Move-Item $inner.FullName $RMysql
    Remove-Item $tmp -Recurse -Force
    Write-Step 'MySQL 准备完成'
}

# ---- 4.3 Redis（Windows 版） ----
$RedisExe = Join-Path $RRedis 'redis-server.exe'
if (-not (Test-Path $RedisExe)) {
    $zip = Join-Path $RDl 'redis.zip'
    if (-not (Test-Path $zip)) { Get-FileFromUrls @($RedisUrl) $zip 'Redis for Windows 5.0.14.1（约 12MB）' }
    Write-Step '解压 Redis ...'
    if (Test-Path $RRedis) { Remove-Item $RRedis -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $RRedis -Force
    Write-Step 'Redis 准备完成'
}

# ---- 4.4 ZLMediaKit（缺失时自动获取社区编译版，约 4MB 单文件） ----
$ZlmExe = Join-Path $RZlm 'MediaServer.exe'
if (-not (Test-Path $ZlmExe)) {
    if ($SkipDownload) {
        Fail @"
未找到 ZLMediaKit：$ZlmExe
离线模式（-SkipDownload）不联网获取，请获取 MediaServer.exe 后放入：
  $RZlm
获取途径（任选其一）：
  1) 社区编译版免登录直链（V2024.9.14，约 4MB，单文件无 dll 依赖）：
     https://gitee.com/beixiaocai/zlm/raw/master/V2024.9.14.windows/MediaServer.exe
  2) 官方 CI 每日构建（需登录 GitHub 下载，见 issue #483「各平台二进制包下载」）：
     https://github.com/ZLMediaKit/ZLMediaKit/issues/483
  3) 自行编译（官方文档）：
     https://docs.zlmediakit.com/zh/guide/install/compilation_instructions_for_windows_version.html
     编译产物位于 ZLMediaKit\release\windows\Release\ 目录，整体拷贝过来即可
放置后重新运行本脚本即可。
"@
    }
    New-Item -ItemType Directory -Force -Path $RZlm | Out-Null
    Get-FileFromUrls @(
        'https://gitee.com/beixiaocai/zlm/raw/master/V2024.9.14.windows/MediaServer.exe',
        'https://gitee.com/beixiaocai/zlm/raw/master/V2023.3.25.windows/MediaServer.exe',
        'https://gitee.com/beixiaocai/zlm/raw/master/V2022.5.22.windows/MediaServer.exe'
    ) $ZlmExe 'ZLMediaKit MediaServer.exe（社区编译版，约 4MB）'
    Write-Step 'ZLMediaKit 准备完成（社区编译版单文件；如需完整目录可自行编译后替换 runtime\zlm\ 内容）'
}

# ---- 4.5 WVP-PRO jar ----
$WvpJarTarget = Join-Path $RWvp 'wvp.jar'
if (-not (Test-Path $WvpJarTarget)) {
    if ($WvpJar) {
        if (-not (Test-Path $WvpJar)) { Fail "指定的 jar 不存在：$WvpJar" }
        New-Item -ItemType Directory -Force -Path $RWvp | Out-Null
        Copy-Item $WvpJar $WvpJarTarget
        Write-Step "已复制 jar 到：$WvpJarTarget"
    }
    else {
        Fail @"
未找到 WVP-PRO jar：$WvpJarTarget
官方 3.0.0 无现成 release 包，请通过以下任一方式获取后重新运行本脚本：
  1) 使用 -WvpJar 参数指定已有 jar：
     .\start.ps1 -WvpJar D:\download\wvp-pro-3.0.0.jar
  2) 手动把 jar 复制到：$WvpJarTarget
获取 jar 的途径（任选）：
  a. 从 docker-compose 构建的 wvp 镜像中提取（jar 跨平台）：
     在 Linux 构建机：docker create --name wvp-tmp wvp-pro:3.0.0 然后 docker cp wvp-tmp:/opt/wvp/wvp.jar .
  b. 自行构建：git clone 源码（gitee/github 648540858/wvp-GB28181-pro，分支 master，pom 版本 3.0.0）
     先 npm run build:prod（web 目录）再 mvn clean package -Dmaven.test.skip=true，产物 target\wvp-pro-3.0.0-*.jar
"@
    }
}

# ========================= 5. 生成配置 =========================
# ---- 5.1 MySQL my.ini ----
$MyIni = Join-Path $RMysql 'my.ini'
$sqlDir = ($RData -replace '\\', '/') + '/mysql'
$sqlLog = ($RLogs -replace '\\', '/') + '/mysql-error.log'
$myIniContent = @"
[mysqld]
port=$MysqlPort
bind-address=127.0.0.1
basedir=$(($RMysql -replace '\\', '/'))
datadir=$sqlDir
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
default-time-zone=+8:00
lower_case_table_names=1
max_connections=500
innodb-buffer-pool-size=256M
log-error=$sqlLog
[client]
default-character-set=utf8mb4
"@
[IO.File]::WriteAllText($MyIni, $myIniContent, [Text.UTF8Encoding]::new($false))
Write-Step "MySQL 配置已生成：$MyIni"

# ---- 5.2 Redis redis.conf ----
$RedisConf = Join-Path $RRedis 'redis.conf'
$rdData = '"' + (($RData -replace '\\', '/') + '/redis') + '"'
$rdLog  = '"' + (($RLogs -replace '\\', '/') + '/redis.log') + '"'
$redisConfContent = @"
port $RedisPort
bind 127.0.0.1
requirepass $RedisPassword
dir $rdData
appendonly yes
dbfilename dump.rdb
logfile $rdLog
"@
[IO.File]::WriteAllText($RedisConf, $redisConfContent, [Text.UTF8Encoding]::new($false))
Write-Step "Redis 配置已生成：$RedisConf"

# ---- 5.3 WVP application.yml ----
$recordPath = ($RData -replace '\\', '/') + '/record/'
$appMap = @{
    WVP_PORT        = $WvpPort
    SIP_PORT        = $SipPort
    SIP_ID          = $SipId
    SIP_DOMAIN      = $SipDomain
    SIP_PASSWORD    = $SipPassword
    SIP_SHOW_IP     = $StreamIp
    STREAM_IP       = $StreamIp
    SDP_IP          = $StreamIp
    ZLM_HTTP_PORT   = $ZlmHttpPort
    ZLM_SECRET      = $ZlmSecret
    MEDIA_ID        = $MediaId
    MYSQL_PORT      = $MysqlPort
    MYSQL_DB        = $MysqlDb
    MYSQL_USER      = $MysqlUser
    MYSQL_PASSWORD  = $MysqlPassword
    REDIS_PORT      = $RedisPort
    REDIS_DB        = $RedisDb
    REDIS_PWD       = $RedisPassword
    RECORD_PATH     = $recordPath
}
Render-Template (Join-Path $Base 'config\application.yml.template') (Join-Path $RConfig 'application.yml') $appMap
Write-Step "WVP 配置已生成：$(Join-Path $RConfig 'application.yml')"

# ---- 5.4 ZLM config.ini ----
$zlmMap = @{
    ZLM_HTTP_PORT = $ZlmHttpPort
    ZLM_RTSP_PORT = $ZlmRtspPort
    ZLM_RTMP_PORT = $ZlmRtmpPort
    ZLM_RTP_PORT  = $ZlmRtpPort
    ZLM_RTC_PORT  = $ZlmRtcPort
    ZLM_SECRET    = $ZlmSecret
    MEDIA_ID      = $MediaId
    WVP_PORT      = $WvpPort
}
Render-Template (Join-Path $Base 'config\zlm-config.ini.template') (Join-Path $RZlm 'config.ini') $zlmMap
Write-Step "ZLM 配置已生成：$(Join-Path $RZlm 'config.ini')"

# ========================= 6. 启动 MySQL 并初始化 =========================
$MysqlMarker = Join-Path $RData 'mysql\.wvp-initialized'
$mysqlAdmin  = Join-Path $RMysql 'bin\mysqladmin.exe'
$mysqlCli    = Join-Path $RMysql 'bin\mysql.exe'

if (-not (Test-Path (Join-Path $RData 'mysql\mysql'))) {
    Write-Step '首次运行：初始化 MySQL 数据目录（约 10~30 秒）...'
    Invoke-Tolerant { & $MysqldExe "--defaults-file=$MyIni" --initialize-insecure }
    if ($LASTEXITCODE -ne 0) { Fail 'MySQL 数据目录初始化失败，请查看上方输出' }
    Write-Step 'MySQL 数据目录初始化完成'
}

Write-Step "启动 MySQL（端口 $MysqlPort）..."
$mysqlProc = Start-Bg -Exe $MysqldExe -Arguments @("--defaults-file=$MyIni") -WorkDir $RMysql -PidName 'mysql'
Wait-Tcp -Port $MysqlPort -TimeoutSec 120 -Desc 'MySQL' -Proc $mysqlProc

$rootPwdSql = Esc-Sql $MysqlRootPassword
if (-not (Test-Path $MysqlMarker)) {
    Write-Step '首次初始化：创建数据库与账号，导入 WVP 3.0.0 表结构 ...'
    $initSql = @"
CREATE DATABASE IF NOT EXISTS ``$MysqlDb`` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$MysqlUser'@'localhost' IDENTIFIED BY '$(Esc-Sql $MysqlPassword)';
CREATE USER IF NOT EXISTS '$MysqlUser'@'%' IDENTIFIED BY '$(Esc-Sql $MysqlPassword)';
GRANT ALL PRIVILEGES ON ``$MysqlDb``.* TO '$MysqlUser'@'localhost';
GRANT ALL PRIVILEGES ON ``$MysqlDb``.* TO '$MysqlUser'@'%';
FLUSH PRIVILEGES;
"@
    Invoke-Tolerant { & $mysqlCli -h 127.0.0.1 -P $MysqlPort -uroot --default-character-set=utf8mb4 -e $initSql }
    if ($LASTEXITCODE -ne 0) { Fail '创建数据库/账号失败，请查看上方输出' }

    Push-Location (Join-Path $Base 'mysql\init')
    try {
        Invoke-Tolerant { & $mysqlCli -h 127.0.0.1 -P $MysqlPort -uroot --default-character-set=utf8mb4 $MysqlDb -e "source wvp-init-3.0.0.sql" }
        if ($LASTEXITCODE -ne 0) { Fail '导入初始化 SQL 失败，请查看上方输出' }
    }
    finally { Pop-Location }

    Invoke-Tolerant { & $mysqlCli -h 127.0.0.1 -P $MysqlPort -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPwdSql';" }
    if ($LASTEXITCODE -ne 0) { Fail '设置 root 密码失败，请查看上方输出' }

    Set-Content -Path $MysqlMarker -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding ASCII
    Write-Step '数据库初始化完成'
}
else {
    Write-Step '数据库已初始化（检测到完成标记），验证连接 ...'
    Invoke-Tolerant { & $mysqlCli -h 127.0.0.1 -P $MysqlPort -uroot "-p$MysqlRootPassword" -e "SELECT 1;" 2>$null | Out-Null }
    if ($LASTEXITCODE -ne 0) {
        Fail "无法用当前密码连接 MySQL（root）。若修改过密码参数，请删除 runtime\data\mysql 后重新运行（数据将清空）"
    }
    $syncSql = @"
ALTER USER '$MysqlUser'@'localhost' IDENTIFIED BY '$(Esc-Sql $MysqlPassword)';
ALTER USER '$MysqlUser'@'%' IDENTIFIED BY '$(Esc-Sql $MysqlPassword)';
FLUSH PRIVILEGES;
"@
    Invoke-Tolerant { & $mysqlCli -h 127.0.0.1 -P $MysqlPort -uroot "-p$MysqlRootPassword" -e $syncSql 2>$null | Out-Null }
    Write-Step '数据库连接正常'
}

# ---- 仅安装模式：数据库已初始化，停止临时 MySQL 后退出 ----
if ($InstallOnly) {
    Write-Step '停止临时启动的 MySQL（仅安装模式不启动服务）...'
    Invoke-Tolerant { & $mysqlAdmin -h 127.0.0.1 -P $MysqlPort -uroot "-p$MysqlRootPassword" shutdown 2>$null | Out-Null }
    Start-Sleep -Seconds 2
    if ($mysqlProc -and -not $mysqlProc.HasExited) {
        Write-Warn 'MySQL 未正常退出，强制结束进程（数据已持久化，通常无碍）'
        Stop-Process -Id $mysqlProc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    Remove-Item (Join-Path $RRun 'mysql.pid') -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host '===== 安装完成（组件就绪 / 配置已生成 / 数据库已初始化） =====' -ForegroundColor Green
    Write-Host '  启动服务 :  .\start.ps1      （离线包内可直接运行 start.bat）'
    Write-Host '  停止服务 :  .\stop.ps1       （离线包内可直接运行 stop.bat）'
    Write-Host "  访问地址 :  http://${StreamIp}:$WvpPort   默认账号 admin / admin"
    Write-Host '==============================================================' -ForegroundColor Green
    exit 0
}

# ========================= 7. 启动 Redis =========================
Write-Step "启动 Redis（端口 $RedisPort）..."
$redisProc = Start-Bg -Exe $RedisExe -Arguments @($RedisConf) -WorkDir $RRedis -PidName 'redis'
Wait-Tcp -Port $RedisPort -TimeoutSec 60 -Desc 'Redis' -Proc $redisProc
Write-Step 'Redis 已就绪'

# ========================= 8. 启动 ZLMediaKit =========================
Write-Step "启动 ZLMediaKit（HTTP $ZlmHttpPort）..."
$zlmProc = Start-Bg -Exe (Join-Path $RZlm 'MediaServer.exe') -Arguments @('-c', 'config.ini', '-l', '0') -WorkDir $RZlm -PidName 'zlm' -LogBase (Join-Path $RLogs 'zlm-console')
Wait-Http -Url "http://127.0.0.1:$ZlmHttpPort/index/api/getServerConfig?secret=$ZlmSecret" -TimeoutSec 60 -Desc 'ZLMediaKit' -Proc $zlmProc
Write-Step 'ZLMediaKit 已就绪'

# ========================= 9. 启动 WVP-PRO =========================
Write-Step '启动 WVP-PRO（首次启动约 30~60 秒）...'
$wvpProc = Start-Bg -Exe $JavaExe `
    -Arguments @('-Xms512m', '-Xmx1024m', '-Duser.timezone=Asia/Shanghai',
                 '-jar', 'wvp/wvp.jar', '--spring.config.location=config/application.yml') `
    -WorkDir $Runtime -PidName 'wvp' -LogBase (Join-Path $RLogs 'wvp-console')
Wait-Http -Url "http://127.0.0.1:$WvpPort/" -TimeoutSec 240 -Desc 'WVP-PRO' -Proc $wvpProc

# ========================= 10. 完成 =========================
Write-Host ''
Write-Host '==================== WVP-PRO 已启动（原生进程） ====================' -ForegroundColor Green
Write-Host "  访问地址 :  http://${StreamIp}:$WvpPort        默认账号 admin / admin"
Write-Host "  设备接入 :  SIP 地址 $StreamIp  端口 $SipPort  密码 $SipPassword"
Write-Host "              服务器 ID $SipId   域 $SipDomain"
Write-Host '  进程管理 :  停止全部 -> .\stop.ps1     重启 -> .\stop.ps1; .\start.ps1'
Write-Host '  日志位置 :  runtime\logs\（wvp-console / zlm-console / mysql-error / redis）'
Write-Host '  数据位置 :  runtime\data\（mysql / redis / record 录像）'
Write-Host "  组件位置 :  runtime\（jre21 / mysql / redis / zlm / wvp）"
Write-Host '==================================================================' -ForegroundColor Green