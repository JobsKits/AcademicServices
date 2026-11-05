# 运行测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[运行测试.py](./运行测试.py) 是学术服务平台的统一测试入口。按脚本位置解析仓库根目录，从外层 `测试/` 运行各端用例，结果写入同目录体系。代码、测试、需求互为同级，运行测试不向代码目录复制或创建测试源码链接。

## 一、<span id="usage">运行与分组</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令以仓库根目录为基准。使用已有 [**Python**](https://www.python.org) 运行，未提供分组或传入 `--list` 时只展示能力，不运行用例、不创建证据目录。显式选择分组后执行，无需额外回车。

```shell
python3 './测试/运行测试.py/运行测试.py' --list

python3 './测试/运行测试.py/运行测试.py' \
  --group mini \
  --group harmony

python3 './测试/运行测试.py/运行测试.py' \
  --group go \
  --go /现有工具链/bin/go
```

`--group` 可以重复，按给定顺序运行并去重；`--group all` 或 `--all` 运行全部分组。也接受位置参数，如 `python3 './测试/运行测试.py/运行测试.py' mini harmony`。全部分组要求对应工具和已安装的项目依赖均可用；缺少工具会明确报阻塞并返回非零退出码，不自动安装，也不把跳过项记作通过。

| 分组 | 实际动作 | 条件与边界 |
| --- | --- | --- |
| `go` | 临时 overlay 映射外层 Go 同包测试（含商城），运行 race 回归与 vet | 需要现有 [**Go**](https://go.dev/) 及模块缓存；PG 用例需要专用空库 `TEST_DATABASE_URL`，未配置会在原测试中明确跳过 |
| `desktop` | `unittest discover` 运行外层桌面测试，GUI 使用离屏平台 | 需要已有 [**PySide6**](https://doc.qt.io/qtforpython/)；打包测试只操作隔离夹具，不生成安装包 |
| `http` | 编译临时 Go 服务，使用动态回环端口执行真实 HTTP 与重启检查 | 不连接正式业务实例；临时目录、数据与进程由测试清理 |
| `deploy` | 顺序运行基础部署与双模式夹具 | 检查脚本、假工具、回环和 PTY；不准备系统依赖、不建立公网隧道；PowerShell 缺失等跳过以日志为准 |
| `mini` | 通过 [**Node.js**](https://nodejs.org) 测试微信HTTP仓库与商城页面／订单逻辑（test_mini.cjs、test_shop.cjs） | 不代表开发者工具、真机、微信身份或发布验收 |
| `flutter` | 从代码端工作目录运行外层移动端与后台四份 [**Flutter**](https://flutter.dev/) 测试，含商城 `shop_test.dart`，带 `--no-pub` | 必须已有 SDK、包配置与依赖；不运行 pub get，不构建移动安装包 |
| `harmony` | 检查鸿蒙生成器与 HTTPS 宿主合同 | 不调用 DevEco，不生成 HAP，不证明真机文件能力 |

## 二、<span id="tools">参数与工具定位</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 参数／环境变量 | 行为 |
| --- | --- |
| `--go`／`GO_BIN` | 指定已有 Go 可执行文件；否则依次检查代码端 `.tools/go/bin/go` 与 PATH |
| `--python` | 指定桌面解释器；否则复用桌面端 `.build-venv` 或当前 Python |
| `--flutter` | 指定已有 Flutter 可执行文件；否则按 PATH 查找 |
| `--timeout` | 每条命令最长秒数，默认 900；超时结束本次命令及其子进程，记为失败 |
| `TEST_DATABASE_URL` | 仅提供独立可清理的空测试库；不使用生产库或已有业务库 |

Go 执行限定 `GOTOOLCHAIN=local`、`GOPROXY=off`，不自动下载 SDK 或模块；现有缓存缺依赖时明确失败。其它命令复用各自已有环境。目录移动后若 Python 虚拟环境或 Flutter 缓存含旧路径，应按模块说明重建开发环境，不能把本机旧绝对路径固化进本入口。

## 三、<span id="evidence">结果、日志与失败处理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

运行前展示所选组、工作目录、命令和日志位置。每次执行在 `../报告与证据/本轮/YYYY.MM.DD HH-mm-ss-微秒/` 保存跨组 `执行摘要.json`；每条命令的日志与截图按职责进入前端、后端或部署目录内的 `证据/本轮/`。Flutter 同时覆盖移动与后台的共享日志放 `前端/报告与证据/本轮/`，不覆盖历史证据。失败分组保留日志，继续运行其它已选组，最终返回非零。命令退出码为零时仍需阅读日志中的跳过项与测试范围，不能等同全端或正式验收通过。

Go overlay JSON 只存在系统临时目录并在结束时清理。私有业务测试使用临时数据，测试入口不打印环境变量或凭据。测试产生编译缓存等工具临时文件，不执行真实部署、正式资金操作或商店发布。

二维码工具可单独使用 `--group qr --go 实际Go路径`，通过临时 Go overlay 注入 `测试/部署/地址二维码/main_test.go`；不在部署源码生成测试副本。执行时使用项目外的测试缓存，避免修改正在运行部署的 `.tools` 归属资源。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
