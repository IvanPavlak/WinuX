# Open-Browser

The primary browser launcher for the entire system.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BrowserGroups`](../../configuration-reference.md#browser-groups) | array of single-key hashtables | array of 12 example groups | The named URL groups `Open-Browser` opens. Groups nest without limit; a leaf is either a bare URL string or `@{ Name; Url }`. Every `Name` must be unique across the whole tree, because a name is a valid selector on its own. |
| [`Universal.DefaultBrowser`](../../configuration-reference.md#browser-configuration) | string (a `Browsers` key) | `""` (empty) | The browser used when `-Browser` is not given. Empty makes `Open-Browser` warn and return until you pass `-Browser` or set it. |
| [`Universal.Browsers`](../../configuration-reference.md#browser-configuration) | hashtable of browser name to `@{ Exe; PrivateArg; NewWindowArg }` | `Firefox`, `Tor`, `Chrome`, `Edge`, `Brave` | The browsers `-Browser` (and `DefaultBrowser`) can name: the executable to start, the private-mode argument and the new-window argument. Placeholders such as `{User}` expand. |

## Decisions

1. Which URL groups do you want to open by name?
    - Options: One group per theme, e.g. `AI`, `Monitoring`, `Docs`. [Add Browser Group](../application/add-browser-group.md) has the full shape. Named leaves (`@{ Name = "..."; Url = "..." }`) can be opened individually; bare URL strings can only be opened as part of their group.
    - Default: Keep the shipped example groups and add your own alongside. Remember that supplying `BrowserGroups` in the local file replaces the whole array.
    - More detail: [`BrowserGroups`](../../configuration-reference.md#browser-groups)
2. Do any of your groups need sub-groups?
    - Options: Nest another single-key hashtable inside the group array. A parent selector opens everything below it.
    - Default: Flat groups.
    - More detail: [`BrowserGroups`](../../configuration-reference.md#browser-groups)
3. Which browser should be the default?
    - Options: A key from `Universal.Browsers`: `Firefox`, `Chrome`, `Edge`, `Brave`, `Tor`, or one you add.
    - Default: Empty - `Open-Browser` warns and opens nothing unless `-Browser` is passed.
    - More detail: [`Universal.DefaultBrowser`](../../configuration-reference.md#browser-configuration)
4. Is a browser installed somewhere other than its shipped `Exe` path, or do you use one the base `Browsers` map does not list?
    - Options: Override that browser's `Exe`, or add an entry with `Exe`, `PrivateArg` and `NewWindowArg`. Because hashtables merge per key, changing or adding one browser does not remove the others.
    - Default: The shipped five, at their default install locations.
    - More detail: [`Universal.Browsers`](../../configuration-reference.md#browser-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `BrowserGroups` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `BrowserGroups`
2. Set `Universal`
3. Reload and confirm the merge landed

## Step 1: Set `BrowserGroups`

The named URL groups `Open-Browser` opens. Groups nest without limit; a leaf is either a bare URL string or `@{ Name; Url }`. Every `Name` must be unique across the whole tree, because a name is a valid selector on its own.

```powershell
BrowserGroups = @(
    @{ Monitoring = @(
        @{ Name = "Dashboard"; Url = "http://localhost:3000" }
        @{ Name = "Logs";      Url = "http://localhost:5341" }
    )}
)
```

## Step 2: Set `Universal`

`DefaultBrowser` and, when needed, extra or corrected `Browsers` entries. `Universal` is a hashtable and deep-merges, so the other `Universal` keys and the shipped browsers stay.

```powershell
Universal = @{
    DefaultBrowser = "Firefox"
    Browsers = @{
        Vivaldi = @{
            Exe          = "{User}\AppData\Local\Vivaldi\Application\vivaldi.exe"
            PrivateArg   = "--incognito"
            NewWindowArg = "--new-window"
        }
    }
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BrowserGroups
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.BrowserGroups
$global:Configuration.Universal.DefaultBrowser
$global:Configuration.Universal.Browsers.Keys
Collect-BrowserUrls -Value $global:Configuration.BrowserGroups
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BrowserGroups = @(
        @{ Monitoring = @(
            @{ Name = "Dashboard"; Url = "http://localhost:3000" }
            @{ Name = "Logs";      Url = "http://localhost:5341" }
        )}
    )
    Universal = @{
        DefaultBrowser = "Firefox"
        Browsers = @{
            Vivaldi = @{
                Exe          = "{User}\AppData\Local\Vivaldi\Application\vivaldi.exe"
                PrivateArg   = "--incognito"
                NewWindowArg = "--new-window"
            }
        }
    }
}
```

## Related

- [`Open-Browser` in the Application module reference](../../../modules/application.md#open-browser) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [Add Browser Group](add-browser-group.md) - browser groups, nesting, unique names, search and per-browser selection
- [`Add-BrowserGroup`](../configuration/Add-BrowserGroup.md) - reads the same configuration
- [`Get-SwaggerCloseTitlePatterns`](../workflow/Get-SwaggerCloseTitlePatterns.md) - reads the same configuration
- [`Resolve-SwaggerBrowserGroup`](../workflow/Resolve-SwaggerBrowserGroup.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
