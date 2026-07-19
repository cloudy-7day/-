const state = {
  articles: [],
  issueDate: "",
  dataPath: "data/articles.json",
  language: "zh",
  archives: [],
  favorites: [],
  favoriteStore: null,
  favoriteMessage: "",
  favoriteDeviceId: "",
  favoriteFileHandle: null,
  favoriteFileStatus: "disconnected",
  favoriteFileName: "",
  favoriteLastSync: "",
  returnToGate: false,
};

const FAVORITES_KEY = "shanhaijing:favorites:v1";
const FAVORITE_DEVICE_KEY = "shanhaijing:favorites-device:v1";
const FAVORITE_HANDLE_DB = "shanhaijing-favorites";
const FAVORITE_HANDLE_STORE = "handles";
const FAVORITE_HANDLE_KEY = "favorites-file";
const FAVORITE_SYNC_LOCK = "shanhaijing-favorites-file";

const app = document.querySelector("#app");
const routeStatus = document.querySelector("#route-status");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let activeSceneAnimation = 0;
let homeSceneProgress = 0;
let touchStartY = null;

const copy = {
  zh: {
    daily: "每日九闻",
    source: "前往原文",
    abstract: "论文摘要",
    back: "返回卷首",
    archive: "往日卷册",
    today: "今日",
    readTime: "预计阅读",
    minute: "分钟",
    empty: "此卷今日暂无条目",
    loadingError: "今日卷册暂未展开，请稍后重试。",
    sayWhat: "这件事在说什么",
    consider: "顺手想一想",
    enter: "进入每日九闻",
    articleUnit: "篇",
    favorites: "收藏",
    favorite: "收藏",
    favorited: "已收藏",
    favoritesEmpty: "还没有收藏。遇到值得留下的内容时，点一下收藏即可。",
    exportFavorites: "导出收藏",
    importFavorites: "导入收藏",
    importedFavorites: "收藏已合并导入",
    storageError: "收藏未能保存，请检查浏览器存储空间。",
    savedOn: "收藏于",
    connectFile: "连接本地文件",
    restoreFile: "恢复文件连接",
    syncFile: "立即同步",
    disconnectFile: "断开连接",
    fileUnsupported: "当前浏览器不支持自动文件同步，可继续使用导入与导出。",
    fileDisconnected: "未连接本地收藏文件",
    filePermission: "需要重新授权文件访问",
    fileSyncing: "正在同步",
    fileConnected: "已连接",
    fileSynced: "已同步",
    fileError: "文件同步失败",
  },
  en: {
    daily: "Nine Daily Notes",
    source: "Read source",
    abstract: "View abstract",
    back: "Back to volume",
    archive: "Past issues",
    today: "Today",
    readTime: "Reading time",
    minute: "min",
    empty: "No entries in this volume today",
    loadingError: "The daily volume could not be opened. Please try again.",
    sayWhat: "What it says",
    consider: "Consider next",
    enter: "Enter today's nine notes",
    articleUnit: "items",
    favorites: "Saved",
    favorite: "Save",
    favorited: "Saved",
    favoritesEmpty: "Nothing saved yet. Save an item when it is worth keeping.",
    exportFavorites: "Export",
    importFavorites: "Import",
    importedFavorites: "Saved items imported",
    storageError: "Could not save. Check browser storage space.",
    savedOn: "Saved",
    connectFile: "Connect local file",
    restoreFile: "Restore file access",
    syncFile: "Sync now",
    disconnectFile: "Disconnect",
    fileUnsupported: "Automatic file sync is not supported here. Import and export remain available.",
    fileDisconnected: "No local favorites file connected",
    filePermission: "File access needs permission",
    fileSyncing: "Syncing",
    fileConnected: "Connected",
    fileSynced: "Synced",
    fileError: "File sync failed",
  },
};

function t(key) {
  return copy[state.language][key];
}

function getFavoriteDeviceId() {
  try {
    const existing = localStorage.getItem(FAVORITE_DEVICE_KEY);
    if (existing) return existing;
    const created = crypto.randomUUID?.() || `device-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    localStorage.setItem(FAVORITE_DEVICE_KEY, created);
    return created;
  } catch {
    return `session-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }
}

function refreshFavoriteItems() {
  state.favorites = SiteCore.favoriteStoreToItems(state.favoriteStore);
}

