#Requires -Version 5.1
<#
.SYNOPSIS
  WVP-PRO 3.0.0 · Windows 离线安装入口（随离线包分发；与 start.ps1 / stop.ps1 同目录使用）
.DESCRIPTION
  等价于同目录 start.ps1 -SkipDownload -InstallOnly：
  完成组件就绪（JRE/MySQL/Redis/ZLM/jar）、配置生成与数据库初始化后退出，不启动服务。
  启动服务：运行同目录 start.ps1（离线包内可双击 start.bat）；停止：stop.ps1（stop.bat）。
  说明：install.ps1 / start.ps1 / stop.ps1 为唯一版本，打包时由 pack.ps1 原样拷入离线包。
.EXAMPLE
  .\install.ps1
.EXAMPLE
  .\install.ps1 -StreamIp 192.168.1.105 -SipPassword MySipPwd
#>
[CmdletBinding()]
param(
    [string]$StreamIp = '',
    [string]$SipPassword = '',
    [string]$MysqlRootPassword = '',
    [string]$MysqlPassword = '',
    [string]$RedisPassword = '',
    [string]$ZlmSecret = ''
)

$target = Join-Path $PSScriptRoot 'start.ps1'
if (-not (Test-Path $target)) {
    Write-Host "[错误] 未找到同目录 start.ps1（$target）：请在离线包解压目录内运行本脚本" -ForegroundColor Red
    exit 1
}

$fwd = @{}
foreach ($n in @('StreamIp', 'SipPassword', 'MysqlRootPassword', 'MysqlPassword', 'RedisPassword', 'ZlmSecret')) {
    if ($PSBoundParameters.ContainsKey($n) -and $PSBoundParameters[$n]) { $fwd[$n] = $PSBoundParameters[$n] }
}

& $target -SkipDownload -InstallOnly @fwd
exit $LASTEXITCODE