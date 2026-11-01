# 知序Windows入口：仅准备项目私有运行环境、运行或本机打包；不改系统PATH。
param([ValidateSet('run','build')][string]$Mode='run')
$ErrorActionPreference='Stop'
$Project=Split-Path $PSScriptRoot -Parent
$Delivery=Split-Path $Project -Parent
function Confirm-Enter([string]$Text) {
    if ([Console]::IsInputRedirected) { throw '无交互输入，请双击平台入口。' }
    $Answer=Read-Host $Text
    if ($Answer -ne '') { throw '已取消当前流程。' }
}
function Show-Intro {
    Write-Host '知序桌面端 · Windows' -ForegroundColor Red
    Write-Host "用途：$Mode；仅写本工程内的运行环境和构建文件，不改系统PATH。"
    if($Mode -eq 'build'){Write-Host '生成EXE+ZIP，会清理本应用dist旧包；成功后打开产物目录并启动本次软件。'}
    Write-Host '缺少Python时从Astral官方Release下载uv并校验SHA256，取得Python3.15.2。'
    Write-Host '来源：https://github.com/astral-sh/uv/releases/tag/0.13.6；Python依赖来自https://pypi.org/'
    Write-Host '日志：zhixu/.build/session.log；Ctrl+C取消。'
    Confirm-Enter '已了解用途与影响，直接回车继续，任意字符取消'
}
function Find-Python {
    foreach($Name in @('python','python3')) {
        $Candidate=Get-Command $Name -ErrorAction SilentlyContinue
        if($Candidate) {
            & $Candidate.Source -c "import sys; assert (3,10) <= sys.version_info[:2] < (3,16)" 2>$null
            if($LASTEXITCODE -eq 0){return $Candidate.Source}
        }
    }
    return $null
}
function Install-Python {
    Confirm-Enter '缺少可用Python。将下载到项目私有.tools，直接回车安装，任意字符取消'
    $Tools=Join-Path $Project '.tools'
    New-Item -ItemType Directory -Force $Tools | Out-Null
    $Arch=if($env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){'aarch64'}else{'x86_64'}
    $Asset="uv-$Arch-pc-windows-msvc.zip"
    $Source="https://github.com/astral-sh/uv/releases/download/0.13.6/$Asset"
    Write-Host "来源：$Source → $Tools"
    $Archive=Join-Path $Tools $Asset
    Invoke-WebRequest -UseBasicParsing -Uri $Source -OutFile $Archive
    Invoke-WebRequest -UseBasicParsing -Uri "$Source.sha256" -OutFile "$Archive.sha256"
    $Expected=((Get-Content "$Archive.sha256" -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    if($Expected -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected){throw 'uv文件SHA256不一致。'}
    Expand-Archive -LiteralPath $Archive -DestinationPath (Join-Path $Tools 'uv') -Force
    $Uv=(Get-ChildItem (Join-Path $Tools 'uv') -Filter uv.exe -Recurse | Select-Object -First 1).FullName
    if(!$Uv){throw 'uv.exe未取得。'}
    & $Uv --version | Out-Host
    if($LASTEXITCODE -ne 0){throw 'uv运行失败。'}
    $env:UV_PYTHON_INSTALL_DIR=Join-Path $Tools 'python'
    & $Uv python install 3.15.2 | Out-Host
    if($LASTEXITCODE -ne 0){throw 'Python安装失败。'}
    $Found= & $Uv python find --managed-python 3.15.2
    if($LASTEXITCODE -ne 0 -or !$Found){throw 'Python安装后复检失败。'}
    return $Found.Trim()
}
function Run-Application {
    $Python=Find-Python
    if(!$Python){$Python=Install-Python}
    & $Python -c "import sys; assert (3,10) <= sys.version_info[:2] < (3,16)"
    if($LASTEXITCODE -ne 0){throw 'Python健康检查失败。'}
    $env:ZHIXU_ENTRY_LOGGING='1'
    $Work=Join-Path $Project '.build'
    New-Item -ItemType Directory -Force $Work | Out-Null
    & $Python (Join-Path $PSScriptRoot 'manage.py') $Mode --entry-confirmed 2>&1 | Tee-Object -FilePath (Join-Path $Work 'session.log')
    if($LASTEXITCODE -ne 0){throw "执行失败，退出码$LASTEXITCODE；请查看日志。"}
}
try {
    Show-Intro
    Run-Application
    exit 0
} catch {
    Write-Host "失败：$($_.Exception.Message)" -ForegroundColor Red
    Read-Host '请保留错误与日志，回车关闭'
    exit 1
}
