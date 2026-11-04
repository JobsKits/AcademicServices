# 知序｜前端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

前端按产品端归类，再按已选技术组织源码；不因目录模板新增未确认的端。测试源码、计划与证据统一位于外层 `测试/`。

## 一、<span id="entry">职责与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 产品端 | 当前实现与入口 |
| --- | --- |
| PC端 | [Python 桌面程序](./PC端/Python/README.md)，Windows／MacOS 共用源码 |
| 移动端 | [Flutter](./移动端/Flutter/README.md) 跨平台用户端；[鸿蒙](./移动端/鸿蒙/README.md)为现有原生在线宿主 |
| 后台管理端 | [独立 Flutter Web 入口](./后台管理端/Flutter/README.md)，本地包依赖复用业务 |
| 微信小程序 | [微信官方原生](./微信小程序/README.md)，本期独立前端 |

用户 Web 预览由移动端 Flutter 的标准 `web/` 目录构建。没有独立原生 iOS／Android 业务工程时不伪造平行目录；Flutter 内部 `ios/`、`android/`、`lib/` 等由工具链要求保留。

后端接口见[唯一接口契约](../后端/接口契约/api.json)，运行与部署说明分别见[后端](../后端/README.md)和[部署](../../部署/README.md)。

## 一、<span id="unit-code-maps">各实施单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [PC端 · Python](PC端/Python/代码地图/README.md)
- [移动端 · Flutter / Dart](移动端/Flutter/代码地图/README.md)
- [移动端 · 鸿蒙 ArkTS / ArkWeb](移动端/鸿蒙/代码地图/README.md)
- [后台管理端 · Flutter / Dart](后台管理端/Flutter/代码地图/README.md)
- [微信小程序 · JavaScript / WXML / WXSS](微信小程序/代码地图/README.md)


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
