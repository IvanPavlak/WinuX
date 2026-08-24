# Test-BrowserGroupAlreadyOpen

Internal idempotency helper for `Open-Browser`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BrowserGroupMatching`](../../configuration-reference.md#more-sections-quick-reference) | hashtable, 5 keys | hashtable, 5 keys | How an already-open browser group is recognised: `BrowserProcessNames` (label to process name), `ExactTitle`, `KeywordExtraction`, `Matching` thresholds and `NegativeMatching`. Tuning knobs, not a list of your own data. |

## Decisions

1. Is any browser group being wrongly reported as already open (or missed)?
    - Options: Adjust `Matching` thresholds, add a `NegativeMatching` term, or extend `BrowserProcessNames` for a browser the base list does not know.
    - Default: Leave the shipped tuning alone. Change this only in response to an actual misdetection.
    - More detail: [`BrowserGroupMatching`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `BrowserGroupMatching`
2. Reload and confirm the merge landed

## Step 1: Set `BrowserGroupMatching`

How an already-open browser group is recognised: `BrowserProcessNames` (label to process name), `ExactTitle`, `KeywordExtraction`, `Matching` thresholds and `NegativeMatching`. Tuning knobs, not a list of your own data.

```powershell
BrowserGroupMatching = @{
    BrowserProcessNames = @{
        Firefox = "firefox"
        Chrome  = "chrome"
        Edge    = "msedge"
        Brave   = "brave"
        Vivaldi = "vivaldi"
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.BrowserGroupMatching
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.BrowserGroupMatching
Test-BrowserGroupAlreadyOpen -Urls @("http://localhost:3000") -GroupDisplayName "Monitoring"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    BrowserGroupMatching = @{
        BrowserProcessNames = @{
            Firefox = "firefox"
            Chrome  = "chrome"
            Edge    = "msedge"
            Brave   = "brave"
            Vivaldi = "vivaldi"
        }
    }
}
```

## Related

- [`Test-BrowserGroupAlreadyOpen` in the Application module reference](../../../modules/application.md#test-browsergroupalreadyopen) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [Add Browser Group](add-browser-group.md) - browser groups, nesting, unique names, search and per-browser selection
- [`Resolve-SwaggerBrowserGroup`](../workflow/Resolve-SwaggerBrowserGroup.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
