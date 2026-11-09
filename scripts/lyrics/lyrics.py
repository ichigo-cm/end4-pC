#!/usr/bin/env python3
"""Fetch synchronized lyrics and normalize optional lyric presentation metadata."""

import json
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

LRC_LINE_TAG = re.compile(r"\[(\d+:\d{2}(?:\.\d+)?)\]")
LRC_INLINE_TAG = re.compile(r"<(\d+:\d{2}(?:\.\d+)?)>")
VOCAL_SEGMENT = re.compile(r"[\(（]([^()（）]{1,120})[\)）]")


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


def _ttml_vocal_kind(span) -> str:
    metadata = " ".join(
        str(span.get(name, ""))
        for name in ("role", "class", "type", "agent")
    ).lower()
    if any(word in metadata for word in ("background", "backing", "bg-vocal", "bg_vocal")):
        return "background"
    if any(word in metadata for word in ("side", "ad-lib", "adlib", "harmony")):
        return "side"
    return ""


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

        vocal_layers = []
        for span in paragraph.iter():
            if span is paragraph or _local_name(span) != "span":
                continue
            kind = _ttml_vocal_kind(span)
            if not kind:
                continue
            vocal_text = _clean_text("".join(span.itertext()))
            if not vocal_text:
                continue
            layer = {"type": kind, "text": vocal_text, "time": line_time}
            try:
                if span.get("begin") is not None:
                    layer["time"] = _resolve_ttml_time(span.get("begin"), line_time)
                if span.get("end") is not None:
                    end_time = _resolve_ttml_time(span.get("end"), line_time)
                    if end_time > layer["time"]:
                        layer["end"] = end_time
            except (ValueError, TypeError):
                pass
            vocal_layers.append(layer)

        raw_text = "".join(paragraph.itertext())
        full_text = _clean_text(raw_text)
        for layer in vocal_layers:
            raw_text = raw_text.replace(layer["text"], "", 1)
        text = _clean_text(raw_text)

        cues = []
        for span in paragraph.iter():
            if span is paragraph or _local_name(span) != "span" or span.get("begin") is None:
                continue
            if _ttml_vocal_kind(span):
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

        if not text and not vocal_layers:
            continue
        full_cues = [dict(cue) for cue in cues]
        for layer in vocal_layers:
            vocal_cue = {"time": layer["time"], "text": layer["text"]}
            if layer.get("end") is not None:
                vocal_cue["end"] = layer["end"]
            full_cues.append(vocal_cue)
        line = {
            "time": line_time,
            "text": text,
            "fullText": full_text,
            "vocalLayers": vocal_layers,
            "fullCues": sorted(full_cues, key=lambda item: item["time"]),
        }
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


def _split_vocals(text: str):
    layers = []

    def replace(match):
        value = _clean_text(match.group(1))
        if not value:
            return " "
        lowered = value.lower()
        kind = "side" if lowered.startswith(("side:", "ad-lib:", "adlib:")) else "background"
        if kind == "side":
            value = _clean_text(value.split(":", 1)[1])
        layers.append({"type": kind, "text": value})
        return " "

    main_text = _clean_text(VOCAL_SEGMENT.sub(replace, text))
    return main_text, layers


def _has_romanizable_script(text: str) -> bool:
    return any(
        0x3040 <= ord(char) <= 0x30FF  # Hiragana/Katakana
        or 0x3400 <= ord(char) <= 0x9FFF  # Han
        or 0xAC00 <= ord(char) <= 0xD7AF  # Hangul syllables
        for char in text
    )


_KANA = {
    "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
    "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
    "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
    "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
    "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
    "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu", "よ": "yo",
    "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
    "わ": "wa", "ゐ": "i", "ゑ": "e", "を": "o", "ん": "n",
    "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
    "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
    "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
    "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
    "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
    "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa", "ゔ": "vu",
}
_SMALL_Y = {"ゃ": "ya", "ゅ": "yu", "ょ": "yo"}


def _romanize_kana(text: str) -> str:
    output = []
    index = 0
    while index < len(text):
        char = text[index]
        # Most full-width katakana have a corresponding hiragana 0x60 codepoints earlier.
        kana = chr(ord(char) - 0x60) if "ァ" <= char <= "ヶ" else char
        if kana == "っ":
            next_index = index + 1
            next_kana = text[next_index] if next_index < len(text) else ""
            next_kana = chr(ord(next_kana) - 0x60) if "ァ" <= next_kana <= "ヶ" else next_kana
            next_romaji = _KANA.get(next_kana, "")
            output.append(next_romaji[0] if next_romaji else "っ")
            index += 1
            continue
        if char == "ー":
            previous = next((c for c in reversed("".join(output)) if c in "aeiou"), "")
            output.append(previous or "ー")
            index += 1
            continue
        romaji = _KANA.get(kana)
        if romaji is None:
            output.append(char)
            index += 1
            continue
        if index + 1 < len(text):
            next_char = text[index + 1]
            next_kana = chr(ord(next_char) - 0x60) if "ァ" <= next_char <= "ヶ" else next_char
            if next_kana in _SMALL_Y and romaji.endswith("i"):
                output.append(romaji[:-1] + _SMALL_Y[next_kana])
                index += 2
                continue
        output.append(romaji)
        index += 1
    return "".join(output)


