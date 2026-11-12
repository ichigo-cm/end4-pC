# AniTrack Local App — v0 preview

This is the first visual draft of the standalone AniTrack browser experience. It is separate from Quickshell's embedded QtWebEngine view. The page uses a timestamped real AniList GraphQL snapshot for titles, scores, and artwork, so it can be previewed without a backend. The artwork itself loads from AniList's HTTPS image CDN.

Search filters only the preview snapshot; featured navigation, the Airing/History pages, weekday controls, details, and accent switching are interactive. Buttons that would launch ani-cli or read local history explicitly say they are preview-only. The local service, live AniList integration, local history reader, and actual terminal launch are not part of this visual v0 yet.

To view it on a machine with the repository checked out, run:

```bash
bash modules/ii/background/widgets/anitrack/local-app/serve-preview.sh
```

Then open `http://127.0.0.1:4173` in a browser. The preview server binds to loopback only; use Ctrl+C in that terminal to stop it. Set `ANITRACK_PREVIEW_PORT` to use a different port.

The approved direction and protected behavior are recorded in [`design-brief.md`](design-brief.md). The next integration stage will use a loopback-only Python service and retain the existing safe `ani_cli_bridge.py` launch boundary. QtWebEngine is intentionally not used.
