pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning

import qs.modules.common

Singleton {
    id: root

    // 10 minute
    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property string city: Config.options.bar.weather.city
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    readonly property string cachePath: `${Quickshell.env("HOME")}/.cache/quickshell/weather.json`
    property bool gpsActive: Config.options.bar.weather.enableGPS
    property bool offline: false
    property double lastSuccessfulFetchMs: 0
    property int ageTick: 0
    property var pendingCachePayload: null

    readonly property string staleAge: {
        // ageTick makes this binding refresh as time passes while offline.
        const elapsedMs = Math.max(0, Date.now() - root.lastSuccessfulFetchMs + root.ageTick * 0)
        const minutes = Math.max(1, Math.ceil(elapsedMs / 60000))
        if (minutes < 60) return `${minutes}m`
        const hours = Math.floor(minutes / 60)
        if (hours < 24) return `${hours}h ${minutes % 60}m`
        const days = Math.floor(hours / 24)
        return `${days}d ${hours % 24}h`
    }

    onUseUSCSChanged: root.getData()
    onCityChanged: root.getData()

    property var location: ({
        valid: false,
        lat: 0,
        lon: 0
    })

    property var data: ({
        uv: 0,
        humidity: 0,
        sunrise: 0,
        sunset: 0,
        windDir: 0,
        wCode: 0,
        city: "",
        description: "",
        cr: "0%",
        wind: "",
        precip: "",
        visib: "",
        press: "",
        temp: "",
        tempFeelsLike: "",
        lastRefresh: ""
    })

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function writeCache(displayData, timestamp) {
        // Persist only the rendered fields; never include the API response, location, or API key.
        root.pendingCachePayload = JSON.stringify({ timestamp: timestamp, values: displayData })
        root.startCacheWrite()
    }

    function startCacheWrite() {
        if (cacheWriter.running || root.pendingCachePayload === null) return
        const payload = root.pendingCachePayload
        root.pendingCachePayload = null
        const directory = `${Quickshell.env("HOME")}/.cache/quickshell`
        cacheWriter.command = ["bash", "-c",
            `mkdir -p -- ${root.shellQuote(directory)} && tmp=${root.shellQuote(root.cachePath)}.tmp.$$ && printf '%s' ${root.shellQuote(payload)} > "$tmp" && mv -f -- "$tmp" ${root.shellQuote(root.cachePath)}`]
        cacheWriter.running = true
    }

    function restoreCache(raw) {
        try {
            const saved = JSON.parse(raw)
            const timestamp = Number(saved?.timestamp)
            const values = saved?.values
            const strings = ["description", "cr", "humidity", "sunrise", "sunset", "city", "wind", "precip", "visib", "press", "temp", "tempFeelsLike", "lastRefresh"]
            if (!Number.isFinite(timestamp) || timestamp <= 0 || !values || typeof values !== "object")
                return false
            if (strings.some(key => typeof values[key] !== "string")
                || !Number.isFinite(values.windDir) || !Number.isFinite(values.wCode))
                return false

            // Rebuild a strict display-only object instead of assigning arbitrary cache keys.
            const restored = {}
            strings.forEach(key => restored[key] = values[key])
            restored.windDir = values.windDir
            restored.wCode = values.wCode
            if (root.lastSuccessfulFetchMs === 0) {
                root.data = restored
                root.lastSuccessfulFetchMs = timestamp
            }
            return true
        } catch (e) {
            console.warn("[WeatherService] Ignoring invalid weather cache:", e.message)
            return false
        }
    }

    function refineData(data) {
        let temp = {}
        const rainMm = data?.rain?.["1h"] || data?.rain?.["3h"] || 0
        const snowMm = data?.snow?.["1h"] || data?.snow?.["3h"] || 0

        temp.description = data?.weather?.[0]?.description || ""
        temp.cr = data?.clouds?.all !== undefined
            ? Math.round(data.clouds.all * 0.8) + "%"
            : "0%"
        temp.humidity = (data?.main?.humidity || 0) + "%"

        const fmt = (unix) => new Date(unix * 1000).toLocaleTimeString("en-US", {
            hour: "numeric",
            minute: "2-digit",
            second: "2-digit",
            hour12: true
        })

        temp.sunrise = data?.sys?.sunrise ? fmt(data.sys.sunrise) : "0"
        temp.sunset  = data?.sys?.sunset  ? fmt(data.sys.sunset)  : "0"

        temp.windDir = data?.wind?.deg || 0
        temp.wCode = data?.weather?.[0]?.id || 0
        temp.city = data?.name || "City"

        if (root.useUSCS) {
            temp.wind = (data?.wind?.speed || 0) + " mph"
            temp.precip = ((rainMm + snowMm) * 0.0394).toFixed(2) + " in"
            temp.visib = ((data?.visibility || 0) / 1609).toFixed(1) + " mi"
            temp.press = (data?.main?.pressure || 0) + " hPa"
            temp.temp = Math.round(data?.main?.temp || 0) + "°F"
            temp.tempFeelsLike = Math.round(data?.main?.feels_like || 0) + "°F"
        } else {
            temp.wind = (data?.wind?.speed || 0) + " m/s"
            temp.precip = (rainMm + snowMm).toFixed(1) + " mm"
            temp.visib = ((data?.visibility || 0) / 1000).toFixed(1) + " km"
            temp.press = (data?.main?.pressure || 0) + " hPa"
            let roundedTemp = Math.round(data?.main?.temp || 0)
            let roundedFeels = Math.round(data?.main?.feels_like || 0)

            temp.temp = roundedTemp + "°C"
            temp.tempFeelsLike = roundedFeels + "°C"
        }

        const fetchedAt = Date.now()
        temp.lastRefresh = DateTime.time + " • " + DateTime.date
        root.data = temp
        root.lastSuccessfulFetchMs = fetchedAt
        root.offline = false
        root.writeCache(temp, fetchedAt)
    }

    function getData() {
        const defaultApiKey = "8b05d62206f459e1d298cbe5844d7d87"
        let apiKey = KeyringStorage.keyringData?.apiKeys?.openweather || defaultApiKey

        if (!apiKey || apiKey === "") {
            console.error("[WeatherService] Missing OpenWeather API key.")
            root.offline = true
            return
        }

        let units = root.useUSCS ? "imperial" : "metric"
        let url = "https://api.openweathermap.org/data/2.5/weather?"

        if (root.gpsActive && root.location.valid) {
            url += `lat=${root.location.lat}&lon=${root.location.lon}`
        } else {
            url += `q=${formatCityName(root.city)}`
        }

        url += `&units=${units}`
        url += `&appid=${apiKey}`

        let command = `curl -sS "${url}"`

        fetcher.command[2] = command
        fetcher.running = true
    }

    function formatCityName(cityName) {
        return cityName.trim().split(/\s+/).join('+')
    }

    Component.onCompleted: {
        cacheFile.reload()
        if (!root.gpsActive) return
        console.info("[WeatherService] Starting GPS service.")
        positionSource.start()
    }

    Process {
        id: fetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) {
                    root.offline = true
                    return
                }

                try {
                    const parsedData = JSON.parse(text)

                    if (parsedData.cod !== undefined && Number(parsedData.cod) !== 200) {
                        console.error("[WeatherService] API error:", parsedData.message)
                        root.offline = true
                        return
                    }

                    if (!parsedData.main || !Number.isFinite(Number(parsedData.main.temp))
                        || !Array.isArray(parsedData.weather) || parsedData.weather.length === 0) {
                        console.error("[WeatherService] Invalid weather response.")
                        root.offline = true
                        return
                    }

                    root.refineData(parsedData)
                } catch (e) {
                    console.error("[WeatherService] JSON parse error:", e.message)
                    root.offline = true
                }
            }
        }
        onExited: code => {
            if (code !== 0) root.offline = true
        }
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        printErrors: false
        onLoaded: root.restoreCache(cacheFile.text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[WeatherService] Could not read weather cache:", error)
        }
    }

    Process {
        id: cacheWriter
        onExited: code => {
            if (code !== 0) console.warn("[WeatherService] Could not update weather cache.")
            root.startCacheWrite()
        }
    }

    Timer {
        running: root.offline && root.lastSuccessfulFetchMs > 0
        repeat: true
        interval: 60000
        onTriggered: root.ageTick++
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                root.location.lat = position.coordinate.latitude
                root.location.lon = position.coordinate.longitude
                root.location.valid = true
                root.getData()
            } else {
                root.gpsActive = root.location.valid ? true : false
                console.error("[WeatherService] Failed to get GPS location.")
            }
        }

        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop()
                root.location.valid = false
                root.gpsActive = false
                console.error("[WeatherService] Could not acquire valid GPS backend.")
            }
        }
    }

    Timer {
        running: !root.gpsActive
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: !root.gpsActive
        onTriggered: root.getData()
    }
}
