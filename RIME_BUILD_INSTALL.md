# 在本地从源码打包并安装 Windows 输入法（小狼毫）

本文针对当前 `rilinic_windows` 仓库，说明如何在 Windows 上从源码构建 Rime 核心和小狼毫（Weasel）前端、生成 NSIS 安装包，并安装到本机。

> [!NOTE]
> 本项目不是 UWP/MSIX 应用。最终产物是 Windows TSF 输入法及其 NSIS 安装程序。构建入口是仓库根目录的 `build.bat`，不是 `uv build`、`npm` 或单独构建 `librime`。

## 1. 构建结果和推荐命令

在当前仓库根目录执行下面的命令，可构建适合普通 Intel/AMD Windows 电脑使用的 x86 和 x64 版本，并生成安装包：

```bat
.\build.bat boost rime data opencc weasel installer
```

成功后安装包位于：

```text
output\archives\weasel-<版本>-installer.exe
```

当前源码中的基础版本为 `0.17.4`。本地非发布构建通常还会在文件名中带上提交数和 Git 短哈希，例如：

```text
weasel-0.17.4.0.93eec2d-installer.exe
```

第一次构建前仍需完成下面的环境准备、子模块初始化和 `env.bat` 配置。

## 2. 准备构建环境

### 2.1 Visual Studio 2022

安装 Visual Studio 2022 Community，在 Visual Studio Installer 中选择“使用 C++ 的桌面开发”，并确认包含：

- MSVC v143 x64/x86 生成工具；
- Windows 10 或 Windows 11 SDK；
- C++ ATL；
- C++ MFC；
- 如果需要 ARM/ARM64 安装包，再安装对应的 MSVC ARM/ARM64 生成工具。

本仓库提供的 `env.vs2022.bat` 使用 `Visual Studio 17 2022`、`msvc-14.3` 和 `v143`。没有必要为了默认值另外安装 v142。

### 2.2 其他工具

还需要：

- Git for Windows，并安装 Git Bash；
- CMake；
- Python；
- NSIS，用于生成 `.exe` 安装包；
- Boost 1.84.0 源码。

本仓库的 CI 使用 Boost 1.84.0。推荐从 Boost 官方归档下载 1.84.0 ZIP。可以在 Developer PowerShell 中执行：

```powershell
Set-Location 'C:\Users\www\coding\20260719rilinic\rilinic_windows'
New-Item -ItemType Directory -Force '.\deps' | Out-Null

$boostArchive = Join-Path $env:TEMP 'boost_1_84_0.zip'
$boostUrl = 'https://archives.boost.io/release/1.84.0/source/boost_1_84_0.zip'
Invoke-WebRequest -Uri $boostUrl -OutFile $boostArchive

$expectedHash = 'cc77eb8ed25da4d596b25e77e4dbb6c5afaac9cddd00dc9ca947b6b268cc76a4'
$actualHash = (Get-FileHash -LiteralPath $boostArchive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw "Boost 压缩包校验失败：$actualHash"
}

Expand-Archive -LiteralPath $boostArchive -DestinationPath '.\deps' -Force
Test-Path '.\deps\boost_1_84_0\boost'
Test-Path '.\deps\boost_1_84_0\bootstrap.bat'
```

最后两条命令都应输出 `True`。下载完成后，`env.bat` 中应配置：

```bat
set BOOST_ROOT=%WEASEL_ROOT%\deps\boost_1_84_0
```


`build.bat boost` 会自行运行 `bootstrap.bat` 和 `b2`，不需要预先手工编译 Boost。


### 安装nsis

仓库也提供 `install_nsis.bat`，它会联网下载 NSIS 3.08 并静默安装。执行它会安装第三方软件，因此请先确认脚本内容和目标机器的安装策略。

## 3. 使用正确的命令行

从开始菜单打开以下任一种 Visual Studio 开发终端，不要使用未加载 VS 环境的普通 PowerShell：

```text
Developer Command Prompt for VS 2022
Developer PowerShell for VS 2022
```

无论使用哪种终端，都必须先切换到包含 `build.bat` 的仓库根目录。当前项目的实际路径为：

```text
C:\Users\www\coding\20260719rilinic\rilinic_windows
```

使用 Developer Command Prompt（CMD）时：

```bat
cd /d C:\Users\www\coding\20260719rilinic\rilinic_windows
build.bat boost rime data opencc weasel installer
```

使用 Developer PowerShell 时：

```powershell
Set-Location 'C:\Users\www\coding\20260719rilinic\rilinic_windows'
.\build.bat boost rime data opencc weasel installer
```

看到提示符 `PS C:\Users\www>` 时，表示仍在用户主目录，不是项目目录。PowerShell 也不会默认搜索当前目录中的脚本，所以即使已经进入项目目录，也要写 `.\build.bat`，不能只写 `build.bat`。

本文后续以 CMD 语法展示环境检查命令；所有 `.\build.bat` 和 `.\xbuild.bat` 命令同时适用于 Developer PowerShell。

确认关键工具可用：

```bat
where msbuild
where cl
where cmake
where git
where bash
where python
```

