const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const source = fs.readFileSync("app.js", "utf8");
const setupEnd = source.indexOf('document.querySelectorAll(".tab")');

if (setupEnd === -1) {
  throw new Error("Could not isolate frontend language helpers.");
}

const sandbox = { URL };
vm.runInNewContext(
  `${source.slice(0, setupEnd)}
   this.setLanguage = (value) => { currentLanguage = value; };
   this.getLocalizedArticle = getLocalizedArticle;
   this.getSafeArticleUrl = getSafeArticleUrl;`,
  sandbox
);

const article = {
  title: "原始标题",
  summary: "中文摘要",
  failureAnalysis: "中文看点",
  paperCard: {
    problem: "中文问题"
  },
  translations: {
    en: {
      title: "English title",
      summary: "English summary",
      failureAnalysis: "English takeaway",
      paperCard: {
        problem: "English problem"
      }
    }
  }
};

sandbox.setLanguage("en");
const englishArticle = sandbox.getLocalizedArticle(article);
assert.equal(englishArticle.title, "English title");
assert.equal(englishArticle.summary, "English summary");
assert.equal(englishArticle.failureAnalysis, "English takeaway");
assert.equal(englishArticle.paperCard.problem, "English problem");

const oldArticle = {
  title: "旧文章",
  summary: "旧中文摘要",
  failureAnalysis: "旧中文看点"
};

const fallbackArticle = sandbox.getLocalizedArticle(oldArticle);
assert.equal(fallbackArticle.summary, "旧中文摘要");
assert.equal(fallbackArticle.failureAnalysis, "旧中文看点");

assert.equal(sandbox.getSafeArticleUrl("https://example.com/read"), "https://example.com/read");
assert.equal(sandbox.getSafeArticleUrl("http://example.com/read"), "http://example.com/read");
assert.equal(sandbox.getSafeArticleUrl("javascript:alert(1)"), "#");
assert.equal(sandbox.getSafeArticleUrl("data:text/html,boom"), "#");

console.log("Frontend language tests passed.");
