# AniTrack web interface

The `webapp` folder contains the local HTML/CSS/JavaScript presentation for AniTrack. Quickshell hosts it in a `QtWebEngine` view, and a narrow `QtWebChannel` bridge forwards actions to the existing QML views. AniList networking, rate limiting, ani-cli history, and terminal launches remain owned by the current QML/Python code.

This deliberately does not run a Rust server. Rust is not needed to render the UI, and adding a long-lived local service would make installation, process ownership, and shutdown more complex without replacing existing backend work.

On Arch, install the optional modules with:

```sh
sudo pacman -S qt6-webengine qt6-webchannel
```

`qt6-webengine` is a large Chromium-based dependency; the Arch package metadata retrieved on 2026-11-12 listed 94.7 MB compressed and 283.4 MB installed. If the QML modules are absent, the loader keeps the current native QML interface visible. Restart Quickshell after installing the modules for QML import discovery to take effect.

The browser content is bundled locally. Its Content Security Policy blocks external scripts, stylesheets, and API connections; poster images may load over HTTPS from URLs supplied by the existing AniList-backed code. The HTML app does not keep a separate AniTrack palette: the QML host supplies the shell's live Material color roles (including the wallpaper-derived scheme), configured font, light/dark color scheme, and reduced-motion setting. Wallpaper/theme changes flow through to the web UI, which preserves keyboard navigation and only replaces the native presentation after the WebChannel has connected and rendered its first state.
