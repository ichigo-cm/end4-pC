# AniTrack web interface

The `webapp` folder contains the local HTML/CSS/JavaScript presentation for AniTrack. Quickshell hosts it in a `QtWebEngine` view, and a narrow `QtWebChannel` bridge forwards actions to the existing QML views. AniList networking, rate limiting, ani-cli history, and terminal launches remain owned by the current QML/Python code.

This deliberately does not run a Rust server. Rust is not needed to render the UI, and adding a long-lived local service would make installation, process ownership, and shutdown more complex without replacing existing backend work.

On Arch, install the optional modules with:

```sh
sudo pacman -Syu qt6-webengine qt6-webchannel
```

Use the full `-Syu` upgrade to keep the Arch system synchronized. QtWebEngine has independent version numbering, so its package version may differ from `qt6-base`; that difference alone does not indicate an incompatibility. `qt6-webengine` is a large Chromium-based dependency; the Arch package metadata retrieved on 2026-11-12 listed 94.7 MB compressed and 283.4 MB installed. The host checks for a non-empty Qt application argument list before creating WebEngine: QtWebEngine's Chromium bootstrap needs the program-name argument, while some Quickshell builds create `QGuiApplication` with `argc=0`. In that case, AniTrack keeps its native QML interface active instead of crashing. A Quickshell runtime fix that passes at least `argv[0]` is required to use the HTML layer. Restart Quickshell after installing the modules or updating the runtime.

The browser content is bundled locally. Its Content Security Policy blocks external scripts, stylesheets, and API connections; poster images may load over HTTPS from URLs supplied by the existing AniList-backed code. The HTML app does not keep a separate AniTrack palette: the QML host supplies the shell's live Material color roles (including the wallpaper-derived scheme), configured font, light/dark color scheme, and reduced-motion setting. Wallpaper/theme changes flow through to the web UI, which preserves keyboard navigation and only replaces the native presentation after the WebChannel has connected and rendered its first state.
