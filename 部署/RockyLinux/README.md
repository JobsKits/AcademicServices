# RockyLinux｜知序部署入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

部署与反部署的生命周期核心分别内嵌在本平台两份脚本中，覆盖原点、操作锁、进程身份、数据备份和资源恢复；两份脚本可分别执行，无须加载外部生命周期函数库。确认顺序、状态协议、数据策略及恢复边界见[原点与恢复协议](../README.md#lifecycle-protocol)。

本目录为 RockyLinux 独立部署单元。同时复制根目录的 `代码/` 与 `部署/`、保留原相对层级后运行 [【Linux】部署.sh](./【Linux】部署.sh/【Linux】部署.sh)，不要只搬这一个脚本。

**双击运行：** 在本系统文件夹中打开 [双击部署（快捷入口）.desktop](./双击部署（快捷入口）.desktop)。它是桌面快捷方式，使用`bash` 调用脚本包内唯一部署实现，并复用内层自述与确认。快捷入口从自身目录校验唯一同名脚本包，缺失或多候选即停止，不复制部署逻辑。需要图形桌面与终端模拟器；文件管理器可能要求操作者信任或允许启动该文件，脚本不会默认更改信任设置或安装图形环境。文件管理器须传入本地绝对路径；若传入 `file://` 等 URI 或相对路径，入口会停止，可从本地文件夹启动或改用终端规范脚本。无桌面服务器仍通过 SSH 执行下方规范脚本。

## <span id="section-1">一、用途与操作</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

入口先展示自述并等待确认，首次配置账户/监听地址，必要时下载经SHA256验证的Go到工程内，然后编译并前台运行。Ctrl+C停止并保留数据；再次运行复用原配置。

完整依赖、平台/架构边界、检查命令、配置、日志、备份和HTTPS说明见[部署总说明](../README.md)。当前系统的真实验证状态也在总说明中，不能将源码存在等同实机部署通过。

## 二、<span id="minimum-machine">最低支持机器配置</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[**Rocky Linux**](https://rockylinux.org/) 64 位安全维护版本；Linux 内核 3.2 或更高，amd64 / arm64；所选版本若要求更高 CPU 指令集或其它硬件条件，仍须满足。

正常入口会下载依赖并在目标机编译 Go 1.27.3。以下为少量数据、单实例联调的工程部署预算；未在下限硬件压测，不构成并发或正式运营容量承诺。

| 场景 | CPU | 可用内存 | 空闲 SSD 空间 |
| --- | --- | --- | --- |
| 仅运行预编译二进制 | 2 核 / vCPU，64 位 | 2 GiB | 10 GiB |
| **正常脚本部署最低预算** | **2 核 / vCPU，64 位** | **4 GiB** | **20 GiB** |

表中内存为扣除操作系统与其它程序占用后的可用余量，磁盘为安装系统后额外留给工程的空闲空间；虚拟机 / 容器须按实际分配给实例的资源计算。

仅运行二进制预算要求已有匹配系统 / 架构的 Go 程序及 Web 产物，不能用于本目录正常编译入口。与数据库、HTTPS 反代同机时，建议按 4 核 / 8 GiB 可用内存 / 40 GiB 空闲 SSD 起做低负载验证；附件、全量状态临时副本、日志和备份增长另计。当前聚合存储没有生产容量验收。

首次部署需 HTTPS 443 联网下载 Go、模块和缺失系统工具；依赖齐备后的本机文件演示可离线。公网演示按至少 5 Mbps 可用上行作预算，附件流量增加时扩容；正式访问使用 HTTPS 443，应用与数据库端口只在本机或受控内网提供。

系统兼容条件参照 [Go 官方最低要求](https://go.dev/wiki/MinimumRequirements)（2026-11-02 核对）；完整口径、存储扩容边界与各系统实机状态见[最低机器配置与适用范围](../README.md#minimum-machine)。本节只说明后端部署，不包含移动端 / 桌面客户端构建工具链。

## 三、<span id="local-tunnel">本地部署＋内网穿透</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

**关闭此运行终端，服务将结束**。本地临时模式在确认公开前及地址生成后的运行日志中单独显示此提示；支持颜色的终端使用红色加粗，非终端、`TERM=dumb` 或 `NO_COLOR` 时显示纯文本，日志不含颜色控制码。当前窗口管理本次后端与隧道，关闭终端或按 `Ctrl+C` 结束本次临时服务，业务数据与账户配置保留。

复用现有电脑或服务器运行本工程，通过隧道的公网 HTTPS 地址让指定测试者访问。适用于前期少量合成数据联调；服务仍监听 `127.0.0.1:8080`，无需把监听改成 `0.0.0.0`，也无需向路由器开放 8080 或数据库端口。工具与安装包随平台选择，不能把其它系统的二进制直接拿来运行。

### 3.1、<span id="local-tunnel-start">用fzf选择本地或服务器部署</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先在终端进入本说明所在的 `部署/RockyLinux` 目录，保证复制的是完整 `后端`。以下先只读检查/审阅计划，再正常启动；直接运行同名脚本包内的规范入口；`--check`/`-Check`本身不会安装、编译或运行：

```bash
bash './【Linux】部署.sh/【Linux】部署.sh' --check
bash './【Linux】部署.sh/【Linux】部署.sh' --plan
bash './【Linux】部署.sh/【Linux】部署.sh'
```

正常运行顺序：阅读脚本自述并回车 → 准备健康的fzf → 在两项菜单中选“本地部署＋内网穿透”或“服务器部署”。选择器显示中文，内部只接受 `local` / `server` 两个ID；Esc、空结果、错误输出均停止，不能当作默认选项。取消选择时不会下载Go、改业务配置或启动后端。初始回车授权工程内工具准备，缺少时按 部署根目录的 `deploy-tools.lock.tsv` 的官方固定版本/架构/SHA256下载；已有健康工具优先复用，不升级系统安装，不要求预装Homebrew、Node或Python。

“本地部署＋内网穿透”：首次设置两组密码，确认本次公网发布后编译；本次进程强制production、回环监听与同源策略，不覆盖已有配置文件。脚本先拒绝已占用端口，再启动本次后端，健康检查成功且该子进程仍存活才创建Cloudflare Quick免费随机HTTPS；终端显示实际 `/client/` 与 `/admin/` URL。无需Cloudflare账号、自有域名或先购买套餐。大陆网络可能无法连接，不能承诺一次即通；45秒无随机地址即停止并回收本次进程，查看日志或使用下述cpolar备选。可仅为当前进程设置 `TUNNEL_START_TIMEOUT` 为1至300秒，不代表延长服务商可用性保证。

“服务器部署”：保留原监听/数据库配置，编译并前台运行后端，不启动隧道、不开放防火墙。要手动使用cpolar或命名Tunnel时选这一项，再按本节原生客户端步骤另开隧道，避免同时重复创建默认Quick Tunnel。

自动Quick路线会在 `../../代码/后端/后端代码/.runtime/logs/` 创建本次会话的 `{}` 空YAML，显式传给 `--config`，不读取或改写个人 `.cloudflared/config.yml`，也不复用已有命名Tunnel配置；实际cloudflared子进程局部移除继承的 `TUNNEL_*` 环境，防止已有名称/域名/Token设置改变本次Quick模式，父环境保留。fzf健康探针与实际菜单都局部清空默认命令/选项，随后恢复宿主环境。

可用的现有工具可通过当前进程 `GO_BIN`、`FZF_BIN`、`CLOUDFLARED_BIN` 指向自己的健康原生可执行文件；脚本不持久化这些路径。不支持的平台/架构会停止而非下载错包。Windows ARM64当前没有锁定cloudflared原生成品；FreeBSD没有上游cloudflared成品、arm64也没有锁定fzf成品；先审阅本平台受信软件仓候选并验证工具，再使用本地模式。Alpine从锁定Linux独立二进制准备后仍先做执行健康检查，musl不兼容时停止，不自动混装edge或glibc。

首次配置时使用 `127.0.0.1:8080`，数据库连接串留空即为单实例文件模式；管理员与客户各设置不同的非默认密码（MacOS 本地调试至少4字符；服务器及其它平台至少12字符）。再次启动会复用 `../../代码/后端/后端代码/.runtime/config.env`，应先确认它的监听、账户与数据目标；不要为了重新输入密码删除现有数据或配置。默认文件模式不需要先安装 PostgreSQL。窗口保持运行，再开一个终端做健康检查。本地模式已经自动管理隧道；下面手动客户端段落用于替代路线与固定地址。

```shell
curl --fail http://127.0.0.1:8080/healthz
```

本机 `/healthz` 应返回成功，`/client/` 和 `/admin/` 应加载本次部署的 Web 产物。只复制 Go 源码不会生成 Flutter 网页；若产物缺失，先按客户端说明构建，再将构建产物随 `代码/后端/` 和根目录 `部署/` 一起分发，保留原相对层级。不能用前端“本地演示”页面冒充后端运行成功。

### 3.2、<span id="local-tunnel-tools">本平台手动备选工具与费用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认自动路线使用Cloudflare Quick：零账号、零域名、零隧道套餐费用；主机电费/宽带等仍由使用者承担。适合先验通，地址不固定且无SLA。下面cpolar为大陆网络或固定地址的手动备选，需要自己的账号/Token；不由脚本采购或写入凭据。

先用 `uname -m` 判断 x86_64 或 aarch64/arm64，从[官方客户端下载页](https://www.cpolar.com/download)选择 Linux 64-bit（amd64）或 ARMv8 64bit（arm64）ZIP；不能选择 Mac/Windows/FreeBSD 包。将客户端解压到工程外私有工具目录，进入该目录运行 `./cpolar version`，缺少执行权限时只对已核实的 `cpolar` 文件补 `chmod u+x`。

Rocky Linux 解压工具若缺失，由管理员确认后安装本系统的软件包；下面安装行会更改系统软件包，不属于后端启动脚本的自动动作。已有工具直接复用，不为隧道执行全系统升级。

```shell
uname -m
command -v unzip
sudo dnf install unzip
```

按实际下载文件名解压，只检查与执行自己的客户端文件；不使用 `curl | sh` 一类直接执行下载脚本的安装方式。本机无桌面时使用下面的私有YAML与前台CLI，仍不需要对外开放本地管理页面。

[**cpolar**](https://www.cpolar.com/) 在官网2026-11-02展示：免费版1Mbps、随机地址、1个在线进程与4条隧道；基础版99元/年、2Mbps、3个保留子域名与8条隧道；专业版149元/年、3Mbps、可自定义域名与2个在线进程。一台电脑上的两个项目可在一个进程内配置两条隧道，数量上无需分别买两份基础套餐；不把两条隧道的带宽相加，实际额度与价格以[官方套餐页](https://www.cpolar.com/pricing)为准。免费/基础普通 HTTP 隧道也可生成公网 HTTPS 地址，专业版“端到端HTTPS”是另一项能力。

需要下载匹配系统和架构的原生客户端，先运行版本检查再配置；不使用关闭证书校验、来源不明镜像或修改系统全局代理来处理下载失败。首次使用隧道会让选定的本地应用变成公网可达；应先确认服务账户、拟公开的两个端口及测试范围。本说明提供操作步骤，不代表已经安装客户端、购买套餐或建立公网入口。

### 3.3、<span id="local-tunnel-two-projects">同一主机上的两个项目</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

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

```shell
./cpolar start \
  -config="./cpolar-private.yml" \
  repair academic
```

上述命令在保存客户端和私有配置的目录中运行。单项目将最后的 `repair academic` 改为 `academic`；双项目使用同一个 cpolar 进程显式启动两个名称。不要用 `start-all` 顺带启动旧配置里的 SSH、远程桌面或管理端口。GUI/后台服务与前台 CLI 二选一，避免基础套餐的1进程额度被第二个客户端占用。前台日志中的两个 HTTPS 地址才是本次实际地址，示例不预先假定域名后缀。

### 3.4、<span id="local-tunnel-fixed">从随机地址改成固定地址</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、免费版先验证链路。随机地址会变化，不要把它永久写进已经分发的 App；本次停止后新建的地址也不能当作同一稳定地址。

2、需要固定地址时，在 cpolar 后台按套餐保留两个不同的子域名，记录名称和所属地区。只在各自隧道下增加 `subdomain: 实际保留名称`，并把 `region` 改成后台记录的同一地区；其余端口和同源规则不变。名称冲突、地区不匹配或套餐不支持时先处理后台配置，不反复更改业务数据。

3、选择自有域名需要相应套餐、自己控制的 DNS 和有效 HTTPS 证书/服务配置；按[官方自定义域名说明](https://www.cpolar.com/docs)完成域名与证书核验，不能把基础版的“保留子域名”写成任意自有域名。域名、证书和固定地址资格属于部署方账户资源。

4、浏览器使用 `https://实际学术域名/client/` 或 `/admin/`；桌面客户端设置完整 `https://实际学术域名/api/v1`；移动端按模块说明填写/构建相同 API 地址。手机上的 `127.0.0.1` 是手机本身。微信小程序正式发布还须按平台要求配置自有 AppID、HTTPS 合法域名等，不以临时隧道地址代替发布验收。

### 3.5、<span id="local-tunnel-cloudflare">Cloudflare 手动临时与固定隧道</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Cloudflare备选从[Cloudflare 官方下载页](https://developers.cloudflare.com/tunnel/downloads/)选择本架构的Linux独立二进制；Debian/Ubuntu也可使用官方DEB，Rocky/Alibaba Cloud Linux可使用官方RPM。独立二进制改名为 `cloudflared` 后先检查 `./cloudflared --version`；未加入PATH时，下例命令名改成 `./cloudflared`。采用包管理器安装时先审阅来源、架构及依赖，不把其它发行版包强装到本系统。

默认本地模式已自动执行Quick路线，不再运行第二份。需要自己管理客户端时，先选服务器模式，确认后端健康；有可用 `cloudflared` 后，可在另一终端只为学术项目创建临时测试入口：

```shell
quick_config="$(mktemp './cloudflared-quick.XXXXXX')"
printf '{}\n' > "$quick_config"
cloudflared tunnel \
  --config "$quick_config" \
  --no-autoupdate \
  --url http://127.0.0.1:8080
```

若同时临时测试维修项目，另开终端把目标改为 `http://127.0.0.1:8098`，保留两个不同的随机地址。[Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)无需账户或自有域名，但随机 URL 每次创建会变化、停止客户端即失效；仅用于测试开发，无可用性保证，最多200个在途请求且不支持 SSE。大陆不同运营商的实际访问需用目标网络测试，不将免费链路写成大陆加速或稳定性承诺。

需要固定域名时，选择[账号中的命名 Tunnel](https://developers.cloudflare.com/tunnel/get-started/)，先准备托管在 Cloudflare 的域名。创建一个 Tunnel 后分别添加学术、维修两个公网主机名，服务地址填上述两个 `http://127.0.0.1` 目标，路径留空整站转发，不设置 HTTP Host Header 覆写。按控制台当前平台的原生客户端命令在前台连接，Token/凭据保存在工程外的私有配置中。需要自启动时再单独审阅服务安装步骤；不能因控制台给出安装命令就默认修改系统常驻。Tunnel费用、域名续费及内容/流量限制按所选计划复核。

### 3.6、<span id="local-tunnel-acceptance">公网验收、运行与停止</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、先用电脑本机访问健康接口，再让手机关闭 Wi-Fi、通过移动网络访问实际 HTTPS 域名的 `/healthz`、`/client/` 和 `/admin/`。证书错误或路由错误停止排查，不关闭证书验证。测试人员不用安装隧道客户端。

2、用客户账户创建一条带可识别标记的合成需求，刷新并从另一客户端重读；再用管理员查看同一编号。应核实成功响应来自后端，而非“本地演示”缓存。前端 API 回退允许页面继续展示，页面能打开或样例能操作并不能证明穿透成功。

3、验证未登录请求私有接口被拒绝、客户不能读取他人私有文件、上传后可按权限重新下载。当前单文件8MB、每单最多50份/合计64MB，上传请求体还有应用限制；隧道“不限流量”不能取消这些限制。超时写入先查询原操作，保留原幂等键，不换新键重复提交。

4、自动本地模式保留一个运行窗口；手动模式保留后端窗口与隧道窗口。自动本地模式的子日志为入口显示日志名追加 `.server.log` / `.tunnel.log`；Windows分别追加 `.server.stdout.log`、`.server.stderr.log`、`.tunnel.stdout.log`、`.tunnel.stderr.log`。可将 cpolar 的 `log` 配置为工程外私有日志文件，但不要启用包含正文/Token的 HTTP 检查或公开本地管理界面；分享日志前脱敏。后端日志位于 `../../代码/后端/后端代码/.runtime/logs/`，实际文件名由启动入口显示。

5、睡眠、合盖、关机、宽带断开或系统重启都会影响访问。无桌面服务器也须确认宿主机、虚拟机和网络不会被暂停。需要常驻时再按本系统的systemd/OpenRC/rc.d能力审阅服务定义、运行账户、绝对运行路径与停止方式；后端和隧道须分别管理。本文不自动注册系统服务或改变电源策略。 速度取决于主机宽带上行、隧道套餐及真实网络，低访问量也不能保证大附件快速传输。

6、自动本地模式在本项目窗口按 `Ctrl+C`，脚本只回收本次创建的后端与隧道，不按进程名或端口杀其它服务；任一子进程先退出，也会停止另一进程。Shell先TERM宽限最多5秒，再强制结束本次仍存活的子进程；Windows只操作本次Process对象。手动模式停止时先关闭这两个公网隧道：前台进程按 `Ctrl+C`；GUI/服务模式只禁用对应两条隧道，不停止其它项目的共用服务。再从外部网络发一个新的健康请求，确认入口已不能到达本机；缓存页面仍显示不代表隧道仍在线。长期不用时，在提供商后台撤销对应路由/域名绑定；Token疑似泄露时在后台撤销并重新签发，不能只隐藏网址。

7、随后在后端窗口按 `Ctrl+C`，正常退出后备份整个 `../../代码/后端/后端代码/data/` 与有效部署配置。公网域名、隧道停用不会自动删除本地数据；卸载客户端也不等于后台路由已经撤销。密钥/Token与业务备份分开保管，恢复前保留当前数据副本，不用重装覆盖原文件。

### 3.7、<span id="local-tunnel-troubleshooting">常见问题与验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

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

本节按现有源码、部署入口与官方工具资料编写；不代表已经在本平台安装隧道、开通账号、实测公网读写或完成最低资源/并发验收。原有平台验证状态继续有效，真实资料与正式运营条件仍须按工程范围逐项验收。平台差异与共用说明见[部署总说明的本地穿透章节](../README.md#local-tunnel)。

## 一、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


## 四、<span id="undeployment">反部署与恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [双击反部署（快捷入口）.desktop](./双击反部署（快捷入口）.desktop)调用独立的 [【Linux】反部署.sh](./【Linux】反部署.sh/【Linux】反部署.sh)，不复用部署快捷入口。无图形桌面时使用 `bash './【Linux】反部署.sh/【Linux】反部署.sh'`。
- 数据通过fzf选择备份（默认）或清零，再经过默认取消的危险菜单和空格复核；备份包含文件数据与账户配置，保存到后端代码目录同级 `反部署备份/`，校验和快照复核通过才清源。取消、备份失败或源发生变化均保留数据。
- 部署前保存 `.runtime` / `.tools` 原点，部署后按文件摘要记录实际变更。反部署仅回收身份匹配的本次进程，并恢复清单内仍未被后续修改的资源。共享、未知、旧部署缺少记录、系统包安装分支及非空数据库连接串都会保留并报告未完成，不能称为已完全恢复。
- [脚本详细说明](./【Linux】反部署.sh/README.md)与[原点与恢复协议](../README.md#lifecycle-protocol)说明操作锁、重试和私密恢复包；反部署完成保留原点审计，下一次全新部署前先私密归档 `.deployment-state`。隔离检查与本系统原生、实库恢复分别验收。

反部署确认后的纯文本审计位于后端 `.deployment-state/posix/operations.log`；资源差异见 `current.tsv` / `restored.tsv`，数据恢复位置见 `data-pending` / `data-destination`。未完成项会返回非零并保留现场。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
**扫码访问：** 地址生成后仍逐行显示完整 URL，并分别生成用户端、管理端的本地二维码。支持颜色且足够宽的终端直接显示黑白码；窄终端、非 TTY、`NO_COLOR` 或 Windows 纯文本环境，打开日志列出的 `.runtime/access-qr.*/index.html`（Windows 为 `access-qr-编号`）扫码，可保存 SVG/PNG。二维码不经过在线服务；隧道地址变化会重新生成，退出时页面标记失效。服务器可通过环境变量或 `.runtime/config.env` 的 `PUBLIC_BASE_URL=https://实际域名` 指定不含账户、查询参数或片段的基地址；未配置时仅显示明确标为“仅本机”的回环入口，手机无法访问。二维码辅助失败只告警，原 URL 与健康服务保留；产物由既有反部署清单管理。详见[二维码输出、固定依赖与使用边界](../公共组件/地址二维码/README.md)。

