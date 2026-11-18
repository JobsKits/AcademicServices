# 本地预埋头像

本目录的八张 `thumbs-01.png`—`thumbs-08.png` 使用 [DiceBear Thumbs](https://www.dicebear.com/styles/thumbs/) 官方头像样式；作者 DiceBear，图片许可 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。2026-11-18 下载自官方 API，版本路径 `9.x`，参数 `size=192`、`seed=Zhixu01` 至 `Zhixu08`。应用运行时只读取随包文件，不请求 DiceBear。

按素材优先顺序先检查了 [iconfont 头像搜索](https://www.iconfont.cn/search/index?searchType=icon&q=%E5%A4%B4%E5%83%8F)，未取得可核验许可的合适资源，改用上述有明确 CC0 声明的官方来源。图片为圆润表情头像，已核对主体；未改动上游程序源码。

MacOS 与 Windows 从包内 `Avatars/` 枚举图像，选择后向现有资料接口上传图像原始 data URI。随包 `ResourceManifest.sha256` 记录每张资源内容摘要。源码、资源和当前验收见项目根 `项目相关报告/桌面与Web资产盘点.md`。
