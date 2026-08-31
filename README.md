# TokenMeow 🐾

一个**AI 额度管家**：把各家的 API 账号添加进来，集中查看剩余额度、用量明细和用量趋势。

> **术语说明**：应用里添加的一条 = 一个提供商的 API 账号（一个 Key）。一个账号下面可以有多个模型，
> 详情页的“各模型用量占比”就是按模型统计的。所以名称可以随意起（默认预填提供商名），比如“DeepSeek 主号”。

- **设计规范**：Material 3（Expressive 风格的圆角卡片与 FAB），默认靛蓝主题（白背景 + 浅主题色卡片），另有靛蓝等 3种主题色可选
- **支持平台**：Android
- **技术栈**：Flutter（不依赖任何第三方插件，只有 `http` 一个纯 Dart 库，图表都是手绘的）

## 运行

```bash
flutter pub get
flutter run -d <设备id>  # Android（flutter devices 查看设备）
```

打包发布：

```bash
flutter build apk --release  # 生成 Android APK（build/app/outputs/flutter-apk/）
```

## 功能

| 位置 | 功能 |
| --- | --- |
| 标题栏左侧 | 软件名称 TokenMeow |
| 标题栏右侧 | 刷新全部按钮 + 竖向三点菜单（设置 / 关于） |
| 内容区 | 模型卡片：剩余量大数字 + 状态标签（正常/余额不足/已用尽/已过期）、剩余(绿)/已用(红)分段进度条（有总额/已用数据才显示）、明细字段、本月 Token 摘要、最后刷新时间；**点击卡片进详情页** |
| 详情页 | 余额总览（大数字+状态标签+横向明细）→ 用量概览（本月总 Token/消费双栏、缓存命中率、每日柱状图，可切换月份）→ 各模型用量占比条形图 → 用量趋势（柱状/折线切换，数据不足有友好提示）→ API 信息（默认折叠）→ 接口原始返回（开发者模式开启时显示）|
| 右下角 FAB | 添加账号（账号名称默认预填提供商名、提供商带品牌徽标、API Key、单位；接口地址由提供商自动推断；下拉仅列有数据查询能力的提供商） |
| 卡片右上角 ⋮ | 查看详情 / 刷新 / 编辑 / 删除 |
| 设置（独立页面） | 刷新（启动刷新、定时刷新、超时时间）、API 网络（HTTP 代理）、数据管理（导出/导入/清空）、外观（主题色、深色模式）、开发者模式（显示接口原始返回） |

明细字段示例：DeepSeek 显示赠送额度和充值余额；Kimi 显示现金余额和代金券；
SiliconFlow 显示充值/赠送余额；智谱 GLM 显示可用/已用/总余额（进度条就来自这三个字段）。

## 已内置的提供商预设（端点都实测验证过）

| 提供商 | 余额接口 | 关键字段 |
| --- | --- | --- |
| DeepSeek（深度求索） | `GET api.deepseek.com/user/balance` | `balance_infos.0.total_balance`（+赠送/充值明细，含每日用量） |
| 智谱 GLM（BigModel） | `GET open.bigmodel.cn/api/paas/v4/users/me/balance` | `data.available_balance / used_balance / total_balance` |
| Z.ai（智谱海外） | `GET api.z.ai/api/paas/v4/users/me/balance` | 同智谱国内站 |
| Moonshot AI（Kimi） | `GET api.moonshot.cn/v1/users/me/balance` | `data.available_balance`（+现金/代金券明细） |
| OpenRouter | `GET openrouter.ai/api/v1/credits` | `data.total_credits` − `data.total_usage` |
| SiliconFlow（硅基流动） | `GET api.siliconflow.cn/v1/user/info` | `data.totalBalance`（+充值/赠送明细） |
| OpenAI | 无余额接口 | 仅 Key 校验（`GET /v1/models`）+ 手动记录余额 |
| Anthropic（Claude） | 无余额接口 | 仅 Key 校验（`GET /v1/models`，`x-api-key` 头）+ 手动记录余额 |
| Google Gemini | 无余额接口 | 仅 Key 校验（`GET /v1beta/models`，`x-goog-api-key` 头）+ 手动记录余额 |
| Groq | 无余额接口 | 仅 Key 校验 + 手动记录余额 |
| xAI（Grok） | 无余额接口 | 仅 Key 校验 + 手动记录余额 |
| 自定义 | 自己填 | 自己填 JSON 路径（兼容 OpenAI 中转站可配自定义 Key 校验地址） |

余额查询统一使用 `Authorization: Bearer <API Key>`；仅校验型提供商按各自认证方式发请求。

## 用量查询（DeepSeek，网页 Token 方案）

DeepSeek 官方 API 只有余额接口，没有用量统计接口。TokenMeow 参考社区逆向的方案，
调用平台网页版的内部接口查询用量，详情页的“本月用量”卡片能看到：

