#Requires -Version 5.1
<#
.SYNOPSIS
  WVP-PRO 3.0.0 · Windows 原生一键停止（配套 start.ps1，不依赖 Docker）
.DESCRIPTION
  按 wvp -> zlm -> redis -> mysql 顺序停止本目录 runtime\ 下的全部组件进程。
  Redis/MySQL 优先优雅停机（redis-cli shutdown / mysqladmin shutdown），失败则强制结束进程。
.PARAMETER Quiet
  静默模式（仅输出必要信息；start.ps1 -Force 内部调用时使用）
.PARAMETER MysqlRootPassword
  MySQL root 密码（需与 start.ps1 使用的密码一致，默认使用内置默认值）
.PARAMETER RedisPassword
  Redis 密码（需与 start.ps1 使用的密码一致，默认使用内置默认值）
.EXAMPLE
  .\stop.ps1
#>
[CmdletBinding()]
param(
    [switch]$Quiet,
    [string]$MysqlRootPassword = 'wvp_root_123456',
    [string]$RedisPassword     = 'wvp_redis_123456'
)

$ErrorActionPreference = 'Continue'

# 端口（需与 start.ps1 顶部保持一致）
$MysqlPort = 3306
$RedisPort = 6379

$Base    = $PSScriptRoot
$Runtime = Join-Path $Base 'runtime'
$RLogs   = Join-Path $Runtime 'logs'
$RRun    = Join-Path $Runtime 'run'
$RMysql  = Join-Path $Runtime 'mysql'
$RRedis  = Join-Path $Runtime 'redis'

function Write-Step { param([string]$Msg) if (-not $Quiet) { Write-Host "[stop] $Msg" -ForegroundColor Cyan } }
function Write-Warn { param([string]$Msg) if (-not $Quiet) { Write-Host "[警告] $Msg" -ForegroundColor Yellow } }

# 读取 PID 并强制结束进程；返回是否执行了停止
function Stop-ByPid {
    param([string]$Name)
    $f = Join-Path $RRun "$Name.pid"
    if (-not (Test-Path $f)) { return $false }
    $pidText = Get-Content $f -ErrorAction SilentlyContinue | Select-Object -First 1
    $proc = $null
    if ($pidText) { $proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue }
    if ($proc) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 500
        }
        if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
            Write-Warn "$Name 进程未能终止（PID $($proc.Id)），请手动处理"
            return $false
        }
        Write-Step "$Name 已停止（PID $($proc.Id)）"
        Remove-Item $f -Force -ErrorAction SilentlyContinue
        return $true
    }
    Remove-Item $f -Force -ErrorAction SilentlyContinue
    return $false
}

# 进程是否仍在运行（按 PID 文件判断）
function Test-Running {
    param([string]$Name)
    $f = Join-Path $RRun "$Name.pid"
    if (-not (Test-Path $f)) { return $false }
    $pidText = Get-Content $f -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pidText -and (Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue)) { return $true }
    return $false
}

Write-Step '正在停止 WVP-PRO 全部组件 ...'

# ---- 1. WVP-PRO ----
if (Test-Running 'wvp') {
    Write-Step '停止 WVP-PRO ...'
    Stop-ByPid 'wvp' | Out-Null
}
else {
    Remove-Item (Join-Path $RRun 'wvp.pid') -Force -ErrorAction SilentlyContinue
    Write-Step 'WVP-PRO 未在运行'
}

# ---- 2. ZLMediaKit ----
if (Test-Running 'zlm') {
    Write-Step '停止 ZLMediaKit ...'
    Stop-ByPid 'zlm' | Out-Null
}
else {
    Remove-Item (Join-Path $RRun 'zlm.pid') -Force -ErrorAction SilentlyContinue
    Write-Step 'ZLMediaKit 未在运行'
}

# ---- 3. Redis（优先 redis-cli 优雅停机） ----
if (Test-Running 'redis') {
    Write-Step '停止 Redis ...'
    $redisCli = Join-Path $RRedis 'redis-cli.exe'
    if (Test-Path $redisCli) {
        & $redisCli -h 127.0.0.1 -p $RedisPort -a $RedisPassword shutdown 2>$null | Out-Null
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Test-Running 'redis')) { break }
            Start-Sleep -Milliseconds 500
        }
    }
    if (Test-Running 'redis') {
        Write-Warn '优雅停机未完成，强制结束 Redis 进程'
        Stop-ByPid 'redis' | Out-Null
    }
    else {
        Remove-Item (Join-Path $RRun 'redis.pid') -Force -ErrorAction SilentlyContinue
        Write-Step 'Redis 已停止'
    }
}
else {
    Remove-Item (Join-Path $RRun 'redis.pid') -Force -ErrorAction SilentlyContinue
    Write-Step 'Redis 未在运行'
}

# ---- 4. MySQL（优先 mysqladmin 优雅停机） ----
if (Test-Running 'mysql') {
    Write-Step '停止 MySQL ...'
    $mysqlAdmin = Join-Path $RMysql 'bin\mysqladmin.exe'
    if (Test-Path $mysqlAdmin) {
        & $mysqlAdmin -h 127.0.0.1 -P $MysqlPort -uroot "-p$MysqlRootPassword" shutdown 2>$null | Out-Null
        for ($i = 0; $i -lt 30; $i++) {
            if (-not (Test-Running 'mysql')) { break }
            Start-Sleep -Milliseconds 500
        }
    }
    if (Test-Running 'mysql') {
        Write-Warn '优雅停机未完成，强制结束 MySQL 进程（数据已持久化，通常无碍）'
        Stop-ByPid 'mysql' | Out-Null
    }
    else {
        Remove-Item (Join-Path $RRun 'mysql.pid') -Force -ErrorAction SilentlyContinue
        Write-Step 'MySQL 已停止'
    }
}
else {
    Remove-Item (Join-Path $RRun 'mysql.pid') -Force -ErrorAction SilentlyContinue
    Write-Step 'MySQL 未在运行'
}

# 端口复查：端口仍被监听时提示可能存在未被 PID 文件记录的残留实例
foreach ($chk in @(@('MySQL', $MysqlPort), @('Redis', $RedisPort))) {
    $name = $chk[0]
    $port = [int]$chk[1]
    $still = $false
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $port)
        $c.Close()
        $still = $true
    }
    catch { $still = $false }
    if ($still) { Write-Warn "端口 $port 仍被监听：可能存在未被 PID 记录的 $name 残留实例，请手动检查" }
}

Write-Step '全部组件已停止'
if (-not $Quiet) {
    Write-Host ''
    Write-Host '  重新启动： .\start.ps1' -ForegroundColor Green
}