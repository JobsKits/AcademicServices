# 隔离夹具：仅在系统临时目录验证Windows原点、备份与精确恢复，不部署真实服务。
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ('academic-windows-undo-' + [guid]::NewGuid().ToString('N'))
if ($Fixture.StartsWith('/var/')) { $Fixture = '/private' + $Fixture }
$Count = 0

function Assert-True([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:Count++
}
function Write-Fixture([string]$Path,[string]$Value) {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Path)) -Force
    [IO.File]::WriteAllText($Path,$Value,(New-Object Text.UTF8Encoding($false)))
}
function New-Fixture([string]$Name,[bool]$ExistingData = $false) {
    $root = Join-Path $Fixture $Name
    Write-Fixture (Join-Path $root '.tools/shared') 'original-shared-sdk'
    Write-Fixture (Join-Path $root '.runtime/config.env') "DATABASE_URL=`nADMIN_PASSWORD=original-secret"
    if ($ExistingData) { Write-Fixture (Join-Path $root 'data/state.json') 'preexisting-data' }
    $lock = Enter-OriginLock $root
    try {
        Start-Origin $root
        Write-Fixture (Join-Path $root '.tools/only-this-deploy') 'new-sdk'
        Write-Fixture (Join-Path $root '.runtime/config.env') "DATABASE_URL=`nADMIN_PASSWORD=current-secret"
        Write-Fixture (Join-Path $root '.runtime/bin/server.exe') 'fake-server'
        Write-Fixture (Join-Path $root 'data/state.json') 'business-state-with-attachments'
        Complete-Origin $root ''
    } finally { Exit-OriginLock $lock }
    return $root
}
function Expect-Failure([scriptblock]$Action,[string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert-True $failed $Message
}
# 只接受真实入口标记内的函数定义，不执行部署或反部署Main。
function Get-EmbeddedOrigin([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $begin = '# BEGIN JOBS DEPLOYMENT LIFECYCLE'
    $end = '# END JOBS DEPLOYMENT LIFECYCLE'
    if (([regex]::Matches($text, '(?m)^' + [regex]::Escape($begin) + '\r?$')).Count -ne 1 -or
        ([regex]::Matches($text, '(?m)^' + [regex]::Escape($end) + '\r?$')).Count -ne 1) { throw '生命周期内嵌标记缺失或重复。' }
    $match = [regex]::Match($text, '(?ms)^' + [regex]::Escape($begin) + '\r?\n(.*?)^' + [regex]::Escape($end) + '\r?$')
    if (-not $match.Success) { throw '生命周期内嵌标记顺序错误。' }
    $errors = $null; $tokens = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($match.Groups[1].Value, [ref]$tokens, [ref]$errors)
    if ($errors) { throw '生命周期内嵌块无法解析。' }
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -isnot [Management.Automation.Language.FunctionDefinitionAst]) { throw '生命周期内嵌块混入可执行入口。' }
    }
    return $match.Groups[1].Value
}

