# 学术服务平台｜依赖更新隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

从八平台真实部署／反部署脚本提取函数，使用临时工程、假 SDK、固定元数据与本地归档验证更新流程。不运行真实部署、不联网安装 SDK、不更新业务模块或修改正式数据。

## 一、<span id="run">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```shell
python3 './【测试】依赖更新.py'
```

需要已有[**Python 3**](https://www.python.org)、Shell 与基础归档／摘要工具；可用的[**PowerShell**](https://learn.microsoft.com/powershell/) 用于 Windows 函数夹具。用例只写系统临时目录，并将 HOME、XDG 缓存和 Windows 缓存位置隔离；跨宿主夹具不替代目标系统原生验收。

真实元数据 helper 的模块报告用例需要已有的已编译 helper，通过 `DEPENDENCY_TEST_RESOLVER` 指定绝对路径；没有指定时该项明确跳过，其余用例照常执行。可在[共享组件目录](../../../部署/公共组件/依赖版本/README.md)用已有健康[**Go**](https://go.dev)离线构建到工程外临时路径，再传入该变量；此报告用例仍使用假 SDK，不访问模块网络。

统一部署回归入口已收录本组：

```shell
python3 './测试/运行测试.py/运行测试.py' --group deploy
```

## 二、<span id="coverage">覆盖范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 场景 | 核对内容 |
| --- | --- |
| 官方查询参数 | 七 POSIX 入口与 Windows 合同；`--minimum-go` 只用于 Go，服务器不查询 cloudflared |
| 版本择新 | 旧 PATH 不能绕过检查；健康且达标的工具可复用，显式旧路径停止并保留原件 |
| 下载验证 | 本地归档的真实 SHA256、健康复检与版本目录采用；摘要或元数据错误立即失败，不回旧锁冒充最新 |
| 平台缺资产 | unsupported 时停止；仅显式健康原生工具且版本达标可继续 |
| 项目外缓存 | 新版本不进入工程 `.tools`；反部署只复用封存摘要匹配的缓存 fzf；独立收据撤回本项目新增且未改对象，原有与后改对象保留 |
| 可取消获取 | 元数据 exit75 退避及下载等待中发送 TERM，回收本轮 helper／下载子进程，不继续构建或启动 |
| 只读业务检查 | 真实 helper 配假 SDK报告更新，模块外临时 mod／sum 副本；源锁逐字节不变 |
| 退出码 | 报告0成功、3未完成警告后按锁构建、2验证失败停止，取消传播 |
| Windows 缓存原点 | PowerShell 临时文件夹具验证独立 owner、原件恢复、新增资源撤回和后改保留 |

## 三、<span id="limits">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

11 项专项在提供 helper 且本机工具齐备时全部执行。网络 HTTP 状态分类、官方来源与摘要解析由[依赖版本组件测试](../依赖版本/README.md)验证；本组不把假工具版本当作官方最新证据。目标系统原生下载、Windows Ctrl+C／ACL／进程树、真实公网和生产恢复需各自验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
