# 商城真实接口回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

`test_http.py` 编译临时Go服务，在动态回环端口、临时数据目录验证真实HTTP行为；测试不访问已运行业务实例，不安装依赖。

## 一、<span id="run">执行入口与覆盖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从项目根使用统一入口：

```shell
python3 './测试/运行测试.py/运行测试.py' --group http --go '<已有Go可执行文件>'
```

- 需要已有Go SDK和模块缓存；可显式传入`--go`或设置GO_BIN。源码和所有路径根据脚本位置解析。
- 商城7项测试覆盖三类与详情、后台新增编辑／下架／缺货、价格版本与快照、双方权限、双渠道模拟支付、同键重试和并发、交付确认评价、重启持久化和写结果对账。
- 其中一项直接加载PC端的 `ShopRepository`，连接同一隔离Go服务，完成登录、购买、付款、站方交付、客户确认及评价；需要当前仓库中的Python客户端模块，不需要GUI依赖。
- 完整脚本还覆盖会话、需求／文件、资金及存储保护。日志由统一运行器保存到本职责的证据目录，具体数量和跳过项以执行输出为准。
- 付款固定mock、不实际扣款；临时服务停止和测试目录回收由脚本负责，超时及错误会明确失败。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
