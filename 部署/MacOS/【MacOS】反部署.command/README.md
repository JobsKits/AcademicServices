# MacOS 反部署入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

部署与反部署的生命周期核心分别内嵌在本平台两份脚本中，覆盖原点、操作锁、进程身份、数据备份和资源恢复；两份脚本可分别执行，无须加载外部生命周期函数库。确认顺序、状态协议、数据策略及恢复边界见[原点与恢复协议](../../README.md#lifecycle-protocol)。

本脚本与[部署脚本](../【MacOS】部署.command/README.md)配对。平台目录的[反部署快捷入口](../【MacOS】双击反部署（快捷入口）.command)只调用本脚本；快照、备份和恢复函数均内嵌于本脚本，执行[原点与恢复协议](../../README.md#lifecycle-protocol)。复制时保持根目录 `代码/` 与 `部署/` 的相对层级。

## 一、<span id="usage">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本说明所在目录运行；也可从任意工作目录通过实际脚本路径调用：

```zsh
zsh './【MacOS】反部署.command' --check
zsh './【MacOS】反部署.command' --plan
zsh './【MacOS】反部署.command'
```

- `--check`／`--plan`只读，不停止服务、不下载工具、不写清单。缺少完整原点时返回未完成并保留现场。
- 正常入口先展示自述并等待回车；fzf默认选择“数据库数据备份”，也可明确选“数据库数据清零”。下一层默认取消，显式选择执行后还需按一次空格并回车复核。Esc、EOF、空选或选择器错误停止执行。
- 依赖系统 zsh、文件复制与SHA256工具，以及健康的 fzf；优先使用现有 PATH、`FZF_BIN` 或已登记的工程内工具，不自动联网安装。最低系统与机器配置沿用[MacOS部署说明](../README.md#minimum-machine)，备份另需至少一份完整数据、配置及清理暂存的空间。

## 二、<span id="scope">数据与环境恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

部署在写入前将 `.runtime/`、`.tools/` 的原状态、必要原件与后态登记在后端代码目录的 `.deployment-state/`；各平台共用归属门禁，不能在另一系统上猜测接管。反部署只恢复原件仍可信且目标未后改的资源，原有、共享、不明和冲突内容保留并明确报告。旧部署缺少记录时停止；不能补一份空清单后声称能够还原旧环境。

数据备份涵盖完整 `data/` 与匹配的 `.runtime/config.env`；附件存于 `state.json` 内。恢复包位于后端代码目录外的同级 `反部署备份/`，逐项校验与源快照复核成功后才处理源数据，失败保留源与已有备份。恢复包包含账户凭据和业务数据，按私有文件保管。清零不可恢复，必须明确确认。配置外部 [**PostgreSQL**](https://www.postgresql.org/) 时停止，不能把本地数据包当作外部数据库已备份或已清零。

只停止记录中 PID、启动时间与命令身份均匹配的部署进程；被复用的 PID、未知服务锁和仍活跃的数据锁会阻止清理。手工启动的服务、独立隧道及手工注册的常驻项仍由其管理入口处理。处理失败后保留原点、备份与检查点，按提示核对后重试；若仍有保留项，结果为部分完成。

## 三、<span id="validation">验证与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离验证入口见[反部署测试](../../../测试/部署/【测试】反部署.py/README.md)。语法及临时夹具通过不能替代原生双击、真实长期服务、外部数据库和实际业务恢复验收；本任务不对用户真实部署执行反部署测试。异常时保留 `.deployment-state/` 和已显示的恢复包位置，不删除清单、锁或业务快照来绕过保护。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
