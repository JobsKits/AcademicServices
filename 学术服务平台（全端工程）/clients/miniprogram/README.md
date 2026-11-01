# 微信小程序入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

原需求的小程序入口保留。使用 [**微信小程序**](https://developers.weixin.qq.com/miniprogram/dev/framework/) 原生WXML/WXSS/JavaScript，零第三方运行依赖。和其它客户端共用Go API，覆盖三服务浏览、登录、提交、需求详情、报价确认、文件、消息、交付反馈/验收、取消结算确认与售后。

## <span id="section-1">一、打开和连接</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

微信开发者工具导入本目录。`project.config.json` 使用 `touristappid` 便于开发预览，基础库 `latest` 由开发者工具解析；本机尚未运行开发者工具验证具体基础库版本。正式发布填写自己的AppID，使用最新稳定开发者工具，并在管理后台配置API的HTTPS合法域名。

“账户与连接”中填写完整API地址。本机工具可连接 `http://127.0.0.1:8080/api/v1`；真机必须使用可访问的HTTPS服务器域名，不能用电脑的loopback地址。开发账户按钮会尝试真实customer演示账户，密码被正式配置替换后须手动输入自己的密码。

## <span id="section-2">二、业务和恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

游客可读三服务，提交前登录。毕业论文要求专业/学历，普刊要求专业，编译要求语种，所有需求要求标题、说明与处理授权。附件从聊天文件选择，每次上传新文件，服务端限制8MB。通过授权下载接口预览文件，当前格式无法打开时提示改用桌面下载。

读失败回退隔离演示，真实空列表不填假数据。401撤销会话并清私有缓存；403/409/422显示真实拒绝。未知真实写入保留原键与正文、阻止重复写，列表提供核对入口；404尚未找到收据不视为在途请求已经失败。本地待核对资料按API地址与账户分开保存，不保存密码/会话Token；设备使用者仍应保护应用存储。

离线演示仅支持新建、留言、补说明与撤回，复杂资金及正式文件动作须连接后端。样例不自动上传。全量管理动作由Flutter管理后台提供，小程序不作为管理员入口。

## <span id="section-3">三、验证与限制</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

仓库逻辑可在工程根运行：

```shell
node --test tests/test_mini.cjs
```

包含空结果、网络恢复、鉴权清缓存、真实未知写入核对、换号迟到响应等保护。WXML/JS的自动检查不等于微信开发者工具编译或真机验收；当前未做微信登录、手机号授权、在线支付、订阅消息或平台提审。所选基础库及iOS/Android微信真机需要继续验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
