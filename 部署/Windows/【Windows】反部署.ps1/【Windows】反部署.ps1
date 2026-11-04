# 脚本自述：按本工程Windows原点精确反部署，fzf默认备份数据后清理本次新建源数据。
# 只处理已记录且摘要未变的资源；原有data、共享资源、外部PostgreSQL与未知旧部署保留并报告。
param([switch]$Check,[switch]$Plan)
$ErrorActionPreference = 'Stop'
$ServerRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../代码/后端/后端代码'))

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

function Show-UndoIntroduction {
    Write-Host '知序服务 | Windows 反部署' -ForegroundColor Red
    Write-Host '按部署原点核对 .runtime、.tools、data，默认备份至后端实现目录外的 UndeploymentBackups，再清理本次新建的数据。' -ForegroundColor Blue
    Write-Host '先关闭部署运行窗口。原有数据/共享或已改变资源保留，外部PostgreSQL没有原生备份能力时停止全部操作。'
    Write-Host 'fzf方向键/Tab选择；Esc取消。最后确认默认取消，选中执行后还须按空格复核。'
    Write-Host '取消不停止进程、不创建日志/备份或修改业务。原点及重试记录保留在 .deployment-state/windows。'
    Write-Host ('目标：' + $ServerRoot)
    if ($Check -or $Plan) { return }
    if ([Console]::IsInputRedirected) { throw '请使用交互终端。' }
    if ((Read-Host '按回车审阅；任意字符取消').Length) { throw '已取消。' }
}

function Find-UndoSelector {
    $candidates = @($env:FZF_BIN)
    $command = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates += $command.Source }
    $candidates += @(Get-ChildItem -LiteralPath (Join-Path $ServerRoot '.tools') -Filter 'fzf.exe' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($candidate in $candidates) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        Assert-PlainPath $candidate
        & $candidate --version 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw '缺少健康fzf；请复用部署准备的工具或提供FZF_BIN。本入口不为反部署联网安装。'
}

function Select-UndoOption([string]$Fzf,[string[]]$Rows,[string]$Title) {
    $keys = @('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','FZF_DEFAULT_COMMAND')
    $saved = @{}
    $oldOutput = $OutputEncoding
    $oldIn = [Console]::InputEncoding
    $oldOut = [Console]::OutputEncoding
    try {
        foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,'','Process') }
        $utf8 = New-Object Text.UTF8Encoding($false)
        $OutputEncoding = $utf8
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $selection = $Rows | & $Fzf --no-multi --layout=reverse --height=45% --border '--delimiter=|' --with-nth=2 '--bind=tab:down,btab:up' "--header=$Title"
        $code = $LASTEXITCODE
    } finally {
        foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
        $OutputEncoding = $oldOutput
        [Console]::InputEncoding = $oldIn
        [Console]::OutputEncoding = $oldOut
    }
    if ($code -in @(1,130)) { return 'cancel' }
    if ($code -ne 0 -or @($selection).Count -ne 1 -or $Rows -cnotcontains $selection) { throw '选择器错误、空选或非法输出，未执行。' }
    return ($selection -split '\|',2)[0]
}

function Main {
    Show-UndoIntroduction
    if ($Check -and $Plan) { throw '-Check与-Plan不能同时使用。' }
    $receipt = Read-Origin $ServerRoot
    if (-not $receipt) { throw '没有本工程Windows原点；旧部署归属无法证明，未删除。' }
    if ($Check -or $Plan) {
        Write-Host ('原点状态：' + $receipt.status)
        Write-Host ('原有data：' + $receipt.dataExisted + '；数据库：' + $receipt.database)
        Write-Host '计划：只核对清单内资源；备份完整data及账户配置。备份损坏、内容变化、未知锁、外部数据库均保留并停止。'
        return
    }
    if ($env:OS -ne 'Windows_NT') { throw '实际反部署仅支持Windows；当前系统仅支持-Check/-Plan。' }
    if ($receipt.status -eq 'complete') { Write-Host '此原点已完成，无需重复清理。'; return }
    $selector = Find-UndoSelector
    $policy = Select-UndoOption $selector @('backup|数据库数据备份（默认）：完整data和配置，验证后清理本次新建源数据','clear|数据库数据清零：不备份，不可恢复','cancel|取消并保留当前状态') '选择数据策略；Esc取消'
    if ($policy -eq 'cancel') { return }
    Write-Host ('准确数据范围：' + (Join-Path $ServerRoot 'data'))
    Write-Host ('程序/配置/依赖范围：' + (Join-Path $ServerRoot '.runtime') + '；' + (Join-Path $ServerRoot '.tools'))
    Write-Host ('原有data：' + $receipt.dataExisted + '；原有/共享/未知对象保留；原点文件不清除。')
    $confirm = Select-UndoOption $selector @('cancel|取消，保留当前状态','execute|确认按上述数据策略反部署') '危险操作：默认取消；请核对范围'
    if ($confirm -ne 'execute') { return }
    Write-Host '最后复核：按空格执行；其它键取消。' -ForegroundColor Red
    if ([Console]::ReadKey($true).Key -ne [ConsoleKey]::Spacebar) { return }
    Invoke-OriginUndo $ServerRoot $policy
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Main } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
}
