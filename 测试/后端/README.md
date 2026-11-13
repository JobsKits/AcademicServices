# 学术服务平台｜后端测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

对应 `代码/后端/后端代码/`，覆盖状态机、存储、鉴权、HTTP 网关和真实接口联调。

## 一、<span id="entry">职责与执行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 位置 | 作用与执行组 |
| --- | --- |
| `auth_account_test.go` | 邮箱注册、两种账号登录、资料、头像、验证码用途／过期／错误次数／重放、找回密码撤销会话、SMTP缺失与正式门禁、Demo admin/1234、账户重启持久化；同属go组 |
| `engine_test.go`、`http_test.go` | 状态、资金、幂等、存储与 HTTP 单元／并发测试，`--group go`；临时 overlay 保留同包访问 |
| `shop_test.go` | 商品后台与版本、下架／缺货、商品快照、双渠道mock、买卖双方交付评价、幂等／并发／写失败回滚、文件重启和商城真实回环HTTP；同属go组 |
| `banner_order_edit_test.go` | 显式Demo账号配置及正式凭据保护、默认轮播入库可编辑／空库补种与既有配置保留、图片／URL／权限／版本／重启／静态兜底、买方需求编辑与商户接单并发锁定；同属go组 |
| `file_store_lock_darwin_test.go` | MacOS 文件锁：真实子进程互斥、强制退出后遗锁恢复与数据保留、活旧进程及不明锁拒绝、guard文件保留；同属 `--group go`，其它系统不执行 |
| `接口/test_http.py` | 启动临时 Go 服务，验证真实回环 HTTP 业务及重启读回，`--group http` |
| `证据/` | 历史后端记录及新的后端命令日志 |

从项目根运行：

```shell
python3 './测试/运行测试.py/运行测试.py' \
  --group go \
  --group http
```

需要已有 Go SDK 与模块缓存。PG 用例须显式提供独立空测试库；未提供时记录跳过，不算数据库通过。HTTP 场景使用临时数据与动态回环端口，不访问正式业务实例。

执行时显式把 `GOCACHE` 和 `GOMODCACHE` 指向项目外的测试／用户管理缓存，避免写入部署封存的后端 `.tools/` 缓存；只读复用Go可执行文件不表示允许改其受管缓存。主测试入口继承这两个环境变量。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
