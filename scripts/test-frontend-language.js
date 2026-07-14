const assert = require("node:assert/strict");
const core = require("../site-core.js");

const article = {
  title: "原始标题",
  summary: "中文摘要",
  failureAnalysis: "中文判断",
  paperCard: { problem: "中文问题" },
  translations: {
    en: {
      title: "English title",
      summary: "English summary",
      failureAnalysis: "English judgement",
      paperCard: { problem: "English problem" },
    },
  },
};

const englishArticle = core.getLocalizedArticle(article, "en");
assert.equal(englishArticle.title, "English title");
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

console.log("Frontend language tests passed.");
