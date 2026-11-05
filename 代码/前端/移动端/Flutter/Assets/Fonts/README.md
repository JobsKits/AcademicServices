# 商城离线字体资源

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

使用 [**Google Fonts**](https://fonts.google.com/noto/specimen/Noto+Serif+Tibetan) 官方仓库提供的 Noto Serif Tibetan 可变字体，以及 [**Noto CJK**](https://github.com/notofonts/noto-cjk) 官方仓库提供的 Noto Sans CJK SC Regular，为藏文及中日韩界面提供随包离线字形。字体二进制均未修改；藏文字体仅将本地文件名简化为 `NotoSerifTibetan.ttf`，族名仍为 Noto Serif Tibetan。来源及许可于2026年11月5日核验。

## 一、<span id="sources">固定来源与文件</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 原始来源及用途 |
| --- | --- |
| [NotoSerifTibetan.ttf](./NotoSerifTibetan.ttf) | [官方固定提交的字体](https://github.com/google/fonts/blob/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/notoseriftibetan/NotoSerifTibetan%5Bwght%5D.ttf)，原名NotoSerifTibetan[wght].ttf，2,063,504字节，字重100～900 |
| [METADATA.pb](./METADATA.pb) | [官方固定元数据](https://github.com/google/fonts/blob/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/notoseriftibetan/METADATA.pb)，声明Tibt及bo_Tibt覆盖与字体上游 |
| [OFL.txt](./OFL.txt) | [官方完整许可](https://github.com/google/fonts/blob/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/notoseriftibetan/OFL.txt)，SIL Open Font License 1.1 |
| [NotoSansCJKsc-Regular.otf](./NotoSansCJKsc-Regular.otf) | [官方固定提交的字体](https://github.com/notofonts/noto-cjk/blob/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf)，16,437,364字节，Version 2.004、Regular字重 |
| [OFL-CJK.txt](./OFL-CJK.txt) | [同一官方固定提交的Sans许可](https://github.com/notofonts/noto-cjk/blob/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/LICENSE)，SIL Open Font License 1.1 |

下载使用固定提交的官方raw地址；字体主体因网络超时使用同一提交的 [jsDelivr镜像](https://cdn.jsdelivr.net/gh/google/fonts@8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/notoseriftibetan/NotoSerifTibetan%5Bwght%5D.ttf)，尾段从官方raw按Range补齐。组装后必须与官方Git blob `584b7092ef881d892c6f31c7b33e428dc8d9bb5b` 完全匹配，已经通过；不以部分下载文件或镜像返回成功代替完整性校验。

CJK字体使用上述官方固定提交及其同内容的固定提交 `165c01b46ea533872e002e0785ff17e44f6d97d8` 的官方raw地址分段获取。16个分段逐一核验Content-Range与字节数，组装后与官方Git blob `dc15562470b4f842321894787a0d066879ccff8b` 完全一致。

## 二、<span id="checksums">SHA-256校验</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | SHA-256 |
| --- | --- |
| NotoSerifTibetan.ttf | 060ec022b04c306de3f58d051fb0e1cf81a5b610c5910fbfc43bba154c057cda |
| OFL.txt | 0077789fc3cb20f358278ba4c6437eb14ade97d4d3e3281eaa42853efcd9dc8b |
| METADATA.pb | 9d15fc898a9bb94aee38705f31d54579014e7ff3bcc35c79b0c6a67f6f6b8827 |
| NotoSansCJKsc-Regular.otf | 2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b |
| OFL-CJK.txt | 6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2 |

## 三、<span id="license">使用与验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 版权所有：2022 The Noto Project Authors。按随附OFL许可随应用嵌入与分发，保留版权及完整许可，不将字体单独销售；具体条款以 `OFL.txt` 为准。
- CJK字体版权所有：© 2014-2021 Adobe，版权与名称保留在官方未修改字体的name表，完整许可见 `OFL-CJK.txt`；随应用分发时同时保留该许可，不将字体单独销售。
- 字体及许可由工程声明随包打入，不在运行时请求字体网络地址；本目录不含真实用户数据或外部运行环境。
- 字形覆盖检查逐一比对十语言87项界面文案及默认商品／服务端中文字符，全部零缺字；详见[字符覆盖结果](../../../../../../测试/前端/移动端/Flutter/证据/商城/font-coverage.json)。该检查验证cmap，实际断网加载与整句排版另以浏览器证据为准。
- 已验证字节长度、官方Git blob、SHA-256及SFNT／cmap结构，确认U+0F40、U+0F56、U+0F7C落在藏文字形映射范围。界面整句连写、不同目标平台字形与布局仍由对应界面验收确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
