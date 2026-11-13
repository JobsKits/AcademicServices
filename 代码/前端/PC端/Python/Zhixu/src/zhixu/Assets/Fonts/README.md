# 桌面离线字体

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

复用项目已核验的Noto CJK与藏文字体，二进制及OFL许可未修改，随桌面包分发并在进程内注册。窗口采用完整字体族回退，避免十语言界面依赖目标机器是否预装相应字体；不修改系统字体配置，也不在运行时下载。

## 一、<span id="sources">来源与完整性</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

官方固定提交、字体族、版权与许可出处见[项目字体来源说明](../../../../../../../移动端/Flutter/Assets/Fonts/README.md)。本地副本逐字节一致，保留原始名称与完整许可。

| 文件 | SHA-256 |
| --- | --- |
| [NotoSansCJKsc-Regular.otf](./NotoSansCJKsc-Regular.otf) | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` |
| [NotoSerifTibetan.ttf](./NotoSerifTibetan.ttf) | `060ec022b04c306de3f58d051fb0e1cf81a5b610c5910fbfc43bba154c057cda` |
| [OFL-CJK.txt](./OFL-CJK.txt) | `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2` |
| [OFL.txt](./OFL.txt) | `0077789fc3cb20f358278ba4c6437eb14ade97d4d3e3281eaa42853efcd9dc8b` |

## 二、<span id="validation">注册与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`shop.py`在创建窗口时一次注册，包资源由`pyproject.toml`声明。Qt离屏回归实际查询已注册字体的藏文、中文与韩文字形，十语言资源完整性另验；Windows／其它设备整句排版与安装包仍需目标平台验证。

<a id="🔚" href="#前言">返回前言</a>
