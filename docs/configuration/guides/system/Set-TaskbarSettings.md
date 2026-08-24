# Set-TaskbarSettings

Applies the Settings > Personalisation > Taskbar page from the `TaskbarSettings` section in the configuration - the programmatic equivalent of walking that page top to bottom.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`TaskbarSettings`](../../configuration-reference.md#taskbar-settings) | hashtable of setting name to value | `@{}` (empty) | Taskbar behaviour `Set-TaskbarSettings` writes to the registry - alignment, search box, widgets, task view. Ships empty. |

## Decisions

1. Which taskbar settings should WinuX enforce?
    - Options: Setting name to value. See the configuration reference for the recognised names.
    - Default: Empty - `Set-TaskbarSettings` no-ops.
    - More detail: [`TaskbarSettings`](../../configuration-reference.md#taskbar-settings)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `TaskbarSettings`
2. Reload and confirm the merge landed

## Step 1: Set `TaskbarSettings`

Taskbar behaviour `Set-TaskbarSettings` writes to the registry - alignment, search box, widgets, task view. Ships empty.

```powershell
TaskbarSettings = @{
    TaskbarAlignment = "Left"
    ShowSearchBox    = $false
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.TaskbarSettings
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.TaskbarSettings
$global:Configuration.TaskbarSettings
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    TaskbarSettings = @{
        TaskbarAlignment = "Left"
        ShowSearchBox    = $false
    }
}
```

## Related

- [`Set-TaskbarSettings` in the System module reference](../../../modules/system.md#set-taskbarsettings) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
