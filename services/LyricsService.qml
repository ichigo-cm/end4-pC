pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    property var lyricsLines: []
    property int activeIndex: -1
    property int revealedCharacters: 0
    property string status: "loading"
    property var slots: ["", "", "", "", "", "", ""]

    readonly property int before: 3
    readonly property int after: 3
    readonly property int total: 7

    readonly property bool playing: root.activePlayer?.isPlaying ?? false
    readonly property bool synced: root.status === "ok" && root.lyricsLines.length > 0
    readonly property bool karaokeMotion: Config.options.media.karaokeAnimation && !Config.options.appearance.reducedMotion
    readonly property real leadSeconds: 0.15

    property real basePosition: 0
    property real baseTime: Date.now()

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            const lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    function currentPosition() {
        return root.playing ? root.basePosition + (Date.now() - root.baseTime) / 1000 : root.basePosition
    }

    function lineEndPosition(index, start, characterCount) {
        const next = root.lyricsLines[index + 1]
        const nextTime = Number(next?.time)
        const trackLength = Number(root.activePlayer?.length ?? 0)
        let span = nextTime > start ? nextTime - start : trackLength > start ? trackLength - start : 3
        span = Math.max(0.35, Math.min(6, span))
        return start + span
    }

    function revealCountAt(index, position) {
        const line = root.lyricsLines[index]
        if (!line) return 0
        const text = String(line.text ?? "")
        const characters = Array.from(text)
        if (characters.length === 0) return 0

        const lineStart = Number(line.time)
        const fallbackEnd = root.lineEndPosition(index, lineStart, characters.length)
        const cues = Array.isArray(line.cues) ? line.cues : []
        let matchedCues = 0
        let revealed = 0
        let cursor = 0

        for (let i = 0; i < cues.length; i++) {
            const cue = cues[i]
            const cueText = String(cue?.text ?? "")
            const cueStart = Number(cue?.time)
            if (!cueText || !Number.isFinite(cueStart)) continue

            const offset = text.indexOf(cueText, cursor)
            if (offset < 0) continue
            matchedCues++

            const cueCharacters = Array.from(cueText)
            const prefixCount = Array.from(text.slice(cursor, offset)).length
            let cueEnd = Number(cue?.end)
            if (!Number.isFinite(cueEnd) || cueEnd <= cueStart) {
                cueEnd = NaN
                for (let nextIndex = i + 1; nextIndex < cues.length; nextIndex++) {
                    const candidate = Number(cues[nextIndex]?.time)
                    if (Number.isFinite(candidate) && candidate > cueStart) {
                        cueEnd = candidate
                        break
                    }
                }
                if (!Number.isFinite(cueEnd)) cueEnd = fallbackEnd
            }

            if (position >= cueStart) {
                const cueProgress = position >= cueEnd
                    ? 1
                    : Math.max(0, Math.min(1, (position - cueStart) / Math.max(0.001, cueEnd - cueStart)))
                const withinCue = Math.floor(cueProgress * cueCharacters.length)
                revealed = Math.max(revealed, prefixCount + withinCue)
            }
            cursor = offset + cueText.length
        }

        if (matchedCues > 0)
            return Math.max(0, Math.min(characters.length, revealed))

        const progress = Math.max(0, Math.min(1, (position - lineStart) / Math.max(0.001, fallbackEnd - lineStart)))
        return Math.floor(progress * characters.length)
    }

    function updateKaraoke() {
        if (root.activeIndex < 0 || root.activeIndex >= root.lyricsLines.length) {
            root.revealedCharacters = 0
            return
        }
        const position = root.currentPosition() + root.leadSeconds
        const nextCount = root.revealCountAt(root.activeIndex, position)
        if (nextCount !== root.revealedCharacters)
            root.revealedCharacters = nextCount
    }

    function escapeMarkup(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function karaokeMarkup(playedColor, pendingColor) {
        const line = root.lyricsLines[root.activeIndex]
        if (!line) return ""
        const characters = Array.from(String(line.text ?? ""))
        const count = Math.max(0, Math.min(characters.length, root.revealedCharacters))
        const played = playedColor.toString()
        const pending = pendingColor.toString()
        const completed = root.escapeMarkup(characters.slice(0, count).join(""))
        const currentCharacter = count < characters.length ? root.escapeMarkup(characters[count]) : ""
        const pendingStart = count + (root.playing && currentCharacter ? 1 : 0)
        const pendingText = root.escapeMarkup(characters.slice(pendingStart).join(""))
        let result = completed ? `<font color=\"${played}\">${completed}</font>` : ""
        if (currentCharacter && root.playing)
            result += `<b><font color=\"${played}\">${currentCharacter}</font></b>`
        if (pendingText)
            result += `<font color=\"${pending}\">${pendingText}</font>`
        return result
    }

    function resync() {
        if (!root.activePlayer) return
        root.activePlayer.positionChanged()
        readPositionTimer.restart()
    }

    function indexAt(pos) {
        const lines = root.lyricsLines
        let low = 0
        let high = lines.length - 1
        let result = -1
        while (low <= high) {
            const mid = (low + high) >> 1
            if (lines[mid].time <= pos) {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    function update() {
        boundaryTimer.stop()
        if (!root.synced) return
        const position = root.currentPosition() + root.leadSeconds
        const idx = root.indexAt(position)
        if (idx !== root.activeIndex) {
            root.activeIndex = idx
            root.slots = root.buildSlots(idx)
        }
        root.updateKaraoke()

        const next = root.lyricsLines[idx + 1]
        if (!root.playing || !next) return
        const delay = (next.time - root.leadSeconds - root.currentPosition()) * 1000
        boundaryTimer.interval = Math.max(1, Math.ceil(delay))
        boundaryTimer.start()
    }

    Timer {
        id: readPositionTimer
        interval: 80
        onTriggered: {
            root.basePosition = root.activePlayer?.position ?? 0
            root.baseTime = Date.now()
            root.update()
        }
    }

    Timer {
        id: boundaryTimer
        onTriggered: root.update()
    }

    Timer {
        id: lyricProgressTimer
        interval: 50
        repeat: true
        running: root.synced && root.playing && root.karaokeMotion
        onTriggered: {
            const index = root.indexAt(root.currentPosition() + root.leadSeconds)
            if (index !== root.activeIndex)
                root.update()
            else
                root.updateKaraoke()
        }
    }

    Timer {
        id: driftTimer
        interval: 4000
        repeat: true
        running: root.synced && root.playing
        onTriggered: root.resync()
    }

    Process {
        id: lyricsProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed === "not_found") { root.status = "not_found"; return }
                if (trimmed === "no_info") { root.status = "no_info"; return }

                let lines = []
                if (trimmed.startsWith("{")) {
                    try {
                        const payload = JSON.parse(trimmed)
                        if (payload.status !== "ok" || !Array.isArray(payload.lines)) return
                        lines = payload.lines
                            .filter(line => Number.isFinite(Number(line?.time)) && typeof line?.text === "string")
                            .map(line => {
                                const normalized = { time: Number(line.time), text: line.text }
                                if (Array.isArray(line.cues)) {
                                    normalized.cues = line.cues
                                        .filter(cue => Number.isFinite(Number(cue?.time)) && typeof cue?.text === "string")
                                        .map(cue => {
                                            const item = { time: Number(cue.time), text: cue.text }
                                            if (Number.isFinite(Number(cue.end))) item.end = Number(cue.end)
                                            return item
                                        })
                                }
                                return normalized
                            })
                    } catch (error) {
                        console.warn(`[Lyrics] Could not parse lyric response: ${error}`)
                        return
                    }
                } else {
                    // Accept the previous separator format if an older helper is still running.
                    const parts = trimmed.split("§")
                    if (parts.length < 3 || parts[parts.length - 1].trim() !== "ok") return
                    for (let i = 0; i < parts.length - 1; i += 2) {
                        const time = Number.parseFloat(parts[i])
                        const text = parts[i + 1] || ""
                        if (Number.isFinite(time)) lines.push({ time, text })
                    }
                }

                if (lines.length === 0) { root.status = "not_found"; return }

                root.lyricsLines = lines
                root.activeIndex = -1
                root.revealedCharacters = 0
                root.slots = root.buildSlots(-1)
                root.status = "ok"
                root.resync()
            }
        }
    }

    function restartLyrics() {
        lyricsProc.running = false
        boundaryTimer.stop()
        root.lyricsLines = []
        root.activeIndex = -1
        root.revealedCharacters = 0
        root.slots = ["", "", "", "", "", "", ""]
        root.status = "loading"

        const title = root.activePlayer?.trackTitle ?? ""
        const artist = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length ?? 0

        if (!title || !artist) { root.status = "no_info"; return }

        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration))
        ]
        lyricsProc.running = true
    }

    Timer {
        id: restartDebounce
        interval: 150
        onTriggered: root.restartLyrics()
    }

    onActivePlayerChanged: restartDebounce.restart()
    onKaraokeMotionChanged: root.updateKaraoke()

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() { root.restartLyrics() }
        function onTrackArtistChanged() { restartDebounce.restart() }
        function onPlaybackStateChanged() { root.resync() }
    }

    Component.onCompleted: root.restartLyrics()
}
