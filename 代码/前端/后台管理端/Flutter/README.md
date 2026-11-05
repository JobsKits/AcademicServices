# 知序｜Flutter 后台入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

独立后台 Flutter Web 工程，入口为 `lib/main.dart`。当前通过 `pubspec.yaml` 的本地 `path: ../../移动端/Flutter` 依赖现有 zhixu 包，复用 `ShopApp`、商城仓库、十语言和暖色三主题，使用 `adminMode: true`。后台可编辑商品名称、价格、图片、详情分节、上下架及缺货，查询订单并开始服务、提交交付。

## 一、<span id="entry">职责与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行构建；所需依赖须先按锁定的移动端包版本准备：

```shell
flutter pub get

flutter build web \
  --release \
  --no-web-resources-cdn \
  --base-href /admin/ \
  --output Dist/Admin
```

将完整 `Dist/Admin/` 内容部署到 `代码/后端/后端代码/admin-web/`。后台默认独立 Web 入口及本地图标随源码提供；生成的启动脚本、CanvasKit 和应用代码由 Flutter 构建产生，不能直接双击源码 `web/index.html` 当运行成品。

运行及构建使用锁定依赖。商品和订单真实空结果保留空态；离线时用隔离演示，不把模拟付款当作真实扣款。未确认写保留原幂等键，可查询原操作或原键重试。用户端入口和共享源码见[移动 Flutter](../../移动端/Flutter/README.md)，正式身份与细分员工权限边界按[主评审](../../../../需求/项目需求与开发评审/项目需求与开发评审.md)执行。

## 一、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
