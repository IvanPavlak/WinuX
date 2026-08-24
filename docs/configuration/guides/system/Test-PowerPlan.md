# Test-PowerPlan

Checks whether the active power plan is set to the optimal performance mode for the current machine type.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`LaptopChassisTypes`](../../configuration-reference.md#more-sections-quick-reference) | array of integers | array of 8 | The WMI chassis type codes `Test-PowerPlan` treats as "this is a laptop", which is what decides whether battery-related power settings apply. |

## Decisions

1. Is this machine chassis type recognised correctly?
    - Options: Add the code `Get-CimInstance Win32_SystemEnclosure` reports, if it is missing. Supply the whole array.
    - Default: The shipped eight codes, which cover mainstream laptops and tablets.
    - More detail: [`LaptopChassisTypes`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `LaptopChassisTypes` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `LaptopChassisTypes`
2. Reload and confirm the merge landed

## Step 1: Set `LaptopChassisTypes`

The WMI chassis type codes `Test-PowerPlan` treats as "this is a laptop", which is what decides whether battery-related power settings apply.

```powershell
LaptopChassisTypes = @(8, 9, 10, 11, 14, 30, 31, 32)
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.LaptopChassisTypes
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.LaptopChassisTypes
Test-PowerPlan
Get-CimInstance Win32_SystemEnclosure | Select-Object ChassisTypes
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    LaptopChassisTypes = @(8, 9, 10, 11, 14, 30, 31, 32)
}
```

## Related

- [`Test-PowerPlan` in the System module reference](../../../modules/system.md#test-powerplan) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
