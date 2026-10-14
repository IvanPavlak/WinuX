# Open-ProjectTerminals

Opens project-specific Windows Terminal tabs based on `Configuration.ProjectTerminals`, with automatic tab naming (`ProjectName.PathKey`, e.g. `MyProject.API`).

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set. |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Name; BasePath; Paths }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project: one tab per `Paths` entry, titled `<Name>.<Key>`, starting in that path under `BasePath` (or a WSL / plain / explicit-path tab for the special entries). Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |
| [`TerminalGreeting.Onefetch.InProjectTerminals`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias) | bool | `$true` | Whether each path tab runs `Invoke-Onefetch` after its `Set-Location`. An explicit `-InvokeOnefetch` on the call wins. |

## Decisions

1. Which WSL distribution should WinuX use?
    - Options: A distribution name as `wsl -l -q` prints it, e.g. `Ubuntu`. Leave empty to keep every WSL feature switched off.
    - Default: Empty - every WSL path no-ops.
    - More detail: [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration)
2. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL - a WSL tab written as `@{ Key = "WSL"; Path = "/mnt/c/Users/Me/Repo" }` starts in that directory instead of the distribution's home, with the path written as WSL sees it. `Run-Project` reads the same list, so these are the tabs `rp` opens too.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
3. Should every project tab show the onefetch repository panel?
    - Options: `$true` appends `Invoke-Onefetch` to each path tab (it still obeys `TerminalGreeting.Onefetch.Enabled` and skips non-repositories); `$false` leaves project tabs plain while `c` keeps the panel.
    - Default: `$true`.
    - More detail: [`TerminalGreeting`](../../configuration-reference.md#terminal-greeting-startup-and-the-c-alias)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals` - that key is an array, so whatever you write is the complete value. `TerminalGreeting` is a hashtable and deep-merges, so `@{ Onefetch = @{ InProjectTerminals = $false } }` changes that one flag only.

## Steps Overview

1. Set `DefaultWSLDistribution`
2. Set `ProjectTerminals`
3. Set `TerminalGreeting.Onefetch.InProjectTerminals`
4. Reload and confirm the merge landed

## Step 1: Set `DefaultWSLDistribution`

The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set.

```powershell
DefaultWSLDistribution = "Ubuntu"
```

## Step 2: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project. `Name` is the project name, `BasePath` a dot-notation reference into the expanded paths (not a literal folder), and every `Paths` entry is one tab titled `<Name>.<Key>`: a subpath key under `BasePath`, `"ROOT"`, `"DEFAULT"` (plain tab), `"WSL"`, `@{ Key = "WSL"; Path = "/mnt/c/..." }`, `@{ Key = "Logs"; Path = "C:\Logs" }` or `@{ Key = "Shell" }`. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable.

```powershell
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI", "WSL") }
)
```

## Step 3: Set `TerminalGreeting.Onefetch.InProjectTerminals`

Whether each path tab appends `Invoke-Onefetch` after its `Set-Location`. Ships `$true`; an explicit `-InvokeOnefetch` on the call wins.

```powershell
TerminalGreeting = @{
    Onefetch = @{
        InProjectTerminals = $false
    }
}
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWSLDistribution
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWSLDistribution
$global:Configuration.ProjectTerminals
$global:Configuration.ProjectTerminals | ConvertTo-Json -Depth 4
$global:Configuration.TerminalGreeting.Onefetch.InProjectTerminals
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    ProjectTerminals = @(
        @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("API", "UI", "WSL") }
    )
    TerminalGreeting = @{
        Onefetch = @{
            InProjectTerminals = $false
        }
    }
}
```

## Related

- [`Open-ProjectTerminals` in the Workflow module reference](../../../modules/workflow.md#open-projectterminals) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [`Open-WSLTab`](../application/Open-WSLTab.md) - reads the same configuration
- [`Test-WSLDistributionInstalled`](../helper/Test-WSLDistributionInstalled.md) - reads the same configuration
- [`Configure-WSL`](../system/Configure-WSL.md) - reads the same configuration
- [`Configure-WSLSSH`](../system/Configure-WSLSSH.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
