const labels = {
  zh: {
    international: "国际新闻",
    ai: "AI 应用",
    paper: "应用论文"
  },
  en: {
    international: "World News",
    ai: "AI Application",
    paper: "Applied Paper"
  }
};

let allArticles = [];
let currentDataPath = "data/articles.json";
let currentFilter = "all";
let currentLanguage = "zh";

function formatDate(value) {
  if (!value) return "日期未知";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString(currentLanguage === "en" ? "en-US" : "zh-CN", {
    year: "numeric",
    month: "short",
    day: "numeric"
  });
}

function renderArticles(filter = "all") {
  currentFilter = filter;
  const list = document.querySelector("#article-list");
  const template = document.querySelector("#article-template");
  list.innerHTML = "";

  const articles = filter === "all"
    ? allArticles
    : allArticles.filter((article) => article.category === filter);

  articles.forEach((article) => {
    const localized = getLocalizedArticle(article);
    const node = template.content.cloneNode(true);
    node.querySelector(".badge").textContent = labels[currentLanguage][article.category] || article.category;
    node.querySelector(".score").textContent = article.recommendationScore
      ? `${getText("scorePrefix")} ${article.recommendationScore}/100`
      : article.scoreLabel || getText("signalPending");
    node.querySelector("h2").textContent = localized.title;
    const metaParts = [article.source, formatDate(article.publishedAt), article.selectionReason];
    if (article.evidenceLabel) {
      metaParts.push(`${getText("evidencePrefix")}: ${article.evidenceLabel}`);
    }
    node.querySelector(".meta").textContent = metaParts.join(" | ");
    node.querySelector(".summary").textContent = localized.summary;
    const paperDetails = node.querySelector(".paper-details");
    if (localized.paperCard) {
      const fields = [
        localized.paperCard.problem,
        localized.paperCard.method,
        localized.paperCard.difference,
        localized.paperCard.innovation,
        localized.paperCard.implementation,
        localized.paperCard.applications,
        ...(localized.paperCard.technicalTerms || [])
      ].filter(Boolean);

      paperDetails.innerHTML = "";
      fields.forEach((value) => {
        const item = document.createElement("li");
        item.textContent = value;
        paperDetails.appendChild(item);
      });
      paperDetails.hidden = false;
    } else {
      paperDetails.hidden = true;
      paperDetails.innerHTML = "";
    }
    node.querySelector(".analysis h3").textContent = article.requiresRiskAnalysis
      ? getText("riskHeading")
      : getText("takeawayHeading");
    node.querySelector(".analysis p").textContent = localized.failureAnalysis;
    node.querySelector(".read-link").href = getSafeArticleUrl(article.url);
    node.querySelector(".read-link").textContent = getText("readOriginal");
    const abstractLink = node.querySelector(".abstract-link");
    if (article.abstractUrl) {
      abstractLink.href = getSafeArticleUrl(article.abstractUrl);
      abstractLink.textContent = getText("readAbstract");
      abstractLink.hidden = false;
    } else {
      abstractLink.hidden = true;
    }
    list.appendChild(node);
  });
}

function getSafeArticleUrl(value) {
  try {
    const base = globalThis.location?.href || "https://example.invalid/";
    const url = new URL(value, base);
    if (url.protocol === "http:" || url.protocol === "https:") {
      return url.href;
    }
  } catch {
    // Invalid or unsafe URLs fall back to a harmless in-page target.
  }
  return "#";
}

function getText(key) {
  const copy = {
    zh: {
      riskHeading: "为什么它可能不能成功",
      takeawayHeading: "关键看点",
      readOriginal: "阅读原文",
      readAbstract: "阅读简介",
      scorePrefix: "推荐分",
      signalPending: "热度待补",
      evidencePrefix: "证据链"
    },
    en: {
      riskHeading: "Why it may fail",
      takeawayHeading: "Key takeaway",
      readOriginal: "Read source",
      readAbstract: "Read abstract",
      scorePrefix: "Score",
      signalPending: "Signal pending",
      evidencePrefix: "Evidence"
    }
  };
  return copy[currentLanguage][key];
}

function getLocalizedArticle(article) {
  const translation = article.translations?.[currentLanguage];
  if (!translation) {
    return article;
  }

  return {
    ...article,
    title: translation.title || article.title,
    summary: translation.summary || article.summary,
    failureAnalysis: translation.failureAnalysis || article.failureAnalysis,
    paperCard: translation.paperCard || article.paperCard
  };
}

async function loadArticles(path = currentDataPath) {
  currentDataPath = path;
  const response = await fetch(path, { cache: "no-store" });
  const payload = await response.json();
  allArticles = payload.articles;
  document.querySelector("#issue-date").textContent = formatDate(payload.issueDate);
  renderArticles(currentFilter);
}

async function loadArchiveIndex() {
  try {
    const response = await fetch("data/archive/index.json", { cache: "no-store" });
    if (!response.ok) return;

    const payload = await response.json();
    const select = document.querySelector("#archive-select");
    payload.archives.forEach((archive) => {
      const option = document.createElement("option");
      option.value = archive.path;
      option.textContent = archive.date;
      select.appendChild(option);
    });
  } catch {
    // Archive index is optional. The daily page still works without it.
  }
}

document.querySelectorAll(".tab").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((tab) => tab.classList.remove("active"));
    button.classList.add("active");
    renderArticles(button.dataset.filter);
  });
});

document.querySelectorAll(".language-button").forEach((button) => {
  button.addEventListener("click", () => {
    currentLanguage = button.dataset.language;
    document.querySelectorAll(".language-button").forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    renderArticles(currentFilter);
  });
});

document.querySelector("#archive-select").addEventListener("change", (event) => {
  loadArticles(event.target.value);
});

loadArchiveIndex();
loadArticles().catch((error) => {
  document.querySelector("#article-list").innerHTML = `
    <article class="article-card">
      <h2>数据暂时没有加载成功</h2>
      <p class="summary">${error.message}</p>
    </article>
  `;
});
