# <span id="前言">部署依赖版本解析器测试</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

本目录的 `main_test.go`、`module_report_test.go` 及平台限定测试是[版本解析组件](../../../部署/公共组件/依赖版本/README.md)的同包正式测试。测试文件保留在外层；通过复制源码与测试到项目外临时目录运行，不把测试或二进制写入部署源目录。

## 一、<span id="version-test-run">隔离执行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从项目根目录使用机器已有的 Go SDK：

```shell
version_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/deploy-version-test.XXXXXX")"
cp ./部署/公共组件/依赖版本/*.go ./部署/公共组件/依赖版本/go.mod \
  ./测试/部署/依赖版本/*.go "$version_test_dir/"
(
  cd "$version_test_dir" || exit 1
  GOWORK=off GOTOOLCHAIN=local go test -count=1 ./...
  GOWORK=off GOTOOLCHAIN=local go vet ./...
)
```

原生 PowerShell 同样将组件全部Go源码、go.mod及外置测试Go文件复制到单独临时目录，再设置进程级 `GOWORK=off`、`GOTOOLCHAIN=local` 后执行 Go 测试；无需 Python、Node.js、jq 或额外依赖安装。已有 race 工具链时可加 `-race`；缓存继续使用机器既有配置或调用方明确传入的项目外测试缓存。

## 二、<span id="version-test-scope">覆盖与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 数值版本及比较退出码、正式版优先、Go最低版本、目标归档和8列输出。
- fzf／cloudflared的精确文件名、来源、digest、平台缺包与禁止混用架构。
- 缺digest时的精确锁清单补充，以及旧版本、错误归属／URL／文件／类型、坏摘要和重复项拒绝。
- 限流／5xx／临时网络退出75，非法JSON／来源重定向／证书错误及参数校验不标成可重试；不会输出假成功行。

- 只读模块报告固定命令／副本及源指纹、拒绝源码内路径／符号与硬链接、失败不泄凭据、无更新与失败区分；假SDK不触真实模块。
- 假SDK派生心跳子进程，验证超时和Unix真实TERM后停止心跳；Windows独占Job实现另做交叉编译，目标系统原生回收行为需实机验证。

HTTP单测通过注入 Go `http.Client` 的 transport 将固定官方 URL 映射到本地 `httptest`；该映射只在测试源码存在，不提供生产覆盖参数。夹具不连接公网、不安装或升级 SDK、不启动／停止业务服务。真实官方元数据的只读小探测与各系统下载安装／生命周期验收分别进行，单测通过不能替代后两项。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
