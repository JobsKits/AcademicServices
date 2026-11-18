# 知序桌面客户端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

当前默认桌面入口已改为[MacOS／Windows原生工程](../README.md)，本目录仅保留迁移参考；既有Python成品不再代表当前默认客户端。

这是面向客户的 [**Python**](https://www.python.org) 桌面用户端，由 Jobs 维护，当前为可运行的首版工程。只提供毕业论文、普刊、编译三项服务，与 [**Go**](https://go.dev/) 后端共用同一套接口和业务数据；运营人员使用工程中的 [**Flutter**](https://flutter.dev/) 管理后台。

## 一、<span id="quick-start">打开与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在对应系统运行本目录启动入口，或使用已针对目标系统重新构建的安装包。首页与商品详情允许游客浏览，购买、订单和「我的」先进入登录流程，登录成功前不展示个人页，取消返回首页；后台读取期间仍可浏览与打开账户门。登录、注册、忘记密码共用一扇账户门：注册以邮箱验证码、用户名和两次一致密码完成；找回密码以绑定邮箱验证码重置，登录支持绑定邮箱或用户名。明确Demo环境可使用customer演示账号，密码demo-customer。

订单待完成时可查看站方交付；站方在响应式后台开始服务并提交交付后，买方确认完成，进入待评价，提交评分和文字后成为已完成。每个列表均提供空态与重新加载。

## 二、<span id="features">功能与设置</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 页面 | 功能 |
| --- | --- |
| 商品 | 三主分类、9个参考子服务、商品图及本地品牌兜底、详情分节、价格和缺货状态 |
| 订单 | 待付款、待完成、待评价、已完成筛选，未付款取消，模拟支付、交付查看、确认及评价 |
| 设置 | 用户名与头像上传；白天／黑夜／跟随系统；十语言选择并保存；切换账户。只有明确Demo才显示API地址与500—10000毫秒超时 |
| 管理操作 | 商品维护与站方交付通过独立响应式后台进行，桌面为买方客户端 |

界面支持简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文；商品名称和详情按后台配置原文显示。顶栏导航为首页／我的订单／个人中心图文入口，登录后个人中心显示用户名、头像及四种订单状态快捷入口。接单前允许编辑购买需求，接单后只读。

主题采用暖米白及暖深色，跟随系统可响应系统外观变化。 随包Noto字体及OFL许可位于`Assets/Fonts/`，进程内注册中日韩／藏文字体回退，不依赖网络或机器预装字体。

桌面采用顶栏图文导航、居中内容区和清晰的标题／价格层级；引导文案与轮播在宽窗并排、窄窗上下排列，商品网格随窗口变为双列或单列。尺寸变化只重排已有控件，保留表单、轮播及列表上下文；卡片使用暖色细边框，输入与按钮提供焦点和悬停状态。

登录后继续原购买确认，仍需主动提交；购买／需求编辑／支付／评价的表单直到服务端成功才关闭，失败保留输入和持续错误，提交中防重复。读取失败保留已取得的真实商品与订单并显示更新失败，后续成功响应采用服务端资料；403权限和404资源缺失不冒充断网。详情返回和刷新保留列表滚动位置，空态配原生语义图标与重载，首页不放常驻重新加载按钮。服务端成功返回空轮播表示全部下架，隐藏运营位；只有未取得配置时才展示本地种子，后续失败保留最近已知配置。多图按4.5秒自动轮播，鼠标可在图片上左右拖动，分页点位于图片内部右下；悬停或分页按钮聚焦不会阻断自动切换，拖动期间及应用退到后台时暂停。不显示播放控制和数字页码。游客设置只有语言、主题及Demo连接选项，不放登录按钮；登录入口保留在页面右上。登录后头像与用户名替换登录入口，设置齿轮收在个人中心，保持单一入口。头像上传立即使用，无人工审核；未上传时分配系统头像。

## 三、<span id="data-source">数据、模拟支付与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

进入、刷新及写操作先请求API，服务不可用时使用隔离演示，后续成功响应自动替换真数据。演示订单不上传为真实订单；真实订单请求超时保留原幂等键，可恢复网络后重试。401／403保留真实错误并清理授权数据。

当前支付记录mode为mock，渠道为alipay或wechat，确认后显示待完成；该记录不代表实际扣款。真实支付SDK、签名与回调随商户资料接入。商品图先显示随包品牌图，图片加载失败保留兜底。

源码入口为 `Zhixu/src/zhixu/shop.py`，数据仓库为 `shop_repository.py`，十语言资源为 `Assets/shop_strings.json`；配置保存主题、语言、API和超时，不保存登录口令或会话。源码与Qt离屏测试见[测试说明](../../../../测试/前端/PC端/Python/README.md)，完整订单HTTP回归与未验证设备见[商城回归](../../../../测试/商城回归/README.md)。本次源码变化须重新构建安装包才能进入成品，不把磁盘现有成品当作当前源码产物。

## 四、<span id="scripts-build">双击入口与打包</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 入口 | 作用与输出 |
| --- | --- |
| `【MacOS】启动知序.command` | 检查 Python，必要时取得工程私有运行时与依赖，启动源码 |
| `【Windows】启动知序.bat` | 通过同工程 PowerShell 引导器完成 Windows 源码运行 |
| `【MacOS】📦生成dmg.command` | 本机打包 `Zhixu.app`，实际启动截图验证后生成 `Zhixu.dmg`，创建第一层相对快捷入口 |
| `【Windows】📦生成exe.bat` | Windows本机生成 `Zhixu/Zhixu.exe` 与完整目录ZIP，创建第一层 `.lnk` 快捷入口 |

所有入口先展示内置自述并等待回车；缺少必须依赖时“直接回车安装，任意字符取消”，安装失败停止。依赖健康时复用，不升级系统全局环境。下载 [**uv**](https://docs.astral.sh/uv/) 0.13.6 时使用其官方 Release，并校验同源 SHA256；Python 私有运行时放 `Zhixu/.tools`，应用 / 构建依赖放 `Zhixu/.build-venv`。

打包将清理本应用固定的 `Dist` 旧包，拒绝符号链接和异常目录。每次产物放在 `Dist/YYYY.MM.DD HH-mm-ss/`；APP / DMG或EXE / ZIP共用一次构建时间。成功后先打开磁盘位置，再启动本次软件。失败不会启动旧包或发布无效快捷入口。请将需要保留的历史安装包先复制到别处。

日志为 `Zhixu/.build/session.log`；直接调用内层构建器也保留日志。源码、构建器、Hook输入与资源均相对本工程定位，可以整体复制改名。成品从包内读取资源，不依赖开发机源码位置。MacOS与Windows安装包必须分别在对应系统构建，MacOS不能直接生成Windows EXE。

## 五、<span id="structure-dependencies">工程与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
desktop/
├── README.md
├── 【MacOS】启动知序.command
├── 【Windows】启动知序.bat
├── 【MacOS】📦生成dmg.command
├── 【Windows】📦生成exe.bat
├── Dist/                           # 每次打包的APP/DMG或EXE/ZIP
└── Zhixu/
    ├── pyproject.toml
    ├── requirements.txt
    ├── build-requirements.txt
    ├── src/zhixu/                  # UI、HTTP仓库、配置、随包资源与许可
    └── Scripts/                    # 环境引导与本机打包

../../../../测试/前端/PC端/Python/                  # 仓库、HTTP夹具、Qt界面与成品验证
```

截至2026-10-30，按依赖声明统计：运行直接依赖1项、打包直接工具1项、PEP517构建工具1项，均为公库，没有私库依赖。版本通过官方包信息与本机实际环境核对；冻结构建目录保存本次工具环境快照，传递依赖不计入直接项。

| 依赖 | 固定版本 | 用途 / 许可证 / 来源 |
| --- | --- | --- |
| [**PySide6**](https://pypi.org/project/PySide6/6.12.0/) | 6.12.0 | Qt界面，LGPL-3.0-only或官方其它许可选项；项目选择LGPL分发条件 |
| [**PyInstaller**](https://pypi.org/project/pyinstaller/6.22.3/) | 6.22.3 | 本机打包；GPLv2-or-later及打包分发例外 |
| [**setuptools**](https://pypi.org/project/setuptools/84.2.1/) | 84.2.1 | Python包构建；MIT |

当前测试 Python 为3.15.2；源码要求3.10—3.15。PySide6 6.12.0 官方MacOS轮子要求14.0及以上；本次ARM64成品只在MacOS27.0.1实际验证，其它系统版本、Intel与Windows需在目标环境复测。商业分发前须履行所选Qt许可义务；原文和来源已随资源打包，见 `src/zhixu/Assets/THIRD_PARTY_NOTICES.txt`。

## 六、<span id="verification">测试与回归</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在仓库根目录运行统一入口，自动设置源码路径与离屏环境：

```shell
python3 ./测试/运行测试.py/运行测试.py --group desktop
```

测试文件与执行证据位于外层 `测试/前端/PC端/Python/`，不要求在核心代码目录建立测试副本。仅检查源码与打包环境时，在本端的 `Zhixu` 目录运行 `python3 Scripts/manage.py check`；该检查不生成安装包。

[测试与验证说明](../../../../测试/前端/PC端/Python/README.md)记录各轮结果、冻结应用、独立复制与真实后端闭环证据。GUI离屏测试覆盖三服务、空态、主题、系统外观信号、报价 / 取消 / 变更按钮、两种窗口尺寸与文字对比；系统外观信号采用Qt信号夹具，不等同Windows或另一台Mac的真实系统外观切换。

开发者只对独立本机开发实例运行 [桌面真实接口冒烟脚本](../../../../测试/前端/PC端/Python/live_smoke.py)；它会创建测试需求与金额台账，请勿连接业务运行数据。该脚本覆盖真实客户 / 管理员接口、三服务需求、私有附件、报价、资金记录、开工、暂停恢复、修改、验收、售后和取消退款。

## 一、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。




<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
