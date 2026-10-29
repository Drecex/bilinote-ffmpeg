param(
    [string]$InstallDir,
    [string]$FFmpegUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
    [switch]$NoRestart,
    [switch]$SkipHealthCheck
)

$ErrorActionPreference = 'Stop'
$script:logFile = Join-Path $PSScriptRoot 'install.log'
if (Test-Path $script:logFile) { Remove-Item $script:logFile -Force }

function Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date).ToString('HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8
}

function Fail {
    param([string]$Message)
    Log $Message 'ERROR'
    Write-Host ''
    Write-Host "安装失败：$Message" -ForegroundColor Red
    Write-Host "详细日志：$script:logFile" -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------- 1. 定位安装目录
function Resolve-InstallDir {
    param([string]$Hint)
    $candidates = @()
    if ($Hint) { $candidates += $Hint }
    $entry = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq 'BiliNote' } | Select-Object -First 1
    if ($entry -and $entry.InstallLocation) { $candidates += $entry.InstallLocation.Trim('"') }
    $candidates += (Join-Path $env:LOCALAPPDATA 'BiliNote')
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'BiliNoteBackend.exe'))) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

function Find-SetupExe {
    $paths = @(
        (Join-Path $PSScriptRoot 'BiliNote_2.4.5_x64-setup.exe'),
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'BiliNote_2.4.5_x64-setup.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\BiliNote_2.4.5_x64-setup.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\BiliNote_2.4.5_x64-setup.exe')
    )
    foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

Log '=== BiliNote + FFmpeg 一键安装 ==='
Log "安装包目录: $PSScriptRoot"

$dir = Resolve-InstallDir -Hint $InstallDir
if (-not $dir) {
    Log '未检测到已安装的 BiliNote，尝试调用官方安装程序...'
    $setup = Find-SetupExe
    if (-not $setup) { Fail '找不到 BiliNote_2.4.5_x64-setup.exe，请把它放到本脚本同级目录后重试。' }
    Log "运行安装程序: $setup"
    $proc = Start-Process -FilePath $setup -ArgumentList '/S' -Wait -PassThru
    Log "安装程序退出码: $($proc.ExitCode)"
    Start-Sleep -Seconds 3
    $dir = Resolve-InstallDir
    if (-not $dir) { Fail 'BiliNote 安装后仍未找到安装目录。' }
}
Log "BiliNote 安装目录: $dir"

# ---------------------------------------------------------------- 2. 校验并部署 ffmpeg
function Test-FFmpegDir {
    param([string]$Dir)
    if (-not $Dir) { return $false }
    return ((Test-Path -LiteralPath (Join-Path $Dir 'ffmpeg.exe')) -and (Test-Path -LiteralPath (Join-Path $Dir 'ffprobe.exe')))
}

$ffSrc = $null
foreach ($cand in @((Join-Path $PSScriptRoot 'ffmpeg\bin'), (Join-Path $dir 'ffmpeg\bin'), (Join-Path $env:LOCALAPPDATA 'BiliNote\ffmpeg\bin'))) {
    if (Test-FFmpegDir $cand) {
        $ffSrc = (Resolve-Path -LiteralPath $cand).Path
        Log "使用已有的 ffmpeg: $ffSrc"
        break
    }
}
if (-not $ffSrc) {
    $sysCmd = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
    if ($sysCmd) {
        $ffSrc = Split-Path -Parent $sysCmd.Source
        Log "使用系统 PATH 中的 ffmpeg: $ffSrc"
    }
}
if (-not $ffSrc) {
    Log "本机没有可用 ffmpeg，开始下载：$FFmpegUrl"
    $work = Join-Path $env:TEMP ('bilinote-ffmpeg-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'ffmpeg.zip'
    try {
        $ProgressPreference = 'SilentlyContinue'   # 关掉进度条，Invoke-WebRequest 会快很多
        Invoke-WebRequest -Uri $FFmpegUrl -OutFile $zip -UseBasicParsing -TimeoutSec 1800
    } catch {
        Fail "ffmpeg 下载失败（$($_.Exception.Message)）。可手动下载后解压到 $(Join-Path $PSScriptRoot 'ffmpeg\bin') 再重试。"
    }
    if (-not (Test-Path -LiteralPath $zip) -or (Get-Item $zip).Length -lt 10MB) { Fail 'ffmpeg 压缩包下载不完整。' }
    Log ("下载完成: " + [math]::Round((Get-Item $zip).Length / 1MB, 1) + " MB，正在解压...")
    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
    $found = Get-ChildItem -LiteralPath $work -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { Fail '压缩包里没有找到 ffmpeg.exe。' }
    $ffSrc = $found.DirectoryName
    Log "已解压到: $ffSrc"
}
foreach ($tool in @('ffmpeg', 'ffprobe')) {
    $exe = Join-Path $ffSrc "$tool.exe"
    if (-not (Test-Path -LiteralPath $exe)) { Fail "ffmpeg 目录里缺少 $tool.exe: $ffSrc" }
    $out = & $exe -version 2>&1
    $rc = $LASTEXITCODE
    $ver = [string]($out | Select-Object -First 1)
    if ($rc -ne 0) { Fail "$tool 自检失败（退出码 $rc）" }
    Log "源 $tool 可用: $ver"
}

$ffDst = Join-Path $dir 'ffmpeg\bin'
New-Item -ItemType Directory -Path $ffDst -Force | Out-Null
foreach ($exe in Get-ChildItem -LiteralPath $ffSrc -Filter '*.exe') {
    $target = Join-Path $ffDst $exe.Name
    if ([System.IO.Path]::GetFullPath($exe.FullName) -eq [System.IO.Path]::GetFullPath($target)) {
        Log "已在目标位置: $($exe.Name)"
        continue
    }
    Copy-Item -LiteralPath $exe.FullName -Destination $ffDst -Force
    Log "已部署: $($exe.Name)"
}
$ffOut = & (Join-Path $ffDst 'ffmpeg.exe') -version 2>&1
$ffRc = $LASTEXITCODE
if ($ffRc -ne 0) { Fail "部署后的 ffmpeg 无法运行（退出码 $ffRc）。" }
Log ("目标 ffmpeg 可用: " + [string]($ffOut | Select-Object -First 1))

# ---------------------------------------------------------------- 3. 写入 FFMPEG_BIN_PATH
$envFile = Join-Path $dir '_internal\.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    $alt = Join-Path $dir '.env'
    if (Test-Path -LiteralPath $alt) { $envFile = $alt } else { Fail "找不到配置文件: $envFile" }
}
Log "配置文件: $envFile"

