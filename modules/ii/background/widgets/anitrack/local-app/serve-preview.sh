#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
port="${ANITRACK_PREVIEW_PORT:-4173}"
printf 'AniTrack design preview: http://127.0.0.1:%s\n' "$port"
printf 'Bound to 127.0.0.1 only. Press Ctrl+C to stop.\n'
exec python3 -m http.server "$port" --bind 127.0.0.1 --directory "$script_dir"