再检查 NSIS：

```bat
if exist "%ProgramFiles(x86)%\NSIS\Bin\makensis.exe" (echo NSIS OK) else (echo NSIS NOT FOUND)
```

如果找不到 `msbuild` 或 `cl`，通常是没有使用 Visual Studio Developer Command Prompt，或者未安装 C++ 工作负载。

## 4. 初始化源码子模块

当前项目通过 Git 子模块固定 `librime` 和 `plum` 的源码版本。在仓库根目录执行：

```bat
git submodule update --init --recursive
git submodule status
```

正常情况下，`librime` 和 `plum` 对应行的最前面不应是 `-`。如果仓库尚未克隆，也可以从一开始递归克隆：

```bat
git clone --recursive <本项目仓库地址> rilinic_windows
```

不要另行克隆最新版 `librime` 覆盖子模块；当前提交记录的子模块版本才与本项目匹配。

## 5. 配置 `env.bat`

本仓库已经提供 VS2022 配置模板。复制后再修改：

```bat
copy /Y env.vs2022.bat env.bat
notepad env.bat
```

推荐配置如下：

```bat
rem 本文件位于 rilinic_windows 根目录
set WEASEL_ROOT=%CD%

rem 必须与实际解压目录一致
set BOOST_ROOT=%WEASEL_ROOT%\deps\boost_1_84_0

set BJAM_TOOLSET=msvc-14.3
set CMAKE_GENERATOR="Visual Studio 17 2022"
set PLATFORM_TOOLSET=v143

rem 只有相关工具尚未进入 PATH 时才需要这一行；末尾分号不能省略
set DEVTOOLS_PATH=%ProgramFiles%\Git\cmd;%ProgramFiles%\Git\usr\bin;%ProgramFiles%\CMake\bin;
```

注意：

- 原始 `env.vs2022.bat` 的默认 Boost 目录是 `deps\boost_1_78_0`，需要改成实际使用的目录；
- 路径可以放在仓库外，但 `BOOST_ROOT` 必须指向直接包含 `boost` 子目录的 Boost 根目录；
- `env.bat` 已被 `.gitignore` 忽略，通常不会被提交；
- 建议避免在依赖路径中使用中文、特殊符号或过深的目录层级。

保存后可用以下命令确认配置被正确加载：

```bat
call env.bat
echo %WEASEL_ROOT%
echo %BOOST_ROOT%
if exist "%BOOST_ROOT%\boost" (echo BOOST OK) else (echo BOOST NOT FOUND)
```

## 6. 从源码构建安装包

### 6.1 普通 x86 和 x64 构建（推荐）

在仓库根目录执行：

```bat
.\build.bat boost rime data opencc weasel installer
```

脚本会按内部固定顺序完成：

1. 编译 Weasel 使用的 Boost 静态库；
2. 从 `librime` 子模块源码构建 x64 和 Win32 版 `rime.dll`、`rime.lib`；
3. 通过 `plum` 准备内置输入方案和数据；
4. 准备 OpenCC 数据；
5. 使用 MSBuild 构建 x64 和 Win32 版 Weasel；
6. 使用 NSIS 生成安装程序。

`data` 阶段可能需要联网下载输入方案。第一次构建还会编译 librime 的第三方依赖，耗时较长是正常现象。

如果需要定位失败阶段，可以拆开执行：

```bat
.\build.bat boost
.\build.bat rime
.\build.bat data opencc
.\build.bat weasel installer
```

每条命令都应返回成功后再继续下一条。

### 6.2 包含 ARM 和 ARM64 的完整构建

只有安装了 ARM/ARM64 工具链并且确实需要跨架构发布时，才执行：

```bat
.\build.bat all
```

在本仓库中，`all` 会启用 `arm64` 标志，同时尝试构建 Win32、x64、ARM、ARM64 和 ARM64X 包装层。只想安装到普通 x64 电脑时，使用 6.1 节的命令即可。

### 6.3 xmake 构建（可选）

仓库还提供 `xbuild.bat`。它使用 xmake 构建 Weasel 前端，但 Boost、librime 和数据步骤仍会调用 `build.bat`。只有已经安装 xmake 或需要验证 xmake 构建时才使用：

```bat
.\xbuild.bat boost rime data opencc weasel installer
```

常规本地打包优先使用 `build.bat`，便于与现有 Visual Studio 工程保持一致。

## 7. 查找并安装产物

列出生成的安装包：

```bat
dir /b /o-d output\archives\weasel-*-installer.exe
```

使用列表中的完整文件名启动安装，例如：

```bat
start "" "output\archives\weasel-0.17.4.0.93eec2d-installer.exe"
```

不要把示例版本号原样照抄，也不要把 `*` 直接传给 `start`。安装程序会请求管理员权限。

### 7.1 使用 NSIS 安装包（推荐）

适合正常安装、升级、测试最终交付物和分发给其他电脑。安装界面会把编译后的输入法文件复制到安装目录并注册 Windows 输入法。

### 7.2 直接安装 `output` 构建目录（开发测试）

如果只是本机快速验证，不必每次都重新生成 NSIS 包：

