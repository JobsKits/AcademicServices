# 脚本自述：在当前backend配置、准备本地Go、编译并启动，不修改全局PATH或防火墙。
# 双击同目录部署.cmd进入；首次设置两组不同密码。--check仅读取，不下载或写入。
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$ServerRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$LogFile = Join-Path $ServerRoot ('.runtime/logs/deploy-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$GoVersion = 'go1.27.3'
$GoExe = ''
# 打印自述并等待执行确认。
function Show-Intro {
    Write-Host "知序服务 | Windows 部署" -ForegroundColor Red
    Write-Host '1、配置账户，缺少环境时下载官方Go至本工程，校验SHA256。'
    Write-Host '2、仅写本目录 .tools/.runtime/data，不改全局PATH、系统服务或防火墙。'
    Write-Host '3、编译成功后在当前窗口运行；Ctrl+C停止，业务数据保留。'
    Write-Host '4、Go模块默认goproxy.cn，失败回退官方；GOPROXY可覆盖，仅当前进程生效。'
    Write-Host "源码：$ServerRoot"
    Write-Host "日志：$LogFile"
    if ($Check) { return }
    if ([Console]::IsInputRedirected) { throw '请在交互终端运行。' }
    if ((Read-Host '按回车继续；任意字符取消').Length -ne 0) { throw '已取消。' }
}
# 检查源码与Windows平台。
function Test-Source {
    if ($env:OS -ne 'Windows_NT') { throw '请使用当前系统专属入口。' }
    if (-not (Test-Path (Join-Path $ServerRoot 'go.mod')) -or -not (Test-Path (Join-Path $ServerRoot 'cmd/server'))) { throw '请复制完整backend文件夹。' }
}
# 创建本次日志和工程内运行目录。
function Initialize-Runtime {
    foreach ($part in @('.runtime','.runtime/logs','.runtime/bin','.tools','data')) {
        $existing = Get-Item -Force -LiteralPath (Join-Path $ServerRoot $part) -ErrorAction SilentlyContinue
        if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '拒绝写入链接运行目录。' }
    }
    foreach ($part in @('.runtime/logs','.runtime/bin','.tools','data')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $ServerRoot $part) | Out-Null
    }
    Start-Transcript -Path $LogFile | Out-Null
}
# 验证候选Go版本，已有健康环境直接复用。
function Test-Go([string]$Candidate) {
    if (-not $Candidate -or -not (Test-Path $Candidate)) { return $false }
    try {
        $version = & $Candidate version 2>$null
        if ($LASTEXITCODE -eq 0 -and ($version -split ' ')[2] -eq $GoVersion) { $script:GoExe = $Candidate; return $true }
    } catch { return $false }
    return $false
}
# 需要下载时明确显示来源和目标，安装在本地工程。
function Ensure-Go {
    if (Test-Go $env:GO_BIN) { return }
    $discovered = Get-Command go -ErrorAction SilentlyContinue
    if ($discovered -and (Test-Go $discovered.Source)) { return }
    $localGo = Join-Path $ServerRoot ".tools/$GoVersion/bin/go.exe"
    if (Test-Go $localGo) { return }
    $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    switch ($architecture) {
        'X64' { $archive = "$GoVersion.windows-amd64.zip"; $sha = 'f26081f438319757f8a1b46d7d0b2c5ec7583d4038e485e0aa725cfde7885fff' }
        'Arm64' { $archive = "$GoVersion.windows-arm64.zip"; $sha = 'c507872ff21f8a7cd3c1c217b059c6f7271a4a9d8e692810ef9dd3e1f601197c' }
        default { throw '仅支持64位x64和ARM64 Windows。' }
    }
    $uri = "https://go.dev/dl/$archive"
    $destination = Join-Path $ServerRoot ".tools/$archive"
    Write-Host "来源 | Go SDK | $uri -> $destination" -ForegroundColor Cyan
    if ((Read-Host '直接回车安装；任意字符取消').Length -ne 0) { throw '已取消安装。' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $uri -OutFile $destination -UseBasicParsing -TimeoutSec 1200
    if ((Get-FileHash $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha) { throw '下载摘要不匹配，未解压。' }
    $target = Join-Path $ServerRoot ".tools/$GoVersion"
    if (Test-Path $target) { throw 'SDK目录存在但不健康；保留原目录，移走后重试。' }
    $stage = Join-Path $ServerRoot ('.tools/sdk-stage-' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $destination -DestinationPath $stage
    Move-Item -LiteralPath (Join-Path $stage 'go') -Destination $target
    Remove-Item -LiteralPath $stage
    if (-not (Test-Go $localGo)) { throw 'Go安装后健康检查失败。' }
}
# 读取隐藏密码，只在进程内短暂转换。
function Read-Password([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    if ($plain.Length -lt 12) { throw '密码至少12个字符。' }
    return $plain
}
# 初次配置与只读加载，禁止执行配置文本。
function Configure-Server {
    $config = Join-Path $ServerRoot '.runtime/config.env'
    $existingConfig = Get-Item -Force -LiteralPath $config -ErrorAction SilentlyContinue
    if ($existingConfig -and ($existingConfig.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '拒绝读取或写入链接配置。' }
    if (-not (Test-Path $config)) {
        $listen = Read-Host '监听地址 [127.0.0.1:8080]'
        if (-not $listen) { $listen = '127.0.0.1:8080' }
        $admin = Read-Password '管理员admin密码（至少12字符）'
        $customer = Read-Password '客户customer密码（至少12字符）'
        if ($admin -eq $customer) { throw '两组密码必须不同。' }
        $secureDb = Read-Host 'PostgreSQL连接串（回车使用单实例本地文件存储）' -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureDb)
        try { $database = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        $lines = @('APP_ENV=production',"LISTEN_ADDR=$listen","ADMIN_PASSWORD=$admin","DEMO_CUSTOMER_PASSWORD=$customer","DATABASE_URL=$database",'CORS_ORIGINS=')
        [IO.File]::WriteAllLines($config,$lines,(New-Object Text.UTF8Encoding($false)))
        $acl = New-Object Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true,$false)
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $config -AclObject $acl
        $admin = $null; $customer = $null; $database = $null; $lines = $null
    }
    if ((Get-Item -LiteralPath $config).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '拒绝符号链接配置。' }
    $allowed = @('APP_ENV','LISTEN_ADDR','ADMIN_PASSWORD','DEMO_CUSTOMER_PASSWORD','DATABASE_URL','CORS_ORIGINS','GOPROXY')
    foreach ($line in [IO.File]::ReadAllLines($config)) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        $pair = $line.Split(@('='),2)
        if ($pair.Length -ne 2 -or $allowed -notcontains $pair[0]) { throw '发现未知配置键。' }
        [Environment]::SetEnvironmentVariable($pair[0],$pair[1],'Process')
    }
    $env:DATA_DIR = Join-Path $ServerRoot 'data'
    $env:ADMIN_STATIC_DIR = Join-Path $ServerRoot 'admin-web'
    $env:CLIENT_STATIC_DIR = Join-Path $ServerRoot 'client-web'
    if (-not $env:GOPROXY) { $env:GOPROXY = 'https://goproxy.cn|https://proxy.golang.org|direct' }
    $env:GOTELEMETRY = 'off'
    $env:GOMODCACHE = Join-Path $ServerRoot '.tools/gomodcache'
    $env:GOCACHE = Join-Path $ServerRoot '.tools/gobuildcache'
    $env:CGO_ENABLED = '0'; $env:GOTOOLCHAIN = 'local'
}
# 编译到临时程序，成功后替换；业务数据不动。
function Build-Server {
    $source = $env:GOPROXY -replace '(https?://)[^/@]*@','$1***@' -replace '\?[^|, ]*','?...'
    Write-Host "来源 | Go依赖 | $source | go.mod/go.sum固定版本 | 缓存 $env:GOMODCACHE"
    Push-Location $ServerRoot
    try {
        & $GoExe build -trimpath -o (Join-Path $ServerRoot '.runtime/bin/server.next.exe') ./cmd/server
        if ($LASTEXITCODE -ne 0) { throw '编译失败，原程序与数据保留。' }
        Move-Item -Force -LiteralPath (Join-Path $ServerRoot '.runtime/bin/server.next.exe') -Destination (Join-Path $ServerRoot '.runtime/bin/server.exe')
    } finally { Pop-Location }
}
# 前台启动，错误可见，Ctrl+C停止。
function Start-Server {
    Write-Host "启动 | $env:LISTEN_ADDR | 管理端 /admin/ | Ctrl+C停止"
    & (Join-Path $ServerRoot '.runtime/bin/server.exe')
    if ($LASTEXITCODE -ne 0) { throw "服务退出码 $LASTEXITCODE" }
}
# 编排自述、配置和本目录部署。
function Main {
    Show-Intro # 先说明影响并等待确认。
    Test-Source # 检查平台和完整源码。
    if ($Check) { Write-Host '检查通过；未编译、安装或启动。'; return }
    Initialize-Runtime # 确认后建立日志。
    try {
        Ensure-Go # 准备可用的本地SDK。
        Configure-Server # 读取或创建配置。
        Build-Server # 编译当前Go源码。
        Start-Server # 前台运行并保留日志。
    } finally { Stop-Transcript | Out-Null }
}
try { Main } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
