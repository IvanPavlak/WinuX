# Get-LayoutMachineType

Resolves the machine type whose window-arrangement settings apply to the current display setup, in order: a non-empty `LayoutMachineTypeOverrides` entry for the detected machine type, else `SmallDisplayMachineType` when `Test-SmallPrimaryDisplay` reports a laptop-class primary display, else the detected type from `DetermineMachineType`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides) | hashtable of machine type to layout set name | `@{ Test = "" }` | Lets a machine use another machine layout set - for example a laptop docked to a different monitor arrangement. `Get-LayoutMachineType` resolves it, so layouts and the reset target can never disagree. An override name is not a machine type: it needs no `ValidMachineTypes` entry and no base paths, only `<Workspace>_<Name>.psd1` layout files. |
| [`SmallDisplayMachineType`](../../configuration-reference.md#layout-set-overrides) | string | empty string | Which layout machine type counts as the small-display profile, used by `Get-LayoutMachineType` and the display-aware sizing helpers. |

## Decisions

1. Should this machine use another machine layout files?
    - Options: Machine type to override name. Empty means use the machine own type.
    - Default: Empty - no override.
    - More detail: [`LayoutMachineTypeOverrides`](../../configuration-reference.md#layout-set-overrides)
2. Do you have a small-display machine type?
    - Options: A machine type or layout override name. Empty means no machine is treated as small.
    - Default: Empty.
    - More detail: [`SmallDisplayMachineType`](../../configuration-reference.md#layout-set-overrides)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `LayoutMachineTypeOverrides`
2. Set `SmallDisplayMachineType`
3. Reload and confirm the merge landed

## Step 1: Set `LayoutMachineTypeOverrides`

Lets a machine use another machine layout set - for example a laptop docked to a different monitor arrangement. `Get-LayoutMachineType` resolves it, so layouts and the reset target can never disagree. An override name is not a machine type: it needs no `ValidMachineTypes` entry and no base paths, only `<Workspace>_<Name>.psd1` layout files.

```powershell
LayoutMachineTypeOverrides = @{
    Test = "Docked"
}
```

## Step 2: Set `SmallDisplayMachineType`

Which layout machine type counts as the small-display profile, used by `Get-LayoutMachineType` and the display-aware sizing helpers.

```powershell
SmallDisplayMachineType = "Laptop"
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.LayoutMachineTypeOverrides
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.LayoutMachineTypeOverrides
$global:Configuration.SmallDisplayMachineType
Get-LayoutMachineType
$global:Configuration.LayoutMachineTypeOverrides
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    LayoutMachineTypeOverrides = @{
        Test = "Docked"
    }
    SmallDisplayMachineType = "Laptop"
}
```

## Related

- [`Get-LayoutMachineType` in the Window module reference](../../../modules/window.md#get-layoutmachinetype) - parameters, usage and behaviour
- [Window configuration guides](README.md) - every guide for this module
- [Configure Window Layout](configure-window-layout.md) - the 3-layer layout system, zones and visualization
- [`Set-WorkspaceWindowLayout`](Set-WorkspaceWindowLayout.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
