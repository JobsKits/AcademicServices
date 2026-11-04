# 知序｜后端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

后端分为唯一接口契约和可独立构建的 Go 后端代码；部署脚本独立放在仓库根目录的 `部署/`。

## 一、<span id="entry">职责与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 子目录 | 内容与入口 |
| --- | --- |
| [接口契约](./接口契约/api.json) | 多端共用的 JSON 接口说明，唯一维护，不保留重复副本 |
| [后端代码](./后端代码/README.md) | Go 服务、运行 DDL、配置、数据与已构建网页资源 |

运行源码时进入 `后端代码/`，从标准入口 `go run ./cmd/server` 启动。部署时同时携带本目录与[部署目录](../../部署/README.md)，保持根目录的 `代码/` 与 `部署/` 并列；工具、账户配置、日志及业务数据仍归后端代码运行根。测试在[外层统一入口](../../测试/README.md)，不把外置测试复制回包内。

## 一、<span id="unit-code-maps">各实施单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [后端 · Go](后端代码/代码地图/README.md)


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
