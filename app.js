const state = {
  articles: [],
  issueDate: "",
  dataPath: "data/articles.json",
  language: "zh",
  detailPage: 1,
  archives: [],
};

const app = document.querySelector("#app");
const routeStatus = document.querySelector("#route-status");

const copy = {
  zh: {
    daily: "每日七闻",
    browse: "择一卷，启封细读",
    source: "前往原文",
    abstract: "论文摘要",
    back: "返回卷首",
    brief: "简介",
    associations: "延伸联想",
    next: "翻至下一页",
    previous: "返回上一页",
    archive: "往日卷册",
    today: "今日",
    readTime: "预计阅读",
    minute: "分钟",
    empty: "此卷今日暂无条目",
    loadingError: "今日卷册暂未展开，请稍后重试。",
  },
  en: {
    daily: "Seven Daily Notes",
    browse: "Choose a volume to begin",
    source: "Read source",
    abstract: "View abstract",
    back: "Back to volume",
    brief: "Brief",
    associations: "Associations",
    next: "Turn the page",
    previous: "Previous page",
    archive: "Past issues",
    today: "Today",
    readTime: "Reading time",
    minute: "min",
    empty: "No entries in this volume today",
    loadingError: "The daily volume could not be opened. Please try again.",
  },
};

function t(key) {
  return copy[state.language][key];
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
  const cards = Object.entries(SiteCore.CATEGORY_CONFIG).map(([key, config], index) => {
    const title = state.language === "en" ? config.en : config.zh;
    const kicker = state.language === "en" ? config.kickerEn : config.kickerZh;
    return `
      <a class="theme-card theme-card--${key}" href="#/category/${key}">
        <span class="theme-number">卷 ${String(index + 1).padStart(2, "0")}</span>
        <img src="assets/${config.creature}-transparent.png" alt="" aria-hidden="true">
        <span class="theme-card-copy">
          <small>${escapeHtml(kicker)}</small>
          <strong>${escapeHtml(title)}</strong>
          <em>${grouped[key].length} 篇</em>
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
          <p class="hero-subtitle">异闻、机巧与格物，藏入每日七篇。</p>
        </div>
        <div class="theme-gate" aria-label="${t("browse")}">
          <header class="theme-heading">
            <p>${t("daily")} · ${escapeHtml(formatDate(state.issueDate))}</p>
            <h2>${t("browse")}</h2>
          </header>
          <div class="theme-list">${cards}</div>
          <div class="home-archive">${renderArchiveControls()}</div>
        </div>
        <div class="scroll-cue"><span>SCROLL</span><i aria-hidden="true"></i></div>
      </div>
    </section>`;

  document.body.classList.add("is-home");
  requestAnimationFrame(updateIntroProgress);
  setRouteStatus("首页");
}

function renderIndexCard(article, index, position) {
  const localized = SiteCore.getLocalizedArticle(article, state.language);
  return `
    <a class="index-card" href="${SiteCore.getArticleRoute(state.issueDate, index)}">
      <span class="index-number">${String(position + 1).padStart(2, "0")}</span>
      <span class="index-copy">
        <small>${escapeHtml(article.source)} · ${escapeHtml(formatDate(article.publishedAt?.slice(0, 10)))}</small>
        <strong>${escapeHtml(localized.title)}</strong>
        <span>${escapeHtml(localized.summary)}</span>
      </span>
      <b>启封细读&nbsp;↗</b>
    </a>`;
}

function renderCategory(category) {
  const config = SiteCore.CATEGORY_CONFIG[category];
  const items = state.articles
    .map((article, index) => ({ article, index }))
    .filter(({ article }) => article.category === category);
  const title = state.language === "en" ? config.en : config.zh;
  const kicker = state.language === "en" ? config.kickerEn : config.kickerZh;

  document.body.classList.remove("is-home");
  app.innerHTML = `
    <section class="category-view page-view">
      <header class="category-heading">
        <a href="#/home">← ${t("back")}</a>
        <div><p>${escapeHtml(kicker)}</p><h1>${escapeHtml(title)}</h1></div>
        ${renderArchiveControls()}
      </header>
      <div class="category-rule" aria-hidden="true"></div>
      <div class="article-index">
        ${items.length ? items.map(({ article, index }, position) => renderIndexCard(article, index, position)).join("") : `<p class="empty-state">${t("empty")}</p>`}
      </div>
    </section>`;
  setRouteStatus(title);
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
  const localized = SiteCore.getLocalizedArticle(article, state.language);
  const config = SiteCore.CATEGORY_CONFIG[article.category];
  const associations = SiteCore.buildAssociations(article, state.language);
  const categoryTitle = state.language === "en" ? config.en : config.zh;
  const originalUrl = SiteCore.getSafeArticleUrl(article.url, location.href);
  const abstractUrl = article.abstractUrl ? SiteCore.getSafeArticleUrl(article.abstractUrl, location.href) : "#";
  const readingTime = SiteCore.estimateReadingMinutes(localized, state.language);

  document.body.classList.remove("is-home");
  app.innerHTML = `
    <article class="detail-view page-view">
      <header class="detail-topline">
        <a href="#/category/${article.category}">← ${escapeHtml(categoryTitle)}</a>
        <span>卷 ${String(route.index + 1).padStart(2, "0")} · 条目</span>
        <span class="detail-progress">1 / 2</span>
      </header>

      <section class="detail-page" data-detail-page="1">
        <div class="detail-hero">
          <p>${escapeHtml(article.source)} · ${escapeHtml(formatDate(state.issueDate))}</p>
          <h1 tabindex="-1">${escapeHtml(localized.title)}</h1>
          <div class="detail-meta">
            <span>${escapeHtml(categoryTitle)}</span>
            <span>${t("readTime")} ${readingTime} ${t("minute")}</span>
            <span>${escapeHtml(article.scoreLabel || "Curated")}</span>
          </div>
        </div>
        <div class="detail-spread">
          <div class="detail-copy">
            <p class="section-kicker">BRIEF / ${t("brief")}</p>
            <h2>这件事在说什么</h2>
            <p class="detail-summary">${escapeHtml(localized.summary)}</p>
          </div>
          <figure class="detail-illustration">
            <img src="assets/${config.creature}-transparent.png" alt="" aria-hidden="true">
          </figure>
        </div>
      </section>

      <section class="detail-page" data-detail-page="2" hidden>
        <div class="detail-spread detail-spread--second">
          <div class="detail-copy">
            <p class="section-kicker">ASSOCIATIONS / ${t("associations")}</p>
            <h2 tabindex="-1">顺手想一想</h2>
            <div class="association-list">${associationMarkup(associations)}</div>
            <div class="source-actions">
              <a href="${escapeHtml(originalUrl)}" target="_blank" rel="noopener noreferrer">${t("source")} ↗</a>
              ${abstractUrl !== "#" ? `<a href="${escapeHtml(abstractUrl)}" target="_blank" rel="noopener noreferrer">${t("abstract")} ↗</a>` : ""}
            </div>
          </div>
          <figure class="detail-illustration detail-illustration--quiet">
            <img src="assets/${config.creature}-transparent.png" alt="" aria-hidden="true">
          </figure>
        </div>
      </section>

      <footer class="detail-footer">
        <button class="detail-page-toggle" type="button" data-next-page="2">${t("next")} <span>→</span></button>
      </footer>
    </article>`;
  setDetailPage(1);
  setRouteStatus(localized.title);
}

function setDetailPage(page) {
  state.detailPage = page === 2 ? 2 : 1;
  document.querySelectorAll("[data-detail-page]").forEach((panel) => {
    panel.hidden = Number(panel.dataset.detailPage) !== state.detailPage;
  });
  const progress = document.querySelector(".detail-progress");
  if (progress) progress.textContent = `${state.detailPage} / 2`;
  const button = document.querySelector(".detail-page-toggle");
  if (button) {
    const nextPage = state.detailPage === 1 ? 2 : 1;
    button.dataset.nextPage = String(nextPage);
    button.innerHTML = `${state.detailPage === 1 ? t("next") : t("previous")} <span>${state.detailPage === 1 ? "→" : "←"}</span>`;
  }
  document.querySelector(`[data-detail-page="${state.detailPage}"] h1, [data-detail-page="${state.detailPage}"] h2`)?.focus({ preventScroll: true });
}

function renderNotFound() {
  document.body.classList.remove("is-home");
  app.innerHTML = `<section class="not-found page-view"><p>404</p><h1>此鱼不在卷中</h1><a href="#/home">返回首页</a></section>`;
  setRouteStatus("页面不存在");
}

function renderRoute() {
  const route = SiteCore.parseRoute(location.hash);
  if (route.name === "home") return renderHome();
  if (route.name === "category") return renderCategory(route.category);
  if (route.name === "article") return renderArticle(route);
  return renderNotFound();
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
  renderRoute();
}

function updateIntroProgress() {
  const journey = document.querySelector(".intro-journey");
  if (!journey) return;
  const distance = Math.max(1, journey.offsetHeight - innerHeight);
  const progress = Math.min(1, Math.max(0, -journey.getBoundingClientRect().top / distance));
  document.documentElement.style.setProperty("--intro-progress", progress.toFixed(4));
  journey.classList.toggle("intro-complete", progress > 0.68);
}

function setRouteStatus(message) {
  routeStatus.textContent = message;
}

function updateClock() {
  const clock = document.querySelector("#clock");
  if (!clock) return;
  const value = new Intl.DateTimeFormat("zh-CN", {
    timeZone: "America/Los_Angeles",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date());
  clock.textContent = `洛杉矶 ${value}`;
}

window.addEventListener("hashchange", () => {
  state.detailPage = 1;
  document.documentElement.style.setProperty("--intro-progress", "0");
  renderRoute();
  scrollTo({ top: 0, behavior: "instant" });
});
window.addEventListener("scroll", updateIntroProgress, { passive: true });
window.addEventListener("resize", updateIntroProgress);

document.addEventListener("click", (event) => {
  const languageButton = event.target.closest("[data-language]");
  if (languageButton) setLanguage(languageButton.dataset.language);

  const pageButton = event.target.closest(".detail-page-toggle");
  if (pageButton) setDetailPage(Number(pageButton.dataset.nextPage));

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
});

function showLoadError(error) {
  document.body.classList.remove("is-home");
  app.innerHTML = `<section class="not-found page-view"><p>DATA</p><h1>${t("loadingError")}</h1><small>${escapeHtml(error.message)}</small></section>`;
}

async function bootstrap() {
  if (!location.hash) location.replace("#/home");
  updateClock();
  setInterval(updateClock, 1000);
  await loadArchiveIndex();
  await loadArticles();
}

bootstrap().catch(showLoadError);
