# 知序 · 原生桌面数据仓库验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

两个测试直接编译实际原生端仓库，连接独立临时Go服务验证接口、业务状态与断网隔离，不操作已有用户数据。UI和目标系统运行分别验收。

## 一、<span id="scope">夹具与执行范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

准备一个独立临时数据目录和未占用回环端口，以 `APP_ENV=test`、`DEMO_MODE=1`、`DATABASE_URL`为空启动实际Go后端。仅使用合成演示账号。测试第一个参数是此服务的 `/api/v1` 根地址；不要传正式服务地址。

自动执行入口会自行构建临时后端、分配空闲回环端口、使用临时数据并在结束时只回收本次子进程；需要Node、Go、.NET 11，Mac另需Swift。`GO_BIN`可指定本机已准备的Go。直接在本目录运行：

```shell
node ./运行验证.mjs
```

`StoreSmoke.swift`与MacOS的 `Models.swift`／`ShopStore.swift` 一起由 `swiftc -parse-as-library` 编译，运行前将 `Web/Assets/` JSON复制到测试可执行文件的资源目录。覆盖真实商品→登录→下单→mock支付→站方交付→买方确认→评价→资料PUT，以及401拒绝、断网隔离订单。当前资料回归使用真实Store保存邮箱／手机／心情原文和显式清空、局部更新与UID注入拒绝；Swift另验证两帧GIF原字节、重登读回及离线双用户资料隔离。

`StoreSmoke.cs`与Windows的 `ShopStore.cs` 一起使用 `net11.0` 控制台工程编译，复制同样的Assets到输出位置，覆盖真实商品、登录、下单、mock支付、资料PUT、401和断网隔离。该测试可在Mac执行，不能替代Windows Forms实机测试。

在MacOS使用本机Swift编译器独立运行并发专项，不需要Go服务或.NET：

```shell
node ./并发验证.mjs
```

`StoreConcurrency.swift`使用可控网络回包，专项入口仅在系统临时目录的Store副本中替换传输符号，业务源码保持原样。当前11项场景通过：逆序刷新、刷新跨写、重复写门禁、未知写原键重试、错误订单／未推进版本／错误归属响应拒绝、退出后的迟到写入隔离，以及旧登录成功／旧登录401不覆盖新身份、取消登录后的迟到身份隔离。夹具与构建产物保留在终端显示的临时目录，不改项目成品、不连接真实服务。

网页另有[14项并发与响应验证](../Web/README.md)。当前应用验证结果与产物入口见[资产盘点](../../../../项目相关报告/桌面与Web资产盘点.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
