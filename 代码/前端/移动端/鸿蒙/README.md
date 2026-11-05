# 知序｜鸿蒙端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录是独立 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/) ArkTS／ArkWeb 宿主，归入前端的移动端，与 Flutter 技术目录并列。当前通过同源 HTTPS 加载 Flutter 用户页面，不是 Flutter OH 引擎；品牌仍为暂名，正式签收范围见[项目评审](../../../../需求/项目需求与开发评审/项目需求与开发评审.md#open-items)。

## 一、<span id="entry">当前能力与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

页面入口为 `entry/src/main/ets/Pages/Index.ets`，服务器配置位于 `entry/src/main/ets/Config/Endpoint.ets`。页面加载失败提供说明与重试；不忽略证书错误，不允许任意来源或本地 file 来源绕过安全校验。离线首启不能加载线上宿主，真实文件能力和原件保存尚未验收。

## 二、<span id="prepare">准备与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录使用准备工具前先查看参数：

```shell
python3 ../Flutter/Tool/prepare_harmony.py --help
```

完整 Web 构建、HTTPS 地址生成、DevEco、签名与文件能力限制见[移动端工程的鸿蒙说明](../Flutter/README.md#harmony)。测试源码在外层 `测试/前端/移动端/鸿蒙/`，由[统一入口](../../../../测试/README.md)运行。合同检查通过只证明已检查的配置与源码，当前没有 HAP／APP 构建、签名安装或真机通过结论。

## 一、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
