# 学术服务后端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

以 [**Go**](https://go.dev/) 实现的自营虚拟商品商城，为毕业论文、普刊、编译的课程／服务提供商品、交易订单、模拟支付、交付与评价 API。维护者 Jobs。当前适用于产品演示与功能联调；真实客户入驻、细分员工权限和真实支付仍需继续完成。零基础操作者先看上级工程使用说明，再运行同级代码层的 `../../../部署` 内对应系统入口。

## 一、<span id="capability">当前功能</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 模块 | 当前行为 |
| --- | --- |
| 商城商品 | 毕业论文／普刊／编译三分类、九个演示商品；课程／服务、详情分节、人民币价格、图片、上下架与手动缺货；管理员新增编辑 |
| 商城订单 | 商品与价格快照下单、待付款／待完成／待评价／已完成、未付款取消；数量固定1，无物流 |
| 买卖双方 | 站方开始服务、提交交付说明；买方确认完成、评分评价；按角色和订单归属校验 |
| 支付 | 支付宝／微信应用内模拟收银台，mock成功不扣款；价格取订单快照，同键重试与并发不重复收款 |
| 一致性 | 商品及订单版本冲突409，业务／支付／评价／审计／幂等收据同一存储事务；提供写结果对账 |
| 安全 | 密码PBKDF2、随机会话、8小时失效、登录每IP每分钟10次、正文限制、明确跨域来源、客户订单隔离 |
| 页面托管 | /admin/ 与 /client/ 托管部署时带入的Flutter Web产物，扩展名为空的路由回退入口 |

当前固定 `admin` 与 `customer` 两个生产身份。开发模式额外提供 `customer2` 便于验证账号隔离；真实微信登录、注册、员工细分权限、短信和推送尚未接通。商品及运行演示价格标为 `is_demo=true`，实际经营内容由后台编辑。

商城付款使用 `PAYMENT_MODE=mock`，模拟记录带 `mode=mock` 与 `MOCK-` 参考号，不表示实际到账。设为 `real` 时未配置的真实驱动返回503、订单继续待付款，不静默降级为mock。已付款取消与退款规则尚未作为商城动作开放；本期仅未付款订单可直接取消，不模拟退款到账。

## 二、<span id="run">启动与配置</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

**后端最低机器配置：** 正常部署脚本包含源码编译，准备 64 位 2 核 / vCPU、4 GiB 可用内存、20 GiB 空闲 SSD；MacOS / Windows 图形机器整机至少 8 GiB 内存并满足可用余量。只运行匹配系统 / 架构的预编译程序、少量数据文件演示，可按 2 核 / 2 GiB 可用内存 / 10 GiB 空闲 SSD 预算；该预算不能用于正常脚本编译。以上为工程估算，未做下限硬件压测或生产容量验收。 系统版本、网络、数据库同机与扩容边界见[部署最低机器配置](../../../部署/README.md#minimum-machine)。

需要 Go 1.27.3。以下在本目录执行；双击部署入口会负责准备本地环境，开发命令不自动下载或配置数据库。

```shell
go mod download
go run ./cmd/server
```

开发默认地址 `http://127.0.0.1:8080`，管理员 `admin / demo-admin-change-me`，客户 `customer / demo-customer`。这两个值仅供本机开发；生产模式拒绝默认密码。查看健康状态访问 `/healthz`。文件及附件在 `DATA_DIR/state.json` 内，不能把开发数据拷到正式服务当客户记录。

| 环境变量 | 默认值 | 用途 |
| --- | --- | --- |
| `APP_ENV` | `development` | 仅接受development/test/production |
| `LISTEN_ADDR` | `127.0.0.1:8080` | API与页面共同监听；外部访问需配置合法地址与HTTPS反向代理 |
| `DATA_DIR` | `./data` | 文件模式持久化目录；相对启动工作目录 |
| `ADMIN_PASSWORD` | 开发样例值 | 生产必须明确设置，通常至少12字符；本地调试开关生效时至少4字符，均禁止默认值 |
| `DEMO_CUSTOMER_PASSWORD` | 开发样例值 | 固定customer身份密码；长度要求同管理员，禁止默认值且必须与管理员不同 |
| `LOCAL_DEBUG_PASSWORDS` | 未设置 | 精确设为 `1` 且生产监听数字IP回环地址时，密码最小长度为4字符；其它情况生产仍要求12字符 |
| `DATABASE_URL` | 空 | 空为单进程文件模式；填写连接串则使用PostgreSQL聚合事务存储 |
| `ADMIN_STATIC_DIR` | `./admin-web` | 管理后台构建产物目录 |
| `CLIENT_STATIC_DIR` | `./client-web` | 用户端Web构建产物目录 |
| `CORS_ORIGINS` | 空 | 空为同源；允许其它来源时逗号分隔精确origin，生产仅HTTPS |
| `PAYMENT_MODE` | `mock` | 模拟付款；`real`预留并拒绝尚未实现的真实付款，禁止失败后转为模拟 |

服务直接读取进程环境，**不自动执行/加载 `.env`**；[配置示例](.env.example) 是字段说明。部署入口使用自身配置并注入环境。反向代理须保留原始 Host。同源HTTPS以及本机loopback HTTP可用；生产公共域名需要HTTPS。CORS是浏览器来源约束，所有私有接口仍单独校验Bearer会话。

[**MacOS**](https://www.apple.com/macos/) 部署入口的“本地部署＋内网穿透”仅给当前进程设置 `LOCAL_DEBUG_PASSWORDS=1`，监听 `127.0.0.1` 时允许4字符密码；“服务器部署”清除此开关并要求12字符。后端也支持数字回环地址 `::1`；`localhost` 等主机名及非回环地址不放宽长度。长度按Unicode字符计数；开关不改变 `APP_ENV=production`、生产账号和CORS限制，也不写入部署配置。

退出时按 `Ctrl+C`，服务完成优雅关闭后删除本实例的 `.server-lock`；同一数据目录不能启动多个文件模式实例。MacOS 文件模式还会在整个运行期间持有 `DATA_DIR` 下 `.server-guard` 的系统文件锁；进程退出后系统释放锁，guard 文件保留，不要手工删除它。

MacOS 再次启动遇到 `.server-lock` 时，只有记录的 `pid`、`started` 格式有效、系统确认该 PID 已不存在，且文件身份与内容复核一致，才先保存同目录的 `.server-lock.stale-*.bak`（0600权限），再回收旧标记并启动。活进程、权限不足、损坏记录、符号链接或无法确认的锁会保留并报错；先核对错误与原实例，不要删锁强行启动。其它系统保留原有排他标记方式，意外退出遗锁须先确认旧进程已停止并备份数据目录，再由维护者处理。各系统均不要删除 `state.json` 或让两个实例共用它。

## 三、<span id="api">接口与动作</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

前缀 `/api/v1`。JSON字段以[唯一接口契约](../接口契约/api.json)及本目录 `internal/platform/shop.go`、`model.go` 为准。私有接口使用 `Authorization: Bearer <token>`。创建、编辑、动作、上传必须提供8至120字符的 `Idempotency-Key`；编辑／动作／上传同时携带看到的 `expected_version`。金额为人民币分整数，时间为RFC3339，日期为YYYY-MM-DD。

| 商城方法与路径 | 用途与返回 |
| --- | --- |
| `GET /products`、`GET /products/{id}` | 公开上架商品；列表支持category_id筛选，返回products／product |
| `GET /admin/products`、`POST /admin/products`、`PUT /admin/products/{id}` | 管理员查看全部、新增和完整编辑；更新含expected_version |
| `POST /shop-orders` | 客户提交product_id、product_version，服务端锁定价格及商品快照，返回order |
| `GET /shop-orders`、`GET /shop-orders/{id}` | 客户本人／管理员全部，返回orders／order |
| `POST /shop-orders/{id}/actions` | pay(channel)、start、deliver(text)、accept、review(rating,text)、cancel |
| `GET /shop-operations/{key}` | 当前身份商城写结果对账，返回最新product或order；404不证明仍在途的写失败 |

公开缺货商品可浏览，缺货或下架不可下单；同一事务校验商品版本，拒绝客户端报价。已生成待付款订单按快照付款，后续改价和下架不改写历史。所有商城业务变化、收据、支付和审计原子提交；同键同文优先重放收据，同键异文409。存储使用当前schema 2，结构不支持或损坏时拒绝覆盖；开发回归使用干净隔离目录，不自动修改现有运行数据。

| 身份与目录方法 | 用途 |
| --- | --- |
| POST /auth/login | account/password换取会话；登录是免幂等键入口 |
| POST /auth/logout | 撤销当前会话，可重复调用 |
| GET /services | 公开三项主分类 |

| 商城动作 | 身份及前置 |
| --- | --- |
| pay(channel) | 客户本人、待付款；channel=alipay／wechat |
| cancel | 客户本人、待付款 |
| start | 管理员、待完成且尚未开始 |
| deliver(text) | 管理员、待完成且未交付，说明不能为空 |
| accept | 客户本人、站方已交付，进入待评价 |
| review(rating,text) | 客户本人、待评价，评分1～5且正文非空；完成时间沿用确认时刻 |

响应丢失时保留原key及完整原正文，通过GET /shop-operations/{key}核对；404不证明仍在途的请求已失败。可由用户主动使用原key重试，服务端先查收据再验版本。同key异文409，不能以新key盲目重做购买／付款。

401重新登录，403身份无权限，409刷新并核对版本/当前状态，422检查输入。5xx/超时按未知提交处理，不能显示“操作成功”。错误结构为 `{"error":{"code":"...","message":"..."}}`。

## 四、<span id="storage">存储与备份</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认文件模式在锁内复制业务状态，成功后把业务、附件字节、幂等摘要、审计和outbox作为同一快照写入临时文件，fsync后原子替换，失败不发布内存状态。备份须先停止服务，再复制整个data目录与有效部署配置；恢复先保留当前数据的副本。目录/文件权限默认0700/0600；文件未加密，正式机器需自行配置磁盘与备份访问权限。

可选 [**PostgreSQL**](https://www.postgresql.org/) 模式使用[运行存储DDL](./Migrations/001_runtime.sql)的 `academic_runtime_state` 单行JSONB聚合。事务内先 `SELECT ... FOR UPDATE`，重新读状态后原子提交商品、订单、支付、评价、收据和审计；当前schema为2。首次使用空目录或专用空库时初始化三分类与九个演示商品，结构不支持或损坏时拒绝覆盖。

当前没有关系表投影、RLS、外部对象存储、后台清理或文件／数据库互导工具。切换 `DATABASE_URL` 会访问另一份数据源，不能直接改连接串当作数据转移。完整字段与事务边界见[数据库设计](../../../需求/数据库设计/数据库设计.md)。

业务聚合保存在一份状态，适合当前演示与联调规模；增长会放大内存、写入和备份成本，未做压力容量验收。商品上下架、缺货和历史快照保护具备公开API及管理界面；真实客户入驻、员工授权、正式支付及生产容量仍需单独验收。

## 五、<span id="verification">验证方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
python3 ../../../测试/运行测试.py/运行测试.py --group go --group http
```

默认测试使用隔离临时目录和内存，不会改部署数据；PostgreSQL集成用例缺少 `TEST_DATABASE_URL` 时明确跳过。真实原生PG验证应先建立**专用空数据库**，再把它的连接串作为 `TEST_DATABASE_URL` 运行测试。该用例会建立运行表并写入测试需求；数据库非空会拒绝，以免混用正式数据。

```shell
TEST_DATABASE_URL='postgres://tester@127.0.0.1:5432/academic_test?sslmode=disable' \
  python3 ../../../测试/运行测试.py/运行测试.py --group go
```

商城测试覆盖商品编辑、版本／价格冲突、上下架／缺货、订单快照、双方权限、双渠道模拟付款、同键与并发、履约评价、写失败回滚和重启持久化。真实服务HTTP测试还使用Python ShopRepository完成客户端到Go的整单闭环。文件锁测试覆盖真实子进程互斥、强制退出后恢复、活进程与不明锁拒绝、guard文件保留；其它已有业务保护也纳入统一回归。具体执行证据与未验收范围见[商城回归](../../../测试/商城回归/README.md)及[后端测试](../../../测试/后端/README.md)，跨平台编译不代替目标系统或设备验收。

## 六、<span id="architecture">源码与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

入口cmd/server/main.go；会话／来源校验／静态页面在internal/platform/http.go，商城资源路由在shop_http.go，商品／订单／付款／交付／评价及事务动作在shop.go，状态与两种存储在model.go及store.go。源码定位见[本单元代码地图](./代码地图/README.md)。

直接运行依赖为[**pgx**](https://github.com/jackc/pgx) v5.11.0（MIT），用于可选数据库存储；工具链及传递依赖由go.mod/go.sum锁定。当前未引入RPC、MQ、定时任务或已接通的外部支付／通知渠道。

~~~mermaid
flowchart LR
  Main[server/main.go] --> Http[http.go 会话与托管]
  Http --> ShopHttp[shop_http.go 商城API]
  ShopHttp --> Shop[shop.go 原子商城动作]
  Shop --> Store[store.go]
  Store --> File[文件快照]
  Store --> PG[数据库行事务]
~~~

~~~mermaid
flowchart LR
  Catalog[三分类商品与详情] --> Buy[下单并保存快照]
  Buy --> Pay[微信或支付宝模拟付款]
  Pay --> Delivery[站方开始与交付]
  Delivery --> Accept[买方确认完成]
  Accept --> Review[买方评价]
  Review --> Complete[已完成]
  Buy --> Cancel[未付款取消]
~~~

## 七、<span id="local-tunnel">本地部署＋内网穿透</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

**关闭此运行终端，服务将结束**。本地临时模式依赖当前运行窗口；确认公开前和地址生成后的日志会单独红色加粗提示，纯文本终端及日志保留原文。关闭终端或按 `Ctrl+C` 结束本次后端与隧道，数据和配置保留。

前期少量联调可复用现有电脑，不必先租云主机。选择一台常开主机，复制根目录的 `代码/` 与 `部署/` 并保留原相对层级；默认 `127.0.0.1:8080` 与文件模式即可运行学术服务，维修项目使用另一个 `127.0.0.1:8098`。隧道由同一主机发起连接，回环监听可以保留。

1、在本说明所在目录按主机类型运行一个入口，阅读确认后通过fzf选“本地部署＋内网穿透”或“服务器部署”；Esc、空选或选择器错误不启动业务。初次设置两组不同的非默认密码，数据库连接串留空：

| 系统 | 本地启动命令 |
| --- | --- |
| MacOS | `zsh '../../../部署/MacOS/【MacOS】部署.command/【MacOS】部署.command'` |
| Windows PowerShell | `..\..\..\部署\Windows\【Windows】部署.cmd\【Windows】部署.cmd` |
| Ubuntu示例 | `bash '../../../部署/Ubuntu/【Linux】部署.sh/【Linux】部署.sh'` |
| 其它Linux / FreeBSD | 选择部署目录中与本系统同名的入口，不套用其它系统的包管理器 |

2、本地模式按锁清单自动准备缺少的工程内fzf/Go/cloudflared（官方固定资产+SHA256，健康现有工具复用，不改全局PATH）；确认公网后先启动后端，健康成功再生成Cloudflare Quick免费随机HTTPS。无需账号/域名/付费；45秒无地址即回收本次进程并显示排查入口。保持窗口，另开终端访问 `http://127.0.0.1:8080/healthz`，并确认 `/client/`、`/admin/` 的真实API可用。网页显示本地演示只表示UI可体验，不能证明部署成功。

自动Quick通过本次工程内空YAML显式指定 --config，保留个人cloudflared配置，实际子进程隔离TUNNEL_*且不污染父环境；fzf探针和菜单局部隔离默认选项。

3、若大陆网络不可达或需要固定地址，先Ctrl+C停止自动本地模式，重新选择服务器部署，再按本平台原生包安装 [**cpolar**](https://www.cpolar.com/download)，或使用 [**Cloudflare Tunnel**](https://developers.cloudflare.com/tunnel/downloads/) 备选。Mac/Windows/常规Linux/Alpine/FreeBSD的包、架构、CLI和常驻方式分别见[各平台本地穿透步骤](../../../部署/README.md#local-tunnel-start)，不要直接复制其它系统的安装命令。

4、同机两个项目在一份私有配置里定义 `academic → 127.0.0.1:8080` 和 `repair → 127.0.0.1:8098`；使用一个cpolar进程显式运行这两个名字，避免基础版进程额度冲突，也不顺带启动SSH样例。Token存工程外，不粘贴到日志/截图/仓库。免费随机地址适合验通；[官方价格](https://www.cpolar.com/pricing)当前基础版99元/年含3个保留子域名、8条隧道，数量上覆盖同机两个项目；专业版149元/年支持自定义域名等，费用和带宽不作永久承诺。

5、每项目一个HTTPS主机名整站转发，保留公网 `Host`；本项目浏览器Origin必须匹配Host或明确允许来源。学术浏览器打开 `https://实际域名/client/`、`/admin/`，桌面/移动客户端使用 `https://实际域名/api/v1`，手机不能填电脑的127.0.0.1。不要把页面、API和附件拆到不同随机域名。

6、让手机关闭Wi-Fi走移动网络，检查公网健康、客户下单后刷新重读、双渠道模拟付款、管理端同编号履约、买方确认评价及未登录私有请求拒绝；低带宽隧道的超时与未知提交对账需要核对。正式小程序的域名/AppID等发布条件另验。

7、电脑睡眠、合盖、断电或宽带中断会影响访问。首次仅前台运行，不默认改变电源策略或注册服务。自动本地模式Ctrl+C同时回收本次后端和隧道；手动模式先停隧道再停后端。用外部新请求确认入口失效，再备份 `data` 和有效配置；缓存演示页面仍显示不能证明隧道在线。固定域名不用时在后台撤销对应路由。

详细私有YAML、平台命令、固定子域名与Cloudflare备选、日志/停止/排查见[各平台本地穿透步骤](../../../部署/README.md#local-tunnel)。这些是操作说明，当前未安装或建立公网隧道，也未完成双项目同机/公网读写/容量验收。

## 八、<span id="code-map">本单元代码地图</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

定位入口见[代码地图目录](代码地图/README.md)，包含本工程的主地图与离线阅读版；共享源只通过原归属引用。


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