try {
    $deploymentEntry = Join-Path $ProjectRoot '部署/Windows/【Windows】部署.ps1/【Windows】部署.ps1'
    $undeploymentEntry = Join-Path $ProjectRoot '部署/Windows/【Windows】反部署.ps1/【Windows】反部署.ps1'
    $deploymentBlock = Get-EmbeddedOrigin $deploymentEntry
    $undeploymentBlock = Get-EmbeddedOrigin $undeploymentEntry
    Assert-True ($deploymentBlock -ceq $undeploymentBlock) '部署与反部署生命周期实现不一致'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '部署/Windows/DeploymentState.psm1'))) '交付仍依赖旧生命周期模块'
    . ([scriptblock]::Create($deploymentBlock))

    $root = New-Fixture '备份与恢复 空格'
    Invoke-OriginUndo $root backup
    $receipt = Read-Origin $root
    Assert-True ($receipt.status -eq 'complete') '备份恢复未完成'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'data'))) '新建源数据未清理'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root '.tools/shared') -Raw) -ceq 'original-shared-sdk') '原有SDK被破坏'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root '.tools/only-this-deploy'))) '本次专属SDK未清理'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root '.runtime/config.env') -Raw).Contains('original-secret')) '原配置未恢复'
    Assert-True ((Get-Content -LiteralPath (Join-Path $receipt.undo.backup.path 'data/state.json') -Raw) -ceq 'business-state-with-attachments') '数据备份丢失'
    Assert-True ((Get-Content -LiteralPath (Join-Path $receipt.undo.backup.path '.runtime/config.env') -Raw).Contains('current-secret')) '备份缺少匹配配置'
    Invoke-OriginUndo $root backup
    Assert-True ((Read-Origin $root).status -eq 'complete') '重复反部署不是幂等'
    Expect-Failure { Start-Origin $root } '已完成原点不应自动覆盖或静默复用'

    $root = New-Fixture 'clear'
    Invoke-OriginUndo $root clear
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'data'))) '清零失败'
    Assert-True ($null -eq (Read-Origin $root).undo.backup) '清零意外创建了数据备份'

    $root = Join-Path $Fixture 'fresh-empty'
    $null = New-Item -ItemType Directory -Path $root
    $lock = Enter-OriginLock $root
    try {
        Start-Origin $root
        Write-Fixture (Join-Path $root '.runtime/config.env') 'DATABASE_URL='
        Write-Fixture (Join-Path $root '.runtime/bin/server.exe') 'server'
        Write-Fixture (Join-Path $root '.tools/fzf.exe') 'selector'
        Write-Fixture (Join-Path $root 'data/state.json') 'new-data'
        Complete-Origin $root ''
    } finally { Exit-OriginLock $lock }
    Invoke-OriginUndo $root backup
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root '.runtime'))) '全新运行目录未清理'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root '.tools'))) '全新专属工具目录未清理'

    $root = New-Fixture 'preexisting' $true
    Expect-Failure { Invoke-OriginUndo $root backup } '原有数据必须报告部分恢复'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root 'data/state.json') -Raw) -ceq 'business-state-with-attachments') '原有data被删'

    $root = New-Fixture 'changed'
    Write-Fixture (Join-Path $root '.runtime/bin/server.exe') 'later-user-change'
    Expect-Failure { Invoke-OriginUndo $root backup } '后续产物变化未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'data/state.json')) '产物冲突时不应删除数据'

    $root = New-Fixture 'unknown'
    Write-Fixture (Join-Path $root '.tools/other-project') 'shared-unknown'
    Expect-Failure { Invoke-OriginUndo $root clear } '共享未知文件未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root '.tools/other-project')) '未知文件被删'

    $root = New-Fixture 'postgres'
    $receipt = Read-Origin $root
    $receipt.database = 'postgresql-external'
    Save-Origin $root $receipt
    Expect-Failure { Invoke-OriginUndo $root backup } '外部PostgreSQL未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'data/state.json')) '外部DB阻断仍删了数据'

    $root = New-Fixture 'backup-fails'
    $receipt = Read-Origin $root
    $backup = Join-Path ([IO.Path]::GetDirectoryName($root)) ('UndeploymentBackups/Windows-' + $receipt.id)
    Write-Fixture (Join-Path $backup 'unrelated') 'keep'
    Expect-Failure { Invoke-OriginUndo $root backup } '备份失败未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'data/state.json')) '备份失败删除了源'
    Assert-True ((Get-Content -LiteralPath (Join-Path $backup 'unrelated') -Raw) -ceq 'keep') '覆盖了原有备份'

    $root = New-Fixture 'changed-after-snapshot'
    $receipt = Read-Origin $root
    $receipt.undo = [pscustomobject]@{ policy='clear'; backup=$null; dataHash=(Get-InventoryDigest (Get-ArtifactInventory $root @('data'))); dataDone=$false; done=@() }
    $receipt.status = 'undoing'
    Save-Origin $root $receipt
    Write-Fixture (Join-Path $root 'data/state.json') 'changed-after-confirmation'
    Expect-Failure { Invoke-OriginUndo $root clear } '数据快照变化未阻断'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root 'data/state.json') -Raw) -ceq 'changed-after-confirmation') '变化数据被删'

    $root = New-Fixture 'live-lock'
    $lock = Enter-OriginLock $root
    try { Expect-Failure { Invoke-OriginUndo $root clear } '活锁未阻断' }
    finally { Exit-OriginLock $lock }

    $root = New-Fixture 'process-identity'
    $receipt = Read-Origin $root
    $receipt.processes = @([pscustomobject]@{ pid=$PID; started='0'; path='never-match' })
    Save-Origin $root $receipt
    Expect-Failure { Invoke-OriginUndo $root clear } 'PID身份不符未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'data/state.json')) '身份不符仍清了数据'

    $root = New-Fixture 'known-stopped-marker'
    $receipt = Read-Origin $root
    $deadPid = 2147483000
    Assert-True (-not (Get-Process -Id $deadPid -ErrorAction SilentlyContinue)) '夹具PID意外存在'
    $receipt.processes = @([pscustomobject]@{ pid=$deadPid; started=[DateTime]::UtcNow.AddSeconds(-5).Ticks.ToString(); path=(Join-Path $root '.runtime/bin/server.exe') })
    $receipt.status = 'deploying'
    Save-Origin $root $receipt
    Write-Fixture (Join-Path $root 'data/.server-lock') ("pid=$deadPid`nstarted=" + [DateTime]::UtcNow.ToString('o') + "`n")
    Complete-Origin $root ''
    Assert-True ($null -ne (Read-Origin $root).stoppedMarker) '本次死进程锁证据未封存'
    Invoke-OriginUndo $root clear
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'data'))) '已记录死进程锁阻止了正常反部署'

    $root = New-Fixture 'unknown-marker'
    Write-Fixture (Join-Path $root 'data/.server-lock') 'unknown-lock'
    Expect-Failure { Invoke-OriginUndo $root clear } '未知服务锁未阻断'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root 'data/.server-lock') -Raw) -ceq 'unknown-lock') '未知服务锁被删'

    $root = New-Fixture 'corrupted-backup'
    $receipt = Read-Origin $root
    $receipt.undo = [pscustomobject]@{ policy='backup'; backup=(New-UndoBackup $root $receipt); dataHash=(Get-InventoryDigest (Get-ArtifactInventory $root @('data'))); dataDone=$false; done=@() }
    $receipt.status = 'undoing'
    Save-Origin $root $receipt
    Write-Fixture (Join-Path $receipt.undo.backup.path 'data/state.json') 'corrupted'
    Expect-Failure { Invoke-OriginUndo $root backup } '损坏备份未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'data/state.json')) '损坏备份仍删了源'

    foreach ($phase in @('prepared','retired')) {
        $root = New-Fixture ('artifact-resume-' + $phase)
        $receipt = Read-Origin $root
        $relative = '.runtime/config.env'
        $old = @($receipt.before | Where-Object path -eq $relative)[0]
        $new = @($receipt.after | Where-Object path -eq $relative)[0]
        $path = Join-Path $root $relative
        $stage = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.academic-restore-' + $receipt.id)
        $retired = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.academic-retired-' + $receipt.id)
        Copy-Item -LiteralPath (Join-Path (Get-OriginLocation $root) ('original/' + $relative)) -Destination $stage
        [IO.File]::Move($path,$retired)
        if ($phase -eq 'retired') { [IO.File]::Move($stage,$path) }
        $journal = [pscustomobject]@{ path=$relative; old=$old.hash; after=$new.hash; phase=$phase }
        $receipt.undo = [pscustomobject]@{ policy='clear'; backup=$null; dataHash=''; dataDone=$true; done=@(); fileJournal=$journal }
        $receipt.status = 'undoing'
        Save-Origin $root $receipt
        Restore-OriginFile $root $receipt $relative $old.hash $new.hash
        Assert-True ((Get-OriginFileHash $path) -ceq $old.hash) '原子移动窗口恢复失败'
        Assert-True (-not (Test-Path -LiteralPath $retired)) '恢复后遗留退休产物'
        Assert-True ($receipt.undo.fileJournal.phase -eq 'done') '文件恢复阶段未完成'
    }

    $root = New-Fixture 'cross-platform'
    [IO.File]::WriteAllText((Join-Path $root '.deployment-state/owner'),'posix')
    Expect-Failure { Invoke-OriginUndo $root clear } '跨OS原点未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'data/state.json')) '跨OS误删数据'

    $root = Join-Path $Fixture 'legacy'
    Write-Fixture (Join-Path $root 'data/state.json') 'legacy'
    Expect-Failure { Invoke-OriginUndo $root backup } '无原点旧部署未阻断'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'data/state.json')) '旧数据被误删'

    # 直接调用实际选择器函数，替身只返回受控结果；不触发控制台危险确认。
    $errors = $null; $tokens = $null
    $entryAst = [Management.Automation.Language.Parser]::ParseFile($undeploymentEntry,[ref]$tokens,[ref]$errors)
    if ($errors) { throw '实际反部署入口无法解析。' }
    $selectorFunctions = @($entryAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Select-UndoOption'
    })
    Assert-True ($selectorFunctions.Count -eq 1) '选择器函数不唯一或不可定位'
    . ([scriptblock]::Create($selectorFunctions[0].Extent.Text))
    $selector = Join-Path $Fixture 'selector.ps1'
    foreach ($code in @(1,130)) {
        Write-Fixture $selector ('$input | Out-Null; exit ' + $code)
        Assert-True ((Select-UndoOption $selector @('backup|备份','clear|清零') 'fixture') -ceq 'cancel') '取消码没有转为取消'
    }
    Write-Fixture $selector '$input | Out-Null; exit 0'
    Expect-Failure { Select-UndoOption $selector @('backup|备份','clear|清零') 'fixture' } '选择器空结果没有阻断'
    Write-Fixture $selector '$input | Out-Null; Write-Output "unexpected|illegal"; exit 0'
    Expect-Failure { Select-UndoOption $selector @('backup|备份','clear|清零') 'fixture' } '选择器非法结果没有阻断'
    Write-Fixture $selector '$input | Out-Null; exit 2'
    Expect-Failure { Select-UndoOption $selector @('backup|备份','clear|清零') 'fixture' } '选择器错误没有阻断'

    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot '部署/Windows') -Recurse -File | Where-Object Extension -in @('.ps1','.psm1')) {
        $errors = $null; $tokens = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert-True (-not $errors) ('语法错误：' + $file.Name)
    }
    Write-Host ("通过：$Count 项Windows隔离断言；未进行Windows原生桌面/ACL/实库部署验收。")
} finally {
    if (Test-Path -LiteralPath $Fixture) { Remove-Item -LiteralPath $Fixture -Recurse -Force }
}
