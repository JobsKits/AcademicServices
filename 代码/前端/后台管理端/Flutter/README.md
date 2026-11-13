# 知序｜Flutter 后台入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

独立后台 Flutter Web 工程，入口为 `lib/main.dart`。当前通过 `pubspec.yaml` 的本地 `path: ../../移动端/Flutter` 依赖现有 zhixu 包，复用 `ShopApp`、商城仓库、十语言和暖色三主题，使用 `adminMode: true`。后台可编辑商品名称、价格、图片、详情分节、上下架及缺货，查询订单、接单并锁定需求、提交交付；独立轮播入口支持图片上传或URL、可选跳转、顺序与上下架。正式环境必须管理员登录后才显示工作区，直达商品、订单或轮播深链也先鉴权；正式／未知环境API失联不会降级为管理员。明确Demo部署会自动使用 `admin / 1234` 建立会话直接进入；登录门仍保留登录、注册与忘记密码入口，普通客户注册不会获得管理员权限。演示凭据仅Demo公开。

## 一、<span id="entry">职责与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行构建；所需依赖须先按锁定的移动端包版本准备：

```shell
flutter pub get

flutter build web \
  --release \
  --no-web-resources-cdn \
  --base-href /admin/ \
  --output Dist/ShopAdmin
```

各系统部署入口优先直接托管本工程完整的 `Dist/ShopAdmin/`；缺少其 `index.html` 时才回退到后端 `admin-web/`。独立后端分发需将完整构建包发布到后端实际使用的管理端静态目录。后台默认独立 Web 入口及本地图标随源码提供；生成的启动脚本、CanvasKit 和应用代码由 Flutter 构建产生，不能直接双击源码 `web/index.html` 当运行成品。共享源码变更后需重新构建并发布完整产物；仅修改源码、运行 `flutter run` 或在其它目录生成包，都不会更新当前 `/admin/`。发布后对照部署日志中的实际静态目录与网址返回资源，刷新当前页面验收。

宽屏Web采用品牌头部和商品／订单／轮播职责侧栏；窄屏保留图文导航。默认hash路由支持`/admin/#/orders?status=pending_completion`、`/admin/#/orders/{id}`、`/admin/#/products/{id}`、`/admin/#/banners`；刷新与登录保留来源，不把表单私密输入写进URL。各编辑表单在服务端确认前保持打开，失败显示持续可读反馈并保留输入；刷新失败保留已有真实记录。配置全部轮播下架后，用户商城隐藏该运营位。

运行及构建使用锁定依赖。商品和订单真实空结果保留空态；显式Demo离线预览可使用隔离演示，不把模拟付款当作真实扣款。未确认写保留原幂等键，可查询原操作或原键重试。用户端入口和共享源码见[移动 Flutter](../../移动端/Flutter/README.md)，正式身份与细分员工权限边界按[主评审](../../../../需求/项目需求与开发评审/项目需求与开发评审.md)执行。

## 一、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
