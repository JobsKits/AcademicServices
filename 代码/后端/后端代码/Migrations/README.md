# 数据存储定义

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

运行表与需求阶段的关系模型分别保存，按实际用途使用。

## 一、<span id="runtime">MVP运行表</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[001_runtime.sql](./001_runtime.sql) 是可选 [**PostgreSQL**](https://www.postgresql.org/) 存储实际使用的表。Go服务在配置DATABASE_URL时自动创建并初始化单行聚合，事务内锁行、更新业务/幂等/审计/通知。默认文件模式不需要数据库。没有自动从文件导入PG的迁移命令。

## 二、<span id="reference">参考关系模型</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[需求数据库结构](../../../../需求/数据库设计/数据库结构.sql) 是外层需求目录唯一维护的 V0.3 原 29 表 DDL，仅供后续关系表映射开发。当前服务**不会执行、不使用这些29表**，不要用其建表成功代替业务PG验收；不要把它对正式库直接执行当升级。后续迁移必须验证旧数据、约束、索引、回滚和新旧业务读写一致性。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
