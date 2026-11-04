# 知序 · Flutter 用户端与共享包

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录是 [**Flutter**](https://flutter.dev/) 用户端工程及共享 zhixu 包，用户端入口为 `lib/main.dart`；[独立后台工程](../../后台管理端/Flutter/README.md)通过 path 依赖复用本目录的接口、状态、界面和主题。普通操作者先阅读平台根目录的使用说明；本页面向本机运行、构建和验收。

## 一、<span id="start">快速体验</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

先启动 Go 服务。服务默认地址为 `http://127.0.0.1:8080`。打开后端托管的 `/admin/` 可直接使用已经构建的管理页面。用户预览由平台的 `/client/` 提供。

客户演示账户为 `customer` / `demo-customer`，管理员为 `admin` / `demo-admin-change-me`。这些仅是本机演示默认值，正式部署按配置修改。首次登录会请求服务；只有网络不可用且明确点击演示账户入口时才进入隔离演示，密码错误不会伪造登录成功。

开发者在本目录运行：

```shell
flutter pub get --enforce-lockfile
flutter run --dart-define=API_BASE_URL=https://你的域名/api/v1
```

管理端请进入[独立后台工程](../../后台管理端/Flutter/README.md)，按其 `lib/main.dart` 入口运行与构建；共享实现仍以本工程为唯一维护源。

浏览器默认使用当前站点的 `/api/v1`。Android 模拟器默认访问 `10.0.2.2`，iOS 模拟器默认访问 `127.0.0.1`。真实手机须使用可访问的 HTTPS 域名，可在“我的 → 配置服务地址”修改。切换地址会清除当前会话和私有列表。

## 二、<span id="features">当前功能</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

| 页面 | 功能 |
| --- | --- |
| 服务 | 毕业论文、普刊、编译；说明、分服务必填字段、选填字数与日期、授权勾选 |
| 需求 | 标题/编号/状态搜索、版本、报价、资金、进度、私有附件 |
| 客户办理 | 补充、接受/拒绝报价、修改反馈、验收、条款变更、取消结算确认、售后与消息 |
| 管理办理 | 报价、人工核实收款、开工、多原因暂停/恢复、正式交付、受理修改轮、取消方案、退款申请/审核/核实、售后关闭 |
| 我的 | 登录/切换/退出、API 地址、白天/黑夜/跟随系统 |

动作由当前阶段与角色决定，最终由服务端再次校验。办理表单提供交付、收款、退款、反馈、变更和暂停原因下拉选择，附件使用多选。修改批次自动生成，管理员可在同轮补充时复用已有标识。金额输入单位为元，发送前转换为整数分。退款申请、批准、结果未知和核实成功分别显示，申请不代表钱已退回。

所有动态列表有空态和重新加载入口。真实成功空列表保持为空，不用演示条目填满。登录令牌仅保存在内存中，不写入偏好设置；重新打开应用需登录。

## 三、<span id="network">网络与未确认操作</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

读取超时默认 2.2 秒，可由仓库构造参数调整。读取失败会切换到隔离演示，保留真实会话以便后续重新加载自动恢复。任何 `401` 都撤销会话与私有列表；`403/409/422` 显示真实拒绝，不改为演示成功。坏结构的响应在进入列表前被拒绝。

真实写入失败时，界面保留原请求与幂等键并显示“结果待确认”。使用“查询原操作”按原键读取已提交结果；404 仅代表尚未发现已提交记录。使用“重试原请求”只发送原键和原正文，后端幂等校验避免重复执行。结果未确认期间不接受另一笔写入。

未确认正文和键按服务地址与账户保存在应用本地偏好目录/浏览器存储，用于重启后核对；不保存密码和令牌，其他账户不会显示这些数据。该本地存储不是加密保险箱；正式设备按操作者权限管理。平台存储不可用时只能保护当前会话，服务器幂等台账仍然保留。已核实完成/明确拒绝后清理本地待核对记录。

附件最大 8 MB，使用授权接口上传与下载。上传断网时显示原键并要求先重新加载核对附件，避免立刻选择相同文件重传。上传原件不在演示模式保存。

## 四、<span id="build">构建与设备适配</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

用户预览在本目录构建；后台在独立 `../../后台管理端/Flutter` 工程构建，并通过本地包依赖共用业务。完整输出分别复制到 `代码/后端/后端代码/client-web/` 与 `admin-web/`：

```shell
flutter build web \
  --release \
  --no-web-resources-cdn \
  --base-href /client/ \
  --output Dist/Client
```

后台命令见[后台工程说明](../../后台管理端/Flutter/README.md)。
两包均包含本地 CanvasKit 渲染资源，不依赖运行时从公共 CDN 获取渲染器。路径末尾的 `/` 必须保留。APK/AAB 的 release 构建不复用开发签名，发布者须在 Android 工程配置自己的 keystore；iOS 上架须配置自己的签名和团队。

[**iPhone Duo**](https://developer.apple.com/iphone-duo/) 使用可变化的场景窗口尺寸。布局按可用宽度调整导航和列表/详情，使用 `SafeArea`、`DisplayFeatureSubScreen`、可滚动表单和键盘避让；不按机型判断宽度。已编写 320、390、678、934、1440 宽窗口与大字号测试。代表尺寸测试不等于 Duo 真机、铰链、多个独立窗口或所有姿态验收；多窗口独立 Flutter 引擎尚未实现，`UIApplicationSupportsMultipleScenes` 保持关闭。

## 五、<span id="harmony">鸿蒙交付方式</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

本轮鸿蒙使用同一 Flutter Web 用户界面与 [**ArkWeb**](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-component-overview) 原生宿主，源码位于 `../鸿蒙/`。这是需要在线加载页面的混合实现。普通 Flutter stable 不含 OHOS 后端；本工程未交付 CPF 原生 Flutter OH 引擎适配。

开发者先填写正式 API 域名，生成同源页面配置与用户端 Web 包：

```shell
python3 Tool/prepare_harmony.py \
  --api https://你的域名/api/v1
```

脚本只接受 `https://域名/api/v1`，将固定的同源 `https://域名/client/?host=harmony` 写入 `../鸿蒙/entry/src/main/ets/Config/Endpoint.ets`。构建生成的 `Dist/Client/` 必须完整部署到同一后端的 `client-web/`。宿主使用 HTTPS 页面，不使用本地 `file:` 页面；API 与页面同源，无需放开 `Origin: null` 或通配 CORS。用 `--check` 只检查路径和工具，不构建、不写配置。Harmony 构建目标配置 API 26、最低 API 23，hvigor 来自最新 DevEco 工具链，不在本工程锁入旧版 OHOS Flutter 插件。

安装官方最新版 [**DevEco Studio**](https://developer.huawei.com/consumer/cn/deveco-studio/)，打开 `../鸿蒙/`，选择匹配 SDK、配置自己的调试/发布签名后构建 HAP 和 APP。当前电脑没有 DevEco/鸿蒙 SDK，故未实编、未签名、未设备安装，配置值需在目标工具链首次导入时核实。

宿主限制页面导航在配置的 HTTPS 来源，禁用 file access 与混合内容，证书错误沿用系统默认拒绝。首次启动必须能访问页面；连接失败或主页面 HTTP 错误显示本地说明与“重新加载”，尚未实现离线首启。页面成功加载之后，API 失败仍使用 Flutter 现有的隔离演示规则。宿主通过 `onShowFileSelector` 拉起原生文件选择器；原件保存暂不支持，页面通过 `host=harmony` 明确提示使用 iOS/Android/桌面端授权下载。首发前必须在实际 ArkWeb 验证页面渲染、文件选择、证书拒绝、同源请求与加载失败重试；源码合同检查不能代替 HAP 构建与设备验收。

## 六、<span id="deps">依赖与资源来源</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

2026-10-30 核实 Flutter 3.47.8 stable / Dart 3.13.7；直接依赖按 [**pub.dev**](https://pub.dev/) 最新稳定版锁定：`http 1.6.0`、`shared_preferences 2.5.6`、`file_picker 13.3.0`、`flutter_lints 6.0.0`。完整解析结果在 `pubspec.lock`。本轮已将兼容可升级的传递依赖全部更新，包括 `shared_preferences_foundation 2.6.1`、`meta 1.19.0`、`vector_math 2.4.4` 等。剩余 `cross_file`、`material_color_utilities`、`test_api` 受上游插件/Flutter SDK 版本约束，没有强制覆盖为不兼容版本；差异记录在 `依赖状态.json`，不能称这三项也是最新上游版本。

业务页面使用文字编号，不依赖外部图标/照片。Flutter 内部控件的 Material 字体来自 Flutter SDK（BSD-3-Clause）；鸿蒙启动图为本工程自制 SVG。生成的平台默认图标仍需在正式品牌确认后替换。字体和前端资源随构建打包，不引用竞争网站素材。

上游来源：[HTTP](https://pub.dev/packages/http)、[Shared Preferences](https://pub.dev/packages/shared_preferences)、[File Picker](https://pub.dev/packages/file_picker)、[Flutter 发布记录](https://docs.flutter.dev/release/release-notes)、[Apple Duo 适配说明](https://developer.apple.com/videos/play/tech-talks/111461/)。CPF 远端正式 tag 核对为 `3.35.7+ohos-1.0.5`，它与当前 stable/插件版本不同步，故采用上述 ArkWeb 路线。

## 七、<span id="android-toolchain">Android 最新工具链</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

2026-10-30 按官方来源更新项目专属配置，未使用脚手架默认值冒充最新：

| 项目 | 当前配置 | 核对来源 |
| --- | --- | --- |
| AGP | 9.4.0 | [Android 官方发布记录](https://developer.android.com/build/releases/agp-9-4-0-release-notes) |
| Gradle | 9.8.2 binary，固定官方 SHA-256 | [Gradle 发布说明](https://docs.gradle.org/current/release-notes.html) |
| Kotlin KGP运行时 | 2.4.21（AGP内置Kotlin，顶层classpath固定） | [Kotlin 发布记录](https://kotlinlang.org/docs/releases.html) |
| compileSdk / targetSdk | 37 / 37 | [Android 17 SDK 配置](https://developer.android.com/about/versions/17/setup-sdk) |
| Build Tools | 37.0.0 | Android SDK Manager |
| NDK | 30.0.16248370（r30 最新 LTS） | [NDK 下载页](https://developer.android.com/ndk/downloads) |
| 最低系统 API | 24 | 当前文件与设置插件的最低要求 |

当前 Android 插件支持内置 Kotlin，工程启用 `android.builtInKotlin=true`；按照 Flutter 当前兼容方案保留 `android.newDsl=false`。最新 KGP 在 settings 插件解析与顶层 buildscript classpath 同时固定，确保先于 AGP 默认旧 KGP 解析；app 模块不再应用旧 kotlin-android 插件。

本机原有平台 36/36.1、NDK 28，最新组合须下载平台 37 与 NDK 30。首轮 Gradle 压缩包不完整导致解压失败，保留在日志中；已改为官方 binary 包并加入官方 SHA-256 校验后重试。后续使用完整校验过的 Gradle 与私有缓存重试，最后按同一最新组合对齐 KGP classpath，已通过 Flutter 的 Kotlin 最低版本检查并进入 AGP 项目配置；随后官方 NDK 30 下载出现 `Premature EOF`，构建停止，未生成 APK。最后依据为 `../../../../测试/前端/移动端/Flutter/证据/build-android-kgp-aligned.log`。修复网络下载后，在 Android Studio SDK Manager 安装 API 37、Build Tools 37.0.0、NDK 30.0.16248370，再运行 `flutter build apk --release`。本轮源码配置不等于 APK 产物或 Android 设备验收通过。缺少 SDK 或网络失败时停止，不默默降到旧版本。

## 八、<span id="tests">回归方式</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

```shell
python3 ../../../../测试/运行测试.py/运行测试.py --group flutter
dart analyze --format machine lib
```

当前最终 Flutter 回归为 `../../../../测试/前端/移动端/Flutter/证据/test-round-12.log`：34项通过；`../../../../测试/前端/移动端/Flutter/证据/analyze-final.log` 为空表示零问题。新增表单提交回归发现并修复了弹窗退出动画中控制器过早释放的问题，失败日志保留于第7轮。第9轮管理员窄屏测试缺少滚动后等待，补齐测试帧等待后第10轮33项全部通过。最终第12轮为34项通过，另覆盖模拟铰链占用下控件不跨越不可用区域；该几何夹具仍不等于真实Duo设备姿态验收。

另可运行 `python3 ../../../../测试/前端/移动端/鸿蒙/test_prepare_harmony.py` 验证 HTTPS 同源配置与宿主源码保护（4项通过）。测试覆盖三类表单必填/选填、弹窗退出生命周期、公开服务连接标识、API、真实空列表、离线恢复、401/403/422、未知写幂等重试/重启恢复、跨账户及迟到读取隔离、坏响应、宽窄窗口、大字体、空态和主题对比。各轮日志保留在 `../../../../测试/前端/移动端/Flutter/证据/`。`flutter analyze` 在本机长中文路径触发上游 LSP 分块解析错误，使用同 SDK 的 `dart analyze --format machine` 完成源码分析；分析通过与 Web/原生构建分别记录，不混为设备验收。

## 一、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


<a id="🔚" href="#前言">我是有底线的➤点我回到首页</a>
