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

浏览器默认使用当前站点的 `/api/v1`。Android 模拟器默认访问 `10.0.2.2`，iOS 模拟器默认访问 `127.0.0.1`。真实手机须使用可访问的 HTTPS 域名，可在“设置 → 服务地址”修改。切换地址会清除当前会话和私有列表。

## 二、<span id="features">商城功能</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

| 页面 | 功能 |
| --- | --- |
| 商城首页与分类 | 毕业论文、普刊、编译，九个子服务，明确演示价格、课程／服务、缺货与上下架状态 |
| 商品详情 | 商品图片、简介、详情分节、交付说明、快照下单 |
| 收银台 | 支付宝／微信渠道弹窗，关闭不付款，主动确认模拟成功；当前不会扣款 |
| 订单 | 待付款、待完成、待评价、已完成与取消筛选；交付说明、确认完成及评分评价 |
| 管理端 | 商品名称、类别、价格、图片、详情、上下架与缺货编辑；开始服务和提交交付 |
| 设置 | 十语言、白天／黑夜／跟随系统，账户及服务地址，500—10000毫秒超时 |

商城为单一自营虚拟商品，无物流。商品详情由后台输入，其正文保持经营方原语言；界面交互支持简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文。设置持久化语言与主题；手动主题不受系统外观变化影响。

界面主色为暖棕与米白，黑夜使用暖深背景。商品图支持 HTTPS、打包资源及后台提供的 PNG／JPEG／WebP data URL；本地品牌图先显示，异步加载失败保留。品牌图复用本仓 `icon.png` 并打包在 `Assets/shop-brand.png`，无参考站外链图片依赖。

## 三、<span id="network">网络与未知写入</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

进入与刷新优先请求 API，初始本地目录即时显示。默认超时2.2秒，可在设置调整；读取失败回退隔离演示，后续成功响应自动覆盖为真实数据，真实空列表保留完整空态与重载。演示请求仍尝试 API，演示数据不会在恢复网络后自动重放到服务器。

登录错误、权限拒绝、状态或版本冲突均保留服务端结果，不伪造成功。真实写入超时或响应无法解析时保留原键和正文，先查询原操作或用原键重试；结果不明期间阻止新写，仓库并发写保护避免重复下单。未确认操作按账户和服务地址保存在本地，令牌和密码不落盘。离线演示仅为本地会话，订单和模拟支付不会同步为正式业务。

当前收银台为应用内 mock，不是正式微信／支付宝SDK，也不产生真实扣款。正式商户参数到齐后须接服务端签名、回调验签、主动查单与各端唤起验收；客户端不能自行声明真实付款成功。

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

业务页面使用文字编号，不依赖外部图标/照片。Flutter 内部控件的 Material 字体来自 Flutter SDK（BSD-3-Clause）；鸿蒙启动图为本工程自制 SVG。生成的平台默认图标仍需在正式品牌确认后替换。字体和前端资源随构建打包，不引用竞争网站素材。中日韩文字使用本地 Noto Sans CJK SC，藏文使用本地 Noto Serif Tibetan 后备字体；十语言交互与商品中文字符均做离线字形覆盖检查，来源、OFL许可证与哈希见[字体资源说明](./Assets/Fonts/README.md)。

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

在仓库根目录运行统一入口，或在本目录分析源码：

```shell
python3 ../../../../测试/运行测试.py/运行测试.py --group flutter
dart analyze --format machine lib/Shop
```

商城测试与范围见[外置测试说明](../../../../测试/前端/移动端/Flutter/README.md)。当前商城26项仓库／Widget测试通过，Dart商城源码分析无问题；覆盖九个子服务、四种窗口宽度、双渠道弹窗、完整订单动作、后台编辑、免费价格与多行详情保存、十语言、主题恢复、对比及未知写。用户与后台 Web 均可在独立 Dist 输出构建；源码／Widget、Web构建、iOS／Android／鸿蒙设备业务与真实渠道验收分别登记；未执行设备或正式支付不写为完成。

## 一、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


<a id="🔚" href="#前言">我是有底线的➤点我回到首页</a>
