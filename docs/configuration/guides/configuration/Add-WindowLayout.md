# Add-WindowLayout

Creates a new window layout `.psd1` template file for a workspace under `Window/Layouts/{MachineType}/`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).
>
> Direction: **writes** configuration. This function edits `Configuration.psd1` in place rather than reading it, so the "Where to Put Values" section below describes what it produces, not what you type by hand. The `-Simple` configuration write first copies the file into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/Config/Configuration/<timestamp>/`) as a one-click undo; a write whose backup cannot be taken is aborted.

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`SimpleLayoutWorkspaces`](../../configuration-reference.md#workspace-layouts) | array of workspace names | `@("Fullscreen", "Empty")` | Workspaces that use a single simple layout instead of a per-machine `<Workspace>_<MachineType>.psd1` file. `Set-WorkspaceWindowLayout` and `Add-WindowLayout` both consult it. |

## Decisions

1. Which workspaces need only a simple layout?
    - Options: One name per workspace. The array replaces wholesale.
    - Default: `Fullscreen` and `Empty`.
    - More detail: [`SimpleLayoutWorkspaces`](../../configuration-reference.md#workspace-layouts)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `SimpleLayoutWorkspaces` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `SimpleLayoutWorkspaces`
2. Reload and confirm the merge landed

## Step 1: Set `SimpleLayoutWorkspaces`

Workspaces that use a single simple layout instead of a per-machine `<Workspace>_<MachineType>.psd1` file. `Set-WorkspaceWindowLayout` and `Add-WindowLayout` both consult it.

```powershell
SimpleLayoutWorkspaces = @("Fullscreen", "Empty", "MyScratch")
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.SimpleLayoutWorkspaces
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.SimpleLayoutWorkspaces
$global:Configuration.SimpleLayoutWorkspaces
Visualize-Layouts
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    SimpleLayoutWorkspaces = @("Fullscreen", "Empty", "MyScratch")
}
```

## Related

- [`Add-WindowLayout` in the Configuration module reference](../../../modules/configuration.md#add-windowlayout) - parameters, usage and behaviour
- [Configuration configuration guides](README.md) - every guide for this module
- [`Set-WorkspaceWindowLayout`](../window/Set-WorkspaceWindowLayout.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