```bat
cd /d C:\path\to\rilinic_windows\output
install.bat /s
```

参数含义：

- `/s`：注册为简体中文输入法，这是默认值；
- `/t`：注册为繁体中文输入法。

例如：

```bat
install.bat /t
```

脚本会停止旧服务、准备预设方案、请求管理员权限、注册输入法并重新启动 `WeaselServer.exe`。这种方式直接依赖当前 `output` 目录，不适合分发给其他电脑。

## 8. 验证安装

安装完成后：

1. 打开 Windows“设置 → 时间和语言 → 语言和区域”；
2. 检查对应中文语言的键盘列表中是否出现“小狼毫”；
3. 用 `Win + Space` 切换到小狼毫；
4. 打开记事本，输入拼音验证候选框和上屏功能。

用户配置、词库和自定义方案默认位于：

```text
%APPDATA%\Rime
```

修改 YAML 配置或词库后，需要从开始菜单运行“小狼毫输入法 → 重新部署”，或者执行安装目录中的：

```bat
WeaselDeployer.exe /deploy
```

如果输入法没有立即出现，可先重新部署并重启 Weasel 服务；仍未出现时，注销并重新登录 Windows 后再次检查语言设置。

## 9. 修改源码后的快速迭代

只修改 Weasel C++ 前端代码，且 Boost、librime 和数据已经构建成功时：

```bat
.\build.bat weasel
```

重新生成最终安装包：

```bat
.\build.bat weasel installer
```

修改了 `librime` 子模块源码时：

```bat
.\build.bat rime weasel installer
```

需要强制重新构建 Weasel 的 MSBuild 项目时：

```bat
.\build.bat rebuild weasel installer
```

`xbuild.bat clean` 只用于清理 xmake 的 `build` 目录，不等同于清理传统 MSBuild 和 librime 的所有产物。`build.bat rime` 本身会先清理 librime 的相关构建缓存。

## 10. 常见问题

### 10.1 `Boost not found`

检查：

```bat
echo %BOOST_ROOT%
dir "%BOOST_ROOT%\boost"
dir "%BOOST_ROOT%\bootstrap.bat"
```

常见原因是复制 `env.vs2022.bat` 后没有把默认的 `boost_1_78_0` 改成实际目录。

### 10.2 `MSB8020`、找不到 v143 或找不到 Windows SDK

在 Visual Studio Installer 中补装 v143 x64/x86 生成工具和 Windows SDK，然后重新打开 Developer Command Prompt。不要仅修改 `PLATFORM_TOOLSET` 来掩盖未安装的组件。

### 10.3 `librime\build.bat` 不存在

子模块没有初始化。执行：

```bat
git submodule update --init --recursive
```

### 10.4 数据阶段找不到 `bash`

安装 Git for Windows，并确认：

```bat
where bash
```

如果仍找不到，检查 `env.bat` 中 `DEVTOOLS_PATH` 的 Git 路径及末尾分号。

### 10.5 数据下载失败

`build.bat data` 会调用 `plum\rime-install`，可能访问外部源码或数据仓库。检查网络、代理、Git 和 Bash，再单独重试：

```bat
.\build.bat data
```

### 10.6 找不到 `makensis.exe`

当前脚本使用固定路径：

```text
%ProgramFiles(x86)%\NSIS\Bin\makensis.exe
```

把 NSIS 安装到默认位置，或根据本机安装路径同步修改 `build.bat`（使用 xmake 时还要修改 `xbuild.bat`）。仅把其他目录加入 PATH 不能改变脚本中的固定调用路径。

### 10.7 Weasel 文件正在使用或链接失败

`build.bat` 会尝试执行 `output\WeaselServer.exe /q` 停止旧服务。如果仍有进程占用文件，可从任务管理器结束旧的 Weasel 进程，或先执行：

```bat
.\output\stop_service.bat
```

然后重新构建。

### 10.8 `output\archives` 中没有安装包

确认构建命令包含 `installer`，并向上检查控制台中最早出现的错误。重点查看：

- Boost 路径或编译失败；
- 子模块未初始化；
- `msbuild`、CMake、Bash 或 Python 不可用；
- v143、SDK 或目标架构工具链缺失；
- NSIS 未安装到脚本使用的位置；
- 数据下载失败。

## 11. 本仓库中的相关文件

- `build.bat`：MSBuild 主构建入口；
- `xbuild.bat`：xmake 构建入口；
- `env.vs2022.bat`：VS2022/v143 环境模板；
- `env.bat.template`：通用环境模板，默认值偏向 v142；
- `weasel.sln`：Visual Studio 解决方案；
- `librime`：Rime 核心源码子模块；
- `plum`：输入方案和数据管理子模块；
- `output\install.nsi`：NSIS 安装脚本；
- `output\install.bat`：开发目录直装脚本；
- `output\archives`：最终安装包目录。

按照本文的推荐路径，最短流程是：安装工具 → 初始化子模块 → 准备 Boost → 配置 `env.bat` → 执行 `.\build.bat boost rime data opencc weasel installer` → 安装 `output\archives` 中的新安装包。
