# 小程序本地视觉资源

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

全部资源随小程序打包。远程轮播、商品图与头像先显示本地品牌图，失败保留品牌图；本地种子海报不依赖服务端。

## 一、<span id="sources">来源与许可</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 目录／文件 | 来源与用途 | 许可 |
| --- | --- | --- |
| `brand.png` | 仓库自有 `icon.png`，图像加载占位与头像兜底 | 项目自有 |
| `Banners/{graduation,journal,editing}.png` | 复用[移动端统一海报](../../移动端/Flutter/Assets/Banners/)，项目原创暖色海报，代码绘制并使用项目自有品牌与已许可Noto CJK字体 | 项目自有；字体来源随原工程登记 |
| `Icons/*.svg` | [Feather官方图标](https://github.com/feathericons/feather)，4.29.2官方npm包的jsDelivr镜像下载；首页、订单、个人中心、四状态、设置 | [MIT原许可](./Icons/LICENSE-Feather.txt) |

按用户素材顺序先查询iconfont（首页／订单／我的），公开搜索页本次不可访问，未取得可核验的对应许可素材；随后选择具有明确MIT许可的Feather官方图标。未采用不明图片或参考站的品牌、人物、评价素材。

SVG用于自定义Tab和状态入口，需在实际微信客户端核验渲染；PNG海报使用aspectFit，保持画面文字完整。轮播后台data URL转换为小程序私有图片文件再加载；缓存仅清理本模块自身创建的文件。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
