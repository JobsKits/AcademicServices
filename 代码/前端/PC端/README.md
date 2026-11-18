# 知序｜PC端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

买方桌面使用 MacOS／Windows 各自原生工程，Web 使用标准网页并支持手机竖屏。三个入口共用同一 Go 商城接口和十语言资源，完整源码、构建入口与成品分别交付。

## 一、<span id="entry">职责与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 入口 | 技术与运行 | 当前验证 |
| --- | --- | --- |
| [MacOS](./MacOS/README.md) | SwiftUI 原生窗口；`Dist/知序.app`；`构建.command` | ARM64 编译／签名校验，实际业务范围见资产表 |
| [Windows](./Windows/README.md) | C# Windows Forms 原生控件；`Dist/win-x64/Zhixu.exe`；`构建.ps1` | 自含 EXE 交叉发布，Windows 实机待验 |
| [Web](./Web/README.md) | HTML／CSS／JavaScript；服务端 `/client/` | 320／390／430／768／1440宽布局与离线下单付款已验 |

三端均包括商品与详情、账户登录／邮箱注册／找回、需求与联系方式、订单、双渠道模拟收银台、站方交付后的确认评价、资料、十语言和白天／黑夜／跟随系统。原 [Python 工程](./Python/README.md)保留为迁移参考，不再作为默认客户端；原素材按出处与许可复用，原Qt成品不代表原生实现。

具体源码入口、偏好、生命周期、接口回退、功能差异与验证边界见[资产盘点](../../../项目相关报告/桌面与Web资产盘点.md)。运营端仍使用已有独立后台；真实支付、Windows 原机、签名公证与商店发布单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
