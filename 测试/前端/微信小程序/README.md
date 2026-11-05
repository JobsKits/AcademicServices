# 微信小程序商城测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

测试微信原生商城的请求、状态、页面与恢复逻辑。使用[**Node.js**](https://nodejs.org/)内置 test，不写运行服务数据，不调用真实支付。

## 一、<span id="entry">运行与覆盖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
node --test ./测试/前端/微信小程序/test_shop.cjs ./测试/前端/微信小程序/test_mini.cjs
```

在仓库根执行。商城24项覆盖九商品／分类、真实空态与恢复、金额快照、下架缺货、双渠道模拟付款、关闭不付款、权限与确认／评价、四状态筛选、写锁、未知写原键对账／重试、错owner及迟到响应、十语言三主题、图片兜底及恢复。HTTP与幂等20项补充会话及超时保护，总计44项通过。

## 二、<span id="device">开发者工具与真机验收</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 开发者工具导入[小程序工程](../../../代码/前端/微信小程序/README.md)，使用实际 AppID 和合法域名；检查六页面编译、三分类及九详情可达、空态重载、字体和长语言布局。当前未执行工具编译。
- iOS微信与Android微信分别真机预览；服务可达时从详情创建订单、关闭／重新打开收银台、支付宝／微信分别确认mock、由管理端交付、买方确认并评价。检查订单四状态筛选、下架／缺货阻止新购及历史快照。
- 真机分别切十语言、三主题与系统主题；断开后端查看本地品牌和演示，恢复后刷新采用服务端；未知真实写只核对／同键重试。真机不能使用电脑loopback地址。
- 工具／真机／体验版／提审／正式发布分别登记，当前均未验收；Node断言不能替代这些证据。mock不证明外部App支付SDK、签名或渠道回调已验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