$backup = "$envFile.bak-" + (Get-Date -Format 'yyyyMMddHHmmss')
Copy-Item -LiteralPath $envFile -Destination $backup -Force
Log "已备份原配置: $backup"

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
try {
    $text = [System.IO.File]::ReadAllText($envFile, $utf8Strict)
} catch {
    Fail "配置文件不是有效的 UTF-8（$($_.Exception.Message)），已停止写入以免破坏配置。"
}

function Set-EnvLine {
    param([string]$Text, [string]$Key, [string]$Value)
    $newLine = "$Key=$Value"
    if ($Text -match "(?m)^\s*$([regex]::Escape($Key))\s*=") {
        return [regex]::Replace($Text, "(?m)^\s*$([regex]::Escape($Key))\s*=.*$", $newLine)
    }
    if (-not $Text.EndsWith("`n")) { $Text += "`r`n" }
    return $Text + $newLine + "`r`n"
}

$ffPath = $ffDst.Replace('\', '/')
$line = "FFMPEG_BIN_PATH=$ffPath"
$text = Set-EnvLine -Text $text -Key 'FFMPEG_BIN_PATH' -Value $ffPath

# 国内网络无法访问 huggingface.co，本地 whisper 模型下载必须走镜像
$hfLine = 'HF_ENDPOINT=https://hf-mirror.com'
if ($text -notmatch '(?m)^\s*HF_ENDPOINT\s*=\s*\S+') {
    $text = Set-EnvLine -Text $text -Key 'HF_ENDPOINT' -Value 'https://hf-mirror.com'
    Log "已写入: $hfLine"
} else {
    Log '已存在 HF_ENDPOINT，保持不变'
}

[System.IO.File]::WriteAllText($envFile, $text, (New-Object System.Text.UTF8Encoding($false)))
Log "已写入: $line"

# 写后校验（历史上出现过写入未落盘的情况，所以必须回读确认）
$check = [System.IO.File]::ReadAllText($envFile, $utf8Strict)
if ($check -notmatch [regex]::Escape($line)) { Fail '配置写入校验失败：回读未找到 FFMPEG_BIN_PATH。' }
if ($check -notmatch [regex]::Escape($hfLine)) { Fail '配置写入校验失败：回读未找到 HF_ENDPOINT。' }
Log '配置写入校验通过（回读一致）'

# ---------------------------------------------------------------- 4. 重启 BiliNote
if (-not $NoRestart) {
    $running = Get-Process -Name 'app', 'BiliNoteBackend' -ErrorAction SilentlyContinue
    if ($running) {
        Log '检测到 BiliNote 正在运行，正在关闭以便重新加载配置...'
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    $appExe = Join-Path $dir 'app.exe'
    if (Test-Path -LiteralPath $appExe) {
        Start-Process -FilePath $appExe
        Log '已启动 BiliNote'
    }
}

# ---------------------------------------------------------------- 5. 健康检查
if (-not $SkipHealthCheck) {
    Log '等待后端就绪并检查 ffmpeg 状态...'
    $ok = $false
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-RestMethod -Uri 'http://127.0.0.1:8483/api/sys_health' -TimeoutSec 5
            if ($r.data.ffmpeg -eq 'ok') { $ok = $true; break }
            if ($r.data.ffmpeg) { Log "当前 ffmpeg 状态: $($r.data.ffmpeg)" }
        } catch { }
    }
    if ($ok) { Log '健康检查通过：ffmpeg = ok' }
    else { Log '健康检查未通过（可能是 BiliNote 尚未启动完成），请手动打开 BiliNote 后重试。' 'WARN' }
    if (-not $ok) {
        Write-Host ''
        Write-Host '配置已写入，但后端未能在 90 秒内报告 ffmpeg = ok。' -ForegroundColor Yellow
        Write-Host "请完全退出 BiliNote 后重新打开，日志：$dir\logs\app.log" -ForegroundColor Yellow
        exit 2
    }
}

Write-Host ''
Write-Host '安装完成：FFmpeg 已集成到 BiliNote，可以正常生成笔记。' -ForegroundColor Green
Write-Host "安装目录：$dir" -ForegroundColor Green
Write-Host "日志文件：$script:logFile" -ForegroundColor Green
exit 0
