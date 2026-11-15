# <span id="前言">部署依赖的官方稳定版本解析器</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

复用部署已准备的健康 [**Go**](https://go.dev/) 工具链编译，仅使用标准库，最低 Go 1.24.0。组件查询版本元数据并输出受校验的目标资产，也可对临时模块副本生成只读更新报告；下载、摘要复核、安装切换、归属清单及服务生命周期仍由各系统原生部署入口负责。测试源码独立放在[外置测试目录](../../../测试/部署/依赖版本/README.md)，部署不依赖该目录。

## 一、<span id="version-cli">构建与调用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录使用已准备的 Go 构建到本轮独占临时目录，调用方须传入目标系统与架构，不根据解析器自身的运行架构代猜：

```shell
go build -mod=readonly -trimpath -o "$RUN_DIR/deploy-versions" .
"$RUN_DIR/deploy-versions" --tool go --os darwin --arch arm64 --minimum-go 1.24.0
"$RUN_DIR/deploy-versions" --tool fzf --os linux --arch amd64 \
  --locked-manifest ../../deploy-tools.lock.tsv
```

`RUN_DIR` 由原生入口解析并准备；独立调用时先设置为自己的已有临时目录。首次机器没有 Go 时，入口先依照现有受控锁清单校验引导 SDK，再编译本组件检查当前官方稳定版本。

| 参数 | 合同 |
| --- | --- |
| `--tool` | 必填，`go`、`fzf` 或 `cloudflared` |
| `--os` | 必填，`darwin`、`linux`、`windows` 或 `freebsd` |
| `--arch` | 必填，`amd64` 或 `arm64`，不以另一架构资源替代 |
| `--minimum-go` | 仅 Go 查询可选，官方最新版本低于项目最低版本时拒绝 |
| `--locked-manifest` | 可选，仅为官方最新资产补缺失的摘要；不回退到锁内旧版本，不改清单 |

成功时 stdout 只输出一行无表头、恰好8列的 TSV，顺序与[工具锁清单](../../deploy-tools.lock.tsv)相同：

```text
tool<TAB>os<TAB>arch<TAB>version<TAB>filename<TAB>sha256<TAB>url<TAB>kind
```

版本不带 `go`／`v` 前缀；`kind` 为 `tar.gz`、`zip` 或 `binary`。当前最新正式版本没有目标平台资产时仍退出0，返回 `tool/os/arch/version/-/-/-/unsupported` 八列，原生入口据此检查已安装工具是否达到该正式版本，不下载其他架构，不把旧锁资产冒充最新。

## 二、<span id="version-sources">官方来源与校验边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- Go 只查询[官方发行元数据](https://go.dev/dl/?mode=json)，在 `stable=true` 条目中数值选择最高正式版本，核对归档版本、目标系统／架构、完整文件名及官方 SHA256；资源地址固定构造为 `https://go.dev/dl/` 下对应文件。
- [**fzf**](https://github.com/junegunn/fzf) 和 [**cloudflared**](https://github.com/cloudflare/cloudflared)分别查询各自 GitHub `releases/latest`；拒绝 draft／prerelease，正式标签、目标文件名和完整官方下载 URL 必须精确匹配。提供的 `digest` 须为 `sha256:` 加64位十六进制。
- 仅在目标资产未提供 digest 时，才从显式锁清单匹配相同工具、系统、架构、版本、文件名、URL及归档类型的既有 SHA256；缺少精确记录、重复记录或非法摘要均拒绝。官方已给出但非法的 digest 不能借旧锁绕过。
- 每次查询有15秒总期限、连接／响应期限和8 MiB响应限制；拒绝来源重定向、非法 JSON、额外响应内容及不合合同的元数据。没有运行态任意 URL、忽略证书、跳过摘要或假称缓存为最新的开关；代理仅沿用调用进程现有环境。

## 三、<span id="version-exit">退出码与版本比较</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 查询退出码 | 含义与调用方处理 |
| --- | --- |
| `0` | 已得到校验成功的8列行；仍须单独处理 `unsupported` |
| `75` | 临时网络／读取失败、HTTP 429／5xx，或 GitHub 403 且限流剩余额度为0；由原生入口按既有等待／取消规则仅重试元数据获取 |
| `2` | 参数、来源／证书、结构、正式标签、资产或摘要校验失败；stderr说明原因，stdout不输出成功行，不能作为下载地址或无限网络重试 |

比较模式不联网，仅接受两个参数：

```shell
"$RUN_DIR/deploy-versions" --compare go1.27.4 --at-least 1.27.3
```

安装版达到目标时输出 `1`、退出0；较旧时输出 `0`、退出1；非法版本退出2且 stdout 为空。仅接受两／三段非负数字版本，可带一个 `go` 或 `v` 前缀；按数值比较，拒绝预发布、后缀和整段命令输出。原生入口先提取真实工具版本，使用条件语句捕获结果，避免严格错误模式把“较旧”误当整次部署失败。

业务库版本与 SDK／工具版本分层管理。本组件不修改 `go.mod/go.sum`、Flutter或其他客户端锁；业务依赖先在临时 modfile／sum 副本中检查，经过独立回归后更新源码基线，部署使用已确认的版本合同。

## 四、<span id="module-report">业务Go依赖的限时只读报告</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

原生入口先将当前源码的 `go.mod`／`go.sum` 复制到模块外本轮运行目录，使用 `.mod` 及配对 `.sum` 文件名，再调用：

```shell
"$RUN_DIR/deploy-versions" --module-report \
  --go-bin "$GO_BIN" --module-dir "$SERVER_ROOT" \
  --modfile "$RUN_DIR/DependencyCheck/backend.mod" --timeout-seconds 30
```

`GO_BIN` 必须是调用方已验证的SDK绝对可执行路径；时限默认30秒，可配1—300秒。组件固定执行 `go list -m -u -json -mod=readonly -modfile=<临时副本> all`，不接受任意命令或额外参数。仅继承当前进程的代理、私库和缓存配置，子进程固定 `GOWORK=off`、`GOTOOLCHAIN=local`，不准备额外SDK或改持久环境。

临时mod／sum须是当前源码的完整普通文件副本；拒绝原 `go.mod`、模块内路径、符号链接、与源码共用的硬链接及不匹配副本。查询前后核对源mod／sum的内容与文件身份；发生独立变化时只报错，不用旧副本覆盖用户更新。stdout只在全部检查成功后输出有更新的模块，每行 `path<TAB>current<TAB>available`，按模块路径排序、无表头；查询成功且无更新时stdout为空。

- 退出0：报告完成；有更新也只是提示，未执行 `go get`、`tidy` 或源码版本变更。
- 退出3：查询失败、报告异常、超时或取消，stderr明确“检查未完成／已中止”，不转储Go错误原文、环境或凭据；原生入口可说明后继续按已确认的锁构建，不循环重试业务报告。
- 退出2：参数／路径／副本或源码不变性校验失败，原生入口停止核对，不能当成一般网络失败略过。该子模式不返回75。

SDK及其子树只属于本次检查：Unix使用独占进程组；Windows先挂起创建、绑定独占Job后恢复线程，并设置关Job时回收。超时、SIGINT／TERM取消及正常结束均清理本次检查子树，避免后台查询残留；不按名称或端口停止其他Go进程。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
