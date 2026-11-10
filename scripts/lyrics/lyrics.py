#!/usr/bin/env python3
"""Fetch synchronized lyrics and normalize optional lyric presentation metadata."""

import json
import math
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

LRC_LINE_TAG = re.compile(r"\[(\d+:\d{2}(?:\.\d+)?)\]")
LRC_INLINE_TAG = re.compile(r"<(\d+:\d{2}(?:\.\d+)?)>")
VOCAL_SEGMENT = re.compile(r"[\(（]([^()（）]{1,120})[\)）]")
LYRICS_USER_AGENT = "end4-pC lyrics helper/1.0 (https://github.com/ichigo-cm/end4-pC)"
LRCLIB_REQUEST_DELAY_SECONDS = 0.25


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


def _lyricsfile_scalar(value: str):
    value = value.strip()
    if not value:
        return ""
    if value.startswith('"'):
        closing = value.rfind('"')
        if closing > 0 and (not value[closing + 1:].strip() or value[closing + 1:].lstrip().startswith("#")):
            value = value[:closing + 1]
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return None
    if value.startswith("'"):
        closing = value.rfind("'")
        if closing > 0 and (not value[closing + 1:].strip() or value[closing + 1:].lstrip().startswith("#")):
            value = value[:closing + 1]
        if len(value) < 2 or not value.endswith("'"):
            return None
        return value[1:-1].replace("''", "'")
    value = re.split(r"\s+#", value, maxsplit=1)[0].rstrip()
    if value in ("null", "Null", "NULL", "~"):
        return None
    if value in ("true", "True", "TRUE"):
        return True
    if value in ("false", "False", "FALSE"):
        return False
    if re.fullmatch(r"[-+]?\d+", value):
        try:
            return int(value)
        except ValueError:
            return None
    if re.fullmatch(r"[-+]?(?:\d+\.\d*|\d*\.\d+)(?:[eE][-+]?\d+)?", value):
        try:
            return float(value)
        except ValueError:
            return None
    if value in ("|", ">", "[]", "{}"):
        return None
    return value


def _lyricsfile_entry(value: str):
    if value.startswith("- "):
        value = value[2:]
    key, separator, scalar = value.partition(":")
    if not separator:
        return None
    key = key.strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        return None
    return key, scalar.strip()


def _parse_lyricsfile(source: str) -> list:
    """Parse Lyricsfile 1.0's line/word timing subset without a YAML dependency."""
    if not isinstance(source, str):
        return []
    raw_lines = source.splitlines()
    lines_header = next(
        (index for index, raw in enumerate(raw_lines)
         if not raw.startswith((" ", "\t")) and re.fullmatch(r"lines\s*:\s*(?:#.*)?", raw.strip())),
        None,
    )
    if lines_header is None:
        return []

    line_records = []
    current_line = None
    current_word = None
    line_item_indent = None
    words_key_indent = None
    word_item_indent = None

    for raw in raw_lines[lines_header + 1:]:
        content = raw.lstrip(" ")
        indent = len(raw) - len(content)
        if not content or content.startswith("#"):
            continue
        if indent == 0 and not content.startswith("- "):
            break

        if content.startswith("- "):
            if line_item_indent is None or indent == line_item_indent:
                current_line = {"_words": []}
                line_records.append(current_line)
                line_item_indent = indent
                words_key_indent = None
                word_item_indent = None
                current_word = None
                entry = _lyricsfile_entry(content)
                if entry:
                    key, scalar = entry
                    if key == "words":
                        words_key_indent = indent
                    else:
                        current_line[key] = _lyricsfile_scalar(scalar)
                continue

            if current_line is None or words_key_indent is None or indent < words_key_indent:
                return []
            if word_item_indent is None:
                word_item_indent = indent
            if indent != word_item_indent:
                return []
            current_word = {}
            current_line["_words"].append(current_word)
            entry = _lyricsfile_entry(content)
            if entry:
                key, scalar = entry
                current_word[key] = _lyricsfile_scalar(scalar)
            continue

        if current_line is None or indent <= line_item_indent:
            continue
        target = current_word if (
            current_word is not None and word_item_indent is not None and indent > word_item_indent
        ) else current_line
        entry = _lyricsfile_entry(content)
        if not entry:
            continue
        key, scalar = entry
        if target is current_line and key == "words":
            if scalar and scalar != "[]" and not scalar.startswith("#"):
                return []
            current_line["_words"] = []
            words_key_indent = indent
            word_item_indent = None
            current_word = None
        else:
            target[key] = _lyricsfile_scalar(scalar)

    def milliseconds(value):
        try:
            result = float(value) / 1000.0
            return result if math.isfinite(result) and result >= 0 else None
        except (TypeError, ValueError):
            return None

    parsed = []
    for record in line_records:
        cues = []
        for word in record.get("_words", []):
            if not isinstance(word, dict) or not str(word.get("text", "")):
                continue
            start = milliseconds(word.get("start_ms"))
            if start is None:
                continue
            cue = {"time": start, "text": str(word["text"])}
            end = milliseconds(word.get("end_ms"))
            if end is not None and end > start:
                cue["end"] = end
            cues.append(cue)

        if not cues:
            continue
        if any(cues[index]["time"] > cues[index + 1]["time"] for index in range(len(cues) - 1)):
            return []

        line_start = milliseconds(record.get("start_ms"))
        if line_start is None:
            line_start = cues[0]["time"]
        line_end = milliseconds(record.get("end_ms"))
        for index, cue in enumerate(cues):
            if "end" in cue:
                continue
            next_start = cues[index + 1]["time"] if index + 1 < len(cues) else line_end
            if next_start is not None and next_start > cue["time"]:
                cue["end"] = next_start

        text = record.get("text")
        if not isinstance(text, str) or not text.strip():
            text = "".join(cue["text"] for cue in cues)
        text = _clean_text(text)
        if not text:
            continue
        parsed.append({
            "time": line_start,
            "text": text,
            "fullText": text,
            "cues": cues,
            "fullCues": [dict(cue) for cue in cues],
        })
    return sorted(parsed, key=lambda item: item["time"])


