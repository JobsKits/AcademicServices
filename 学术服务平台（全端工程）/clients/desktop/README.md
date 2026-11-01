# 知序桌面客户端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

这是面向客户的 [**Python**](https://www.python.org) 桌面用户端，由 Jobs 维护，当前为可运行的首版工程。只提供毕业论文、普刊、编译三项服务，与 [**Go**](https://go.dev/) 后端共用同一套接口和业务数据；运营人员使用工程中的 [**Flutter**](https://flutter.dev/) 管理后台。

## 一、<span id="quick-start">第一次使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、在本机 [**macOS**](https://www.apple.com/macos/) 上，直接双击本文件夹里的 `知序.app` 快捷入口即可打开已生成的应用。`知序.dmg` 用于分发同一份应用，普通使用者运行成品不需要安装 Python。

2、在 [**Windows**](https://www.microsoft.com/windows) 上，先双击 `【Windows】启动知序.bat` 从源码运行。窗口会说明用途；直接回车继续，任意字符或 `Ctrl+C` 取消。缺少 Python 时在工程内下载私有运行时，缺少依赖时再次说明来源并等待回车安装。需要可分发的成品时，在 Windows 本机双击 `【Windows】📦生成exe.bat`。

3、管理员先按[平台总说明](../../README.md)启动后端。客户端默认连接 `http://127.0.0.1:8080/api/v1`；远程服务器请在“连接设置”里填写管理员提供的 HTTPS 地址。更换地址会退出当前登录。

4、点击右上角“登录”，使用客户账号。开发环境样例账号为 `customer`，口令为 `demo-customer`；正式环境以管理员实际配置的口令为准。后台账号不能登录这个客户端。

5、从“服务首页”选择一项服务，填写带 * 的必填项；毕业论文填写专业与学历，普刊填写专业方向，编译填写源语言与目标语言，字数、日期与联系说明选填，确认有权使用材料后提交。成功后在“我的需求与订单”上传材料。

6、收到报价后核对范围、价格、启动款、有效期和修改额度，再确认生成订单。服务中可以留言；交付后可以下载文件、反馈修改、确认验收或发起售后。

首次双击 macOS 来源未公证的应用时，按系统提供的正常“打开”流程处理；本工程不会自动关闭 Gatekeeper 或清除隔离属性。当前安装包为本机 Apple Silicon 构建，Intel Mac 请在对应机器重新生成。

## 二、<span id="features">现在能够做什么</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 页面 | 可以操作的内容 |
| --- | --- |
| 服务首页 | 三服务说明与提交入口；服务下架时禁用提交；真实空目录有重载入口 |
| 需求表单 | 按服务显示填写提示；授权确认；提交后上传独立材料版本 |
| 需求详情 | 查看说明、版本与进度；补充未成交需求、撤回需求、发送留言 |
| 报价与订单 | 核对当前报价、确认 / 拒绝报价；查看已收、已退、处理中退款与凭据 |
| 交付与售后 | 私有文件下载、反馈修改、验收最新主交付 / 对应售后交付、申请售后 |
| 协商方案 | 确认 / 拒绝取消结算方案；确认 / 拒绝价格、期限和范围变更 |
| 连接与外观 | 设置 API 地址与1.5 / 2.5 / 5 / 10秒超时；白天 / 黑夜 / 跟随系统主题 |

附件最大8MB；较大文件可在连接设置选择10秒超时。下载目标已存在时不会覆盖，请选择新文件名。权限、费用、过期报价、并发版本、修改轮次及取消结算由服务器最终校验。客户端没有收取真实款项的支付 SDK，金额仅展示后端人工核实台账。

## 三、<span id="data-source">真实数据、演示与待核对</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 进入页面、定时刷新和写操作都会请求 API。请求成功后自动用服务器数据替换当前展示；返回空列表时显示真实空态。
- 无法连接、超时、5xx或响应格式错误时，读操作显示隔离的本地演示资料。顶部始终标明来源；不会把之前账号的私人缓存当作演示资料。
- 离线登录仅允许 `customer` 样例，演示支持需求提交、补充说明与留言，数据仅在当前会话保留。报价、资金、验收与复杂售后需要真实服务端。网络恢复后重新登录即可进入真实账号，演示写入不会上传。
- 真实会话中的写操作超时，可能已经在服务器完成。客户端保存原请求键、路径和正文，禁止继续发起另一笔写入；先点“重新核对”。未查到记录仍可能在途，可继续核对或点“使用原请求键重试”。重试保留完整原请求和原键，由服务器幂等处理。
- 401 / 403 清除当前授权和私人界面；其它4xx显示服务器原因，不能变成演示成功。请求禁止重定向，远程地址必须HTTPS。

口令与令牌仅在进程内使用。主题、地址、超时与按服务器 / 账号隔离的待核对记录保存在目标机器的用户目录；待核对记录可能包含业务材料，因此不要公开分享该目录：

| 系统 | 用户数据目录 |
| --- | --- |
| macOS | `~/Library/Application Support/Zhixu` |
| Windows | `%LOCALAPPDATA%\Zhixu` |
| 开发隔离测试 | 可用 `ZHIXU_DATA_DIR` 指定临时目录 |

## 四、<span id="scripts-build">双击入口与打包</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 入口 | 作用与输出 |
| --- | --- |
| `【MacOS】启动知序.command` | 检查 Python，必要时取得工程私有运行时与依赖，启动源码 |
| `【Windows】启动知序.bat` | 通过同工程 PowerShell 引导器完成 Windows 源码运行 |
| `【MacOS】📦生成dmg.command` | 本机打包 `Zhixu.app`，实际启动截图验证后生成 `Zhixu.dmg`，创建第一层相对快捷入口 |
| `【Windows】📦生成exe.bat` | Windows本机生成 `Zhixu/Zhixu.exe` 与完整目录ZIP，创建第一层 `.lnk` 快捷入口 |

所有入口先展示内置自述并等待回车；缺少必须依赖时“直接回车安装，任意字符取消”，安装失败停止。依赖健康时复用，不升级系统全局环境。下载 [**uv**](https://docs.astral.sh/uv/) 0.13.6 时使用其官方 Release，并校验同源 SHA256；Python 私有运行时放 `zhixu/.tools`，应用 / 构建依赖放 `zhixu/.build-venv`。

打包将清理本应用固定的 `dist` 旧包，拒绝符号链接和异常目录。每次产物放在 `dist/YYYY.MM.DD HH-mm-ss/`；APP / DMG或EXE / ZIP共用一次构建时间。成功后先打开磁盘位置，再启动本次软件。失败不会启动旧包或发布无效快捷入口。请将需要保留的历史安装包先复制到别处。

日志为 `zhixu/.build/session.log`；直接调用内层构建器也保留日志。源码、构建器、Hook输入与资源均相对本工程定位，可以整体复制改名。成品从包内读取资源，不依赖开发机源码位置。macOS与Windows安装包必须分别在对应系统构建，macOS不能直接生成Windows EXE。

## 五、<span id="structure-dependencies">工程与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
desktop/
├── README.md
├── 【MacOS】启动知序.command
├── 【Windows】启动知序.bat
├── 【MacOS】📦生成dmg.command
├── 【Windows】📦生成exe.bat
├── dist/                           # 每次打包的APP/DMG或EXE/ZIP
└── zhixu/
    ├── pyproject.toml
    ├── requirements.txt
    ├── build-requirements.txt
    ├── src/zhixu/                  # UI、HTTP仓库、配置、随包资源与许可
    ├── scripts/                    # 环境引导、本机打包、真实Go联调
    └── tests/                      # 仓库、真实HTTP夹具、Qt界面回归与证据
```

截至2026-10-30，按依赖声明统计：运行直接依赖1项、打包直接工具1项、PEP517构建工具1项，均为公库，没有私库依赖。版本通过官方包信息与本机实际环境核对；冻结构建目录保存本次工具环境快照，传递依赖不计入直接项。

| 依赖 | 固定版本 | 用途 / 许可证 / 来源 |
| --- | --- | --- |
| [**PySide6**](https://pypi.org/project/PySide6/6.12.0/) | 6.12.0 | Qt界面，LGPL-3.0-only或官方其它许可选项；项目选择LGPL分发条件 |
| [**PyInstaller**](https://pypi.org/project/pyinstaller/6.22.3/) | 6.22.3 | 本机打包；GPLv2-or-later及打包分发例外 |
| [**setuptools**](https://pypi.org/project/setuptools/84.2.1/) | 84.2.1 | Python包构建；MIT |

当前测试 Python 为3.15.2；源码要求3.10—3.15。PySide6 6.12.0 官方macOS轮子要求14.0及以上；本次ARM64成品只在macOS27.0.1实际验证，其它系统版本、Intel与Windows需在目标环境复测。商业分发前须履行所选Qt许可义务；原文和来源已随资源打包，见 `src/zhixu/assets/THIRD_PARTY_NOTICES.txt`。

## 六、<span id="verification">测试与回归</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在 `desktop/zhixu` 下运行：

```shell
PYTHONPATH=src \
  QT_QPA_PLATFORM=offscreen \
  python3 -m unittest discover \
    -s tests \
    -v

python3 -m compileall -q src scripts tests

python3 scripts/manage.py check
```

Windows源码测试可先执行 `$env:PYTHONPATH='src'` 与 `$env:QT_QPA_PLATFORM='offscreen'`，再执行相同的 `python -m unittest discover -s tests -v`。

[测试与验证说明](./zhixu/tests/README.md)记录各轮结果、冻结应用、独立复制与真实后端闭环证据。GUI离屏测试覆盖三服务、空态、主题、系统外观信号、报价 / 取消 / 变更按钮、两种窗口尺寸与文字对比；系统外观信号采用Qt信号夹具，不等同Windows或另一台Mac的真实系统外观切换。

开发者只对独立本机开发实例运行 `scripts/live_smoke.py`；它会创建测试需求与金额台账，请勿连接业务运行数据。该脚本覆盖真实客户 / 管理员接口、三服务需求、私有附件、报价、资金记录、开工、暂停恢复、修改、验收、售后和取消退款。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
