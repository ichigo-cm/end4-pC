# Legacy embedded AniTrack frontend

This folder contains the earlier HTML/CSS/JavaScript experiment hosted through QtWebEngine and QtWebChannel. It is **not loaded by the current AniTrack widget**: the Loader is intentionally inactive so Chromium is never instantiated inside Quickshell. Do not install QtWebEngine for AniTrack.

The active design direction is the standalone local browser app in [`../local-app/`](../local-app/). Its current v0 is a visual preview with timestamped AniList data; the live AniList connection, loopback-only local service, local history reader, ani-cli launcher, and Quickshell launcher integration are still to be built. Until then, AniTrack continues to use its native QML interface, and the preview-only web app can be run separately as described in its README.

The local service must bind only to `127.0.0.1`, validate host and same-origin state-changing requests, expose only narrow operations, and reuse `ani_cli_bridge.py` rather than accepting arbitrary commands or shell strings. See the local app's design brief for preserved behavior and the planned interface.