def _is_match(data: dict, title: str, artist: str) -> bool:
    has_timed_data = bool(data.get("syncedLyrics")) or (
        data.get("hasWordSync") is True and bool(data.get("lyricsfile"))
    )
    if not has_timed_data:
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


def fetch_lrclib_candidates(title: str, artist: str, duration: float, album: str = "") -> tuple:
    query = {"track_name": title, "artist_name": artist}
    if album:
        query["album_name"] = album
    urls = []
    try:
        duration_seconds = int(duration)
    except (TypeError, ValueError, OverflowError):
        duration_seconds = 0
    if duration_seconds > 0:
        exact_query = dict(query)
        exact_query["duration"] = str(duration_seconds)
        urls.append(f"https://lrclib.net/api/get?{urllib.parse.urlencode(exact_query)}")
    urls.extend([
        f"https://lrclib.net/api/search?{urllib.parse.urlencode(query)}",
        f"https://lrclib.net/api/search?q={urllib.parse.quote(' '.join(part for part in (title, artist, album) if part))}",
    ])
    word_synced_lines = []
    line_synced_lines = []
    for index, url in enumerate(urls):
        data = None
        try:
            request = urllib.request.Request(
                url,
                headers={"User-Agent": LYRICS_USER_AGENT},
            )
            with urllib.request.urlopen(request, timeout=15) as response:
                data = json.loads(response.read().decode())
        except urllib.error.HTTPError as error:
            if error.code == 429:
                break
        except Exception:
            pass

        records = data if isinstance(data, list) else [data]
        for record in records:
            if not isinstance(record, dict) or not _is_match(record, title, artist):
                continue
            if not word_synced_lines and record.get("hasWordSync") is True:
                word_synced_lines = _parse_lyricsfile(record.get("lyricsfile", ""))
            if not line_synced_lines and record.get("syncedLyrics"):
                line_synced_lines = _parse_lrc(record["syncedLyrics"])
            if word_synced_lines:
                return word_synced_lines, line_synced_lines
        if index + 1 < len(urls):
            time.sleep(LRCLIB_REQUEST_DELAY_SECONDS)
    return word_synced_lines, line_synced_lines


def fetch_lrclib(title: str, artist: str, duration: float, album: str = "") -> list:
    word_synced, line_synced = fetch_lrclib_candidates(title, artist, duration, album)
    return word_synced or line_synced


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
    )
    metadata += " " + str(span.get("{http://www.w3.org/ns/ttml#metadata}role", ""))
    metadata = metadata.lower()
    if any(word in metadata for word in ("background", "backing", "bg-vocal", "bg_vocal", "x-bg")):
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
            timed_descendants = [
                child for child in span.iter()
                if child is not span and _local_name(child) == "span" and child.get("begin") is not None
            ]
            if timed_descendants:
                for child in timed_descendants:
                    child_text = _clean_text("".join(child.itertext()))
                    if not child_text:
                        continue
                    layer = {"type": kind, "text": child_text, "time": line_time}
                    try:
                        layer["time"] = _resolve_ttml_time(child.get("begin"), line_time)
                        if child.get("end") is not None:
                            end_time = _resolve_ttml_time(child.get("end"), line_time)
                            if end_time > layer["time"]:
                                layer["end"] = end_time
                    except (ValueError, TypeError):
                        pass
                    vocal_layers.append(layer)
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

        parents = {child: parent for parent in paragraph.iter() for child in parent}

        def is_inside_vocal_layer(span):
            current = span
            while current is not None and current is not paragraph:
                if _ttml_vocal_kind(current):
                    return True
                current = parents.get(current)
            return False

        cues = []
        for span in paragraph.iter():
            if span is paragraph or _local_name(span) != "span" or span.get("begin") is None:
                continue
            if is_inside_vocal_layer(span):
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


