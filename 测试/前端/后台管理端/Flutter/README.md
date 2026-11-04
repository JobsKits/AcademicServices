# 学术服务平台｜Flutter 后台测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

对应独立后台产品的现有行为测试，复用移动 Flutter 包的依赖上下文。

## 一、<span id="entry">职责与执行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

入口 `admin_widget_test.dart` 保存既有后台动作规则及宽窄窗口报价表单用例，从原混合 Widget 文件拆分，测试主体与覆盖数量保留。

在项目根运行：

```shell
python3 './测试/运行测试.py/运行测试.py' --group flutter
```

该组同时执行移动端的共享仓库／用户 Widget 和本目录后台用例，使用现有移动 Flutter 工程解析 `package:zhixu`。不会运行 pub get、复制业务包或生成安装包；缺少锁定依赖时明确记录阻塞。跨两个前端产品的本组日志集中在 `测试/前端/报告与证据/本轮/`，不冒充真机、浏览器端到端或正式权限验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
