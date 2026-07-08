# 个人信息收集库

这是第一版可手机访问的信息收集网页：每天目标 7 篇文章，分为 3 篇国际新闻、2 篇 AI 应用、2 篇应用型论文。线上固定地址是 https://cloudy-7day.github.io/-/ 。

每次修改后的说明记录在 `CHANGELOG.md`，包括改了什么、为什么改、对使用有什么影响。

## 先用大白话说明

这个系统现在像一个“每天自动更新的阅读网页”。

你每天早上打开手机上的网页，就能看到 7 篇文章。它不是公众号，也不是 App。第一版先让它稳定工作，后面再加真正的手机通知、收藏、打分和复盘。

## 当前设计决定

1. 为什么先做网页？
   因为网页最容易让手机访问。你不用先学数据库、服务器、App 开发，只要电脑开着服务，手机在同一个网络里就能看。

2. 为什么先用本地数据文件？
   数据文件可以理解成一个小账本，里面记录今天 7 篇文章的标题、链接、来源和分析。以后文章越来越多，再换成数据库。

3. 为什么新闻不直接按浏览量？
   因为大多数新闻网站不会公开真实浏览量。我们不能假装知道。所以第一版先用 RSS 排序、媒体位置、社区讨论这些能公开看到的信号来代替，这叫“热度代理”。

4. 什么是 RSS？
   RSS 是媒体网站给机器看的文章目录。它能告诉我们“今天有哪些新文章”，但通常不会告诉我们“每篇有多少人看过”。

5. 什么是 HN points / comments？
   HN 是 Hacker News，一个技术圈常用讨论站。points 类似点赞，comments 是评论数。它们能说明技术人是否关注这篇文章，但不代表文章一定正确。

6. 为什么 Reddit 还没完全接入？
   Reddit 现在更推荐用官方 OAuth 授权。没有授权时，公开入口有时会返回网页壳，而不是干净数据。所以第一版先把它作为下一步，而不是让系统每天因为 Reddit 抽风就失败。

7. 为什么要 DeepSeek API？
   API 可以理解成“给 DeepSeek 发任务的通道”。系统把文章标题、摘要和链接发给 DeepSeek，让它帮你做初读，并生成“为什么这个项目可能不能成功”的反方分析。

8. 会不会依赖 GPT？
   不会。这个项目不调用 GPT。自动分析只准备接 DeepSeek。没有 DeepSeek key 时，系统只会使用固定规则提醒，不会偷偷换成 GPT。

9. 为什么论文不能只看 PDF 链接？
   公开 PDF 只是第一道门槛。系统还会检查能不能提取出足够正文信息；如果只有标题、摘要或碎片内容，就不进入论文位，论文不足时用 AI 应用文章补位。

10. 能不能看英文？
    可以。网页有中文 / English 切换。每日更新会保存英文翻译字段；DeepSeek 不可用时，会显示本地英文兜底提示。

11. 为什么要“为什么不能成功”？
   这是训练技术审美力。看到一个项目，不只问“它酷不酷”，还要问“真实需求是谁、成本高不高、数据从哪来、能不能规模化、有没有监管风险”。

12. 为什么每天洛杉矶时间 8 点？
    你的电脑现在就是 Pacific Time，所以计划任务直接设成每天 08:00。好处是夏令时变化由系统处理，不需要你手动换算。

## 使用

启动本地网页服务后，用同一 Wi-Fi 下的手机访问电脑局域网地址即可。

每日更新脚本：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/update-daily.ps1
```

安装每天 08:00 自动更新：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-daily-task.ps1
```

安装登录后自动启动网页服务：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-web-server-task.ps1
```

配置 DeepSeek API：

```powershell
setx DEEPSEEK_API_KEY "你的 DeepSeek API Key"
```

设置后，重新打开终端或重启电脑，计划任务就能读到这个 key。

## 下一步建议

1. 你给我 DeepSeek API key 后，我帮你接上真实初读和反方分析。
2. 下一步接 Reddit OAuth，让 Reddit 数据稳定进入筛选。
3. 再加收藏、评分、你的读后判断。这样系统会从“信息列表”变成“训练技术审美力的复盘库”。

## GitHub 稳定访问

GitHub Pages 用来提供固定网页地址：https://cloudy-7day.github.io/-/ 。GitHub Actions 用来每天洛杉矶时间 08:00 自动更新文章。

需要在 GitHub 仓库里手动设置一次 Secret：

1. 打开仓库 Settings
2. 进入 Secrets and variables > Actions
3. 新增 Repository secret
4. Name 填 `DEEPSEEK_API_KEY`
5. Secret 填 DeepSeek API key

然后在 Settings > Pages 中启用 GitHub Pages：

1. Source 选择 Deploy from a branch
2. Branch 选择 `main`
3. Folder 选择 `/root`
4. 保存后等待 GitHub 生成 Pages 地址
