# Resolve-ProjectTerminalTab

Reads one `ProjectTerminals` path entry into the tab it describes - the single reader both `Open-ProjectTerminals` and `Run-Project` use, so `op` and `rp` always open the same tabs.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Name; BasePath; Paths }` | array of 3 | Which Windows Terminal tabs a project gets, and where each one starts. Every entry in `Paths` is read by this function. |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution every WSL-touching function uses. A `WSL` tab carries it, and both project flows skip the tab entirely while it is empty. |

## Decisions

1. Which tabs should a project open, and in what shape?
    - Options: `"ROOT"` or another path key under the project's `BasePath`; `"DEFAULT"` for a plain shell; `"WSL"` for a tab on the WSL distribution; `@{ Key = "WSL"; Path = "/mnt/c/Users/Me/Repo" }` for a WSL tab started inside the project; `@{ Key = "Name"; Path = "C:\path" }` for an explicit Windows path; `@{ Key = "Name" }` for a plain tab with a custom title.
    - Default: The shipped three entries, all plain path keys.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
2. Which WSL distribution should a `WSL` tab open?
    - Options: A distribution name as `wsl -l -q` prints it, e.g. `Ubuntu`. Leave empty to keep every WSL feature switched off - a `WSL` entry is then skipped with a warning instead of opening a tab.
    - Default: Empty - every WSL path no-ops.
    - More detail: [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectTerminals`
2. Set `DefaultWSLDistribution`
3. Reload and confirm the merge landed

## Step 1: Set `ProjectTerminals`

Which tabs a project gets. A string entry names a path key under the project's `BasePath` (`ROOT` is the project root); a hashtable entry gives the tab an explicit path or just a name.

```powershell
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("ROOT", @{ Key = "WSL"; Path = "/mnt/c/Users/Me/Development/MyProject" }) }
)
```

A WSL path is written as WSL sees it - `/mnt/c/...` for a Windows-mounted repository, `/home/...` for a native clone - and is passed through untranslated, because it is handed to `wsl --cd` and never to `Set-Location`.

## Step 2: Set `DefaultWSLDistribution`

The distribution a `WSL` tab opens on. Ships empty, and while it is empty a `WSL` entry is skipped with a warning and the project's other tabs open as usual.

```powershell
DefaultWSLDistribution = "Ubuntu"
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectTerminals
```

## Verification

Read-only checks. None of these change anything - the function resolves an entry, it does not open anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWSLDistribution
$global:Configuration.ProjectTerminals

# What each configured entry of a project resolves to
$mapping = $global:Configuration.ProjectTerminals | Where-Object { $_.Name -eq "MyProject" }
$mapping.Paths | ForEach-Object { Resolve-ProjectTerminalTab -ProjectName "MyProject" -PathEntry $_ } | Format-Table Key, Kind, Path, Distribution
```

A tab that reads back as `Kind = Path` with an empty `Path` is a path key with no matching entry under the project's `BasePath`; a `WSL` tab with an empty `Distribution` means `DefaultWSLDistribution` is not set.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    ProjectTerminals       = @(
        @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("ROOT", @{ Key = "WSL"; Path = "/mnt/c/Users/Me/Development/MyProject" }) }
    )
}
```

## Related

- [`Resolve-ProjectTerminalTab` in the Helper module reference](../../../modules/helper.md#resolve-projectterminaltab) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Run-Project`](Run-Project.md) - reads the same configuration
- [`Resolve-ProjectPath`](Resolve-ProjectPath.md) - resolves the path keys this function hands it
- [`Open-ProjectTerminals`](../workflow/Open-ProjectTerminals.md) - reads the same configuration
- [`Open-WSLTab`](../application/Open-WSLTab.md) - opens the WSL tabs this function describes
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
