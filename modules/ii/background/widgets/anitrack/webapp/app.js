(() => {
  "use strict";

  const el = (id) => document.getElementById(id);
  const ui = {
    app: el("app"),
    subtitle: el("subtitle"),
    refresh: el("refresh"),
    tabs: [...document.querySelectorAll(".tab")],
    searchForm: el("search-form"),
    searchInput: el("search-input"),
    searchSummary: el("search-summary"),
    searchCount: el("search-count"),
    searchState: el("search-state"),
    searchResults: el("search-results"),
    searchMore: el("search-more"),
    scheduleTitle: el("schedule-title"),
    scheduleCount: el("schedule-count"),
    dayPicker: el("day-picker"),
    scheduleState: el("schedule-state"),
    scheduleResults: el("schedule-results"),
    scheduleMore: el("schedule-more"),
    historyCount: el("history-count"),
    historyState: el("history-state"),
    historyResults: el("history-results"),
    continueHistory: el("continue-history"),
    detailBack: el("detail-back"),
    detailPoster: el("detail-poster"),
    detailMeta: el("detail-meta"),
    detailTitle: el("detail-title"),
    detailFacts: el("detail-facts"),
    detailGenres: el("detail-genres"),
    detailSynopsis: el("detail-synopsis"),
    detailLaunch: el("detail-launch"),
    anilistLink: el("anilist-link"),
    footerStatus: el("footer-status"),
    footerCount: el("footer-count")
  };

  let api = null;
  let state = {};
  let detailReturnId = "";

  const icons = {
    poster: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="16" height="16" rx="3"/><path d="M9 4v16M15 4v16M4 9h5M15 9h5M4 15h5M15 15h5"/></svg>',
    search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.8" cy="10.8" r="6.2"/><path d="m15.4 15.4 4.2 4.2"/></svg>',
    calendar: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="5" width="16" height="16" rx="2"/><path d="M8 3v4M16 3v4M4 10h16M8 14h3M8 17h6"/></svg>',
    history: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v14H4zM8 9h8M8 13h6M8 17h4"/></svg>',
    error: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v6M12 17h.01"/></svg>'
  };

  function safeImageUrl(value) {
    const url = String(value || "");
    return /^https:\/\//i.test(url) ? url : "";
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function makePoster(url, title) {
    const poster = document.createElement("div");
    poster.className = "poster";
    poster.setAttribute("aria-hidden", "true");
    const safeUrl = safeImageUrl(url);
    if (!safeUrl) {
      poster.innerHTML = icons.poster;
      return poster;
    }
    const image = document.createElement("img");
    image.alt = "";
    image.loading = "lazy";
    image.decoding = "async";
    image.referrerPolicy = "no-referrer";
    image.src = safeUrl;
    image.addEventListener("error", () => {
      poster.replaceChildren();
      poster.innerHTML = icons.poster;
    }, { once: true });
    poster.appendChild(image);
    return poster;
  }

  function addButton(label, className, onClick, accessibleName) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = className;
    button.textContent = label;
    if (accessibleName) button.setAttribute("aria-label", accessibleName);
    button.addEventListener("click", onClick);
    return button;
  }

  function metadata(item) {
    return [item.type || "", item.year || "", Number(item.episodes) > 0 ? `${item.episodes} eps` : ""]
      .filter(Boolean).join(" · ");
  }

  function formatScore(value) {
    const score = Number(value) || 0;
    return score > 0 ? `★ ${score.toFixed(1)}` : String(value || "Score unavailable");
  }

  function renderState(node, title, detail, mode = "idle", icon = icons.search) {
    clear(node);
    node.className = `state-message${node.id === "search-state" ? "" : " compact-state"} ${mode}`.trim();
    const iconWrap = document.createElement("span");
    iconWrap.className = "state-icon";
    iconWrap.setAttribute("aria-hidden", "true");
    iconWrap.innerHTML = icon;
    const titleNode = document.createElement("span");
    titleNode.className = "state-title";
    titleNode.textContent = title;
    node.append(iconWrap, titleNode);
    if (detail) {
      const detailNode = document.createElement("span");
      detailNode.className = "state-detail";
      detailNode.textContent = detail;
      node.appendChild(detailNode);
    }
    node.hidden = false;
  }

  function stateView(stateName, errorText, initialTitle, initialDetail, emptyTitle, emptyDetail, loadingTitle, loadingDetail) {
    if (stateName === "loading" || stateName === "waiting") {
      return { title: loadingTitle, detail: loadingDetail, mode: "loading", icon: icons.search };
    }
    if (stateName === "error") {
      return { title: "Could not load this section", detail: errorText || "Try again in a moment.", mode: "error", icon: icons.error };
    }
    if (stateName === "empty") {
      return { title: emptyTitle, detail: emptyDetail, mode: "empty", icon: icons.search };
    }
    return { title: initialTitle, detail: initialDetail, mode: "idle", icon: icons.search };
  }

  function makeAnimeCard(item, index) {
    const card = document.createElement("article");
    card.className = `anime-card${index === 0 ? " featured" : ""}`;
    const image = makePoster(item.imageUrl, item.title);
    image.setAttribute("aria-hidden", "true");

    const copy = document.createElement("div");
    copy.className = "card-copy";
    if (index === 0) {
      const eyebrow = document.createElement("p");
      eyebrow.className = "eyebrow";
      eyebrow.textContent = "Top match";
      copy.appendChild(eyebrow);
    }
    const title = document.createElement("h3");
    title.className = "card-title";
    title.textContent = item.title || "Untitled anime";
    const meta = document.createElement("p");
    meta.className = "card-meta";
    meta.textContent = metadata(item) || item.status || "Anime";
    const score = document.createElement("p");
    score.className = "card-score";
    score.textContent = formatScore(item.score || item.status);
    const actions = document.createElement("div");
    actions.className = "card-actions";
    const open = document.createElement("button");
    open.type = "button";
    open.className = "primary-button";
    open.setAttribute("aria-label", `Open ${item.title || "anime"} in ani-cli`);
    open.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m8 5 11 7-11 7z"/></svg><span>Open in ani-cli</span>';
    open.addEventListener("click", () => api?.launchTitle(String(item.title || "")));
    const details = addButton("Details", "secondary-button", () => {
      const safeItem = {
        id: Number(item.id) || 0,
        title: String(item.title || "Untitled anime"),
        nativeTitle: String(item.nativeTitle || ""),
        imageUrl: safeImageUrl(item.imageUrl),
        year: Number(item.year) || 0,
        type: String(item.type || ""),
        episodes: Number(item.episodes) || 0,
        score: Number(item.score) || 0,
        status: String(item.status || ""),
        synopsis: String(item.synopsis || ""),
        genres: Array.isArray(item.genres) ? item.genres.map(String) : []
      };
      detailReturnId = String(safeItem.id);
      api?.openDetails(safeItem);
    }, `View details for ${item.title || "anime"}`);
    details.dataset.animeId = String(Number(item.id) || 0);
    actions.append(open, details);
    copy.append(title, meta, score, actions);
    card.append(image, copy);
    return card;
  }

  function renderDiscover() {
    const discover = state.search || {};
    const results = Array.isArray(discover.results) ? discover.results : [];
    const status = String(discover.state || "idle");
    const query = String(discover.submittedQuery || "");
    const loading = status === "loading" || status === "waiting";

    ui.searchCount.textContent = status === "ready" || status === "empty" ? String(results.length) : "";
    ui.searchSummary.textContent = status === "ready" ? `Results for “${query}”`
      : status === "empty" ? `No matches for “${query}”` : status === "error" ? "Search unavailable" : "Search AniList";
    clear(ui.searchResults);
    ui.searchResults.hidden = results.length === 0;
    if (results.length > 0) results.forEach((item, index) => ui.searchResults.appendChild(makeAnimeCard(item, index)));
    ui.searchMore.hidden = !discover.hasNextPage;
    ui.searchMore.disabled = Boolean(discover.loadingMore);
    ui.searchMore.textContent = discover.loadingMore ? "Loading more…" : "Load more results";
    if (results.length > 0) {
      ui.searchState.hidden = true;
    } else {
      const message = stateView(
        status,
        discover.error,
        "Search anime on AniList",
        "Enter a title to see live matches and episode details.",
        "No anime found",
        "Try another title or spelling.",
        loading ? "Searching AniList…" : "Search anime on AniList",
        loading ? "Looking up titles and details." : "Enter a title to see live matches and episode details."
      );
      if (status === "error") message.title = "Search unavailable";
      renderState(ui.searchState, message.title, message.detail, message.mode, message.icon);
    }
    if (loading) ui.searchMore.disabled = true;
  }

  function renderDayPicker() {
    const schedule = state.schedule || {};
    const weekdays = Array.isArray(schedule.weekdays) ? schedule.weekdays : [];
    clear(ui.dayPicker);
    for (const day of weekdays) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "day-button";
      button.textContent = day.shortName || String(day.name || "").slice(0, 3);
      button.setAttribute("aria-label", `Show ${day.name || day.key} schedule`);
      button.setAttribute("aria-pressed", String(day.key === schedule.selectedDay));
      button.addEventListener("click", () => api?.selectDay(String(day.key || "")));
      ui.dayPicker.appendChild(button);
    }
  }

  function makeScheduleCard(item) {
    const card = document.createElement("article");
    card.className = "anime-card schedule-card";
    card.appendChild(makePoster(item.imageUrl, item.title));
    const copy = document.createElement("div");
    copy.className = "schedule-copy";
    const title = document.createElement("h3");
    title.className = "card-title";
    title.textContent = item.title || "Untitled anime";
    const meta = document.createElement("p");
    meta.className = "card-meta";
    meta.textContent = item.nativeTitle || item.type || "Currently airing";
    const time = document.createElement("p");
    time.className = "schedule-time";
    time.textContent = item.broadcastTime || "Time not listed";
    const open = document.createElement("button");
    open.type = "button";
    open.className = "schedule-action";
    open.textContent = "Open in ani-cli";
    open.setAttribute("aria-label", `Open ${item.title || "anime"} in ani-cli, airing ${item.broadcastTime || "time not listed"}`);
    open.addEventListener("click", () => api?.launchTitle(String(item.title || "")));
    copy.append(title, meta, time, open);
    card.appendChild(copy);
    return card;
  }

  function renderSchedule() {
    const schedule = state.schedule || {};
    const entries = Array.isArray(schedule.entries) ? schedule.entries : [];
    const status = String(schedule.state || "idle");
    const selectedDay = (schedule.weekdays || []).find(day => day.key === schedule.selectedDay);
    ui.scheduleTitle.textContent = selectedDay?.name || "This week";
    ui.scheduleCount.textContent = status === "ready" || status === "empty" ? String(entries.length) : "";
    renderDayPicker();
    clear(ui.scheduleResults);
    ui.scheduleResults.hidden = entries.length === 0;
    if (entries.length > 0) entries.forEach(item => ui.scheduleResults.appendChild(makeScheduleCard(item)));
    ui.scheduleMore.hidden = !schedule.hasNextPage;
    ui.scheduleMore.disabled = Boolean(schedule.loadingMore);
    ui.scheduleMore.textContent = schedule.loadingMore ? "Loading more…" : "Load more anime";
    if (entries.length > 0) {
      ui.scheduleState.hidden = true;
    } else {
      const label = selectedDay?.name || "this day";
      const message = stateView(
        status,
        schedule.error,
        "Choose a weekday to see its airing schedule.",
        "Airing times use your local time zone.",
        `No anime listed for ${label}`,
        "Try another day or refresh the schedule.",
        `Loading ${label} schedule…`,
        "Checking AniList for upcoming episodes."
      );
      if (status === "error") message.title = "Schedule unavailable";
      renderState(ui.scheduleState, message.title, message.detail, message.mode, message.icon);
    }
    if (status === "ready" && entries.length === 0) ui.scheduleState.hidden = false;
    if (status === "loading" || status === "waiting") ui.scheduleMore.disabled = true;
  }

  function normalizedTitle(value) {
    return String(value || "").normalize("NFKC").toLowerCase()
      .replace(/[^a-z0-9\u3040-\u30ff\u3400-\u9fff]+/g, " ").trim();
  }

  function makeHistoryCard(item, artwork) {
    const card = document.createElement("article");
    card.className = "anime-card history-card";
    const cache = artwork || {};
    const cached = cache[normalizedTitle(item.title)] || {};
    card.appendChild(makePoster(cached.imageUrl || "", item.title));
    const copy = document.createElement("div");
    copy.className = "history-copy";
    const title = document.createElement("h3");
    title.className = "card-title";
    title.textContent = item.title || "Untitled anime";
    const episode = document.createElement("p");
    episode.className = "history-episode";
    episode.textContent = `Episode ${item.episode || "—"} · saved by ani-cli`;
    copy.append(title, episode);
    const open = addButton("Open", "primary-button history-open", () => api?.launchTitle(String(item.title || "")), `Open ${item.title || "anime"} in ani-cli`);
    card.append(copy, open);
    return card;
  }

  function renderHistory() {
    const history = state.history || {};
    const entries = Array.isArray(history.entries) ? history.entries : [];
    const status = String(history.state || "loading");
    ui.historyCount.textContent = status === "ready" || status === "empty" || status === "missing" ? String(entries.length) : "";
    ui.continueHistory.disabled = status !== "ready";
    clear(ui.historyResults);
    ui.historyResults.hidden = entries.length === 0;
    if (entries.length > 0) entries.forEach(item => ui.historyResults.appendChild(makeHistoryCard(item, history.artwork)));
    if (entries.length > 0) {
      ui.historyState.hidden = true;
    } else {
      const message = status === "loading"
        ? { title: "Reading ani-cli history…", detail: "Checking the local ani-cli state file.", mode: "loading", icon: icons.history }
        : status === "error"
          ? { title: "History unavailable", detail: history.error || "Could not read ani-cli history.", mode: "error", icon: icons.error }
          : status === "missing"
            ? { title: "No ani-cli history yet", detail: "Watch an episode with ani-cli and saved progress will appear here.", mode: "idle", icon: icons.history }
            : { title: "Nothing saved yet", detail: "ani-cli has not saved any episode entries yet.", mode: "idle", icon: icons.history };
      renderState(ui.historyState, message.title, message.detail, message.mode, message.icon);
    }
  }

  function renderDetail() {
    const anime = state.selectedAnime;
    if (!anime) return;
    const safeUrl = safeImageUrl(anime.imageUrl);
    if (safeUrl) {
      ui.detailPoster.src = safeUrl;
      ui.detailPoster.alt = `Poster for ${anime.title || "anime"}`;
      ui.detailPoster.hidden = false;
      ui.detailPoster.onerror = () => { ui.detailPoster.hidden = true; };
    } else {
      ui.detailPoster.removeAttribute("src");
      ui.detailPoster.alt = "";
      ui.detailPoster.hidden = true;
    }
    const meta = [anime.type || "", anime.year || "", anime.status || ""].filter(Boolean).join(" · ");
    const facts = [Number(anime.episodes) > 0 ? `${anime.episodes} episodes` : "", Number(anime.score) > 0 ? `★ ${Number(anime.score).toFixed(1)} / 10` : ""]
      .filter(Boolean).join(" · ");
    ui.detailMeta.textContent = meta || "Anime details from AniList";
    ui.detailTitle.textContent = anime.title || "Anime details";
    ui.detailFacts.textContent = facts;
    ui.detailGenres.textContent = Array.isArray(anime.genres) && anime.genres.length ? anime.genres.join(" · ") : "Anime details from AniList";
    ui.detailSynopsis.textContent = anime.synopsis || "No synopsis is available for this title.";
    ui.detailLaunch.setAttribute("aria-label", `Search ${anime.title || "anime"} in ani-cli`);
  }

  function setTab(index) {
    const safeIndex = Math.max(0, Math.min(2, Number(index) || 0));
    document.documentElement.style.setProperty("--tab-index", String(safeIndex));
    ui.tabs.forEach((tab, current) => {
      const active = current === safeIndex;
      tab.classList.toggle("active", active);
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    const detail = Boolean(state.detailOpen && state.selectedAnime);
    el("panel-detail").hidden = !detail;
    el("panel-discover").hidden = detail || safeIndex !== 0;
    el("panel-airing").hidden = detail || safeIndex !== 1;
    el("panel-history").hidden = detail || safeIndex !== 2;
    if (detail) {
      ui.subtitle.textContent = "A closer look at this story";
      renderDetail();
    } else {
      ui.subtitle.textContent = safeIndex === 0 ? "Find a story for tonight" : safeIndex === 1 ? "Airing by weekday" : "Your ani-cli watch history";
    }
  }

  function applyTheme() {
    const theme = state.theme || {};
    const variables = {
      "--panel": theme.panel,
      "--surface": theme.surface,
      "--card": theme.card,
      "--hover": theme.hover,
      "--outline": theme.outline,
      "--text": theme.text,
      "--secondary": theme.secondary,
      "--primary": theme.primary,
      "--mint": theme.mint,
      "--error": theme.error,
      "--error-container": theme.errorContainer,
      "--on-primary": theme.onPrimary
    };
    for (const [name, value] of Object.entries(variables)) {
      if (typeof value === "string" && value) document.documentElement.style.setProperty(name, value);
    }
    if (theme.fontMain) {
      const safeFont = String(theme.fontMain).replace(/["\\\n\r]/g, " ").trim();
      document.documentElement.style.setProperty("--font-main", `"${safeFont}", sans-serif`);
    }
    ui.app.classList.toggle("reduce-motion", Boolean(theme.reducedMotion));
  }

  function renderFooter() {
    const launch = state.launch || {};
    ui.footerStatus.textContent = String(launch.status || "");
    ui.footerStatus.classList.toggle("error", Boolean(launch.failed));
    const tab = Number(state.currentTab) || 0;
    const source = tab === 0 ? state.search || {} : tab === 1 ? state.schedule || {} : state.history || {};
    const count = tab === 0 ? (source.results || []).length : (source.entries || []).length;
    ui.footerCount.textContent = source.state === "ready" || source.state === "empty" || source.state === "missing" ? `${count} ${tab === 0 ? "titles" : tab === 1 ? "airing" : "saved"}` : "";
  }

  function render() {
    const wasDetailOpen = Boolean(state.detailOpen);
    state = api?.state || {};
    applyTheme();
    setTab(Number(state.currentTab) || 0);
    renderDiscover();
    renderSchedule();
    renderHistory();
    renderFooter();
    if (state.detailOpen && !wasDetailOpen) {
      ui.detailBack.focus();
    } else if (!state.detailOpen && wasDetailOpen) {
      const trigger = [...ui.searchResults.querySelectorAll("[data-anime-id]")]
        .find(button => button.dataset.animeId === detailReturnId);
      (trigger || ui.tabs[0]).focus();
      detailReturnId = "";
    }
  }

  ui.searchForm.addEventListener("submit", (event) => {
    event.preventDefault();
    api?.search(ui.searchInput.value.trim());
  });
  ui.refresh.addEventListener("click", () => api?.refresh());
  ui.tabs.forEach((tab) => tab.addEventListener("click", () => api?.selectTab(Number(tab.dataset.tab))));
  ui.searchMore.addEventListener("click", () => api?.loadMoreSearch());
  ui.scheduleMore.addEventListener("click", () => api?.loadMoreSchedule());
  ui.continueHistory.addEventListener("click", () => api?.continueHistory());
  ui.detailBack.addEventListener("click", () => api?.closeDetails());
  ui.detailLaunch.addEventListener("click", () => api?.launchTitle(String(state.selectedAnime?.title || "")));
  ui.anilistLink.addEventListener("click", () => api?.openAniList());

  ui.tabs.forEach((tab, index) => tab.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const delta = event.key === "ArrowRight" ? 1 : -1;
    const next = (index + delta + ui.tabs.length) % ui.tabs.length;
    ui.tabs[next].focus();
    ui.tabs[next].click();
  }));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && state.detailOpen) api?.closeDetails();
  });

  function connectBridge() {
    if (typeof qt === "undefined" || !qt.webChannelTransport || typeof QWebChannel === "undefined") {
      renderState(ui.searchState, "AniTrack connection unavailable", "Reload the widget to reconnect to Quickshell.", "error", icons.error);
      return;
    }
    new QWebChannel(qt.webChannelTransport, (channel) => {
      api = channel.objects.anitrack;
      if (!api) {
        renderState(ui.searchState, "AniTrack connection unavailable", "The QML bridge was not registered.", "error", icons.error);
        return;
      }
      api.stateChanged.connect(render);
      render();
      api.ready();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", connectBridge, { once: true });
  else connectBridge();
})();
