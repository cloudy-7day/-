const state = {
  articles: [],
  issueDate: "",
  dataPath: "data/articles.json",
  language: "zh",
  archives: [],
};

const app = document.querySelector("#app");
const routeStatus = document.querySelector("#route-status");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let activeSceneAnimation = 0;
let homeSceneProgress = 0;
let touchStartY = null;

const copy = {
  zh: {
    daily: "每日七闻",
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
    enter: "进入每日七闻",
    articleUnit: "篇",
  },
  en: {
    daily: "Seven Daily Notes",
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
    enter: "Enter today’s notes",
    articleUnit: "items",
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
          <p class="theme-date">${t("daily")} · ${escapeHtml(formatDate(state.issueDate))}</p>
          <div class="theme-list">${cards}</div>
          <div class="home-archive">${renderArchiveControls()}</div>
        </div>
        <button class="scroll-cue enter-button" type="button" aria-label="${t("enter")}">
          <span>SCROLL</span><i aria-hidden="true"></i>
        </button>
      </div>
    </section>`;

  document.body.classList.add("is-home");
  homeSceneProgress = getHomeScrollProgress();
  renderHomeScene(reducedMotion.matches ? 1 : homeSceneProgress);
  setRouteStatus(state.language === "en" ? "Home" : "首页");
}

function renderIndexCard(article, index, position) {
  const localized = SiteCore.getLocalizedArticle(article, state.language);
  const highlight = SiteCore.getArticleHighlight(article, state.language);
  return `
    <a class="index-card" href="${SiteCore.getArticleRoute(state.issueDate, index)}">
      <span class="index-number">${String(position + 1).padStart(2, "0")}</span>
      <span class="index-copy">
        <small>${escapeHtml(article.source)} · ${escapeHtml(formatDate(article.publishedAt?.slice(0, 10)))}</small>
        <strong>${escapeHtml(localized.title)}</strong>
        <span class="index-highlight">${escapeHtml(highlight)}</span>
      </span>
    </a>`;
}

function renderCategory(category) {
  const config = SiteCore.CATEGORY_CONFIG[category];
  const items = state.articles
    .map((article, index) => ({ article, index }))
    .filter(({ article }) => article.category === category);
  const title = state.language === "en" ? config.en : config.zh;

  document.body.classList.remove("is-home");
  app.innerHTML = `
    <section class="category-view page-view">
      <header class="category-heading">
        <a href="#/home">← ${t("back")}</a>
        <h1>${escapeHtml(title)}</h1>
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
  const summarySourceLabel = SiteCore.getSummarySourceLabel(article, state.language);
  const summarySourceMarkup = summarySourceLabel
    ? `<small class="summary-source-label">${escapeHtml(summarySourceLabel)}</small>`
    : "";

  document.body.classList.remove("is-home");
  app.innerHTML = `
    <article class="detail-view page-view">
      <header class="detail-topline">
        <a href="#/category/${article.category}">← ${escapeHtml(categoryTitle)}</a>
        <span>${escapeHtml(article.source)} · ${escapeHtml(formatDate(state.issueDate))}</span>
      </header>

      <div class="detail-hero">
        <h1 tabindex="-1">${escapeHtml(localized.title)}</h1>
        <div class="detail-meta">
          <span>${escapeHtml(categoryTitle)}</span>
          <span>${t("readTime")} ${readingTime} ${t("minute")}</span>
          <span>${escapeHtml(article.scoreLabel || "Curated")}</span>
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
  if (route.name === "home") return renderHome();
  if (route.name === "category") return renderCategory(route.category);
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
  renderRoute();
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

document.addEventListener("click", (event) => {
  const languageButton = event.target.closest("[data-language]");
  if (languageButton) setLanguage(languageButton.dataset.language);

  if (event.target.closest(".enter-button")) animateHomeScene(1);

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
