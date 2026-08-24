# Rename-Machine

Sets the machine hostname from `Configuration.psd1` or interactively prompts for a new name.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping) | hashtable of hostname to machine type | `@{ Test = "Test" }` | How `DetermineMachineType` turns this computer name into a machine type. A hostname that is not listed falls back to `DefaultMachineType`. |

## Decisions

1. What is this machine hostname, and which machine type should it map to?
    - Options: Hostname to machine type. The machine type must be in `ValidMachineTypes`. [Add New Machine](../bootstrap/add-new-machine.md) walks the whole set of keys a new type needs.
    - Default: Unmapped, so the machine resolves to `DefaultMachineType`.
    - More detail: [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping)
2. Do you have other machines to map now?
    - Options: One entry per hostname you own. Mapping several hostnames to the same type is normal.
    - Default: Just this machine.
    - More detail: [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `HostnameToMachineType`
2. Reload and confirm the merge landed

## Step 1: Set `HostnameToMachineType`

How `DetermineMachineType` turns this computer name into a machine type. A hostname that is not listed falls back to `DefaultMachineType`.

```powershell
HostnameToMachineType = @{
    Test             = "Test"
    "DESKTOP-GAMING" = "Machine"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.HostnameToMachineType
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.HostnameToMachineType
$global:Configuration.HostnameToMachineType
$env:COMPUTERNAME
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    HostnameToMachineType = @{
        Test             = "Test"
        "DESKTOP-GAMING" = "Machine"
    }
}
```

## Related

- [`Rename-Machine` in the System module reference](../../../modules/system.md#rename-machine) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`DetermineMachineType`](../bootstrap/DetermineMachineType.md) - reads the same configuration
- [`Load-PathConfiguration`](../bootstrap/Load-PathConfiguration.md) - reads the same configuration
- [`Configure-Taskbar`](Configure-Taskbar.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