def _romanize_hangul(text: str) -> str:
    initials = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
    vowels = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
    finals = ["", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "p", "l", "l", "l", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"]
    result = []
    for char in text:
        code = ord(char) - 0xAC00
        if not 0 <= code < 11172:
            result.append(char)
            continue
        initial = code // 588
        vowel = (code % 588) // 28
        final = code % 28
        result.append(initials[initial] + vowels[vowel] + finals[final])
    return "".join(result)


def _fallback_romanize_text(text: str) -> str:
    # The fallback is complete for Hangul syllable decomposition and kana, but
    # deliberately refuses to claim a complete Chinese/kanji reading without a
    # local dictionary-backed transliterator such as ICU's uconv.
    if any(0x3400 <= ord(char) <= 0x9FFF for char in text):
        return ""
    if any(0xAC00 <= ord(char) <= 0xD7AF for char in text):
        return _clean_text(_romanize_hangul(text))
    if any(0x3040 <= ord(char) <= 0x30FF for char in text):
        return _clean_text(_romanize_kana(text))
    return ""


def _romanize_text(text: str) -> str:
    """Use local ICU transliteration when available, with kana/Hangul fallback."""
    if not _has_romanizable_script(text):
        return ""
    uconv = shutil.which("uconv")
    if uconv:
        try:
            result = subprocess.run(
                [uconv, "-x", "Any-Latin"],
                input=text,
                text=True,
                capture_output=True,
                timeout=3,
                check=False,
            )
            converted = _clean_text(result.stdout)
            if result.returncode == 0 and converted and converted != _clean_text(text):
                return converted
        except (OSError, subprocess.SubprocessError):
            pass
    return _fallback_romanize_text(text)


def _romanize_texts(texts: list) -> list:
    """Transliterate many lyric lines in one local ICU process when possible."""
    results = [""] * len(texts)
    indices = [index for index, text in enumerate(texts) if _has_romanizable_script(text)]
    if not indices:
        return results

    uconv = shutil.which("uconv")
    if uconv:
        try:
            source_lines = [str(texts[index]) for index in indices]
            converted = subprocess.run(
                [uconv, "-x", "Any-Latin"],
                input="\n".join(source_lines),
                text=True,
                capture_output=True,
                timeout=3,
                check=False,
            )
            output_lines = converted.stdout.splitlines()
            if converted.returncode == 0 and len(output_lines) == len(indices):
                for index, source, output in zip(indices, source_lines, output_lines):
                    value = _clean_text(output)
                    results[index] = value if value and value != _clean_text(source) else _fallback_romanize_text(source)
                return results
        except (OSError, subprocess.SubprocessError):
            pass

    for index in indices:
        results[index] = _fallback_romanize_text(str(texts[index]))
    return results


def _enrich_lines(lines: list) -> list:
    enriched = []
    for source_line in lines:
        line = dict(source_line)
        line_time = float(line.get("time", 0))
        full_text = str(line.get("fullText", line.get("text", "")))
        full_cues = [dict(cue) for cue in line.get("fullCues", line.get("cues", []))]
        line_text, inline_vocals = _split_vocals(str(line.get("text", "")))
        layers = list(line.get("vocalLayers", []))
        cue_vocal_keys = set()

        normalized_cues = []
        for cue in line.get("cues", []):
            cue_item = dict(cue)
            cue_text, cue_vocals = _split_vocals(str(cue_item.get("text", "")))
            cue_item["text"] = cue_text
            cue_time = float(cue_item.get("time", line_time))
            for item in cue_vocals:
                cue_vocal_keys.add((item["type"], item["text"]))
                vocal = {"type": item["type"], "text": item["text"], "time": cue_time}
                if cue_item.get("end") is not None:
                    vocal["end"] = float(cue_item["end"])
                layers.append(vocal)
            if cue_text:
                normalized_cues.append(cue_item)

        layers.extend(
            {"type": item["type"], "text": item["text"], "time": line_time}
            for item in inline_vocals
            if (item["type"], item["text"]) not in cue_vocal_keys
        )

        unique_layers = []
        seen_layers = set()
        for layer in layers:
            marker = (
                layer.get("type"), layer.get("text"),
                layer.get("time", line_time), layer.get("end"),
            )
            if marker not in seen_layers:
                seen_layers.add(marker)
                unique_layers.append(layer)

        line["text"] = line_text
        line["fullText"] = full_text
        line["cues"] = normalized_cues
        line["fullCues"] = full_cues
        line["vocalLayers"] = [
            layer for layer in unique_layers
            if isinstance(layer, dict) and str(layer.get("text", "")).strip()
        ]
        line["romanizedText"] = ""
        line["romanizedFullText"] = ""
        enriched.append(line)

    romanized_texts = _romanize_texts([
        text
        for line in enriched
        for text in (line["text"], line["fullText"])
    ])
    for index, line in enumerate(enriched):
        line["romanizedText"] = romanized_texts[index * 2]
        line["romanizedFullText"] = romanized_texts[index * 2 + 1]
    return enriched


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
    lines = _enrich_lines(lines)
    romanization_supported = any(_has_romanizable_script(line.get("fullText", "")) for line in lines)
    romanization_available = any(line.get("romanizedText") or line.get("romanizedFullText") for line in lines)
    print(json.dumps({
        "status": "ok",
        "lines": lines,
        "romanizationSupported": romanization_supported,
        "romanizationAvailable": romanization_available,
    }, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
