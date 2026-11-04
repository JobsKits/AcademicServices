# 脚本自述：在当前后端配置、准备本地Go、编译并启动，不修改全局PATH或防火墙。
# 双击同级【Windows】部署.cmd包内的同名启动器进入；首次设置两组不同密码。-Check仅读取，不下载或写入。
param([switch]$Check,[switch]$Plan)
$ErrorActionPreference = 'Stop'
$CodeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../代码'))
$DeployRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$ServerRoot = Join-Path $CodeRoot '后端/后端代码'
$LogFile = Join-Path $ServerRoot ('.runtime/logs/deploy-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$GoVersion = 'go1.27.3'
$GoExe = ''
$DeployMode = ''; $CloudflaredExe = ''; $LocalUrl = ''
$OwnServer = $null; $OwnTunnel = $null
$OriginLock = $null
# 打印自述并等待执行确认。
# BEGIN JOBS DEPLOYMENT LIFECYCLE
# 原点与恢复函数由本脚本内嵌；严格模式仅限定在生命周期函数内。
function Assert-PlainPath([string]$Path) {
    Set-StrictMode -Version 2
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "拒绝链接路径：$cursor" }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Protect-Origin([string]$Path) {
    Set-StrictMode -Version 2
    if ($env:OS -ne 'Windows_NT') { return }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Get-OriginLocation([string]$Root) {
    Set-StrictMode -Version 2
    return Join-Path $Root '.deployment-state/windows'
}

function Enter-OriginLock([string]$Root) {
    Set-StrictMode -Version 2
    $state = Join-Path $Root '.deployment-state'
    Assert-PlainPath $state
    $owner = Join-Path $state 'owner'
    Assert-PlainPath $owner
    if ((Test-Path -LiteralPath $owner) -and (Get-Content -LiteralPath $owner -Raw).Trim() -cne 'windows') { throw '另一个操作系统持有部署原点，必须回到原系统反部署。' }
    if ((Test-Path -LiteralPath $state) -and -not (Test-Path -LiteralPath $owner) -and @(Get-ChildItem -LiteralPath $state -Force).Count) { throw '状态目录已有资料但归属缺失，保留并停止。' }
    $null = New-Item -ItemType Directory -Path $state -Force
    Protect-Origin $state
    $guardPath = Join-Path $state 'windows-operation.guard'
    Assert-PlainPath $guardPath
    $guard = [IO.File]::Open($guardPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
    $path = Join-Path $state 'operation-lock'
    Assert-PlainPath $path
    if (Test-Path -LiteralPath $path) {
        $pidFile = Join-Path $path 'pid'
        Assert-PlainPath $pidFile
        $oldPid = 0
        if (-not (Test-Path -LiteralPath $pidFile) -or -not [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(),[ref]$oldPid)) { throw '操作锁身份未知，保留并停止。' }
        if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) { throw '部署或反部署正在运行，未取得操作锁。' }
        foreach ($item in Get-ChildItem -LiteralPath $path -Force) {
            if ($item.Name -notin @('pid','identity') -or $item.PSIsContainer) { throw '操作锁含未知资料，未回收。' }
            Assert-PlainPath $item.FullName
        }
        Remove-Item -LiteralPath $path -Recurse
    }
    $null = New-Item -ItemType Directory -Path $path -ErrorAction Stop
    [IO.File]::WriteAllText((Join-Path $path 'pid'),$PID.ToString())
    [IO.File]::WriteAllText((Join-Path $path 'identity'),(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString())
    if (-not (Test-Path -LiteralPath $owner)) { [IO.File]::WriteAllText($owner,'windows') }
    if ((Get-Content -LiteralPath $owner -Raw).Trim() -cne 'windows') { throw '原点归属在争锁时发生变化。' }
    return [pscustomobject]@{ path=$path; stream=$guard }
    } catch { $guard.Dispose(); throw }
}

function Exit-OriginLock($Lock) {
    Set-StrictMode -Version 2
    $Path = $Lock.path
    try {
    Assert-PlainPath $Path
    if ((Get-Content -LiteralPath (Join-Path $Path 'pid') -Raw).Trim() -cne $PID.ToString()) { throw '操作锁归属已改变，保留。' }
    Remove-Item -LiteralPath (Join-Path $Path 'pid')
    Remove-Item -LiteralPath (Join-Path $Path 'identity')
    Remove-Item -LiteralPath $Path
    } finally { $Lock.stream.Dispose() }
}

function Get-ArtifactInventory([string]$Root,[string[]]$Parts = @('.runtime','.tools')) {
    Set-StrictMode -Version 2
    $rows = @()
    foreach ($part in $Parts) {
        $path = Join-Path $Root $part
        Assert-PlainPath $path
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $rootItem = Get-Item -LiteralPath $path -Force
        $items = @($rootItem)
        if ($rootItem.PSIsContainer) { $items += @(Get-ChildItem -LiteralPath $path -Recurse -Force) }
        foreach ($item in $items) {
            Assert-PlainPath $item.FullName
            $relative = $item.FullName.Substring($Root.TrimEnd('\','/').Length + 1).Replace('\','/')
            if ($item.PSIsContainer) { $hash = 'directory' } else { $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
            $sddl = ''
            if ($env:OS -eq 'Windows_NT') { $sddl = (Get-Acl -LiteralPath $item.FullName).Sddl }
            $rows += [pscustomobject]@{ path=$relative; hash=$hash; acl=$sddl }
        }
    }
    return @($rows | Sort-Object path)
}

function Get-InventoryDigest($Rows,[switch]$IncludeAcl) {
    Set-StrictMode -Version 2
    $text = (@($Rows | Where-Object { $null -ne $_ } | Sort-Object path | ForEach-Object { $_.path + '|' + $_.hash + $(if ($IncludeAcl) { '|' + $_.acl } else { '' }) }) -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Save-Origin([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $directory = Get-OriginLocation $Root
    Assert-PlainPath $directory
    $path = Join-Path $directory 'receipt.json'
    $temporary = Join-Path $directory ('receipt-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary,($Receipt | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Read-Origin([string]$Root) {
    Set-StrictMode -Version 2
    $owner = Join-Path $Root '.deployment-state/owner'
    Assert-PlainPath $owner
    if ((Test-Path -LiteralPath $owner) -and (Get-Content -LiteralPath $owner -Raw).Trim() -cne 'windows') { throw '原点属于另一个操作系统，请使用该系统的反部署入口。' }
    $path = Join-Path (Get-OriginLocation $Root) 'receipt.json'
    Assert-PlainPath $path
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $receipt = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($receipt.schema -ne 1 -or $receipt.root -cne $Root -or $receipt.id -notmatch '^[a-f0-9]{32}$') { throw '部署原点与当前工程不匹配，未修改。' }
    foreach ($row in @(@($receipt.before) + @($receipt.after) | Where-Object { $null -ne $_ })) {
        if ($row.path -notmatch '^(\.runtime|\.tools)(/[^/]+)*$' -or $row.path -match '(^|/)\.\.?(/|$)' -or $row.path.Contains('\') -or $row.path.Contains(':')) { throw '原点含越界路径。' }
        if ($row.hash -notmatch '^(directory|[A-F0-9]{64})$') { throw '原点摘要无效。' }
    }
    return $receipt
}

function Copy-OriginFiles([string]$Root,$Rows,[string]$Destination) {
    Set-StrictMode -Version 2
    foreach ($row in @($Rows | Where-Object { $null -ne $_ } | Sort-Object { $_.path.Length })) {
        $source = Join-Path $Root $row.path
        $target = Join-Path $Destination $row.path
        Assert-PlainPath $source
        Assert-PlainPath $target
        if ($row.hash -eq 'directory') { $null = New-Item -ItemType Directory -Path $target -Force }
        else {
            $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force
            Copy-Item -LiteralPath $source -Destination $target
            if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $row.hash -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $row.hash) { throw '原点复制时文件变化，未开始部署。' }
        }
    }
}

function Start-Origin([string]$Root) {
    Set-StrictMode -Version 2
    $receipt = Read-Origin $Root
    if ($receipt -and $receipt.status -ne 'complete') {
        if ($receipt.status -ne 'deployed') { throw '上轮部署或反部署未完成，请先按原点核对恢复；禁止覆盖依据。' }
        $current = Get-ArtifactInventory $Root
        if ((Get-InventoryDigest $current -IncludeAcl) -cne (Get-InventoryDigest $receipt.after -IncludeAcl)) { throw '上轮产物已被后续修改，请先核对反部署原点，不覆盖后续内容。' }
        $receipt.status = 'deploying'
        Save-Origin $Root $receipt
        return
    }
    $directory = Get-OriginLocation $Root
    Assert-PlainPath $directory
    if ($receipt) {
        throw '此原点已完成反部署。重新部署前请把整个 .deployment-state 私密归档到项目外，保留审计；不自动覆盖或复用旧原点。'
    } elseif (Test-Path -LiteralPath $directory) { throw '原点目录无有效收据，保留以供人工核查。' }
    $before = @(Get-ArtifactInventory $Root)
    $null = New-Item -ItemType Directory -Path $directory
    Protect-Origin $directory
    $receipt = [pscustomobject]@{ schema=1; id=[guid]::NewGuid().ToString('N'); root=$Root; status='preparing'; before=$before; after=@(); dataExisted=(Test-Path -LiteralPath (Join-Path $Root 'data')); database='file'; processes=@(); undo=$null }
    Save-Origin $Root $receipt
    Copy-OriginFiles $Root $before (Join-Path $directory 'original')
    $receipt.status = 'deploying'
    Save-Origin $Root $receipt
}

function Complete-Origin([string]$Root,[string]$DatabaseURL) {
    Set-StrictMode -Version 2
    $receipt = Read-Origin $Root
    if (-not $receipt -or $receipt.status -ne 'deploying') { throw '部署原点未开始，禁止伪造完成记录。' }
    $receipt.after = @(Get-ArtifactInventory $Root)
    $receipt.database = $(if ($DatabaseURL) { 'postgresql-external' } else { 'file' })
    $receipt | Add-Member -MemberType NoteProperty -Name stoppedMarker -Value (Get-OwnedStoppedMarker $Root $receipt) -Force
    $receipt.status = 'deployed'
    Save-Origin $Root $receipt
}

# Windows强制结束子进程可能留下O_EXCL标记；仅封存同一收据进程所写且已死亡的标记。
function Get-OwnedStoppedMarker([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $marker = Join-Path $Root 'data/.server-lock'
    Assert-PlainPath $marker
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { return $null }
    $hash = Get-OriginFileHash $marker
    $text = [IO.File]::ReadAllText($marker)
    $match = [regex]::Match($text,'\Apid=([0-9]+)\r?\nstarted=([^\r\n]+)\r?\n\z')
    if (-not $match.Success) { return $null }
    $markerPid = 0
    if (-not [int]::TryParse($match.Groups[1].Value,[ref]$markerPid) -or $markerPid -lt 1) { return $null }
    $rows = @($Receipt.processes | Where-Object { $_.pid -eq $markerPid -and $_.path -ieq (Join-Path $Root '.runtime/bin/server.exe') })
    if ($rows.Count -ne 1 -or (Get-Process -Id $markerPid -ErrorAction SilentlyContinue)) { return $null }
    $time = [DateTimeOffset]::MinValue
    $stamp = [regex]::Replace($match.Groups[2].Value,'(\.\d{7})\d+','$1')
    if (-not [DateTimeOffset]::TryParse($stamp,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$time)) { return $null }
    $processTicks = 0L
    if (-not [long]::TryParse($rows[0].started,[ref]$processTicks) -or $time.UtcDateTime.Ticks -lt $processTicks -or $time.UtcDateTime -gt [DateTime]::UtcNow.AddSeconds(1)) { return $null }
    if ((Get-OriginFileHash $marker) -cne $hash) { return $null }
    return [pscustomobject]@{ pid=$markerPid; hash=$hash; started=$rows[0].started }
}

function Add-OriginProcess([string]$Root,$Process) {
    Set-StrictMode -Version 2
    $receipt = Read-Origin $Root
    $Process.Refresh()
    if ($Process.HasExited) { return }
    $receipt.processes = @($receipt.processes) + @([pscustomobject]@{ pid=$Process.Id; started=$Process.StartTime.ToUniversalTime().Ticks.ToString(); path=$Process.Path })
    Save-Origin $Root $receipt
}

function Stop-OriginProcesses([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    foreach ($row in @($Receipt.processes)) {
        $process = Get-Process -Id ([int]$row.pid) -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        try {
            if ($process.StartTime.ToUniversalTime().Ticks.ToString() -cne $row.started -or $process.Path -cne $row.path) { throw 'PID已复用或身份无法证明，保留进程并停止反部署。' }
            Stop-Process -InputObject $process -ErrorAction Stop
            if (-not $process.WaitForExit(5000)) { throw '本次进程未在5秒内停止。' }
        } finally { $process.Dispose() }
    }
    # 非本入口启动的实例没有进程收据，保守阻断，不按PID文本或名称强杀。
    $data = Join-Path $Root 'data'
    $marker = Join-Path $data '.server-lock'
    if ((Test-Path -LiteralPath $marker) -and $Receipt.PSObject.Properties.Name -contains 'stoppedMarker' -and $Receipt.stoppedMarker) {
        $proof = $Receipt.stoppedMarker
        if (Get-Process -Id ([int]$proof.pid) -ErrorAction SilentlyContinue) { throw '已记录标记PID重新存活，保留锁并停止。' }
        if ((Get-OriginFileHash $marker) -cne $proof.hash) { throw '服务锁已偏离部署封存证据，保留。' }
        $retired = Join-Path (Get-OriginLocation $Root) ('stopped-server-lock-' + $Receipt.id)
        Assert-PlainPath $retired
        if (Test-Path -LiteralPath $retired) { throw '服务锁审计位置已有内容，保留并停止。' }
        [IO.File]::Move($marker,$retired)
        if ((Get-OriginFileHash $retired) -cne $proof.hash) { throw '隔离服务锁不匹配，保留审计与数据，不清理。' }
    }
    foreach ($name in @('.server-lock','.server-guard')) {
        if (Test-Path -LiteralPath (Join-Path $data $name)) { throw '数据锁仍存在；请先关闭实例并核对锁，未删除数据。' }
    }
}

function Assert-FileDatabase([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    if ($Receipt.database -ne 'file') { throw '该部署使用外部 PostgreSQL；当前入口没有数据库原生备份/清零能力，全部保留。' }
    $config = Join-Path $Root '.runtime/config.env'
    Assert-PlainPath $config
    if (Test-Path -LiteralPath $config) {
        foreach ($line in [IO.File]::ReadAllLines($config)) {
            if ($line -match '^DATABASE_URL=(.+)$') { throw '当前配置使用外部 PostgreSQL，未处理数据或产物。' }
        }
    }
}

function New-UndoBackup([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $base = Join-Path ([IO.Path]::GetDirectoryName($Root)) 'UndeploymentBackups'
    Assert-PlainPath $base
    $target = Join-Path $base ('Windows-' + $Receipt.id)
    if (Test-Path -LiteralPath $target) { throw '备份位置已存在但未登记，保留且停止，不覆盖。' }
    $null = New-Item -ItemType Directory -Path $target -Force
    Protect-Origin $target
    $rows = @(Get-ArtifactInventory $Root @('data','.runtime/config.env'))
    Copy-OriginFiles $Root $rows $target
    $copy = @(Get-ArtifactInventory $target @('data','.runtime/config.env'))
    if ((Get-InventoryDigest $rows) -cne (Get-InventoryDigest $copy)) { throw '数据备份完整性核验失败，源数据与现有备份保留。' }
    return [pscustomobject]@{ path=$target; rows=$rows; hash=(Get-InventoryDigest $rows) }
}

function Assert-UndoSnapshot([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    if ((Get-InventoryDigest (Get-ArtifactInventory $Root) -IncludeAcl) -cne (Get-InventoryDigest $Receipt.after -IncludeAcl)) { throw '产物清单含后续变化或未知对象，保留全部业务数据与产物。' }
    foreach ($row in @($Receipt.after)) {
        $before = @($Receipt.before | Where-Object { $_.path -ceq $row.path })
        if ($before.Count -eq 1 -and $before[0].hash -ceq $row.hash -and $before[0].acl -ceq $row.acl) { continue }
        $path = Join-Path $Root $row.path
        Assert-PlainPath $path
        if ($env:OS -eq 'Windows_NT' -and (Test-Path -LiteralPath $path) -and (Get-Acl -LiteralPath $path).Sddl -cne $row.acl) { throw ('产物权限发生后续变化，已保留：' + $row.path) }
        if ($row.hash -eq 'directory') { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $row.hash) { throw "产物已改变或缺失，保留并停止：$($row.path)" }
    }
}

function Move-UndoData([string]$Root,$Receipt,[string]$Policy) {
    Set-StrictMode -Version 2
    $data = Join-Path $Root 'data'
    $retired = Join-Path $Root ('.data-retired-' + $Receipt.id)
    Assert-PlainPath $data
    Assert-PlainPath $retired
    if ($Receipt.dataExisted) { return } # 原有业务数据不属于本轮新建资源。
    if ($Receipt.undo.dataDone) {
        if (Test-Path -LiteralPath $data) { throw '反部署后原数据路径被重建，已保留。' }
        return
    }
    if ((Test-Path -LiteralPath $data) -and (Test-Path -LiteralPath $retired)) { throw '源与隔离目录同时存在，保留并停止。' }
    $source = $(if (Test-Path -LiteralPath $retired) { $retired } else { $data })
    $actual = @(Get-ArtifactInventory $Root @([IO.Path]::GetFileName($source)))
    # 统一相对根名后比较，隔离重命名不改变已确认的内容摘要。
    $normalized = @($actual | ForEach-Object { [pscustomobject]@{ path=('data' + $_.path.Substring([IO.Path]::GetFileName($source).Length)); hash=$_.hash; acl=$_.acl } })
    if ((Get-InventoryDigest $normalized) -cne $Receipt.undo.dataHash) { throw '数据已偏离确认快照，保留源与原备份，不重新备份后清零。' }
    if (Test-Path -LiteralPath $data) { [IO.Directory]::Move($data,$retired) }
    if (Test-Path -LiteralPath $retired) {
        # 移至唯一收据归属隔离目录，删除前再校验；发生改变即保留。
        $verify = @(Get-ArtifactInventory $Root @([IO.Path]::GetFileName($retired)) | ForEach-Object { [pscustomobject]@{ path=('data' + $_.path.Substring([IO.Path]::GetFileName($retired).Length)); hash=$_.hash; acl=$_.acl } })
        if ((Get-InventoryDigest $verify) -cne $Receipt.undo.dataHash) { throw '隔离数据发生变化，未删除。' }
        Remove-Item -LiteralPath $retired -Recurse -Force
    }
    $Receipt.undo.dataDone = $true
    Save-Origin $Root $Receipt
}

function Get-OriginFileHash([string]$Path) {
    Set-StrictMode -Version 2
    Assert-PlainPath $Path
    if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '预期文件位置出现了目录，保留。' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# 先准备和校验原件，再以同卷重命名替换；每个窗口都有持久化阶段可核对。
function Restore-OriginFile([string]$Root,$Receipt,[string]$Relative,[string]$OldHash,[string]$NewHash) {
    Set-StrictMode -Version 2
    $path = Join-Path $Root $Relative
    $parent = [IO.Path]::GetDirectoryName($path)
    $stage = Join-Path $parent ('.academic-restore-' + $Receipt.id)
    $retired = Join-Path $parent ('.academic-retired-' + $Receipt.id)
    $current = Get-OriginFileHash $path
    $journal = $null
    if ($Receipt.undo.PSObject.Properties.Name -contains 'fileJournal') { $journal = $Receipt.undo.fileJournal }
    if (-not $journal -or $journal.path -cne $Relative) {
        if ($journal -and $journal.phase -ne 'done') { throw '另一个文件恢复尚未结束，保留暂存现场。' }
        if ($current -ceq $OldHash) { return }
        if ($current -cne $NewHash) { throw "恢复前文件变化，已保留：$Relative" }
        if ((Get-OriginFileHash $stage) -cne 'absent' -or (Get-OriginFileHash $retired) -cne 'absent') { throw '恢复暂存名已被占用，保留且停止。' }
        $journal = [pscustomobject]@{ path=$Relative; old=$OldHash; after=$NewHash; phase='preparing' }
        $Receipt.undo | Add-Member -MemberType NoteProperty -Name fileJournal -Value $journal -Force
        Save-Origin $Root $Receipt
    }
    if ($journal.old -cne $OldHash -or $journal.after -cne $NewHash -or $journal.phase -notin @('preparing','prepared','retired','installed','done')) { throw '文件恢复阶段不匹配，保留。' }
    if ($journal.phase -eq 'preparing') {
        if ($current -cne $NewHash -or (Get-OriginFileHash $retired) -cne 'absent') { throw '准备原件前现场发生变化。' }
        if ($OldHash -ne 'absent') {
            $original = Join-Path (Get-OriginLocation $Root) ('original/' + $Relative)
            if ((Get-OriginFileHash $original) -cne $OldHash) { throw '原点副本损坏，禁止覆盖。' }
            $stageHash = Get-OriginFileHash $stage
            if ($stageHash -eq 'absent') {
                $null = New-Item -ItemType Directory -Path $parent -Force
                Copy-Item -LiteralPath $original -Destination $stage
                $stageHash = Get-OriginFileHash $stage
            }
            if ($stageHash -cne $OldHash) { throw '准备副本未通过完整性验证，原产物保留。' }
        }
        $journal.phase = 'prepared'
        Save-Origin $Root $Receipt
    }
    if ($journal.phase -eq 'prepared') {
        if ($OldHash -ne 'absent' -and (Get-OriginFileHash $stage) -cne $OldHash) { throw '退休产物前准备副本缺失或变化，保留原产物。' }
        $current = Get-OriginFileHash $path
        $retiredHash = Get-OriginFileHash $retired
        if ($current -ceq $NewHash -and $retiredHash -eq 'absent' -and $NewHash -ne 'absent') { [IO.File]::Move($path,$retired) }
        elseif ($current -ne 'absent' -or ($NewHash -ne 'absent' -and $retiredHash -cne $NewHash)) { throw '退休产物现场与已记录内容不符。' }
        $journal.phase = 'retired'
        Save-Origin $Root $Receipt
    }
    if ($journal.phase -eq 'retired') {
        $current = Get-OriginFileHash $path
        $stageHash = Get-OriginFileHash $stage
        if ($OldHash -ne 'absent') {
            if ($current -eq 'absent' -and $stageHash -ceq $OldHash) { [IO.File]::Move($stage,$path) }
            elseif ($current -cne $OldHash -or $stageHash -ne 'absent') { throw '安装原件现场不符，未覆盖。' }
        } elseif ($current -ne 'absent') { throw '目标位置被重建，已保留。' }
        $journal.phase = 'installed'
        Save-Origin $Root $Receipt
    }
    if ($journal.phase -eq 'installed') {
        if ((Get-OriginFileHash $path) -cne $OldHash -or (Get-OriginFileHash $stage) -ne 'absent') { throw '原件安装结果不匹配。' }
        $retiredHash = Get-OriginFileHash $retired
        if ($retiredHash -ne 'absent') {
            if ($retiredHash -cne $NewHash) { throw '退休产物被修改，已保留。' }
            Remove-Item -LiteralPath $retired -Force
        }
        $journal.phase = 'done'
        Save-Origin $Root $Receipt
    }
    if ((Get-OriginFileHash $path) -cne $OldHash -or (Get-OriginFileHash $stage) -ne 'absent' -or (Get-OriginFileHash $retired) -ne 'absent') { throw '文件恢复仍有遗留差异。' }
}

function Restore-OriginArtifacts([string]$Root,$Receipt) {
    Set-StrictMode -Version 2
    $all = @(@($Receipt.before | ForEach-Object { $_.path }) + @($Receipt.after | ForEach-Object { $_.path }) | Sort-Object -Unique | Sort-Object Length -Descending)
    foreach ($relative in $all) {
        if (@($Receipt.undo.done) -contains $relative) { continue }
        $old = @($Receipt.before | Where-Object { $_.path -ceq $relative })
        $new = @($Receipt.after | Where-Object { $_.path -ceq $relative })
        $path = Join-Path $Root $relative
        Assert-PlainPath $path
        if ($old.Count -and $new.Count -and $old[0].hash -ceq $new[0].hash -and $old[0].acl -ceq $new[0].acl) { continue }
        if (($new.Count -and $new[0].hash -eq 'directory') -or ($old.Count -and $old[0].hash -eq 'directory')) {
            if (-not $old.Count -and (Test-Path -LiteralPath $path)) {
                if (@(Get-ChildItem -LiteralPath $path -Force).Count) { throw "目录含未知或共享资料，已保留：$relative" }
                Remove-Item -LiteralPath $path -Force
            } elseif ($old.Count -and -not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path -Force }
        } else {
            $oldHash = $(if ($old.Count) { $old[0].hash } else { 'absent' })
            $newHash = $(if ($new.Count) { $new[0].hash } else { 'absent' })
            Restore-OriginFile $Root $Receipt $relative $oldHash $newHash
        }
        if ($old.Count -and $old[0].acl -and $env:OS -eq 'Windows_NT') {
            $acl = Get-Acl -LiteralPath $path
            $acl.SetSecurityDescriptorSddlForm($old[0].acl)
            Set-Acl -LiteralPath $path -AclObject $acl
        }
        $Receipt.undo.done = @($Receipt.undo.done) + @($relative)
        Save-Origin $Root $Receipt
    }
}

function Invoke-OriginUndo([string]$Root,[ValidateSet('backup','clear')][string]$Policy) {
    Set-StrictMode -Version 2
    $lock = Enter-OriginLock $Root
    try {
        $receipt = Read-Origin $Root
        if (-not $receipt) { throw '没有部署前原点，未猜测或删除旧部署资源。' }
        if ($receipt.status -eq 'complete') { Write-Host '此原点已完成，无需重复清理。'; return }
        if ($receipt.status -notin @('deployed','undoing')) { throw '部署未封存，保留全部现场，先核对原点。' }
        Assert-FileDatabase $Root $receipt
        Stop-OriginProcesses $Root $receipt
        if (-not $receipt.undo) {
            Assert-UndoSnapshot $Root $receipt
            $receipt.undo = [pscustomobject]@{ policy=$Policy; backup=$null; dataHash=(Get-InventoryDigest (Get-ArtifactInventory $Root @('data'))); dataDone=$false; done=@() }
            $receipt.status = 'undoing'
            Save-Origin $Root $receipt
        } elseif ($receipt.undo.policy -cne $Policy) { throw '重试须沿用已经确认的数据策略。' }
        if ($Policy -eq 'backup') {
            if (-not $receipt.undo.backup) {
                $receipt.undo.backup = New-UndoBackup $Root $receipt
                Save-Origin $Root $receipt
            }
            $backup = $receipt.undo.backup
            if ((Get-InventoryDigest (Get-ArtifactInventory $backup.path @('data','.runtime/config.env'))) -cne $backup.hash) { throw '原备份已改变，保留全部剩余对象。' }
        }
        Move-UndoData $Root $receipt $Policy
        Restore-OriginArtifacts $Root $receipt
        if ($receipt.dataExisted) { throw '本轮产物已逆向处理；部署前已存在的data已保留，属于部分恢复。原点继续保留供核对。' }
        if ((Get-InventoryDigest (Get-ArtifactInventory $Root) -IncludeAcl) -cne (Get-InventoryDigest $receipt.before -IncludeAcl)) { throw '仍有未知或变更产物，部分恢复；原点保留。' }
        $receipt.status = 'complete'
        Save-Origin $Root $receipt
        Write-Host ('反部署完成；原点：' + (Get-OriginLocation $Root))
        if ($receipt.undo.backup) { Write-Host ('数据备份：' + $receipt.undo.backup.path) }
    } finally { Exit-OriginLock $lock }
}
# END JOBS DEPLOYMENT LIFECYCLE

function Show-Intro {
    Write-Host "知序服务 | Windows 部署" -ForegroundColor Red
    Write-Host '1、自述回车后fzf选择本地部署＋内网穿透或服务器部署，Esc取消。' -ForegroundColor Blue
    Write-Host '缺少fzf/Go/cloudflared时按锁清单自动准备工程内工具并验SHA256；本地模式另确认公网。' -ForegroundColor Blue
    Write-Host '2、记录部署原点，再写 .tools、.runtime、data；反部署仅按清单处理，不改全局PATH、系统服务或防火墙。'
    Write-Host '3、编译成功后在当前窗口运行；Ctrl+C停止，业务数据保留。'
    Write-Host '4、Go模块默认goproxy.cn，失败回退官方；GOPROXY可覆盖，仅当前进程生效。'
    Write-Host "源码：$ServerRoot"
    Write-Host "日志：$LogFile"
    if ($Check -or $Plan) { return }
    if ([Console]::IsInputRedirected) { throw '请在交互终端运行。' }
    if ((Read-Host '按回车继续；任意字符取消').Length -ne 0) { throw '已取消。' }
}
# 检查源码与Windows平台。
function Test-Source {
    if ($env:OS -ne 'Windows_NT') { throw '请使用当前系统专属入口。' }
    if (-not (Test-Path (Join-Path $ServerRoot 'go.mod')) -or -not (Test-Path (Join-Path $ServerRoot 'cmd/server'))) { throw '请保持根目录部署与代码/后端/后端代码的相对结构。' }
}
# 创建本次日志和工程内运行目录。
function Initialize-Runtime {
    foreach ($part in @('.runtime','.runtime/logs','.runtime/bin','.tools','data')) {
        $existing = Get-Item -Force -LiteralPath (Join-Path $ServerRoot $part) -ErrorAction SilentlyContinue
        if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '拒绝写入链接运行目录。' }
    }
    foreach ($part in @('.runtime/logs','.tools')) {
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
    if ($discovered) { Write-Host "现有Go未通过锁定版本 $GoVersion 健康检查；保留系统安装，改用工程内SDK。" }
    $localGo = Join-Path $ServerRoot ".tools/$GoVersion/bin/go.exe"
    if (Test-Go $localGo) { return }
    $architecture = Get-ToolArchitecture
    switch ($architecture) {
        'amd64' { $archive = "$GoVersion.windows-amd64.zip"; $sha = 'f26081f438319757f8a1b46d7d0b2c5ec7583d4038e485e0aa725cfde7885fff' }
        'arm64' { $archive = "$GoVersion.windows-arm64.zip"; $sha = 'c507872ff21f8a7cd3c1c217b059c6f7271a4a9d8e692810ef9dd3e1f601197c' }
        default { throw '仅支持64位x64和ARM64 Windows。' }
    }
    $uri = "https://go.dev/dl/$archive"
    $destination = Join-Path $ServerRoot ".tools/$archive"
    Write-Host "来源 | Go SDK | $uri -> $destination" -ForegroundColor Cyan
    Write-Host '按已确认模式准备本地Go，不更改系统安装。'
    $previousTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $uri -OutFile $destination -UseBasicParsing -TimeoutSec 1200
    } finally { [Net.ServicePointManager]::SecurityProtocol = $previousTls }
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
    $allowed = @('APP_ENV','LISTEN_ADDR','ADMIN_PASSWORD','DEMO_CUSTOMER_PASSWORD','DATABASE_URL','CORS_ORIGINS','GOPROXY','PUBLIC_BASE_URL')
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
# 独立编译二维码辅助工具，失败不影响业务服务。
function Build-AccessQr {
    $script:QrReady = $false
    $script:QrBinary = Join-Path $ServerRoot '.runtime/bin/deployqr.exe'
    $script:QrOutput = Join-Path $ServerRoot ('.runtime/access-qr-' + [guid]::NewGuid().ToString('N'))
    Write-Host "来源 | 二维码编码依赖 | github.com/skip2/go-qrcode | 固定da1b6568686e + go.sum | 缓存 $env:GOMODCACHE"
    try {
        Push-Location (Join-Path $DeployRoot '公共组件/地址二维码')
        try {
            & $GoExe build -mod=readonly -trimpath -o "$QrBinary.next.exe" .
            if ($LASTEXITCODE -ne 0) { throw '辅助工具编译失败。' }
        } finally { Pop-Location }
        Move-Item -LiteralPath "$QrBinary.next.exe" -Destination $QrBinary -Force
        New-Item -ItemType Directory -Path $QrOutput | Out-Null
        $script:QrReady = $true
    } catch { Write-Host '警告：二维码辅助工具构建失败；继续部署并保留URL。' -ForegroundColor Yellow }
}
# 将页面标记失效，已另存图片无法撤销。
function Expire-AccessQr {
    if ($script:QrReady) {
        try {
            & $QrBinary --expire --output-dir $QrOutput
            if ($LASTEXITCODE -ne 0) { throw '标记失败。' }
        } catch { Write-Host '警告：请丢弃本轮旧二维码。' -ForegroundColor Yellow }
    }
}
# 仅编码访问URL；纯文本终端使用离线HTML/SVG/PNG兜底。
function Show-AccessQr([string]$BaseUrl,[string]$Title) {
    $base = $BaseUrl.TrimEnd('/')
    Write-Host "用户端（复制整行）`n$base/client/"
    Write-Host "管理端（复制整行）`n$base/admin/"
    if (-not $script:QrReady) { return }
    try {
        $qrArgs = @('--output-dir',$QrOutput,'--title',$Title,'--entry',"用户端|$base/client/",'--entry',"管理端|$base/admin/",'--terminal-width','0')
        if (Test-Path -LiteralPath (Join-Path $QrOutput 'index.html')) { Expire-AccessQr }
        & $QrBinary @qrArgs
        if ($LASTEXITCODE -ne 0) { throw '二维码参数或写入失败。' }
    } catch { Expire-AccessQr; Write-Host '警告：二维码未生成；原URL仍可复制，服务继续运行。' -ForegroundColor Yellow }
}
# 外部入口需显式配置；回环地址明确标注不能用手机访问。
function Show-ServerAccess {
    if ($env:PUBLIC_BASE_URL -and ($env:PUBLIC_BASE_URL -notmatch '^https?://[^/?#@]+(?:/[^?#@]*)?$')) { Write-Host 'PUBLIC_BASE_URL必须为不含账户、查询参数或片段的HTTP/HTTPS入口；未显示该配置值。'; return }
    if ($env:PUBLIC_BASE_URL) { Show-AccessQr $env:PUBLIC_BASE_URL '知序｜服务器访问（按配置，尚未公网验收）' }
    else {
        $port = ($env:LISTEN_ADDR -split ':')[-1]
        if ($port -match '^\d+$') {
            Write-Host '仅本机：回环地址不能供手机扫码访问；请配置PUBLIC_BASE_URL为实际HTTPS域名后重新部署。'
            Show-AccessQr "http://127.0.0.1:$port" '知序｜仅本机访问（手机不可用）'
        }
    }
}
# 前台启动，错误可见，Ctrl+C停止。
function Start-Server {
    Write-Host "启动 | $env:LISTEN_ADDR | 管理端 /admin/ | Ctrl+C停止"
    $script:OwnServer = Start-Process -FilePath (Join-Path $ServerRoot '.runtime/bin/server.exe') -WorkingDirectory $ServerRoot -NoNewWindow -PassThru
    Add-OriginProcess $ServerRoot $script:OwnServer
    Show-ServerAccess
    while (-not $OwnServer.WaitForExit(1000)) { }
    if ($OwnServer.ExitCode -ne 0) { throw "服务退出码 $($OwnServer.ExitCode)" }
}
# 当前宿主架构只映射真实存在的原生资产。
function Get-ToolArchitecture {
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture) {
        'AMD64' { return 'amd64' }
        'ARM64' { return 'arm64' }
        default { throw '仅支持64位x64与ARM64 Windows。' }
    }
}
# 健康工具直接复用；选择器须支持内部ID输出。
function Test-LocalTool([string]$Name,[string]$Candidate) {
    if (-not $Candidate -or -not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Candidate).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    $probeKeys = @('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','FZF_DEFAULT_COMMAND')
    $probeEnvironment = @{}
    if ($Name -eq 'fzf') {
        foreach ($key in $probeKeys) { $probeEnvironment[$key] = [Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,'','Process') }
    }
    try {
        & $Candidate --version 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        if ($Name -eq 'fzf') { $help = & $Candidate --help 2>$null; $flag = '--accept-nth' }
        else { $help = & $Candidate tunnel --help 2>$null; $flag = '--url' }
        if ($LASTEXITCODE -ne 0 -or -not (($help -join "`n").Contains($flag))) { return $false }
        if ($Name -eq 'cloudflared' -and (-not (($help -join "`n").Contains('--config')) -or -not (($help -join "`n").Contains('--no-autoupdate')))) { return $false }
        return $true
    } catch { return $false }
    finally { if ($Name -eq 'fzf') { foreach ($key in $probeKeys) { [Environment]::SetEnvironmentVariable($key,$probeEnvironment[$key],'Process') } } }
}
# 只从锁清单下载匹配架构的官方归档，校验后才执行。
function Ensure-LocalTool([string]$Name) {
    $override = if ($Name -eq 'fzf') { $env:FZF_BIN } else { $env:CLOUDFLARED_BIN }
    if (Test-LocalTool $Name $override) { return $override }
    $found = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found -and (Test-LocalTool $Name $found.Source)) { return $found.Source }
    $arch = Get-ToolArchitecture
    $target = Join-Path $ServerRoot ".tools/deploy-$Name-windows-$arch"
    $local = Join-Path $target "$Name.exe"
    if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '拒绝链接工具缓存。' }
    if (Test-LocalTool $Name $local) { return $local }
    $lock = Join-Path $DeployRoot 'deploy-tools.lock.tsv'
    if (-not (Test-Path -LiteralPath $lock -PathType Leaf) -or ((Get-Item -LiteralPath $lock).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '缺少可信工具锁清单。' }
    $records = @(Import-Csv -LiteralPath $lock -Delimiter "`t" | Where-Object { $_.tool -eq $Name -and $_.os -eq 'windows' -and $_.arch -eq $arch })
    if ($records.Count -ne 1) { throw "没有锁定的 $Name/windows/$arch 原生资产；未使用其它架构。请指定已验证原生 CLOUDFLARED_BIN/FZF_BIN，或改用平台README的cpolar备选。" }
    $record = $records[0]
    if ($record.url -notmatch '^https://github\.com/(junegunn/fzf|cloudflare/cloudflared)/releases/download/') { throw '工具来源不在官方锁定发布域。' }
    Write-Host "来源 | $Name $($record.version) | $($record.url) -> $target" -ForegroundColor Cyan
    Write-Host '按已确认自述准备工程内工具；不修改全局PATH或注册服务。'
    $stage = Join-Path $ServerRoot ('.tools/tool-stage-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $archive = Join-Path $stage $record.filename
    $previousTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $record.url -OutFile $archive -UseBasicParsing -TimeoutSec 300
    } finally { [Net.ServicePointManager]::SecurityProtocol = $previousTls }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sha256) { throw '工具SHA256不匹配；未解压或执行。' }
    if ($record.kind -eq 'zip') { Expand-Archive -LiteralPath $archive -DestinationPath $stage }
    elseif ($record.kind -eq 'binary') { Copy-Item -LiteralPath $archive -Destination (Join-Path $stage "$Name.exe") }
    else { throw 'Windows入口不接受该归档格式。' }
    $candidate = Join-Path $stage "$Name.exe"
    if (-not (Test-LocalTool $Name $candidate)) { throw '工具执行健康检查失败；不回退到其它架构。' }
    if (Test-Path -LiteralPath $target) { throw '工具缓存存在但不健康，已保留；请移走损坏缓存后重试。' }
    New-Item -ItemType Directory -Path $target | Out-Null
    Move-Item -LiteralPath $candidate -Destination $local
    if (-not (Test-LocalTool $Name $local)) { throw '工具发布复检失败。' }
    return $local
}
# fzf接收UTF8显示文本，仅输出local/server内部ID；局部编码和选项随后恢复。
function Select-DeploymentMode {
    $fzf = Ensure-LocalTool 'fzf'
    $savedOutput = $OutputEncoding
    $savedConsoleInput = [Console]::InputEncoding
    $savedConsoleOutput = [Console]::OutputEncoding
    $savedOpts = $env:FZF_DEFAULT_OPTS
    $savedOptsFile = $env:FZF_DEFAULT_OPTS_FILE
    $savedCommand = $env:FZF_DEFAULT_COMMAND
    try {
        $utf8 = New-Object Text.UTF8Encoding($false)
        $OutputEncoding = $utf8
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $env:FZF_DEFAULT_OPTS = ''; $env:FZF_DEFAULT_OPTS_FILE = ''; $env:FZF_DEFAULT_COMMAND = ''
        $selected = @("local`t本地部署＋内网穿透（免费临时HTTPS）", "server`t服务器部署（仅运行后端）") | & $fzf --height=45% --layout=reverse --border --no-multi "--delimiter=`t" --with-nth=2 --accept-nth=1 '--prompt=部署方式 > ' '--header=回车选择；Esc取消，不启动后端'
        $selectorCode = $LASTEXITCODE
    } finally {
        $OutputEncoding = $savedOutput
        [Console]::InputEncoding = $savedConsoleInput
        [Console]::OutputEncoding = $savedConsoleOutput
        $env:FZF_DEFAULT_OPTS = $savedOpts; $env:FZF_DEFAULT_OPTS_FILE = $savedOptsFile; $env:FZF_DEFAULT_COMMAND = $savedCommand
    }
    if ($selectorCode -eq 1 -or $selectorCode -eq 130) { throw '已取消；未准备Go、改配置或启动后端。' }
    if ($selectorCode -ne 0) { throw "fzf失败（$selectorCode），未启动业务。" }
    if (@($selected).Count -ne 1 -or $selected -isnot [string]) { throw '选择结果必须为单一内部ID。' }
    if ($selected -ceq 'local') { $script:DeployMode = 'local' }
    elseif ($selected -ceq 'server') { $script:DeployMode = 'server' }
    else { throw '选择结果为空、多行或不受支持；未启动业务。' }
    Write-Host "部署模式 | $DeployMode"
}
# 计划与检查仅读取路径和平台，不创建日志或联网。
function Show-Plan {
    Write-Host '计划：自述回车 -> 工程内fzf -> 两模式选择 -> Go/密码配置/编译。'
    Write-Host '本地：production + loopback + 同源，后端健康后建立Cloudflare Quick随机HTTPS；公网前另确认。'
    Write-Host '服务器：保留原配置，仅运行后端；不建立隧道。'
    Write-Host '健康工具复用，缺少时按部署/deploy-tools.lock.tsv下载固定官方资产并验SHA256，不改全局PATH。'
    Write-Host 'Windows ARM64没有锁定的cloudflared原生成品；现有原生工具或cpolar备选须单独核验。'
    Write-Host 'Quick免费、无SLA、200在途、无SSE、大陆可达性需实测。此计划未下载、编译、写配置或发布。'
}
# 控制台只写样式，Host输出正文，让Transcript仅记录纯文本。
function Write-TerminalLifetimeNotice {
    $message = '关闭此运行终端，服务将结束'
    $color = -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal -and -not $env:NO_COLOR -and $env:TERM -ne 'dumb'
    if ($color) { [Console]::Write(([char]27).ToString() + '[1;31m') }
    try { Write-Host $message }
    finally { if ($color) { [Console]::Write(([char]27).ToString() + '[0m') } }
}
# 公网路线只覆盖本次进程环境，不覆盖已有文件。
function Prepare-SelectedMode {
    if ($DeployMode -ne 'local') { return }
    $script:CloudflaredExe = Ensure-LocalTool 'cloudflared'
    $portText = ($env:LISTEN_ADDR -split ':')[-1]
    $portNumber = 0
    if (-not [int]::TryParse($portText,[ref]$portNumber) -or $portNumber -lt 1 -or $portNumber -gt 65535) { throw '本地监听端口必须为1至65535。' }
    $env:APP_ENV = 'production'; $env:LISTEN_ADDR = "127.0.0.1:$portNumber"; $env:CORS_ORIGINS = ''
    $script:LocalUrl = "http://$env:LISTEN_ADDR"
    Write-Host '本次将创建可公网访问的临时HTTPS入口；必须使用非默认账户密码和合成测试数据。' -ForegroundColor Yellow
    Write-Host '不改系统代理、防火墙、电源、自启。Ctrl+C撤回本次入口，保留数据；网址重建会变化。'
    Write-TerminalLifetimeNotice
    if ((Read-Host '确认发布本次临时入口，直接回车继续；其它输入取消').Length -ne 0) { throw '已取消公网发布。' }
}
# Windows CreateProcess参数引用，兼容中文、空格、反斜杠及双引号。
function ConvertTo-NativeArgument([string]$Value) {
    return '"' + [regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}
# 捕获本次Process对象和独立日志，不按进程名或端口杀进程。
function Start-OwnedProcess([string]$File,[string[]]$Arguments,[string]$Prefix) {
    $quoted = @($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ })
    $parameters = @{ FilePath=$File; WorkingDirectory=$ServerRoot; NoNewWindow=$true; PassThru=$true; RedirectStandardOutput="$Prefix.stdout.log"; RedirectStandardError="$Prefix.stderr.log" }
    if ($quoted.Count) { $parameters.ArgumentList = $quoted -join ' ' }
    $process = Start-Process @parameters
    Add-OriginProcess $ServerRoot $process
    return $process
}
# 仅回收本次直接创建的两个Process，等待有界。
function Stop-OwnedProcesses {
    foreach ($process in @($script:OwnTunnel,$script:OwnServer)) {
        if ($null -eq $process) { continue }
        try {
            $process.Refresh()
            if (-not $process.HasExited) { Stop-Process -InputObject $process -ErrorAction SilentlyContinue }
            $null = $process.WaitForExit(5000)
        } catch { Write-Host '本次子进程已结束。' }
        finally { $process.Dispose() }
    }
    $script:OwnTunnel = $null; $script:OwnServer = $null
}
# 非HTTP服务占用也拒绝；绝不发布已在运行的服务。
function Test-LocalPort {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1',[int](($env:LISTEN_ADDR -split ':')[-1]),$null,$null)
        if (-not $pending.AsyncWaitHandle.WaitOne(1000)) { return $false }
        $client.EndConnect($pending)
        return $true
    } catch { return $false }
    finally { $client.Close() }
}
# 后端健康且本次进程仍活着，才启动隧道；任一退出回收另一进程。
function Start-LocalTunnel {
    if (Test-LocalPort) { throw '本地端口已被占用；未复用、停止或公开该服务。' }
    $serverPrefix = "$LogFile.server"; $tunnelPrefix = "$LogFile.tunnel"
    $script:OwnServer = Start-OwnedProcess (Join-Path $ServerRoot '.runtime/bin/server.exe') @() $serverPrefix
    $healthy = $false
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        $OwnServer.Refresh()
        if ($OwnServer.HasExited) { throw "本次后端已退出；见 $serverPrefix.stderr.log" }
        try { $null = Invoke-WebRequest -Uri "$LocalUrl/healthz" -UseBasicParsing -TimeoutSec 1; $healthy = $true } catch { $healthy = $false }
        if ($healthy) {
            $OwnServer.Refresh()
            if ($OwnServer.HasExited) { throw '健康响应时本次后端已退出，未启动隧道。' }
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $healthy) { throw "后端健康检查超时；见 $serverPrefix.stderr.log" }
    Write-Host "后端健康 | $LocalUrl | 本次PID $($OwnServer.Id)"
    $quickConfig = Join-Path $ServerRoot ('.runtime/logs/quick-config-' + [guid]::NewGuid().ToString('N') + '.yml')
    $quickStream = [IO.File]::Open($quickConfig,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $emptyMap = [Text.Encoding]::UTF8.GetBytes("{}`n"); $quickStream.Write($emptyMap,0,$emptyMap.Length) } finally { $quickStream.Dispose() }
    $tunnelEnvironment = @{}
    foreach ($item in Get-ChildItem Env:TUNNEL_*) { $tunnelEnvironment[$item.Name] = $item.Value }
    try {
        foreach ($key in $tunnelEnvironment.Keys) { Remove-Item -LiteralPath "Env:$key" -ErrorAction Stop }
        $script:OwnTunnel = Start-OwnedProcess $CloudflaredExe @('tunnel','--config',$quickConfig,'--no-autoupdate','--url',$LocalUrl) $tunnelPrefix
    } finally { foreach ($key in $tunnelEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key,$tunnelEnvironment[$key],'Process') } }
    $deadline = 45
    if ($env:TUNNEL_START_TIMEOUT) {
        if (-not [int]::TryParse($env:TUNNEL_START_TIMEOUT,[ref]$deadline) -or $deadline -lt 1 -or $deadline -gt 300) { throw 'TUNNEL_START_TIMEOUT须为1至300秒。' }
    }
    Write-Host "等待临时HTTPS；隧道日志 $tunnelPrefix.stderr.log；Ctrl+C停止。"
    $url = ''; $elapsed = 0
    while ($true) {
        $OwnServer.Refresh(); $OwnTunnel.Refresh()
        if ($OwnServer.HasExited -or $OwnTunnel.HasExited) { throw '本次后端或隧道已退出，回收另一子进程；请检查各自日志。' }
        $logs = (Get-Content -LiteralPath "$tunnelPrefix.stdout.log","$tunnelPrefix.stderr.log" -Raw -ErrorAction SilentlyContinue) -join "`n"
        $matches = [regex]::Matches($logs,'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
        $latest = if ($matches.Count -gt 0) { $matches[$matches.Count - 1].Value } else { '' }
        if ($latest -and $latest -ne $url) {
            $url = $latest
            Show-AccessQr $url '知序｜公网临时访问入口'
            Write-TerminalLifetimeNotice
            Write-Host '请以手机移动网络验真实登录、写入刷新重读和私有文件权限，页面演示数据不算验收。'
        } elseif (-not $url -and $elapsed -ge $deadline) { throw "隧道地址超时；检查网络或按README改用cpolar；见 $tunnelPrefix.stderr.log" }
        Start-Sleep -Seconds 1; $elapsed++
    }
}

# 编排自述、模式选择和工程内运行；取消时不触发业务配置。
function Main {
    Show-Intro # 先说明影响并等待确认。
    Test-Source # 检查平台和完整源码。
    if ($Check -and $Plan) { throw 'Check和Plan不能同时使用。' }
    if ($Check) { Write-Host '检查通过；未编译、安装或启动。'; return }
    if ($Plan) { Show-Plan; return }
    $environmentKeys = @('APP_ENV','LISTEN_ADDR','ADMIN_PASSWORD','DEMO_CUSTOMER_PASSWORD','DATABASE_URL','CORS_ORIGINS','GOPROXY','DATA_DIR','ADMIN_STATIC_DIR','CLIENT_STATIC_DIR','GOTELEMETRY','GOMODCACHE','GOCACHE','CGO_ENABLED','GOTOOLCHAIN','PUBLIC_BASE_URL')
    $savedEnvironment = @{}
    foreach ($key in $environmentKeys) { $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
    $script:OriginLock = Enter-OriginLock $ServerRoot
    $originStarted = $false
    try {
        Start-Origin $ServerRoot # 在任何部署写入前保存原状态与归属。
        $originStarted = $true
        Initialize-Runtime # 确认后建立工具目录和日志。
        Select-DeploymentMode # fzf确认，取消不准备Go或业务配置。
        foreach ($part in @('.runtime/bin','data')) { New-Item -ItemType Directory -Force -Path (Join-Path $ServerRoot $part) | Out-Null }
        Ensure-Go # 复用健康SDK或准备项目内固定版本。
        Configure-Server # 初次密码配置，其后只读复用。
        Prepare-SelectedMode # 本地模式工具与公网发布确认。
        Build-Server # 编译当前Go源码。
        Build-AccessQr # 构建离线二维码，失败保留URL。
        if ($DeployMode -eq 'local') { Start-LocalTunnel } else { Start-Server }
    } finally {
        Stop-OwnedProcesses
        Expire-AccessQr
        try { Stop-Transcript | Out-Null } catch { Write-Host '日志记录尚未启动或已结束。' }
        try { if ($originStarted) { Complete-Origin $ServerRoot $env:DATABASE_URL } }
        finally {
            foreach ($key in $environmentKeys) {
                if ($null -eq $savedEnvironment[$key]) { Remove-Item -LiteralPath "Env:$key" -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key],'Process') }
            }
            Exit-OriginLock $script:OriginLock
        }
    }
}
try { Main } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
