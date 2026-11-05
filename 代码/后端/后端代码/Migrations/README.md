# 数据存储定义

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

当前商城使用[数据库设计](../../../../需求/数据库设计/数据库设计.md)描述的商品、交易订单、模拟支付、交付与评价模型。

## 一、<span id="runtime">商城运行表</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[001_runtime.sql](./001_runtime.sql) 是可选 [**PostgreSQL**](https://www.postgresql.org/) 存储实际使用的表。Go服务在配置DATABASE_URL时创建并初始化单行聚合，事务内锁行并一起更新商品、订单、支付、评价、幂等收据和审计。默认文件模式不需要数据库，使用相同数据结构。

## 二、<span id="initialization">初始化与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

干净目录或专用空库初始化当前schema 2、三分类、九个演示商品和空订单。演示商品及价格必须由后台校对后用于实际经营；mock支付不会产生真实扣款。结构不支持或损坏时拒绝覆盖，不自动清库。回归只用临时目录或显式TEST_DATABASE_URL专用库，不操作正在运行的数据。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
