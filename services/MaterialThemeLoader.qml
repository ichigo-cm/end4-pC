pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath
    property var defaultMaterialColors: ({})
    property var loadedMaterialColors: ({})

    function macPalette() {
        const d = Appearance.design
        return {
            m3background: d.canvas,
            m3onBackground: d.foreground,
            m3surface: d.surface0,
            m3surfaceDim: d.canvas,
            m3surfaceBright: d.surface4,
            m3surfaceContainerLowest: d.canvas,
            m3surfaceContainerLow: d.surface1,
            m3surfaceContainer: d.surface2,
            m3surfaceContainerHigh: d.surface3,
            m3surfaceContainerHighest: d.surface4,
            m3onSurface: d.foreground,
            m3surfaceVariant: d.surface3,
            m3onSurfaceVariant: d.foregroundSecondary,
            m3inverseSurface: d.foreground,
            m3inverseOnSurface: d.canvas,
            m3outline: d.outline,
            m3outlineVariant: d.outlineVariant,
            m3shadow: "#000000",
            m3scrim: "#000000",
            m3surfaceTint: d.accent,
            m3primary: d.accent,
            m3onPrimary: "#ffffff",
            m3primaryContainer: d.accentContainer,
            m3onPrimaryContainer: d.onAccentContainer,
            m3inversePrimary: "#f2555c",
            m3secondary: d.foregroundSecondary,
            m3onSecondary: d.canvas,
            m3secondaryContainer: d.surface3,
            m3onSecondaryContainer: d.foreground,
            m3tertiary: "#cfd0d4",
            m3onTertiary: d.canvas,
            m3tertiaryContainer: d.surface2,
            m3onTertiaryContainer: d.foreground,
            m3error: d.statusError,
            m3onError: "#28090b",
            m3errorContainer: "#381318",
            m3onErrorContainer: "#ffdcdd",
            m3primaryFixed: "#f8e7e8",
            m3primaryFixedDim: "#e8b4b6",
            m3onPrimaryFixed: "#271214",
            m3onPrimaryFixedVariant: "#5a272c",
            m3secondaryFixed: "#f2f2f4",
            m3secondaryFixedDim: d.foregroundSecondary,
            m3onSecondaryFixed: "#17181b",
            m3onSecondaryFixedVariant: d.outlineVariant,
            m3tertiaryFixed: "#f1f1f3",
            m3tertiaryFixedDim: "#cfd0d4",
            m3onTertiaryFixed: "#17181b",
            m3onTertiaryFixedVariant: d.surface3,
            m3success: d.statusSuccess,
            m3onSuccess: "#11251c",
            m3successContainer: d.statusSuccessContainer,
            m3onSuccessContainer: d.onStatusSuccessContainer
        }
    }

    function applyMacPalette() {
        const palette = root.macPalette()
        for (const key in palette)
            Appearance.m3colors[key] = palette[key]
    }

    function restoreMaterialPalette() {
        const palette = root.macPalette()
        for (const key in palette) {
            if (key in root.loadedMaterialColors)
                Appearance.m3colors[key] = root.loadedMaterialColors[key]
            else if (key in root.defaultMaterialColors)
                Appearance.m3colors[key] = root.defaultMaterialColors[key]
        }
    }

    function reapplyTheme() {
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        const json = JSON.parse(fileContent)
        const palette = root.macPalette()
        for (const key in palette) {
            if (!(key in root.defaultMaterialColors))
                root.defaultMaterialColors[key] = Appearance.m3colors[key]
        }
        const loaded = ({})
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                loaded[m3Key] = json[key]
                Appearance.m3colors[m3Key] = json[key]
            }
        }
        root.loadedMaterialColors = loaded
        if (Appearance.design.isMacOS)
            root.applyMacPalette()
        Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
        // Custom window border colors are stored as palette roles, so they
        // have to be pushed to Hyprland again whenever the palette changes.
        HyprlandConfig.applyBorderColors()
    }

    Connections {
        target: Config.options.appearance
        function onShellStyleChanged() {
            if (Appearance.design.isMacOS)
                root.applyMacPalette()
            else
                root.restoreMaterialPalette()
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
            HyprlandConfig.applyBorderColors()
        }
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    function useLockTheme() {
        root.filePath = ""
        root.filePath = Directories.generatedLockMaterialThemePath
    }

    function useLiveTheme() {
        root.filePath = ""
        root.filePath = Directories.generatedMaterialThemePath
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

    FileView {
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }
}
