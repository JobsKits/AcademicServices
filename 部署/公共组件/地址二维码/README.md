# 部署地址二维码

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

由部署入口调用的独立 [**Go**](https://go.dev/) 工具，使用本地已准备的 Go 构建，不依赖 Python、Node.js 或在线二维码网站，不修改业务后端模块。

## 一、<span id="usage">输出与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
go build -mod=readonly -trimpath -o ./deployqr .
./deployqr --output-dir ./本轮二维码 --title '部署入口' \
  --entry '用户端|https://example.com/client/' \
  --entry '管理端|https://example.com/admin/'
```

- 完整 URL 原样编码；用户端、管理端分别标识。输出目录必须为本次运行独占且非符号链接的目录。
- 每个入口生成保留四模块白色静区的黑白 SVG 和 PNG；`index.html` 内嵌 SVG，无外部资源，浏览器直接打开即可扫码、选择复制文本或点击访问。
- 终端支持颜色且宽度足够时，调用方传入 `--terminal-width 列数 --ansi`，使用固定黑前景、白背景与半高方块；窄终端、非 TTY、`TERM=dumb` 或 `NO_COLOR` 使用原 URL 和本地页面。工具自身也尊重已设置的 `NO_COLOR`（包括空值）；直接调用默认不输出 ANSI。
- `--expire --output-dir ./本轮二维码` 将页面标记为失效，不再显示可扫码入口。已另存的图片无法撤销；图片只记录地址，服务和临时隧道结束后不再代表可用入口，重新部署必须使用新码。
- 使用最终对外地址。`0.0.0.0`、`[::]` 是监听地址，拒绝生成；回环地址只能当前电脑访问。服务器模式有明确的外部入口时用 `PUBLIC_BASE_URL`（只允许无账户、查询参数或片段的 HTTP/HTTPS 基地址），没有时只显示“仅本机”的回环地址。
- 不在入口中放账号、密码、令牌或签名。本工具拒绝 URL userinfo 以及常见认证查询参数；普通查询参数、URL 转义与片段保持原文。该检查不替代调用方确认地址不含秘密。
- 二维码构建或生成失败仅告警；部署仍保留可复制 URL。辅助二进制和本轮二维码均放后端 `.runtime/`，由原部署与反部署清单统一管理。

独立工具单元回归位于 `测试/部署/地址二维码/main_test.go`，从根目录运行 `python3 ./测试/运行测试.py/运行测试.py --group qr --go 实际Go路径`；使用项目外的测试缓存，不向部署源码写测试文件。

## 二、<span id="dependency">来源与固定版本</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

二维码编码依赖 [**go-qrcode**](https://github.com/skip2/go-qrcode)，固定版本 `v0.0.0-20200617195104-da1b6568686e`，完整校验值在 `go.sum`，MIT 许可原文保留在 `LICENSE-go-qrcode.txt`。未复制或修改第三方源码；依赖准备沿用部署当前进程的 Go 镜像、官方回退及缓存配置，模块下载后依照 Go 校验机制核对内容。地址仅在本机内存参与编码，HTML/SVG/PNG 生成过程不联网。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
