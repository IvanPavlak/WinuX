# Resolve-SwaggerBrowserGroup

Resolves the `Swagger` browser group for a project so it can be handed to `Open-Browser`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`BrowserGroupMatching`](../../configuration-reference.md#more-sections-quick-reference) | hashtable, 5 keys | hashtable, 5 keys | How an already-open browser group is recognised: `BrowserProcessNames` (label to process name), `ExactTitle`, `KeywordExtraction`, `Matching` thresholds and `NegativeMatching`. Tuning knobs, not a list of your own data. |
| [`BrowserGroups`](../../configuration-reference.md#browser-groups) | array of single-key hashtables | array of 12 example groups | The named URL groups `Open-Browser` opens. Groups nest without limit; a leaf is either a bare URL string or `@{ Name; Url }`. Every `Name` must be unique across the whole tree, because a name is a valid selector on its own. |
| [`Universal`](../../configuration-reference.md#universal-constants) | hashtable, 26 keys | hashtable, 26 keys | Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `ProcessCleanup` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too. |

## Decisions

1. Is any browser group being wrongly reported as already open (or missed)?
    - Options: Adjust `Matching` thresholds, add a `NegativeMatching` term, or extend `BrowserProcessNames` for a browser the base list does not know.
    - Default: Leave the shipped tuning alone. Change this only in response to an actual misdetection.
    - More detail: [`BrowserGroupMatching`](../../configuration-reference.md#more-sections-quick-reference)
2. Which URL groups do you want to open by name?
    - Options: One group per theme, e.g. `AI`, `Monitoring`, `Docs`. [Add Browser Group](../application/add-browser-group.md) has the full shape. Named leaves (`@{ Name = "..."; Url = "..." }`) can be opened individually; bare URL strings can only be opened as part of their group.
    - Default: Keep the shipped example groups and add your own alongside. Remember that supplying `BrowserGroups` in the local file replaces the whole array.
    - More detail: [`BrowserGroups`](../../configuration-reference.md#browser-groups)
3. Do any of your groups need sub-groups?
    - Options: Nest another single-key hashtable inside the group array. A parent selector opens everything below it.
    - Default: Flat groups.
    - More detail: [`BrowserGroups`](../../configuration-reference.md#browser-groups)
4. Which browser should be the default?
    - Options: A key from `Universal.Browsers`: `Firefox`, `Chrome`, `Edge`, `Brave`, `Tor`. Ships empty, so `Open-Browser` asks or uses the system default.
    - Default: Empty.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)
5. Are any of the shipped executable paths wrong on this machine?
    - Options: Override the individual `Universal.<App>Exe` value. Absolute paths, or placeholder paths such as `{User}\AppData\Local\...`.
    - Default: The shipped paths, which assume default install locations.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)
6. Do you use a browser the base `Browsers` map does not list?
    - Options: Add an entry with `Exe`, `PrivateArg` and `NewWindowArg`. Because hashtables merge per key, adding one browser does not remove the others.
    - Default: The shipped five.
    - More detail: [`Universal`](../../configuration-reference.md#universal-constants)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `BrowserGroups` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `BrowserGroupMatching`
2. Set `BrowserGroups`
3. Set `Universal`
4. Reload and confirm the merge landed

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

## Step 2: Set `BrowserGroups`

The named URL groups `Open-Browser` opens. Groups nest without limit; a leaf is either a bare URL string or `@{ Name; Url }`. Every `Name` must be unique across the whole tree, because a name is a valid selector on its own.

```powershell
BrowserGroups = @(
    @{ Monitoring = @(
        @{ Name = "Dashboard"; Url = "http://localhost:3000" }
        @{ Name = "Logs";      Url = "http://localhost:5341" }
    )}
)
```

## Step 3: Set `Universal`

Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `ProcessCleanup` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too.

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

## Step 4: Reload and confirm the merge landed

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
$global:Configuration.BrowserGroups
$global:Configuration.Universal
Resolve-SwaggerBrowserGroup -Project "MyProject" -SkipDuplicateCheck
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

- [`Resolve-SwaggerBrowserGroup` in the Workflow module reference](../../../modules/workflow.md#resolve-swaggerbrowsergroup) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Test-BrowserGroupAlreadyOpen`](../application/Test-BrowserGroupAlreadyOpen.md) - reads the same configuration
- [`Open-Browser`](../application/Open-Browser.md) - reads the same configuration
- [`Add-BrowserGroup`](../configuration/Add-BrowserGroup.md) - reads the same configuration
- [`Get-SwaggerCloseTitlePatterns`](Get-SwaggerCloseTitlePatterns.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
