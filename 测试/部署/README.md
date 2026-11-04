# 学术服务平台｜部署测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

对应 `部署/`，验证部署脚本和生命周期夹具，独立于前后端业务测试。

## 一、<span id="entry">职责与执行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 入口 | 验证内容 |
| --- | --- |
| `test_deploy.py` | Shell／PowerShell 解析、同名脚本包、快捷入口转交与路径、参数及退出码、配置和依赖保护；Windows CMD 只做静态核对，原生运行另验 |
| [双模式沙盒](./【测试】部署双模式.py/README.md) | 假 Go／选择器／隧道、临时回环服务与 PTY，核对取消、超时、退出及进程清理 |
| [反部署隔离测试](./【测试】反部署.py/README.md) | 各平台内嵌函数等价、真实入口只读转交、既有原点兼容、共享与未知资源、备份失败／源变化、清零确认、PID 身份、日志封口和中断重试 |

在项目根运行：

```shell
python3 './测试/运行测试.py/运行测试.py' --group deploy
```

用例覆盖各系统同名脚本包中的规范入口及标明“快捷入口”的启动文件；MacOS 沙盒从中文、空格及改名目录启动，工作目录设为工程外，验证只读检查、真实终端取消、参数与退出码。六份 `.desktop` 按格式规范解码后调用临时替身，检查迁移、目标缺失／歧义及 Alpine／FreeBSD 不依赖 bash；此隔离执行不替代目标桌面双击验收。

不安装系统依赖、不建立真实公网隧道、不修改正式数据。新输出位于本目录的 `证据/本轮/`，执行摘要由外层统一入口索引。沙盒通过不替代目标系统部署、真实公网或恢复演练。

生命周期从各平台真实部署／反部署脚本的 `BEGIN/END JOBS DEPLOYMENT LIFECYCLE` 标记内提取到临时夹具，仅加载函数，不执行真实 `main`。交付入口各自内嵌实现，测试不要求保留已删除的外部生命周期函数库。Windows 测试从两份 PowerShell 入口提取并比较函数块；原生 Windows 验收与跨宿主文件夹具分别记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
