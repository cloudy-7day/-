const labels = {
  international: "国际新闻",
  ai: "AI 应用",
  paper: "应用论文"
};

let allArticles = [];
let currentDataPath = "data/articles.json";

function formatDate(value) {
  if (!value) return "日期未知";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString("zh-CN", {
    year: "numeric",
    month: "short",
    day: "numeric"
  });
}

function renderArticles(filter = "all") {
  const list = document.querySelector("#article-list");
  const template = document.querySelector("#article-template");
  list.innerHTML = "";

  const articles = filter === "all"
    ? allArticles
    : allArticles.filter((article) => article.category === filter);

  articles.forEach((article) => {
    const node = template.content.cloneNode(true);
    node.querySelector(".badge").textContent = labels[article.category] || article.category;
    node.querySelector(".score").textContent = article.recommendationScore
      ? `推荐分 ${article.recommendationScore}/100`
      : article.scoreLabel || "热度待补";
    node.querySelector("h2").textContent = article.title;
    node.querySelector(".meta").textContent = `${article.source} | ${formatDate(article.publishedAt)} | ${article.selectionReason}`;
    node.querySelector(".summary").textContent = article.summary;
    node.querySelector(".analysis p").textContent = article.failureAnalysis;
    node.querySelector(".read-link").href = article.url;
    list.appendChild(node);
  });
}

async function loadArticles(path = currentDataPath) {
  currentDataPath = path;
  const response = await fetch(path, { cache: "no-store" });
  const payload = await response.json();
  allArticles = payload.articles;
  document.querySelector("#issue-date").textContent = formatDate(payload.issueDate);
  renderArticles();
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
