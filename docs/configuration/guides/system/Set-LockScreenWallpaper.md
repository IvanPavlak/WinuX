# Set-LockScreenWallpaper

Sets the Windows lock screen background image to match the active theme and machine type via native registry settings.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WallpaperDarkSettings`](../../configuration-reference.md#wallpaper-settings) | hashtable of machine type to wallpaper settings | `@{}` (empty) | Which wallpaper `Set-Wallpaper` and `Set-LockScreenWallpaper` apply in dark mode, per machine type. Supports a single file or one per monitor. |
| [`WallpaperLightSettings`](../../configuration-reference.md#wallpaper-settings) | hashtable of machine type to wallpaper settings | `@{}` (empty) | The light-mode counterpart of `WallpaperDarkSettings`. |

## Decisions

1. Which dark-mode wallpaper should this machine type use?
    - Options: A `@{ File; Style }` entry per machine type, or a per-monitor map for multi-monitor setups. `Style` is a key from `WallpaperStyles`.
    - Default: Empty - `Set-Wallpaper` reports nothing configured.
    - More detail: [`WallpaperDarkSettings`](../../configuration-reference.md#wallpaper-settings)
2. Which light-mode wallpaper should this machine type use?
    - Options: Same shape as `WallpaperDarkSettings`.
    - Default: Empty.
    - More detail: [`WallpaperLightSettings`](../../configuration-reference.md#wallpaper-settings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `WallpaperDarkSettings`
2. Set `WallpaperLightSettings`
3. Reload and confirm the merge landed

## Step 1: Set `WallpaperDarkSettings`

Which wallpaper `Set-Wallpaper` and `Set-LockScreenWallpaper` apply in dark mode, per machine type. Supports a single file or one per monitor.

```powershell
WallpaperDarkSettings = @{
    Test = @{ File = "BlackSpace1.jpg"; Style = "Fill" }
}
```

## Step 2: Set `WallpaperLightSettings`

The light-mode counterpart of `WallpaperDarkSettings`.

```powershell
WallpaperLightSettings = @{
    Test = @{ File = "WhiteSpace1.jpg"; Style = "Fill" }
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.WallpaperDarkSettings
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.WallpaperDarkSettings
$global:Configuration.WallpaperLightSettings
$global:Configuration.WallpaperDarkSettings
$global:Configuration.WallpaperLightSettings
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    WallpaperDarkSettings = @{
        Test = @{ File = "BlackSpace1.jpg"; Style = "Fill" }
    }
    WallpaperLightSettings = @{
        Test = @{ File = "WhiteSpace1.jpg"; Style = "Fill" }
    }
}
```

## Related

- [`Set-LockScreenWallpaper` in the System module reference](../../../modules/system.md#set-lockscreenwallpaper) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Set-Wallpaper`](Set-Wallpaper.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
