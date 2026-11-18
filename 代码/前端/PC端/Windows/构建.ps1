param([switch]$Build)
$ErrorActionPreference = 'Stop'
function Show-Intro {
    Write-Host '知序 Windows 原生客户端：C# Windows Forms。本机构建 self-contained win-x64 EXE 到本工程 Dist；首次还原从官方 NuGet 获取 Windows SDK引用和运行时，不安装系统级软件。'
    if (-not $Build) {
        if ([Console]::IsInputRedirected) { throw '非交互构建请加 -Build' }
        if ((Read-Host '按回车构建，输入其它内容取消') -ne '') { throw '已取消' }
    }
}
function Build-App {
    $output = Join-Path $PSScriptRoot 'Dist/win-x64'
    if ((Test-Path $output) -and ((Get-Item $output).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '拒绝链接输出目录' }
    & dotnet publish (Join-Path $PSScriptRoot 'Zhixu.Windows.csproj') -c Release -r win-x64 --self-contained true -o $output -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
    if ($LASTEXITCODE -ne 0) { throw "构建失败：$LASTEXITCODE" }
    if (-not (Test-Path (Join-Path $output 'Zhixu.exe'))) { throw '未生成 Zhixu.exe' }
    $sourceManifest = foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Extension -in @('.cs', '.csproj') }) {
        $digest = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$digest  $($file.Name)"
    }
    $sourceManifest | Set-Content -LiteralPath (Join-Path $output 'SourceManifest.sha256') -Encoding utf8
    $assets = Join-Path $output 'Assets'
    $resourceManifest = foreach ($file in Get-ChildItem -LiteralPath $assets -Recurse -File) {
        $digest = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$digest  $($file.FullName.Substring($assets.Length).TrimStart([char[]]'\/'))"
    }
    $resourceManifest | Set-Content -LiteralPath (Join-Path $output 'ResourceManifest.sha256') -Encoding utf8
    Write-Host "构建完成：$output"
}
Show-Intro
Build-App
