# <span id="前言">部署二维码工具测试</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

`main_test.go` 属于 `部署/公共组件/地址二维码` 的同包测试，通过统一入口的临时 Go overlay 注入，部署目录不放测试副本。

从项目根目录运行：

```shell
python3 ./测试/运行测试.py/运行测试.py --group qr --go 实际Go路径
```

使用已有 SDK、已准备的模块和项目外测试缓存；测试不下载工具、不启动后端、不连接公网。覆盖 URL 转义与普通查询原样保留、凭据与通配地址拒绝、空值 `NO_COLOR`、窄终端回退、离线 HTML/SVG/PNG、页面失效及符号链接保护。二维码实际识别须用独立解码器比对完整 URL，单元通过不等于手机公网访问验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
