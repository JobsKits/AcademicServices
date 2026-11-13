# 知序｜鸿蒙端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录是独立 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/) ArkTS／ArkWeb 宿主，归入前端的移动端，与 Flutter 技术目录并列。当前通过同源 HTTPS 加载 Flutter 用户页面，不是 Flutter OH 引擎；品牌仍为暂名，正式签收范围见[项目评审](../../../../需求/项目需求与开发评审/项目需求与开发评审.md#open-items)。

## 一、<span id="entry">当前能力与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

页面入口为 `entry/src/main/ets/Pages/Index.ets`，服务器配置位于 `entry/src/main/ets/Config/Endpoint.ets`。页面加载失败提供说明与重试；不忽略证书错误，不允许任意来源或本地 file 来源绕过安全校验。离线首启不能加载线上宿主，真实文件能力和原件保存尚未验收。

配置的同源页面继续在宿主内显示。用户主动点击的 HTTP／HTTPS 外链通过系统隐式 Want 请求浏览器处理，不指定浏览器包名；系统已设置默认处理器时由其接收，否则可能展示选择界面。普通主框架导航检查手势及重定向；`window.open` 检查 `isUserTrigger` 并关闭嵌入弹窗请求。同源新窗口回到当前宿主。其它 scheme、非法URL、URL内凭据、子帧外部导航、无手势／重定向外跳均阻止，不放宽文件访问或 TLS 校验。无法启动时显示失败提示；没有把 API 返回等同于目标页面加载完成。

原生浏览器失败Toast按恢复页当前语言覆盖简体／繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文，默认跟随系统；Web内的主题与语言仍由商城设置管理。

连接失败页使用暖色居中布局、大字号说明和重试按钮；语言可选跟随系统或十语言，主题可选跟随系统／白天／黑夜。文案集中于 `Config/ShellCopy.ets`，切换后错误说明同步更新；这些选项用于原生恢复页，Web内设置仍由商城管理。

## 二、<span id="prepare">准备与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录使用准备工具前先查看参数：

```shell
python3 ../Flutter/Tool/prepare_harmony.py --help
```

完整 Web 构建、HTTPS 地址生成、DevEco、签名与文件能力限制见[移动端工程的鸿蒙说明](../Flutter/README.md#harmony)。测试源码在外层 `测试/前端/移动端/鸿蒙/`，由[统一入口](../../../../测试/README.md)运行。合同检查通过只证明已检查的配置与源码，当前没有 HAP／APP 构建、签名安装或真机通过结论。

`prepare_harmony.py` 仅生成 `Endpoint.ets`；`Index.ets` 是唯一维护的宿主源码，不会被准备工具覆盖。当前6项合同检查包含17组从宿主提取并执行的导航策略案例、端点合法性及窗口释放／隐式启动约束；没有 DevEco／ArkTS SDK 编译、HAP、设备浏览器选择或 Flutter Web → ArkWeb → 浏览器的真机证据。目标设备应分别验证主框架链接、轮播 `window.open`、默认浏览器／无默认时选择、返回宿主、失败提示及非法链接拦截。

## 三、<span id="sources">API核验来源</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

按官方 OpenHarmony 文档核验 API 签名；当前工程编译SDK为7.0.0（26）、兼容SDK为6.1.0（23），文档所用接口从API9—12起可用。华为网页正文当时抓取超时，采用官方上游接口文档核对，不使用社区文章猜测签名：

- [ArkWeb导航与新窗口事件](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-events.md)：多窗口开启、普通导航拦截及新窗口处理。
- [新窗口事件字段](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-i.md#onwindownewevent12)与[ControllerHandler](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-ControllerHandler.md)：用户触发判断、目标地址及无嵌入窗口时传null释放。
- [WebResourceRequest](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-WebResourceRequest.md)：主框架、用户手势及重定向判定。
- [URL解析](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkts/js-apis-url.md)与[UIAbilityContext.startAbility](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-ability-kit/js-apis-inner-application-uiAbilityContext.md)：解析协议／origin／凭据，通过隐式Want启动系统处理器。
- [LocalizationKit.System.getSystemLanguage](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-localization-kit/js-apis-i18n.md#getsystemlanguage9)：原生浏览器失败提示采用系统语言。

## 四、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
