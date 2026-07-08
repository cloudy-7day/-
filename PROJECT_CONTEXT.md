# PROJECT_CONTEXT

## 1. 项目目标

本项目是一个个人信息收集与阅读训练网页，**线上最终交付地址为 `https://cloudy-7day.github.io/-/`**。
当前目标是每天自动整理 7 篇内容：

- 3 篇国际新闻
- 2 篇 AI 应用文章
- 2 篇应用型论文

核心目标不是收集最多内容，而是帮助使用者训练技术判断力：来源是否可靠、内容是否可读、是否有真实应用价值、失败风险在哪里、证据链是否可追溯。

### 当前需要解决的体验问题

1. **论文缺少阅读简介链接** — 目前的「阅读原文」直接指向 PDF 全文，用户缺少一个先看摘要/简介的入口。已在论文卡片上增加独立的「阅读简介」链接指向 arXiv 摘要页，和「阅读原文」（PDF）分开。
2. **卡片高度不统一** — 论文卡片因为包含 6 个详细字段（问题、方法、差异、创新点、实现、应用）加术语列表，长度远超新闻和 AI 卡片。已通过 CSS 限制论文详情区域高度（max-height: 200px + 滚动），让所有卡片在视觉上更整齐。

## 2. 关键原则

- **以 GitHub Pages 线上地址为最终交付目标**，本地预览只作为检查手段。
- 不绕过订阅墙、登录限制、验证码或反爬限制。
- DeepSeek 只基于可访问内容总结，不调用 GPT，不假装读过不可访问全文。
- 后续若有新的根目录项目文档需要归档，使用命令：
  `Move-Item -LiteralPath 'D:\111 codex\<文档名>.md' -Destination 'D:\111 codex\个人信息收集库\<文档名>.md'`

## 3. 技术栈

- 前端：静态 HTML、CSS、JavaScript。
- 数据存储：本地 JSON 文件，主数据为 `data/articles.json`，历史数据在 `data/archive/`。
- 自动更新：PowerShell 脚本 `scripts/update-daily.ps1`。
- 论文 PDF 文本提取：Python 脚本 `scripts/extract-pdf-text.py`，优先使用 `pypdf`。
- AI 分析：DeepSeek API，不调用 GPT。
- 自动化发布：GitHub Actions 定时运行更新脚本，GitHub Pages 提供网页访问。
- 本地预览：Python `http.server`，由 `scripts/start-web-server.ps1` 启动。

## 4. 文件结构

```text
D:\111 codex                    # GitHub Pages 主发布目录
├── index.html                  # 首页（含语言切换、历史归档、论文双链接）
├── app.js                      # 前端渲染逻辑（含中英文切换、论文简介链接）
├── styles.css                  # 页面样式（含语言切换、卡片高度统一）
├── README.md                   # 项目说明
├── CHANGELOG.md                # 修改记录
├── PROJECT_CONTEXT.md          # 本文件，项目上下文
├── data/
│   ├── articles.json           # 当前每日 7 篇内容（含英文翻译、abstractUrl）
│   └── archive/                # 历史归档（含 abstractUrl）
├── docs/
│   └── context/                # 合规与来源规则文档
├── scripts/
│   ├── update-daily.ps1        # 每日更新主脚本（含 abstractUrl 生成）
│   ├── article-selection.ps1   # AI/论文筛选规则
│   ├── extract-pdf-text.py     # PDF 文本提取
│   ├── test-ai-selection.ps1   # AI 筛选测试
│   ├── test-paper-selection.ps1# 论文筛选测试
│   ├── test-frontend-language.js   # 前端语言切换回归测试
│   ├── test-translation.ps1    # 英文翻译回归测试
│   ├── test-update-daily-rules.ps1 # 每日更新规则测试
│   ├── test-local-preview.ps1  # 本地预览语言切换测试
│   ├── sync-public.ps1         # 同步静态发布目录
│   └── start-web-server.ps1    # 本地网页服务
├── public/                     # 本地预览/发布同步目录
├── 个人信息收集库/             # 本地文档与归档库（不推送 GitHub）
└── .github/workflows/daily-update.yml  # GitHub Actions 定时更新
```

## 5. 已完成的功能

### 网页
- 静态网页展示系统，手机可访问
- 每日 7 篇内容结构（3 新闻 + 2 AI + 2 论文）
- 中文 / English 切换，标题、摘要、关键看点、论文卡片全部跟随切换
- 历史日期选择下拉框
- 安全链接过滤（只允许 http/https 协议）
- 论文卡片展示：解决问题、方法、差异、创新点、实现、应用、术语解释
- AI 应用显示证据链标签
- **论文卡片增加「阅读简介」链接**，指向 arXiv 摘要页，与「阅读原文」（PDF）分开
- **卡片高度统一**：论文详情区域用 max-height + 滚动，避免长卡片占据过多空间