- 当月总 Token、请求次数、缓存命中率（`命中 / (命中 + 未命中)`）、消费金额
- 按模型分解（每个模型多少 Token、命中率多少）
- 每日用量柱状图，可切换查看过去月份

**因为内部接口用的是网页登录凭据而不是 API Key，首次使用需要你粘贴一次 Token：**

1. 浏览器打开 platform.deepseek.com 并登录
2. 按 F12 打开控制台，执行 `JSON.parse(localStorage.userToken).value`
3. 复制结果，粘贴到 TokenMeow 详情页 → 本月用量 → “填入 Token”

Token 短期有效，失效后用量卡片会提示“网页 Token 已失效”，重复上面步骤更新即可。
请求时会自动带上模拟浏览器的 User-Agent 和 `x-app-version` 头。

> ⚠️ 内部接口没有官方 SLA，平台改版可能随时失效。自定义提供商也可以在编辑弹窗里
> 配置自己的用量/消费接口地址（`{month}`、`{year}` 占位符），返回结构需与 DeepSeek
> 平台一致。将来计划支持在应用内嵌 WebView 自动抓取 Token，免去手动粘贴。

## 界面细节

- **页面切换**：MD3 的 FadeForwards 平滑过渡（淡入 + 轻微前移），无缩放
- **主题背景**：白色页面背景 + 带浅浅主题色的圆角卡片（同 Shizuku 风格），卡片内元素（进度轨道、小卡片、代码块）用半透明色融入
- **提供商徽标**：下拉选项与卡片头像显示真实品牌 logo（`assets/providers/` 本地资源，加载失败自动回退品牌色字母徽标）

## 网络代理

应用默认**直连**，不走系统代理（Dart 网络栈不读系统代理设置）。访问 OpenAI、Z.ai、
OpenRouter 等海外接口时，在 **设置 → API 网络** 里选择“手动代理”，填代理地址
（如 Clash 默认 `127.0.0.1:7897`）；代理工具会设置 `HTTP_PROXY` 环境变量的话，
选“跟随环境变量”即可。

> **OpenAI / Claude / Gemini / Groq / xAI 为什么不能自动查余额？**
> 它们不提供普通 API Key 可用的余额查询接口。对这些提供商，应用采用“降级不缺席”策略：
> ① 刷新时自动调用模型列表接口校验 Key（标签显示 Key 有效/失效，并统计可用模型数）；
> ② 余额可在详情页手动记录——每次记录都是一条快照，趋势图和状态标签照常工作；
> ③ 用 OpenAI 兼容中转站的话，可在编辑账号里填自定义 Key 校验地址。
> MiniMax（无公开余额接口）与阿里云百炼（需 AK/SK 签名）暂不支持。

**自定义提供商**怎么填：填上完整的余额接口地址，再用“JSON 路径”告诉应用取哪个字段。
路径用英文点分隔、数组用下标（`balance_infos.0.total_balance`），支持多个候选用英文逗号分隔。
每行一条的明细字段（`显示名=JSON路径`）可以把赠送额度、token 用量等附加数据都展示出来。

## 数据保存在哪

所有数据（模型列表、设置、查询历史）保存在一个 JSON 文件里，明文可查：

- Android：应用私有目录下的 `tokenmeow_data.json`

> ⚠️ API Key 是明文保存的，请像保管密码一样保管这个文件。
> 每次成功刷新都会记录一个历史数据点（上限 300 条），详情页的趋势图就来自这里。

## 代码结构

```
lib/
├── main.dart                  # 入口：加载/保存数据，根据设置生成主题
├── models.dart                # 数据模型：ModelAccount、历史记录、提供商预设、设置
├── storage.dart               # 本地存储：读写 JSON 文件（零插件方案）
├── api_service.dart           # 网络请求：余额接口、JSON 路径解析、HTTP 代理
├── usage_service.dart         # 用量查询：平台内部接口、按模型/按天解析、Token 失效识别
├── utils.dart                 # 工具：路径取值、数字/时间格式化、明细解析
├── home_page.dart             # 主页面：标题栏、菜单、响应式卡片网格、FAB、定时刷新
├── pages/
│   ├── settings_page.dart     # 独立设置页（刷新/代理/数据管理/外观）
│   └── model_detail_page.dart # 详情页（明细、本月用量、趋势图、API 信息、原始返回）
└── widgets/
    ├── model_card.dart        # 模型卡片：数字 + 分段进度条 + 明细
    ├── split_progress_bar.dart# 剩余(绿)/已用(红) 分段进度条
    ├── trend_chart.dart       # 趋势图（CustomPainter 手绘柱状图/折线图）
    ├── usage_bar_chart.dart   # 每日用量柱状图
    ├── add_model_dialog.dart  # 添加/编辑模型弹窗
    └── about_dialog.dart      # 关于弹窗
```