function loadFavorites() {
  state.favoriteDeviceId = getFavoriteDeviceId();
  try {
    state.favoriteStore = SiteCore.parseFavoriteStore(
      localStorage.getItem(FAVORITES_KEY),
      state.favoriteDeviceId,
    );
  } catch {
    state.favoriteStore = SiteCore.emptyFavoriteStore(state.favoriteDeviceId);
  }
  state.favoriteStore.deviceId = state.favoriteDeviceId;
  refreshFavoriteItems();
  persistFavoriteStore({ syncFile: false });
}

function persistFavoriteStore({ syncFile = true } = {}) {
  try {
    localStorage.setItem(FAVORITES_KEY, JSON.stringify(state.favoriteStore));
    refreshFavoriteItems();
    if (syncFile && state.favoriteFileHandle) void syncFavoritesWithFile();
    return true;
  } catch {
    setRouteStatus(t("storageError"));
    return false;
  }
}

function getFavorite(id) {
  return state.favorites.find((item) => item.id === id) || null;
}

function isFavorite(id) {
  return Boolean(getFavorite(id));
}

function updateFavoritesHeader() {
  document.querySelectorAll("[data-favorites-label]").forEach((label) => {
    label.textContent = t("favorites");
  });
  document.querySelectorAll("[data-favorites-count]").forEach((count) => {
    count.textContent = String(state.favorites.length);
  });
}

function toggleFavorite(article, issueDate) {
  if (!article?.id) return;
  const previous = SiteCore.parseFavoriteStore(JSON.stringify(state.favoriteStore), state.favoriteDeviceId);
  const updatedAt = new Date().toISOString();
  if (isFavorite(article.id)) {
    state.favoriteStore.records[article.id] = {
      id: article.id,
      updatedAt,
      deviceId: state.favoriteDeviceId,
      deleted: true,
      item: null,
    };
  } else {
    const snapshot = SiteCore.createFavoriteSnapshot(article, issueDate, updatedAt);
    if (snapshot) {
      state.favoriteStore.records[article.id] = {
        id: article.id,
        updatedAt,
        deviceId: state.favoriteDeviceId,
        deleted: false,
        item: snapshot,
      };
    }
  }
  state.favoriteStore.updatedAt = updatedAt;
  if (!persistFavoriteStore()) {
    state.favoriteStore = previous;
    refreshFavoriteItems();
    return;
  }
  updateFavoritesHeader();
  renderRoute();
}

function supportsFavoriteFileSync() {
  return "showSaveFilePicker" in window && "indexedDB" in window;
}

function openFavoriteHandleDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(FAVORITE_HANDLE_DB, 1);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(FAVORITE_HANDLE_STORE)) {
        request.result.createObjectStore(FAVORITE_HANDLE_STORE);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function readStoredFavoriteFileHandle() {
  if (!("indexedDB" in window)) return null;
  const db = await openFavoriteHandleDb();
  try {
    return await new Promise((resolve, reject) => {
      const request = db.transaction(FAVORITE_HANDLE_STORE, "readonly")
        .objectStore(FAVORITE_HANDLE_STORE)
        .get(FAVORITE_HANDLE_KEY);
      request.onsuccess = () => resolve(request.result || null);
      request.onerror = () => reject(request.error);
    });
  } finally {
    db.close();
  }
}

async function storeFavoriteFileHandle(handle) {
  const db = await openFavoriteHandleDb();
  try {
    await new Promise((resolve, reject) => {
      const request = db.transaction(FAVORITE_HANDLE_STORE, "readwrite")
        .objectStore(FAVORITE_HANDLE_STORE)
        .put(handle, FAVORITE_HANDLE_KEY);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  } finally {
    db.close();
  }
}

async function clearFavoriteFileHandle() {
  if (!("indexedDB" in window)) return;
  const db = await openFavoriteHandleDb();
  try {
    await new Promise((resolve, reject) => {
      const request = db.transaction(FAVORITE_HANDLE_STORE, "readwrite")
        .objectStore(FAVORITE_HANDLE_STORE)
        .delete(FAVORITE_HANDLE_KEY);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  } finally {
    db.close();
  }
}

async function hasFavoriteFilePermission(handle, requestPermission = false) {
  if (!handle) return false;
  const options = { mode: "readwrite" };
  if (typeof handle.queryPermission !== "function") return true;
  if (await handle.queryPermission(options) === "granted") return true;
  return requestPermission
    && typeof handle.requestPermission === "function"
    && await handle.requestPermission(options) === "granted";
}

function favoriteFileStatusText() {
  if (!supportsFavoriteFileSync()) return t("fileUnsupported");
  const name = state.favoriteFileName ? ` · ${state.favoriteFileName}` : "";
  if (state.favoriteFileStatus === "permission") return `${t("filePermission")}${name}`;
  if (state.favoriteFileStatus === "syncing") return `${t("fileSyncing")}${name}`;
  if (state.favoriteFileStatus === "connected") {
    const time = state.favoriteLastSync
      ? new Intl.DateTimeFormat(state.language === "en" ? "en-US" : "zh-CN", {
        hour: "2-digit",
        minute: "2-digit",
      }).format(new Date(state.favoriteLastSync))
      : "";
    return `${time ? t("fileSynced") : t("fileConnected")}${name}${time ? ` · ${time}` : ""}`;
  }
  if (state.favoriteFileStatus === "error") return `${t("fileError")}${name}`;
  return t("fileDisconnected");
}

function refreshFavoriteFileStatus() {
  document.querySelectorAll("[data-favorite-file-status]").forEach((element) => {
    element.textContent = favoriteFileStatusText();
  });
}

async function withFavoriteSyncLock(task) {
  if (navigator.locks?.request) return navigator.locks.request(FAVORITE_SYNC_LOCK, task);
  return task();
}

async function syncFavoritesWithFile({ requestPermission = false } = {}) {
  const handle = state.favoriteFileHandle;
  if (!handle) return false;
  try {
    if (!await hasFavoriteFilePermission(handle, requestPermission)) {
      state.favoriteFileStatus = "permission";
      refreshFavoriteFileStatus();
      return false;
    }
    state.favoriteFileStatus = "syncing";
    refreshFavoriteFileStatus();
    await withFavoriteSyncLock(async () => {
      const file = await handle.getFile();
      const remoteStore = file.size
        ? SiteCore.parseFavoriteStore(await file.text(), state.favoriteDeviceId)
        : SiteCore.emptyFavoriteStore(state.favoriteDeviceId);
      const merged = SiteCore.mergeFavoriteStores(state.favoriteStore, remoteStore);
      merged.deviceId = state.favoriteDeviceId;
      state.favoriteStore = merged;
      persistFavoriteStore({ syncFile: false });
      const writable = await handle.createWritable();
      await writable.write(JSON.stringify(state.favoriteStore, null, 2));
      await writable.close();
    });
    state.favoriteLastSync = new Date().toISOString();
    state.favoriteFileStatus = "connected";
    updateFavoritesHeader();
    refreshFavoriteFileStatus();
    return true;
  } catch (error) {
    console.error("Favorite file sync failed", error);
    state.favoriteFileStatus = "error";
    refreshFavoriteFileStatus();
    return false;
  }
}

async function connectFavoriteFile() {
  if (!supportsFavoriteFileSync()) return;
  try {
    if (!state.favoriteFileHandle) {
      state.favoriteFileHandle = await window.showSaveFilePicker({
        id: "shanhaijing-favorites",
        suggestedName: "shanhaijing-favorites.json",
        types: [{
          description: "JSON favorites",
          accept: { "application/json": [".json"] },
        }],
      });
      await storeFavoriteFileHandle(state.favoriteFileHandle);
    }
    state.favoriteFileName = state.favoriteFileHandle.name || "shanhaijing-favorites.json";
    await syncFavoritesWithFile({ requestPermission: true });
    renderFavorites();
  } catch (error) {
    if (error?.name === "AbortError") return;
    console.error("Could not connect favorites file", error);
    state.favoriteFileStatus = "error";
    renderFavorites();
  }
}

async function restoreFavoriteFileConnection() {
  if (!supportsFavoriteFileSync()) {
    state.favoriteFileStatus = "unsupported";
    return;
  }
  try {
    state.favoriteFileHandle = await readStoredFavoriteFileHandle();
    if (!state.favoriteFileHandle) return;
    state.favoriteFileName = state.favoriteFileHandle.name || "shanhaijing-favorites.json";
    if (await hasFavoriteFilePermission(state.favoriteFileHandle)) {
      await syncFavoritesWithFile();
    } else {
      state.favoriteFileStatus = "permission";
    }
  } catch (error) {
    console.error("Could not restore favorites file", error);
    state.favoriteFileHandle = null;
    state.favoriteFileStatus = "error";
  }
}

async function disconnectFavoriteFile() {
  try {
    await clearFavoriteFileHandle();
  } catch (error) {
    console.error("Could not clear favorites file handle", error);
  }
  state.favoriteFileHandle = null;
  state.favoriteFileName = "";
  state.favoriteLastSync = "";
  state.favoriteFileStatus = "disconnected";
  renderFavorites();
}

function escapeHtml(value = "") {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(`${value}T12:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(state.language === "en" ? "en-US" : "zh-CN", {
    year: "numeric",
    month: state.language === "en" ? "short" : "long",
    day: "numeric",
  }).format(date);
}

function renderArchiveControls() {
  const options = [
    `<option value="data/articles.json"${state.dataPath === "data/articles.json" ? " selected" : ""}>${t("today")} · ${escapeHtml(state.issueDate)}</option>`,
    ...state.archives.map((archive) =>
      `<option value="${escapeHtml(archive.path)}"${state.dataPath === archive.path ? " selected" : ""}>${escapeHtml(archive.date)}</option>`,
    ),
  ].join("");
  return `<label class="archive-control"><span>${t("archive")}</span><select id="archive-select">${options}</select></label>`;
}

function renderHome() {
  const grouped = SiteCore.groupArticles(state.articles);
  const returnToGate = state.returnToGate;
  state.returnToGate = false;
  const cards = Object.entries(SiteCore.CATEGORY_CONFIG).map(([key, config], index) => {
    const title = state.language === "en" ? config.en : config.zh;
    return `
      <a class="theme-card theme-card--${key}" href="#/category/${key}">
        <span class="theme-number">${String(index + 1).padStart(2, "0")}</span>
        <img src="assets/${config.creature}-transparent.png" alt="" aria-hidden="true">
        <span class="theme-card-copy">
          <strong>${escapeHtml(title)}</strong>
          <em>${grouped[key].length} ${t("articleUnit")}</em>
        </span>
      </a>`;
  }).join("");

  app.innerHTML = `
    <section class="intro-journey" aria-labelledby="hero-title">
      <div class="intro-stage">
        <div class="hero-scene" aria-hidden="true"></div>
        <div class="hero-copy">
          <p class="hero-overline">THE LOST CREATURES OF SHAN HAI JING</p>
          <h1 id="hero-title" class="hero-title">山海经的漏网之鱼</h1>
        </div>
        <div class="theme-gate" aria-label="${t("daily")}">
          <div class="theme-gate-meta">
            <p class="theme-date">${escapeHtml(formatDate(state.issueDate))}</p>
            <a class="home-favorites-link" href="#/favorites">
              <span data-favorites-label>${t("favorites")}</span>
              <b data-favorites-count>${state.favorites.length}</b>
              <i aria-hidden="true">→</i>
            </a>
          </div>
          <div class="theme-list">${cards}</div>
          <div class="home-archive">${renderArchiveControls()}</div>
        </div>
        <button class="scroll-cue enter-button" type="button" aria-label="${t("enter")}">
          <span>SCROLL</span><i aria-hidden="true"></i>
        </button>
      </div>
    </section>`;

  document.body.classList.add("is-home");
  if (returnToGate) {
    requestAnimationFrame(() => {
      const journey = document.querySelector(".intro-journey");
      if (!journey) return;
      const distance = Math.max(1, journey.offsetHeight - innerHeight);
      scrollTo({ top: journey.offsetTop + distance, behavior: "instant" });
      renderHomeScene(1);
    });
  } else {
    homeSceneProgress = getHomeScrollProgress();
    renderHomeScene(reducedMotion.matches ? 1 : homeSceneProgress);
  }
  setRouteStatus(state.language === "en" ? "Home" : "首页");
}

function renderFavoriteButton(article, issueDate, className = "") {
  const saved = isFavorite(article.id);
  const label = saved ? t("favorited") : t("favorite");
  return `<button class="favorite-toggle${className ? ` ${className}` : ""}" type="button"
    data-favorite-id="${escapeHtml(article.id)}" data-issue-date="${escapeHtml(issueDate)}"
    aria-pressed="${String(saved)}" aria-label="${escapeHtml(label)}">
      <span aria-hidden="true">${saved ? "◆" : "◇"}</span><em>${escapeHtml(label)}</em>
    </button>`;
}

function renderIndexCard(article, index, position, options = {}) {
  const localized = SiteCore.getLocalizedArticle(article, state.language);
  const highlight = SiteCore.getArticleHighlight(article, state.language);
  const issueDate = options.issueDate || state.issueDate;
  const href = options.href || SiteCore.getArticleRoute(issueDate, index);
  const showFavorite = options.showFavorite !== false;
  return `
    <article class="index-entry">
      <a class="index-card" href="${escapeHtml(href)}">
        <span class="index-number">${String(position + 1).padStart(2, "0")}</span>
        <span class="index-copy">
          <small>${escapeHtml(article.source)} · ${escapeHtml(formatDate(article.publishedAt?.slice(0, 10)))}</small>
          <strong>${escapeHtml(localized.title)}</strong>
          <span class="index-highlight">${escapeHtml(highlight)}</span>
        </span>
      </a>
      ${showFavorite ? renderFavoriteButton(article, issueDate, "index-favorite") : ""}
    </article>`;
}

function renderCategory(category) {
  const config = SiteCore.CATEGORY_CONFIG[category];
  const items = state.articles
    .map((article, index) => ({ article, index }))
    .filter(({ article }) => SiteCore.getDisplayCategory(article.category) === category);
  const title = state.language === "en" ? config.en : config.zh;
  const renderIndex = (indexItems) => `
    <div class="article-index category-index">
      ${indexItems.length ? `<div class="category-index-archive">${renderArchiveControls()}</div>` : ""}
      ${indexItems.length
        ? indexItems.map(({ article, index }, position) => renderIndexCard(article, index, position, { showFavorite: false })).join("")
        : `<p class="empty-state">${t("empty")}</p>`}
    </div>`;
  const indexMarkup = renderIndex(items);

  document.body.classList.remove("is-home");
  app.innerHTML = `
    <section class="category-view page-view">
      <header class="category-heading">
        <a href="#/home" data-back-gate>← ${t("back")}</a>
        <h1>${escapeHtml(title)}</h1>
      </header>
      <div class="category-rule" aria-hidden="true"></div>
      ${indexMarkup}
    </section>`;
  setRouteStatus(title);
}

function renderFavorites() {
  document.body.classList.remove("is-home");
  const cards = state.favorites.map((article, position) => renderIndexCard(article, position, position, {
    issueDate: article.issueDate,
    href: SiteCore.getFavoriteRoute(article.id),
  })).join("");
  const message = state.favoriteMessage;
  state.favoriteMessage = "";
  const fileSupported = supportsFavoriteFileSync();
  const hasFile = Boolean(state.favoriteFileHandle);
  const needsFilePermission = state.favoriteFileStatus === "permission";
  app.innerHTML = `
    <section class="favorites-view page-view">
      <header class="favorites-heading">
        <a href="#/home" data-back-gate>← ${t("back")}</a>
        <div class="favorites-title">
          <h1>${t("favorites")}</h1>
          <p>${state.favorites.length} ${t("articleUnit")}</p>
        </div>
        <div class="favorites-actions">
          <div class="favorites-tools">
            <button type="button" data-export-favorites${state.favorites.length ? "" : " disabled"}>${t("exportFavorites")}</button>
            <label>${t("importFavorites")}<input type="file" data-import-favorites accept="application/json,.json"></label>
            ${fileSupported ? `
              ${!hasFile || needsFilePermission ? `<button type="button" data-connect-favorites-file>${hasFile ? t("restoreFile") : t("connectFile")}</button>` : ""}
              ${hasFile ? `<button type="button" data-sync-favorites-file>${t("syncFile")}</button>
                <button type="button" data-disconnect-favorites-file>${t("disconnectFile")}</button>` : ""}
            ` : ""}
          </div>
          <p class="favorite-file-status" data-favorite-file-status>${escapeHtml(favoriteFileStatusText())}</p>
        </div>
      </header>
      <div class="category-rule" aria-hidden="true"></div>
      ${message ? `<p class="favorites-message" role="status">${escapeHtml(message)}</p>` : ""}
      <div class="article-index favorites-index">
        ${cards || `<p class="empty-state">${t("favoritesEmpty")}</p>`}
      </div>
    </section>`;
  setRouteStatus(t("favorites"));
}

function exportFavorites() {
  if (!state.favorites.length) return;
  const payload = JSON.stringify({ ...state.favoriteStore, exportedAt: new Date().toISOString() }, null, 2);
  const blob = new Blob([payload], { type: "application/json;charset=utf-8" });
  const href = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = href;
  link.download = `shanhaijing-favorites-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(href), 0);
}

async function importFavorites(file) {
  if (!file) return;
  let payload;
  try {
    payload = JSON.parse(await file.text());
  } catch {
    state.favoriteMessage = state.language === "en" ? "The selected file is not valid JSON." : "所选文件不是有效的收藏文件。";
    return renderFavorites();
  }
  const isLegacyCollection = Array.isArray(payload) || Array.isArray(payload?.items);
  const isCurrentStore = payload?.version === 2 && payload.records && typeof payload.records === "object";
  if (!isLegacyCollection && !isCurrentStore) {
    state.favoriteMessage = state.language === "en" ? "No saved items were found in this file." : "文件中没有找到收藏记录。";
    return renderFavorites();
  }
  const importedStore = SiteCore.parseFavoriteStore(payload, state.favoriteDeviceId);
  const imported = SiteCore.favoriteStoreToItems(importedStore);
  const previous = SiteCore.parseFavoriteStore(JSON.stringify(state.favoriteStore), state.favoriteDeviceId);
  state.favoriteStore = SiteCore.mergeFavoriteStores(state.favoriteStore, importedStore);
  state.favoriteStore.deviceId = state.favoriteDeviceId;
  if (!persistFavoriteStore()) {
    state.favoriteStore = previous;
    refreshFavoriteItems();
    return;
  }
  state.favoriteMessage = `${t("importedFavorites")} · ${imported.length}`;
  updateFavoritesHeader();
  renderFavorites();
}

function associationMarkup(rows) {
  return rows.map((row) => `
    <div class="association-row">
      <strong>${escapeHtml(row.label)}</strong>
      <p>${escapeHtml(row.text)}</p>
    </div>`).join("");
}

function renderArticle(route) {
  const article = SiteCore.getArticleByRoute(state.articles, route);
  if (!article || route.issueDate !== state.issueDate) return renderNotFound();
  const displayCategory = SiteCore.getDisplayCategory(article.category);
  const config = SiteCore.CATEGORY_CONFIG[displayCategory];
  const categoryTitle = state.language === "en" ? config.en : config.zh;
  const backHref = displayCategory === "news" ? "#/category/news" : `#/category/${displayCategory}`;
  return renderArticleView(article, state.issueDate, backHref, categoryTitle);
}

function renderFavoriteArticle(route) {
  const article = getFavorite(route.id);
  if (!article) return renderNotFound();
  return renderArticleView(article, article.issueDate, "#/favorites", t("favorites"));
}

function renderArticleView(article, issueDate, backHref, backLabel) {
  const localized = SiteCore.getLocalizedArticle(article, state.language);
  const displayCategory = SiteCore.getDisplayCategory(article.category);
  const config = SiteCore.CATEGORY_CONFIG[displayCategory];
  const associations = SiteCore.buildAssociations(article, state.language);
  const categoryTitle = state.language === "en" ? config.en : config.zh;
  const originalUrl = SiteCore.getSafeArticleUrl(article.url, location.href);
  const abstractUrl = article.abstractUrl ? SiteCore.getSafeArticleUrl(article.abstractUrl, location.href) : "#";
  const readingTime = SiteCore.estimateReadingMinutes(localized, state.language);
  const summarySourceLabel = SiteCore.getSummarySourceLabel(article, state.language);
  const summarySourceMarkup = summarySourceLabel
    ? `<small class="summary-source-label">${escapeHtml(summarySourceLabel)}</small>`
    : "";

  document.body.classList.remove("is-home");
  app.innerHTML = `
    <article class="detail-view page-view">
      <header class="detail-topline">
        <a href="${escapeHtml(backHref)}">← ${escapeHtml(backLabel)}</a>
        <span>${escapeHtml(article.source)} · ${escapeHtml(formatDate(issueDate))}</span>
      </header>

      <div class="detail-hero">
        <h1 tabindex="-1">${escapeHtml(localized.title)}</h1>
        <div class="detail-meta">
          <span>${escapeHtml(categoryTitle)}</span>
          <span>${t("readTime")} ${readingTime} ${t("minute")}</span>
          <span>${escapeHtml(article.scoreLabel || "Curated")}</span>
          ${renderFavoriteButton(article, issueDate, "detail-favorite")}
        </div>
      </div>

      <section class="detail-content">
        <div class="detail-primary">
          <h2>${t("sayWhat")}</h2>
          ${summarySourceMarkup}
          <p class="detail-summary">${escapeHtml(localized.summary)}</p>
        </div>
        <aside class="detail-secondary">
          <h2>${t("consider")}</h2>
          <div class="association-list">${associationMarkup(associations)}</div>
          <div class="source-actions">
            <a href="${escapeHtml(originalUrl)}" target="_blank" rel="noopener noreferrer">${t("source")} ↗</a>
            ${abstractUrl !== "#" ? `<a href="${escapeHtml(abstractUrl)}" target="_blank" rel="noopener noreferrer">${t("abstract")} ↗</a>` : ""}
          </div>
        </aside>
      </section>
    </article>`;
  document.querySelector(".detail-hero h1")?.focus({ preventScroll: true });
  setRouteStatus(localized.title);
}

function renderNotFound() {
  document.body.classList.remove("is-home");
  app.innerHTML = `<section class="not-found page-view"><p>404</p><h1>此鱼不在卷中</h1><a href="#/home">返回首页</a></section>`;
  setRouteStatus("页面不存在");
}

function renderRoute() {
  cancelAnimationFrame(activeSceneAnimation);
  activeSceneAnimation = 0;
  const route = SiteCore.parseRoute(location.hash);
  const favoritesLink = document.querySelector(".favorites-link");
  if (favoritesLink) {
    if (route.name === "favorites" || route.name === "favorite") favoritesLink.setAttribute("aria-current", "page");
    else favoritesLink.removeAttribute("aria-current");
  }
  if (route.name === "home") return renderHome();
  if (route.name === "category") return renderCategory(route.category);
  if (route.name === "favorites") return renderFavorites();
  if (route.name === "favorite") return renderFavoriteArticle(route);
  if (route.name === "article") return renderArticle(route);
  return renderNotFound();
}

function getHomeScrollProgress() {
  const journey = document.querySelector(".intro-journey");
  if (!journey) return homeSceneProgress;
  const distance = Math.max(1, journey.offsetHeight - innerHeight);
  return Math.min(1, Math.max(0, (scrollY - journey.offsetTop) / distance));
}

function renderHomeScene(progress) {
  const journey = document.querySelector(".intro-journey");
  if (!journey) return;
  const value = Math.min(1, Math.max(0, Number(progress) || 0));
  const hero = MotionCore.heroFrame(value);
  const heroCopy = journey.querySelector(".hero-copy");
  const gate = journey.querySelector(".theme-gate");
  const date = journey.querySelector(".theme-date");
  const cue = journey.querySelector(".scroll-cue");
  const gateProgress = Math.min(1, Math.max(0, (value - 0.2) / 0.5));

  if (heroCopy) {
    heroCopy.style.opacity = String(hero.opacity);
    heroCopy.style.transform = `translateY(${hero.yVh}vh) scale(${hero.scale})`;
    heroCopy.style.filter = `blur(${hero.blurPx}px)`;
  }
  if (gate) {
    gate.style.opacity = String(gateProgress);
    gate.style.pointerEvents = value > 0.92 ? "auto" : "none";
  }
  if (date) {
    date.style.opacity = String(gateProgress);
    date.style.transform = `translateY(${18 * (1 - gateProgress)}vh)`;
  }
  journey.querySelectorAll(".theme-card").forEach((card, index) => {
    const frame = MotionCore.cardFrame(value, index);
    card.style.opacity = String(frame.opacity);
    card.style.transform = `translateY(${frame.yVh}vh) scale(${frame.scale})`;
    card.style.filter = `saturate(${frame.saturation}) blur(${frame.blurPx}px)`;
  });
  if (cue) cue.style.opacity = String(Math.max(0, 0.65 * (1 - value * 3)));
  journey.classList.toggle("intro-complete", value > 0.92);
  homeSceneProgress = value;
}

function animateHomeScene(targetProgress) {
  const journey = document.querySelector(".intro-journey");
  if (!journey) return;
  cancelAnimationFrame(activeSceneAnimation);
  if (reducedMotion.matches) {
    renderHomeScene(1);
    return;
  }

  const startProgress = homeSceneProgress;
  const target = targetProgress > startProgress ? 1 : 0;
  const distance = Math.max(1, journey.offsetHeight - innerHeight);
  const startTime = performance.now();
  const duration = Math.max(320, MotionCore.durationMs * Math.abs(target - startProgress));

  function step(now) {
    const elapsed = Math.min(1, (now - startTime) / duration);
    const eased = elapsed * elapsed * (3 - 2 * elapsed);
    const progress = startProgress + (target - startProgress) * eased;
    renderHomeScene(progress);
    scrollTo({ top: journey.offsetTop + distance * progress, behavior: "instant" });
    if (elapsed < 1) {
      activeSceneAnimation = requestAnimationFrame(step);
    } else {
      activeSceneAnimation = 0;
      renderHomeScene(target);
    }
  }

  activeSceneAnimation = requestAnimationFrame(step);
}

function handleWheel(event) {
  if (!document.body.classList.contains("is-home") || Math.abs(event.deltaY) < 8) return;
  event.preventDefault();
  animateHomeScene(event.deltaY > 0 ? 1 : 0);
}

function handleHomeKey(event) {
  if (!document.body.classList.contains("is-home")) return;
  const down = ["ArrowDown", "PageDown", " "].includes(event.key);
  const up = ["ArrowUp", "PageUp", "Home"].includes(event.key);
  if (!down && !up) return;
  event.preventDefault();
  animateHomeScene(down ? 1 : 0);
}

async function loadArticles(path = state.dataPath) {
  const response = await fetch(path, { cache: "no-store" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const payload = await response.json();
  state.articles = payload.articles || [];
  state.issueDate = payload.issueDate || "";
  state.dataPath = path;
  renderRoute();
}

async function loadArchiveIndex() {
  try {
    const response = await fetch("data/archive/index.json", { cache: "no-store" });
    if (!response.ok) return;
    const payload = await response.json();
    state.archives = payload.archives || [];
  } catch {
    state.archives = [];
  }
}

function setLanguage(language) {
  state.language = language === "en" ? "en" : "zh";
  document.documentElement.lang = state.language === "en" ? "en" : "zh-CN";
  document.querySelectorAll("[data-language]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.language === state.language));
  });
  updateFavoritesHeader();
  renderRoute();
}

function setRouteStatus(message) {
  routeStatus.textContent = message;
}

window.addEventListener("hashchange", () => {
  cancelAnimationFrame(activeSceneAnimation);
  activeSceneAnimation = 0;
  scrollTo({ top: 0, behavior: "instant" });
  renderRoute();
});
window.addEventListener("wheel", handleWheel, { passive: false });
window.addEventListener("keydown", handleHomeKey);
window.addEventListener("scroll", () => {
  if (document.body.classList.contains("is-home") && !activeSceneAnimation && !reducedMotion.matches) {
    renderHomeScene(getHomeScrollProgress());
  }
}, { passive: true });
window.addEventListener("resize", () => renderHomeScene(reducedMotion.matches ? 1 : getHomeScrollProgress()));
window.addEventListener("touchstart", (event) => {
  touchStartY = event.touches[0]?.clientY ?? null;
}, { passive: true });
window.addEventListener("touchend", (event) => {
  if (touchStartY === null || !document.body.classList.contains("is-home")) return;
  const endY = event.changedTouches[0]?.clientY ?? touchStartY;
  const delta = touchStartY - endY;
  touchStartY = null;
  if (Math.abs(delta) >= 30) animateHomeScene(delta > 0 ? 1 : 0);
}, { passive: true });
reducedMotion.addEventListener?.("change", () => renderHomeScene(reducedMotion.matches ? 1 : getHomeScrollProgress()));
window.addEventListener("storage", (event) => {
  if (event.key !== FAVORITES_KEY) return;
  state.favoriteStore = SiteCore.parseFavoriteStore(event.newValue, state.favoriteDeviceId);
  state.favoriteStore.deviceId = state.favoriteDeviceId;
  refreshFavoriteItems();
  updateFavoritesHeader();
  renderRoute();
});

document.addEventListener("click", (event) => {
  const languageButton = event.target.closest("[data-language]");
  if (languageButton) setLanguage(languageButton.dataset.language);

  if (event.target.closest(".enter-button")) animateHomeScene(1);

  if (event.target.closest("[data-back-gate]")) state.returnToGate = true;

  const favoriteButton = event.target.closest("[data-favorite-id]");
  if (favoriteButton) {
    const article = state.articles.find((item) => item.id === favoriteButton.dataset.favoriteId)
      || getFavorite(favoriteButton.dataset.favoriteId);
    toggleFavorite(article, favoriteButton.dataset.issueDate || article?.issueDate || state.issueDate);
  }

  if (event.target.closest("[data-export-favorites]")) exportFavorites();
  if (event.target.closest("[data-connect-favorites-file]")) void connectFavoriteFile();
  if (event.target.closest("[data-sync-favorites-file]")) {
    void syncFavoritesWithFile({ requestPermission: true }).then(() => renderFavorites());
  }
  if (event.target.closest("[data-disconnect-favorites-file]")) void disconnectFavoriteFile();

  const themeButton = event.target.closest("[data-theme-toggle]");
  if (themeButton) {
    const isDark = document.documentElement.toggleAttribute("data-dark");
    themeButton.setAttribute("aria-pressed", String(isDark));
  }
});

document.addEventListener("change", (event) => {
  if (event.target.id === "archive-select") {
    loadArticles(event.target.value).catch(showLoadError);
  }
  if (event.target.matches("[data-import-favorites]")) {
    importFavorites(event.target.files?.[0]);
  }
});

function showLoadError(error) {
  document.body.classList.remove("is-home");
  app.innerHTML = `<section class="not-found page-view"><p>DATA</p><h1>${t("loadingError")}</h1><small>${escapeHtml(error.message)}</small></section>`;
}

async function bootstrap() {
  if (!location.hash) location.replace("#/home");
  loadFavorites();
  await restoreFavoriteFileConnection();
  updateFavoritesHeader();
  await loadArchiveIndex();
  await loadArticles();
}

bootstrap().catch(showLoadError);