### 数据与筛选
- 公开 RSS 新闻来源（NPR、The Guardian、Reuters 等）
- AI 应用文章 3 个月硬性时限
- AI 应用证据链规则：至少 2 个锚点，至少 1 个一手锚点
- AI 应用创新类显示"为什么它可能不能成功"，概念解释类显示"关键看点"
- 论文公开全文 PDF 门槛
- 论文正文提取质量门槛：提取不足 700 字符或缺少方法/应用信号时跳过
- 论文 `readabilityStatus` 字段（open / thin / unavailable）
- 论文方向保留：AI、脑机接口、芯片、能源
- 论文不足 2 篇时用 AI 应用文章补位
- 数据结构支持 `translations.en` 英文翻译字段
- 论文数据新增 `abstractUrl` 字段，指向 arXiv 摘要页
- 新闻来源保证多样性：每个来源最多选 1 篇（当前来源池：NPR World、The Guardian World、Reuters World）

### 测试
- `scripts/test-paper-selection.ps1` — 论文筛选规则回归验证
- `scripts/test-frontend-language.js` — 前端语言切换和链接安全验证
- `scripts/test-translation.ps1` — 英文翻译兜底链路验证
- `scripts/test-update-daily-rules.ps1` — 每日更新规则验证
- `scripts/test-local-preview.ps1` — 本地预览语言切换验证

### 自动化
- GitHub Actions 配置洛杉矶时间 08:00 自动更新
- 工作流推送触发验证

### 近期新增（2026-07-08）
- 新闻来源多样性：每来源最多选 1 篇，避免 3 篇来自同一媒体
- 文档中 BBC World 引用全部删除，统一为 NPR World / The Guardian World / Reuters World
- 论文卡片增加「阅读简介」链接（abstractUrl），与「阅读原文」（PDF）分开
- 论文详情区域 max-height: 200px + 滚动，控制卡片高度统一
- 数据结构：论文新增 `abstractUrl` 字段

## 6. 当前状态（2026-07-08）

- 所有代码修改已完成，已推送到 GitHub（commit `7cbeaba`）。
- `data/articles.json` 日期为 2026-07-07，含 7 篇完整内容、英文翻译、abstractUrl。
- AI 和论文筛选规则均已通过测试脚本验证。
- 英文模式标题翻译兜底链路已通过测试验证。
- `https://cloudy-7day.github.io/-/` 已部署最新版本。

## 7. 待完成

### 短期
1. 替换有效 DeepSeek API key，让 AI 智能总结和英文翻译走 DeepSeek 而非本地兜底。
2. 确认 GitHub Actions Secret 中 `DEEPSEEK_API_KEY` 有效，手动触发一次验证。
3. 观察 GitHub Actions 在云端环境能否稳定提取 PDF 文本。

### 中期
1. 增加用户收藏、评分、读后判断功能。
2. 增加更新日志中「本次为什么选中」的展示质量。
3. 增加失败日志摘要，方便判断每天哪些来源失败。
4. 优化英文翻译质量。

### 长期
1. 从 JSON 文件逐步迁移到轻量数据库或结构化数据层。
2. 增加多日趋势分析：哪些来源稳定、哪些主题反复出现。
3. 建立个人复盘库，从「每日阅读列表」升级为「技术判断力训练档案」。
4. 接入更稳定的 Reddit OAuth 或其他公开 API 作为候选发现来源。

## 8. 已知问题

- DeepSeek API key 当前无效（`401 invalid api key`），论文智能总结和英文翻译走本地兜底。
- GitHub Actions 需在推送后验证 PDF 文本提取是否在云端环境正常工作。
- 文档中 BBC World 引用已全部删除，统一为 NPR World / The Guardian World / Reuters World。
- 论文卡片高度虽已通过 max-height 控制，但长内容需要滚动查看，不是最理想的阅读体验。
- 长期考虑从 JSON 文件迁移到结构化数据层。

## 9. 重要设计决定

- 网页优先，不先做 App。
- 本地 JSON 优先，不先上数据库。
- GitHub Pages 作为固定访问入口。
- 后续页面功能和数据更新以线上 GitHub Pages `https://cloudy-7day.github.io/-/` 为最终交付目标；本地预览只用于检查，不作为完成标准。
- 新闻使用公开 RSS/API，不使用不可验证的真实浏览量。
- AI 应用必须 3 个月内，无例外。
- AI 应用创新类必须有证据链，不能只靠观点入选。
- 论文必须公开全文可读，且正文提取足够支撑阅读卡片；只看摘要或提取碎片的不进入每日推荐。
- 论文方向只保留 AI、脑机接口、芯片、能源。
- 论文不足 2 篇时用 AI 应用文章补位。
- DeepSeek 只基于可访问内容总结，不调用 GPT，不假装读过全文。
- 英文模式优先读取 `translations.en`；缺失翻译的旧归档回退显示原字段，避免历史数据损坏。
- 论文卡片同时显示「阅读简介」（摘要页）和「阅读原文」（PDF）两个链接。
- 卡片列表使用 CSS grid 等高新布局，论文详情区域限制高度以保持视觉统一。
- 后续由助手生成的项目文档统一归档到 `个人信息收集库/` 子文件夹，不再散放在项目根目录。
- 若根目录发布文件和 `个人信息收集库/` 中的归档快照冲突，根目录版本优先；归档快照只供追溯。
