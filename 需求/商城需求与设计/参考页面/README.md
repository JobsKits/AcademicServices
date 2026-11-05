# 参考商城页面映射

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

参考[氪研学术首页](https://www.keyan.asia/)和[产品服务页](https://www.keyan.asia/productService/)。本表记录实际公开读取所得的分类、子商品、价格性质及内容层级，供开发映射使用。核验日期：2026-11-05（Asia/Shanghai）；价格属于参考站当时的公开展示，不构成本平台的经营定价。

## 一、<span id="pages">三分类与九详情</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 分类 | 子商品与详情URL | 公开价格 | 内容主题概括 | 读取依据 |
| --- | --- | --- | --- | --- |
| 毕业论文 | [论文提纲](https://www.keyan.asia/goodsdetail/2) | ¥498.00 | 论文框架与参考文献梳理 | HTTP 200；公开详情API 200，4张有序详情图 |
| 毕业论文 | [开题指导报告课](https://www.keyan.asia/goodsdetail/4) | ¥0.01 | 开题方案的指导课程 | HTTP 200；公开详情API 200，4张有序详情图 |
| 毕业论文 | [毕业论文一对一](https://www.keyan.asia/goodsdetail/6) | ¥50.00 | 选题、写作、实验与答辩的一对一指导 | HTTP 200；公开详情API 200，4张有序详情图 |
| 普刊 | [审测投稿](https://www.keyan.asia/goodsdetail/9) | 咨询 | 稿件测评与期刊推荐 | HTTP 200；公开详情API 200，4张有序详情图 |
| 普刊 | [普刊论文一对一](https://www.keyan.asia/goodsdetail/10) | ¥200.00 | 按稿件需求提供一对一辅导 | HTTP 200；公开详情API 200，4张有序详情图 |
| 普刊 | [论文专业测评](https://www.keyan.asia/goodsdetail/11) | ¥600.00 | 稿件质量专业评估 | HTTP 200；公开详情API 200，4张有序详情图 |
| 普刊 | [普刊训练营](https://www.keyan.asia/goodsdetail/31) | ¥2199.00 | 围绕普刊写作的互动训练课程 | HTTP 200；公开详情API 200，4张有序详情图 |
| 编译 | [学术翻译](https://www.keyan.asia/goodsdetail/23) | 咨询 | 学术稿件语言翻译与校对 | HTTP 200；公开详情API 200，4张有序详情图 |
| 编译 | [学术润色](https://www.keyan.asia/goodsdetail/24) | 咨询 | 稿件语言表达和文章质量润色 | HTTP 200；公开详情API 200，4张有序详情图 |

- 分类来源：公开GET /api/applet/service/goods?type=1、type=2、type=5，与真实浏览器产品列表逐项核对；毕业论文3项、普刊4项、编译2项。
- 每个详情路由均单独GET核验HTTP 200，并读取同源公开GET /api/applet/service/detail/{id}。对应API含商品ID、类别、名称、是否明码套餐、最低展示价、特有概要和4张有序详情长图地址。咨询商品的数值0是无公开定价，不能显示成免费商品。
- 当前本平台九个开发商品沿这些名称映射；三项咨询商品使用明确标记的本地演示价，后台可改为正式经营价。没有把演示价格标成原站价格。

## 二、<span id="layers">页面层级与行为</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

真实Chrome访客页可看到：产品服务页含分类筛选、搜索、商品图片、名称、明码或咨询标记、详情入口。切毕业论文后收窄为三项。论文提纲详情的实际视觉与可访问树已核验：面包屑、主视觉、服务内容／流程图片、客户评价、常见问题、推荐商品、底部固定价格和立即购买。点击立即购买提示登录后再咨询／购买；未进行登录或任何实际交易。

九个详情均完成路由及公开详情数据核验；除论文提纲外，其余八页未逐张视觉检查36张长图的全部文字，也未声称完成这些正文的逐段一比一复刻。静态抓取工具对多数详情路由返回不可访问或缺少异步数据，不能据此写成商品不存在；公开API的读取结果与真实浏览器目录是本表的依据。

本平台采用相同业务信息层级并提供九个可达详情；商品详情以可编辑简介、正文及分节保存，购买后接本站订单与收银台。参考站的客户评价、资质、人员头像、营销统计与服务承诺不能当本站真实运营事实。

## 三、<span id="assets">内容与素材边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 现有[首页截图](../../参考截图/01-官网首页.jpg)与[服务总览截图](../../参考截图/02-服务总览.jpg)是内部需求讨论材料，未发现可用于产品宣传的参考站图片授权。
- 本次未把参考站长图、商标、人物、客户评价或长篇营销原文打包进产品；商品默认使用仓库自有品牌图。本表概括内容主题，实际交付条款由本站后台编辑。
- 完整照搬长篇正文及视觉素材的授权缺口见[需求M-Q01](../README.md#pages)。商户Key尚未到齐，外部真实支付宝／微信付款不作为已验收行为，见[支付边界](../README.md#payment)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
