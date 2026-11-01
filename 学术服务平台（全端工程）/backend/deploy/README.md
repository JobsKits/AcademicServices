# 后端分平台部署

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

复制**完整backend文件夹**到目标机器，再运行对应系统入口。该目录包含单份 [**Go**](https://go.dev/) 源码、锁定依赖、独立部署脚本与已构建的Flutter页面。服务器不需要安装Flutter或Node。以下入口按系统分别独立实现，不依赖开发机其它项目。

## <span id="section-1">一、支持矩阵与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 平台 | 入口 | 运行环境 | 本轮验证 |
| --- | --- | --- | --- |
| macOS Intel / Apple Silicon | `macOS/部署.command` | zsh、系统curl/tar/shasum、本地Go | 本机ARM64迁移目录实际配置/编译/启动/停止；Intel待实机 |
| Windows 10/11 / Server x64、ARM64 | `Windows/部署.cmd` | 系统PowerShell、工程内Go | PowerShell语法与路径静态检查；原生运行待验 |
| Ubuntu | `Ubuntu/双击部署.desktop` 或 `deploy.sh` | bash；缺工具时apt-get | 语法/静态/夹具；目标机部署待验 |
| Debian | `Debian/双击部署.desktop` 或 `deploy.sh` | bash；缺工具时apt-get | 同上 |
| RockyLinux | `RockyLinux/双击部署.desktop` 或 `deploy.sh` | bash；缺工具时dnf | 同上 |
| Alibaba Cloud Linux | `AlibabaCloudLinux/双击部署.desktop` 或 `deploy.sh` | bash；缺工具时dnf | 同上 |
| Alpine | `Alpine/deploy.sh` | 系统sh；缺工具时apk | 同上；其桌面快捷项需有bash桌面环境 |
| FreeBSD | `FreeBSD/deploy.sh` | 系统sh；缺工具时pkg | 语法/静态；目标机待验 |

上述归档安装器覆盖amd64/arm64。Go服务还可交叉编译到其它Go支持的平台，交叉编译不等于脚本自动部署或对应系统已实机运行。没有桌面环境的服务器不存在双击动作，SSH终端执行对应脚本即可。

## <span id="section-2">二、第一次运行与配置</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、首次自述回车继续；其它字符取消。没有可交互输入会停止，不把EOF当确认。

2、检查Go 1.27.3：显式 `GO_BIN`、PATH、本目录 `.tools/go1.27.3/bin/go` 依次检查。没有匹配健康版本时下载工程内SDK，校验[官方SHA256](https://go.dev/dl/)后解压。不会更新现有全局Go。

3、缺curl/tar/摘要工具时，Linux/FreeBSD使用本机已配置软件源安装必需包，需要管理员权限与交互确认；已有健康工具复用。macOS缺系统工具时停止并给修复说明，不盲装包管理器。

4、设置监听地址、两组不同且至少12位的账户密码。数据库连接串可选，空为单实例文件模式。配置写 `backend/.runtime/config.env`，POSIX权限0600、Windows限制当前账户读取。日志不输出密码。该文件为数据，不会当脚本执行；未知配置键会拒绝。

5、构建到临时二进制，成功后替换程序。前台启动、显示日志路径，按 `Ctrl+C` 停止。再次运行保留配置与数据，不清理业务目录。

首次下载需HTTPS访问Go官方与模块源。依赖拉取默认采用goproxy.cn镜像，失败回退proxy.golang.org及direct；只影响脚本当前进程的GOPROXY，不修改系统网络代理或全局Go配置。可在启动前提供GOPROXY，或在配置文件中添加同名键。来源在构建前脱敏打印，go.sum固定依赖摘要。Go版本与各归档摘要在[工具链清单](./toolchains.json)；这是2026-10-30核对的最新稳定基线，日后版本更新需复核摘要并重跑回归，不在每次部署中无条件升级。

## <span id="section-3">三、命令与只读检查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从任意工作目录运行，路径按入口自身定位：

```shell
zsh './macOS/部署.command' --check
bash './Ubuntu/deploy.sh' --check
sh './Alpine/deploy.sh' --check
sh './FreeBSD/deploy.sh' --check
```

[**PowerShell**](https://learn.microsoft.com/powershell/)检查与启动：

```powershell
powershell.exe -NoProfile -File .\Windows\deploy.ps1 -Check
.\Windows\部署.cmd
```

`--check`/`-Check` 仅检查平台和源码路径，不下载、不写配置、不编译或启动。正常入口需要交互，自动化CI直接通过环境配置运行已构建Go程序，见[后端说明](../README.md)。脚本只配置自身运行实例，不注册系统服务或放开防火墙。

## <span id="section-4">四、数据、迁移和常驻</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 文件模式的资料、附件、审计、幂等收据与待发送通知在 `data/state.json` 的同一原子快照中。单进程锁拒绝多个文件实例共享目录。
- PostgreSQL选项使用数据库内 `academic_runtime_state` JSONB事务聚合；脚本不会安装或创建数据库账户，填写连接串前应备好独立数据库。原29表关系DDL仅参考，当前业务未逐表写入。
- 两种存储没有自动互转。修改 `DATABASE_URL` 是切换数据源，不能当作数据迁移。需要先导出/转换/对账并完成恢复测试。
- 备份前正常停止服务。保存整个data目录与有效配置；不要只备份程序。还原前保留旧数据副本，确认密码与数据库目标匹配。
- 当前入口以前台运行便于新手发现错误，关闭窗口就会停止。需要服务器重启后自动运行时，由运维将 `.runtime/bin/server` 接入 systemd、launchd 或Windows任务计划，使用同一工作目录和环境；未在脚本内静默创建系统常驻项。

## <span id="section-5">五、对外HTTPS</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认loopback只供本机。正式域名应在独立反向代理上配置HTTPS，将 `/api/v1/`、`/admin/`、`/client/` 转发到同一Go服务并保留Host。证书和域名由部署方提供，脚本不购买域名、不请求未知账户权限，不更改系统防火墙。

客户端填写 `https://域名/api/v1`。同源页面无需CORS；其它网页来源仅在 `CORS_ORIGINS` 中逐个填可信HTTPS origin，不能用 `*`。鸿蒙远程Web宿主与后端同源。公开HTTP传输登录密码不可作为正式部署方式。

## <span id="section-6">六、目录与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
backend/
├── cmd/ internal/ migrations/ contracts/   # 单份Go业务代码与契约
├── admin-web/ client-web/                 # 已构建页面，整体复制
├── deploy/                               # 各平台独立入口
├── .tools/                               # 按需下载SDK、模块/构建缓存
├── .runtime/config.env                   # 首次设置；不要公开传播
├── .runtime/logs/                        # 每次独立部署日志
├── .runtime/bin/                         # 编译出的本机程序
└── data/                                 # 业务持久化与实例锁
```

复制源码给另一台机器时，不带旧机器的 `.runtime/config.env` 或 `data`，首次启动重新配置；迁移现有业务则先正常停机并按备份恢复流程明确携带数据。不要让试用数据混入正式环境。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
