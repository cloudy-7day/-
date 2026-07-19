(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.SiteCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const CATEGORY_CONFIG = {
    news: {
      zh: "天下异闻",
      en: "Daily News",
      kickerZh: "观天下大事",
      kickerEn: "Signals at home and abroad",
      creature: "feifei",
    },
    ai: {
      zh: "机巧新术",
      en: "New Mechanisms",
      kickerZh: "察器物新生",
      kickerEn: "Tools, agents and inventions",
      creature: "tiangou",
    },
    paper: {
      zh: "格物手稿",
      en: "Research Manuscripts",
      kickerZh: "究万物之理",
      kickerEn: "Ideas beneath the evidence",
      creature: "nine-tailed-fox",
    },
  };

  function getDisplayCategory(category) {
    return category === "domestic" || category === "international" ? "news" : category;
  }

  function parseRoute(hash = "#/home") {
    const parts = hash.replace(/^#\/?/, "").split("/").filter(Boolean);
    if (!parts.length || parts[0] === "home") return { name: "home" };
    if (parts[0] === "favorites" && parts.length === 1) return { name: "favorites" };
    if (parts[0] === "favorite" && parts[1]) {
      try {
        return { name: "favorite", id: decodeURIComponent(parts.slice(1).join("/")) };
      } catch {
        return { name: "not-found" };
      }
    }
    const category = getDisplayCategory(parts[1]);
    if (parts[0] === "category" && CATEGORY_CONFIG[category]) {
      return { name: "category", category };
    }
    if (
      parts[0] === "article" &&
      /^\d{4}-\d{2}-\d{2}$/.test(parts[1]) &&
      /^\d+$/.test(parts[2])
    ) {
      return { name: "article", issueDate: parts[1], index: Number(parts[2]) };
    }
    return { name: "not-found" };
  }

  function groupArticles(articles = []) {
    return Object.fromEntries(
      Object.keys(CATEGORY_CONFIG).map((key) => [
        key,
        articles.filter((article) => getDisplayCategory(article.category) === key),
      ]),
    );
  }

  function getLocalizedArticle(article, language) {
    const translation = article?.translations?.[language];
    return translation
      ? { ...article, ...translation, paperCard: translation.paperCard || article.paperCard }
      : article;
  }

  function getSafeArticleUrl(value, base = "https://example.invalid/") {
    try {
      const url = new URL(value, base);
      return url.protocol === "http:" || url.protocol === "https:" ? url.href : "#";
    } catch {
      return "#";
    }
  }

  const getArticleRoute = (issueDate, index) => `#/article/${issueDate}/${index}`;
  const getFavoriteRoute = (id) => `#/favorite/${encodeURIComponent(String(id || ""))}`;

  function getArticleByRoute(articles, route) {
    return route.name === "article" ? articles[route.index] || null : null;
  }

  function cloneJson(value, fallback) {
    try {
      return value == null ? fallback : JSON.parse(JSON.stringify(value));
    } catch {
      return fallback;
    }
  }

  function createFavoriteSnapshot(article, issueDate, savedAt = new Date().toISOString()) {
    if (!article?.id || !article?.title) return null;
    if (!CATEGORY_CONFIG[getDisplayCategory(article.category)]) return null;
    return {
      id: String(article.id),
      savedAt: String(savedAt),
      issueDate: String(issueDate || ""),
      category: String(article.category || ""),
      title: String(article.title),
      source: String(article.source || ""),
      url: String(article.url || ""),
      abstractUrl: article.abstractUrl ? String(article.abstractUrl) : null,
      publishedAt: String(article.publishedAt || ""),
      scoreLabel: String(article.scoreLabel || ""),
      summary: String(article.summary || ""),
      failureAnalysis: String(article.failureAnalysis || ""),
      highlight: String(article.highlight || ""),
      summarySource: String(article.summarySource || ""),
      paperCard: cloneJson(article.paperCard, null),
      translations: cloneJson(article.translations, {}),
    };
  }

  function emptyFavoriteStore(deviceId = "") {
    return { version: 2, deviceId: String(deviceId || ""), updatedAt: "", records: {} };
  }

  function normalizeFavoriteRecord(id, value, fallbackDeviceId = "") {
    if (!id || !value || typeof value !== "object") return null;
    const updatedAt = String(value.updatedAt || value.item?.savedAt || "");
    const deviceId = String(value.deviceId || fallbackDeviceId || "");
    if (value.deleted) {
      return { id: String(id), updatedAt, deviceId, deleted: true, item: null };
    }
    const source = value.item || value;
    const item = createFavoriteSnapshot(source, source.issueDate, source.savedAt || updatedAt);
    return item ? { id: item.id, updatedAt: updatedAt || item.savedAt, deviceId, deleted: false, item } : null;
  }

  function parseFavoriteStore(serialized, deviceId = "") {
    let payload;
    try {
      payload = typeof serialized === "string" ? JSON.parse(serialized) : serialized;
    } catch {
      return emptyFavoriteStore(deviceId);
    }
    const store = emptyFavoriteStore(payload?.deviceId || deviceId);
    if (payload?.version === 2 && payload.records && typeof payload.records === "object") {
      Object.entries(payload.records).forEach(([id, value]) => {
        if (["__proto__", "prototype", "constructor"].includes(id)) return;
        const record = normalizeFavoriteRecord(id, value, store.deviceId);
        if (record) store.records[record.id] = record;
      });
      store.updatedAt = String(payload.updatedAt || "");
      return store;
    }
    const items = Array.isArray(payload) ? payload : payload?.items;
    if (!Array.isArray(items)) return store;
    items.forEach((item) => {
      const record = normalizeFavoriteRecord(item?.id, { item, updatedAt: item?.savedAt }, store.deviceId);
      if (record) store.records[record.id] = record;
    });
    store.updatedAt = String(payload?.updatedAt || payload?.exportedAt || "");
    return store;
  }

  function compareFavoriteRecords(left, right) {
    const byTime = String(left?.updatedAt || "").localeCompare(String(right?.updatedAt || ""));
    if (byTime) return byTime;
    return String(left?.deviceId || "").localeCompare(String(right?.deviceId || ""));
  }

  function mergeFavoriteStores(...stores) {
    const normalized = stores.map((store) => parseFavoriteStore(store));
    const result = emptyFavoriteStore(normalized.find((store) => store.deviceId)?.deviceId || "");
    normalized.forEach((store) => {
      Object.values(store.records).forEach((record) => {
        const existing = result.records[record.id];
        if (!existing || compareFavoriteRecords(existing, record) <= 0) result.records[record.id] = record;
      });
      if (String(store.updatedAt) > String(result.updatedAt)) result.updatedAt = store.updatedAt;
    });
    return result;
  }

  function favoriteStoreToItems(store) {
    return Object.values(parseFavoriteStore(store).records)
      .filter((record) => !record.deleted && record.item)
      .map((record) => record.item)
      .sort((a, b) => String(b.savedAt).localeCompare(String(a.savedAt)));
  }

  function parseFavoriteCollection(serialized) {
    return favoriteStoreToItems(parseFavoriteStore(serialized));
  }

  function buildAssociations(article, language) {
    const localized = getLocalizedArticle(article, language);
    const rows = [];
    if (localized?.paperCard?.applications) {
      rows.push({ label: language === "en" ? "Applications" : "应用", text: localized.paperCard.applications });
    }
    if (localized?.paperCard?.innovation) {
      rows.push({ label: language === "en" ? "Innovation" : "新意", text: localized.paperCard.innovation });
    }
    if (localized?.failureAnalysis) {
      rows.push({ label: language === "en" ? "Judgement" : "判断", text: localized.failureAnalysis });
    }
    if (!rows.length && localized?.summary) {
      rows.push({ label: language === "en" ? "Outlook" : "展望", text: localized.summary });
    }
    return rows.slice(0, 3);
  }

  function estimateReadingMinutes(article, language) {
    const text = [
      article?.summary,
      article?.failureAnalysis,
      ...buildAssociations(article, language).map((row) => row.text),
    ].filter(Boolean).join(" ");
    const amount = language === "en"
      ? text.trim().split(/\s+/).filter(Boolean).length / 200
      : text.replace(/\s/g, "").length / 400;
    return Math.max(1, Math.ceil(amount));
  }

  function getSummarySourceLabel(article, language) {
    if (article?.summarySource !== "source_extract") return "";
    return language === "en"
      ? "DeepSeek is temporarily unavailable; showing an automatic extract from the public source"
      : "DeepSeek 暂不可用，当前为公开原文自动摘录";
  }

  function cleanHighlightOpening(value) {
    return String(value || "")
      .replace(/\s+/g, " ")
      .trim()
      .replace(/^(?:本文介绍(?:了)?|文章指出|这篇论文提出(?:了)?|值得阅读(?:的是)?)[，,:：]?\s*/, "")
      .replace(/^This (?:article|paper) (?:introduces|reports that|reports|presents|proposes|explains)\s+/i, "")
      .replace(/^Worth reading(?: because)?[,:]?\s*/i, "")
      .trim();
  }

  function isPlaceholderHighlight(value) {
    return /Local (?:English )?fallback|candidate collected automatically|智能总结需要\s*DeepSeek\s*key|read the source and/i.test(String(value || ""));
  }

  function getArticleHighlight(article, language) {
    const localized = getLocalizedArticle(article, language);
    const explicit = cleanHighlightOpening(localized?.highlight);
    if (explicit && !isPlaceholderHighlight(explicit)) return explicit;

    const summary = String(localized?.summary || "").replace(/\s+/g, " ").trim();
    const sentences = summary.match(/[^.!?。！？]+[.!?。！？]?/g) || [];
    for (const sentence of sentences) {
      if (isPlaceholderHighlight(sentence)) continue;
      const cleaned = cleanHighlightOpening(sentence);
      if (cleaned.length >= 4) return cleaned.slice(0, 180).trim();
    }
    const fallback = cleanHighlightOpening(summary).slice(0, 180).trim();
    if (fallback && !isPlaceholderHighlight(fallback)) return fallback;
    return cleanHighlightOpening(localized?.title).slice(0, 180).trim();
  }

  return {
    CATEGORY_CONFIG,
    getDisplayCategory,
    parseRoute,
    groupArticles,
    getLocalizedArticle,
    getSafeArticleUrl,
    getArticleRoute,
    getFavoriteRoute,
    getArticleByRoute,
    createFavoriteSnapshot,
    emptyFavoriteStore,
    parseFavoriteStore,
    mergeFavoriteStores,
    favoriteStoreToItems,
    parseFavoriteCollection,
    buildAssociations,
    estimateReadingMinutes,
    getSummarySourceLabel,
    getArticleHighlight,
  };
});
