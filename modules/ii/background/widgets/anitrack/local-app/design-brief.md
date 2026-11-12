# AniTrack Local App — v0 Design Brief

## Redesign plan

**Mode:** Presentation overhaul; preserve AniTrack's data and launch contracts.

**Preserve:** AniTrack identity; Discover, Airing, and My History information architecture; AniList search/schedule data; local ani-cli history format; the existing argument-safe ani-cli launcher; Quickshell Material colors and reduced-motion preference when launched from the shell.

**Improve:** Expand from the fixed 420×540 widget into a responsive desktop experience. Lead with real anime artwork, clear browsing hierarchy, larger poster cards, and spacious details. Keep search, airing, history, and launch affordances easy to reach.

**Remove:** QtWebEngine/WebChannel as the presentation layer for this app. The user's Quickshell runtime crashed during Chromium startup; the local browser app should not instantiate WebEngine.

**Protected contracts:** ani-cli launch continues through `ani_cli_bridge.py`, with no shell interpolation. The app service will bind to loopback only, validate same-origin requests, and never expose launch actions to the network. AniList rate-limit handling and local-time schedule semantics must be preserved.

## Design Read

- **Artifact:** Responsive local browser app launched from the Quickshell AniTrack widget.
- **Audience:** The shell owner browsing anime and continuing ani-cli viewing history.
- **Visual language:** Cinematic anime-catalog browsing: dark editorial canvas, one art-led feature, horizontal poster shelves, restrained Material accent. Crunchyroll informs browsing rhythm only; AniTrack keeps its own wordmark, content source, and visual identity.
- **Narrative role:** Discover is the landing experience; Airing and My History are task-focused destinations; details are a focused secondary view.
- **Viewing distance:** Laptop/desktop at arm's length, with responsive narrowing down to a small browser window.
- **Visual temperature:** Nighttime, energetic through artwork rather than neon effects.
- **Capacity check:** At a 1440×900 desktop viewport, the hero and first poster shelf should be visible together. At narrower widths, the hero contracts and shelves become horizontal scroll regions; navigation remains visible.
- **Dials:** Variance 5/10 (familiar browsing layout with an art-led hero); motion 3/10 (short state feedback only); density 5/10 (one hero plus grouped shelves); asset dependence 8/10 (real AniList banners/posters); AniTrack identity fidelity 6/10 (use reference cues without copying Crunchyroll identity).

## Design decisions

- **Palette:** Ink `#0D0F12`, surface `#17191D`, raised surface `#202329`, primary text `#F3F4F6`, secondary text `#A7ABB3`. Accent is a CSS token supplied by Quickshell's wallpaper-derived Material `colPrimary`; a warm amber fallback is used in standalone preview mode. Avoid a separate purple theme and avoid copied Crunchyroll brand assets.
- **Typography:** Use the configured shell font when launched from Quickshell; use the local system sans-serif stack in standalone preview mode. Large bold feature title, medium-weight section titles, comfortable 16px body text.
- **Spacing:** 4px base rhythm; practical steps 8, 12, 16, 24, 32, 48px.
- **Shape:** 20px hero, 14–18px media surfaces, fully rounded small controls. No ornamental floating status chips.
- **Elevation:** Prefer contrast and artwork scrims over card shadows; reserve a soft shadow for the hero/modal only.
- **Motion:** 160–220ms, ease-out, transform/opacity only; no parallax or autoplay. Respect both `prefers-reduced-motion` and the shell's setting.
- **Imagery:** AniList API banners and cover images in the preview; no Crunchyroll logo, screenshots, or show art embedded as app assets.
- **Interaction:** Native buttons and labelled search, visible keyboard focus, Escape closes details, explicit loading/empty/error states, and clear preview-only launch messaging until the localhost bridge is integrated.

## v0 boundary

This v0 validates the visual language and principal navigation with a timestamped AniList data snapshot. It is not yet connected to live search, local ani-cli history, or terminal launching; those are explicitly marked as next integration work rather than simulated as live features.
