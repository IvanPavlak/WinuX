# Unpin-TaskbarApps

Clears all taskbar pins and applies an XML layout policy that prevents further taskbar modifications.

> [!NOTE]
> An existing **real** taskbar layout XML (which may encode your own hand-pinned arrangement) is copied into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/System/TaskbarLayout/<timestamp>/`) before the empty layout replaces it; if the backup cannot be taken the write is skipped.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.TaskbarLayoutFile`](../../configuration-reference.md#path-templates--placeholder-system) | string (path) | `"C:\ProgramData\provisioning\taskbar_layout.xml"` | Where the empty layout XML is written and what the `StartLayoutFile` policy is pointed at (read from `$global:MachineSpecificPaths.TaskbarLayoutFile`). Machine-local, never versioned. Empty makes the function log an error and stop after clearing the pins. |

## Decisions

1. Should the taskbar layout file live somewhere other than the shipped location?
    - Options: Override `PathTemplates.TaskbarLayoutFile` with an absolute path. Its folder is created when missing. Keep it the same path `Configure-Taskbar` uses, since both functions own the same `StartLayoutFile` policy.
    - Default: `C:\ProgramData\provisioning\taskbar_layout.xml`. Almost never needs changing.
    - More detail: [`PathTemplates.TaskbarLayoutFile`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PathTemplates.TaskbarLayoutFile` (only if needed)
2. Reload and confirm the merge landed

## Step 1: Set `PathTemplates.TaskbarLayoutFile` (only if needed)

Ships with a working value. `PathTemplates` is a hashtable, so this single key merges over the base and everything else stays as shipped.

```powershell
PathTemplates = @{
    TaskbarLayoutFile = "C:\ProgramData\provisioning\taskbar_layout.xml"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:MachineSpecificPaths` after a reload is the expanded ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.TaskbarLayoutFile
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.TaskbarLayoutFile
Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -ErrorAction SilentlyContinue | Select-Object StartLayoutFile, LockedStartLayout
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        TaskbarLayoutFile = "C:\ProgramData\provisioning\taskbar_layout.xml"
    }
}
```

## Related

- [`Unpin-TaskbarApps` in the System module reference](../../../modules/system.md#unpin-taskbarapps) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [`Configure-Taskbar`](Configure-Taskbar.md) - reads the same configuration
- [Backups](../../../reference/backups.md) - where a replaced layout file is kept
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
