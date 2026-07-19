const assert = require("node:assert/strict");
const core = require("../site-core.js");

assert.deepEqual(core.parseRoute("#/home"), { name: "home" });
assert.deepEqual(core.parseRoute("#/category/ai"), { name: "category", category: "ai" });
assert.deepEqual(core.parseRoute("#/category/news"), { name: "category", category: "news" });
assert.deepEqual(core.parseRoute("#/category/international"), { name: "category", category: "news" });
assert.deepEqual(core.parseRoute("#/favorites"), { name: "favorites" });
assert.deepEqual(core.parseRoute("#/favorite/news-123"), { name: "favorite", id: "news-123" });
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
assert.equal(core.CATEGORY_CONFIG.news.zh, "\u5929\u4e0b\u5f02\u95fb");
assert.equal(core.CATEGORY_CONFIG.news.en, "Daily News");
assert.equal(core.CATEGORY_CONFIG.news.creature, "feifei");
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
const favorite = core.createFavoriteSnapshot({
  id: "news-123",
  category: "domestic",
  title: "值得保留的新闻",
  source: "Example",
  url: "https://example.com/story",
  summary: "摘要",
  translations: { en: { title: "A useful story", summary: "Summary" } },
}, "2026-07-14", "2026-07-15T10:00:00.000Z");
assert.equal(favorite.id, "news-123");
assert.equal(favorite.issueDate, "2026-07-14");
assert.equal(favorite.savedAt, "2026-07-15T10:00:00.000Z");
assert.equal(favorite.translations.en.title, "A useful story");
assert.equal(core.getFavoriteRoute("news-123"), "#/favorite/news-123");
assert.deepEqual(core.parseFavoriteCollection("not-json"), []);
assert.deepEqual(core.parseFavoriteCollection(JSON.stringify({ version: 1, items: [{ nope: true }] })), []);
assert.deepEqual(core.parseFavoriteCollection(JSON.stringify({ version: 1, items: [{ ...favorite, category: "unknown" }] })), []);
assert.deepEqual(
  core.parseFavoriteCollection(JSON.stringify({ version: 1, items: [favorite, { ...favorite, title: "newer" }] })),
  [{ ...favorite, title: "newer" }],
);
const legacyStore = core.parseFavoriteStore(JSON.stringify({ version: 1, items: [favorite] }), "device-a");
assert.equal(legacyStore.version, 2);
assert.equal(legacyStore.records[favorite.id].item.title, "值得保留的新闻");
const deletedStore = core.parseFavoriteStore({
  version: 2,
  deviceId: "device-b",
  updatedAt: "2026-07-16T10:00:00.000Z",
  records: {
    [favorite.id]: {
      id: favorite.id,
      updatedAt: "2026-07-16T10:00:00.000Z",
      deviceId: "device-b",
      deleted: true,
      item: null,
    },
  },
});
assert.deepEqual(core.favoriteStoreToItems(core.mergeFavoriteStores(legacyStore, deletedStore)), []);
const restoredStore = core.parseFavoriteStore({
  version: 2,
  deviceId: "device-a",
  updatedAt: "2026-07-17T10:00:00.000Z",
  records: {
    [favorite.id]: {
      id: favorite.id,
      updatedAt: "2026-07-17T10:00:00.000Z",
      deviceId: "device-a",
      deleted: false,
      item: { ...favorite, title: "重新收藏" },
    },
  },
});
assert.equal(core.favoriteStoreToItems(core.mergeFavoriteStores(deletedStore, restoredStore))[0].title, "重新收藏");
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
