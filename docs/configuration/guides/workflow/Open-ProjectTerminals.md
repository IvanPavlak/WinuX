# Open-ProjectTerminals

Opens project-specific Windows Terminal tabs based on `Configuration.ProjectTerminals`, with automatic tab naming (`ProjectName.PathKey`, e.g.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration) | string | empty string | The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set. |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Project; Tabs; ... }` | array of 3 | Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable. |

## Decisions

1. Which WSL distribution should WinuX use?
    - Options: A distribution name as `wsl -l -q` prints it, e.g. `Ubuntu`. Leave empty to keep every WSL feature switched off.
    - Default: Empty - every WSL path no-ops.
    - More detail: [`DefaultWSLDistribution`](../../configuration-reference.md#wsl-configuration)
2. Which terminal tabs should open for this project?
    - Options: One entry per project with its tab list. Each tab can set a title and a starting directory, and can run in WSL.
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `DefaultWSLDistribution`
2. Set `ProjectTerminals`
3. Reload and confirm the merge landed

## Step 1: Set `DefaultWSLDistribution`

The WSL distribution every WSL-touching function uses. Ships empty, and that is deliberate: `Configure-WSL`, `Initialize-WSLEnvironment`, `Configure-WSLSSH`, `Open-WSLTab`, `Deploy-CoreAiRules` and WSL symlinks all no-op until it is set.

```powershell
DefaultWSLDistribution = "Ubuntu"
```

## Step 2: Set `ProjectTerminals`

Which Windows Terminal tabs `Open-ProjectTerminals` creates for a project, and with what titles and starting directories. Tabs are created with `--title --suppressApplicationTitle`, so their titles are stable.

```powershell
ProjectTerminals = @(
    @{ Project = "MyProject"; Tabs = @(
        @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
    )}
)
```

## Step 3: Reload and confirm the merge landed

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
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWSLDistribution = "Ubuntu"
    ProjectTerminals = @(
        @{ Project = "MyProject"; Tabs = @(
            @{ Title = "MyProject"; Path = "{Dev}\MyProject" }
        )}
    )
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
