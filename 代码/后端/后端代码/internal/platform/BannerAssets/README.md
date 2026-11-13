# 商城默认轮播资源

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

三张1440×560原创PNG来自项目[统一轮播资源](../../../../../前端/移动端/Flutter/Assets/Banners/)，使用项目自有品牌、暖色矢量构图和已登记OFL字体。此处副本随Go二进制嵌入，运行时不依赖源码目录或网络。

## 一、<span id="fallback">使用与校验</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `graduation.png`、`journal.png`、`editing.png` 分别对应毕业论文、普刊、编译，默认点击地址为空；后台配置目标URL后才跳转。
- 初始数据库保存`seed-graduation`、`seed-journal`、`seed-editing`三条轮播，version为1，后台可直接修改；启动时只对空轮播字典补齐并持久化，已有非空配置及全下架状态保留。
- 仅服务端轮播字典本身为空时，公开接口防御性返回三张图的data URL；已有非空配置全部下架时成功返回空数组，客户端应隐藏运营位。后台列表继续显示真实配置；客户端打包副本用于接口不可达时兜底。
- 资源来源、字体及许可见统一资源目录及其相邻字体说明；同步时逐字节核对两处PNG一致。实际页面布局、轮播操作和外链行为由对应前端验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
