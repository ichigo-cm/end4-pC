#!/usr/bin/env python3
import json
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

LRC_LINE_TAG = re.compile(r"\[(\d+:\d{2}(?:\.\d+)?)\]")
LRC_INLINE_TAG = re.compile(r"<(\d+:\d{2}(?:\.\d+)?)>")


def _lrc_seconds(value: str) -> float:
    minutes, seconds = value.split(":", 1)
    return int(minutes) * 60 + float(seconds)


def _clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _parse_lrc(lrc_text: str) -> list:
    lines = []
    for raw in lrc_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        time_tags = list(LRC_LINE_TAG.finditer(raw))
        if not time_tags:
            continue

        try:
            line_times = [_lrc_seconds(tag.group(1)) for tag in time_tags]
        except (ValueError, TypeError):
            continue

        body = raw[time_tags[-1].end():]
        inline_tags = list(LRC_INLINE_TAG.finditer(body))
        cues = []
        if inline_tags:
            prefix = _clean_text(body[:inline_tags[0].start()])
            if prefix:
                cues.append({"time": line_times[0], "text": prefix})
            for index, tag in enumerate(inline_tags):
                end = inline_tags[index + 1].start() if index + 1 < len(inline_tags) else len(body)
                text = _clean_text(body[tag.end():end])
                if text:
                    cues.append({"time": _lrc_seconds(tag.group(1)), "text": text})
            text = _clean_text(LRC_INLINE_TAG.sub("", body))
        else:
            text = _clean_text(body)

        if not text:
            continue

        first_time = line_times[0]
        for line_time in line_times:
            line = {"time": line_time, "text": text}
            if cues:
                shift = line_time - first_time
                line["cues"] = [
                    {"time": cue["time"] + shift, "text": cue["text"]}
                    for cue in cues
                ]
            lines.append(line)

    return sorted(lines, key=lambda item: item["time"])


def _is_match(data: dict, title: str, artist: str) -> bool:
    if not data.get("syncedLyrics"):
        return False
    remote_title = (data.get("trackName") or "").lower()
    remote_artist = (data.get("artistName") or "").lower()
    requested_title = title.lower()
    requested_artist = artist.lower()
    title_match = (
        requested_title in remote_title
        or remote_title in requested_title
        or any(word in remote_title for word in requested_title.split() if len(word) > 3)
    )
    artist_match = (
        requested_artist in remote_artist
        or remote_artist in requested_artist
        or any(word in remote_artist for word in requested_artist.split() if len(word) > 3)
    )
    return title_match and artist_match


def fetch_lrclib(title: str, artist: str, duration: float) -> list:
    urls = [
        f"https://lrclib.net/api/get?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}&duration={int(duration)}",
        f"https://lrclib.net/api/search?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}",
        f"https://lrclib.net/api/search?q={urllib.parse.quote(title + ' ' + artist)}",
    ]
    for url in urls:
        try:
            with urllib.request.urlopen(url, timeout=15) as response:
                data = json.loads(response.read().decode())
            if isinstance(data, list):
                data = next((item for item in data if _is_match(item, title, artist)), None)
            if data and _is_match(data, title, artist):
                lines = _parse_lrc(data["syncedLyrics"])
                if lines:
                    return lines
        except Exception:
            continue
    return []


def _ttml_seconds(value: str) -> float:
    value = value.strip()
    if value.endswith("ms"):
        return float(value[:-2]) / 1000.0
    if value.endswith("s"):
        return float(value[:-1])
    if ":" not in value:
        return float(value)
    total = 0.0
    for part in value.split(":"):
        total = total * 60 + float(part)
    return total


def _resolve_ttml_time(value: str, parent_start: float) -> float:
    seconds = _ttml_seconds(value)
    # TTML offset expressions are relative to their parent; clock expressions
    # are commonly emitted as absolute timestamps by lyric providers. Use the
    # parent offset when the value is clearly an offset or precedes the line.
    if value.strip().endswith(("s", "ms")) or seconds + 0.05 < parent_start:
        return parent_start + seconds
    return seconds


def _local_name(element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _parse_ttml(ttml: str) -> list:
    document = ET.fromstring(ttml)
    lines = []
    for paragraph in document.iter():
        if _local_name(paragraph) != "p":
            continue
        begin = paragraph.get("begin")
        if begin is None:
            continue
        try:
            line_time = _ttml_seconds(begin)
        except (ValueError, TypeError):
            continue

        text = _clean_text("".join(paragraph.itertext()))
        if not text:
            continue

        cues = []
        for span in paragraph.iter():
            if span is paragraph or _local_name(span) != "span" or span.get("begin") is None:
                continue
            # Avoid counting a timed parent and its timed child twice.
            has_timed_child = any(
                child is not span
                and _local_name(child) == "span"
                and child.get("begin") is not None
                for child in span.iter()
            )
            if has_timed_child:
                continue
            cue_text = _clean_text("".join(span.itertext()))
            if not cue_text:
                continue
            try:
                cue_time = _resolve_ttml_time(span.get("begin"), line_time)
                cue_end = (
                    _resolve_ttml_time(span.get("end"), line_time)
                    if span.get("end") is not None
                    else None
                )
            except (ValueError, TypeError):
                continue
            cue = {"time": cue_time, "text": cue_text}
            if cue_end is not None and cue_end > cue_time:
                cue["end"] = cue_end
            cues.append(cue)

        line = {"time": line_time, "text": text}
        if cues:
            line["cues"] = sorted(cues, key=lambda item: item["time"])
        lines.append(line)

    return sorted(lines, key=lambda item: item["time"])


BOIDU_BASES = ["https://api.betterlyrics.org", "https://lyrics-api.boidu.dev"]


def fetch_boidu(title: str, artist: str, duration: float) -> list:
    query = f"/getLyrics?s={urllib.parse.quote(title)}&a={urllib.parse.quote(artist)}"
    if duration > 0:
        query += f"&d={int(duration)}"
    for base in BOIDU_BASES:
        try:
            request = urllib.request.Request(base + query, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(request, timeout=15) as response:
                data = json.loads(response.read().decode())
            lines = _parse_ttml(data.get("ttml") or "")
            if len(lines) >= 3:
                return lines
        except Exception:
            continue
    return []


def main():
    if len(sys.argv) < 4:
        print("no_info", flush=True)
        sys.exit(0)
    title = sys.argv[1]
    artist = sys.argv[2]
    duration = float(sys.argv[3])
    if not title or not artist:
        print("no_info", flush=True)
        sys.exit(0)
    lines = fetch_lrclib(title, artist, duration) or fetch_boidu(title, artist, duration)
    if not lines:
        print("not_found", flush=True)
        sys.exit(0)
    print(json.dumps({"status": "ok", "lines": lines}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
