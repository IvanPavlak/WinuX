# Open-VSCodeWorkspace

Opens a VS Code multi-root workspace (`*.code-workspace`) from `PathTemplates.Projects.Self.VSCodeWorkspaces` (`<repo>\VSCode\Workspaces`).

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.Projects.Self.VSCodeWorkspaces`](../../configuration-reference.md#vs-code-workspaces-path) | path template | `{RepoRoot}\VSCode\Workspaces` | The folder the `.code-workspace` files are listed from (through `Get-VSCodeWorkspaceNames`) and opened from. Read from its expanded form, `$global:MachineSpecificPaths.Projects.Self.VSCodeWorkspaces`; an empty or missing folder is reported as an error. |

## Decisions

1. Where do your `.code-workspace` files live?
    - Options: Any directory path; placeholders such as `{RepoRoot}` and `{Dev}` expand. Leave it at the shipped template to keep the workspaces in the repository.
    - Default: `{RepoRoot}\VSCode\Workspaces`.
    - More detail: [`PathTemplates.Projects.Self.VSCodeWorkspaces`](../../configuration-reference.md#vs-code-workspaces-path)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PathTemplates.Projects.Self.VSCodeWorkspaces`
2. Reload and confirm the merge landed

## Step 1: Set `PathTemplates.Projects.Self.VSCodeWorkspaces`

The folder holding the `.code-workspace` files. Hashtables deep-merge, so setting only this key keeps the other `Projects.Self` paths. Expanded into `$global:MachineSpecificPaths.Projects.Self.VSCodeWorkspaces`.

```powershell
PathTemplates = @{
    Projects = @{
        Self = @{
            VSCodeWorkspaces = "{RepoRoot}\VSCode\Workspaces"
        }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.PathTemplates
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.PathTemplates
$global:MachineSpecificPaths.Projects.Self.VSCodeWorkspaces
Get-VSCodeWorkspaceNames
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        Projects = @{
            Self = @{
                VSCodeWorkspaces = "{RepoRoot}\VSCode\Workspaces"
            }
        }
    }
}
```

## Related

- [`Open-VSCodeWorkspace` in the Application module reference](../../../modules/application.md#open-vscodeworkspace) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Get-VSCodeWorkspaceNames`](Get-VSCodeWorkspaceNames.md) - reads the same configuration
- [`Open-Workspace`](../workflow/Open-Workspace.md) - reroutes its `Open-VSCode` action here when a `-VSCodeWorkspace` override is active
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
