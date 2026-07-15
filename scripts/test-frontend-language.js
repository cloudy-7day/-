const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const core = require("../site-core.js");

const article = {
  title: "原始标题",
  highlight: "中文摘句",
  summary: "中文摘要",
  failureAnalysis: "中文判断",
  paperCard: { problem: "中文问题" },
  translations: {
    en: {
      title: "English title",
      highlight: "English source highlight.",
      summary: "English summary",
      failureAnalysis: "English judgement",
      paperCard: { problem: "English problem" },
    },
  },
};

const englishArticle = core.getLocalizedArticle(article, "en");
assert.equal(englishArticle.title, "English title");
assert.equal(englishArticle.highlight, "English source highlight.");
assert.equal(englishArticle.summary, "English summary");
assert.equal(englishArticle.failureAnalysis, "English judgement");
assert.equal(englishArticle.paperCard.problem, "English problem");

const fallbackArticle = core.getLocalizedArticle(article, "fr");
assert.equal(fallbackArticle.summary, "中文摘要");
assert.equal(fallbackArticle.failureAnalysis, "中文判断");

assert.equal(core.getSafeArticleUrl("https://example.com/read"), "https://example.com/read");
assert.equal(core.getSafeArticleUrl("http://example.com/read"), "http://example.com/read");
assert.equal(core.getSafeArticleUrl("javascript:alert(1)"), "#");
assert.equal(core.getSafeArticleUrl("data:text/html,boom"), "#");

const root = path.join(__dirname, "..");
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
const live = readJson(path.join(root, "data", "articles.json"));
const archive = readJson(path.join(root, "data", "archive", `${live.issueDate}.json`));
assert.equal(live.articles.length, 7);
for (const current of live.articles) {
  assert.ok(current.highlight?.trim(), `Missing Chinese highlight: ${current.id}`);
  assert.ok(current.translations?.en?.highlight?.trim(), `Missing English highlight: ${current.id}`);
  assert.doesNotMatch(current.highlight, /^\s*(本文介绍|文章指出|值得阅读|这篇论文提出)/);
  assert.ok(current.highlight.length <= 260, `Chinese highlight is too long: ${current.id}`);
  assert.ok(current.translations.en.highlight.length <= 260, `English highlight is too long: ${current.id}`);
}
assert.deepEqual(live, archive);

console.log("Frontend language tests passed.");
