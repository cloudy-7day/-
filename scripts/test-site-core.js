const assert = require("node:assert/strict");
const core = require("../site-core.js");

assert.deepEqual(core.parseRoute("#/home"), { name: "home" });
assert.deepEqual(core.parseRoute("#/category/ai"), { name: "category", category: "ai" });
assert.deepEqual(core.parseRoute("#/article/2026-07-14/3"), {
  name: "article",
  issueDate: "2026-07-14",
  index: 3,
});
assert.equal(core.parseRoute("#/category/unknown").name, "not-found");

const articles = [
  { category: "international", title: "新闻" },
  { category: "ai", title: "工具" },
  { category: "paper", title: "论文" },
];

assert.equal(core.groupArticles(articles).international.length, 1);
assert.equal(core.groupArticles(articles).ai.length, 1);
assert.equal(core.groupArticles(articles).paper.length, 1);
assert.equal(core.getSafeArticleUrl("javascript:alert(1)", "https://example.com"), "#");
assert.equal(
  core.getArticleByRoute(articles, { name: "article", issueDate: "2026-07-14", index: 1 }),
  articles[1],
);
assert.ok(core.estimateReadingMinutes({ summary: "测试内容" }, "zh") >= 1);
console.log("Site core tests passed.");
