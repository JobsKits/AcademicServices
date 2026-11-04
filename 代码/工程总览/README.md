# 工程总览与单元导航

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本页只导航独立工程地图及跨单元依赖；具体文件、模块和本单元关系在对应地图维护。

## 一、<span id="unit-maps">独立工程代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 实施单元 | 地图入口 |
| --- | --- |
| PC端 · Python | [原稿与阅读版](../前端/PC端/Python/代码地图/README.md) |
| 移动端 · Flutter / Dart | [原稿与阅读版](../前端/移动端/Flutter/代码地图/README.md) |
| 移动端 · 鸿蒙 ArkTS / ArkWeb | [原稿与阅读版](../前端/移动端/鸿蒙/代码地图/README.md) |
| 后台管理端 · Flutter / Dart | [原稿与阅读版](../前端/后台管理端/Flutter/代码地图/README.md) |
| 微信小程序 · JavaScript / WXML / WXSS | [原稿与阅读版](../前端/微信小程序/代码地图/README.md) |
| 后端 · Go | [原稿与阅读版](../后端/后端代码/代码地图/README.md) |
| MacOS 部署 | [原稿与阅读版](../../部署/MacOS/代码地图/README.md) |
| Windows 部署 | [原稿与阅读版](../../部署/Windows/代码地图/README.md) |
| Ubuntu 部署 | [原稿与阅读版](../../部署/Ubuntu/代码地图/README.md) |
| Debian 部署 | [原稿与阅读版](../../部署/Debian/代码地图/README.md) |
| RockyLinux 部署 | [原稿与阅读版](../../部署/RockyLinux/代码地图/README.md) |
| AlibabaCloudLinux 部署 | [原稿与阅读版](../../部署/AlibabaCloudLinux/代码地图/README.md) |
| Alpine 部署 | [原稿与阅读版](../../部署/Alpine/代码地图/README.md) |
| FreeBSD 部署 | [原稿与阅读版](../../部署/FreeBSD/代码地图/README.md) |

## 二、<span id="shared-navigation">跨单元依赖导航</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [移动 Flutter](../前端/移动端/Flutter/代码地图/代码地图.md)承载唯一共享 zhixu 包；[后台 Flutter](../前端/后台管理端/Flutter/代码地图/代码地图.md)用本地 path 依赖复用，[鸿蒙宿主](../前端/移动端/鸿蒙/代码地图/代码地图.md)通过 HTTPS 加载其用户 Web。
- [Python 桌面](../前端/PC端/Python/代码地图/代码地图.md)、[移动 Flutter](../前端/移动端/Flutter/代码地图/代码地图.md)、[后台 Flutter](../前端/后台管理端/Flutter/代码地图/代码地图.md)和[微信小程序](../前端/微信小程序/代码地图/代码地图.md)使用[唯一接口契约](../后端/接口契约/api.json)；[Go 实现](../后端/后端代码/代码地图/代码地图.md)负责 API、私有文件以及 /admin/、/client/ 构建产物托管。
- [分系统部署](../../部署/README.md)通过自身位置解析后端，分发保持根目录的代码与部署并列，后端留在代码/后端/后端代码；公共锁清单仍是唯一维护源。每个系统的实施文件在自己的地图定位。
- [全部测试](../../测试/README.md)按前端、后端与部署外置；共享执行入口负责寻址，不把测试复制进核心代码。

## 三、<span id="project-overview">其它工程说明</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [本导航离线阅读版](单元导航阅读版.html)
- [代码工程说明](../README.md)
- [工程说明离线阅读版](工程总览阅读版.html)

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
