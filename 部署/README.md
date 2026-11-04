# 后端分平台部署

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

同时复制根目录的 **代码/** 与 **部署/** 到目标机器，保留 `代码/后端/后端代码` 与 `部署/` 的相对层级，再运行对应系统入口。该目录包含单份 [**Go**](https://go.dev/) 源码、锁定依赖、独立部署脚本与已构建的Flutter页面。服务器不需要安装Flutter或Node。以下入口按系统分别独立实现，不依赖开发机其它项目。

[地址二维码](./公共组件/地址二维码/README.md)集中在[公共组件](./公共组件/README.md)。各操作系统的部署与反部署脚本分别内嵌生命周期核心，原点、互斥、进程身份、备份和恢复均由当前脚本执行，不依赖外部生命周期函数库。平台入口保留在对应系统目录。

## 一、<span id="section-1">支持矩阵与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 平台 | 运行环境 | 本轮验证 |
| --- | --- | --- |
| MacOS Intel / Apple Silicon | zsh、系统curl/tar/shasum、本地Go | 本机ARM64迁移目录实际配置/编译/启动/停止；Intel待实机 |
| Windows 10/11 / Server x64、ARM64 | 系统PowerShell、工程内Go | PowerShell语法与路径静态检查；原生运行待验 |
| Ubuntu | bash；缺工具时apt-get | 语法/静态/夹具；目标机部署待验 |
| Debian | bash；缺工具时apt-get | 同上 |
| RockyLinux | bash；缺工具时dnf | 同上 |
| Alibaba Cloud Linux | bash；缺工具时dnf | 同上 |
| Alpine | 系统sh；缺工具时apk | 同上；桌面快捷入口使用 sh，需有图形桌面与终端模拟器 |
| FreeBSD | 系统sh；缺工具时pkg | 语法/静态；目标机待验 |

**<span id="deployment-shortcuts">快捷入口与规范实现</span>**

从对应系统文件夹直接双击标有“快捷入口”的文件。下表路径以各自系统文件夹为基准；快捷入口只调用包内唯一部署实现，复用自述、确认和部署流程，不另存一套逻辑。命令行仍可直接运行规范实现。

| 系统文件夹 | 双击快捷入口 | 唯一部署实现 |
| --- | --- | --- |
| `MacOS/` | [【MacOS】双击部署（快捷入口）.command](./MacOS/【MacOS】双击部署（快捷入口）.command) | [【MacOS】部署.command/【MacOS】部署.command](./MacOS/【MacOS】部署.command/【MacOS】部署.command) |
| `Windows/` | [【Windows】双击部署（快捷入口）.cmd](./Windows/【Windows】双击部署（快捷入口）.cmd) | [【Windows】部署.ps1/【Windows】部署.ps1](./Windows/【Windows】部署.ps1/【Windows】部署.ps1) |
| `Ubuntu/` | [双击部署（快捷入口）.desktop](./Ubuntu/双击部署（快捷入口）.desktop) | [【Linux】部署.sh/【Linux】部署.sh](./Ubuntu/【Linux】部署.sh/【Linux】部署.sh) |
| `Debian/` | [双击部署（快捷入口）.desktop](./Debian/双击部署（快捷入口）.desktop) | [【Linux】部署.sh/【Linux】部署.sh](./Debian/【Linux】部署.sh/【Linux】部署.sh) |
| `RockyLinux/` | [双击部署（快捷入口）.desktop](./RockyLinux/双击部署（快捷入口）.desktop) | [【Linux】部署.sh/【Linux】部署.sh](./RockyLinux/【Linux】部署.sh/【Linux】部署.sh) |
| `AlibabaCloudLinux/` | [双击部署（快捷入口）.desktop](./AlibabaCloudLinux/双击部署（快捷入口）.desktop) | [【Linux】部署.sh/【Linux】部署.sh](./AlibabaCloudLinux/【Linux】部署.sh/【Linux】部署.sh) |
| `Alpine/` | [双击部署（快捷入口）.desktop](./Alpine/双击部署（快捷入口）.desktop) | [【Linux】部署.sh/【Linux】部署.sh](./Alpine/【Linux】部署.sh/【Linux】部署.sh) |
| `FreeBSD/` | [双击部署（快捷入口）.desktop](./FreeBSD/双击部署（快捷入口）.desktop) | [【FreeBSD】部署.sh/【FreeBSD】部署.sh](./FreeBSD/【FreeBSD】部署.sh/【FreeBSD】部署.sh) |

MacOS 与 Windows 快捷文件保留参数及退出码。Windows 快捷 CMD 直接调用 PowerShell 实现，包内 CMD 也调用同一实现；请保留现有两个脚本包。Windows 和桌面快捷入口从自身目录定位并校验唯一同名脚本包，缺失或多候选即停止，不复制部署逻辑。Linux／FreeBSD 的 `.desktop` 需要图形桌面、终端模拟器及文件管理器允许启动；Alpine 与 FreeBSD 使用系统 sh，其它 Linux 使用 bash。桌面入口要求文件管理器传入本地绝对路径，收到 `file://` 等 URI 或相对路径时停止；此时从本地文件夹启动或改用终端规范脚本。信任或允许启动由操作者在本机界面确认，脚本不默认修改信任设置或安装图形环境；无桌面服务器仍通过 SSH 运行规范脚本。

上述归档安装器覆盖amd64/arm64。Go服务还可交叉编译到其它Go支持的平台，交叉编译不等于脚本自动部署或对应系统已实机运行。没有桌面环境的服务器不存在双击动作，SSH终端执行对应脚本即可。

### 1.1、<span id="minimum-machine">最低支持机器配置</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下是当前单实例、少量数据演示的**工程部署预算**，不是硬件下限实测或并发承诺。各系统入口每次均编译 Go，正常双击或命令行部署按“脚本部署”一行准备，不能套用“仅运行二进制”的较低预算。

| 场景 | CPU | 可用内存 | 空闲 SSD 空间 | 适用范围 |
| --- | --- | --- | --- | --- |
| 仅运行预编译二进制 | 2 核 / vCPU，64 位 | 2 GiB | 10 GiB | 匹配目标系统与架构的 Go 程序＋已构建 Web，单实例文件演示；不在该机编译 |
| **正常脚本部署最低预算** | **2 核 / vCPU，64 位** | **4 GiB** | **20 GiB** | 准备 Go 1.27.3、下载依赖、源码编译并运行；不包含 Flutter / 移动端 SDK 构建 |
| Go＋数据库＋HTTPS 反代同机的建议预算 | 4 核 / vCPU，64 位 | 8 GiB | 40 GiB | 仅供低负载验证规划；需另备数据库，不是已验收的正式运营配置 |

“可用内存”指扣除操作系统与其它程序后留给本工程的余量；MacOS / Windows 图形机器整机至少 8 GiB 内存，并仍需满足脚本部署的 4 GiB 可用余量。SSD 数值是安装系统后留给工程、SDK、缓存和少量数据的空闲空间，不是整盘容量；业务附件、日志与备份增长需另外扩容。

| 系统 | 系统与处理器条件 |
| --- | --- |
| [**MacOS**](https://www.apple.com/macos/) | 13 Ventura 或更高；Intel x86-64（amd64）或 Apple Silicon（arm64），机器须受该系统支持 |
| [**Windows**](https://www.microsoft.com/windows) | Windows 10 或更高 / Windows Server 2016 或更高；x64（amd64）或 ARM64，使用与系统一致的归档并满足所选系统自身硬件门槛 |
| [**Linux**](https://www.kernel.org/) | 内核 3.2 或更高；amd64 / arm64；选择仍受安全维护且与入口匹配的 Ubuntu、Debian、RockyLinux、Alibaba Cloud Linux 或 Alpine，系统自身要求更高时从其要求 |
| [**FreeBSD**](https://www.freebsd.org/) | amd64 / arm64；选择同时处于系统安全维护期与 Go 官方支持矩阵内的版本，具体版本下限尚未实机确认 |

系统兼容条件依据 [Go 官方最低要求](https://go.dev/wiki/MinimumRequirements)及 [Go on FreeBSD 支持矩阵](https://go.dev/wiki/FreeBSD)（2026-11-02 核对）；项目脚本归档只覆盖 amd64 / arm64，不提供 32 位部署。官方工具链兼容不代表本项目已在所有系统、版本或上述下限硬件通过验收，实机状态仍以本章支持矩阵为准。

网络：首次部署需能通过 HTTPS 443 访问 Go 下载站、模块源及系统软件源；完整 SDK、依赖和 Web 产物已就绪后的本机文件演示可离线。公网低负载演示可按至少 5 Mbps 可用上行作预算，附件流量增加时另行扩容，该数值不保证响应时延或并发量。对外统一开放反代 HTTPS 443，Go 默认 8080 与数据库端口仅供本机或受控内网，脚本不代开防火墙。

存储边界：文件模式与 [**PostgreSQL**](https://www.postgresql.org/) 模式均把全部业务历史和附件聚合到同一状态，读写时还会复制、序列化整份状态；数据增长会增加内存和磁盘开销。除现有状态外，至少另留一次原子写临时副本与一份备份的空间，并监测剩余内存、磁盘和写入耗时；切换数据库不能消除聚合存储瓶颈。当前尚无下限硬件压测、生产容量或并发验收，正式运营配置须在存储方案完善后按真实数据量与负载验证。

## 二、<span id="section-2">第一次运行与配置</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 首次自述回车继续；其它字符取消。没有可交互输入会停止，不把EOF当确认。

- 检查Go 1.27.3：显式 `GO_BIN`、PATH、本目录 `.tools/go1.27.3/bin/go` 依次检查。没有匹配健康版本时下载工程内SDK，校验[官方SHA256](https://go.dev/dl/)后解压。不会更新现有全局Go。

- 缺curl/tar/摘要工具时，Linux/FreeBSD使用本机已配置软件源安装必需包，需要管理员权限与交互确认；已有健康工具复用。MacOS缺系统工具时停止并给修复说明，不盲装包管理器。

- 设置监听地址、两组不同的账户密码（MacOS 本地调试至少4字符；服务器及其它平台至少12字符）。数据库连接串可选，空为单实例文件模式。配置写 `../代码/后端/后端代码/.runtime/config.env`，POSIX权限0600、Windows限制当前账户读取。日志不输出密码。该文件为数据，不会当脚本执行；未知配置键会拒绝。

- 构建到临时二进制，成功后替换程序。前台启动、显示日志路径，按 `Ctrl+C` 停止。再次运行保留配置与数据，不清理业务目录。

首次下载需HTTPS访问Go官方与模块源。依赖拉取默认采用goproxy.cn镜像，失败回退proxy.golang.org及direct；只影响脚本当前进程的GOPROXY，不修改系统网络代理或全局Go配置。可在启动前提供GOPROXY，或在配置文件中添加同名键。来源在构建前脱敏打印，go.sum固定依赖摘要。Go版本与各归档摘要在[工具链清单](./toolchains.json)；这是2026-10-30核对的最新稳定基线，日后版本更新需复核摘要并重跑回归，不在每次部署中无条件升级。

## 三、<span id="section-3">命令与只读检查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令从本说明所在的 `部署/` 目录运行。脚本按自身位置定位源码；从其它工作目录启动时，请相应替换脚本路径：

```shell
zsh './MacOS/【MacOS】部署.command/【MacOS】部署.command' --check
bash './Ubuntu/【Linux】部署.sh/【Linux】部署.sh' --check
sh './Alpine/【Linux】部署.sh/【Linux】部署.sh' --check
sh './FreeBSD/【FreeBSD】部署.sh/【FreeBSD】部署.sh' --check
```

[**PowerShell**](https://learn.microsoft.com/powershell/)检查与启动：

```powershell
powershell.exe -NoProfile -File .\Windows\【Windows】部署.ps1\【Windows】部署.ps1 -Check
.\Windows\【Windows】部署.cmd\【Windows】部署.cmd
```

`--check`/`-Check` 仅检查平台和源码路径，不下载、不写配置、不编译或启动。正常入口需要交互，自动化CI直接通过环境配置运行已构建Go程序，见[后端说明](../代码/后端/后端代码/README.md)。脚本只配置自身运行实例，不注册系统服务或放开防火墙。

## 四、<span id="section-4">数据、迁移和常驻</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 文件模式的资料、附件、审计、幂等收据与待发送通知在 `data/state.json` 的同一原子快照中。单进程锁拒绝多个文件实例共享目录。
- [**PostgreSQL**](https://www.postgresql.org/)选项使用数据库内 `academic_runtime_state` JSONB事务聚合；脚本不会安装或创建数据库账户，填写连接串前应备好独立数据库。原29表关系DDL仅参考，当前业务未逐表写入。
- 两种存储没有自动互转。修改 `DATABASE_URL` 是切换数据源，不能当作数据迁移。需要先导出/转换/对账并完成恢复测试。
- 备份前正常停止服务。保存整个data目录与有效配置；不要只备份程序。还原前保留旧数据副本，确认密码与数据库目标匹配。
- 当前入口以前台运行便于新手发现错误，关闭窗口就会停止。需要服务器重启后自动运行时，由运维将 `.runtime/bin/server` 接入 systemd、launchd 或Windows任务计划，使用同一工作目录和环境；未在脚本内静默创建系统常驻项。

### 4.1、<span id="undeployment">成对反部署入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

每个平台分别提供反部署脚本包与标名“反部署（快捷入口）”的启动文件。部署入口负责安装与启动，反部署入口负责核对归属、处理数据和恢复资源；两者分别运行，快捷入口只转交各自唯一实现。

| 平台 | 反部署快捷入口 | 配套说明 |
| --- | --- | --- |
| MacOS | [【MacOS】双击反部署（快捷入口）.command](./MacOS/【MacOS】双击反部署（快捷入口）.command) | [反部署脚本说明](./MacOS/【MacOS】反部署.command/README.md) |
| Windows | [【Windows】双击反部署（快捷入口）.cmd](./Windows/【Windows】双击反部署（快捷入口）.cmd) | [Windows说明](./Windows/README.md#undeployment) |
| Ubuntu | [双击反部署（快捷入口）.desktop](./Ubuntu/双击反部署（快捷入口）.desktop) | [Ubuntu说明](./Ubuntu/README.md#undeployment) |
| Debian | [双击反部署（快捷入口）.desktop](./Debian/双击反部署（快捷入口）.desktop) | [Debian说明](./Debian/README.md#undeployment) |
| RockyLinux | [双击反部署（快捷入口）.desktop](./RockyLinux/双击反部署（快捷入口）.desktop) | [RockyLinux说明](./RockyLinux/README.md#undeployment) |
| AlibabaCloudLinux | [双击反部署（快捷入口）.desktop](./AlibabaCloudLinux/双击反部署（快捷入口）.desktop) | [AlibabaCloudLinux说明](./AlibabaCloudLinux/README.md#undeployment) |
| Alpine | [双击反部署（快捷入口）.desktop](./Alpine/双击反部署（快捷入口）.desktop) | [Alpine说明](./Alpine/README.md#undeployment) |
| FreeBSD | [双击反部署（快捷入口）.desktop](./FreeBSD/双击反部署（快捷入口）.desktop) | [FreeBSD说明](./FreeBSD/README.md#undeployment) |

- 部署在首次写入前记录原点、原件及资源摘要；运行资料共用一个后端目录，因此各平台通过共用归属门禁阻止相互接管。MacOS、Linux、FreeBSD和Windows的部署／反部署脚本各自内嵌本平台生命周期函数，状态协议及原点兼容规则保持一致。随项目复制时必须一并保留整个 `部署/`。
- 阅读内置自述并回车，再用 fzf 选择“数据库数据备份”（默认）或“数据库数据清零”；执行前默认取消，显式选择执行并空格复核后才进行写操作。Esc、空选、选择器异常均停止，反部署不为获取选择器自动联网安装工具。
- 默认备份覆盖文件模式的完整 `data/` 和有效账户配置；附件字节包含在 `state.json` 内，不能只备份程序。备份保存在清理范围外，逐项校验并复核源快照后才处理本项目源数据。备份包含私有业务和凭据，应按私有数据保管，不提交至仓库。
- 只停止记录中身份匹配的本次进程，只恢复本次覆盖且后态仍匹配的资源；原有、共享、归属不明或后续改动的资源保留并列明未完成项。旧部署没有原点清单时停止，不根据目录名推测归属。重复反部署使用检查点核对，不能把部分完成写成全部恢复。
- 配置了外部 [**PostgreSQL**](https://www.postgresql.org/) 时，本入口停止并保留数据及恢复依据，不能以本地文件备份代替数据库备份或清零。手动注册的常驻服务、独立隧道、反向代理、DNS及证书仍由其管理入口撤回；共享系统软件包不会整片卸载。
- `--check`／`--plan`（Windows为 `-Check`／`-Plan`）只读。语法、隔离夹具与目标机器原生双击、真实数据库反部署分别验收；未使用用户真实环境进行删除测试。

### 4.2、<span id="lifecycle-protocol">内嵌生命周期与恢复协议</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

生命周期核心直接维护在各平台部署与反部署脚本中，接受两份脚本保留相同函数；没有运行时加载的独立生命周期库，也不通过生成器再输出脚本。脚本从自身位置解析项目及后端目录，保留 `代码/` 与 `部署/` 的相对结构；依赖系统 Shell、文件复制、文件状态及 SHA256 工具，不新增 Python 或 Node 运行依赖。各系统仍通过同一后端 `.deployment-state/owner` 与 `operation-lock` 互斥，不能覆盖另一系统的原点。

MacOS、Linux 与 FreeBSD 的内嵌函数按以下阶段工作：

- `lc_begin` 在用户确认后、首次写运行资源前调用，保存 `.runtime`、`.tools` 各文件的类型、摘要、权限和恢复副本，记录原有 data 及包装进程身份。中文、空格路径可用；换行、制表符、符号链接及特殊文件会阻断操作。
- `lc_checkpoint` 在构建完成、服务启动前封存资源后态。`lc_record_process server|tunnel PID` 保存实际 PID、启动时间与命令行；身份不明、PID复用或进程无法退出时停止恢复。
- `lc_finalize` 在退出清理子进程后更新仅本轮日志、Quick配置及明确登记的本轮二维码产物摘要，再释放操作锁；构建前失败也保留现场，不能把无关资源变化静默纳入后态。
- `lc_note_external_resources` 在系统包安装前记录包管理器、请求包及原有安装状态，退出保存实际变化。共享系统包保留并返回“未完全恢复”，不宣称已完全还原环境。
- 反部署脚本自己的 `lc_undeploy_main` 使用该入口解析的 `SERVER_ROOT`、`DEPLOY_ROOT` 和 `PLATFORM_ID`；`--check`／`--plan` 只读，正常执行依次展示自述、fzf默认备份菜单、默认取消的危险菜单及空格复核。选择器和交互失败均不删除。

文件模式备份完整 `data/` 和恢复所需账户配置到后端代码目录同级的 `反部署备份/`，设置私有权限并逐项验摘要；附件已内嵌业务状态。源数据、配置或备份偏离确认快照时停止，保留源和原备份。任何移动或删除前写入 `data-pending`，分阶段重试沿用原快照；中断后的隔离源位于恢复包 `check-tree/data/`，不能当作无用文件手工清空，也不能在缺少可信恢复依据时重新备份后继续清零。

资源恢复只操作后态与清单仍一致的已归属文件。原有、共享、封存后新增或修改的对象保留并报告；本次新建目录仅为空时移除。最终逐项核对原点，仍有差异返回非零，允许核对后重试。旧部署没有清单、非空 `DATABASE_URL` 对应的外部数据库、未知服务锁及其它系统资源均保留；当前没有外部数据库原生自动备份／清零接口。活动数据锁阻断恢复；MacOS持久guard还须由系统 `lsof` 确认无人持有。

危险确认后的纯文本审计位于 `.deployment-state/posix/operations.log`，资源差异见 `current.tsv`／`restored.tsv`，数据事务与恢复包位置见 `data-pending`／`data-destination`。日志不打印账户密码或数据库连接串，状态、原件及备份包含私密配置，不能提交或公开。完成后仍保留原点审计和owner；下一次全新部署前，先将整个 `.deployment-state` 私密归档到项目外，脚本不覆盖旧原点。

Windows的内嵌函数维持同一归属边界，并保留本平台的收据、ACL、独占句柄、备份路径及服务标记核验；详细规则见[Windows反部署说明](./Windows/【Windows】反部署.ps1/README.md)。生命周期函数内部单独启用 `Set-StrictMode -Version 2`，不扩大到原有部署界面的脚本作用域。

语法及临时工程隔离用例不执行真实环境的安装或反部署，不能代替目标系统原生启动、真实数据库恢复及公网业务验收。

## 五、<span id="section-5">对外HTTPS</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认loopback只供本机。正式域名应在独立反向代理上配置HTTPS，将 `/api/v1/`、`/admin/`、`/client/` 转发到同一Go服务并保留Host。证书和域名由部署方提供，脚本不购买域名、不请求未知账户权限，不更改系统防火墙。

客户端填写 `https://域名/api/v1`。同源页面无需CORS；其它网页来源仅在 `CORS_ORIGINS` 中逐个填可信HTTPS origin，不能用 `*`。鸿蒙远程Web宿主与后端同源。公开HTTP传输登录密码不可作为正式部署方式。

## 六、<span id="section-6">目录与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
工程根目录/
├── 代码/
│   └── 后端/
│       ├── 接口契约/api.json
│       └── 后端代码/
│           ├── cmd/ / internal/ / Migrations/ / go.mod
│           ├── admin-web/ / client-web/  # 另行构建或随发布包携带
│           └── .runtime/ / .tools/ / data/  # 当前机器的配置、工具与数据
├── 部署/
│   ├── MacOS/ / Windows/ / Ubuntu/ / Debian/
│   ├── RockyLinux/ / AlibabaCloudLinux/ / Alpine/ / FreeBSD/
│   └── toolchains.json / deploy-tools.lock.tsv
├── 测试/
└── 需求/
```

复制源码给另一台机器时，不带旧机器的 `.runtime/config.env` 或 `data`，首次启动重新配置；迁移现有业务则先正常停机并按备份恢复流程明确携带数据。不要让试用数据混入正式环境。

## 七、<span id="local-tunnel">本地部署＋内网穿透</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

<strong style="color:#c62828;">关闭此运行终端，服务将结束</strong>。本地临时模式在确认公开前及地址生成后的运行日志中单独显示此提示；支持颜色的终端使用红色加粗，非终端、`TERM=dumb` 或 `NO_COLOR` 时显示纯文本，日志不含颜色控制码。当前窗口管理本次后端与隧道，关闭终端或按 `Ctrl+C` 结束本次临时服务，业务数据与账户配置保留。

复用现有电脑或服务器运行本工程，通过隧道的公网 HTTPS 地址让指定测试者访问。适用于前期少量合成数据联调；服务仍监听 `127.0.0.1:8080`，无需把监听改成 `0.0.0.0`，也无需向路由器开放 8080 或数据库端口。工具与安装包随平台选择，不能把其它系统的二进制直接拿来运行。

### 7.1、<span id="local-tunnel-start">用fzf选择本地或服务器部署</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先选择与宿主系统一致的入口，所有命令以本 `部署` 目录为基准，只运行对应一行；双击入口与命令行入口是同一套部署逻辑。

| 宿主 | 本机启动 | 隧道工具与平台说明 |
| --- | --- | --- |
| MacOS | `zsh './MacOS/【MacOS】部署.command/【MacOS】部署.command'` | [Mac原生cpolar、Darwin cloudflared](./MacOS/README.md#local-tunnel) |
| Windows | `.\Windows\【Windows】部署.cmd\【Windows】部署.cmd` | [Windows安装包、GUI或PowerShell](./Windows/README.md#local-tunnel) |
| Ubuntu | `bash './Ubuntu/【Linux】部署.sh/【Linux】部署.sh'` | [Linux原生包、apt辅助工具](./Ubuntu/README.md#local-tunnel) |
| Debian | `bash './Debian/【Linux】部署.sh/【Linux】部署.sh'` | [Linux原生包、apt辅助工具](./Debian/README.md#local-tunnel) |
| Rocky Linux | `bash './RockyLinux/【Linux】部署.sh/【Linux】部署.sh'` | [Linux原生包、dnf辅助工具](./RockyLinux/README.md#local-tunnel) |
| Alibaba Cloud Linux | `bash './AlibabaCloudLinux/【Linux】部署.sh/【Linux】部署.sh'` | [Linux原生包、dnf辅助工具](./AlibabaCloudLinux/README.md#local-tunnel) |
| Alpine | `sh './Alpine/【Linux】部署.sh/【Linux】部署.sh'` | [musl、仓库候选与独立二进制边界](./Alpine/README.md#local-tunnel) |
| FreeBSD | `sh './FreeBSD/【FreeBSD】部署.sh/【FreeBSD】部署.sh'` | [FreeBSD amd64 cpolar、Ports cloudflared](./FreeBSD/README.md#local-tunnel) |

正常运行顺序：阅读脚本自述并回车 → 准备健康的fzf → 在两项菜单中选“本地部署＋内网穿透”或“服务器部署”。选择器显示中文，内部只接受 `local` / `server` 两个ID；Esc、空结果、错误输出均停止，不能当作默认选项。取消选择时不会下载Go、改业务配置或启动后端。初始回车授权工程内工具准备，缺少时按 部署根目录的 `deploy-tools.lock.tsv` 的官方固定版本/架构/SHA256下载；已有健康工具优先复用，不升级系统安装，不要求预装Homebrew、Node或Python。

“本地部署＋内网穿透”：首次设置两组密码，确认本次公网发布后编译；本次进程强制production、回环监听与同源策略，不覆盖已有配置文件。脚本先拒绝已占用端口，再启动本次后端，健康检查成功且该子进程仍存活才创建Cloudflare Quick免费随机HTTPS；终端显示实际 `/client/` 与 `/admin/` URL。无需Cloudflare账号、自有域名或先购买套餐。大陆网络可能无法连接，不能承诺一次即通；45秒无随机地址即停止并回收本次进程，查看日志或使用下述cpolar备选。可仅为当前进程设置 `TUNNEL_START_TIMEOUT` 为1至300秒，不代表延长服务商可用性保证。

“服务器部署”：保留原监听/数据库配置，编译并前台运行后端，不启动隧道、不开放防火墙。要手动使用cpolar或命名Tunnel时选这一项，再按本节原生客户端步骤另开隧道，避免同时重复创建默认Quick Tunnel。

自动Quick路线会在 `../代码/后端/后端代码/.runtime/logs/` 创建本次会话的 `{}` 空YAML，显式传给 `--config`，不读取或改写个人 `.cloudflared/config.yml`，也不复用已有命名Tunnel配置；实际cloudflared子进程局部移除继承的 `TUNNEL_*` 环境，防止已有名称/域名/Token设置改变本次Quick模式，父环境保留。fzf健康探针与实际菜单都局部清空默认命令/选项，随后恢复宿主环境。

可用的现有工具可通过当前进程 `GO_BIN`、`FZF_BIN`、`CLOUDFLARED_BIN` 指向自己的健康原生可执行文件；脚本不持久化这些路径。不支持的平台/架构会停止而非下载错包。Windows ARM64当前没有锁定cloudflared原生成品；FreeBSD没有上游cloudflared成品、arm64也没有锁定fzf成品；先审阅本平台受信软件仓候选并验证工具，再使用本地模式。Alpine从锁定Linux独立二进制准备后仍先做执行健康检查，musl不兼容时停止，不自动混装edge或glibc。

首次配置时使用 `127.0.0.1:8080`，数据库连接串留空即为单实例文件模式；管理员与客户各设置不同的非默认密码（MacOS 本地调试至少4字符；服务器及其它平台至少12字符）。再次启动会复用 `../代码/后端/后端代码/.runtime/config.env`，应先确认它的监听、账户与数据目标；不要为了重新输入密码删除现有数据或配置。默认文件模式不需要先安装 [**PostgreSQL**](https://www.postgresql.org/)。窗口保持运行，再开一个终端做健康检查。本地模式已经自动管理隧道；下面手动客户端段落用于替代路线与固定地址。

```shell
curl --fail http://127.0.0.1:8080/healthz
```

Windows用PowerShell：

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8080/healthz'
```

本机 `/healthz` 应返回成功，`/client/` 和 `/admin/` 应加载本次部署的 Web 产物。只复制 Go 源码不会生成 Flutter 网页；若产物缺失，先按客户端说明构建，再将构建产物随 `代码/后端/` 和根目录 `部署/` 一起分发，保留原相对层级。不能用前端“本地演示”页面冒充后端运行成功。

### 7.2、<span id="local-tunnel-tools">本平台手动备选工具与费用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认自动路线使用Cloudflare Quick：零账号、零域名、零隧道套餐费用；主机电费/宽带等仍由使用者承担。适合先验通，地址不固定且无SLA。下面cpolar为大陆网络或固定地址的手动备选，需要自己的账号/Token；不由脚本采购或写入凭据。

优先在已经使用的主机完成本机启动，再选择穿透工具。工具品牌可跨系统使用，实际差异是客户端操作系统/架构、安装格式、命令解释器与常驻方式：

| 平台 | 首选准备方式 | 不能套用的部分 |
| --- | --- | --- |
| MacOS | cpolar的Darwin arm64/amd64 ZIP；cloudflared用Homebrew或Darwin包 | 不运行Windows EXE或Linux ELF |
| Windows | cpolar原生安装器/GUI或PowerShell前台；cloudflared Windows x64 EXE | GUI服务和CLI不能无意启动两份；ARM64隧道工具另验 |
| Ubuntu / Debian | cpolar Linux ZIP；cloudflared Linux二进制或官方DEB | 只在缺解压工具时审阅apt安装，不执行全系统升级 |
| Rocky / Alibaba Cloud Linux | cpolar Linux ZIP；cloudflared Linux二进制或官方RPM | 不复制apt、deb安装和MacOS服务命令 |
| Alpine | cloudflared当前受信仓候选或官方Linux二进制先验启动 | 当前可查包位于edge/testing，稳定源不混装；musl兼容须验 |
| FreeBSD | 官网FreeBSD amd64 cpolar ZIP；或FreeBSD Ports cloudflared | amd64不能冒充arm64支持，Linux包不是FreeBSD包 |

逐平台的下载来源、版本检查和命令在上表链接中展开。通用命令示例假定工具已安装在当前终端PATH，或由操作者替换成当前客户端的实际路径；Windows使用 `.\cpolar.exe`，POSIX手动解压通常使用 `./cpolar`。

[**cpolar**](https://www.cpolar.com/) 在官网2026-11-02展示：免费版1Mbps、随机地址、1个在线进程与4条隧道；基础版99元/年、2Mbps、3个保留子域名与8条隧道；专业版149元/年、3Mbps、可自定义域名与2个在线进程。一台电脑上的两个项目可在一个进程内配置两条隧道，数量上无需分别买两份基础套餐；不把两条隧道的带宽相加，实际额度与价格以[官方套餐页](https://www.cpolar.com/pricing)为准。免费/基础普通 HTTP 隧道也可生成公网 HTTPS 地址，专业版“端到端HTTPS”是另一项能力。

需要下载匹配系统和架构的原生客户端，先运行版本检查再配置；不使用关闭证书校验、来源不明镜像或修改系统全局代理来处理下载失败。首次使用隧道会让选定的本地应用变成公网可达；应先确认服务账户、拟公开的两个端口及测试范围。本说明提供操作步骤，不代表已经安装客户端、购买套餐或建立公网入口。

### 7.3、<span id="local-tunnel-two-projects">同一主机上的两个项目</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 隧道名称 | 本地目标 | 对外组织 |
| --- | --- | --- |
| `academic` | `http://127.0.0.1:8080` | 陈泉羽项目的页面、`/api/v1/`、私有文件共用一个 HTTPS 主机名 |
| `repair` | `http://127.0.0.1:8098` | 李林哲项目整站使用另一个 HTTPS 主机名；先在其项目中启动对应后端 |

两个项目各自保留原数据目录、配置和账号。不能让文件模式实例共享一个 `state.json`，不能让 Mac 与 Windows 同时写同步盘中的同一份状态。默认Quick路线分别在两个项目选择本地模式，会得到两个不同随机HTTPS地址，各窗口只管理本次后端和隧道。选择cpolar固定/临时路线时，两项目先各选服务器模式，两个后端分别健康后再开下面一个cpolar进程；只运行本项目时只启动 `academic`。

在工程目录之外的客户端私有目录新建 `cpolar-private.yml`。下例只有占位文本，必须把 `REPLACE_WITH_PRIVATE_TOKEN` 在本机编辑器中替换为本账户 Token；不要将真实值放入仓库、聊天、截图或命令历史。若用已有 cpolar 服务或 GUI 管理配置，先备份原文件并增量合并，保留其它隧道，不要用这个示例覆盖现有配置。

```yaml
authtoken: REPLACE_WITH_PRIVATE_TOKEN
web_addr: false
log: stdout
log_level: info
tunnels:
  academic:
    proto: http
    addr: 127.0.0.1:8080
    region: cn
    bind_tls: true
    inspect: false
  repair:
    proto: http
    addr: 127.0.0.1:8098
    region: cn
    bind_tls: true
    inspect: false
```

保持 `Host` 原值，不增加 `host_header: localhost` 或 `-host-header=rewrite`。本工程会检查浏览器 `Origin` 与请求 `Host` 的对应关系；默认采用同源访问，`CORS_ORIGINS` 可保持空。网页、API和附件不能拆到三个随机域名；来自其它网页的访问只有确需跨域时才逐项列入可信 HTTPS 来源，不使用 `*`。

POSIX手动客户端：

```shell
./cpolar start \
  -config="./cpolar-private.yml" \
  repair academic
```

Windows客户端目录：

```powershell
.\cpolar.exe start `
  -config=".\cpolar-private.yml" `
  repair academic
```

上述命令在保存客户端和私有配置的目录中运行。单项目将最后的 `repair academic` 改为 `academic`；双项目使用同一个 cpolar 进程显式启动两个名称。不要用 `start-all` 顺带启动旧配置里的 SSH、远程桌面或管理端口。GUI/后台服务与前台 CLI 二选一，避免基础套餐的1进程额度被第二个客户端占用。前台日志中的两个 HTTPS 地址才是本次实际地址，示例不预先假定域名后缀。

### 7.4、<span id="local-tunnel-fixed">从随机地址改成固定地址</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 免费版先验证链路。随机地址会变化，不要把它永久写进已经分发的 App；本次停止后新建的地址也不能当作同一稳定地址。

- 需要固定地址时，在 cpolar 后台按套餐保留两个不同的子域名，记录名称和所属地区。只在各自隧道下增加 `subdomain: 实际保留名称`，并把 `region` 改成后台记录的同一地区；其余端口和同源规则不变。名称冲突、地区不匹配或套餐不支持时先处理后台配置，不反复更改业务数据。

- 选择自有域名需要相应套餐、自己控制的 DNS 和有效 HTTPS 证书/服务配置；按[官方自定义域名说明](https://www.cpolar.com/docs)完成域名与证书核验，不能把基础版的“保留子域名”写成任意自有域名。域名、证书和固定地址资格属于部署方账户资源。

- 浏览器使用 `https://实际学术域名/client/` 或 `/admin/`；桌面客户端设置完整 `https://实际学术域名/api/v1`；移动端按模块说明填写/构建相同 API 地址。手机上的 `127.0.0.1` 是手机本身。微信小程序正式发布还须按平台要求配置自有 AppID、HTTPS 合法域名等，不以临时隧道地址代替发布验收。

### 7.5、<span id="local-tunnel-cloudflare">Cloudflare 手动临时与固定隧道</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从 [Cloudflare 官方下载页](https://developers.cloudflare.com/tunnel/downloads/) 选择本平台与架构；MacOS已有Homebrew可审阅后安装，Linux选择对应独立二进制/DEB/RPM，Windows用原生EXE。Alpine/FreeBSD按各自说明先核软件仓或ABI，不能把Linux安装命令照搬。每种路线先做版本检查，均不默认注册后台服务。

默认本地模式已自动执行Quick路线，不再运行第二份。需要自己管理客户端时，先选服务器模式，确认后端健康；有可用 `cloudflared` 后，可在另一终端只为学术项目创建临时测试入口：

```shell
quick_config="$(mktemp './cloudflared-quick.XXXXXX')"
printf '{}\n' > "$quick_config"
cloudflared tunnel \
  --config "$quick_config" \
  --no-autoupdate \
  --url http://127.0.0.1:8080
```

Windows客户端目录：

```powershell
$quickConfig = Join-Path (Get-Location) ('quick-' + [guid]::NewGuid().ToString('N') + '.yml')
[IO.File]::WriteAllText($quickConfig, "{}`n", (New-Object Text.UTF8Encoding($false)))
.\cloudflared.exe tunnel `
  --config $quickConfig `
  --no-autoupdate `
  --url http://127.0.0.1:8080
```

若同时临时测试维修项目，另开终端把目标改为 `http://127.0.0.1:8098`，保留两个不同的随机地址。[Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)无需账户或自有域名，但随机 URL 每次创建会变化、停止客户端即失效；仅用于测试开发，无可用性保证，最多200个在途请求且不支持 SSE。大陆不同运营商的实际访问需用目标网络测试，不将免费链路写成大陆加速或稳定性承诺。

需要固定域名时，选择[账号中的命名 Tunnel](https://developers.cloudflare.com/tunnel/get-started/)，先准备托管在 Cloudflare 的域名。创建一个 Tunnel 后分别添加学术、维修两个公网主机名，服务地址填上述两个 `http://127.0.0.1` 目标，路径留空整站转发，不设置 HTTP Host Header 覆写。按控制台当前平台的原生客户端命令在前台连接，Token/凭据保存在工程外的私有配置中。需要自启动时再单独审阅服务安装步骤；不能因控制台给出安装命令就默认修改系统常驻。Tunnel费用、域名续费及内容/流量限制按所选计划复核。

### 7.6、<span id="local-tunnel-acceptance">公网验收、运行与停止</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 先用电脑本机访问健康接口，再让手机关闭 Wi-Fi、通过移动网络访问实际 HTTPS 域名的 `/healthz`、`/client/` 和 `/admin/`。证书错误或路由错误停止排查，不关闭证书验证。测试人员不用安装隧道客户端。

- 用客户账户创建一条带可识别标记的合成需求，刷新并从另一客户端重读；再用管理员查看同一编号。应核实成功响应来自后端，而非“本地演示”缓存。前端 API 回退允许页面继续展示，页面能打开或样例能操作并不能证明穿透成功。

- 验证未登录请求私有接口被拒绝、客户不能读取他人私有文件、上传后可按权限重新下载。当前单文件8MB、每单最多50份/合计64MB，上传请求体还有应用限制；隧道“不限流量”不能取消这些限制。超时写入先查询原操作，保留原幂等键，不换新键重复提交。

- 自动本地模式保留一个运行窗口；手动模式保留后端窗口与隧道窗口。自动本地模式的子日志为入口显示日志名追加 `.server.log` / `.tunnel.log`；Windows分别追加 `.server.stdout.log`、`.server.stderr.log`、`.tunnel.stdout.log`、`.tunnel.stderr.log`。可将 cpolar 的 `log` 配置为工程外私有日志文件，但不要启用包含正文/Token的 HTTP 检查或公开本地管理界面；分享日志前脱敏。后端日志位于 `../代码/后端/后端代码/.runtime/logs/`，实际文件名由启动入口显示。

- 睡眠、合盖、关机、宽带断开或系统重启都会影响访问。MacOS、Windows、Linux与FreeBSD分别按本平台说明保持当前展示会话唤醒；避免默认全局改电源策略。后台常驻只在前台验证成功后另行审阅，应用与隧道分别管理。 速度取决于主机宽带上行、隧道套餐及真实网络，低访问量也不能保证大附件快速传输。

- 自动本地模式在本项目窗口按 `Ctrl+C`，脚本只回收本次创建的后端与隧道，不按进程名或端口杀其它服务；任一子进程先退出，也会停止另一进程。Shell先TERM宽限最多5秒，再强制结束本次仍存活的子进程；Windows只操作本次Process对象。手动模式停止时先关闭这两个公网隧道：前台进程按 `Ctrl+C`；GUI/服务模式只禁用对应两条隧道，不停止其它项目的共用服务。再从外部网络发一个新的健康请求，确认入口已不能到达本机；缓存页面仍显示不代表隧道仍在线。长期不用时，在提供商后台撤销对应路由/域名绑定；Token疑似泄露时在后台撤销并重新签发，不能只隐藏网址。

- 随后在后端窗口按 `Ctrl+C`，正常退出后备份整个 `../代码/后端/后端代码/data/` 与有效部署配置。公网域名、隧道停用不会自动删除本地数据；卸载客户端也不等于后台路由已经撤销。密钥/Token与业务备份分开保管，恢复前保留当前数据副本，不用重装覆盖原文件。

### 7.7、<span id="local-tunnel-troubleshooting">常见问题与验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 现象 | 排查顺序 |
| --- | --- |
| fzf取消/空选/报错 | 业务尚未启动；排查终端是否交互、工具版本能力和日志，再重新明确选择，不使用参数绕过菜单 |
| 没有原生工具资产 | 查看平台/架构与受信仓候选，健康原生工具可按当前进程变量指定；不使用其它架构或修改系统源蒙混安装 |
| 隧道地址45秒超时 | 查看cloudflared子日志、网络与官方Quick限制；可按本平台cpolar备选操作；失败已回收本次后端与隧道 |
| 502 / 无法连接本机 | 先看本机 `/healthz`，再核对隧道目标端口与所在主机；不要先开放防火墙或改监听为全网 |
| 首页能开，提交被拒 | 检查公网 `Host` 是否被改成 localhost、浏览器 `Origin` 是否同源、实际 API 是否请求同一 HTTPS 主机 |
| 页面显示演示样例 | 检查健康/API响应、前端实际服务地址和服务端日志；通过真实写入刷新重读判断是否连通 |
| 随机地址失效 | 查看当前客户端日志/后台，免费地址会变化；固定地址须核对保留名称与地区 |
| 两个隧道互相掉线 | 检查是否启动多个客户端进程或GUI服务；在一进程中只启动所需两条隧道 |
| 上传失败或很慢 | 核对应用8MB限制、超时、实际上行、套餐带宽及服务商单请求限制，不把问题直接归为数据库故障 |
| 电脑重启后不可访问 | 应用和隧道都要恢复；先前台验证，再选择本平台服务/任务计划，保持数据目录与私有配置路径一致 |

本节按现有源码、部署入口与官方工具资料编写；不代表已经在本平台安装隧道、开通账号、实测公网读写或完成最低资源/并发验收。原有平台验证状态继续有效，真实资料与正式运营条件仍须按工程范围逐项验收。平台差异与共用说明见[本章平台入口](#local-tunnel-start)。

## 八、<span id="unit-code-maps">各实施单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [MacOS 部署](MacOS/代码地图/README.md)
- [Windows 部署](Windows/代码地图/README.md)
- [Ubuntu 部署](Ubuntu/代码地图/README.md)
- [Debian 部署](Debian/代码地图/README.md)
- [RockyLinux 部署](RockyLinux/代码地图/README.md)
- [AlibabaCloudLinux 部署](AlibabaCloudLinux/代码地图/README.md)
- [Alpine 部署](Alpine/代码地图/README.md)
- [FreeBSD 部署](FreeBSD/代码地图/README.md)


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
**扫码访问：** 地址生成后仍逐行显示完整 URL，并分别生成用户端、管理端的本地二维码。支持颜色且足够宽的终端直接显示黑白码；窄终端、非 TTY、`NO_COLOR` 或 Windows 纯文本环境，打开日志列出的 `.runtime/access-qr.*/index.html`（Windows 为 `access-qr-编号`）扫码，可保存 SVG/PNG。二维码不经过在线服务；隧道地址变化会重新生成，退出时页面标记失效。服务器可通过环境变量或 `.runtime/config.env` 的 `PUBLIC_BASE_URL=https://实际域名` 指定不含账户、查询参数或片段的基地址；未配置时仅显示明确标为“仅本机”的回环入口，手机无法访问。二维码辅助失败只告警，原 URL 与健康服务保留；产物由既有反部署清单管理。详见[二维码输出、固定依赖与使用边界](./公共组件/地址二维码/README.md)。