def fetch_boidu(title: str, artist: str, duration: float, album: str = "") -> list:
    query = urllib.parse.urlencode({
        "s": title,
        "a": artist,
        "al": album,
        "d": max(0, int(duration)),
    })
    query = f"/getLyrics?{query}"
    for base in BOIDU_BASES:
        try:
            request = urllib.request.Request(base + query, headers={"User-Agent": LYRICS_USER_AGENT})
            with urllib.request.urlopen(request, timeout=15) as response:
                data = json.loads(response.read().decode())
            lines = _parse_ttml(data.get("ttml") or "")
            if len(lines) >= 3:
                return lines
        except Exception:
            continue
    return []


def fetch_best_lyrics(title: str, artist: str, duration: float, album: str = "") -> list:
    word_synced, line_synced = fetch_lrclib_candidates(title, artist, duration, album)
    if word_synced:
        return word_synced

    ttml_lines = fetch_boidu(title, artist, duration, album)
    has_timed_cues = any(
        line.get("cues") or line.get("fullCues")
        for line in ttml_lines
        if isinstance(line, dict)
    )
    if has_timed_cues:
        return ttml_lines
    return line_synced or ttml_lines


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


_LATIN_VOWELS = frozenset("aeiouyàáâãäåæèéêëìíîïòóôõöøùúûüÿāēīōūœ")
_GREEK_VOWELS = frozenset("αεηιουω")
_CYRILLIC_VOWELS = frozenset("аеёиоуыэюя")
_SMALL_KANA = frozenset("ぁぃぅぇぉゃゅょゎァィゥェォャュョヮ")


def _karaoke_character_weights(text: str) -> list:
    """Return relative character durations; these shape animation, not source timestamps."""
    weights = []
    for char in str(text):
        codepoint = ord(char)
        category = unicodedata.category(char)
        if category.startswith("M"):
            weight = 0.0
        elif char.isspace():
            weight = 0.28
        elif char == "ー":
            weight = 1.8
        elif char == "っ":
            weight = 0.55
        elif char in _SMALL_KANA:
            weight = 0.4
        elif char in ".!?…！？。":
            weight = 2.2
        elif char in ",;:，、；：":
            weight = 1.25
        elif 0x3040 <= codepoint <= 0x30FF or 0x3400 <= codepoint <= 0x9FFF or 0xAC00 <= codepoint <= 0xD7AF:
            weight = 1.0
        elif char.isalpha():
            decomposed = unicodedata.normalize("NFD", char.casefold())
            base = next((value for value in decomposed if value.isalpha()), char.casefold())
            if base in _LATIN_VOWELS or base in _GREEK_VOWELS or base in _CYRILLIC_VOWELS:
                weight = 1.8 if base != "y" else 1.2
            elif base in "mnlrw":
                weight = 0.78
            elif codepoint < 0x0250:
                weight = 0.52
            else:
                weight = 1.0
        elif category.startswith("P"):
            weight = 0.9
        else:
            weight = 0.8
        weights.append(weight)
    return weights


def _enrich_lines(lines: list) -> list:
    enriched = []
    for source_line in lines:
        line = dict(source_line)
        line_time = float(line.get("time", 0))
        full_text = str(line.get("fullText", line.get("text", "")))
        full_cues = [dict(cue) for cue in line.get("fullCues", line.get("cues", []))]
        for cue in full_cues:
            cue["weights"] = _karaoke_character_weights(str(cue.get("text", "")))
        line_text, inline_vocals = _split_vocals(str(line.get("text", "")))
        layers = list(line.get("vocalLayers", []))
        cue_vocal_keys = set()

        normalized_cues = []
        for cue in line.get("cues", []):
            cue_item = dict(cue)
            cue_text, cue_vocals = _split_vocals(str(cue_item.get("text", "")))
            cue_item["text"] = cue_text
            cue_item["weights"] = _karaoke_character_weights(cue_text)
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
        line["karaokeWeights"] = _karaoke_character_weights(line_text)
        line["fullKaraokeWeights"] = _karaoke_character_weights(full_text)
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
    album = sys.argv[4] if len(sys.argv) > 4 else ""
    if not title or not artist:
        print("no_info", flush=True)
        sys.exit(0)
    lines = fetch_best_lyrics(title, artist, duration, album)
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
