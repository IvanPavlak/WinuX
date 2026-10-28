# Resolve-LayoutTokens

Expands layout-file tokens to regex patterns at the matching boundary.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal`](../../configuration-reference.md#universal-constants) | hashtable | shipped `Browsers` map: `Firefox`, `Tor`, `Chrome`, `Edge`, `Brave` | Only `Universal.Browsers` is read: every key except `Tor` joins the title side of the `Browser` token, and the basename of its `Exe` joins the process side. |

The `Browser` layout token expands from `Universal.Browsers` - the same map `Open-Browser` reads - with Tor excluded (SecureBrowser layouts target `tor` explicitly). Because hashtables deep-merge per key, adding a browser under `Universal.Browsers` in `Configuration.local.psd1` both makes it launchable by `Open-Browser` and joins it into the `Browser` token, without touching the shipped entries. A **top-level** `Browsers` map is honoured as a legacy fallback (an earlier version of this function read only that location), and when no configuration is loaded at all the token falls back to the built-in `firefox|chrome|msedge|brave` set.

## Decisions

1. Do you use a browser the base `Browsers` map does not list?
    - Options: Add an entry with `Exe`, `PrivateArg` and `NewWindowArg`. Because hashtables merge per key, adding one browser does not remove the others, and the new browser joins the `Browser` token.
    - Default: The shipped five; the `Browser` token covers all of them except `Tor`.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal`
2. Reload and confirm the merge landed

## Step 1: Set `Universal`

This function reads only `Universal.Browsers`. Add a browser there and it joins the `Browser` token: its key on the title side, its `Exe` basename (`vivaldi`) on the process side. `Universal` is expanded in place by `Load-PathConfiguration`, so placeholders work in `Exe`.

```powershell
Universal = @{
    Browsers = @{
        Vivaldi = @{
            Exe          = "{User}\AppData\Local\Vivaldi\Application\vivaldi.exe"
            PrivateArg   = "--incognito"
            NewWindowArg = "--new-window"
        }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.Browsers
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.Browsers
Resolve-LayoutTokens -LayoutEntry @{ ProcessName = "Browser" }   # shows the expanded regex
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
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

- [`Resolve-LayoutTokens` in the Window module reference](../../../modules/window.md#resolve-layouttokens) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [`Open-Browser`](../application/Open-Browser.md) - reads the same configuration
- [`Open-LeagueOfLegends`](../application/Open-LeagueOfLegends.md) - reads the same configuration
- [`Open-NotepadPlusPlus`](../application/Open-NotepadPlusPlus.md) - reads the same configuration
- [`Open-Steam`](../application/Open-Steam.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
