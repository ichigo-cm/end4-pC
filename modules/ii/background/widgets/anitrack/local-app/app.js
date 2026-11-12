(() => {
  "use strict";

  const data = window.AniTrackPreview;
  const entries = Array.isArray(data?.entries) ? data.entries : [];
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const heroImage = $("#hero-image");
  const heroTitle = $("#hero-title");
  const heroMeta = $("#hero-meta");
  const heroGenres = $("#hero-genres");
  const heroIndex = $("#hero-index");
  const dots = $("#hero-dots");
  const rail = $("#trending-rail");
  const dialog = $("#detail-dialog");
  const toast = $("#toast");
  const input = $("#search-input");
  const weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  let activeHero = 0;
  let activeEntry = null;
  let toastTimer = 0;

  function safeArtworkUrl(value) {
    try {
      const url = new URL(String(value || ""));
      return url.protocol === "https:" && url.hostname === "s4.anilist.co" ? url.href : "";
    } catch (_) {
      return "";
    }
  }

  function scoreText(value) {
    const score = Number(value) || 0;
    return score > 0 ? `${(score / 10).toFixed(1)} AniList score` : "Score unavailable";
  }

  function metadata(item) {
    const parts = [item.format || "Anime", item.year || ""];
    if (Number(item.episodes) > 0) parts.push(`${item.episodes} episodes`);
    return parts.filter(Boolean).join(" · ");
  }

  function setHero(index) {
    if (!entries.length) return;
    activeHero = (index + entries.length) % entries.length;
    const item = entries[activeHero];
    const image = safeArtworkUrl(item.bannerImage) || safeArtworkUrl(item.coverImage);
    heroImage.style.backgroundImage = image
      ? `linear-gradient(90deg, rgba(12, 14, 17, .96) 0%, rgba(12, 14, 17, .78) 37%, rgba(12, 14, 17, .08) 100%), linear-gradient(0deg, rgba(12, 14, 17, .88), transparent 64%), url("${image}")`
      : "linear-gradient(110deg, #191c21, #343941)";
    heroTitle.textContent = item.title || "Anime";
    heroMeta.textContent = `${metadata(item)}  ·  ${scoreText(item.score)}`;
    heroGenres.textContent = (item.genres || []).slice(0, 4).join("  /  ");
    heroIndex.innerHTML = `${String(activeHero + 1).padStart(2, "0")} <span>/ ${String(entries.length).padStart(2, "0")}</span>`;
    $$(".hero-dot", dots).forEach((dot, dotIndex) => {
      dot.classList.toggle("is-active", dotIndex === activeHero);
      dot.setAttribute("aria-pressed", String(dotIndex === activeHero));
    });
    activeEntry = item;
  }

  function posterCard(item, index) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "poster-card";
    button.setAttribute("aria-label", `View details for ${item.title || "anime"}`);

    const art = document.createElement("span");
    art.className = "poster-art";
    const imageUrl = safeArtworkUrl(item.coverImage);
    if (imageUrl) {
      const image = document.createElement("img");
      image.src = imageUrl;
      image.alt = "";
      image.loading = index > 2 ? "lazy" : "eager";
      image.decoding = "async";
      image.referrerPolicy = "no-referrer";
      image.addEventListener("error", () => image.remove(), { once: true });
      art.appendChild(image);
    } else {
      art.classList.add("poster-fallback");
      art.textContent = "A";
    }

    const copy = document.createElement("span");
    copy.className = "poster-copy";
    const title = document.createElement("span");
    title.className = "poster-title";
    title.textContent = item.title || "Untitled anime";
    const details = document.createElement("span");
    details.className = "poster-meta";
    details.textContent = `${item.format || "Anime"}  ·  ${scoreText(item.score)}`;
    copy.append(title, details);
    button.append(art, copy);
    button.addEventListener("click", () => openDetails(item, button));
    return button;
  }

  function renderRail(items, query = "") {
    rail.replaceChildren();
    if (!items.length) {
      const empty = document.createElement("p");
      empty.className = "rail-empty";
      empty.textContent = query ? `No preview titles match “${query}”. Try another search.` : "No AniList titles are available in this preview.";
      rail.appendChild(empty);
      return;
    }
    items.forEach((item, index) => rail.appendChild(posterCard(item, index)));
  }

  function fillDetails(item) {
    const image = safeArtworkUrl(item.bannerImage) || safeArtworkUrl(item.coverImage);
    $("#dialog-art").style.backgroundImage = image
      ? `linear-gradient(0deg, rgba(15,17,20,.68), transparent 72%), url("${image}")`
      : "linear-gradient(110deg, #20242a, #454a53)";
    $("#dialog-title").textContent = item.title || "Anime details";
    $("#dialog-meta").textContent = `${metadata(item)}  ·  ${scoreText(item.score)}`;
    $("#dialog-genres").textContent = (item.genres || []).join("  /  ") || "Anime details from AniList";
  }

  function openDetails(item, trigger) {
    activeEntry = item;
    dialog.dataset.returnFocus = trigger?.id || "";
    fillDetails(item);
    if (!dialog.open) dialog.showModal();
    $("#dialog-close").focus();
  }

  function closeDetails() {
    if (dialog.open) dialog.close();
  }

  function showToast(message) {
    window.clearTimeout(toastTimer);
    toast.textContent = message;
    toast.hidden = false;
    toast.classList.remove("is-visible");
    requestAnimationFrame(() => toast.classList.add("is-visible"));
    toastTimer = window.setTimeout(() => {
      toast.classList.remove("is-visible");
      window.setTimeout(() => { toast.hidden = true; }, 180);
    }, 3100);
  }

  function setPage(name) {
    const page = ["discover", "airing", "history"].includes(name) ? name : "discover";
    $$(".page").forEach((panel) => {
      const active = panel.id === `page-${page}`;
      panel.hidden = !active;
      panel.classList.toggle("is-visible", active);
    });
    $$(".nav-link").forEach((button) => {
      const active = button.dataset.page === page;
      button.classList.toggle("is-active", active);
      if (active) button.setAttribute("aria-current", "page");
      else button.removeAttribute("aria-current");
    });
    if (page !== "discover") $("#main").focus({ preventScroll: true });
  }

  function renderWeekdays() {
    const row = $("#weekday-row");
    const today = (new Date().getDay() + 6) % 7;
    row.replaceChildren();
    weekdays.forEach((day, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "weekday-button";
      button.textContent = day.slice(0, 3);
      button.setAttribute("aria-label", `Show ${day} schedule`);
      button.setAttribute("aria-pressed", String(index === today));
      button.addEventListener("click", () => {
        $$(".weekday-button", row).forEach((other) => other.setAttribute("aria-pressed", String(other === button)));
        $("#schedule-day-title").textContent = `${day} lineup`;
      });
      row.appendChild(button);
    });
    $("#schedule-day-title").textContent = `${weekdays[today]} lineup`;
  }

  $("#hero-launch").addEventListener("click", () => showToast("Preview only — ani-cli will connect in the local integration build."));
  $("#dialog-launch").addEventListener("click", () => showToast("Preview only — ani-cli will connect in the local integration build."));
  $$("[data-preview-action]").forEach((button) => button.addEventListener("click", () => {
    showToast("This layout is ready; local history and launch actions are next." );
  }));
  $("#hero-details").addEventListener("click", () => activeEntry && openDetails(activeEntry, $("#hero-details")));
  $("#dialog-close").addEventListener("click", closeDetails);
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) closeDetails();
  });
  dialog.addEventListener("close", () => {
    const returnId = dialog.dataset.returnFocus;
    const target = returnId ? document.getElementById(returnId) : $("#hero-details");
    (target || $("#hero-details")).focus();
  });
  $("#hero-prev").addEventListener("click", () => setHero(activeHero - 1));
  $("#hero-next").addEventListener("click", () => setHero(activeHero + 1));
  $("#shelf-prev").addEventListener("click", () => rail.scrollBy({ left: -420, behavior: "smooth" }));
  $("#shelf-next").addEventListener("click", () => rail.scrollBy({ left: 420, behavior: "smooth" }));
  $$(".nav-link").forEach((button) => button.addEventListener("click", () => setPage(button.dataset.page)));
  $$("[data-open-page]").forEach((button) => button.addEventListener("click", () => setPage(button.dataset.openPage)));

  $("#search-form").addEventListener("submit", (event) => {
    event.preventDefault();
    const query = input.value.trim();
    const normalized = query.toLocaleLowerCase();
    const matches = normalized
      ? entries.filter((item) => item.title.toLocaleLowerCase().includes(normalized) || (item.genres || []).some((genre) => genre.toLocaleLowerCase().includes(normalized)))
      : entries;
    $("#trending-heading").textContent = query ? `Search results for “${query}”` : "Trending right now";
    renderRail(matches, query);
    setPage("discover");
  });
  input.addEventListener("input", () => {
    if (!input.value.trim()) {
      $("#trending-heading").textContent = "Trending right now";
      renderRail(entries);
    }
  });

  $("#accent-toggle").addEventListener("click", () => {
    const sage = document.body.classList.toggle("accent-sage");
    try { localStorage.setItem("anitrack-preview-accent", sage ? "sage" : "warm"); } catch (_) {}
    showToast(sage ? "Preview accent: soft sage" : "Preview accent: warm amber");
  });
  try {
    if (localStorage.getItem("anitrack-preview-accent") === "sage") document.body.classList.add("accent-sage");
  } catch (_) {}

  document.addEventListener("keydown", (event) => {
    if (event.key === "/" && !event.ctrlKey && !event.metaKey && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
      event.preventDefault();
      input.focus();
    }
    if (event.key === "Escape" && dialog.open) closeDetails();
  });

  const dotsFragment = document.createDocumentFragment();
  entries.forEach((item, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `hero-dot${index === 0 ? " is-active" : ""}`;
    button.setAttribute("aria-label", `Feature ${item.title || "anime"}`);
    button.setAttribute("aria-pressed", String(index === 0));
    button.addEventListener("click", () => setHero(index));
    dotsFragment.appendChild(button);
  });
  dots.appendChild(dotsFragment);
  setHero(0);
  renderRail(entries);
  renderWeekdays();
  $("#airing-rail").replaceChildren(...entries.slice(0, 5).map((item, index) => posterCard(item, index)));
})();
