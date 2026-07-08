# PROJECT_CONTEXT

## 1. 项目目标

本项目是一个个人信息收集与阅读训练网页，**线上最终交付地址为 `https://cloudy-7day.github.io/-/`**。
当前目标是每天自动整理 7 篇内容：

- 3 篇国际新闻
- 2 篇 AI 应用文章
- 2 篇应用型论文

核心目标不是收集最多内容，而是帮助使用者训练技术判断力：来源是否可靠、内容是否可读、是否有真实应用价值、失败风险在哪里、证据链是否可追溯。

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
├── index.html                  # 首页（含语言切换、历史归档）
├── app.js                      # 前端渲染逻辑（含中英文切换）
├── styles.css                  # 页面样式（含语言切换样式）
├── README.md                   # 项目说明
├── CHANGELOG.md                # 修改记录
├── PROJECT_CONTEXT.md          # 本文件，项目上下文
├── data/
│   ├── articles.json           # 当前每日 7 篇内容（含英文翻译）
│   └── archive/                # 历史归档
├── docs/
│   └── context/                # 合规与来源规则文档
├── scripts/
│   ├── update-daily.ps1        # 每日更新主脚本
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

## 6. 当前状态（2026-07-08）

- 所有代码修改已完成，已在本地验证通过。
- `data/articles.json` 日期为 2026-07-07，含 7 篇完整内容及英文翻译。
- AI 和论文筛选规则均已通过测试脚本验证。
- 英文模式标题翻译兜底链路已通过测试验证。
- 由于当前 Codex 使用额度限制（阻断信息：`You've hit your usage limit... try again at Jul 8th, 2026 12:20 AM`），**尚未执行 `git add` / `git commit` / `git push`**。
- `https://cloudy-7day.github.io/-/` 尚未更新到最新版本。

## 7. 待完成

额度恢复后，由用户手动执行以下命令：

```powershell
git add CHANGELOG.md README.md app.js data/articles.json data/archive/2026-07-07.json data/archive/index.json index.html scripts/article-selection.ps1 scripts/test-paper-selection.ps1 scripts/update-daily.ps1 styles.css scripts/test-frontend-language.js scripts/test-translation.ps1 scripts/test-update-daily-rules.ps1
git commit -m "Add English mode and stricter paper filtering"
git push origin main
```

## 8. 已知问题

- DeepSeek API key 当前无效（`401 invalid api key`），论文智能总结和英文翻译走本地兜底。
- GitHub Actions 需在推送后验证 PDF 文本提取是否在云端环境正常工作。
- 文档中 BBC World 引用已全部删除，统一为 NPR World / The Guardian World / Reuters World。
- 长期考虑从 JSON 文件迁移到结构化数据层。
