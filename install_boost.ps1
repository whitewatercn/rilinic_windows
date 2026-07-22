[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# 使用 .NET 直接计算 SHA-256，兼容缺少 Get-FileHash 的旧版 PowerShell。
function Get-FileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha256.Dispose()
    }
}

# 校验缓存文件。文件不存在、尚未下载完成或无法读取时均返回失败。
function Test-BoostArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256
    )

    if (-not [System.IO.File]::Exists($Path)) {
        return $false
    }

    try {
        return (Get-FileSha256 -Path $Path) -eq $ExpectedSha256
    }
    catch {
        return $false
    }
}

# 使用 .NET ZIP API 解压，以兼容缺少 Expand-Archive 的旧版 PowerShell。
function Expand-BoostArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$BoostVersion
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # 目标路径末尾保留目录分隔符，防止 ZIP 条目越过解压根目录。
    $destinationRoot = [System.IO.Path]::GetFullPath($DestinationPath) + [System.IO.Path]::DirectorySeparatorChar
    $activity = '正在解压 Boost ' + $BoostVersion
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)

    try {
        $totalEntries = $archive.Entries.Count
        $processedEntries = 0
        $lastPercent = 0

        Write-Progress -Id 1 -Activity $activity -Status ('0 / ' + $totalEntries + ' 个条目') -PercentComplete 0

        foreach ($entry in $archive.Entries) {
            $entryPath = $entry.FullName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $targetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destinationRoot, $entryPath))

            # 拒绝包含 ..、绝对路径或盘符跳转的恶意 ZIP 条目。
            if (-not $targetPath.StartsWith($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw ('ZIP 中包含不安全路径：' + $entry.FullName)
            }

            if ([System.String]::IsNullOrEmpty($entry.Name)) {
                [System.IO.Directory]::CreateDirectory($targetPath) | Out-Null
            }
            else {
                $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
                [System.IO.Directory]::CreateDirectory($targetDirectory) | Out-Null

                # 覆盖已存在文件，使中断后的再次解压可以继续完成。
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            }

            $processedEntries++
            if ($totalEntries -eq 0) {
                $percent = 100
            }
            else {
                $percent = [int][System.Math]::Floor(($processedEntries * 100.0) / $totalEntries)
            }

            # 每增加一个百分点刷新一次，避免 8 万多个条目逐个刷新拖慢解压。
            if ($percent -gt $lastPercent) {
                Write-Progress `
                    -Id 1 `
                    -Activity $activity `
                    -Status ($processedEntries.ToString() + ' / ' + $totalEntries.ToString() + ' 个条目') `
                    -CurrentOperation $entry.FullName `
                    -PercentComplete $percent
                $lastPercent = $percent
            }
        }
    }
    finally {
        Write-Progress -Id 1 -Activity $activity -Completed
        $archive.Dispose()
    }
}

# 如果当前终端尚未加载 MSVC，则通过 vswhere 定位可用的 VS 2022。
function Find-VsDevCmd {
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) {
        return $null
    }

    $vswhereCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    )
    $vswhere = $vswhereCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ([System.String]::IsNullOrWhiteSpace($vswhere)) {
        throw '未找到 vswhere.exe。请安装 Visual Studio 2022 的“使用 C++ 的桌面开发”工作负载。'
    }

    # pwsh 7.6 在原生命令直接接 PowerShell 管道时不会更新 $LASTEXITCODE，
    # 因此先单独执行命令并保存退出码，再从文本输出中选择第一条路径。
    $installationPaths = & $vswhere `
        -latest `
        -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    $vswhereExitCode = $LASTEXITCODE
    $installationPath = $installationPaths | Select-Object -First 1

    if ($vswhereExitCode -ne 0 -or [System.String]::IsNullOrWhiteSpace($installationPath)) {
        throw 'Visual Studio 2022 尚未安装 MSVC v143 x64/x86 工具。请在 Visual Studio Installer 中修改安装，并勾选“使用 C++ 的桌面开发”。'
    }

    $vsDevCmd = Join-Path $installationPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $vsDevCmd)) {
        throw ('未找到 Visual Studio 开发环境脚本：' + $vsDevCmd)
    }

    return $vsDevCmd
}

try {
    # 读取调用者传入的环境变量，并为未设置项提供默认值。
    $rimeRoot = $env:RIME_ROOT
    if ([System.String]::IsNullOrWhiteSpace($rimeRoot)) {
        $rimeRoot = (Get-Location).Path
    }
    $rimeRoot = [System.IO.Path]::GetFullPath($rimeRoot)

    $boostVersion = $env:boost_version
    if ([System.String]::IsNullOrWhiteSpace($boostVersion)) {
        $boostVersion = '1.84.0'
    }
    if ($boostVersion -ne '1.84.0') {
        throw '本脚本目前仅支持 Boost 1.84.0。'
    }

    $boostVersionPath = $boostVersion.Replace('.', '_')
    $boostRoot = $env:BOOST_ROOT
    if ([System.String]::IsNullOrWhiteSpace($boostRoot)) {
        $boostRoot = Join-Path (Join-Path $rimeRoot 'deps') ('boost_' + $boostVersionPath)
    }
    $boostRoot = [System.IO.Path]::GetFullPath($boostRoot)

    $buildScript = Join-Path $rimeRoot 'build.bat'
    if (-not (Test-Path -LiteralPath $buildScript)) {
        throw ('项目根目录中未找到 build.bat：' + $rimeRoot)
    }

    # 在下载大文件前确认 C++ 工具链，避免最后才发现无法编译。
    $vsDevCmd = Find-VsDevCmd

    $headersPath = Join-Path $boostRoot 'boost'
    $bootstrapPath = Join-Path $boostRoot 'bootstrap.bat'
    $sourceReady = (Test-Path -LiteralPath $headersPath) -and (Test-Path -LiteralPath $bootstrapPath)

    if (-not $sourceReady) {
        $boostParent = [System.IO.Path]::GetDirectoryName($boostRoot)
        [System.IO.Directory]::CreateDirectory($boostParent) | Out-Null

        $archivePath = Join-Path $boostParent ('boost_' + $boostVersionPath + '.zip')
        $downloadUrl = 'https://archives.boost.io/release/' + $boostVersion + '/source/boost_' + $boostVersionPath + '.zip'
        $expectedSha256 = 'cc77eb8ed25da4d596b25e77e4dbb6c5afaac9cddd00dc9ca947b6b268cc76a4'

        $archiveReady = Test-BoostArchive -Path $archivePath -ExpectedSha256 $expectedSha256
        if ($archiveReady) {
            Write-Host '现有 Boost 压缩包完整，跳过下载。'
        }
        else {
            $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
            if (-not $curl) {
                throw '未找到 curl.exe，无法进行断点续传下载。现有的部分文件已保留。'
            }

            if ([System.IO.File]::Exists($archivePath)) {
                $existingLength = (Get-Item -LiteralPath $archivePath).Length
                Write-Host ('从 ' + $existingLength + ' 字节处继续下载 Boost ' + $boostVersion + '……')
            }
            else {
                Write-Host ('正在下载 Boost ' + $boostVersion + '……')
            }

            $curlArguments = @(
                '--location',
                '--fail',
                '--retry', '5',
                '--retry-delay', '2',
                '--continue-at', '-',
                '--output', $archivePath,
                $downloadUrl
            )
            & $curl.Source @curlArguments
            if ($LASTEXITCODE -ne 0) {
                throw ('Boost 下载或续传失败。部分文件已保留，重新运行脚本即可续传：' + $archivePath)
            }

            Write-Host '正在校验 Boost 压缩包……'
            $actualSha256 = Get-FileSha256 -Path $archivePath
            if ($actualSha256 -ne $expectedSha256) {
                throw ('Boost 压缩包 SHA-256 校验失败。预期：' + $expectedSha256 + '；实际：' + $actualSha256)
            }
        }

        Expand-BoostArchive `
            -ArchivePath $archivePath `
            -DestinationPath $boostParent `
            -BoostVersion $boostVersion

        if (-not (Test-Path -LiteralPath $headersPath)) {
            throw '解压后未找到 Boost 头文件目录。'
        }
        if (-not (Test-Path -LiteralPath $bootstrapPath)) {
            throw '解压后未找到 Boost bootstrap.bat。'
        }
    }

    Write-Host 'Boost 源码已准备完成：'
    Write-Host ('  "' + $boostRoot + '"')

    # 将解析后的路径传给 build.bat，避免依赖调用者预先设置环境变量。
    $env:RIME_ROOT = $rimeRoot
    $env:BOOST_ROOT = $boostRoot

    if ($vsDevCmd) {
        Write-Host '正在初始化 Visual Studio C++ 构建环境……'
        $buildCommand = 'call "{0}" -no_logo -arch=x64 -host_arch=x64 && call "{1}" boost' -f $vsDevCmd, $buildScript
    }
    else {
        $buildCommand = 'call "{0}" boost' -f $buildScript
    }

    Push-Location $rimeRoot
    try {
        & $env:ComSpec /d /s /c $buildCommand
        $buildResult = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($buildResult -ne 0) {
        throw ('Boost 编译失败，退出码：' + $buildResult)
    }
}
catch {
    Write-Host ('错误：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

exit 0
