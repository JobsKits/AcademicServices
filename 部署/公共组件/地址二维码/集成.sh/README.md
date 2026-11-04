# <span id="前言">部署二维码 Shell 集成</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

仅供部署入口 `source` 的跨平台函数库，不单独执行、不新增确认流程；由各系统既有部署自述和确认授权。复用当前 Go 与缓存构建二维码辅助程序，生成每次独占的 `.runtime/access-qr.*` 页面、SVG、PNG 和终端展示；无凭据编码或在线二维码服务。辅助工具构建、生成失败只告警并保留原 URL，不中止健康服务。

`qr_prepare` 在业务构建后、资源清单封存前调用；`qr_display` 在取得最终隧道地址后调用，地址变化重新生成；`qr_expire` 在回收本次进程时将页面标记失效。服务器模式使用明确配置的无凭据 `PUBLIC_BASE_URL`，缺少时只提示仅本机回环入口。产物须由调用方脚本内嵌的生命周期函数登记，反部署沿用原归属与并发保护规则。详细输出和固定依赖见[二维码工具说明](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
