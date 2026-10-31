# Set-PowerPlan

Sets the Windows power plan to Balanced, HighPerformance, or UltimatePerformance.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PowerPlans`](../../configuration-reference.md#power-plans) | hashtable of machine type to plan mode | `@{}` (empty) | The plan `Set-PowerPlan -Auto` activates on each machine type: `Balanced`, `HighPerformance` or `UltimatePerformance`. Ships empty. |
| [`PowerTimeouts`](../../configuration-reference.md#power-timeouts) | hashtable of machine type to timeouts | `@{}` (empty) | The sleep, hibernate and display timeouts `-Auto` writes into every power scheme, in minutes (`0` = never): `SleepPluggedIn`, `SleepOnBattery`, `HibernatePluggedIn`, `HibernateOnBattery`, `DisplayPluggedIn`, `DisplayOnBattery`. A key left out is not managed. Ships empty. |

## Decisions

1. Which power plan should each machine type run?
    - Options: Machine type to one of `Balanced`, `HighPerformance`, `UltimatePerformance` (the hidden Ultimate Performance scheme is duplicated on first use). No GUIDs - the function maps the mode name to the scheme itself.
    - Default: Empty - `Set-PowerPlan -Auto` warns and leaves the active plan as-is.
    - More detail: [`PowerPlans`](../../configuration-reference.md#power-plans)
2. Should a machine type stay awake on mains power (it runs unattended jobs), or change any sleep or display timeout?
    - Options: `PowerTimeouts` per machine type: `SleepPluggedIn = 0; HibernatePluggedIn = 0` keeps it awake on mains power while the display still turns off on its own timeout; any of the six keys in minutes.
    - Default: Empty - no timeout is changed.
    - More detail: [`PowerTimeouts`](../../configuration-reference.md#power-timeouts)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PowerPlans`
2. Set `PowerTimeouts`
3. Reload and confirm the merge landed

## Step 1: Set `PowerPlans`

The plan `Set-PowerPlan -Auto` activates on each machine type. Ships empty.

```powershell
PowerPlans = @{
    Machine = "UltimatePerformance"
    Laptop  = "HighPerformance"
}
```

## Step 2: Set `PowerTimeouts`

The timeouts `Set-PowerPlan -Auto` writes into every power scheme of each machine type. Ships empty.

```powershell
PowerTimeouts = @{
    Machine = @{ SleepPluggedIn = 0; HibernatePluggedIn = 0 }
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.PowerPlans
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.PowerPlans
$global:Configuration.PowerTimeouts
powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PowerPlans    = @{
        Machine = "UltimatePerformance"
        Laptop  = "HighPerformance"
    }
    PowerTimeouts = @{
        Machine = @{ SleepPluggedIn = 0; HibernatePluggedIn = 0 }
    }
}
```

## Related

- [`Set-PowerPlan` in the System module reference](../../../modules/system.md#set-powerplan) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
