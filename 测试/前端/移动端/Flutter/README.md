# Flutter 商城测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

`shop_test.dart` 验证用户端与管理端复用的商城源码。使用内存 HTTP 替身和隔离偏好设置，不连接真实支付，不修改运行中的业务数据。

## 一、<span id="run">运行</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

在仓库根目录运行完整 Flutter 分组：

```shell
python3 './测试/运行测试.py/运行测试.py' --group flutter
```

只运行商城用例时，在 `../../../../代码/前端/移动端/Flutter/` 执行：

```shell
flutter test --no-pub ../../../../测试/前端/移动端/Flutter/shop_test.dart
dart analyze --format machine lib/Shop
```

需要已安装的 Flutter SDK 和锁定依赖，统一入口不自动安装。日志由统一入口写入前端测试证据目录；直接执行测试时输出到当前终端。

## 二、<span id="coverage">覆盖与边界</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

- 九个子服务、三分类子页、详情分节、320／390／934／1440窗口。
- 双渠道模拟收银台；关闭不付款，主动确认后付款。
- 离线买方下单／支付、站方开工／交付、买方确认／评价及历史快照。
- 商品编辑字段过滤、版本、库存权限、真实空列表、离线恢复、错误口令不回退成功。
- 未知真实写保留原键与正文重试，避免重复订单。
- 十语言词条完整性、主题偏好恢复、暖色主副文字对比。

Widget 与替身测试通过不代表 Web 构建、iOS／Android 安装、微信／支付宝外部 App 唤起或真机验收。各端实际构建及设备证据由总回归登记。

<a id="🔚" href="#前言">我是有底线的➤点我回到首页</a>
