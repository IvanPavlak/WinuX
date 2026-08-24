# Resolve-ProjectPath

Resolves a project's file paths from the configuration mappings.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Project; Tabs; ... }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array of single-key hashtables | array of 1 | The repository groups `Update-Repositories` walks and `Initialize-Repository` can clone into. Group name to an array of repository entries. |
| [`Universal`](../../configuration-reference.md#universal-constants) | hashtable, 26 keys | hashtable, 26 keys | Machine-independent constants: executable paths (`FirefoxExe`, `DockerExe`, `DbeaverExe`, ...), the `Browsers` map, `DefaultBrowser`, shared URLs, the `ProcessCleanup` lists, and `Desktop` (auto-resolved at load). Expanded in place by `Load-PathConfiguration`, so placeholders work here too. |

## Decisions

1. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
2. Which repository groups do you want to manage?
    - Options: One group per collection, e.g. `Personal`, `Work`. Each entry carries the repository name and its remote - see [Add New Repository](../git/add-new-repository.md).
    - Default: The shipped single example group.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
3. Where should each group be cloned to?
    - Options: A path per group, normally under `{Dev}`.
    - Default: The shipped path.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
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

On this page that bites on `ProjectTerminals`, `RepositoryGroups` - those keys are arrays, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectTerminals`
2. Set `RepositoryGroups`
3. Set `Universal`
4. Reload and confirm the merge landed

## Step 1: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable.

```powershell
ProjectTerminals = @(
    @{ Project = "MyProject"; Tabs = @(
        @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
    )}
)
```

## Step 2: Set `RepositoryGroups`

The repository groups `Update-Repositories` walks and `Initialize-Repository` can clone into. Group name to an array of repository entries.

```powershell
RepositoryGroups = @(
    @{ Personal = @(
        @{ Name = "MyRepo"; Url = "https://github.com/YourUsername/MyRepo.git" }
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
$global:Configuration.ProjectTerminals
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectTerminals
$global:Configuration.RepositoryGroups
$global:Configuration.Universal
Resolve-ProjectPath -ProjectName "MyProject"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectTerminals = @(
        @{ Project = "MyProject"; Tabs = @(
            @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
        )}
    )
    RepositoryGroups = @(
        @{ Personal = @(
            @{ Name = "MyRepo"; Url = "https://github.com/YourUsername/MyRepo.git" }
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

- [`Resolve-ProjectPath` in the Helper module reference](../../../modules/helper.md#resolve-projectpath) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Run-Project`](Run-Project.md) - reads the same configuration
- [`Open-ProjectTerminals`](../workflow/Open-ProjectTerminals.md) - reads the same configuration
- [`Open-Workspace`](../workflow/Open-Workspace.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
