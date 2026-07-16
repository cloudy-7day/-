const assert = require("node:assert/strict");
const core = require("../site-core.js");

assert.deepEqual(core.parseRoute("#/home"), { name: "home" });
assert.deepEqual(core.parseRoute("#/category/ai"), { name: "category", category: "ai" });
assert.deepEqual(core.parseRoute("#/category/news"), { name: "category", category: "news" });
assert.deepEqual(core.parseRoute("#/category/international"), { name: "category", category: "news" });
assert.deepEqual(core.parseRoute("#/article/2026-07-14/3"), {
  name: "article",
  issueDate: "2026-07-14",
  index: 3,
});
assert.equal(core.parseRoute("#/category/unknown").name, "not-found");

const articles = [
  { category: "domestic", title: "国内新闻" },
  { category: "ai", title: "工具" },
  { category: "international", title: "国际新闻" },
  { category: "paper", title: "论文" },
];

const grouped = core.groupArticles(articles);
assert.deepEqual(Object.keys(grouped), ["news", "ai", "paper"]);
assert.deepEqual(grouped.news, [articles[0], articles[2]]);
assert.deepEqual(grouped.ai, [articles[1]]);
assert.deepEqual(grouped.paper, [articles[3]]);
assert.deepEqual(core.groupArticles([{ category: "international", title: "旧卷新闻" }]).news, [
  { category: "international", title: "旧卷新闻" },
]);

assert.equal(core.getDisplayCategory("domestic"), "news");
assert.equal(core.getDisplayCategory("international"), "news");
assert.equal(core.getDisplayCategory("ai"), "ai");
assert.equal(core.getDisplayCategory("paper"), "paper");
assert.equal(core.getDisplayCategory("unknown"), "unknown");
assert.equal(core.getSafeArticleUrl("javascript:alert(1)", "https://example.com"), "#");
assert.equal(
  core.getArticleByRoute(articles, { name: "article", issueDate: "2026-07-14", index: 1 }),
  articles[1],
);
assert.ok(core.estimateReadingMinutes({ summary: "测试内容" }, "zh") >= 1);
assert.equal(core.getSummarySourceLabel({ summarySource: "deepseek" }, "zh"), "");
assert.equal(
  core.getSummarySourceLabel({ summarySource: "source_extract" }, "zh"),
  "DeepSeek 暂不可用，当前为公开原文自动摘录",
);
assert.equal(
  core.getSummarySourceLabel({ summarySource: "source_extract" }, "en"),
  "DeepSeek is temporarily unavailable; showing an automatic extract from the public source",
);
assert.equal(core.getSummarySourceLabel({}, "zh"), "");
assert.equal(
  core.getArticleHighlight({ highlight: "来源摘句", summary: "完整摘要。" }, "zh"),
  "来源摘句",
);
assert.equal(
  core.getArticleHighlight({ summary: "文章指出，边境之外仍在寻找更快路径。第二句。" }, "zh"),
  "边境之外仍在寻找更快路径。",
);
assert.equal(
  core.getArticleHighlight({
    highlight: "中文摘句",
    translations: { en: { highlight: "The original sentence remains intact." } },
  }, "en"),
  "The original sentence remains intact.",
);
assert.equal(
  core.getArticleHighlight({ summary: "这篇论文提出了一种可检查的结构推理方法。值得阅读。" }, "zh"),
  "一种可检查的结构推理方法。",
);
assert.equal(
  core.getArticleHighlight({
    title: "边境会谈重新启动",
    summary: "Local fallback: news candidate collected automatically.",
    translations: {
      en: {
        title: "Border talks resume",
        summary: "Local English fallback: read the source and identify the event.",
      },
    },
  }, "en"),
  "Border talks resume",
);
console.log("Site core tests passed.");
