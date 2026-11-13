# 鸿蒙准备工具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

`prepare_harmony.py` 复用已安装Flutter，构建共享用户Web并将鸿蒙宿主绑定到指定HTTPS源。不会安装SDK、修改系统代理、签名或发布。

## 一、<span id="usage">入口与行为</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```shell
python3 ./prepare_harmony.py --api https://service.example/api/v1 --check
```

`--check`仅核对输入和Flutter路径，不构建或写文件。移除`--check`后打印自述，交互回车开始，任意非空输入或EOF取消；构建失败不生成宿主端点配置。生成Web位于本Flutter工程`../Dist/Client/`，端点配置位于[鸿蒙工程](../../鸿蒙/README.md)的`entry/src/main/ets/Config/Endpoint.ets`，拒绝符号链接目标。API必须使用无凭据、无query或fragment的`https://域名/api/v1`，默认443端口规范化，其它有效端口保留。

构建完成后按终端说明部署用户Web，使用DevEco独立配置签名并构建HAP；首启需要访问同源HTTPS服务。工具只生成Endpoint，ArkWeb外链逻辑唯一维护在鸿蒙Index：同源留宿主，用户触发HTTP(S)交系统浏览器处理，非法scheme及无手势外跳受阻。具体策略、API来源与未验收边界见[鸿蒙说明](../../鸿蒙/README.md)。

## 二、<span id="validation">验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

统一测试入口的harmony分组运行端点和宿主策略合同检查，不执行Flutter完整构建、DevEco、签名、HAP或真机。检查通过不等于设备浏览器已唤起。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
